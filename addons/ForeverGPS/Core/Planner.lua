-- Inspecting a journey before taking it. Plans each way of going in the route
-- engine's slices, one after another, without touching the route being followed;
-- then starts the one the player picks, with the steps already worked out.
--
-- A plan owns everything it found, walks included. The engine keeps walks under the
-- settings they were drawn with, and those change as each mode is tried, so each
-- option takes its own walks while its settings are live. That is what lets the map
-- show any option at any time, with no shared state to disturb.
--
-- current = { target, dest, status, options, selected, message }
--   status: "planning", "partial", "ready", "unreachable" or "failed"
--   an option: { mode, avoid, steps, total, advice, risk, walks, yards, quality,
--                same, noWay, estimate, failed, from, builtAt }
--   quality: "detailed" (every walk follows the ground), "partial" or "estimate"
local FG = ForeverGPS
local Planner = {}
FG.Planner = Planner

local Bridge, Risk = FG.Bridge, FG.Risk
local L = FG.L

local NO_TRANSPORT = { "taxi", "boat", "zeppelin", "portal", "teleport" }

-- avoid: the grid setting a mode turns on, offered only where the data has it.
-- also: ways of travel it leaves out, always offered.
local MODES = {
    { key = "fastest", label = "MODE_FASTEST", tip = "MODE_FASTEST_TT" },
    { key = "safer", label = "MODE_SAFER", tip = "MODE_SAFER_TT", avoid = "danger" },
    { key = "roads", label = "MODE_ROADS", tip = "MODE_ROADS_TT", avoid = "offroad" },
    { key = "overland", label = "MODE_OVERLAND", tip = "MODE_OVERLAND_TT", also = NO_TRANSPORT },
}
Planner.MODES = MODES

local WAIT_SECONDS = 0.15     -- until the engine is free again
local STALE_SECONDS = 120     -- a plan this old is planned again before starting
local STALE_YARDS = 120       -- as is one from this far away
local PLAN_TIMEOUT = 20       -- a plan another replaced never reports back
local SAME_SECONDS = 4        -- routes this close, with the same steps, are one route
local KEPT_PLANS = 6          -- finished plans remembered, for going back and forth
local KEPT_SECONDS = 45

local current
local runID = 0
local kept = {}               -- recent plans, newest first

function Planner.Current() return current end

local function Changed()
    FG.Emit("plan:changed", current)
end

local function ModeAvailable(mode, kinds)
    if not mode.avoid then return true end
    for i = 1, #kinds do
        if kinds[i] == mode.avoid then return true end
    end
    return false
end

local function AvoidFor(mode)
    local avoid = Bridge.BaseAvoid()
    if mode.avoid then avoid[mode.avoid] = true end
    for _, kind in ipairs(mode.also or {}) do avoid[kind] = true end
    return avoid
end

-- Steps that are the engine's plain fallback: one line to the spot, or the
-- step saying nothing reaches it.
local function NoWay(steps) return steps and steps[1] and steps[1].noWay == true end
local function Fallback(steps) return steps and #steps == 1 and steps[1].go == nil end

local function Signature(steps)
    local parts = {}
    for i = 1, #steps do parts[i] = steps[i].kind .. ":" .. (steps[i].text or "") end
    return table.concat(parts, "|")
end

local function WalkYards(option)
    local yards = 0
    for _, path in pairs(option.walks or {}) do yards = yards + (path.len or 0) end
    return yards
end

-- Same steps and same time: a route another mode already found. Walks can differ
-- a little without being a different choice for the player.
local function SameAs(a, b)
    return a.total and b.total and math.abs(a.total - b.total) <= SAME_SECONDS
        and Signature(a.steps) == Signature(b.steps)
end

local function Quality(option)
    if option.estimate then return "estimate" end
    for i, step in ipairs(option.steps) do
        if step.kind == "travel" and not step.fly and not (option.walks and option.walks[i]) then return "partial" end
    end
    return "detailed"
end

local function Remember(plan)
    for i = #kept, 1, -1 do
        if kept[i].key == plan.key then table.remove(kept, i) end
    end
    table.insert(kept, 1, { key = plan.key, plan = plan, at = GetTime() })
    for i = #kept, KEPT_PLANS + 1, -1 do kept[i] = nil end
end

local function Recall(key)
    for i = #kept, 1, -1 do
        local entry = kept[i]
        if GetTime() - entry.at > KEPT_SECONDS then
            table.remove(kept, i)
        elseif entry.key == key then
            return entry.plan
        end
    end
    return nil
end

local function Finish()
    local chosen, first
    local want = FG.char and FG.char.mode or "fastest"
    for _, option in ipairs(current.options) do
        if option.steps and not option.noWay then
            first = first or option
            if option.mode.key == want and not option.same then chosen = option end
        end
    end
    chosen = chosen or first
    Bridge.RestoreNav()
    FG.Metrics.End("plan")
    if chosen then
        current.selected, current.status = chosen, "ready"
        if current.key then Remember(current) end
    else
        current.status = "unreachable"
        current.message = L["ROUTE_NO_WAY"]
    end
    Changed()
end

local RunNext

local function Keep(id, index, steps, total, extra)
    if id ~= runID or not current then return end
    local option = current.options[index]
    extra = extra or {}
    option.steps, option.total, option.advice = steps, total, extra.advice
    option.risk, option.walks = extra.risk, extra.walks
    option.builtAt = GetTime()
    option.from = extra.from or Bridge.PlayerStart()
    if not steps then
        option.failed = true
    elseif NoWay(steps) then
        option.noWay = true
    elseif Fallback(steps) then
        option.estimate = true
    end
    if steps and not option.noWay then
        option.yards = WalkYards(option)
        option.quality = Quality(option)
        for i = 1, index - 1 do
            local earlier = current.options[i]
            if earlier.steps and not earlier.same and SameAs(option, earlier) then
                option.same = earlier
                break
            end
        end
    end
    -- The first answer is enough to show; the others fill in.
    if not current.selected and steps and not option.noWay then
        current.selected = option
        current.status = "partial"
    end
    Changed()
    RunNext(id, index + 1)
end

-- Runs in the planner's slices. The walks are read here, under this option's
-- settings, for as long as those are the grid's.
local function BuildOption(dest, option, stops)
    local steps, total, advice
    if stops then
        steps, total, advice = Bridge.BuildTrip(stops, option.avoid, "all")
    else
        steps, total, advice = Bridge.BuildRoute(dest, option.avoid, "all")
    end
    local from = Bridge.PlayerStart()
    local extra = { advice = advice, from = from }
    if steps and not NoWay(steps) and not Fallback(steps) then
        local plan = { steps = steps, from = from }
        extra.walks = Bridge.WalksOf(plan)
        extra.risk = Risk.Assess(plan, extra.walks)
    end
    return steps, total, extra
end

RunNext = function(id, index)
    if id ~= runID or not current then return end
    local option = current.options[index]
    if not option then return Finish() end
    -- The engine's own work comes first; a plan of ours gone out of date gives way.
    if Bridge.IsPlanning() and not Bridge.PlanIsOurs() then
        FG.After(WAIT_SECONDS, function() RunNext(id, index) end)
        return
    end
    local dest, stops = current.dest, current.stops
    Bridge.PlanOurs(function()
        return BuildOption(dest, option, stops)
    end, function(steps, total, extra)
        Keep(id, index, steps, total, extra)
    end)
    -- A plan another took over from reports nothing: go on past it.
    FG.After(PLAN_TIMEOUT, function()
        if id == runID and current and current.options[index] == option and not option.builtAt then
            FG.Metrics.Note("plan timed out")
            RunNext(id, index)
        end
    end)
end

local function Key(dest, stops, start)
    local parts = {}
    for k, v in pairs(Bridge.BaseAvoid()) do
        if v then parts[#parts + 1] = k end
    end
    table.sort(parts)
    table.insert(parts, 1, ("%d:%d:%d"):format(start.ci, math.floor(start.wx / 20), math.floor(start.wy / 20)))
    for _, s in ipairs(stops or { dest }) do
        parts[#parts + 1] = ("%s:%.3f:%.3f"):format(s.mapID or 0, s.x or 0, s.y or 0)
    end
    return table.concat(parts, "|")
end

local function Failed(message)
    current.status, current.message = "failed", message
    FG.Metrics.Note("plan failed: " .. tostring(message))
    return Changed()
end

-- Plans the journey to target: { data, name, subtitle, icon, binding }.
-- data: a search row, or { name, mapID, x, y }. stops: a list of those, for a trip.
function Planner.Inspect(target)
    runID = runID + 1
    current = { target = target, options = {}, status = "planning", stops = target.stops }
    if not Bridge.Ready() then return Failed(L["NOT_READY"]) end
    if not target.stops and not Bridge.CanNavigate(target.data) then
        return Failed(target.reason or L["ROUTE_CANNOT_NAVIGATE"])
    end
    local start = Bridge.PlayerStart()
    if not start then return Failed(L["ROUTE_UNKNOWN_POSITION"]) end
    current.dest = target.stops and target.stops[#target.stops] or Bridge.DestinationOf(target.data)
    current.key = Key(current.dest, target.stops, start)
    local again = Recall(current.key)
    if again then
        again.target, again.key = target, current.key
        current = again
        return Changed()
    end
    local kinds = Bridge.AvoidKinds()
    for _, mode in ipairs(MODES) do
        if ModeAvailable(mode, kinds) then
            current.options[#current.options + 1] = { mode = mode, avoid = AvoidFor(mode) }
        end
    end
    FG.Metrics.Begin("plan")
    Changed()
    RunNext(runID, 1)
end

-- Says a journey is being worked out before planning can begin.
function Planner.Hold(target)
    runID = runID + 1
    current = { target = target, options = {}, status = "planning" }
    Changed()
end

function Planner.Replan()
    kept = {}
    if current and current.target then Planner.Inspect(current.target) end
end

function Planner.Clear()
    runID = runID + 1
    current = nil
    Changed()
end

function Planner.Select(option)
    if not current then return end
    current.selected = option
    if FG.char then FG.char.mode = option.mode.key end
    Changed()
end

-- Forgets remembered plans: the world they were worked out in has changed.
function Planner.Forget() kept = {} end

function Planner.KeptCount() return #kept end

-- The one thing most worth knowing from the engine's advice, which it works out
-- once a route is under way; nil with none.
function Planner.Tip(advice)
    if not advice then return nil end
    local Duration = FG.Format.Duration
    local learn = advice.learn
    local pickup = advice.pickups and advice.pickups[1]
    if pickup then
        if learn and learn.id == pickup.id and learn.save then
            return L["TIP_PICKUP_SAVE_FMT"]:format(pickup.name or "?", Duration(learn.save))
        end
        return L["TIP_PICKUP_FMT"]:format(pickup.name or "?")
    end
    if learn and learn.extra and learn.save then
        return L["TIP_DETOUR_FMT"]:format(learn.name or "?", Duration(learn.extra), Duration(learn.save))
    end
    return nil
end

-- Whether a plan still holds from where the player stands now.
local function Fresh(option)
    if not (option.steps and option.builtAt and option.from) then return false end
    if GetTime() - option.builtAt > STALE_SECONDS then return false end
    local here = Bridge.PlayerStart()
    if not here or here.ci ~= option.from.ci then return false end
    return (here.wx - option.from.wx) ^ 2 + (here.wy - option.from.wy) ^ 2 <= STALE_YARDS * STALE_YARDS
end

local function Started(option)
    local target = current.target
    FG.Saved.AddRecent(target)
    FG.Journey.Bind(target.binding, target.bindings)
    FG.Emit("route:committed", current.dest, option)
    Planner.Clear()
end

-- Starts navigation on the selected option. A plan gone stale is planned once
-- more from here first.
function Planner.Start()
    local option = current and current.selected
    if not (option and option.steps) then return false end
    if Fresh(option) then
        Bridge.Commit(current.dest, option.steps, option.total, option.advice, option.avoid, current.stops)
        Started(option)
        return true
    end
    if Bridge.IsPlanning() and not Bridge.PlanIsOurs() then
        FG.After(WAIT_SECONDS, Planner.Start)
        return true
    end
    local dest, stops, id = current.dest, current.stops, runID
    Bridge.PlanOurs(function()
        if stops then return Bridge.BuildTrip(stops, option.avoid, "first") end
        return Bridge.BuildRoute(dest, option.avoid, "first")
    end, function(steps, total, advice)
        if id ~= runID or not (steps and current) then return end
        Bridge.Commit(dest, steps, total, advice, option.avoid, stops)
        Started(option)
    end)
    return true
end

-- What a time saved or lost reads as, against the fastest route.
function Planner.Difference(option, base)
    if not (base and option ~= base and option.total and base.total) then return nil end
    local diff = option.total - base.total
    if math.abs(diff) < 30 then return nil end
    return (diff > 0 and "+" or "-") .. FG.Format.Duration(math.abs(diff))
end

-- The way the others are measured against: the first that works.
function Planner.Base(plan)
    for _, option in ipairs(plan.options) do
        if option.steps and not option.noWay then return option end
    end
    return nil
end

local RISK_RANK = { low = 1, moderate = 2, high = 3 }

local function Has(list, value)
    for i = 1, #list do
        if list[i] == value then return true end
    end
    return false
end

-- How a way differs from another, as a line: time, transport, walking, hazards.
-- Only what really differs, so a line this short means the ways are close.
function Planner.Compare(option, base)
    if not (base and option ~= base and option.steps and base.steps) then return nil end
    local parts = { Planner.Difference(option, base) or L["CMP_SAME_TIME"] }
    local mine, theirs = FG.Kinds.Labels(option.steps), FG.Kinds.Labels(base.steps)
    for _, label in ipairs(theirs) do
        if not Has(mine, label) then parts[#parts + 1] = L["CMP_NO_FMT"]:format(label:lower()) end
    end
    for _, label in ipairs(mine) do
        if not Has(theirs, label) then parts[#parts + 1] = L["CMP_ADDS_FMT"]:format(label:lower()) end
    end
    local walked = (option.yards or 0) - (base.yards or 0)
    if math.abs(walked) >= 100 then
        parts[#parts + 1] = L[walked > 0 and "CMP_WALK_MORE_FMT" or "CMP_WALK_LESS_FMT"]:format(FG.Format.Yards(math.abs(walked)))
    end
    local a = option.risk and RISK_RANK[option.risk.level]
    local b = base.risk and RISK_RANK[base.risk.level]
    if a and b and a ~= b then parts[#parts + 1] = L[a < b and "CMP_FEWER_HAZARDS" or "CMP_MORE_HAZARDS"] end
    return table.concat(parts, " \194\183 ")
end

-- Says which other ways came out the same as this one; nil if none did.
function Planner.SameNote(plan, option)
    local names = {}
    for _, other in ipairs(plan.options) do
        if other.same == option then names[#names + 1] = L[other.mode.label] end
    end
    if #names == 0 then return nil end
    return L["CMP_SAME_ROUTE_FMT"]:format(table.concat(names, ", "))
end

local CONFIDENCE = {
    detailed = { "QUALITY_DETAILED", "QUALITY_DETAILED_TT" },
    partial = { "QUALITY_PARTIAL", "QUALITY_PARTIAL_TT" },
    estimate = { "QUALITY_ESTIMATE", "QUALITY_ESTIMATE_TT" },
}

-- How far a route can be trusted, in words and a sentence of why.
function Planner.Confidence(option)
    local entry = CONFIDENCE[option.quality or (option.estimate and "estimate") or ""]
    if not entry then return nil end
    return L[entry[1]], L[entry[2]]
end

FG.OnEvent("TAXIMAP_OPENED", function() FG.After(0.2, Planner.Forget) end)
