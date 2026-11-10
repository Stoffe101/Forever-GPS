-- What a journey costs in money, and what that money is worth in time.
--
-- Fares are learned, never made up: each time a flight master's map opens, the game says
-- what every flight from there costs this character, discounts included, and that is kept
-- per character with the day it was read. A leg flown somewhere never seen is estimated
-- from this character's own fares per yard, and said to be estimated. With no fare seen at
-- all, a rough figure stands in so that Best Value can still weigh a flight at all, and the
-- route says so. Money is integer copper throughout.
--
-- Best Value and Cheapest are ways of planning like any other. The engine adds a flight's
-- fare to its time at the player's rate (copper per minute), so it searches the whole
-- network with both in mind rather than taking the fastest route and removing flights.
-- That finds every route a rate could make best; a full multi-label search would also
-- find the few no rate prefers, at several times the cost. docs/TRAVEL_COSTS.md.
local FG = ForeverGPS
local Fares = {}
FG.Fares = Fares

local Bridge = FG.Bridge
local L = FG.L

local DAY = 86400
local FRESH_DAYS, STALE_DAYS = 1, 30
local PRIOR_COPPER_PER_YARD = 0.012   -- only with no fare seen at all; marked as a guess

-- Copper per minute of travel saved, for each preset. Custom is the player's own.
Fares.PRESETS = {
    { key = "money", label = "VALUE_MONEY", rate = 20 },
    { key = "balanced", label = "VALUE_BALANCED", rate = 100 },
    { key = "time", label = "VALUE_TIME", rate = 500 },
}

function Fares.Rate()
    local t = FG.db.travel
    if t.preset == "custom" then return math.max(1, t.customRate or 100) end
    for _, p in ipairs(Fares.PRESETS) do
        if p.key == t.preset then return p.rate end
    end
    return 100
end

local function Book()
    local c = FG.char
    if not c then return {} end
    c.fares = c.fares or {}
    return c.fares
end

-- ==== learning ==============================================================

-- Every fare from the master whose map is open. Called on TAXIMAP_OPENED.
function Fares.Learn()
    local mapID = GetTaxiMapID and GetTaxiMapID()
    if not (mapID and C_TaxiMap and C_TaxiMap.GetAllTaxiNodes and TaxiNodeCost and Enum and Enum.FlightPathState) then return 0 end
    local ok, list = pcall(C_TaxiMap.GetAllTaxiNodes, mapID)
    if not (ok and list) then return 0 end
    local state, here = Enum.FlightPathState, nil
    for _, n in ipairs(list) do
        if n.state == state.Current then here = n.nodeID end
    end
    if not here then return 0 end
    local book, now, count = Book(), time(), 0
    book[here] = book[here] or {}
    for _, n in ipairs(list) do
        if n.state == state.Reachable and n.nodeID and n.slotIndex then
            local cost = TaxiNodeCost(n.slotIndex)
            if type(cost) == "number" and cost >= 0 then
                book[here][n.nodeID] = { c = math.floor(cost), t = now }
                count = count + 1
            end
        end
    end
    Fares.rate = nil
    FG.Emit("fares:learned", here, count)
    return count
end

FG.OnEvent("TAXIMAP_OPENED", function() FG.After(0.2, Fares.Learn) end)

-- ==== reading ===============================================================

local function NodeWorld(id)
    local n = Bridge.FlightNodes()[id]
    if not n then return nil end
    if n.wx then return n.ci, n.wx, n.wy end
    if n.p then return n.p.ci, n.p.wx, n.p.wy end
    return nil
end

local function Yards(a, b)
    local ca, ax, ay = NodeWorld(a)
    local cb, bx, by = NodeWorld(b)
    if not (ca and ca == cb) then return nil end
    return ((ax - bx) ^ 2 + (ay - by) ^ 2) ^ 0.5
end

-- This character's copper per yard, from what it has been charged.
local function LearnedRate()
    if Fares.rate ~= nil then return Fares.rate or nil end
    local total, yards = 0, 0
    for from, row in pairs(Book()) do
        for to, fare in pairs(row) do
            local d = Yards(from, to)
            if d and d > 200 then total, yards = total + fare.c, yards + d end
        end
    end
    Fares.rate = yards > 0 and total / yards or false
    return Fares.rate or nil
end

-- A flight's fare: copper and how sure. sure: "fresh" (read today), "seen", "stale",
-- "estimate" (from this character's own fares per yard) or "guess" (no fare seen yet).
function Fares.Of(from, to, yards)
    local row = Book()[from]
    local fare = row and row[to]
    if fare then
        local age = (time() - fare.t) / DAY
        return fare.c, age <= FRESH_DAYS and "fresh" or age <= STALE_DAYS and "seen" or "stale"
    end
    yards = yards or Yards(from, to)
    if not yards then return nil, "unknown" end
    local rate = LearnedRate()
    if rate then return math.floor(yards * rate + 0.5), "estimate" end
    return math.floor(yards * PRIOR_COPPER_PER_YARD + 0.5), "guess"
end

-- What a planned journey costs. { copper, sure = worst certainty in it, paid = number of
-- paid legs }. A route with no paid leg is confirmed free.
local SURENESS = { fresh = 1, seen = 2, stale = 3, estimate = 4, guess = 5, unknown = 6 }
function Fares.RouteCost(steps)
    local copper, worst, paid = 0, "fresh", 0
    for _, step in ipairs(steps or {}) do
        if step.kind == "taxi" and step.nodeID and step.toID then
            local c, sure = Fares.Of(step.nodeID, step.toID)
            paid = paid + 1
            copper = copper + (c or 0)
            if SURENESS[sure] > SURENESS[worst] then worst = sure end
        end
    end
    return { copper = copper, sure = paid > 0 and worst or "free", paid = paid }
end

-- ==== the engine's weighing =================================================

-- Seconds a leg's fare is worth at the player's rate, for the money ways only. avoid.money
-- holds that rate in copper per minute.
function Fares.Penalty(a, b, yards, avoid)
    local rate = avoid and avoid.money
    if not rate then return 0 end
    local copper = Fares.Of(a, b, yards)
    return (copper or 0) / rate * 60
end

-- Seconds a hearth must save before it is worth its cooldown.
function Fares.HearthReserve()
    return (FG.db.travel.hearthMinutes or 0) * 60
end

FG.On("login", function()
    local ns = Bridge.NS()
    local Route = ns and ns.GPSRoute
    if Route then
        Route.FarePenalty = Fares.Penalty
        Route.HearthReserve = Fares.HearthReserve
    end
end)

-- ==== words =================================================================

function Fares.Money(copper)
    if not copper then return "?" end
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    if g > 0 then return s > 0 and ("%dg %ds"):format(g, s) or ("%dg"):format(g) end
    if s > 0 then return c > 0 and ("%ds %dc"):format(s, c) or ("%ds"):format(s) end
    return ("%dc"):format(c)
end

-- A route's cost as it reads beside its time: "free", "8s", "~8s".
function Fares.Label(cost)
    if not cost or cost.sure == "free" then return L["COST_FREE"] end
    local money = Fares.Money(cost.copper)
    if cost.sure == "guess" or cost.sure == "estimate" or cost.sure == "unknown" then return "~" .. money end
    return money
end

function Fares.Note(cost)
    if not cost then return nil end
    if cost.sure == "guess" then return L["COST_GUESS"] end
    if cost.sure == "estimate" then return L["COST_ESTIMATE"] end
    if cost.sure == "stale" then return L["COST_STALE"] end
    return nil
end
