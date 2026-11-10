-- The destination is kept until the player arrives or stops; the route to it is not. The
-- route engine notices a walk gone astray, and a crossing taken to the wrong continent. It
-- did not notice anything else: waiting for a boat, flight or hearth, the player could fly,
-- ride or teleport anywhere on the same continent and the GPS stayed on that step for good.
--
-- EasyFind GPS asks this each second, before its own check (an assembly edit in
-- tools/assemble.py): "wait" holds the step, "reroute" plans again from here, nil leaves
-- the step to the engine. It plans nothing during a flight, once on landing, and again a
-- few seconds later only if that plan failed. The destination and a trip's stops ahead go
-- through untouched: the engine's reroute keeps them.
local FG = ForeverGPS
local Continuity = {}
FG.Continuity = Continuity

local Bridge = FG.Bridge
local L = FG.L

local LANDED_AWAY = 220      -- yards from a ride's planned landing: somewhere else
local LEFT_CROSSING = 400    -- yards from both ends of a crossing still waited for
local JUMP = 600             -- yards moved between two looks a few seconds apart
local JUMP_WINDOW = 4
local RETRY = 6              -- seconds before a failed plan is tried again

local last = {}

local function World(point)
    if not point then return nil end
    if point.wx and point.ci then return point.ci, point.wx, point.wy end
    return Bridge.WorldPos(point.m or point.mapID, point.x, point.y)
end

local function Yards(point, ci, px, py)
    local pci, wx, wy = World(point)
    if not pci or pci ~= ci then return math.huge end
    return ((px - wx) ^ 2 + (py - wy) ^ 2) ^ 0.5
end

local function StartOf(route, i)
    local step = route.steps[i]
    if step.go then return step.go end
    if i > 1 then return route.steps[i - 1].arrive end
    return route.from
end

-- Where this step is waited for or ridden from, and where it lands.
local function Away(route, step, ci, px, py, yards)
    local i = route.active or 1
    return Yards(StartOf(route, i), ci, px, py) > yards and Yards(step.arrive, ci, px, py) > yards
end

-- The step under way has been left behind by another way of travelling.
local function Lost(route, why)
    route.offPlan, route.offWhy = "lost", why
end

function Continuity.Check(route, step, ci, px, py)
    local now = GetTime()
    if UnitOnTaxi("player") == true then
        route.wasFlying = true
        last.ci = nil
        if step.kind ~= "taxi" then
            route.offPlan = "flying"
            return "wait"
        end
        return nil
    end
    -- A jump within one step: a step finishing by one (a portal) moves on to the next.
    local same = last.route == route and last.step == (route.active or 1)
    local jumped = same and last.ci ~= nil and now - last.t <= JUMP_WINDOW
        and (last.ci ~= ci or ((px - last.x) ^ 2 + (py - last.y) ^ 2) ^ 0.5 > JUMP)
    last.ci, last.x, last.y, last.t, last.route, last.step = ci, px, py, now, route, route.active or 1
    if route.wasFlying then
        route.wasFlying = nil
        if route.offPlan == "flying" then
            Lost(route, "flight")
        elseif step.kind == "taxi" and Yards(step.arrive, ci, px, py) > LANDED_AWAY then
            Lost(route, "flight")
        end
    end
    local crossing = step.kind ~= "travel" and step.kind ~= "learn"
    if not route.offPlan and jumped and not Bridge.OnRide() and Yards(step.arrive, ci, px, py) > LANDED_AWAY then
        Lost(route, "jump")
    end
    if not route.offPlan and crossing and not Bridge.OnRide() then
        if step.kind ~= "teleport" and not Bridge.Aboard(step) and Away(route, step, ci, px, py, LEFT_CROSSING) then
            Lost(route, "left")
        end
    end
    if route.offPlan == "flying" then return "wait" end
    if route.offPlan ~= "lost" then return nil end
    if Bridge.IsPlanning() or now - (route.rerouteAt or 0) < RETRY then return "wait" end
    route.rerouteAt = now
    FG.Metrics.Note("rerouted after " .. tostring(route.offWhy))
    return "reroute"
end

-- What the HUD says while a route waits on this: nil when nothing is off.
function Continuity.Note(route)
    if not route then return nil end
    if route.offPlan == "flying" then return L["HUD_OFF_PLAN_FLYING"] end
    if route.offPlan == "lost" then return L["HUD_OFF_PLAN_LOST"] end
    return nil
end

FG.On("login", function()
    local ns = Bridge.NS()
    if ns and ns.GPS then ns.GPS.OffPlan = Continuity.Check end
end)
