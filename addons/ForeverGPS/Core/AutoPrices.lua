-- Prices that keep themselves fresh: whenever the player opens an auction house, a full
-- scan is asked for when the server allows it and the prices are old enough, and while it
-- does not, the items that matter now are searched one by one instead. Nothing to press.
--
-- What the game allows, as seen: Auctionator, installed beside Forever-GPS in the user's
-- game, calls C_AuctionHouse.ReplicateItems by itself when the auction house opens (its
-- "autoscan"), and Forever-GPS 2.4 read one such scan there (5,534 items). The server
-- allows about one full scan in 15 minutes; Market.CanScan keeps to that.
--
-- Living with other addons: the ask waits AUTO_DELAY seconds after the window opens. A
-- scan another addon starts meanwhile is read instead (Core/Market.lua reads any scan), and
-- Auctionator's own record of its last scan, when it is installed, counts for the wait. At
-- most one full scan and one short queue of searches per visit; the searches stop as soon
-- as the player searches the auction house themself, and never buy, bid or post anything.
local FG = ForeverGPS
local Auto = {}
FG.AutoPrices = Auto

local L = FG.L

local AUTO_DELAY = 3
local TARGETED_MOST = 20
local TARGET_AGE = 3600          -- a price older than this is worth a search
local FRESHNESS = { permitted = 15 * 60, hour = 3600, day = 86400 }
Auto.AUTO_DELAY, Auto.TARGETED_MOST = AUTO_DELAY, TARGETED_MOST

local visit = 0
Auto.status = { last = nil, at = nil, why = nil, searched = 0 }

local function Settings()
    FG.db.prices = FG.db.prices or {}
    local s = FG.db.prices
    if s.auto == nil then s.auto = "permitted" end
    if s.targeted == nil then s.targeted = true end
    return s
end
Auto.Settings = Settings

local function Say(last, why, n)
    Auto.status.last, Auto.status.why, Auto.status.at = last, why, time()
    if n then Auto.status.searched = n end
    FG.Metrics.Note("auto prices: " .. last .. (why and (" (" .. why .. ")") or ""))
    FG.Emit("market:changed")
end

-- Another addon's full scan this recently: Auctionator keeps when it last asked.
local function OtherScannedAt()
    local a = _G["Auctionator"]
    local state = type(a) == "table" and type(a.SavedState) == "table" and a.SavedState or nil
    local t = state and state.TimeOfLastReplicateScan
    return type(t) == "number" and t or nil
end

-- The items worth a search now: what a list still needs, the current plan's reagents,
-- recipes' missing prices, and items with an alert. Only those with no price, or one
-- older than TARGET_AGE. At most TARGETED_MOST.
function Auto.Targets()
    local out, seen = {}, {}
    local function Add(id)
        if not id or seen[id] or #out >= TARGETED_MOST then return end
        seen[id] = true
        local p = FG.Market.Price(id)
        if not p or p.age > TARGET_AGE then out[#out + 1] = id end
    end
    for _, project in ipairs(FG.Crafting.Projects()) do
        local ok, shop = pcall(FG.Crafting.Shopping, project, true)
        for _, row in ipairs(ok and shop.rows or {}) do
            if row.left > 0 then Add(row.id) end
        end
    end
    for id in pairs(FG.db.alerts or {}) do Add(id) end
    for _, p in ipairs(FG.Professions.List()) do
        if not FG.Professions.IsGathering(p) then
            for _, id in ipairs(FG.Crafting.MissingPrices(p.line, TARGETED_MOST)) do Add(id) end
        end
    end
    return out
end

local function Targeted(why)
    if not Settings().targeted then return Say("waits", why) end
    local ids = Auto.Targets()
    if #ids == 0 then return Say("nothing to refresh", why) end
    local n = FG.MarketSearch.Ask(ids, { auto = true })
    Say("searches", why, n)
end

-- Decides, once the window has been open AUTO_DELAY seconds, what this visit asks for.
function Auto.Decide()
    local s = Settings()
    if s.auto == "off" then return Say("off") end
    if not FG.Market.IsOpen() then return end
    local scan = FG.Market.Scanning()
    if scan.state == "waiting" or scan.state == "settling" or scan.state == "reading" then
        return Say("another scan", scan.by == "other" and "other addon" or "running")
    end
    local house = FG.Market.House(FG.Market.Key())
    local last = math.max(house.scannedAt or 0, house.partialAt or 0)
    local age = time() - last
    if age < (FRESHNESS[s.auto] or FRESHNESS.permitted) then return Targeted("fresh") end
    local other = OtherScannedAt()
    if other and time() - other < FRESHNESS.permitted then return Targeted("other addon scanned") end
    local ok, why = FG.Market.CanScan()
    if not ok then return Targeted(why) end
    if FG.Market.Scan() then
        FG.Market.Scanning().auto = true
        return Say("full scan")
    end
    Targeted("refused")
end

FG.OnEvent("AUCTION_HOUSE_SHOW", function()
    visit = visit + 1
    local mine = visit
    FG.After(AUTO_DELAY, function()
        -- Closed and opened again meanwhile: that visit decides for itself.
        if mine == visit then Auto.Decide() end
    end)
end)
FG.OnEvent("AUCTION_HOUSE_CLOSED", function() visit = visit + 1 end)

-- The player searching the auction house themself: our own searches stop at once.
FG.OnEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function()
    if FG.MarketSearch.CancelAuto() > 0 then Say("searches stopped", "you searched") end
end)

-- The choices, for the settings page.
Auto.CHOICES = { { "permitted", "SET_PRICES_PERMITTED" }, { "hour", "SET_PRICES_HOUR" }, { "day", "SET_PRICES_DAY" },
                 { "off", "SET_PRICES_OFF" } }

function Auto.Line()
    local st = Auto.status
    if not st.last then return nil end
    local key = ({ ["full scan"] = "AUTO_FULL", searches = "AUTO_SEARCHES_FMT", ["nothing to refresh"] = "AUTO_NOTHING",
                   ["another scan"] = "AUTO_OTHER", off = "AUTO_OFF", waits = "AUTO_WAITS",
                   ["searches stopped"] = "AUTO_STOPPED" })[st.last]
    if not key then return nil end
    if key == "AUTO_SEARCHES_FMT" and st.searched == 1 then key = "AUTO_SEARCHES_ONE" end
    return L[key]:format(st.searched or 0)
end
