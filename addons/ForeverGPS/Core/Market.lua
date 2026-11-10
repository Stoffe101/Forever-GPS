-- Prices, from this character's own auction house and merchants, and nowhere else.
--
-- A full scan asks the server for every listing at once (C_AuctionHouse.ReplicateItems),
-- which it allows about once every 15 minutes, and only with the auction house open. It is
-- only ever started by the player's click. The listings are read a few milliseconds a frame
-- and boiled down per item to the lowest buyout per unit, a typical one (the price under
-- which a quarter of the units sit), and how many are listed. That is all that is kept.
--
-- Each auction house is its own market: realm, then the Alliance or Horde house, or the
-- neutral one in a goblin town. A price is only ever read from the market it came from,
-- and says how old it is. Merchant prices are learned when a merchant window opens; what a
-- merchant pays for an item comes from the game. Nothing is bought, bid on or posted.
local FG = ForeverGPS
local Market = {}
FG.Market = Market

local L = FG.L

local SCAN_COOLDOWN = 15 * 60
local SLICE_MS, CHECK_EVERY = 4, 50
local FRESH, RECENT = 3600, 3 * 86400
local NEUTRAL = { ["Booty Bay"] = true, ["Gadgetzan"] = true, ["Everlook"] = true }

local scan = { state = "idle" }      -- idle, waiting, reading, done, failed
local open = false

local function DB()
    FG.db.market = FG.db.market or { houses = {}, vendor = {} }
    return FG.db.market
end

-- Which house this is: realm, and the side's house or the neutral one by its town.
function Market.Key()
    local realm = GetRealmName and GetRealmName() or "?"
    local zone = GetMinimapZoneText and GetMinimapZoneText() or ""
    local side = NEUTRAL[zone] and "Neutral" or (UnitFactionGroup("player") or "?")
    return realm .. ":" .. side, side
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

-- ==== scanning ==============================================================

function Market.CanScan()
    if not open then return false, L["MARKET_CLOSED"] end
    if scan.state == "waiting" or scan.state == "reading" then return false, L["MARKET_SCANNING"] end
    local house = House(Market.Key())
    local wait = house.scannedAt and SCAN_COOLDOWN - (time() - house.scannedAt) or 0
    if wait > 0 then return false, L["MARKET_WAIT_FMT"]:format(FG.Format.Duration(wait) or "?"), wait end
    if not (C_AuctionHouse and C_AuctionHouse.ReplicateItems) then return false, L["MARKET_NO_API"] end
    return true
end

-- Asks for every listing. Only from a click: never by itself.
function Market.Scan()
    local ok, why = Market.CanScan()
    if not ok then return false, why end
    scan = { state = "waiting", key = Market.Key(), asked = GetTime() }
    C_AuctionHouse.ReplicateItems()
    FG.Emit("market:changed")
    return true
end

-- The listings read into per-item summaries, a slice at a time.
local function Read()
    local n = C_AuctionHouse.GetNumReplicateItems and C_AuctionHouse.GetNumReplicateItems() or 0
    scan.state, scan.at, scan.total, scan.units = "reading", 0, n, {}
    local driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", function(self)
        if not open then
            scan.state = "failed"
            scan.why = L["MARKET_CLOSED_MID"]
            self:SetScript("OnUpdate", nil)
            return FG.Emit("market:changed")
        end
        local stop = debugprofilestop() + SLICE_MS
        local units = scan.units
        while scan.at < scan.total do
            local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = C_AuctionHouse.GetReplicateItemInfo(scan.at)
            scan.at = scan.at + 1
            if itemID and buyout and buyout > 0 and count and count > 0 then
                local list = units[itemID]
                if not list then
                    list = {}
                    units[itemID] = list
                end
                list[#list + 1] = math.floor(buyout / count)
                list[#list + 1] = count
            end
            if scan.at % CHECK_EVERY == 0 and debugprofilestop() > stop then
                FG.Emit("market:changed")
                return
            end
        end
        self:SetScript("OnUpdate", nil)
        Market.Store(scan.key, units)
        scan.state = "done"
        FG.Emit("market:changed")
    end)
end

-- Per item: lowest unit buyout, the unit price under which a quarter of the units are
-- listed, and the units listed. Kept as "min:typical:units" to stay small.
function Market.Store(key, units)
    local house = House(key)
    local items = {}
    local n = 0
    for itemID, list in pairs(units) do
        local pairs_ = {}
        local total = 0
        for i = 1, #list, 2 do
            pairs_[#pairs_ + 1] = { list[i], list[i + 1] }
            total = total + list[i + 1]
        end
        table.sort(pairs_, function(a, b) return a[1] < b[1] end)
        local quarter, seen, typical = total / 4, 0, pairs_[1][1]
        for _, p in ipairs(pairs_) do
            seen = seen + p[2]
            typical = p[1]
            if seen >= quarter then break end
        end
        items[itemID] = ("%d:%d:%d"):format(pairs_[1][1], typical, total)
        n = n + 1
    end
    house.items, house.scannedAt, house.count = items, time(), n
    local db = DB()
    db.current = db.current or {}
    db.current[UnitFactionGroup("player") or "?"] = key
    return n
end

function Market.Scanning() return scan end

FG.OnEvent("AUCTION_HOUSE_SHOW", function()
    open = true
    local db = DB()
    db.current = db.current or {}
    db.current[UnitFactionGroup("player") or "?"] = Market.Key()
    FG.Emit("market:changed")
end)
FG.OnEvent("AUCTION_HOUSE_CLOSED", function()
    open = false
    FG.Emit("market:changed")
end)
FG.OnEvent("REPLICATE_ITEM_LIST_UPDATE", function()
    if scan.state == "waiting" then Read() end
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

-- An item's price: { buy (cheapest unit), typical, units, age (seconds), fresh, sure }.
-- sure: "fresh" (within the hour), "recent" (three days), "stale", or nil when unknown.
function Market.Price(itemID, key)
    key = key or Market.Current()
    local house = DB().houses[key]
    local packed = house and house.items[itemID]
    if not packed then return nil end
    local low, typical, units = packed:match("^(%d+):(%d+):(%d+)$")
    local age = time() - (house.scannedAt or 0)
    return { buy = tonumber(low), typical = tonumber(typical), units = tonumber(units), age = age,
             sure = age <= FRESH and "fresh" or age <= RECENT and "recent" or "stale" }
end

-- What a merchant sells it for, when one has been seen to.
function Market.VendorBuy(itemID) return DB().vendor[itemID] end

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
    return { key = key, count = house and house.count or 0, at = house and house.scannedAt, open = open }
end

function Market.IsOpen() return open end
