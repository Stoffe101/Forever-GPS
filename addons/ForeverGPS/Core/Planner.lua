-- Inspecting a journey before taking it. Plans each way of going (fastest,
-- safer, on roads) in the route engine's slices, one after another, without
-- touching the route being followed; then starts the one the player picks,
-- with the steps already worked out.
--
-- current = { target, dest, status, options, selected, message }
--   status: "planning", "ready", "unreachable" or "failed"
--   an option: { mode, avoid, steps, total, advice, risk, same, estimate }
local _, FG = ...
local Planner = {}
FG.Planner = Planner

local Bridge, Risk = FG.Bridge, FG.Risk
local L = FG.L

local MODES = {
    { key = "fastest", label = "MODE_FASTEST", tip = "MODE_FASTEST_TT" },
    { key = "safer", label = "MODE_SAFER", tip = "MODE_SAFER_TT", avoid = "danger" },
    { key = "roads", label = "MODE_ROADS", tip = "MODE_ROADS_TT", avoid = "offroad" },
}
Planner.MODES = MODES

local WAIT_SECONDS = 0.15     -- until the engine is free again
local STALE_SECONDS = 120     -- a plan this old is planned again before starting
local STALE_YARDS = 120       -- as is one from this far away
local PLAN_TIMEOUT = 20       -- a plan a newer one replaced never reports back
local SAME_SECONDS = 4        -- routes this close, with the same steps, are one route

local current
local runID = 0

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

local function SameAs(a, b)
    return a.total and b.total and math.abs(a.total - b.total) <= SAME_SECONDS
        and Signature(a.steps) == Signature(b.steps)
end

local function Finish()
    local chosen
    local want = FG.char and FG.char.mode or "fastest"
    local first
    for _, option in ipairs(current.options) do
        if option.steps and not option.noWay then
            first = first or option
            if option.mode.key == want and not option.same then chosen = option end
        end
    end
    chosen = chosen or first
    Bridge.RestoreNav()
    if chosen then
        current.selected, current.status = chosen, "ready"
    else
        current.status = "unreachable"
        current.message = L["ROUTE_NO_WAY"]
    end
    Changed()
end

local RunNext

local function Keep(id, index, steps, total, advice, risk)
    if id ~= runID or not current then return end
    local option = current.options[index]
    option.steps, option.total, option.advice, option.risk = steps, total, advice, risk
    option.builtAt = GetTime()
    option.from = Bridge.PlayerStart()
    if not steps then
        option.failed = true
    elseif NoWay(steps) then
        option.noWay = true
    elseif Fallback(steps) then
        option.estimate = true
    end
    if index > 1 and steps and not option.noWay then
        local base = current.options[1]
        if base.steps and SameAs(option, base) then option.same = true end
    end
    -- The first answer is enough to show; the others fill in.
    if index == 1 and steps and not option.noWay then
        current.selected = option
        current.status = "partial"
    end
    Changed()
    RunNext(id, index + 1)
end

RunNext = function(id, index)
    if id ~= runID or not current then return end
    local option = current.options[index]
    if not option then return Finish() end
    if Bridge.IsPlanning() then
        FG.After(WAIT_SECONDS, function() RunNext(id, index) end)
        return
    end
    local dest = current.dest
    Bridge.Plan(function()
        local steps, total, advice = Bridge.BuildRoute(dest, option.avoid, "all")
        local risk
        if steps and not NoWay(steps) and not Fallback(steps) then
            risk = Risk.Assess({ steps = steps, from = Bridge.PlayerStart() })
        end
        return steps, total, { advice = advice, risk = risk }
    end, function(steps, total, extra)
        Keep(id, index, steps, total, extra and extra.advice, extra and extra.risk)
    end)
    -- A plan another took over from reports nothing: go on past it.
    FG.After(PLAN_TIMEOUT, function()
        if id == runID and current and current.options[index] == option and not option.builtAt then
            RunNext(id, index)
        end
    end)
end

-- Plans the journey to target: { data, name, subtitle, icon, binding }.
-- data: a search row, or { name, mapID, x, y }.
function Planner.Inspect(target)
    runID = runID + 1
    current = { target = target, options = {}, status = "planning" }
    if not Bridge.Ready() then
        current.status, current.message = "failed", L["NOT_READY"]
        return Changed()
    end
    if not Bridge.CanNavigate(target.data) then
        current.status, current.message = "failed", target.reason or L["ROUTE_CANNOT_NAVIGATE"]
        return Changed()
    end
    if not Bridge.PlayerStart() then
        current.status, current.message = "failed", L["ROUTE_UNKNOWN_POSITION"]
        return Changed()
    end
    current.dest = Bridge.DestinationOf(target.data)
    local kinds = Bridge.AvoidKinds()
    for _, mode in ipairs(MODES) do
        if ModeAvailable(mode, kinds) then
            current.options[#current.options + 1] = { mode = mode, avoid = AvoidFor(mode) }
        end
    end
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
    FG.Journey.Bind(target.binding, current.dest)
    FG.Emit("route:committed", current.dest, option)
end

-- Starts navigation on the selected option. A plan gone stale is planned once
-- more from here first.
function Planner.Start()
    local option = current and current.selected
    if not (option and option.steps) then return false end
    if Fresh(option) then
        Bridge.Commit(current.dest, option.steps, option.total, option.advice, option.avoid)
        Started(option)
        return true
    end
    if Bridge.IsPlanning() then
        FG.After(WAIT_SECONDS, Planner.Start)
        return true
    end
    local dest, id = current.dest, runID
    Bridge.Plan(function()
        return Bridge.BuildRoute(dest, option.avoid, "first")
    end, function(steps, total, advice)
        if id ~= runID or not (steps and current) then return end
        Bridge.Commit(dest, steps, total, advice, option.avoid)
        Started(option)
    end)
    return true
end
