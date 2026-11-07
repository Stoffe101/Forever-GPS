-- Several stops in one journey, and Quest Circuit: a sensible order to visit them
-- in. The order is worked out from the route engine's own travel times; the trip
-- itself is planned and followed by EasyFind GPS's multi-stop engine, so there is no
-- second router here, only the choice of order.
local FG = ForeverGPS
local Trip = {}
FG.Trip = Trip

local Bridge, Eta = FG.Bridge, FG.Eta
local L = FG.L

local MAX_STOPS = 8          -- beyond this the matrix stops being cheap and the trip stops being useful
local MAX_SAVED = 8
local NEARBY_YARDS = 700     -- close enough to take in on one walk
local SAME_SPOT_YARDS = 40   -- two things this close are one stop
local TWO_OPT_PASSES = 6
local UNKNOWN = 1e6          -- a leg with no estimate: possible, but a last resort

-- The list is kept with the character, so it survives a reload.
local stops = {}
FG.On("loaded", function() stops = FG.char.trip end)

function Trip.List() return stops end
function Trip.Count() return #stops end

local function Changed() FG.Emit("trip:changed") end

local function Same(a, b)
    return a.mapID == b.mapID and a.x == b.x and a.y == b.y and a.name == b.name
end

-- stop: { name, mapID, x, y, icon, subtitle, binding }. False when the list is
-- full or it is already on it.
function Trip.Add(stop)
    if #stops >= MAX_STOPS then return false, L["TRIP_FULL_FMT"]:format(MAX_STOPS) end
    for i = 1, #stops do
        if Same(stops[i], stop) then return false end
    end
    stops[#stops + 1] = stop
    Changed()
    return true
end

function Trip.Has(stop)
    for i = 1, #stops do
        if Same(stops[i], stop) then return true end
    end
    return false
end

-- A stop for a journey being inspected; nil when it has no one place to stand.
function Trip.FromTarget(target)
    if not target.data then return nil end
    local ok, dest = pcall(Bridge.DestinationOf, target.data)
    if not (ok and dest and dest.mapID and dest.x and dest.y) then return nil end
    return { name = target.name or dest.name, subtitle = target.subtitle, icon = target.icon,
             mapID = dest.mapID, x = dest.x, y = dest.y, binding = target.binding }
end

function Trip.Remove(i)
    table.remove(stops, i)
    Changed()
end

function Trip.Move(i, j)
    if not stops[i] or j < 1 or j > #stops or i == j then return end
    table.insert(stops, j, table.remove(stops, i))
    Changed()
end

function Trip.Clear()
    stops = {}
    FG.char.trip = stops
    Changed()
end

-- Keeps the trip as it stands, by where it goes.
function Trip.Save()
    if #stops == 0 then return false end
    local list = FG.char.savedTrips
    local name = #stops == 1 and stops[1].name or L["TRIP_SAVED_FMT"]:format(stops[1].name, stops[#stops].name)
    local copy = {}
    for i, stop in ipairs(stops) do copy[i] = stop end
    table.insert(list, 1, { name = name, stops = copy })
    for i = #list, MAX_SAVED + 1, -1 do list[i] = nil end
    Changed()
    return true
end

function Trip.Saved() return FG.char.savedTrips end

function Trip.Load(i)
    local saved = FG.char.savedTrips[i]
    if not saved then return end
    stops = {}
    for k, stop in ipairs(saved.stops) do stops[k] = stop end
    FG.char.trip = stops
    Changed()
end

function Trip.Forget(i)
    table.remove(FG.char.savedTrips, i)
    Changed()
end

-- ==== choosing an order =====================================================

-- Whether visiting in this order respects what must come first.
local function Valid(order, before)
    local at = {}
    for pos, stop in ipairs(order) do at[stop] = pos end
    for a, b in pairs(before or {}) do
        for _, later in ipairs(type(b) == "table" and b or { b }) do
            if at[a] and at[later] and at[a] >= at[later] then return false end
        end
    end
    return true
end

local function Length(order, cost)
    local total, from = 0, 0
    for _, stop in ipairs(order) do
        total = total + cost(from, stop)
        from = stop
    end
    return total
end

-- The order to visit stops 1..n in, starting from 0. cost(a, b) is the time from a
-- to b; before[a] = b, or a list of them, says a must come before b. Nearest first, then improved by
-- reversing stretches while that helps: not the best possible, but good, and
-- bounded, which suits eight stops in a game frame.
function Trip.Order(n, cost, before)
    local order, used, from = {}, {}, 0
    local function Ready(stop)
        for a, b in pairs(before or {}) do
            for _, later in ipairs(type(b) == "table" and b or { b }) do
                if later == stop and not used[a] then return false end
            end
        end
        return true
    end
    for _ = 1, n do
        local best, bestCost
        for stop = 1, n do
            if not used[stop] and Ready(stop) then
                local c = cost(from, stop)
                if not best or c < bestCost then best, bestCost = stop, c end
            end
        end
        if not best then break end
        used[best] = true
        order[#order + 1] = best
        from = best
    end
    for _ = 1, TWO_OPT_PASSES do
        local improved = false
        for i = 1, #order - 1 do
            for j = i + 1, #order do
                local candidate = {}
                for k = 1, #order do candidate[k] = order[k] end
                for k = 0, j - i do candidate[i + k] = order[j - k] end
                if Valid(candidate, before) and Length(candidate, cost) + 0.5 < Length(order, cost) then
                    order, improved = candidate, true
                end
            end
        end
        if not improved then break end
    end
    return order
end

-- ==== Quest Circuit =========================================================

local QUEST_ORDER = { start = 1, objective = 2, turnin = 3 }

-- Whether quest a must be turned in before quest b can be picked up.
local function Unlocks(a, b)
    for _, group in ipairs(FG.QuestChain.Requirements(b)) do
        for _, id in ipairs(group.ids) do
            if id == a then return true end
        end
    end
    return false
end

-- A quest is picked up before it is worked on, and worked on before it is handed in; a
-- quest comes after the one it needs. Anything else is free to go wherever is shortest.
local function Precedence(list)
    local before = {}
    for i, a in ipairs(list) do
        local later = {}
        for j, b in ipairs(list) do
            local x, y = a.binding, b.binding
            if i ~= j and x and y then
                if x.questID == y.questID then
                    local p, q = QUEST_ORDER[x.kind], QUEST_ORDER[y.kind]
                    if p and q and p < q then later[#later + 1] = j end
                elseif x.kind == "turnin" and y.kind == "start" and Unlocks(x.questID, y.questID) then
                    later[#later + 1] = j
                end
            end
        end
        if #later > 0 then before[i] = later end
    end
    return before
end
Trip._Precedence = Precedence

local function PointOf(stop)
    local ci, wx, wy = Bridge.WorldPos(stop.mapID, stop.x, stop.y)
    if not ci then return nil end
    return { m = stop.mapID, x = stop.x, y = stop.y, ci = ci, wx = wx, wy = wy }
end

-- Estimates every leg in later frames, then puts the stops in the best order found.
function Trip.Optimize(done)
    local list, n = stops, #stops
    if n < 2 then
        if done then done() end
        return
    end
    local here = Bridge.PlayerStart()
    if not here then
        if done then done(L["ROUTE_UNKNOWN_POSITION"]) end
        return
    end
    FG.Metrics.Begin("circuit")
    local points = { [0] = here }
    for i = 1, n do points[i] = PointOf(list[i]) end
    local matrix = {}
    local waiting = 0
    local function Settle()
        local function Cost(a, b)
            local row = matrix[a]
            return row and row[b] or UNKNOWN
        end
        local order = Trip.Order(n, Cost, Precedence(list))
        local sorted = {}
        for k, i in ipairs(order) do sorted[k] = list[i] end
        if #sorted == n then
            stops = sorted
            FG.char.trip = stops
        end
        FG.Metrics.End("circuit")
        Changed()
        if done then done() end
    end
    for a = 0, n do
        matrix[a] = {}
        for b = 1, n do
            if a ~= b and points[a] and points[b] then
                waiting = waiting + 1
                local from = points[a]
                Eta.Request(Bridge.DestinationOf(list[b]), function(value)
                    matrix[a][b] = value and value.sec or UNKNOWN
                    waiting = waiting - 1
                    if waiting == 0 then Settle() end
                end, nil, from)
            end
        end
    end
    if waiting == 0 then Settle() end
end

-- What is open and close by, the nearest first: each as a stop. The closest area of each
-- objective, and the turn-in of anything finished. Things side by side count once.
function Trip.NearbyStops()
    local Quests, Targets = FG.Quests, FG.QuestTargets
    local start = Bridge.PlayerStart()
    if not start then return {} end
    local found = {}
    local function Consider(q, target)
        local best, bestYards
        for _, area in ipairs(target.areas or {}) do
            if area.ci == start.ci then
                local yards = ((area.wx - start.wx) ^ 2 + (area.wy - start.wy) ^ 2) ^ 0.5
                if not bestYards or yards < bestYards then best, bestYards = area, yards end
            end
        end
        if not best or bestYards > NEARBY_YARDS then return end
        for _, other in ipairs(found) do
            if (other.area.wx - best.wx) ^ 2 + (other.area.wy - best.wy) ^ 2 < SAME_SPOT_YARDS ^ 2 then return end
        end
        found[#found + 1] = { yards = bestYards, area = best, q = q, target = target }
    end
    for _, q in ipairs(Quests.All()) do
        if not q.failed then
            local entry = Targets.Peek(q)
            local targets = entry and entry.targets
            if targets and q.complete then
                if targets.turnIn and targets.turnIn.status == "ok" then Consider(q, targets.turnIn) end
            elseif targets then
                for i = 1, #q.objectives do
                    local target = targets.objectives[i]
                    if target and target.status == "ok" and not target.done then Consider(q, target) end
                end
            end
        end
    end
    table.sort(found, function(a, b) return a.yards < b.yards end)
    local out = {}
    for i = 1, math.min(#found, MAX_STOPS) do
        local f = found[i]
        out[i] = Trip.FromTarget(Targets.Destination(f.q, f.target, f.area))
    end
    return out
end

-- Everything close by as a trip, in a sensible order, ready to look over.
function Trip.PlanNearby()
    local found = Trip.NearbyStops()
    if #found == 0 then return end
    stops = {}
    FG.char.trip = stops
    for _, stop in ipairs(found) do stops[#stops + 1] = stop end
    Changed()
    FG.Window.Show("trip")
    Trip.Optimize(function()
        Trip.Preview()
        FG.Window.ShowRoute()
    end)
end

-- Plans the trip as it stands, in the journey panel and on the map.
function Trip.Preview()
    if #stops == 0 then return end
    if #stops == 1 then
        local stop = stops[1]
        return FG.Planner.Inspect({ data = stop, name = stop.name, subtitle = stop.subtitle, icon = stop.icon,
                                    binding = stop.binding })
    end
    local list, bindings = {}, {}
    for i, stop in ipairs(stops) do
        list[i] = Bridge.DestinationOf(stop)
        bindings[i] = stop.binding or false
    end
    FG.Planner.Inspect({ stops = list, bindings = bindings, name = L["TRIP_NAME_FMT"]:format(#list),
                         subtitle = L["TRIP_THROUGH_FMT"]:format(list[#list].name or "?"), trip = true,
                         data = list[#list] })
end

-- ==== a trip under way ======================================================

-- Goes on from here to the stops left, keeping the way it was planned on.
local function Replan(route, left)
    if #left == 0 then return Bridge.Stop() end
    local avoid, dest = route.wayAvoid, left[#left]
    local function Build()
        if #left == 1 then return Bridge.BuildRoute(dest, avoid, "first") end
        return Bridge.BuildTrip(left, avoid, "first")
    end
    if Bridge.IsPlanning() and not Bridge.PlanIsOurs() then
        FG.After(0.2, function() Replan(route, left) end)
        return
    end
    Bridge.PlanOurs(Build, function(steps, total, advice)
        if steps and Bridge.Route() == route then
            Bridge.Commit(dest, steps, total, advice, avoid, #left > 1 and left or nil)
        end
    end)
end

-- Drops the stop at position k of those ahead, and goes on without it.
function Trip.SkipStop(k)
    local route = Bridge.ActiveRoute()
    if not route then return end
    local ahead = Bridge.StopsAhead(route)
    if not ahead then return end
    local left = {}
    for i = 1, #ahead do
        if i ~= k then left[#left + 1] = ahead[i] end
    end
    local bindings = FG.char.bindings
    if bindings then table.remove(bindings, k + (#bindings - #ahead)) end
    Replan(route, left)
end

-- The first stop ahead, on a trip; nil on a journey with one destination.
function Trip.NextStop()
    local route = Bridge.ActiveRoute()
    local ahead = route and Bridge.StopsAhead(route)
    if ahead and #ahead > 1 then return ahead[1] end
    return nil
end

-- An objective done mid-trip: its stop is no reason to go on, so it drops out.
FG.On("quests:changed", function()
    local route = Bridge.ActiveRoute()
    local bindings = FG.char and FG.char.bindings
    if not (route and bindings) then return end
    local ahead = Bridge.StopsAhead(route)
    if not ahead then return end
    local offset = #bindings - #ahead
    for k = #ahead, 1, -1 do
        local binding = bindings[k + offset]
        if binding and binding.kind == "objective" then
            local q = FG.Quests.Get(binding.questID)
            local objective = q and q.objectives[binding.index]
            if objective and objective.finished then
                FG.Emit("toast", L["QUEST_OBJECTIVE_FINISHED"]:format(objective.text))
                Trip.SkipStop(k)
                return
            end
        end
    end
end)
