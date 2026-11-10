-- The destination stays; the route is disposable. Every test here takes another way than
-- the one planned, and expects to be guided on from where it ends up. The first few were
-- written against 2.2 and failed there: the GPS stayed on the step it was waiting for.
local T = require("support.t")
local Stack = require("support.stack")

local AUBERDINE = { name = "Auberdine", mapID = 1439, x = 0.37, y = 0.44 }
local GOLDSHIRE = { name = "Goldshire", mapID = 1429, x = 0.42, y = 0.65 }
local IRONFORGE = { m = 1455, x = 0.55, y = 0.48 }
local MENETHIL = { m = 1437, x = 0.06, y = 0.62 }

local function Start(opts)
    opts = opts or {}
    opts.mapID, opts.x, opts.y = opts.mapID or 1453, opts.x or 0.6, opts.y or 0.6
    if opts.ui == nil then opts.ui = false end
    return Stack.new(opts)
end

local function Go(c, dest)
    local P = c.FG.Planner
    P.Inspect({ data = dest or AUBERDINE, name = (dest or AUBERDINE).name })
    T.ok(Stack.Until(c, function() return P.Current() and P.Current().status == "ready" end, 30), "planned")
    P.Start()
    c:Advance(1.5)
    return c.FG.Bridge.ActiveRoute()
end

local function Reach(c, step)
    local p = step.arrive
    c:SetPlayer(p.m, p.x, p.y)
    c:Advance(2.2)
end

local function StepKind(c)
    local route = c.FG.Bridge.ActiveRoute()
    local step = route and route.steps[route.active or 1]
    return step and step.kind
end

-- Settles every plan the reroute starts.
local function Settle(c, seconds)
    c:Advance(seconds or 2)
    Stack.Until(c, function() return not c.FG.Bridge.IsPlanning() end, 60)
    c:Advance(1.5)
end

local function From(c)
    local route = c.FG.Bridge.ActiveRoute()
    return route and route.from
end

local function Near(c, point, yards)
    local here = From(c)
    local ci, wx, wy = c.FG.Bridge.WorldPos(point.m, point.x, point.y)
    return here and here.ci == ci and ((here.wx - wx) ^ 2 + (here.wy - wy) ^ 2) ^ 0.5 <= (yards or 200)
end

local function FirstBoatIndex(route)
    for i, step in ipairs(route.steps) do
        if step.kind == "boat" then return i end
    end
end

local tests = {}

-- At the dock, waiting for the boat: the player takes a flight to Ironforge instead.
function tests.waitingForABoat_aFlightElsewhere_isFollowedFromTheLanding()
    local c = Start()
    local route = Go(c)
    local boat = FirstBoatIndex(route)
    T.ok(boat, "the plan takes a boat")
    for i = 1, boat - 1 do Reach(c, route.steps[i]) end
    T.eq(StepKind(c), "boat", "at the dock")
    c.player.taxi = true
    c:Advance(3)
    T.eq(c.FG.Journey.View().state, "riding", "known to be flying")
    T.ok(c.FG.Bridge.ActiveRoute(), "and still going to Auberdine")
    c:SetPlayer(IRONFORGE.m, IRONFORGE.x, IRONFORGE.y)
    c:Advance(2)
    c.player.taxi = false
    Settle(c)
    local now = c.FG.Bridge.ActiveRoute()
    T.ok(now and not now.arrived, "still under way")
    T.eq(now.dest.name, "Auberdine", "to the same place")
    Stack.Until(c, function() return Near(c, IRONFORGE) end, 90)
    T.ok(Near(c, IRONFORGE), "from where it landed")
end

-- On a planned flight, landing somewhere else: on from there, not back to the planned field.
function tests.aDifferentFlight_isFollowedFromWhereItLands()
    local c = Start()
    local route = Go(c)
    local boat = FirstBoatIndex(route)
    for i = 1, boat - 1 do Reach(c, route.steps[i]) end
    -- Pretend the step under way is a flight, landing at Menethil.
    local step = route.steps[route.active]
    step.kind = "taxi"
    c.player.taxi = true
    c:Advance(2)
    c:SetPlayer(IRONFORGE.m, IRONFORGE.x, IRONFORGE.y)
    c.player.taxi = false
    Settle(c)
    Stack.Until(c, function() return Near(c, IRONFORGE) end, 90)
    T.ok(Near(c, IRONFORGE), "rerouted from the landing")
    T.eq(c.FG.Bridge.ActiveRoute().dest.name, "Auberdine")
end

-- Waiting at the dock, then gone by other means and much further away: guided from there.
function tests.aJumpFarFromAWaitingCrossing_isGuidedOnFromThere()
    local c = Start()
    local route = Go(c)
    local boat = FirstBoatIndex(route)
    for i = 1, boat - 1 do Reach(c, route.steps[i]) end
    c:SetPlayer(IRONFORGE.m, IRONFORGE.x, IRONFORGE.y)
    Settle(c, 4)
    Stack.Until(c, function() return Near(c, IRONFORGE) end, 90)
    T.ok(Near(c, IRONFORGE), "rerouted")
    T.eq(c.FG.Bridge.ActiveRoute().dest.name, "Auberdine")
end

-- The plan says hearth; the player takes a flight instead.
function tests.aHearthSuggested_aFlightTaken_isFollowed()
    local c = Start()
    local route = Go(c)
    local boat = FirstBoatIndex(route)
    for i = 1, boat - 1 do Reach(c, route.steps[i]) end
    route.steps[route.active].kind = "teleport"
    c.player.taxi = true
    c:Advance(2)
    T.eq(c.FG.Journey.View().state, "riding")
    c:SetPlayer(IRONFORGE.m, IRONFORGE.x, IRONFORGE.y)
    c.player.taxi = false
    Settle(c)
    Stack.Until(c, function() return Near(c, IRONFORGE) end, 90)
    T.ok(Near(c, IRONFORGE), "on from the landing")
end

-- Walking towards a hearth step is not leaving it: it can be used from anywhere.
function tests.walkingWithAHearthAhead_doesNotReroute()
    local c = Start()
    local route = Go(c)
    local boat = FirstBoatIndex(route)
    for i = 1, boat - 1 do Reach(c, route.steps[i]) end
    route.steps[route.active].kind = "teleport"
    local reroutes = 0
    local ns = c.FG.Bridge.NS()
    local rerouted = ns.GPS.Rerouted
    ns.GPS.Rerouted = function(...) reroutes = reroutes + 1 return rerouted(...) end
    local go = route.steps[route.active].go
    for k = 1, 20 do
        c:SetPlayer(go.m, go.x + k * 0.003, go.y)
        c:Advance(1)
    end
    T.eq(reroutes, 0)
    ns.GPS.Rerouted = rerouted
end

-- A teleport in the middle of a walk: guided on from where it lands.
function tests.aTeleportMidWalk_isGuidedOnFromThere()
    local c = Start()
    Go(c, GOLDSHIRE)
    c:SetPlayer(IRONFORGE.m, IRONFORGE.x, IRONFORGE.y)
    Settle(c, 6)
    Stack.Until(c, function() return Near(c, IRONFORGE) end, 60)
    Stack.Until(c, function() return Near(c, IRONFORGE) end, 90)
    T.ok(Near(c, IRONFORGE), "rerouted")
    T.eq(c.FG.Bridge.ActiveRoute().dest.name, "Goldshire")
end

function tests.inFlight_nothingIsPlannedOverAndOver()
    local c = Start()
    local route = Go(c)
    local boat = FirstBoatIndex(route)
    for i = 1, boat - 1 do Reach(c, route.steps[i]) end
    local plans = 0
    local ns = c.FG.Bridge.NS()
    local plan = ns.GPS.Plan
    ns.GPS.Plan = function(...) plans = plans + 1 return plan(...) end
    c.player.taxi = true
    for _ = 1, 20 do
        c:SetPlayer(1437, 0.3 + _ * 0.01, 0.5)
        c:Advance(1)
    end
    T.eq(plans, 0, "no plan while flying")
    ns.GPS.Plan = plan
end

function tests.aReloadMidFlight_stillReroutesOnLanding()
    local c = Start()
    local route = Go(c)
    local boat = FirstBoatIndex(route)
    for i = 1, boat - 1 do Reach(c, route.steps[i]) end
    c.player.taxi = true
    c:Advance(2)
    local d = Start({ saved = Stack.Saved(c) })
    d.player.taxi = true
    d:Advance(3)
    T.ok(d.FG.Bridge.ActiveRoute(), "the route came back")
    d:SetPlayer(IRONFORGE.m, IRONFORGE.x, IRONFORGE.y)
    d.player.taxi = false
    -- A reload redraws the route's walks first; the reroute waits its turn behind them.
    Settle(d, 10)
    Stack.Until(d, function() return Near(d, IRONFORGE) end, 90)
    T.ok(Near(d, IRONFORGE), "and goes on from the landing")
end

function tests.aRerouteThatFails_keepsTheDestination_andTriesAgain()
    local c = Start()
    local route = Go(c)
    local boat = FirstBoatIndex(route)
    for i = 1, boat - 1 do Reach(c, route.steps[i]) end
    local ns = c.FG.Bridge.NS()
    local build = ns.GPS.BuildStops
    ns.GPS.BuildStops = function() return nil end
    c.player.taxi = true
    c:Advance(2)
    c:SetPlayer(IRONFORGE.m, IRONFORGE.x, IRONFORGE.y)
    c.player.taxi = false
    Settle(c)
    local still = c.FG.Bridge.ActiveRoute()
    T.ok(still and still.dest.name == "Auberdine", "the destination stands")
    T.ok(c.FG.Journey.View(), "and the view has something to say")
    ns.GPS.BuildStops = build
    Settle(c, 12)
    Stack.Until(c, function() return Near(c, IRONFORGE) end, 90)
    T.ok(Near(c, IRONFORGE), "the next try succeeds")
end

-- Walking the wrong way: rerouted once, not over and over.
function tests.walkingAway_reroutesOnce_notInALoop()
    local c = Start()
    Go(c, GOLDSHIRE)
    local reroutes = 0
    c.FG.On("route:rerouted", function() reroutes = reroutes + 1 end)
    local ns = c.FG.Bridge.NS()
    local rerouted = ns.GPS.Rerouted
    ns.GPS.Rerouted = function(...) reroutes = reroutes + 1 return rerouted(...) end
    c:SetPlayer(1453, 0.75, 0.25)
    Settle(c, 6)
    for _ = 1, 30 do c:Advance(1) end
    T.ok(reroutes >= 1 and reroutes <= 2, "rerouted, then settled: " .. reroutes)
    ns.GPS.Rerouted = rerouted
end

function tests.aTripsStopsAhead_surviveATakeOff()
    local c = Start()
    local Trip = c.FG.Trip
    Trip.Add({ name = "Goldshire", mapID = 1429, x = 0.42, y = 0.65 })
    Trip.Add({ name = "Auberdine", mapID = 1439, x = 0.37, y = 0.44 })
    Trip.Preview()
    T.ok(Stack.Until(c, function() return c.FG.Planner.Current() and c.FG.Planner.Current().status == "ready" end, 60))
    c.FG.Planner.Start()
    c:Advance(1.5)
    c.player.taxi = true
    c:Advance(2)
    c:SetPlayer(MENETHIL.m, MENETHIL.x, MENETHIL.y)
    c.player.taxi = false
    Settle(c)
    local route = c.FG.Bridge.ActiveRoute()
    T.ok(route and route.stops and #route.stops >= 1, "the stops still ahead are kept")
end

function tests.noPosition_holdsAndDoesNotReroute()
    local c = Start()
    local route = Go(c)
    local boat = FirstBoatIndex(route)
    for i = 1, boat - 1 do Reach(c, route.steps[i]) end
    local get = c.env.C_Map.GetPlayerMapPosition
    c.env.C_Map.GetPlayerMapPosition = function() return nil end
    c:Advance(10)
    T.eq(StepKind(c), "boat", "nothing moved under it")
    c.env.C_Map.GetPlayerMapPosition = get
end

return tests
