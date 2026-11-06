-- Quest Circuit and trips: the order is ours, the routing is EasyFind GPS's.
local T = require("support.t")
local Stack = require("support.stack")

local QUESTIE = {
    areaMaps = { [12] = 1429, [40] = 1436 },
    npcs = {
        [1] = { name = "Near Thing", spawns = { [12] = { { 42, 66 } } } },
        [2] = { name = "Far Thing", spawns = { [40] = { { 56, 47 } } } },
        [3] = { name = "Mid Thing", spawns = { [12] = { { 30, 70 } } } },
        [9] = { name = "Marshal Dughan", spawns = { [12] = { { 42.1, 65.9 } } } },
    },
    quests = {
        [1] = { name = "Three Things", objectives = { { id = 1, text = "Near" }, { id = 2, text = "Far" }, { id = 3, text = "Mid" } }, finisher = 9 },
    },
}

local function Obj(text)
    return { text = text, numFulfilled = 0, numRequired = 1, finished = false }
end

local function Log()
    return { { questID = 1, title = "Three Things", level = 6, header = "Elwynn Forest",
               objectives = { Obj("Near: 0/1"), Obj("Far: 0/1"), Obj("Mid: 0/1") } } }
end

local function Start(opts)
    opts = opts or {}
    opts.mapID, opts.x, opts.y = opts.mapID or 1429, opts.x or 0.45, opts.y or 0.7
    opts.questie, opts.quests = opts.questie or QUESTIE, opts.quests or Log()
    return Stack.new(opts)
end

local function Stop(name, mapID, x, y, binding)
    return { name = name, mapID = mapID, x = x, y = y, binding = binding }
end

-- A cost from a table of points on a line.
local function Line(points)
    return function(a, b) return math.abs(points[a] - points[b]) end
end

local tests = {}

function tests.anOrder_visitsEachStopOnce()
    local c = Start({ ui = false })
    local points = { [0] = 0, 30, 10, 20 }
    local order = c.FG.Trip.Order(3, Line(points))
    T.eq(table.concat(order, ","), "2,3,1", "out along the line")
end

function tests.nearestFirst_isImprovedOn()
    -- Nearest-first goes to 1 and must then come back past the start; going the
    -- other way round first is shorter overall.
    local c = Start({ ui = false })
    local points = { [0] = 0, -1, 2, 3, 4 }
    local cost = Line(points)
    local order = c.FG.Trip.Order(4, cost)
    local total, from = 0, 0
    for _, stop in ipairs(order) do
        total = total + cost(from, stop)
        from = stop
    end
    T.ok(total <= 6, "a short way round: " .. total)
end

function tests.aTurnIn_comesAfterWhatItIsFor()
    local c = Start({ ui = false })
    local order = c.FG.Trip.Order(3, Line({ [0] = 0, 10, 20, 1 }), { [2] = 3 })
    local at = {}
    for pos, stop in ipairs(order) do at[stop] = pos end
    T.ok(at[2] < at[3], "stop 2 before stop 3, though 3 is nearest: " .. table.concat(order, ","))
end

function tests.ordering_isFastEnoughToNotNotice()
    local c = Start({ ui = false })
    local cost = function(a, b) return ((a * 7 + b * 13) % 17) + 1 end
    local started = os.clock()
    c.FG.Trip.Order(8, cost)
    T.ok(os.clock() - started < 0.05, "eight stops")
end

function tests.stops_canBeAddedMovedAndRemoved()
    local c = Start({ ui = false })
    local Trip = c.FG.Trip
    T.ok(Trip.Add(Stop("A", 1429, 0.4, 0.6)))
    T.no(Trip.Add(Stop("A", 1429, 0.4, 0.6)), "not twice")
    Trip.Add(Stop("B", 1429, 0.5, 0.6))
    Trip.Add(Stop("C", 1429, 0.6, 0.6))
    Trip.Move(3, 1)
    T.eq(Trip.List()[1].name, "C", "moved")
    Trip.Remove(1)
    T.eq(Trip.Count(), 2)
    Trip.Clear()
    T.eq(Trip.Count(), 0)
end

function tests.aTrip_hasALimit()
    local c = Start({ ui = false })
    local Trip = c.FG.Trip
    for i = 1, 8 do T.ok(Trip.Add(Stop("S" .. i, 1429, i / 10, 0.5))) end
    local ok, why = Trip.Add(Stop("Too many", 1429, 0.95, 0.5))
    T.no(ok, "the ninth is refused")
    T.ok(why, "and says why")
end

function tests.optimizing_usesRealTravelTimes()
    local c = Start({ ui = false })
    local Trip = c.FG.Trip
    Trip.Add(Stop("Westfall", 1436, 0.56, 0.47))
    Trip.Add(Stop("Close by", 1429, 0.44, 0.68))
    local done
    Trip.Optimize(function() done = true end)
    T.ok(Stack.Until(c, function() return done end, 20), "settles in later frames")
    T.eq(Trip.List()[1].name, "Close by", "the near stop first")
end

function tests.aTrip_plansAsOneJourney()
    local c = Start({ ui = false })
    local Trip, P = c.FG.Trip, c.FG.Planner
    Trip.Add(Stop("Close by", 1429, 0.44, 0.68))
    Trip.Add(Stop("Westfall", 1436, 0.56, 0.47))
    Trip.Preview()
    T.ok(Stack.Until(c, function() return P.Current().status == "ready" end, 40), "planned")
    local plan = P.Current()
    T.ok(plan.stops and #plan.stops == 2, "both stops")
    T.ok(plan.selected.total > 0)
    local stopsSeen = 0
    for _, step in ipairs(plan.selected.steps) do
        if step.tripStop then stopsSeen = stopsSeen + 1 end
    end
    T.eq(stopsSeen, 2, "each leg ends at its stop")
    P.Start()
    c:Advance(0.5)
    local route = c.FG.Bridge.ActiveRoute()
    T.ok(route and route.stops and #route.stops == 2, "and runs as a trip")
end

local function Under(c)
    local Q = c.FG.QuestTargets
    local q = c.FG.Quests.Get(1)
    local targets = Q.For(q)
    local Trip = c.FG.Trip
    for i = 1, 3 do
        local t = targets.objectives[i]
        local done
        Q.Resolve(t, function() done = true end)
        T.ok(Stack.Until(c, function() return done end, 10), "resolved")
        local dest = Q.Destination(q, t, t.best)
        local stop = dest.data
        stop.name, stop.binding = dest.name, dest.binding
        Trip.Add(stop)
    end
    Trip.Preview()
    T.ok(Stack.Until(c, function() return c.FG.Planner.Current().status == "ready" end, 40), "planned")
    c.FG.Planner.Start()
    c:Advance(1)
end

function tests.aFinishedObjective_dropsOutOfTheTrip()
    local c = Start({ ui = false })
    Under(c)
    local route = c.FG.Bridge.ActiveRoute()
    T.eq(#route.stops, 3, "three stops")
    c.quests[1].objectives[2] = { text = "Far: 1/1", numFulfilled = 1, numRequired = 1, finished = true }
    c:Fire("QUEST_LOG_UPDATE")
    T.ok(Stack.Until(c, function()
        local now = c.FG.Bridge.ActiveRoute()
        return now and now ~= route
    end, 30), "replanned without it")
    local now = c.FG.Bridge.ActiveRoute()
    T.eq(#now.stops, 2, "two left")
    for _, s in ipairs(now.stops) do T.lacks(s.name, "Far", "the done stop is gone") end
end

function tests.skippingAStop_goesOnToTheNext()
    local c = Start({ ui = false })
    Under(c)
    local route = c.FG.Bridge.ActiveRoute()
    local first = c.FG.Trip.NextStop()
    T.ok(first, "a next stop")
    c.FG.Trip.SkipStop(1)
    T.ok(Stack.Until(c, function()
        local now = c.FG.Bridge.ActiveRoute()
        return now and now ~= route
    end, 30), "replanned")
    T.ok(c.FG.Trip.NextStop().name ~= first.name, "it moved on")
end

function tests.finishingAnObjective_offersWhatComesNext()
    local c = Start()
    local q = c.FG.Quests.Get(1)
    local Q = c.FG.QuestTargets
    local target = Q.For(q).objectives[1]
    local done
    Q.Resolve(target, function() done = true end)
    Stack.Until(c, function() return done end, 10)
    c.FG.Planner.Inspect(Q.Destination(q, target, target.best))
    Stack.Until(c, function() return c.FG.Planner.Current().status == "ready" end, 30)
    c.FG.Planner.Start()
    c:Advance(0.5)
    c.quests[1].objectives[1] = { text = "Near: 1/1", numFulfilled = 1, numRequired = 1, finished = true }
    c:Fire("QUEST_LOG_UPDATE")
    c:Advance(1)
    T.no(c.FG.Bridge.ActiveRoute(), "the walk to it is over")
    local hud = c.env.ForeverGPSHUD
    T.ok(hud.toast:IsShown(), "something is offered")
    T.has(hud.toast.text:GetText(), "Next:", "what comes next")
    T.ok(hud.toast.action:IsShown(), "with a button, not a change of route")
    T.no(c.FG.Bridge.Route(), "nothing started by itself")
end

function tests.aSearchResult_canBecomeAStop()
    local c = Start({ ui = false })
    local Trip = c.FG.Trip
    local stop = Trip.FromTarget({ data = { name = "Westfall", mapID = 1436, x = 0.5, y = 0.5 }, name = "Westfall", subtitle = "Zone" })
    T.ok(stop, "a stop")
    T.eq(stop.mapID, 1436)
    T.ok(Trip.Add(stop))
    T.ok(Trip.Has(stop), "on the trip")
end

function tests.aTrip_onScreen()
    local c = Start({ screen = { 1920, 1080, 1 } })
    local FG = c.FG
    FG.Window.Show("trip")
    c:Advance(0.2)
    local view = FG.TripView.Get()
    T.no(view.plan:IsEnabled(), "nothing to plan yet")
    FG.Trip.Add(Stop("Close by", 1429, 0.44, 0.68))
    FG.Trip.Add(Stop("Westfall", 1436, 0.56, 0.47))
    c:Advance(0.2)
    T.ok(view.plan:IsEnabled(), "two stops to plan")
    T.ok(view.order:IsEnabled(), "and an order to find")
    local rows = 0
    for _ in ipairs(view.list.shown) do rows = rows + 1 end
    T.eq(rows, 2, "a row for each stop")
    view.plan:Click()
    T.ok(Stack.Until(c, function()
        local p = FG.Planner.Current()
        return p and p.status == "ready"
    end, 40), "planned from the button")
end

function tests.anUnrelatedRoute_isNeverReplacedByASuggestion()
    local c = Start()
    c.FG.Planner.Inspect({ data = { name = "Westfall", mapID = 1436, x = 0.5, y = 0.5 }, name = "Westfall" })
    Stack.Until(c, function() return c.FG.Planner.Current().status == "ready" end, 30)
    c.FG.Planner.Start()
    c:Advance(0.5)
    local route = c.FG.Bridge.ActiveRoute()
    c.quests[1].objectives[1] = { text = "Near: 1/1", numFulfilled = 1, numRequired = 1, finished = true }
    c:Fire("QUEST_LOG_UPDATE")
    c:Advance(1)
    T.ok(c.FG.Bridge.ActiveRoute() == route, "it was not for that quest, so it stands")
end

return tests
