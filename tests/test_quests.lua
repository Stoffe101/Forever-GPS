-- From Your Quests: the log as the client gives it, Questie's places through
-- the real EasyFind_Questie extension, and what happens with neither.
local T = require("support.t")
local Stack = require("support.stack")

local QUESTIE = {
    areaMaps = { [12] = 1429, [40] = 1436, [148] = 1439, [999] = 2999 },
    npcs = {
        [299] = { name = "Young Wolf", spawns = { [12] = { { 43, 72 }, { 44, 73 } }, [40] = { { 58, 22 } } } },
        [38] = { name = "Defias Thug", spawns = { [12] = { { 52, 60 } } } },
        [240] = { name = "Marshal Dughan", spawns = { [12] = { { 42.1, 65.9 } } } },
        [777] = { name = "Far Wolf", spawns = { [148] = { { 40, 40 } }, [12] = { { 90, 90 } } } },
    },
    quests = {
        [1] = { name = "Two Things", objectives = { { id = 299, text = "Young Wolf" }, { id = 38, text = "Defias Thug" } }, finisher = 240 },
        [2] = { name = "No Places", objectives = { { id = 5555, text = "Ghost" } }, finisher = 5556 },
        [3] = { name = "Done Already", objectives = { { id = 38, text = "Defias Thug" } }, finisher = 240 },
        [4] = { name = "Across the Sea", objectives = { { id = 777, text = "Far Wolf" } }, finisher = 240 },
    },
}

local function Obj(text, have, need, done)
    return { text = text, numFulfilled = have, numRequired = need, finished = done or false, type = "monster" }
end

local function Log()
    return {
        { questID = 1, title = "Two Things", level = 6, header = "Elwynn Forest",
          objectives = { Obj("Young Wolf slain: 3/8", 3, 8), Obj("Defias Thug slain: 0/4", 0, 4) } },
        { questID = 2, title = "No Places", level = 7, objectives = { Obj("Ghost seen: 0/1", 0, 1) } },
        { questID = 3, title = "Done Already", level = 5, header = "Westfall", complete = true,
          objectives = { Obj("Defias Thug slain: 4/4", 4, 4, true) } },
    }
end

local function Start(opts)
    opts = opts or {}
    if opts.ui == nil then opts.ui = false end
    opts.mapID, opts.x, opts.y = opts.mapID or 1429, opts.x or 0.45, opts.y or 0.7
    opts.quests = opts.quests or Log()
    return Stack.new(opts)
end

local function WithQuestie(opts)
    opts = opts or {}
    opts.questie = QUESTIE
    return Start(opts)
end

local function Resolved(c, target)
    local done
    c.FG.QuestTargets.Resolve(target, function() done = true end)
    T.ok(Stack.Until(c, function() return done end, 10), "resolved")
    return target
end

local tests = {}

function tests.theLog_isReadWithHeadersLevelsAndProgress()
    local c = Start()
    local all = c.FG.Quests.All()
    T.eq(#all, 3, "headers are not quests")
    T.eq(all[1].title, "Two Things")
    T.eq(all[1].level, 6)
    T.eq(all[1].zone, "Elwynn Forest", "under its header")
    T.eq(all[3].zone, "Westfall")
    T.eq(#all[1].objectives, 2)
    T.eq(all[1].objectives[1].have, 3)
    T.eq(all[1].objectives[1].need, 8)
end

function tests.status_saysWhatIsLeft()
    local c = Start()
    local Q = c.FG.Quests
    T.eq((Q.Status(Q.Get(1))), "2 objectives left")
    T.eq((Q.Status(Q.Get(2))), "1 objective left")
    T.eq((Q.Status(Q.Get(3))), "Ready to turn in")
    T.near(Q.Progress(Q.Get(1)), 0.1875, 0.001, "by each objective's share")
    T.eq(Q.Progress(Q.Get(3)), 1)
end

function tests.aFailedQuest_saysSo()
    local log = Log()
    log[2].failed = true
    local c = Start({ quests = log })
    T.eq(select(2, c.FG.Quests.Status(c.FG.Quests.Get(2))), "failed")
end

function tests.anEmptyLog_isNoError()
    local c = Start({ quests = {} })
    T.eq(#c.FG.Quests.All(), 0)
    T.eq(#c.errors, 0)
end

function tests.aHiddenQuest_isLeftOut()
    local log = Log()
    log[2].hidden = true
    local c = Start({ quests = log })
    T.eq(#c.FG.Quests.All(), 2)
    T.no(c.FG.Quests.Get(2), "hidden")
end

function tests.changes_areReadOnceAfterABurst()
    local c = Start()
    local Q = c.FG.Quests
    Q.All()
    local reads = 0
    local real = c.env.C_QuestLog.GetNumQuestLogEntries
    c.env.C_QuestLog.GetNumQuestLogEntries = function()
        reads = reads + 1
        return real()
    end
    local topics = 0
    c.FG.On("quests:changed", function()
        topics = topics + 1
        Q.All()
    end)
    for _ = 1, 40 do c:Fire("QUEST_LOG_UPDATE") end
    c:Advance(1)
    T.eq(topics, 1, "forty updates in one frame, one change")
    T.ok(reads <= 2, "and the log is read only then, not per event: " .. reads)
end

function tests.everyUnfinishedObjective_isOfferedNotJustTheFirst()
    local c = WithQuestie()
    local targets = c.FG.QuestTargets.For(c.FG.Quests.Get(1))
    T.eq(#targets.objectives, 2, "both objectives")
    T.eq(targets.objectives[1].status, "ok")
    T.eq(targets.objectives[2].status, "ok")
    Resolved(c, targets.objectives[1])
    Resolved(c, targets.objectives[2])
    T.ok(targets.objectives[1].best, "the wolves have a place")
    T.ok(targets.objectives[2].best, "and so do the thugs: not forced into the first")
    T.ok(targets.objectives[1].best.spot.x ~= targets.objectives[2].best.spot.x, "and they are different places")
end

function tests.aFinishedObjective_isMarkedDone()
    local log = Log()
    log[1].objectives[1] = Obj("Young Wolf slain: 8/8", 8, 8, true)
    local c = WithQuestie({ quests = log })
    local targets = c.FG.QuestTargets.For(c.FG.Quests.Get(1))
    T.ok(targets.objectives[1].done, "done")
    T.no(targets.objectives[2].done, "the other is not")
    T.eq(c.FG.QuestTargets.FirstOpen(c.FG.Quests.Get(1), targets), targets.objectives[2], "and the next to do skips it")
end

function tests.aDoneQuest_leadsToTheTurnIn()
    local c = WithQuestie()
    local q = c.FG.Quests.Get(3)
    local targets = c.FG.QuestTargets.For(q)
    local first = c.FG.QuestTargets.FirstOpen(q, targets)
    T.eq(first, targets.turnIn, "the turn-in")
    T.has(first.text, "Marshal Dughan", "names who")
    Resolved(c, first)
    T.eq(first.best.zone, "Elwynn Forest")
end

function tests.spawns_areGroupedAndTheClosestByTravelLeads()
    local c = WithQuestie()
    local targets = c.FG.QuestTargets.For(c.FG.Quests.Get(1))
    local wolves = Resolved(c, targets.objectives[1])
    T.eq(wolves.spotCount, 3, "three spawns")
    T.eq(#wolves.areas, 2, "two areas: Elwynn and Westfall")
    T.eq(wolves.best.zone, "Elwynn Forest", "the near one")
    T.eq(wolves.basis, "travel", "by the route engine's time")
end

function tests.closestByTravelTime_beatsClosestOnAStraightLine()
    -- A spawn across the sea, closer as the crow flies than a far one on land,
    -- is exactly what straight-line choice gets wrong.
    local log = { { questID = 4, title = "Across the Sea", level = 6, objectives = { Obj("Far Wolf slain: 0/1", 0, 1) } } }
    local c = WithQuestie({ quests = log, mapID = 1439, x = 0.36, y = 0.44 })
    local target = c.FG.QuestTargets.For(c.FG.Quests.Get(4)).objectives[1]
    Resolved(c, target)
    T.eq(target.best.zone, "Darkshore", "the one on this side of the sea")
    T.ok(target.best.sec < 600, "and priced as a walk, not a voyage")
end

function tests.noLocation_isSaidAndNoRouteInvented()
    local c = WithQuestie()
    local targets = c.FG.QuestTargets.For(c.FG.Quests.Get(2))
    local target = targets.objectives[1]
    T.eq(target.status, "none")
    T.has(target.reason, "No reliable location", "says so")
    Resolved(c, target)
    T.no(target.best, "no destination at all")
end

function tests.withoutQuestie_theLogStillWorks()
    local c = Start()
    T.no(c.FG.QuestTargets.HasQuestie(), "Questie is not here")
    local q = c.FG.Quests.Get(1)
    local targets = c.FG.QuestTargets.For(q)
    T.eq(targets.source, "game")
    T.eq(#targets.objectives, 2, "objectives still listed")
    T.eq(targets.objectives[1].status, "none")
    T.has(targets.objectives[1].reason, "Questie", "and it says what would help")
    T.eq(#c.errors, 0)
end

function tests.withoutQuestie_theGamesMarkerIsUsed()
    local log = Log()
    log[1].poi = { mapID = 1429, x = 0.42, y = 0.66 }
    local c = Start({ quests = log })
    local q = c.FG.Quests.Get(1)
    local targets = c.FG.QuestTargets.For(q)
    T.ok(targets.marker, "the game's own mark")
    T.eq(targets.marker.status, "ok")
    T.eq(c.FG.QuestTargets.FirstOpen(q, targets), targets.marker)
end

function tests.withoutQuestie_aDoneQuestsMarkerIsItsTurnIn()
    local log = Log()
    log[3].poi = { mapID = 1429, x = 0.42, y = 0.66 }
    local c = Start({ quests = log })
    local q = c.FG.Quests.Get(3)
    local targets = c.FG.QuestTargets.For(q)
    T.eq(targets.turnIn, targets.marker, "the mark is where it is handed in")
end

function tests.questieInstalledButNotReady_fallsBackQuietly()
    local c = Start({})
    T.no(c.FG.QuestTargets.HasQuestie())
    T.eq(c.FG.QuestTargets.For(c.FG.Quests.Get(1)).source, "game")
    T.eq(#c.errors, 0)
end

function tests.aQuestRoute_plansAndCarriesItsQuest()
    local c = WithQuestie()
    local q = c.FG.Quests.Get(1)
    local target = c.FG.QuestTargets.For(q).objectives[2]
    Resolved(c, target)
    local dest = c.FG.QuestTargets.Destination(q, target, target.best)
    T.has(dest.name, "Two Things", "the quest's name")
    c.FG.Planner.Inspect(dest)
    T.ok(Stack.Until(c, function() return c.FG.Planner.Current().status == "ready" end, 20), "planned")
    c.FG.Planner.Start()
    local bound = c.FG.Journey.Binding()
    T.eq(bound.questID, 1)
    T.eq(bound.kind, "objective")
    T.eq(bound.index, 2)
    T.eq(#c.FG.Saved.Recents(), 0, "quests stay out of the recent list")
end

local function Under(c, questID, index)
    local q = c.FG.Quests.Get(questID)
    local targets = c.FG.QuestTargets.For(q)
    local target = index and targets.objectives[index] or targets.turnIn
    Resolved(c, target)
    c.FG.Planner.Inspect(c.FG.QuestTargets.Destination(q, target, target.best))
    Stack.Until(c, function() return c.FG.Planner.Current().status == "ready" end, 20)
    c.FG.Planner.Start()
    c:Advance(0.5)
end

function tests.abandoningTheQuest_stopsItsRoute()
    local c = WithQuestie({ ui = true })
    Under(c, 1, 1)
    T.ok(c.FG.Bridge.ActiveRoute(), "under way")
    table.remove(c.quests, 1)
    c:Fire("QUEST_REMOVED", 1)
    c:Advance(1)
    T.no(c.FG.Bridge.ActiveRoute(), "stopped")
    T.no(c.FG.Journey.Binding(), "and forgotten")
    local said = table.concat(c.printed, "\n")
    T.has(said, "no longer in your quest log", "and it says why")
end

function tests.turningIn_doesNotReadAsAbandoning()
    local c = WithQuestie({ ui = true })
    Under(c, 3)
    c:Fire("QUEST_TURNED_IN", 3)
    table.remove(c.quests, 3)
    c:Fire("QUEST_REMOVED", 3)
    c:Advance(1)
    T.no(c.FG.Bridge.ActiveRoute(), "the turn-in route is finished")
    T.lacks(table.concat(c.printed, "\n"), "no longer in your quest log", "not called abandoned")
end

function tests.anUnrelatedQuestLeaving_changesNothing()
    local c = WithQuestie()
    Under(c, 1, 1)
    table.remove(c.quests, 2)
    c:Fire("QUEST_REMOVED", 2)
    c:Advance(1)
    T.ok(c.FG.Bridge.ActiveRoute(), "still going")
end

function tests.finishingTheObjective_endsTheWalkToIt()
    local c = WithQuestie({ ui = true })
    Under(c, 1, 1)
    c.quests[1].objectives[1] = Obj("Young Wolf slain: 8/8", 8, 8, true)
    c:Fire("QUEST_LOG_UPDATE")
    c:Advance(1)
    T.no(c.FG.Bridge.ActiveRoute(), "no reason to keep going")
    T.has(table.concat(c.printed, "\n"), "Objective done", "and it says so")
end

local function Browser(opts)
    opts = opts or {}
    opts.screen = opts.screen or { 1920, 1080, 1 }
    opts.ui, opts.questie = true, QUESTIE
    local c = Start(opts)
    c.FG.Window.Show("quests")
    c:Advance(0.5)
    return c, c.FG.QuestsView
end

local function ShownTitles(view)
    local out = {}
    for _, item in ipairs(view.Get().list.items) do
        if item.kind == "quest" then out[#out + 1] = item.quest.title end
    end
    return out
end

function tests.theBrowser_filters()
    local c, view = Browser()
    T.eq(#ShownTitles(view), 3, "all to begin with")
    view.SetFilter("ready")
    T.eq(table.concat(ShownTitles(view), ","), "Done Already")
    view.SetFilter("missing")
    T.eq(table.concat(ShownTitles(view), ","), "No Places")
    view.SetFilter("nearby")
    T.has(table.concat(ShownTitles(view), ","), "Two Things", "wolves are close")
    view.SetFilter("other")
    T.lacks(table.concat(ShownTitles(view), ","), "Two Things", "and not elsewhere")
    view.SetFilter("all")
    T.eq(#c.errors, 0)
end

function tests.theBrowser_groups()
    local _, view = Browser()
    T.eq(view.Grouping(), "zone")
    view.NextGrouping()
    T.eq(view.Grouping(), "status")
    local headings = {}
    for _, item in ipairs(view.Get().list.items) do
        if item.kind == "zone" then headings[#headings + 1] = item.text end
    end
    T.ok(#headings > 0, "under headings")
    view.NextGrouping()
    T.eq(view.Grouping(), "distance")
    view.NextGrouping()
    T.eq(view.Grouping(), "zone", "and back round")
end

function tests.thingsCloseBy_areOfferedAsACircuit()
    local c, view = Browser()
    local items = view.Get().list.items
    local banner
    for _, item in ipairs(items) do
        if item.kind == "circuit" then banner = item end
    end
    T.ok(banner, "the browser offers it")
    T.ok(banner.count >= 2, "with how many: " .. tostring(banner.count))
    c.FG.Trip.PlanNearby()
    T.ok(Stack.Until(c, function()
        local p = c.FG.Planner.Current()
        return p and p.status == "ready"
    end, 60), "and one click plans it")
    T.ok(c.FG.Planner.Current().stops, "as a trip")
    T.no(c.FG.Bridge.ActiveRoute(), "which it does not start")
end

function tests.anObjectiveInsideAnInstance_goesToItsDoor()
    local c = Start({ ui = false, questie = QUESTIE })
    local B = c.FG.Bridge
    local Places = B.SearchPlaces
    B.SearchPlaces = function(text)
        if text == "The Deadmines" then return { { name = "The Deadmines", isDungeonEntrance = true, mapID = 1436, x = 0.42, y = 0.72, category = "dungeon" } } end
        return Places(text)
    end
    local Can = B.CanNavigate
    B.CanNavigate = function(row) return row.isDungeonEntrance == true or (row.zone == nil and Can(row)) end
    local t = { status = "ok", areas = { { spot = { mapID = 756, x = 0.5, y = 0.5 }, zone = "The Deadmines", ci = 0, wx = 0, wy = 0, n = 1, routable = false } } }
    local done
    c.FG.QuestTargets.Resolve(t, function() done = true end)
    T.ok(done, "settled")
    T.eq(t.status, "ok", "with somewhere to go")
    T.ok(t.entrance, "its door")
    T.has(t.best.zone, "entrance", "and it says so")
end

function tests.progress_doesNotRescanEveryQuest()
    local c, view = Browser()
    local calls = 0
    local For = c.FG.QuestTargets.For
    c.FG.QuestTargets.For = function(...)
        calls = calls + 1
        return For(...)
    end
    c.quests[1].objectives[1].numFulfilled = 1
    c:Fire("QUEST_LOG_UPDATE")
    c:Advance(1)
    view.Refresh(true)
    T.eq(calls, 0, "a counter moving changes no quest's places")
end

function tests.questie_arrivingLater_isPickedUp()
    local c = Start({ screen = { 1920, 1080, 1 }, ui = true, questie = QUESTIE, questieLate = true })
    c.FG.Window.Show("quests")
    c:Advance(0.5)
    T.has(c.FG.QuestsView.Get().list.items[1].text or "", "Questie", "without it, it says so")
    c:QuestieReady()
    c.FG.Window.Show("quests")
    c:Advance(0.5)
    T.lacks(c.FG.QuestsView.Get().list.items[1].text or "", "Questie", "and with it, it stops saying so")
end

return tests
