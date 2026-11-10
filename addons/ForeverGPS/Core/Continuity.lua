-- The destination is kept until the player arrives or stops; the route to it is not. The
-- route engine notices a walk gone astray, and a crossing taken to the wrong continent. It
-- did not notice anything else: waiting for a boat, flight or hearth, the player could fly,
-- ride or teleport anywhere on the same continent and the GPS stayed on that step for good.
--
-- EasyFind GPS asks this each second, before its own check (an assembly edit in
-- tools/assemble.py): "wait" holds the step, "reroute" plans again from here, nil leaves
-- the step to the engine. The destination and a trip's stops ahead go through untouched:
-- the engine's reroute keeps them, and the way chosen (wayAvoid) with them.
--
-- Where a route stands, for the HUD and the report (Continuity.State):
--   flying        on a flight the plan did not ask for: nothing is planned in the air
--   recalculating left behind (a landing, a jump, a crossing walked away from): planning
--   unavailable   a plan from here failed: tried again later, each wait longer
--   held          rerouted too often in a short time: a pause before the next try
--   nil           on plan: the engine's own states (moving, waiting, riding, arrived)
--
-- A reroute starts the moment the planner is free, not at the next once-a-second look:
-- a plan still running (the old route's other ways) used to leave a gap of up to a second
-- in which nothing was planning and nothing had started. docs/LIFECYCLE.md.
local FG = ForeverGPS
local Continuity = {}
FG.Continuity = Continuity

local Bridge = FG.Bridge
local L = FG.L

local LANDED_AWAY = 220      -- yards from a ride's planned landing: somewhere else
local LEFT_CROSSING = 400    -- yards from both ends of a crossing still waited for
local JUMP = 600             -- yards moved between two looks a few seconds apart
local JUMP_WINDOW = 4
local RETRY, RETRY_MOST = 6, 60   -- after a failed plan: 6 s, then twice as long, at most a minute
local LOOP_COUNT, LOOP_WINDOW, LOOP_HOLD = 4, 60, 30

Continuity.RETRY, Continuity.RETRY_MOST = RETRY, RETRY_MOST
Continuity.LOOP_COUNT, Continuity.LOOP_WINDOW, Continuity.LOOP_HOLD = LOOP_COUNT, LOOP_WINDOW, LOOP_HOLD

local last = {}
-- GetTime() is this session's clock, so its times are never saved with the route.
local session = setmetatable({}, { __mode = "k" })
local recent = {}            -- when the last reroutes started, whatever the route

local function S(route)
    local s = session[route]
    if not s then
        s = { failures = 0 }
        session[route] = s
    end
    return s
end

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

local function Prune(now)
    while recent[1] and now - recent[1] > LOOP_WINDOW do table.remove(recent, 1) end
end

-- Whether a reroute may start now, and if not, until when it waits.
function Continuity.Ready(route, now)
    if Bridge.IsPlanning() then return false end
    local s = S(route)
    if s.retryAt and now < s.retryAt then return false, s.retryAt end
    Prune(now)
    if #recent >= LOOP_COUNT and now - recent[#recent] < LOOP_HOLD then
        s.held = true
        return false, recent[#recent] + LOOP_HOLD
    end
    s.held = nil
    return true
end

-- Records a reroute about to start. The engine's next plan is this reroute.
local function Started(route, now)
    local s = S(route)
    s.at, s.serial = now, Bridge.PlanSerial() + 1
    recent[#recent + 1] = now
    FG.Metrics.Note("rerouted after " .. tostring(route.offWhy))
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
    if not Continuity.Ready(route, now) then return "wait" end
    Started(route, now)
    return "reroute"
end

-- A plan finished. Was it this route's reroute, and did it fail? Or is the planner free
-- for a reroute that was waiting on it? Either way, at once.
local function PlanDone(serial)
    local route = Bridge.ActiveRoute()
    if not (route and route.offPlan == "lost") then return end
    local now = GetTime()
    local s = S(route)
    if s.serial == serial then
        -- The engine replaces the route when a reroute succeeds: still here, it failed.
        s.serial = nil
        s.failures = s.failures + 1
        s.retryAt = now + math.min(RETRY_MOST, RETRY * 2 ^ (s.failures - 1))
        FG.Metrics.Note("reroute failed " .. s.failures)
        FG.Emit("journey:changed")
        return
    end
    if s.serial then return end      -- a reroute of this route is still to come back
    if not Continuity.Ready(route, now) then return end
    Started(route, now)
    if not Bridge.Reroute(route) then
        s.serial = nil
        table.remove(recent)
    end
end
FG.On("plan:done", PlanDone)

-- Where the route stands: state, reason and, while waiting to try again, seconds left.
function Continuity.State(route)
    if not route then return nil end
    if route.offPlan == "flying" then return "flying", "flight" end
    if route.offPlan ~= "lost" then return nil end
    local s = session[route]
    local now = GetTime()
    if s and s.held then
        Prune(now)
        local left = recent[#recent] and recent[#recent] + LOOP_HOLD - now
        if left and left > 0 then return "held", route.offWhy, left end
    end
    if s and s.retryAt and s.retryAt > now then return "unavailable", route.offWhy, s.retryAt - now end
    return "recalculating", route.offWhy
end

local REASON = { flight = "HUD_RECALC_LANDED", jump = "HUD_RECALC_JUMP", left = "HUD_RECALC_LEFT" }

-- What the HUD says while a route waits on this: nil when nothing is off.
function Continuity.Note(route)
    local state, why, left = Continuity.State(route)
    if state == "flying" then return L["HUD_OFF_PLAN_FLYING"] end
    if state == "unavailable" then return L["HUD_UNAVAILABLE_FMT"]:format(FG.Format.Duration(left) or "?") end
    if state == "held" then return L["HUD_HELD_FMT"]:format(FG.Format.Duration(left) or "?") end
    if state == "recalculating" then return L[REASON[why] or "HUD_OFF_PLAN_LOST"] end
    return nil
end

-- For the navigation report.
function Continuity.Report(route)
    local state, why, left = Continuity.State(route)
    local s = route and session[route]
    Prune(GetTime())
    return { state = state or "on plan", why = why, waits = left, failures = s and s.failures or 0,
             recent = #recent }
end

FG.On("login", function()
    local ns = Bridge.NS()
    if ns and ns.GPS then ns.GPS.OffPlan = Continuity.Check end
end)

-- Tests start each case afresh.
function Continuity._Reset()
    last, recent = {}, {}
    session = setmetatable({}, { __mode = "k" })
end
