-- How an item's lowest listing has moved, and alerts when it falls below a price the player
-- set. Kept small on purpose: one point a day per item (the day's lowest, and the units then
-- listed), for at most 14 days, only for items that matter to this account (reagents and
-- outputs of known recipes, items on a list, items with an alert), at most 600 per house.
--
-- These are listings, not sales: the client does not say what sold. Every view says so.
-- An alert is only ever checked when new prices arrive, and only says something; nothing is
-- bought.
local FG = ForeverGPS
local History = {}
FG.PriceHistory = History

local L = FG.L

local DAYS, MOST_ITEMS = 14, 600
History.DAYS, History.MOST_ITEMS = DAYS, MOST_ITEMS

local function Day(t) return math.floor((t or time()) / 86400) end

-- The items worth a history: what this character makes and makes from, its lists, alerts.
local function Watched()
    local set = {}
    for _, r in ipairs(FG.Professions.Recipes()) do
        if r.learned then
            if r.out then set[r.out] = true end
            for _, g in ipairs(r.reagents or {}) do set[g.id] = true end
        end
    end
    for _, project in ipairs(FG.Crafting.Projects()) do
        for _, item in ipairs(project.items) do
            local r = FG.Professions.Recipe(item.recipe)
            for _, g in ipairs(r and r.reagents or {}) do set[g.id] = true end
        end
    end
    for id in pairs(FG.db.alerts or {}) do set[id] = true end
    return set
end
History._Watched = Watched

-- Adds today's point for each watched item in a house, from its current prices.
function History.Note(key)
    local db = FG.db.market
    local house = db and db.houses and db.houses[key]
    if not house then return 0 end
    house.history = house.history or {}
    local today = Day()
    local n = 0
    for id in pairs(Watched()) do
        local price = FG.Market.Price(id, key)
        if price and price.age < 86400 then
            local text = house.history[id] or ""
            local points = {}
            for d, low, units in text:gmatch("(%d+):(%d+):(%d+)") do
                points[#points + 1] = { tonumber(d), tonumber(low), tonumber(units) }
            end
            local last = points[#points]
            if last and last[1] == today then
                last[2], last[3] = math.min(last[2], price.buy), price.units
            else
                points[#points + 1] = { today, price.buy, price.units }
            end
            while #points > 0 and today - points[1][1] >= DAYS do table.remove(points, 1) end
            local parts = {}
            for i, p in ipairs(points) do parts[i] = p[1] .. ":" .. p[2] .. ":" .. p[3] end
            house.history[id] = table.concat(parts, ";")
            n = n + 1
        end
    end
    -- Bounded: the items whose last point is oldest go first.
    local all = {}
    for id, text in pairs(house.history) do
        all[#all + 1] = { id = id, last = tonumber(text:match("(%d+):%d+:%d+$")) or 0 }
    end
    if #all > MOST_ITEMS then
        table.sort(all, function(a, b) return a.last > b.last end)
        for i = MOST_ITEMS + 1, #all do house.history[all[i].id] = nil end
    end
    return n
end

-- An item's points, oldest first: { { day, low, units } }, and how it moved: the last low
-- against the median of the ones before ("up", "down", "flat"), or nil with too few.
function History.Of(id, key)
    key = key or FG.Market.Current()
    local db = FG.db.market
    local house = db and db.houses and db.houses[key]
    local text = house and house.history and house.history[id]
    local points = {}
    for d, low, units in (text or ""):gmatch("(%d+):(%d+):(%d+)") do
        points[#points + 1] = { day = tonumber(d), low = tonumber(low), units = tonumber(units) }
    end
    if #points < 3 then return points, nil end
    local before = {}
    for i = 1, #points - 1 do before[i] = points[i].low end
    table.sort(before)
    local median = before[math.ceil(#before / 2)]
    local now = points[#points].low
    local trend = now > median * 1.1 and "up" or now < median * 0.9 and "down" or "flat"
    return points, trend, median
end

-- ==== alerts ================================================================

function History.SetAlert(id, below)
    FG.db.alerts = FG.db.alerts or {}
    FG.db.alerts[id] = below and { below = below } or nil
    FG.Emit("alerts:changed")
end

function History.Alert(id) return FG.db.alerts and FG.db.alerts[id] end

-- Checked when new prices arrive, never on a timer. Says each item at or under its price
-- once per new price.
function History.CheckAlerts(key)
    local said = {}
    for id, alert in pairs(FG.db.alerts or {}) do
        local price = FG.Market.Price(id, key)
        if price and price.buy <= alert.below and alert.lastSaid ~= price.buy then
            alert.lastSaid = price.buy
            said[#said + 1] = id
            local name = GetItemInfo(id) or ("item:" .. id)
            FG.Print(L["ALERT_BELOW_FMT"]:format(name, FG.Fares.Money(price.buy), FG.Fares.Money(alert.below)))
        elseif price and price.buy > alert.below then
            alert.lastSaid = nil
        end
    end
    if #said > 0 then FG.Emit("market:alert", said) end
    return said
end

FG.On("market:prices", function(key)
    History.Note(key)
    History.CheckAlerts(key)
end)
