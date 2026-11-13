-- The journeys the addon exists for, end to end, on the real search, the real engine
-- and the real interface. Only the player's movement is pretend: each path goes from
-- typing to arriving, the way a person would.
local T = require("support.t")
local Stack = require("support.stack")

local QUESTIE = {
    areaMaps = { [12] = 1429, [40] = 1436 },
    npcs = {
        [299] = { name = "Young Wolf", spawns = { [12] = { { 43, 72 }, { 44, 73 } } } },
        [240] = { name = "Marshal Dughan", spawns = { [12] = { { 42.1, 65.9 } } } },
    },
    quests = { [33] = { name = "Wolves Across the Border", objectives = { { id = 299, text = "Young Wolf" } }, finisher = 240 } },
}

local function Log()
    return { { questID = 33, title = "Wolves Across the Border", level = 6, header = "Elwynn Forest",
               objectives = { { text = "Young Wolf slain: 3/8", numFulfilled = 3, numRequired = 8, finished = false } } } }
end

local function Start(opts)
    opts = opts or {}
    opts.screen = opts.screen or { 1920, 1080, 1.406 }
    opts.mapID, opts.x, opts.y = opts.mapID or 1453, opts.x or 0.6, opts.y or 0.6
    local c = Stack.new(opts)
    c.FG.db.autoClose = true
    return c
end

local function Ready(c)
    return Stack.Until(c, function()
        local p = c.FG.Planner.Current()
        return p and p.status == "ready"
    end, 30)
end

-- Types into the search box as a person does and waits out the debounce.
local function Search(c, text)
    local FG = c.FG
    FG.Window.Show("search")
    FG.SearchView.Query(text)
    c:Advance(0.6)
    return FG.SearchView._Results()
end

local function Reach(c, step)
    local p = step.arrive
    c:SetPlayer(p.m, p.x, p.y)
    c:Advance(2.2)
end

local function NoErrors(c, name)
    T.eq(#c.errors, 0, name .. ": no errors reached the handler: " .. tostring(c.errors[1]))
end

local tests = {}

-- A: Stormwind to Auberdine, across the sea.
function tests.goldenA_stormwindToAuberdine()
    local c = Start()
    local FG = c.FG
    local results = Search(c, "auberdine")
    T.ok(results[1], "found")
    T.has(results[1].name, "Auberdine")
    FG.SearchView.Open(results[1])
    T.ok(Ready(c), "planned")
    local plan = FG.Planner.Current()
    T.no(FG.Bridge.ActiveRoute(), "looking starts nothing")
    T.ok(plan.selected.total > 60, "a real journey")
    local kinds = {}
    for _, step in ipairs(plan.selected.steps) do kinds[#kinds + 1] = step.kind end
    T.has(table.concat(kinds, ","), "boat", "by boat")
    c.env.WorldMapFrame:Show()
    FG.MapPreview.Open()
    c:Advance(0.3)
    T.ok(FG.MapPreview._Lines().n > 0, "it shows on the map")
    c.env.WorldMapFrame:Hide()
    FG.RoutePanel.Go()
    c:Advance(1.5)
    T.no(FG.Window.IsShown(), "the window gets out of the way")
    local route = FG.Bridge.ActiveRoute()
    T.ok(route, "under way")
    T.ok(c.env.ForeverGPSHUD:IsVisible(), "the HUD leads")
    T.eq(FG.Journey.View().state, "moving", "walking to the dock")

    Reach(c, route.steps[1])
    c.ns.GPSBoats.Aboard = function() return false end
    c:Advance(0.5)
    local view = FG.Journey.View()
    T.eq(view.state, "waiting", "at the dock")
    T.no(view.leaves, "no time is made up")

    c.ns.GPSBoats.Aboard = function() return true end
    c.ns.GPSBoats.Carried = function() return true end
    c:Advance(0.5)
    T.eq(FG.Journey.View().state, "riding", "under way")

    c.ns.GPSBoats.Carried = function() return false end
    c.ns.GPSBoats.Aboard = function() return false end
    Reach(c, route.steps[2])
    T.eq(FG.Bridge.Route().active, 3, "landed: the last walk")
    local last = route.steps[3]
    c:SetPlayer(last.arrive.m, last.arrive.x, last.arrive.y)
    c:Advance(2.2)
    T.ok(FG.Bridge.Route().arrived, "arrived")
    T.eq(FG.Journey.View().state, "arrived")
    c:Advance(10)
    T.no(FG.Bridge.Route(), "and the route puts itself away")
    NoErrors(c, "A")
end

-- B: a quest objective, then what comes next, then the turn-in.
function tests.goldenB_aQuestFromObjectiveToTurnIn()
    local c = Start({ mapID = 1429, x = 0.45, y = 0.7, questie = QUESTIE, quests = Log() })
    local FG = c.FG
    FG.Window.Show("quests")
    FG.QuestsView.Toggle(33)
    T.ok(Stack.Until(c, function()
        for _, item in ipairs(FG.QuestsView.Get().list.items) do
            if item.kind == "target" and item.target.kind == "objective" and item.target.best then return true end
        end
    end, 10), "the objective is placed")
    local target
    for _, item in ipairs(FG.QuestsView.Get().list.items) do
        if item.kind == "target" and item.target.kind == "objective" then target = item end
    end
    FG.QuestsView.Go(target)
    T.ok(Ready(c), "planned")
    FG.Planner.Start()
    c:Advance(0.5)
    T.ok(FG.Bridge.ActiveRoute(), "under way")
    c.quests[1].complete = true
    c.quests[1].objectives[1] = { text = "Young Wolf slain: 8/8", numFulfilled = 8, numRequired = 8, finished = true }
    c:Fire("QUEST_LOG_UPDATE")
    c:Advance(1)
    T.no(FG.Bridge.ActiveRoute(), "the objective done, the walk to it is over")
    local toast = FG.HUD.ToastFrame()
    T.ok(toast:IsVisible(), "the next step is offered")
    T.has(toast.detail:GetText(), "Turn in", "the turn-in: " .. toast.detail:GetText())
    toast.action:Click()
    T.ok(Ready(c), "its route")
    T.has(FG.Planner.Current().target.name, "Marshal Dughan", "to the right person")
    FG.Planner.Start()
    c:Advance(0.5)
    T.ok(FG.Bridge.ActiveRoute(), "under way again")
    c.quests[1] = nil
    c:Fire("QUEST_TURNED_IN", 33)
    c:Fire("QUEST_REMOVED", 33)
    c:Advance(1)
    T.no(FG.Bridge.ActiveRoute(), "turned in: done")
    NoErrors(c, "B")
end

-- C: the nearest of a kind of service, by travel time.
function tests.goldenC_theNearestMailbox()
    local c = Start()
    local FG = c.FG
    local results = Search(c, "nearest mailbox")
    T.ok(#results > 0, "found")
    T.ok(Stack.Until(c, function() return FG.SearchView._Results()[1].eta ~= nil end, 10), "priced")
    results = FG.SearchView._Results()
    local first = results[1]
    for i = 2, #results do
        local other = results[i]
        if other.eta and first.eta then
            T.ok(first.eta.sec <= other.eta.sec + 0.01, "the first is the quickest to reach")
        end
    end
    FG.SearchView.Open(first)
    T.ok(Ready(c), "planned")
    FG.Planner.Start()
    c:Advance(1)
    local route = FG.Bridge.ActiveRoute()
    T.ok(route, "under way")
    local last = route.steps[#route.steps]
    c:SetPlayer(last.arrive.m, last.arrive.x, last.arrive.y)
    c:Advance(2.2)
    T.ok(FG.Bridge.Route().arrived, "there")
    NoErrors(c, "C")
end

-- D: off the route, without flapping, and saying why.
function tests.goldenD_offTheRoute()
    local c = Start()
    local FG = c.FG
    FG.Planner.Inspect({ data = { name = "Goldshire", mapID = 1429, x = 0.42, y = 0.65 }, name = "Goldshire" })
    T.ok(Ready(c), "planned")
    FG.Planner.Start()
    c:Advance(1.5)
    local rebuilt, said = 0, 0
    local real = c.ns.GPS.Rerouted
    c.ns.GPS.Rerouted = function(...)
        rebuilt = rebuilt + 1
        return real(...)
    end
    FG.On("toast", function() said = said + 1 end)
    c:SetPlayer(1429, 0.8, 0.8)
    T.ok(Stack.Until(c, function() return rebuilt > 0 end, 20), "a new route from here")
    c:Advance(10)
    T.ok(rebuilt <= 2, "and it settles: rebuilt " .. rebuilt)
    T.ok(said >= 1 and said <= 1, "one word on it, not many: " .. said)
    T.eq(FG.Bridge.ActiveRoute().dest.name, "Goldshire", "to the same place")
    NoErrors(c, "D")
end

-- E: what is not known is said, and nothing is invented.
function tests.goldenE_whenDataIsMissing()
    local c = Start({ mapID = 1429, x = 0.45, y = 0.7, quests = Log() })
    local FG = c.FG
    FG.Window.Show("quests")
    FG.QuestsView.Toggle(33)
    c:Advance(1)
    local note, offered = nil, false
    for _, item in ipairs(FG.QuestsView.Get().list.items) do
        if item.kind == "note" then note = item.text end
        if item.kind == "target" and item.target.best then offered = true end
    end
    T.has(note, "Questie", "without Questie, it says so")
    T.no(offered, "and offers no route it cannot back up")
    FG.Search.Run("xyzzy nowhere", "all")
    local results = Search(c, "xyzzy nowhere")
    T.eq(#results, 0, "nothing found is nothing shown")
    -- Where the game reports no position, as inside an instance.
    c.env.C_Map.GetPlayerMapPosition = function() return nil end
    FG.Planner.Inspect({ data = { name = "Goldshire", mapID = 1429, x = 0.42, y = 0.65 }, name = "Goldshire" })
    c:Advance(0.3)
    local plan = FG.Planner.Current()
    T.eq(plan.status, "failed", "no route from nowhere")
    T.has(plan.message, "position", "and it says why: " .. tostring(plan.message))
    NoErrors(c, "E")
end

-- F: a look at somewhere else leaves the journey under way exactly as it was.
function tests.goldenF_aRouteUnderWayPlusAPreview()
    local c = Start()
    local FG = c.FG
    FG.Planner.Inspect({ data = { name = "Auberdine", mapID = 1439, x = 0.37, y = 0.44 }, name = "Auberdine" })
    T.ok(Ready(c), "planned")
    FG.Planner.Start()
    T.ok(Stack.Until(c, function() return FG.Bridge.ActiveRoute().others ~= nil end, 60), "settled")
    local route = FG.Bridge.ActiveRoute()
    local before = { route = route, active = route.active, dest = route.dest.name, steps = #route.steps, epoch = c.ns.GPSNav.epoch,
                     title = FG.Journey.View().title, avoid = route.wayAvoid }
    c.env.WorldMapFrame:Show()
    FG.Planner.Inspect({ data = { name = "Darkshire", mapID = 1431, x = 0.75, y = 0.45 }, name = "Darkshire" })
    T.ok(Ready(c), "the other journey is worked out")
    FG.MapPreview.Open()
    for _, option in ipairs(FG.Planner.Current().options) do
        if option.steps and not option.noWay and not option.same then FG.Planner.Select(option) end
    end
    c:Advance(1)
    T.ok(FG.Bridge.ActiveRoute() == before.route, "the same route")
    T.eq(FG.Bridge.ActiveRoute().active, before.active, "on the same step")
    T.eq(FG.Bridge.ActiveRoute().dest.name, before.dest, "to the same place")
    T.eq(#FG.Bridge.ActiveRoute().steps, before.steps)
    T.eq(c.ns.GPSNav.epoch, before.epoch, "the walking grid untouched")
    T.eq(FG.Journey.View().title, before.title, "the HUD says the same")
    FG.Planner.Clear()
    c:Advance(0.5)
    T.ok(FG.Bridge.ActiveRoute() == before.route, "and leaving the preview changes nothing either")
    NoErrors(c, "F")
end

return tests
