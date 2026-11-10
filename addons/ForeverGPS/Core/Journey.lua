-- The journey under way, as the HUD reads it, and what happens around it: a
-- quest abandoned or finished mid-route, the arrow in use. EasyFind GPS itself
-- advances the steps, reroutes, leads a ghost to its corpse and restores the
-- route after a reload; this only reads that state and keeps quests in step.
local FG = ForeverGPS
local Journey = {}
FG.Journey = Journey

local Bridge, Kinds, Quests = FG.Bridge, FG.Kinds, FG.Quests
local L = FG.L

local TURN_IN_WINDOW = 3     -- seconds: a quest gone this soon after turning in was not abandoned
local WAITING_YARDS = 30     -- this close to where a ride is boarded, the player is waiting for it
local TURN_REACH = 60        -- yards ahead a turn is worth mentioning
local TURN_SHARP = 0.7       -- radians: gentler than this is not a turn
local REROUTE_NOTE_EVERY = 30
local RIDE_MEMORY = 30       -- seconds a ride is still the likely reason for finding oneself elsewhere
local LANDED_YARDS = 300     -- this close to where a ride lands, it went where it should

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

-- Where the player stands with a ride: "riding", "aboard" a docked one, "waiting"
-- at its stop, or nil while still on the way there. A flight is taken by talking to
-- its master, so there is no waiting for one.
local function RideState(step)
    if not Kinds.IsRide(step) then return nil end
    if Bridge.OnRide() or UnitOnTaxi("player") == true then return "riding" end
    if step.kind == "taxi" then return nil end
    if Bridge.Aboard(step) then return "aboard" end
    if Bridge.AtSpot(step.go, WAITING_YARDS) then return "waiting" end
    return nil
end

local function WaitingTitle(step)
    local ride = step.reach or Kinds.Label(step)
    return L["HUD_WAITING_FMT"]:format((ride:gsub("^%u", string.lower)))
end

local shownEta

-- A time left that glides: one change of speed should not make the number leap.
-- A reroute sets it straight at once, and says why.
local function Glide(eta)
    if not eta then
        shownEta = nil
        return nil
    end
    if not shownEta then
        shownEta = eta
    else
        local most = math.max(1, shownEta * 0.01)
        shownEta = shownEta + math.max(-most, math.min(most, eta - shownEta))
    end
    return shownEta
end

Journey._Glide = Glide

-- What the HUD shows now; nil with no route.
function Journey.View()
    local route = Bridge.Route()
    if not route then return nil end
    if route.arrived then
        local name = route.dest and route.dest.name or "?"
        return { state = "arrived", title = L["HUD_ARRIVED_FMT"]:format(name), icon = FG.ART .. "flag", progress = 1, count = #route.steps,
                 index = #route.steps, took = Journey.Took() }
    end
    local index = route.active or 1
    local step = route.steps[index]
    if not step then return nil end
    local ride = RideState(step)
    -- Off the plan: "riding" another flight, "rerouting", or "unavailable" while a failed
    -- plan waits to be tried again (also after too many reroutes in a minute).
    local off = FG.Continuity and FG.Continuity.Note(route)
    if off and not ride then
        local cstate = FG.Continuity.State(route)
        ride = cstate == "flying" and "riding" or (cstate == "unavailable" or cstate == "held") and "unavailable" or "rerouting"
    end
    local view = {
        state = ride or "moving",
        title = off or (ride == "waiting" and WaitingTitle(step)) or Bridge.StepText(step, true),
        icon = Kinds.Icon(step), kind = step.kind, step = step,
        index = index, count = #route.steps, nextText = NextText(route, index),
        eta = route.eta, stepEta = route.stepEta, total = route.total,
        yards = not ride and Yards() or nil,
        dest = route.dest and route.dest.name,
        hostile = step.hostile,
    }
    if ride == "waiting" then view.leaves = Bridge.LeavesIn(step) end
    -- A cast or a click ahead rather than ground to cover: nothing to point at.
    view.pointing = not ride and step.kind ~= "teleport" and step.kind ~= "learn"
    if view.pointing and FG.db.hud.mode == "detailed" then view.turn = Bridge.TurnAhead(TURN_REACH, TURN_SHARP) end
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

-- ==== how the journey went ===================================================

local underway                  -- { name, at, planned }, from start to arrival
local tookSeconds

function Journey.Took() return tookSeconds end

local function Begin()
    local route = Bridge.Route()
    tookSeconds = nil
    if route and route.dest then
        underway = { name = route.dest.name, at = GetTime(), planned = route.total }
    end
    FG.Saved.SetResume(nil)
end

FG.On("route:arrived", function()
    if underway then
        tookSeconds = GetTime() - underway.at
        FG.Saved.LogJourney(underway.name, tookSeconds, underway.planned)
    end
    underway = nil
    FG.Saved.SetResume(nil)
    FG.Emit("journey:arrived", tookSeconds)
end)

-- Stopped short: the way back to it stays on offer for a while.
local function Stopped()
    local route = Journey.lastRoute
    Journey.lastRoute = nil
    if underway and route and route.dest then
        FG.Saved.SetResume(route.dest.name, { name = route.dest.name, mapID = route.dest.mapID, x = route.dest.x, y = route.dest.y }, route.stops)
    end
    underway = nil
end

FG.On("route:cleared", Stopped)

-- ==== quests in step with the route =========================================

local turnedIn = {}

-- The quest the route was started for, or nil to forget it. bindings: the quests a
-- trip's stops stand for, in order.
function Journey.Bind(binding, bindings)
    FG.char.binding, FG.char.bindings = binding, bindings
end

function Journey.Binding() return FG.char and FG.char.binding end

local function Stop()
    FG.char.binding = nil
    Bridge.Stop()
end

-- What a turn-in opens, once the game has caught up: offered, and never taken up for them.
local function OfferNext(questID)
    if not (FG.db.quests.offerNext and FG.QuestDB.Ready()) then return end
    local open = {}
    for _, id in ipairs(FG.QuestChain.Opens(questID)) do
        if FG.QuestStatus.Open(FG.QuestStatus.Of(id)) then open[#open + 1] = id end
    end
    if #open == 0 then return end
    FG.Journey.lastOpened = open
    FG.Emit("toast", L["QUEST_NEXT_IN_CHAIN_FMT"]:format(FG.QuestBrowse.NameOf(open[1])), nil,
        #open > 1 and L["QUEST_NEXT_MORE_FMT"]:format(#open - 1) or nil)
end

FG.OnEvent("QUEST_TURNED_IN", function(questID)
    turnedIn[questID] = GetTime()
    FG.After(1.5, function() OfferNext(questID) end)
    local binding = Journey.Binding()
    if binding and binding.questID == questID then
        FG.Emit("toast", L["QUEST_TURNED_IN"]:format(binding.title or "?"))
        if binding.kind == "turnin" or binding.kind == "marker" then Stop() else FG.char.binding = nil end
    end
end)

-- Picked up what the journey was for: nothing further to walk to, and a quest that is now
-- in the log, with places of its own to go to.
FG.OnEvent("QUEST_ACCEPTED", function(questID)
    local binding = Journey.Binding()
    if not (binding and binding.questID == questID and binding.kind == "start") then return end
    FG.Emit("toast", L["QUEST_ACCEPTED_FMT"]:format(binding.title or "?"))
    if #Bridge.StopsAhead(Bridge.ActiveRoute() or { steps = {} }) <= 1 then Stop() else FG.char.binding = nil end
end)

FG.OnEvent("QUEST_REMOVED", function(questID)
    local binding = Journey.Binding()
    if not (binding and binding.questID == questID) then return end
    local at = turnedIn[questID]
    if at and GetTime() - at < TURN_IN_WINDOW then return end
    FG.Emit("toast", L["QUEST_ABANDONED"]:format(binding.title or "?"))
    if Bridge.ActiveRoute() then Stop() else FG.char.binding = nil end
end)

-- What this quest needs next, as a line to offer; nil when nothing is left to go
-- to. Offered only: an unrelated route the player chose is never replaced.
function Journey.NextFor(q)
    if not FG.db.quests.offerNext then return nil end
    local target = FG.QuestTargets.FirstOpen(q, FG.QuestTargets.For(q))
    if not (target and target.status == "ok") then return nil end
    return target
end

-- An objective done while heading to it: no reason to keep going, and a good
-- moment to say what comes next.
FG.On("quests:changed", function()
    local binding = Journey.Binding()
    if not (binding and binding.kind == "objective" and Bridge.ActiveRoute()) then return end
    local q = Quests.Get(binding.questID)
    local objective = q and q.objectives[binding.index]
    if not (objective and objective.finished) then return end
    Stop()
    local following = Journey.NextFor(q)
    FG.Emit("toast", L["QUEST_OBJECTIVE_FINISHED"]:format(objective.text), following and q.questID or nil,
        following and L["QUEST_NEXT_FMT"]:format(following.text or "?") or nil)
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
local since, lastKey = 0, nil
local following                     -- the route being watched
local lastRide                      -- the ride last on the route: where it lands, and when
local notedAt = -math.huge

-- The engine replaced the route under way: says why, once in a while. A route
-- started on purpose announces itself and does not come through here.
local function NoteReroute()
    shownEta = nil
    local now = GetTime()
    local strayed = lastRide ~= nil and now - lastRide.at < RIDE_MEMORY and not Bridge.AtSpot(lastRide.arrive, LANDED_YARDS)
    lastRide = nil
    if not strayed and now - notedAt < REROUTE_NOTE_EVERY then return end
    notedAt = now
    FG.Emit("toast", L[strayed and "REROUTE_RIDE" or "REROUTE_PLAIN"], nil, nil, true)
end

local function Follow(view)
    local route = Bridge.Route()
    if following and route and route ~= following then NoteReroute() end
    following = route
    local step = view.step
    if step and step.arrive and (Kinds.IsRide(step) or step.kind == "portal") then
        lastRide = { arrive = step.arrive, at = GetTime() }
    end
    -- Landed where it should: whatever happens next is not the ride's doing.
    if lastRide and Bridge.AtSpot(lastRide.arrive, LANDED_YARDS) then lastRide = nil end
end

local function Publish()
    local view = Journey.View()
    if view then
        Journey.lastRoute = Bridge.Route()
        Follow(view)
        view.eta = Glide(view.eta)
    else
        following, lastRide, shownEta = nil, nil, nil
    end
    FG.Emit("journey:view", view)
    if not view then
        driver:SetScript("OnUpdate", nil)
        lastKey = nil
        return
    end
    -- A new step, or the same one changing hands: boarding, or landing.
    local key = view.index .. view.state
    if key ~= lastKey then
        lastKey = key
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

FG.On("route:started", function()
    following, shownEta = nil, nil
    Begin()
    Journey.Watch()
end)
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
    Bridge.HoldCharacterArrow(mode ~= "character")
    Bridge.ClaimGuiding(function() return FG.HUD ~= nil and FG.HUD.Guiding() end)
    FG.Emit("arrow:changed", mode)
end

FG.On("login", Journey.ApplyArrow)

function Journey.ArrowMode()
    local mode = FG.db.arrow
    if mode == "tomtom" and not FG.TomTom.Available() then return "hud" end
    return mode
end
