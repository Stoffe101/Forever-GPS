-- The journey under way, as the HUD reads it, and what happens around it: a
-- quest abandoned or finished mid-route, the arrow in use. EasyFind GPS itself
-- advances the steps, reroutes, leads a ghost to its corpse and restores the
-- route after a reload; this only reads that state and keeps quests in step.
local _, FG = ...
local Journey = {}
FG.Journey = Journey

local Bridge, Kinds, Quests = FG.Bridge, FG.Kinds, FG.Quests
local L = FG.L

local TURN_IN_WINDOW = 3     -- seconds: a quest gone this soon after turning in was not abandoned

-- ==== the view ==============================================================

local function Yards()
    local f = Bridge.Follow()
    if not f then return nil end
    if f.path then return math.max(0, f.path.len - f.along) end
    return f.straight
end

local function NextText(route, index)
    local step = route.steps[index + 1]
    return step and step.text or nil
end

-- What the HUD shows now; nil with no route.
function Journey.View()
    local route = Bridge.Route()
    if not route then return nil end
    if route.arrived then
        local name = route.dest and route.dest.name or "?"
        return { state = "arrived", title = L["HUD_ARRIVED_FMT"]:format(name), icon = FG.ART .. "flag", progress = 1, count = #route.steps,
                 index = #route.steps }
    end
    local index = route.active or 1
    local step = route.steps[index]
    if not step then return nil end
    local riding = Kinds.IsRide(step) and (Bridge.OnRide() or UnitOnTaxi("player") == true)
    local view = {
        state = riding and "riding" or "moving",
        title = Bridge.StepText(step, true), icon = Kinds.Icon(step), kind = step.kind, step = step,
        index = index, count = #route.steps, nextText = NextText(route, index),
        eta = route.eta, stepEta = route.stepEta, total = route.total,
        yards = not riding and Yards() or nil,
        dest = route.dest and route.dest.name,
        hostile = step.hostile,
    }
    -- A cast or a click ahead rather than ground to cover: nothing to point at.
    view.pointing = not riding and step.kind ~= "teleport" and step.kind ~= "learn"
    if route.total and route.total > 0 and route.eta then
        view.progress = math.max(0, math.min(1, 1 - route.eta / route.total))
    else
        view.progress = (index - 1) / math.max(1, #route.steps)
    end
    return view
end

-- Where the HUD's arrow should point, relative to the player's facing; nil
-- when there is nowhere to point (no facing here, or riding).
function Journey.Heading()
    local px, py, ax, ay = Bridge.ArrowAim()
    if not px then return nil end
    local facing = GetPlayerFacing and GetPlayerFacing()
    if not facing or (issecretvalue and issecretvalue(facing)) then return nil end
    local f = Bridge.Follow()
    local bearing = f and Bridge.Bearing(f.ci, px, py, ax, ay)
    if not bearing then return nil end
    return bearing - facing
end

-- ==== quests in step with the route =========================================

local turnedIn = {}

-- The quest the route was started for, or nil to forget it.
function Journey.Bind(binding)
    FG.char.binding = binding
end

function Journey.Binding() return FG.char and FG.char.binding end

local function Stop()
    FG.char.binding = nil
    Bridge.Stop()
end

FG.OnEvent("QUEST_TURNED_IN", function(questID)
    turnedIn[questID] = GetTime()
    local binding = Journey.Binding()
    if binding and binding.questID == questID then
        FG.Emit("toast", L["QUEST_TURNED_IN"]:format(binding.title or "?"))
        if binding.kind == "turnin" or binding.kind == "marker" then Stop() else FG.char.binding = nil end
    end
end)

FG.OnEvent("QUEST_REMOVED", function(questID)
    local binding = Journey.Binding()
    if not (binding and binding.questID == questID) then return end
    local at = turnedIn[questID]
    if at and GetTime() - at < TURN_IN_WINDOW then return end
    FG.Emit("toast", L["QUEST_ABANDONED"]:format(binding.title or "?"))
    if Bridge.ActiveRoute() then Stop() else FG.char.binding = nil end
end)

-- An objective done while heading to it: no reason to keep going.
FG.On("quests:changed", function()
    local binding = Journey.Binding()
    if not (binding and binding.kind == "objective" and Bridge.ActiveRoute()) then return end
    local q = Quests.Get(binding.questID)
    local objective = q and q.objectives[binding.index]
    if objective and objective.finished then
        FG.Emit("toast", L["QUEST_OBJECTIVE_FINISHED"]:format(objective.text), binding.questID)
        Stop()
    end
end)

FG.On("route:cleared", function()
    if FG.char then FG.char.binding = nil end
end)

-- After a reload: the route came back with the character, its quest may not have.
FG.On("login", function()
    local binding = Journey.Binding()
    if not binding then return end
    FG.After(2, function()
        local still = Journey.Binding()
        if still and not Bridge.Route() then
            FG.char.binding = nil
        elseif still and not Quests.Get(still.questID) then
            FG.Emit("toast", L["QUEST_ABANDONED"]:format(still.title or "?"))
            Stop()
        end
    end)
end)

-- ==== watching the route ====================================================

-- Five times a second while a route exists, and not at all otherwise.
local THROTTLE = 0.2
local driver = CreateFrame("Frame")
local since, lastIndex = 0, nil

local function Publish()
    local view = Journey.View()
    FG.Emit("journey:view", view)
    if not view then
        driver:SetScript("OnUpdate", nil)
        lastIndex = nil
        return
    end
    if view.index ~= lastIndex then
        lastIndex = view.index
        FG.Emit("journey:step", view)
    end
end

local function Tick(_, elapsed)
    since = since + elapsed
    if since < THROTTLE then return end
    since = 0
    Publish()
end

function Journey.Watch()
    since = 0
    driver:SetScript("OnUpdate", Tick)
    Publish()
end

FG.On("route:started", Journey.Watch)
FG.On("route:committed", Journey.Watch)
FG.On("route:cleared", function() FG.After(0, Journey.Watch) end)
FG.On("login", function()
    -- The route the character logged out on carries on.
    if Bridge.Route() then Journey.Watch() end
end)

-- ==== the arrow in use ======================================================

-- Exactly one arrow leads: the HUD's, EasyFind's at the character, TomTom's, or
-- none. The route's beacon draws its own edge arrow when it thinks no arrow
-- leads, so the HUD says it does.
function Journey.ApplyArrow()
    local mode = FG.db.arrow
    if mode == "tomtom" and not FG.TomTom.Available() then mode = "hud" end
    Bridge.SetCharacterArrow(mode == "character")
    Bridge.ClaimGuiding(function() return FG.HUD ~= nil and FG.HUD.Guiding() end)
    FG.Emit("arrow:changed", mode)
end

FG.On("login", Journey.ApplyArrow)

function Journey.ArrowMode()
    local mode = FG.db.arrow
    if mode == "tomtom" and not FG.TomTom.Available() then return "hud" end
    return mode
end
