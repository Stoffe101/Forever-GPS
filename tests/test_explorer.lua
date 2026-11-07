-- The Quest Explorer's facts: finding quests, what a character can take, what leads to
-- what, and where a quest starts. Questie is a stand-in that follows its rules. The real
-- database is checked by hand: docs/QUEST_EXPLORER.md says what was measured.
local T = require("support.t")
local Stack = require("support.stack")

local QUESTIE = {
    areaMaps = { [12] = 1429, [40] = 1436, [148] = 1439, [999] = 2999 },
    npcs = {
        [240] = { name = "Marshal Dughan", zoneID = 12, spawns = { [12] = { { 42.1, 65.9 } } } },
        [241] = { name = "Remy Two Times", zoneID = 12, spawns = { [12] = { { 42.1, 67.2 } } } },
        [242] = { name = "Scribe of Auberdine", zoneID = 148, spawns = { [148] = { { 37, 44 } } } },
        [243] = { name = "Hidden Giver", zoneID = 12 },
        [244] = { name = "Young Wolf", zoneID = 12, spawns = { [12] = { { 43, 72 } } } },
        [245] = { name = "Bad Coordinates", zoneID = 12, spawns = { [12] = { { -1, -1 } } } },
    },
    objects = {
        [500] = { name = "Wanted Poster", zoneID = 12, spawns = { [12] = { { 42, 66 } } } },
    },
    items = {
        [600] = { name = "Bloodstained Letter", npcDrops = { 244 } },
        [601] = { name = "Mysterious Letter" },
    },
    quests = {
        [10] = { name = "First Steps", starter = 240, finisher = 240, questLevel = 1, requiredLevel = 1, zoneOrSort = 12,
                 nextQuestInChain = 11, objectivesText = { "Speak to the marshal." } },
        [11] = { name = "The Middle", starter = 240, finisher = 241, questLevel = 2, requiredLevel = 1, zoneOrSort = 12,
                 preQuestSingle = { 10 }, nextQuestInChain = 12 },
        [12] = { name = "The End", starter = 241, finisher = 241, questLevel = 3, requiredLevel = 1, zoneOrSort = 12, preQuestSingle = { 11 } },

        [20] = { name = "Left Fork", starter = 240, finisher = 240, questLevel = 5, requiredLevel = 1, zoneOrSort = 12 },
        [21] = { name = "Right Fork", starter = 241, finisher = 240, questLevel = 5, requiredLevel = 1, zoneOrSort = 12 },
        [22] = { name = "Either Way", starter = 240, finisher = 240, questLevel = 6, requiredLevel = 1, zoneOrSort = 12, preQuestSingle = { 20, 21 } },

        [30] = { name = "Both Needed", starter = 240, finisher = 240, questLevel = 6, requiredLevel = 1, zoneOrSort = 12, preQuestGroup = { 10, 20 } },

        [32] = { name = "Light Path", starter = 240, finisher = 240, questLevel = 8, requiredLevel = 1, zoneOrSort = 12, exclusiveTo = { 33 } },
        [33] = { name = "Dark Path", starter = 241, finisher = 240, questLevel = 8, requiredLevel = 1, zoneOrSort = 12, exclusiveTo = { 32 } },
        [34] = { name = "After A Path", starter = 240, finisher = 240, questLevel = 9, requiredLevel = 1, zoneOrSort = 12, preQuestGroup = { 32 } },
        [35] = { name = "Light Only", starter = 240, finisher = 240, questLevel = 9, requiredLevel = 1, zoneOrSort = 12, preQuestGroup = { -32 } },

        [40] = { name = "A Letter For You", starter = 240, finisher = 242, questLevel = 10, requiredLevel = 1, zoneOrSort = 148, breadcrumbForQuestId = 41 },
        [41] = { name = "Trouble In Auberdine", starter = 242, finisher = 242, questLevel = 11, requiredLevel = 1, zoneOrSort = 148, breadcrumbs = { 40 } },

        [50] = { name = "For The Horde", starter = 240, questLevel = 10, requiredLevel = 1, zoneOrSort = 12, requiredRaces = 178, stop = "WRONG_RACE" },
        [51] = { name = "Rogues Only", starter = 240, questLevel = 10, requiredLevel = 1, zoneOrSort = 12, requiredClasses = 8, stop = "WRONG_CLASS" },
        [52] = { name = "Far Too Soon", starter = 240, questLevel = 60, requiredLevel = 58, zoneOrSort = 12 },
        [53] = { name = "Friends Only", starter = 240, questLevel = 20, requiredLevel = 1, zoneOrSort = 12, requiredMinRep = { 72, 3000 }, stop = "MISSING_REPUTATION" },
        [54] = { name = "Tailors Only", starter = 240, questLevel = 20, requiredLevel = 1, zoneOrSort = 12, requiredSkill = { 197, 100 }, stop = "PROFESSION_SKILL" },
        [55] = { name = "Read The Poster", startedBy = { nil, { 500 } }, finisher = 240, questLevel = 12, requiredLevel = 1, zoneOrSort = 12 },
        [56] = { name = "A Letter Falls", startedBy = { nil, nil, { 600 } }, finisher = 240, questLevel = 12, requiredLevel = 1, zoneOrSort = 12 },
        [57] = { name = "A Letter From Nowhere", startedBy = { nil, nil, { 601 } }, finisher = 240, questLevel = 12, requiredLevel = 1, zoneOrSort = 12 },
        [58] = { name = "No One Knows", finisher = 240, questLevel = 12, requiredLevel = 1, zoneOrSort = 12 },
        [59] = { name = "Where Are They", starter = 243, finisher = 240, questLevel = 12, requiredLevel = 1, zoneOrSort = 12 },
        [60] = { name = "Everywhere", startedBy = { { 240, 242 } }, finisher = 240, questLevel = 12, requiredLevel = 1, zoneOrSort = 12 },
        [61] = { name = "Bad Place", starter = 245, finisher = 240, questLevel = 12, requiredLevel = 1, zoneOrSort = 12 },
        [62] = { name = "Over Level", starter = 240, finisher = 240, questLevel = 5, requiredLevel = 1, requiredMaxLevel = 10, zoneOrSort = 12 },
        [63] = { name = "Again And Again", starter = 240, finisher = 240, questLevel = 30, requiredLevel = 1, zoneOrSort = 12, repeatable = true },

        [70] = { name = "Cycle One", starter = 240, finisher = 240, questLevel = 7, requiredLevel = 1, zoneOrSort = 12, preQuestSingle = { 71 } },
        [71] = { name = "Cycle Two", starter = 240, finisher = 240, questLevel = 7, requiredLevel = 1, zoneOrSort = 12, preQuestSingle = { 70 } },
        [80] = { name = "Broken Link", starter = 240, finisher = 240, questLevel = 7, requiredLevel = 1, zoneOrSort = 12, preQuestSingle = { 9999 } },
        [81] = { name = "Broken In A Group", starter = 240, finisher = 240, questLevel = 7, requiredLevel = 1, zoneOrSort = 12, preQuestGroup = { 10, 9999 } },
        [82] = { name = "Needs An Active Quest", starter = 240, finisher = 240, questLevel = 7, requiredLevel = 1, zoneOrSort = 12, parentQuest = 10 },
        [83] = { name = "For The Other Side Only", starter = 240, questLevel = 7, requiredLevel = 1, zoneOrSort = 12, preQuestSingle = { 50 } },
    },
}

local function World()
    local quests = {}
    for id, q in pairs(QUESTIE.quests) do quests[id] = q end
    return { areaMaps = QUESTIE.areaMaps, npcs = QUESTIE.npcs, objects = QUESTIE.objects, items = QUESTIE.items, quests = quests }
end

local function Start(opts)
    opts = opts or {}
    if opts.ui == nil then opts.ui = false end
    opts.mapID, opts.x, opts.y = opts.mapID or 1429, opts.x or 0.45, opts.y or 0.7
    opts.level = opts.level or 12
    if not opts.noQuestie then opts.questie = opts.questie or World() end
    local c = Stack.new(opts)
    c:Advance(0.2)
    c.FG.QuestIndex.Warm()
    T.ok(opts.noIndex or Stack.Until(c, function() return c.FG.QuestIndex.Ready() end, 10), "the index builds")
    return c
end

local function KeyOf(c, id) return c.FG.QuestStatus.Of(id).key end

local function Names(c, rows)
    local out = {}
    for i, n in ipairs(rows) do out[i] = c.FG.QuestIndex.Row(n).name end
    return out
end

local function Has(list, value)
    for _, v in ipairs(list) do
        if v == value then return true end
    end
    return false
end

local tests = {}

-- ==== finding ===============================================================

function tests.byName_inWholeOrPart()
    local c = Start()
    local I = c.FG.QuestIndex
    T.eq(Names(c, I.Find("first steps"))[1], "First Steps")
    T.eq(Names(c, I.Find("FIRST"))[1], "First Steps", "any case")
    T.eq(Names(c, I.Find("steps"))[1], "First Steps", "a later word")
    T.eq(Names(c, I.Find("irst st"))[1], "First Steps", "inside a word")
end

function tests.byId()
    local c = Start()
    T.eq(c.FG.QuestIndex.Row(c.FG.QuestIndex.Find("41")[1]).id, 41)
end

function tests.byGiver_andZone_andBothTogether()
    local c = Start()
    local I = c.FG.QuestIndex
    T.ok(Has(Names(c, I.Find("remy")), "The End"), "the giver")
    T.ok(Has(Names(c, I.Find("darkshore")), "Trouble In Auberdine") or #I.Find("darkshore") == 0, "the zone, if the map has that name")
    T.ok(Has(Names(c, I.Find("remy end")), "The End"), "words in any order, across fields")
end

function tests.aNearMiss_stillFinds()
    local c = Start()
    T.eq(Names(c, c.FG.QuestIndex.Find("frist steps"))[1], "First Steps")
end

function tests.theOtherSide_isLeftOutUnlessAskedFor()
    local c = Start()
    local I = c.FG.QuestIndex
    T.no(Has(Names(c, I.Find("for the horde")), "For The Horde"))
    T.ok(Has(Names(c, I.Find("for the horde", true)), "For The Horde"))
end

function tests.notInTheLog_isFoundAsWellAsInTheLog()
    local c = Start({ quests = { { questID = 10, title = "First Steps", level = 1, objectives = {} } } })
    T.eq(KeyOf(c, 10), "active", "in the log")
    T.eq(KeyOf(c, 20), "available", "not in it")
    T.eq(#c.FG.QuestIndex.Find("first steps"), 1)
    T.eq(#c.FG.QuestIndex.Find("left fork"), 1)
end

function tests.zones_areListed_andBrowsed()
    local c = Start()
    local zones = c.FG.QuestIndex.Zones()
    T.ok(#zones >= 1, "some zones")
    local rows = c.FG.QuestIndex.InZone(zones[1].zone)
    T.ok(#rows > 0)
end

-- ==== status ================================================================

function tests.statuses_sayWhereTheCharacterStands()
    local c = Start({ completed = { [20] = true }, quests = {
        { questID = 10, title = "First Steps", level = 1, objectives = {} },
        { questID = 21, title = "Right Fork", level = 5, complete = true, objectives = {} } } })
    T.eq(KeyOf(c, 10), "active", "in progress")
    T.eq(KeyOf(c, 21), "turnin", "ready to hand in")
    T.eq(KeyOf(c, 20), "done", "completed")
    T.eq(KeyOf(c, 32), "available", "open")
    T.eq(KeyOf(c, 12), "locked", "a prerequisite first")
    T.eq(KeyOf(c, 52), "level", "too low")
    T.eq(c.FG.QuestStatus.Of(52).need, 58)
    T.eq(KeyOf(c, 50), "no", "race or faction")
    T.eq(KeyOf(c, 51), "no", "class")
    T.eq(KeyOf(c, 53), "gated", "reputation")
    T.eq(KeyOf(c, 54), "gated", "profession")
    T.eq(KeyOf(c, 9999), "unknown", "Questie holds no such quest")
end

function tests.tooHighALevel_isNotOffered()
    local c = Start({ level = 12 })
    T.eq(KeyOf(c, 62), "no")
end

function tests.noStarter_isOnlyLikely_neverSimplyAvailable()
    local c = Start()
    T.eq(KeyOf(c, 58), "likely")
    T.ok(c.FG.QuestStatus.Of(58).why, "and it says why")
end

function tests.withoutQuestiesReasons_itStillSaysNo_andDoesNotGuess()
    local world = World()
    world.noVerbose = true
    local c = Start({ questie = world })
    T.eq(KeyOf(c, 12), "no")
    T.ok(c.FG.QuestStatus.Of(12).why)
end

function tests.withoutQuestie_everythingIsUnknown_andNothingBreaks()
    local c = Start({ noQuestie = true, noIndex = true })
    T.eq(c.FG.QuestDB.Ready(), false)
    T.eq(KeyOf(c, 10), "unknown")
    T.eq(#c.FG.QuestIndex.Find("first"), 0)
    T.eq(c.FG.QuestTargets.Starter(10), nil)
    T.eq(#c.errors, 0)
end

function tests.aQuestieThatArrivesLate_isPickedUp()
    local c = Start({ questieLate = true, noIndex = true })
    T.no(c.FG.QuestIndex.Ready())
    T.eq(KeyOf(c, 10), "unknown", "too early to say")
    c:QuestieReady()
    c:Fire("QUEST_LOG_UPDATE")
    c:Advance(0.5)
    T.ok(Stack.Until(c, function() return c.FG.QuestIndex.Ready() end, 10), "built once it is there")
    T.eq(KeyOf(c, 10), "available")
end

function tests.aStatus_changesWhenTheLogDoes_notWithEveryKill()
    local c = Start()
    T.eq(KeyOf(c, 11), "locked")
    local epoch = c.FG.QuestStatus.Epoch()
    for _ = 1, 20 do c:Fire("QUEST_LOG_UPDATE") end
    c:Advance(0.5)
    T.eq(c.FG.QuestStatus.Epoch(), epoch, "kills change nothing")
    c.completed[10] = true
    c:Fire("QUEST_TURNED_IN", 10)
    c:Advance(1.2)
    T.eq(KeyOf(c, 11), "available", "a turn-in does")
end

function tests.levelingUp_opensWhatItShould()
    local c = Start({ level = 57 })
    T.eq(KeyOf(c, 52), "level")
    c.player.level = 58
    c:Fire("PLAYER_LEVEL_UP", 58)
    T.eq(KeyOf(c, 52), "available")
end

-- ==== prerequisites =========================================================

function tests.requirements_singleMeansAnyOne()
    local c = Start({ completed = { [21] = true } })
    local req = c.FG.QuestChain.Requirements(22)
    T.eq(req[1].kind, "any")
    T.ok(req[1].met, "either will do")
    T.eq(KeyOf(c, 22), "available")
end

function tests.requirements_groupMeansAll()
    local c = Start({ completed = { [10] = true } })
    local req = c.FG.QuestChain.Requirements(30)
    T.eq(req[1].kind, "all")
    T.no(req[1].met, "one of two")
    T.eq(KeyOf(c, 30), "locked")
    c.completed[20] = true
    c.FG.QuestStatus.Forget()
    T.ok(c.FG.QuestChain.Requirements(30)[1].met, "both")
    T.eq(KeyOf(c, 30), "available")
end

function tests.requirements_anExclusiveQuestCounts_unlessTheIdIsNegative()
    local c = Start({ completed = { [33] = true } })
    T.ok(c.FG.QuestChain.Requirements(34)[1].met, "the other path counts")
    T.eq(KeyOf(c, 34), "available")
    T.no(c.FG.QuestChain.Requirements(35)[1].met, "a negative id wants that very quest")
    T.eq(KeyOf(c, 35), "locked")
end

function tests.requirements_agreeWithQuestie_acrossEveryCombination()
    for mask = 0, 15 do
        local done = {}
        for bit, id in ipairs({ 10, 20, 32, 33 }) do
            if mask % 2 ^ bit >= 2 ^ (bit - 1) then done[id] = true end
        end
        local c = Start({ completed = done })
        for _, id in ipairs({ 22, 30, 34, 35 }) do
            if not done[id] then
                local met = true
                for _, group in ipairs(c.FG.QuestChain.Requirements(id)) do met = met and group.met end
                local s = c.FG.QuestStatus.Of(id)
                T.eq(s.key ~= "locked", met, ("quest %d, mask %d"):format(id, mask))
            end
        end
    end
end

function tests.aQuestThatMustBeActive_isNotDoneByFinishingIt()
    local c = Start({ quests = { { questID = 10, title = "First Steps", level = 1, objectives = {} } } })
    T.ok(c.FG.QuestChain.Requirements(82)[1].met)
    T.eq(c.FG.QuestChain.Requirements(82)[1].kind, "active")
    local d = Start({ completed = { [10] = true } })
    T.no(d.FG.QuestChain.Requirements(82)[1].met, "turned in is not in the log")
end

function tests.aMissingLink_isSaidToBeMissing()
    local c = Start()
    local group = c.FG.QuestChain.Requirements(80)[1]
    T.eq(group.missing[1], 9999)
end

-- ==== the way to a quest ====================================================

function tests.thePath_startsWithTheFirstThingToDo()
    local c = Start()
    local path = c.FG.QuestChain.Path(12)
    T.eq(#path.steps, 2)
    T.eq(path.steps[1].ids[1], 10, "first")
    T.eq(path.steps[2].ids[1], 11, "then")
    T.eq(path.first.ids[1], 10)
end

function tests.thePath_skipsWhatIsDone()
    local c = Start({ completed = { [10] = true } })
    local path = c.FG.QuestChain.Path(12)
    T.eq(#path.steps, 1)
    T.eq(path.first.ids[1], 11)
end

function tests.thePath_offersAlternatives_andChoosesNone()
    local c = Start()
    local path = c.FG.QuestChain.Path(22)
    T.eq(#path.steps, 1)
    T.ok(path.first.choice, "a choice")
    T.eq(#path.first.ids, 2, "both")
end

function tests.thePath_goesThroughEachOfAGroup()
    local c = Start()
    local path = c.FG.QuestChain.Path(30)
    T.eq(#path.steps, 2)
end

function tests.thePath_leavesOutWhatThisCharacterCannotTake()
    local c = Start()
    local path = c.FG.QuestChain.Path(83)
    T.ok(path.blocked, "the only way is closed to them")
    T.eq(#path.steps, 0)
end

function tests.thePath_survivesACycle()
    local c = Start()
    local path = c.FG.QuestChain.Path(70)
    T.ok(#path.steps <= 2, "stops")
    T.eq(#c.errors, 0)
end

function tests.thePath_reportsABrokenLink_andInventsNothing()
    local c = Start()
    local path = c.FG.QuestChain.Path(81)
    T.eq(path.gaps, 1)
    T.ok(path.first, "what can be done still is")
    T.eq(path.first.ids[1], 10)
end

function tests.aQuestWithNothingBeforeIt_hasAnEmptyPath()
    local c = Start()
    T.eq(#c.FG.QuestChain.Path(20).steps, 0)
end

-- ==== the chain =============================================================

function tests.aLinearChain_saysWhereYouAre()
    local c = Start({ completed = { [10] = true } })
    local chain = c.FG.QuestChain.Walk(11)
    T.ok(chain.linear)
    T.eq(chain.position, 2)
    T.eq(chain.total, 3)
    T.eq(chain.done, 1)
    T.eq(#chain.rows, 3)
end

function tests.aBranch_isNotCountedAsALine()
    local c = Start()
    local chain = c.FG.QuestChain.Walk(22)
    T.no(chain.linear)
    T.eq(chain.position, nil, "no 3 of 7 where that would be a guess")
    T.eq(#chain.rows, 2)
    T.eq(#chain.rows[1], 2, "both forks")
end

function tests.aBreadcrumb_isShownAndMarkedOptional()
    local c = Start()
    local chain = c.FG.QuestChain.Walk(41)
    T.ok(chain.nodes[40].optional)
    T.no(chain.linear)
end

function tests.aCycle_stopsAndIsNoticed()
    local c = Start()
    local chain = c.FG.QuestChain.Walk(70)
    T.ok(chain.looped)
    T.no(chain.linear)
    T.eq(chain.total, 2)
end

function tests.aBrokenLink_isNoticed()
    local c = Start()
    local chain = c.FG.QuestChain.Walk(80)
    T.eq(chain.gaps, 1)
    T.no(chain.linear)
end

function tests.aHugeChain_isCutOff_andSaysSo()
    local world = World()
    for i = 1, 400 do
        world.quests[1000 + i] = { name = "Link " .. i, starter = 240, finisher = 240, questLevel = 1, requiredLevel = 1, zoneOrSort = 12,
                                   preQuestSingle = i > 1 and { 1000 + i - 1 } or nil, nextQuestInChain = 1000 + i + 1 }
    end
    local c = Start({ questie = world })
    local at = os.clock()
    local chain = c.FG.QuestChain.Walk(1200)
    T.ok(chain.total <= c.FG.QuestChain.MAX_NODES)
    T.ok(chain.truncated)
    T.no(chain.linear, "not when part of it is cut")
    T.ok(os.clock() - at < 0.5, "and quickly")
    local path = c.FG.QuestChain.Path(1200)
    T.ok(#path.steps <= c.FG.QuestChain.MAX_NODES)
end

function tests.aWideChain_isHeld()
    local world = World()
    world.quests[2000] = { name = "The Root", starter = 240, finisher = 240, questLevel = 1, requiredLevel = 1, zoneOrSort = 12 }
    for i = 1, 87 do
        world.quests[2000 + i] = { name = "Spoke " .. i, starter = 240, finisher = 240, questLevel = 1, requiredLevel = 1, zoneOrSort = 12, preQuestSingle = { 2000 } }
    end
    local c = Start({ questie = world })
    local chain = c.FG.QuestChain.Walk(2000)
    T.eq(chain.total, 88, "the widest the real data goes")
    T.no(chain.truncated)
end

function tests.whatAQuestOpens_isKnown()
    local c = Start()
    T.ok(Has(c.FG.QuestChain.Opens(10), 11))
    T.ok(Has(c.FG.QuestChain.Opens(20), 22))
    T.ok(Has(c.FG.QuestChain.Opens(20), 30))
end

-- ==== where a quest starts ==================================================

local function Starter(c, id) return c.FG.QuestTargets.Starter(id) end

function tests.aPersonStartsIt()
    local c = Start()
    local t = Starter(c, 10)
    T.eq(t.starterKind, "npc")
    T.eq(t.status, "ok")
    T.ok(t.text:find("Marshal Dughan", 1, true))
end

function tests.anObjectStartsIt_andIsCalledOne()
    local c = Start()
    local t = Starter(c, 55)
    T.eq(t.starterKind, "object")
    T.ok(t.text:find("object", 1, true), t.text)
    T.ok(t.text:find("Wanted Poster", 1, true))
end

function tests.anItemStartsIt_andOnlyWhatDropsItIsOffered()
    local c = Start()
    local t = Starter(c, 56)
    T.eq(t.starterKind, "item")
    T.ok(t.text:find("Bloodstained Letter", 1, true))
    T.ok(t.text:find("Young Wolf", 1, true), "where it comes from")
    T.eq(t.status, "ok")
end

function tests.anItemWithNoKnownSource_saysSo_andOffersNoPlace()
    local c = Start()
    local t = Starter(c, 57)
    T.eq(t.starterKind, "item")
    T.eq(t.status, "none")
    T.ok(t.reason:find("item", 1, true))
end

function tests.noKnownStarter_saysSo()
    local c = Start()
    local t = Starter(c, 58)
    T.eq(t.starterKind, nil)
    T.eq(t.status, "none")
end

function tests.aGiverWithNoSpawn_saysSo()
    local c = Start()
    T.eq(Starter(c, 59).status, "none")
end

function tests.badCoordinates_areNotARoute()
    local c = Start()
    T.eq(Starter(c, 61).status, "none")
end

function tests.severalStarters_comeBackAsAreas_toChooseByTravelTime()
    local c = Start()
    local t = Starter(c, 60)
    T.eq(#t.areas, 2)
    local done
    c.FG.QuestTargets.Resolve(t, function() done = true end)
    T.ok(Stack.Until(c, function() return done end, 30), "priced")
    T.eq(t.best.spot.mapID, 1429, "the one in reach, not the first listed or a straight line over the sea")
    T.ok(t.best.sec, "by a real estimate")
end

function tests.everythingElseAboutAQuest_isThereToShow()
    local c = Start()
    local all = c.FG.QuestTargets.Explore(11)
    T.eq(all.start.status, "ok")
    T.eq(all.turnIn.status, "ok")
    T.ok(all.turnIn.text:find("Remy", 1, true))
end

-- ==== lists =================================================================

local function Listed(c, opts)
    local out = {}
    for _, item in ipairs(c.FG.QuestBrowse.List(opts).items) do out[item.row.id] = item end
    return out
end

function tests.filters_chooseByStatus()
    local c = Start({ completed = { [10] = true }, quests = { { questID = 20, title = "Left Fork", level = 5, objectives = {} } } })
    local B = c.FG.QuestBrowse
    B.Scan()
    T.ok(Stack.Until(c, B.Scanned, 10))
    local open = Listed(c, { filter = "available" })
    T.ok(open[11], "next in line")
    T.no(open[12], "locked is not open")
    T.no(open[10], "done is not open")
    T.no(open[50], "the other side is not open")
    T.ok(Listed(c, { filter = "soon" })[12])
    T.ok(Listed(c, { filter = "soon" })[52], "level locked")
    T.ok(Listed(c, { filter = "done" })[10])
    T.ok(Listed(c, { filter = "log" })[20])
    T.ok(Listed(c, { filter = "repeatable" })[63])
    T.ok(Listed(c, { filter = "chains" })[11], "leads somewhere")
    T.ok(Listed(c, { filter = "all" })[50], "all of them")
    T.ok(Listed(c, { filter = "level" })[32], "around this level")
    T.no(Listed(c, { filter = "level" })[63], "not far above it")
end

function tests.aZoneAndWords_narrowAList()
    local c = Start()
    local zone = c.FG.QuestIndex.Zones()[1].zone
    local list = c.FG.QuestBrowse.List({ zone = zone, filter = "all" })
    T.ok(list.total > 0)
    local words = c.FG.QuestBrowse.List({ text = "left fork", filter = "available" })
    T.eq(words.total, 1)
end

function tests.quitLists_areCappedAndSaySo()
    local world = World()
    for i = 1, 500 do
        world.quests[3000 + i] = { name = "Filler " .. i, starter = 240, finisher = 240, questLevel = 1, requiredLevel = 1, zoneOrSort = 12 }
    end
    local c = Start({ questie = world })
    c.FG.QuestBrowse.Scan()
    T.ok(Stack.Until(c, c.FG.QuestBrowse.Scanned, 30))
    local list = c.FG.QuestBrowse.List({ filter = "available" })
    T.eq(#list.items, 200)
    T.ok(list.capped)
    T.ok(list.total > 200)
end

function tests.nearMe_findsWhatIsCloseAndPricesIt()
    local c = Start()
    local found
    T.ok(c.FG.QuestBrowse.Near(function(list) found = list end))
    T.ok(Stack.Until(c, function() return found ~= nil end, 30), "finishes")
    T.ok(#found > 0)
    T.ok(#found <= 8, "only the closest few are priced")
    local darkshore = false
    for _, item in ipairs(found) do
        T.ok(c.FG.QuestStatus.Open(item.status), "open quests only")
        darkshore = darkshore or item.row.id == 41
    end
    T.no(darkshore, "nothing from over the sea")
end

function tests.details_holdWhatThePanelShows()
    local c = Start()
    local d = c.FG.QuestBrowse.Details(53)
    T.eq(d.name, "Friends Only")
    T.eq(d.rep.name, "Faction 72")
    T.eq(d.rep.value, 3000)
    T.eq(c.FG.QuestBrowse.Details(54).skill.value, 100)
    T.eq(c.FG.QuestBrowse.Details(9999), nil)
    T.eq(c.FG.QuestBrowse.Details(55).starters[1].kind, "object")
    T.eq(c.FG.QuestBrowse.Details(56).starters[1].kind, "item")
    T.eq(c.FG.QuestBrowse.Details(50).side, "Horde")
end

return tests
