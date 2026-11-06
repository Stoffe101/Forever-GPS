-- Journeys on the real route engine, the real Forever data and the real walking
-- grid. Nothing here is a mock of routing: only the player is pretended.
local T = require("support.t")
local Stack = require("support.stack")

local STORMWIND = { mapID = 1453, x = 0.6, y = 0.6 }
local AUBERDINE = { name = "Auberdine", mapID = 1439, x = 0.37, y = 0.44 }

local function Start(opts)
    opts = opts or {}
    opts.ui = false
    opts.mapID = opts.mapID or STORMWIND.mapID
    opts.x, opts.y = opts.x or STORMWIND.x, opts.y or STORMWIND.y
    return Stack.new(opts)
end

local function Kinds(steps)
    local out = {}
    for i, s in ipairs(steps) do out[i] = s.kind end
    return table.concat(out, ",")
end

local function Plan(c, dest)
    local Planner = c.FG.Planner
    Planner.Inspect({ data = dest, name = dest.name })
    T.ok(Stack.Until(c, function()
        local p = Planner.Current()
        return p.status == "ready" or p.status == "failed" or p.status == "unreachable"
    end, 30), "the plan finishes")
    return Planner.Current()
end

local function Learn(c, ids)
    local Route = c.ns.GPSRoute
    Route.recordedKnown = {}
    for _, id in ipairs(ids) do Route.recordedKnown[id] = true end
    Route.ForgetKnown()
    c.FG.Planner.Forget()   -- as a flight master's map does
end

local tests = {}

function tests.stormwindToAuberdine_takesTheDirectBoat()
    local c = Start()
    local plan = Plan(c, AUBERDINE)
    T.eq(plan.status, "ready")
    local steps = plan.selected.steps
    T.eq(Kinds(steps), "travel,boat,travel", "walk, boat, walk")
    T.has(steps[1].text, "dock for the boat to Auberdine", "the first step names the dock and where the boat goes")
    T.has(steps[2].text, "Board the boat to Auberdine", "the second says which boat")
    T.eq(steps[2].route, 11616, "the Stormwind Harbor boat, not the Menethil one")
    T.eq(steps[2].go.m, 1453, "boarded in Stormwind")
    T.eq(steps[2].arrive.m, 1439, "lands in Darkshore")
    T.has(steps[3].text, "Auberdine", "then walks the rest")
    T.ok(plan.selected.total > 120 and plan.selected.total < 900, "a believable time: " .. plan.selected.total)
end

function tests.ironforgeToDarkshore_prefersTramAndDirectBoat()
    -- Forever's direct Stormwind Harbor boat beats flying to Menethil, whose boat
    -- is several minutes longer: the engine should find that, flights or not.
    local c = Start({ mapID = 1455, x = 0.55, y = 0.48 })
    local dest = { name = "Darkshore", mapID = 1439, x = 0.37, y = 0.44 }
    local plan = Plan(c, dest)
    T.eq(Kinds(plan.selected.steps):gsub("travel,", ""), "tram,boat,travel", "tram to Stormwind, then the boat")
    Learn(c, { 6, 7 })
    plan = Plan(c, dest)
    T.has(Kinds(plan.selected.steps), "tram", "knowing the Menethil flight does not make the slower boat the answer")
end

function tests.flights_areTakenOnlyOnceLearned()
    local c = Start({ mapID = 1455, x = 0.55, y = 0.48 })
    local dest = { name = "Menethil Harbor", mapID = 1437, x = 0.1, y = 0.6 }
    local plan = Plan(c, dest)
    local walking = plan.selected.total
    T.lacks(Kinds(plan.selected.steps), "taxi", "none learned: no flight is invented")
    Learn(c, { 6, 7 })
    plan = Plan(c, dest)
    T.has(Kinds(plan.selected.steps), "taxi", "both ends learned: the flight is taken")
    T.ok(plan.selected.total < walking, "and it is quicker")
end

function tests.unknownFlightMaster_isNeverAFlightsEnd()
    local c = Start()
    Learn(c, { 2 })
    local plan = Plan(c, { name = "Sentinel Hill", mapID = 1436, x = 0.5657, y = 0.5267 })
    for _, step in ipairs(plan.selected.steps) do
        T.no(step.kind == "taxi" and step.toID == 4 and not step.learn, "a flight into an unlearned master")
    end
end

function tests.aHorde_doesNotRideAllianceFlights()
    local c = Start({ faction = "Horde", race = "Orc", mapID = 1454, x = 0.5, y = 0.5 })
    Learn(c, { 23, 25, 22, 2, 6 })
    local plan = Plan(c, { name = "Stormwind", mapID = 1453, x = 0.6, y = 0.6 })
    for _, step in ipairs(plan.selected.steps) do
        if step.kind == "taxi" then
            T.no(step.nodeID == 2 or step.nodeID == 6 or step.toID == 2 or step.toID == 6, "an Alliance flight master for a Horde character")
        end
    end
end

function tests.aHorde_takesTheZeppelinNotTheAllianceBoat()
    local c = Start({ faction = "Horde", race = "Orc", mapID = 1454, x = 0.5, y = 0.5 })
    local plan = Plan(c, { name = "Undercity", mapID = 1458, x = 0.66, y = 0.44 })
    T.has(Kinds(plan.selected.steps), "zeppelin", "Orgrimmar to Undercity by zeppelin")
    for _, step in ipairs(plan.selected.steps) do T.no(step.hostile, "no enemy transport when your own will do") end
end

function tests.anEnemyBoat_isALastResortAndSaysSo()
    local c = Start({ faction = "Horde", race = "Orc", mapID = 1453, x = 0.3, y = 0.6 })
    local plan = Plan(c, AUBERDINE)
    if plan.status == "ready" then
        for _, step in ipairs(plan.selected.steps) do
            if step.hostile then T.has(step.text, "Hostile", "the step says it is the enemy's") end
        end
    end
end

function tests.anAvoidedWay_isOnlyTakenWhenNothingElseReaches()
    local c = Start()
    c.FG.Bridge.SetAvoid("boat", true)
    local plan = Plan(c, { name = "Stranglethorn", mapID = 1434, x = 0.4, y = 0.3 })
    T.lacks(Kinds(plan.selected.steps), "boat", "same continent: no boat when boats are avoided")
    c.FG.Bridge.SetAvoid("boat", false)
end

function tests.theModes_collapseWhenTheyAreTheSameRoute()
    local c = Start()
    local plan = Plan(c, AUBERDINE)
    T.eq(#plan.options, 4, "fastest, safer, roads and overland were each tried")
    T.ok(plan.options[1].steps, "fastest planned")
    for i = 2, #plan.options do
        local o = plan.options[i]
        if o.same then T.eq(#o.steps, #plan.options[1].steps, "same steps") end
    end
end

function tests.planning_leavesTheFollowedRoutesGridAlone()
    local c = Start()
    local Nav = c.ns.GPSNav
    Plan(c, AUBERDINE)
    c.FG.Planner.Start()
    T.ok(Stack.Until(c, function() return c.FG.Bridge.ActiveRoute().others ~= nil end, 90), "settled")
    local epoch = Nav.epoch
    Plan(c, { name = "Westfall", mapID = 1436, x = 0.5, y = 0.5 })
    T.eq(Nav.epoch, epoch, "comparing routes puts the grid's settings back, or the arrow would lose its walk")
end

function tests.aNewPlan_doesNotReplaceTheRouteUnderWay()
    local c = Start()
    Plan(c, AUBERDINE)
    c.FG.Planner.Start()
    c:Advance(1)
    local route = c.FG.Bridge.ActiveRoute()
    Plan(c, { name = "Westfall", mapID = 1436, x = 0.5, y = 0.5 })
    T.ok(c.FG.Bridge.ActiveRoute() == route, "inspecting changes nothing until Start")
end

function tests.theEstimate_isCloseToTheRealRoute()
    local c = Start()
    local plan = Plan(c, AUBERDINE)
    local dest = c.FG.Planner.Current().dest
    local estimate = c.FG.Eta.Now(dest)
    T.near(estimate.sec, plan.selected.total, plan.selected.total * 0.2, "within a fifth of the full route")
    T.eq(estimate.transports, "Boat", "and takes the same transport")
end

function tests.theEstimate_isCheapEnoughForAList()
    local c = Start()
    local dest = { name = "x", mapID = 1439, x = 0.37, y = 0.44 }
    local started = os.clock()
    for i = 1, 20 do c.FG.Eta.Now({ name = "x", mapID = 1439, x = 0.3 + i / 100, y = 0.44 }, nil) end
    local each = (os.clock() - started) / 20
    T.ok(each < 0.05, ("an estimate took %.1f ms; a list prices ten of these"):format(each * 1000))
    T.ok(c.FG.Eta.Now(dest), "and it answers")
end

function tests.anUnreachableSpot_saysSoAndInventsNothing()
    local c = Start()
    local plan = Plan(c, { name = "Nowhere", mapID = 999999, x = 0.5, y = 0.5 })
    T.eq(plan.status, "failed", "no map, no route")
    T.ok(plan.message, "with a reason")
end

function tests.noPosition_isSaidPlainly()
    local c = Start()
    c.env.C_Map.GetPlayerMapPosition = function() return nil end
    local plan = Plan(c, AUBERDINE)
    T.eq(plan.status, "failed")
    T.has(plan.message, "position", "the reason is the missing position")
end

function tests.aStalePlan_isPlannedAgainFromHere()
    local c = Start()
    Plan(c, AUBERDINE)
    c:SetPlayer(1453, 0.45, 0.55)
    c:Advance(1)
    T.ok(c.FG.Planner.Start(), "starts")
    T.ok(Stack.Until(c, function() return c.FG.Bridge.ActiveRoute() ~= nil end, 20), "after planning once more")
    T.eq(c.FG.Bridge.ActiveRoute().dest.name, "Auberdine")
end

function tests.aFreshPlan_startsWithoutPlanningAgain()
    local c = Start()
    local plan = Plan(c, AUBERDINE)
    local steps = plan.selected.steps
    c.FG.Planner.Start()
    T.ok(c.FG.Bridge.ActiveRoute().steps == steps, "the steps shown are the steps followed")
end

function tests.theChosenWay_staysWithTheRoute()
    local c = Start()
    local plan = Plan(c, AUBERDINE)
    local safer = plan.options[2]
    c.FG.Planner.Select(safer)
    T.eq(c.FG.char.mode, "safer", "remembered")
    c.FG.Planner.Start()
    T.ok(c.FG.Bridge.ActiveRoute().wayAvoid.danger, "and reroutes keep to it")
end

function tests.risk_saysWhatItKnowsAndClaimsNoMore()
    local c = Start({ faction = "Horde", race = "Orc", level = 10, mapID = 1429, x = 0.5, y = 0.5 })
    local plan = Plan(c, { name = "Stormwind", mapID = 1453, x = 0.6, y = 0.6 })
    local risk = plan.selected.risk
    T.ok(risk, "assessed")
    T.eq(risk.level, "high", "a Horde level 10 walking into Stormwind: " .. tostring(risk.level))
    T.has(table.concat(risk.reasons, " "), "guards", "the reason is the guards")
    local L = c.FG.L
    for _, key in ipairs({ "RISK_LOW", "RISK_MODERATE", "RISK_HIGH" }) do
        T.lacks(L[key]:lower(), "safe", "no label promises safety")
    end
    T.has(L["RISK_DISCLAIMER"], "Enemy players cannot be detected", "and the limits are stated")
end

function tests.contestedGround_isNamedAndNeverCalledSafe()
    local c = Start({ mapID = 1429, x = 0.8, y = 0.7 })
    local plan = Plan(c, { name = "Darkshire", mapID = 1431, x = 0.75, y = 0.45 })
    T.eq(plan.status, "ready")
    local risk = plan.selected.risk
    T.ok(risk, "assessed")
    local found
    for _, reason in ipairs(risk.reasons) do
        if reason:find("contested", 1, true) then found = reason end
    end
    T.ok(found, "says so: " .. table.concat(risk.reasons, "; "))
    T.has(found, "Duskwood")
    T.ok(risk.level ~= "low", "and that is not a low risk: " .. risk.level)
    T.has(c.FG.L["RISK_DISCLAIMER"], "cannot be detected", "enemy players are never claimed to be accounted for")
end

function tests.aDangerousEnd_isCalledAnApproach()
    local c = Start({ ui = false })
    local Risk = c.FG.Risk
    T.eq(Risk.Label("high", { approach = true }), "Dangerous approach")
    T.eq(Risk.Label("high", {}), c.FG.L["RISK_HIGH"])
    T.eq(Risk.Label("contested"), "Contested territory")
    T.eq(Risk.Label("low"), "Low known environmental risk")
end

function tests.flightAdvice_readsAsATip()
    local c = Start({ ui = false })
    local P = c.FG.Planner
    T.eq(P.Tip(nil), nil)
    T.has(P.Tip({ pickups = { { id = 1, name = "Sentinel Hill" } } }), "Sentinel Hill")
    T.has(P.Tip({ pickups = { { id = 1, name = "X" } }, learn = { id = 1, save = 300 } }), "5 min", "with what it saves")
    T.has(P.Tip({ learn = { id = 2, name = "Y", extra = 60, save = 300 } }), "detour")
end

function tests.aSharedPlace_carriesNothingButWords()
    local c = Start({ ui = false })
    local line = c.FG.Saved.ShareLine("|cffff0000Bad|r |Hitem:1|h[link]|h name", "Elwynn Forest", 0.5, 0.25)
    T.lacks(line, "|", "no color or link codes")
    T.lacks(line, "[", "no brackets")
    T.has(line, "/fgps way Elwynn Forest 50.0 25.0")
end

return tests
