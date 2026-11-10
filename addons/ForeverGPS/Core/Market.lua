-- Prices, from this character's own auction house and merchants, and nowhere else.
--
-- The full scan follows CraftProfit's AHAdapter.lua (https://github.com/Renaud-Sto/CraftProfit,
-- commit 79e8eda, MIT License, Copyright (c) 2026 Sto, Licenses/CraftProfit-LICENSE.txt), whose
-- rules were measured in the WoW Forever client (third_party/CraftProfit/docs/probe-findings.md):
--   - REPLICATE_ITEM_LIST_UPDATE fires hundreds of times for one scan (F2), so the listing is
--     read once the events stop, and events just after a read are the same scan;
--   - a row's buyout is the whole stack's (F2), so a unit costs buyout / count;
--   - every read is guarded, so a failing one can never leave a scan stuck, and closing the
--     window ends the scan by a token, so nothing late lands in the wrong one.
-- Rewritten here in Forever-GPS's style, with these additions: the read also waits for the
-- row count to stop growing; a scan with no answer in 30 seconds, or still arriving after
-- 60, ends with a reason; rows that arrive during the read are read once more; and the
-- cheapest price tiers are kept, so a quantity can be priced (Core/Quote.lua).
--
-- A full scan is only ever started by the player's click, and the server allows one about
-- every 15 minutes. One started by another addon is read too, and counts for the wait.
--
-- Each auction house is its own market: realm, then the side's house or the neutral one,
-- told by the map the player is on (a number, so any language), and by the zone's name
-- only when the map cannot say. Nothing is bought, bid on or posted.
local FG = ForeverGPS
local Market = {}
FG.Market = Market

local L = FG.L

local SCAN_COOLDOWN = 15 * 60
local ASK_AGAIN = 60            -- after a scan with no answer, before asking again
local NO_ANSWER, QUIET, SETTLE_MOST, REREAD_QUIET = 30, 1, 60, 10
local SLICE_MS, CHECK_EVERY = 4, 50
local FRESH, RECENT = 3600, 3 * 86400
local LADDER = 10               -- price tiers kept per item
Market.NO_ANSWER, Market.QUIET, Market.SETTLE_MOST, Market.LADDER = NO_ANSWER, QUIET, SETTLE_MOST, LADDER
-- Neutral houses by map: Stranglethorn Vale (Booty Bay), Tanaris (Gadgetzan), Winterspring
-- (Everlook). Each of these maps has no other auction house.
local NEUTRAL_MAPS = { [1434] = true, [1446] = true, [1452] = true }
local NEUTRAL_TOWNS = { ["Booty Bay"] = true, ["Gadgetzan"] = true, ["Everlook"] = true }

local scan = { state = "idle" }      -- idle, waiting, settling, reading, done, failed
local open = false
local token = 0
local lastRead, lastAsk

local function DB()
    FG.db.market = FG.db.market or { houses = {}, vendor = {} }
    FG.db.market.houses = FG.db.market.houses or {}
    FG.db.market.vendor = FG.db.market.vendor or {}
    return FG.db.market
end

local function Secret(v) return issecretvalue ~= nil and issecretvalue(v) == true end

-- Which house this is: realm, and the side's house or the neutral one. how: "map" or "zone".
function Market.Key()
    local realm = GetRealmName and GetRealmName() or "?"
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local neutral, how
    if map then
        neutral, how = NEUTRAL_MAPS[map] == true, "map"
    else
        neutral, how = NEUTRAL_TOWNS[GetMinimapZoneText and GetMinimapZoneText() or ""] == true, "zone"
    end
    local side = neutral and "Neutral" or (UnitFactionGroup("player") or "?")
    return realm .. ":" .. side, side, how
end

-- The house the player's prices are read from: the one last opened on this side.
function Market.Current()
    local db = DB()
    local key = db.current and db.current[UnitFactionGroup("player") or "?"]
    return key or (Market.Key())
end

local function House(key)
    local db = DB()
    db.houses[key] = db.houses[key] or { items = {} }
    return db.houses[key]
end
Market.House = House

-- ==== scanning ==============================================================

local driver = CreateFrame("Frame")

local function Finish(state, why)
    scan.state, scan.why, scan.ended = state, why, GetTime()
    driver:SetScript("OnUpdate", nil)
    FG.Metrics.Note("market scan " .. state .. (why and (": " .. why) or ""))
    FG.Emit("market:changed")
end

function Market.CanScan()
    if not open then return false, L["MARKET_CLOSED"] end
    if scan.state == "waiting" or scan.state == "settling" or scan.state == "reading" then
        return false, L["MARKET_SCANNING"]
    end
    local house = House(Market.Key())
    local now = time()
    local wait = house.askedAt and SCAN_COOLDOWN - (now - house.askedAt) or 0
    if lastAsk and scan.state == "failed" and scan.noAnswer then wait = math.max(0, ASK_AGAIN - (GetTime() - lastAsk)) end
    if wait > 0 then return false, L["MARKET_WAIT_FMT"]:format(FG.Format.Duration(wait) or "?"), wait end
    if not (C_AuctionHouse and C_AuctionHouse.ReplicateItems) then return false, L["MARKET_NO_API"] end
    return true
end

local Watch

-- Asks for every listing. Only from a click: never by itself.
function Market.Scan()
    local ok, why = Market.CanScan()
    if not ok then return false, why end
    token = token + 1
    scan = { state = "waiting", key = Market.Key(), asked = GetTime(), token = token, by = "you" }
    lastAsk = GetTime()
    if not pcall(C_AuctionHouse.ReplicateItems) then
        Finish("failed", L["MARKET_NO_API"])
        return false, L["MARKET_NO_API"]
    end
    driver:SetScript("OnUpdate", Watch)
    FG.Emit("market:changed")
    return true
end

local function Count()
    local ok, n = pcall(C_AuctionHouse.GetNumReplicateItems)
    if not ok or Secret(n) or type(n) ~= "number" then return nil end
    return n
end

local Read

-- While waiting for an answer, and while the answer still arrives: when to read, and when
-- to give up. Runs only during a scan.
function Watch()
    local now = GetTime()
    if not open then return Finish("failed", L["MARKET_CLOSED_MID"]) end
    if scan.state == "waiting" then
        if now - scan.asked > NO_ANSWER then
            scan.noAnswer = true
            return Finish("failed", L["MARKET_NO_ANSWER"])
        end
    elseif scan.state == "settling" then
        local n = Count()
        if n ~= scan.lastCount then scan.lastCount, scan.countAt = n, now end
        local quiet = now - scan.lastEvent >= QUIET and now - (scan.countAt or now) >= QUIET
        local tooLong = now - scan.firstEvent > SETTLE_MOST
        if (quiet and n and n > 0) or tooLong then
            scan.cut = tooLong and not quiet or nil
            Read()
        end
    end
end

-- The listings read into per-item price lists, a slice at a time.
function Read()
    local n = Count()
    if not n then return Finish("failed", L["MARKET_READ_FAILED"]) end
    -- No rows is not "nothing is for sale": never a reason to forget every price.
    if n == 0 then return Finish("failed", L["MARKET_EMPTY"]) end
    scan.state, scan.at, scan.total, scan.units, scan.passes = "reading", 0, n, {}, (scan.passes or 0) + 1
    local mine = scan.token
    local function Rows(first, last)
        local units = scan.units
        for i = first, last do
            local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = C_AuctionHouse.GetReplicateItemInfo(i)
            if not (Secret(count) or Secret(buyout) or Secret(itemID))
                and type(itemID) == "number" and type(buyout) == "number" and buyout > 0
                and type(count) == "number" and count > 0 then
                local list = units[itemID]
                if not list then
                    list = {}
                    units[itemID] = list
                end
                list[#list + 1] = math.floor(buyout / count)
                list[#list + 1] = count
            end
        end
    end
    driver:SetScript("OnUpdate", function()
        if mine ~= token or scan.token ~= mine or not open then return driver:SetScript("OnUpdate", nil) end
        local stop = debugprofilestop() + SLICE_MS
        FG.Metrics.Begin("marketScan")
        while scan.at < scan.total do
            local last = math.min(scan.at + CHECK_EVERY, scan.total)
            if not pcall(Rows, scan.at, last - 1) then
                FG.Metrics.End("marketScan")
                return Finish("failed", L["MARKET_READ_FAILED"])
            end
            scan.at = last
            if debugprofilestop() > stop then
                FG.Metrics.End("marketScan")
                return FG.Emit("market:changed")
            end
        end
        FG.Metrics.End("marketScan")
        -- Rows that came in while reading: read once more, from the start.
        local now = Count()
        if now and now > scan.total and scan.passes < 2 then return Read() end
        Market.Store(scan.key, scan.units, { partial = scan.cut, by = scan.by })
        lastRead = GetTime()
        Finish("done")
    end)
end

-- One item's listings boiled down: lowest unit buyout, the unit price under which a
-- quarter of the units sit, the units listed, and the cheapest tiers, as
-- "min:typical:units|unit*count,unit*count,...".
function Market.Pack(list)
    local tiers, total = {}, 0
    for i = 1, #list, 2 do
        tiers[#tiers + 1] = { list[i], list[i + 1] }
        total = total + list[i + 1]
    end
    table.sort(tiers, function(a, b) return a[1] < b[1] end)
    local quarter, seen, typical = total / 4, 0, tiers[1][1]
    for _, p in ipairs(tiers) do
        seen = seen + p[2]
        typical = p[1]
        if seen >= quarter then break end
    end
    local ladder, last = {}, nil
    for _, p in ipairs(tiers) do
        if last and last[1] == p[1] then
            last[2] = last[2] + p[2]
        elseif #ladder < LADDER then
            last = { p[1], p[2] }
            ladder[#ladder + 1] = last
        else
            break
        end
    end
    local parts = {}
    for i, p in ipairs(ladder) do parts[i] = p[1] .. "*" .. p[2] end
    return ("%d:%d:%d|%s"):format(tiers[1][1], typical, total, table.concat(parts, ","))
end

-- A scan's prices into its house. A whole scan replaces the house's prices; a partial one
-- (closed mid-read, or cut off) only updates the items it read, each with its own time.
function Market.Store(key, units, opts)
    opts = opts or {}
    local house = House(key)
    local now = time()
    local n = 0
    if opts.partial then
        house.fresh = house.fresh or {}
        for itemID, list in pairs(units) do
            house.items[itemID] = Market.Pack(list)
            house.fresh[itemID] = now
            n = n + 1
        end
        house.partialAt, house.partialSeen = now, opts.seen and opts.of and opts.seen / math.max(1, opts.of) or nil
    else
        local items = {}
        for itemID, list in pairs(units) do
            items[itemID] = Market.Pack(list)
            n = n + 1
        end
        house.items, house.scannedAt, house.count, house.fresh = items, now, n, nil
        house.partialAt, house.partialSeen = nil, nil
        house.by = opts.by
    end
    house.askedAt = house.askedAt or now
    local db = DB()
    db.current = db.current or {}
    db.current[UnitFactionGroup("player") or "?"] = key
    FG.Emit("market:prices", key)
    return n
end

function Market.Scanning() return scan end

FG.OnEvent("AUCTION_HOUSE_SHOW", function()
    open = true
    local key = Market.Key()
    local db = DB()
    db.current = db.current or {}
    db.current[UnitFactionGroup("player") or "?"] = key
    -- The auctioneer, so a house can be told by who keeps it as well as where.
    local npc = UnitGUID and UnitGUID("npc")
    local id = npc and tonumber((select(6, strsplit("-", npc))))
    if id then
        local house = House(key)
        house.npcs = house.npcs or {}
        house.npcs[id] = true
    end
    FG.Emit("market:changed")
end)
FG.OnEvent("AUCTION_HOUSE_CLOSED", function()
    open = false
    -- Ends any scan: whatever arrives late belongs to no scan.
    token = token + 1
    if scan.state == "reading" then
        -- Closed mid-read: what was read is kept beside the old prices, marked partial.
        if (scan.at or 0) > 0 then
            scan.kept = Market.Store(scan.key, scan.units, { partial = true, seen = scan.at, of = scan.total })
        end
        Finish("failed", L["MARKET_CLOSED_MID"])
    elseif scan.state == "waiting" or scan.state == "settling" then
        Finish("failed", L["MARKET_CLOSED_MID"])
    else
        FG.Emit("market:changed")
    end
end)
FG.OnEvent("REPLICATE_ITEM_LIST_UPDATE", function()
    local now = GetTime()
    -- The server's wait counts from any scan, ours or another addon's.
    if open then House(Market.Key()).askedAt = time() end
    if scan.state == "waiting" then
        scan.state, scan.firstEvent, scan.lastEvent = "settling", now, now
        return FG.Emit("market:changed")
    end
    if scan.state == "settling" then
        scan.lastEvent = now
        return
    end
    if scan.state == "reading" then return end
    -- Another addon's scan: read it as well, unless this is the tail of one just read.
    if open and not (lastRead and now - lastRead < REREAD_QUIET) then
        token = token + 1
        scan = { state = "settling", key = Market.Key(), asked = now, firstEvent = now, lastEvent = now,
                 token = token, by = "other" }
        driver:SetScript("OnUpdate", Watch)
        FG.Emit("market:changed")
    end
end)

-- ==== merchants =============================================================

-- What a merchant sells, and for how much, kept for every merchant seen.
function Market.LearnMerchant()
    if not (GetMerchantNumItems and GetMerchantItemInfo and GetMerchantItemID) then return 0 end
    local vendor = DB().vendor
    local n = 0
    for i = 1, GetMerchantNumItems() do
        local _, _, price, quantity, available = GetMerchantItemInfo(i)
        local id = GetMerchantItemID(i)
        -- Limited stock is not a price to plan on.
        if id and price and price > 0 and (available or -1) < 0 then
            vendor[id] = math.floor(price / math.max(1, quantity or 1))
            n = n + 1
        end
    end
    return n
end
FG.OnEvent("MERCHANT_SHOW", function() FG.After(0.2, Market.LearnMerchant) end)

-- ==== reading ===============================================================

local function Age(age)
    return age <= FRESH and "fresh" or age <= RECENT and "recent" or "stale"
end
Market.Age = Age

-- An item's price: { buy (cheapest unit), typical, units, ladder = { {unit, count}, ... },
-- age (seconds), sure ("fresh", "recent", "stale"), partial }, or nil when unknown.
function Market.Price(itemID, key)
    key = key or Market.Current()
    local house = DB().houses[key]
    local packed = house and house.items[itemID]
    if not packed then return nil end
    local low, typical, units, rest = packed:match("^(%d+):(%d+):(%d+)|?(.*)$")
    if not low then return nil end
    local ladder = {}
    for unit, count in (rest or ""):gmatch("(%d+)%*(%d+)") do ladder[#ladder + 1] = { tonumber(unit), tonumber(count) } end
    if #ladder == 0 then ladder[1] = { tonumber(low), tonumber(units) } end
    local at = house.fresh and house.fresh[itemID] or house.scannedAt or house.partialAt or 0
    local age = time() - at
    return { buy = tonumber(low), typical = tonumber(typical), units = tonumber(units), ladder = ladder, age = age,
             sure = Age(age), partial = house.fresh and house.fresh[itemID] and house.partialAt and true or nil }
end

-- What a merchant sells it for, when one has been seen to. listed: from the client's
-- data only, until a merchant is opened (the price may differ with reputation).
function Market.VendorBuy(itemID)
    local seen = DB().vendor[itemID]
    if seen then return seen, "seen" end
    local data = FG.RecipeData and FG.RecipeData.vendor[itemID]
    if data then return data, "listed" end
    return nil
end

-- What a merchant pays for it: the game's own figure.
function Market.VendorSell(itemID)
    if not GetItemInfo then return nil end
    local sell = select(11, GetItemInfo(itemID))
    return type(sell) == "number" and sell > 0 and sell or nil
end

-- The cheapest way to get one: a merchant's price, or the auction house's lowest.
-- Returns copper, where ("vendor"|"auction"), and the auction price record.
function Market.Cost(itemID)
    local vendor = Market.VendorBuy(itemID)
    local price = Market.Price(itemID)
    if vendor and (not price or vendor <= price.buy) then return vendor, "vendor", price end
    if price then return price.buy, "auction", price end
    return nil, nil, nil
end

-- A house's summary, for the Market page.
function Market.Summary(key)
    key = key or Market.Current()
    local house = DB().houses[key]
    local at = house and (house.scannedAt or house.partialAt)
    return { key = key, count = house and house.count or 0, at = at, open = open,
             sure = at and Age(time() - at) or nil, partial = house and house.partialAt and not house.scannedAt or nil,
             by = house and house.by }
end

function Market.IsOpen() return open end
