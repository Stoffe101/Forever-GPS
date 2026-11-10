-- The auction house, as the real client behaves (third_party/CraftProfit/docs/probe-findings.md):
-- a full scan's answer arrives as hundreds of events while its rows grow, searches can be
-- answered twice or throttled, and the window can close at any moment. Every case ends in
-- a state that says what happened; none leaves a scan running.
local T = require("support.t")
local Stack = require("support.stack")

local HERB, VIAL, GEAR = 900, 902, 4000

local function Start(opts)
    opts = opts or {}
    opts.mapID, opts.x, opts.y = opts.mapID or 1453, opts.x or 0.6, opts.y or 0.6
    if opts.ui == nil then opts.ui = false end
    opts.professions = opts.professions or { { name = "Alchemy", skill = 132, max = 150, line = 171 } }
    opts.recipes = opts.recipes or {}
    opts.auctions = opts.auctions or {
        { itemID = HERB, count = 10, buyout = 1000 },
        { itemID = HERB, count = 5, buyout = 750 },
        { itemID = VIAL, count = 20, buyout = 600 },
    }
    opts.merchant = opts.merchant or {}
    local c = Stack.new(opts)
    c:Advance(4)
    return c
end

local function Open(c) c:Fire("AUCTION_HOUSE_SHOW") end

local function State(c) return c.FG.Market.Scanning().state end

local function Settled(c, limit)
    return Stack.Until(c, function()
        local s = State(c)
        return s == "done" or s == "failed"
    end, limit or 120)
end

local function Many(n, itemID, unit)
    local list = {}
    for i = 1, n do list[i] = { itemID = itemID + (i % 50), count = 1 + i % 3, buyout = (unit or 100) * (1 + i % 3) } end
    return list
end

local tests = {}

-- ==== the full scan =========================================================

-- The answer arrives over three seconds of events with the rows growing; it is read once,
-- after they stop, and holds every row.
function tests.aScanArrivingInPieces_isReadOnceItIsAllThere()
    local c = Start({ auctions = Many(3000, 10000) })
    c.replicateSpread = 3
    Open(c)
    T.ok(c.FG.Market.Scan())
    local readAt, lastEvent
    c.FG.On("market:prices", function() readAt = c.now end)
    local fire = c.Fire
    c.Fire = function(self, event, ...)
        if event == "REPLICATE_ITEM_LIST_UPDATE" then lastEvent = self.now end
        return fire(self, event, ...)
    end
    T.ok(Settled(c), "the scan ends")
    c.Fire = fire
    T.eq(State(c), "done")
    T.ok(readAt >= lastEvent, "read after the last event")
    T.eq(c.FG.Market.Scanning().total, 3000, "every row")
    T.eq(c.FG.Market.Summary().count, 50)
end

function tests.aSilentServer_endsTheScanWithAReason()
    local c = Start()
    c.replicateSilent = true
    Open(c)
    T.ok(c.FG.Market.Scan())
    c:Advance(c.FG.Market.NO_ANSWER - 1)
    T.eq(State(c), "waiting", "still waiting before the limit")
    c:Advance(2)
    T.eq(State(c), "failed")
    T.eq(c.FG.Market.Scanning().why, c.FG.L["MARKET_NO_ANSWER"])
    T.no(c.FG.Market.CanScan(), "not asked again at once")
    c:Advance(61)
    c.replicateSilent = nil
    T.ok(c.FG.Market.CanScan(), "a minute later it may ask again: no answer, no server wait")
end

-- Events that never stop (another addon rescanning, a client fault): read after a minute,
-- marked partial, never stuck.
function tests.anAnswerThatNeverSettles_isCutOff()
    local c = Start({ auctions = Many(500, 10000) })
    Open(c)
    T.ok(c.FG.Market.Scan())
    local beat
    beat = function()
        if State(c) == "waiting" or State(c) == "settling" then
            c:Fire("REPLICATE_ITEM_LIST_UPDATE")
            c:After(0.3, beat)
        end
    end
    c:After(0.5, beat)
    T.ok(Settled(c, 120), "ended")
    T.eq(State(c), "done")
    T.ok(c.FG.Market.Scanning().cut, "said to be cut off")
    T.ok(c.FG.Market.Summary().partial, "the prices say partial")
end

function tests.closingMidRead_keepsWhatWasRead_asPartial()
    local c = Start()
    Open(c)
    T.ok(c.FG.Market.Scan())
    T.ok(Settled(c))
    local house = c.FG.db.market.houses[c.FG.Market.Key()]
    house.askedAt, house.scannedAt = house.askedAt - 3600, house.scannedAt - 3600
    T.eq(c.FG.Market.Price(VIAL).buy, 30)
    c.auctions = {}
    for i = 1, 30000 do c.auctions[i] = { itemID = HERB, count = 1, buyout = 50 } end
    c.auctions[30001] = { itemID = VIAL, count = 1, buyout = 5 }
    T.ok(c.FG.Market.Scan())
    T.ok(Stack.Until(c, function() return State(c) == "reading" and c.FG.Market.Scanning().at > 0 end, 20))
    c:Fire("AUCTION_HOUSE_CLOSED")
    T.eq(State(c), "failed", "ended, not left reading")
    c:Advance(2)
    T.eq(State(c), "failed", "and nothing late restarts it")
    local herb = c.FG.Market.Price(HERB)
    T.eq(herb.buy, 50, "what was read is kept")
    T.ok(herb.partial, "marked partial")
    T.eq(c.FG.Market.Price(VIAL).buy, 30, "what was not read keeps its older price")
end

function tests.rowsArrivingDuringTheRead_areReadToo()
    local c = Start({ auctions = Many(20000, 10000) })
    Open(c)
    T.ok(c.FG.Market.Scan())
    T.ok(Stack.Until(c, function() return State(c) == "reading" end, 20))
    for i = 1, 100 do c.auctions[#c.auctions + 1] = { itemID = 777, count = 1, buyout = 70 } end
    T.ok(Settled(c))
    T.eq(State(c), "done")
    T.eq(c.FG.Market.Price(777).buy, 70, "the late rows are in")
end

function tests.anotherAddonsScan_isReadToo_andCountsForTheWait()
    local c = Start()
    Open(c)
    c:Fire("REPLICATE_ITEM_LIST_UPDATE")
    T.ok(Settled(c))
    T.eq(State(c), "done")
    T.eq(c.FG.Market.Scanning().by, "other")
    T.eq(c.FG.Market.Price(HERB).buy, 100)
    T.no(c.FG.Market.CanScan(), "the server's wait counts from that scan")
    T.eq(c.replicated, nil, "nothing asked of the server")
end

function tests.eventsJustAfterARead_areTheSameScan()
    local c = Start()
    Open(c)
    T.ok(c.FG.Market.Scan())
    T.ok(Settled(c))
    c:Advance(2)
    c:Fire("REPLICATE_ITEM_LIST_UPDATE")
    c:Advance(3)
    T.eq(State(c), "done", "not read again")
end

function tests.anEmptyAnswer_forgetsNothing()
    local c = Start()
    Open(c)
    T.ok(c.FG.Market.Scan())
    T.ok(Settled(c))
    local house = c.FG.db.market.houses[c.FG.Market.Key()]
    house.askedAt = house.askedAt - 3600
    c.auctions = {}
    T.ok(c.FG.Market.Scan())
    T.ok(Settled(c, 120))
    T.eq(State(c), "failed")
    T.eq(c.FG.Market.Price(HERB).buy, 100, "the prices stand")
end

function tests.secretRows_areSkipped_notCounted()
    local c = Start()
    c.env.issecretvalue = function(v) return v == 750 end
    Open(c)
    T.ok(c.FG.Market.Scan())
    T.ok(Settled(c))
    T.eq(c.FG.Market.Price(HERB).units, 10, "the secret row is left out")
end

-- ==== price depth ===========================================================

function tests.theCheapestTiers_areKept()
    local c = Start()
    Open(c)
    T.ok(c.FG.Market.Scan())
    T.ok(Settled(c))
    local p = c.FG.Market.Price(HERB)
    T.eq(#p.ladder, 2)
    T.eq(p.ladder[1][1], 100)
    T.eq(p.ladder[1][2], 10)
    T.eq(p.ladder[2][1], 150)
    T.eq(p.ladder[2][2], 5)
end

function tests.aLadder_mergesEqualPrices_andStopsAtItsLength()
    local c = Start()
    local list = {}
    for i = 1, 40 do
        list[#list + 1] = 100 + i % 20
        list[#list + 1] = 2
    end
    local packed = c.FG.Market.Pack(list)
    local tiers = select(2, packed:gsub("%*", ""))
    T.eq(tiers, c.FG.Market.LADDER, "at most the ladder's length")
    T.ok(packed:find("^100:", 1), "lowest first")
    T.ok(packed:find("|100*4,", 1, true), "equal prices merged: " .. packed)
end

-- ==== markets ===============================================================

function tests.aNeutralHouse_isToldByTheMap_inAnyLanguage()
    local c = Start()
    c.env.GetMinimapZoneText = function() return "Bahía del Botín" end
    c:SetPlayer(1434, 0.27, 0.77)
    local _, side, how = c.FG.Market.Key()
    T.eq(side, "Neutral")
    T.eq(how, "map")
    c:SetPlayer(1453, 0.6, 0.6)
    T.eq(select(2, c.FG.Market.Key()), "Alliance")
end

function tests.withNoMap_theZoneNameIsTheFallback()
    local c = Start()
    c.env.C_Map.GetBestMapForUnit = function() return nil end
    c.env.GetMinimapZoneText = function() return "Everlook" end
    local _, side, how = c.FG.Market.Key()
    T.eq(side, "Neutral")
    T.eq(how, "zone")
end

-- ==== targeted searches =====================================================

function tests.searches_runOneAtATime_andStoreFreshPrices()
    local c = Start()
    Open(c)
    T.eq(c.FG.MarketSearch.Ask({ HERB, VIAL, HERB }), 2, "each item once")
    T.ok(Stack.Until(c, function() return c.FG.MarketSearch.Status().waiting == 0 and not c.FG.MarketSearch.Status().current end, 10))
    T.eq(#c.searches, 2)
    local p = c.FG.Market.Price(HERB)
    T.eq(p.buy, 100)
    T.eq(p.units, 15)
    T.eq(p.sure, "fresh")
    T.eq(c.FG.MarketSearch.Status().answered, 2)
end

function tests.aSecondIdenticalAnswer_isIgnored()
    local c = Start()
    c.searchTwice = true
    Open(c)
    c.FG.MarketSearch.Ask({ HERB, VIAL })
    T.ok(Stack.Until(c, function() return c.FG.MarketSearch.Status().answered == 2 end, 10))
    c:Advance(2)
    T.eq(c.FG.MarketSearch.Status().answered, 2, "not counted twice")
end

function tests.theThrottle_isWaitedFor()
    local c = Start()
    c.throttled = 3
    Open(c)
    c.FG.MarketSearch.Ask({ HERB })
    T.eq(#(c.searches or {}), 0, "not sent while the throttle says no")
    T.ok(Stack.Until(c, function() return c.FG.MarketSearch.Status().answered == 1 end, 10))
end

function tests.anUnansweredSearch_timesOut_andTheQueueGoesOn()
    local c = Start()
    c.searchSilent = true
    Open(c)
    c.FG.MarketSearch.Ask({ HERB, VIAL })
    c:Advance(c.FG.MarketSearch.TIMEOUT + 0.5)
    T.eq(c.FG.MarketSearch.Status().missed, 1)
    T.eq(c.FG.MarketSearch.Status().current, VIAL, "moved on")
    c:Advance(c.FG.MarketSearch.TIMEOUT + 0.5)
    T.eq(c.FG.MarketSearch.Status().missed, 2)
    T.eq(c.FG.MarketSearch.Status().current, nil, "nothing left running")
end

function tests.closing_endsTheQueue()
    local c = Start()
    c.searchDelay = 2
    Open(c)
    c.FG.MarketSearch.Ask({ HERB, VIAL })
    c:Advance(0.5)
    c:Fire("AUCTION_HOUSE_CLOSED")
    c:Advance(5)
    local s = c.FG.MarketSearch.Status()
    T.eq(s.waiting, 0)
    T.eq(s.current, nil)
    T.eq(s.answered, 0, "a late answer lands in no search")
end

function tests.gear_isAnsweredAsWholeAuctions()
    local c = Start({ auctions = { { itemID = GEAR, count = 1, buyout = 5000 }, { itemID = GEAR, count = 1, buyout = 4000 } } })
    c.gear = { [GEAR] = true }
    Open(c)
    c.FG.MarketSearch.Ask({ GEAR })
    T.ok(Stack.Until(c, function() return c.FG.MarketSearch.Status().answered == 1 end, 10))
    T.eq(c.FG.Market.Price(GEAR).buy, 4000)
end

function tests.nobodySelling_keepsTheOldPrice()
    local c = Start()
    Open(c)
    T.ok(c.FG.Market.Scan())
    T.ok(Settled(c))
    c.auctions = {}
    c.FG.MarketSearch.Ask({ HERB })
    T.ok(Stack.Until(c, function() return c.FG.MarketSearch.Status().empty == 1 end, 10))
    T.eq(c.FG.Market.Price(HERB).buy, 100, "the scan's price, with its own age")
end

-- ==== buying a quantity =====================================================

local function Ladder(c, tiers, units)
    return { buy = tiers[1][1], typical = tiers[1][1], units = units, ladder = tiers, sure = "fresh", age = 0 }
end

function tests.aQuote_buysCheapestFirst()
    local c = Start()
    local Q = c.FG.Quote
    local price = Ladder(c, { { 100, 10 }, { 150, 5 } }, 15)
    local q = Q.Buy(HERB, 12, { price = price })
    T.eq(q.cost, 10 * 100 + 2 * 150)
    T.eq(q.remaining, 0)
    q = Q.Buy(HERB, 20, { price = price })
    T.eq(q.bought, 15)
    T.eq(q.remaining, 5, "not enough listed")
    T.eq(q.cost, 1750)
end

function tests.aMerchantsPrice_isOneMoreTier()
    local c = Start({ merchant = { { id = HERB, price = 120 } } })
    c:Fire("MERCHANT_SHOW")
    c:Advance(0.5)
    local q = c.FG.Quote.Buy(HERB, 12, { price = Ladder(c, { { 100, 10 }, { 150, 5 } }, 15) })
    T.eq(q.cost, 10 * 100 + 2 * 120)
    T.eq(q.fromVendor, 2)
    T.eq(q.remaining, 0, "a merchant never runs out")
end

function tests.unknown_isNeverFree()
    local c = Start()
    local q = c.FG.Quote.Buy(123456, 5)
    T.eq(q.status, "unknown")
    T.eq(q.remaining, 5)
    local b = c.FG.Quote.Budget({ [123456] = 5, [HERB] = 0 })
    T.eq(b.unknown, 1)
    T.eq(b.uncovered, 1)
end

-- The covering knapsack against every subset of a few whole auctions.
function tests.wholeAuctions_matchEverySubsetChecked()
    local c = Start()
    local seed = 7
    local function rand(n)
        seed = (seed * 1103515245 + 12345) % 2147483648
        return seed % n
    end
    for _ = 1, 60 do
        local offers = {}
        for i = 1, 2 + rand(5) do offers[i] = { 5 + rand(20), 1 + rand(6) } end
        table.sort(offers, function(a, b) return a[1] < b[1] end)
        local units = 0
        for _, o in ipairs(offers) do units = units + o[2] end
        local want = 1 + rand(units)
        local best
        for mask = 1, 2 ^ #offers - 1 do
            local got, cost, m = 0, 0, mask
            for i = 1, #offers do
                if m % 2 == 1 then got, cost = got + offers[i][2], cost + offers[i][1] * offers[i][2] end
                m = math.floor(m / 2)
            end
            if got >= want and (not best or cost < best) then best = cost end
        end
        local q = c.FG.Quote.Buy(HERB, want, { whole = true, noVendor = true,
                                               price = { buy = offers[1][1], units = units, ladder = offers, sure = "fresh" } })
        T.eq(q.cost, best, "cheapest set of whole auctions")
        T.ok(q.bought >= want)
        T.eq(q.surplus, q.bought - want)
    end
end

return tests
