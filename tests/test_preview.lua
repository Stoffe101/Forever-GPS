-- The journey on the world map before it is taken. These run the real plan, on the
-- real walking grid, through the real line renderer, into the fake map's canvas.
local T = require("support.t")
local Stack = require("support.stack")

local AUBERDINE = { name = "Auberdine", mapID = 1439, x = 0.37, y = 0.44 }

local function Start(opts)
    opts = opts or {}
    opts.mapID, opts.x, opts.y = opts.mapID or 1453, opts.x or 0.6, opts.y or 0.6
    local c = Stack.new(opts)
    c.env.WorldMapFrame:Show()
    return c
end

local function Plan(c, dest)
    local P = c.FG.Planner
    P.Inspect({ data = dest, name = dest.name })
    T.ok(Stack.Until(c, function()
        local p = P.Current()
        return p.status == "ready" or p.status == "failed" or p.status == "unreachable"
    end, 30), "the plan finishes")
    c:Advance(0.3)
    return P.Current()
end

-- The strips the preview's own lines have shown.
local function Strips(c)
    local lines = c.FG.MapPreview._Lines()
    return lines and lines.n or 0
end

local function ShownMarks(c)
    local n = 0
    for _, m in ipairs(c.FG.MapPreview._Marks()) do
        if m:IsShown() then n = n + 1 end
    end
    return n
end

local tests = {}

function tests.previewing_startsNothing()
    local c = Start()
    Plan(c, AUBERDINE)
    T.no(c.FG.Bridge.Route(), "no route exists")
    T.ok(c.FG.MapPreview.Showing(), "yet the map shows one")
    T.ok(Strips(c) > 0, "drawn as real strips: " .. Strips(c))
end

function tests.aPreview_followsTheGroundNotAStraightLine()
    local c = Start()
    local plan = Plan(c, AUBERDINE)
    local option = plan.selected
    local walk = option.walks[1]
    T.ok(walk and walk.pts and #walk.pts > 6, "the walk has real geometry")
    local a, z = option.from, option.steps[1].go
    local straight = ((a.wx - z.wx) ^ 2 + (a.wy - z.wy) ^ 2) ^ 0.5
    T.ok(walk.len > straight, ("it bends: %.0f yards against %.0f in a line"):format(walk.len, straight))
    T.ok(Strips(c) >= #walk.pts / 2 - 2 or Strips(c) > 8, "and is drawn as many strips, not one: " .. Strips(c))
end

function tests.aPreview_leavesAnActiveRouteUntouched()
    local c = Start()
    Plan(c, AUBERDINE)
    c.FG.Planner.Start()
    T.ok(Stack.Until(c, function() return c.FG.Bridge.ActiveRoute().others ~= nil end, 90), "settled")
    local route = c.FG.Bridge.ActiveRoute()
    local active, total, steps = route.active, route.total, route.steps
    Plan(c, { name = "Westfall", mapID = 1436, x = 0.5, y = 0.5 })
    T.ok(c.FG.MapPreview.Showing(), "a second journey is shown")
    T.ok(c.FG.Bridge.ActiveRoute() == route, "and the first still runs")
    T.eq(route.active, active)
    T.eq(route.total, total)
    T.ok(route.steps == steps, "with the very same steps")
    c.FG.Planner.Clear()
    c:Advance(0.3)
    T.no(c.FG.MapPreview.Showing(), "closing the preview clears it")
    T.ok(c.FG.Bridge.ActiveRoute() == route, "and leaves the route")
end

function tests.closingAPreview_leavesNothingOnTheMap()
    local c = Start()
    Plan(c, AUBERDINE)
    T.ok(c.env.ForeverGPSMapPreview:IsShown(), "drawn")
    c.FG.Planner.Clear()
    c:Advance(0.2)
    T.no(c.env.ForeverGPSMapPreview:IsShown(), "gone")
    T.no(c.env.ForeverGPSMapBanner:IsShown(), "and so is its banner")
end

function tests.startingFromAPreview_handsOverToTheRoute()
    local c = Start()
    Plan(c, AUBERDINE)
    c.FG.Planner.Start()
    c:Advance(0.5)
    T.ok(c.FG.Bridge.ActiveRoute(), "navigating")
    T.no(c.FG.MapPreview.Showing(), "the preview steps aside for the real line")
end

function tests.changingMode_changesWhatIsDrawn()
    local c = Start({ mapID = 1429, x = 0.45, y = 0.6 })
    local plan = Plan(c, { name = "Stranglethorn", mapID = 1434, x = 0.4, y = 0.3 })
    local chosen = plan.selected
    local other
    for _, option in ipairs(plan.options) do
        if option ~= chosen and option.steps and not option.same and not option.noWay then other = option end
    end
    T.ok(other, "a real alternative exists here")
    c.FG.Planner.Select(other)
    c:Advance(0.3)
    T.ok(c.FG.MapPreview._Current().option == other, "the map follows the choice")
end

function tests.aPlanRemembers_itsWalksAfterTheGridMovesOn()
    local c = Start()
    local plan = Plan(c, AUBERDINE)
    for _, option in ipairs(plan.options) do
        if option.steps and not option.noWay then
            T.ok(next(option.walks), option.mode.key .. " kept its walks")
        end
    end
end

function tests.aCrossContinentJourney_hasNoLineThroughTheWorld()
    local c = Start()
    local plan = Plan(c, AUBERDINE)
    -- On the map of the start, the boat's far end is not on it.
    c.env.WorldMapFrame:SetMapID(1453)
    c.FG.MapPreview._Redraw()
    local boat = plan.selected.steps[2]
    T.eq(boat.kind, "boat")
    local titles = {}
    for _, m in ipairs(c.FG.MapPreview._Marks()) do
        if m:IsShown() and m.tipTitle then titles[#titles + 1] = m.tipTitle end
    end
    T.has(table.concat(titles, "|"), "Board the boat to Auberdine", "the boarding point is labeled with where it goes")
    -- On the map of the far side, the walk picks up at the landing.
    c.env.WorldMapFrame:SetMapID(1439)
    c.FG.MapPreview._Redraw()
    titles = {}
    for _, m in ipairs(c.FG.MapPreview._Marks()) do
        if m:IsShown() and m.tipTitle then titles[#titles + 1] = m.tipTitle end
    end
    local joined = table.concat(titles, "|")
    T.has(joined, "arrives here", "the landing is marked on the far map")
    T.has(joined, "Auberdine", "and the destination")
end

function tests.aJourneyStep_turnsTheMapToIt()
    local c = Start()
    Plan(c, AUBERDINE)
    c.FG.MapPreview.Focus(3)
    T.eq(c.FG.MapPreview.Focused(), 3)
    T.eq(c.FG.RouteMap.MapID(), 1439, "the last walk is in Darkshore")
    c.FG.MapPreview.Focus(3)
    T.eq(c.FG.MapPreview.Focused(), nil, "again shows them all")
end

function tests.opening_doesNothingWhenThereIsNothingToShow()
    local c = Start()
    T.no(c.FG.MapPreview.Open(), "no plan")
    T.eq(#c.errors, 0)
end

function tests.inCombat_theGamesMapIsLeftAlone_andOursStillOpens()
    local c = Start()
    Plan(c, AUBERDINE)
    c.env.WorldMapFrame:Hide()
    c.player.combat = true
    T.ok(c.FG.MapPreview.Open(), "our own frame, so nothing is protected")
    T.no(c.env.WorldMapFrame:IsShown(), "the game's map stays the player's")
end

-- Tiles row by row as the game's own detail layer lays them, the last ones cut to the map.
function tests.theRouteMapsArt_isLaidOutAsTheGameLaysIt()
    local c = Start()
    c.env.C_Map.GetMapArtLayers = function()
        return { { layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256 } }
    end
    c.env.C_Map.GetMapArtLayerTextures = function()
        local out = {}
        for i = 1, 12 do out[i] = 1000 + i end
        return out
    end
    c.FG.RouteMap.Show(1453)
    T.eq(c.FG.RouteMap.Tiles(), 12, "four across, three down")
    T.eq(c.FG.RouteMap.MapID(), 1453)
    T.ok(c.FG.RouteMap.Shown())
    c.FG.RouteMap.Show(1429)
    T.eq(c.FG.RouteMap.MapID(), 1429, "and turns")
end

-- It was left unanchored the first time, when it had no reason to move.
function tests.theVeryFirstMark_landsOnTheMap()
    local c = Stack.new({ mapID = 1429, x = 0.45, y = 0.7 })
    c.FG.MapPreview.ShowPlaces("A Quest", { { mapID = 1429, x = 0.5, y = 0.5, role = "start", title = "Here" } })
    c:Advance(0.3)
    local overlay = c.env.ForeverGPSMapPreview
    T.ok(overlay:GetWidth() > 100, "the layer is as wide as the map")
    T.near(overlay:GetWidth(), c.FG.RouteMap.Canvas():GetWidth(), 1)
end

function tests.aMapWithNoArt_stillShowsTheJourney()
    local c = Start()
    c.env.C_Map.GetMapArtLayers = function() return {} end
    Plan(c, AUBERDINE)
    T.ok(c.FG.MapPreview.Open(), "the route, on plain ground")
    T.eq(c.FG.RouteMap.Tiles(), 0)
    c:Advance(0.3)
    T.ok(Strips(c) > 0, "drawn all the same")
    T.eq(#c.errors, 0)
end

function tests.aMapOpenedLater_stillShowsThePreview()
    local c = Start()
    c.env.WorldMapFrame:Hide()
    Plan(c, AUBERDINE)
    c.env.WorldMapFrame:Show()
    c:Advance(0.3)
    T.ok(Strips(c) > 0, "drawn on opening")
end

function tests.zoomingTheMap_redrawsThePreview()
    local c = Start()
    Plan(c, AUBERDINE)
    local before = c.FG.Metrics.Last("mapDraw")
    T.ok(before, "it was drawn")
    local canvas = c.env.WorldMapFrame.ScrollContainer.Child
    canvas:ClearAllPoints()
    canvas:SetPoint("TOPLEFT")
    canvas:SetSize(2000, 1400)
    c:Advance(0.3)
    T.ok(Strips(c) > 0, "still drawn at the new size")
end

function tests.aPlanCancelledMidway_cleansUp()
    local c = Start()
    c.FG.Planner.Inspect({ data = AUBERDINE, name = "Auberdine" })
    c:Advance(0.1, 0.05)
    c.FG.Planner.Clear()
    c:Advance(3)
    T.no(c.FG.Planner.Current(), "nothing lingers")
    T.no(c.FG.MapPreview.Showing())
    T.eq(#c.errors, 0, tostring(c.errors[1]))
end

function tests.aNewDestination_replacesOurOwnPlanAtOnce()
    local c = Start()
    c.FG.Planner.Inspect({ data = AUBERDINE, name = "Auberdine" })
    c:Advance(0.05, 0.05)
    local dest = { name = "Westfall", mapID = 1436, x = 0.5, y = 0.5 }
    c.FG.Planner.Inspect({ data = dest, name = dest.name })
    T.ok(Stack.Until(c, function() return c.FG.Planner.Current().status == "ready" end, 30), "the newer one finishes")
    T.eq(c.FG.Planner.Current().target.name, "Westfall", "and it is what shows")
end

function tests.aNewPlan_neverReplacesTheEnginesOwnWork()
    local c = Start()
    local replaced = false
    c.ns.GPS:Plan(nil, function()
        coroutine.yield()
        return "engine"
    end, function() replaced = true end, true)
    T.ok(c.FG.Bridge.IsPlanning(), "the engine is working")
    T.no(c.FG.Bridge.PlanIsOurs(), "and that is not ours")
    c.FG.Planner.Inspect({ data = AUBERDINE, name = "Auberdine" })
    T.ok(Stack.Until(c, function() return replaced end, 10), "the engine's plan was let finish")
end

function tests.goingBackToADestination_doesNotPlanAgain()
    local c = Start()
    local first = Plan(c, AUBERDINE)
    Plan(c, { name = "Westfall", mapID = 1436, x = 0.5, y = 0.5 })
    c.FG.Planner.Inspect({ data = AUBERDINE, name = "Auberdine" })
    T.ok(c.FG.Planner.Current() == first, "the plan is still good")
    T.eq(first.status, "ready", "and ready at once")
end

function tests.aRememberedPlan_isForgottenWhenFlightsAreLearned()
    local c = Start()
    local first = Plan(c, AUBERDINE)
    c:Fire("TAXIMAP_OPENED")
    c:Advance(0.5)
    c.FG.Planner.Inspect({ data = AUBERDINE, name = "Auberdine" })
    T.ok(c.FG.Planner.Current() ~= first, "planned afresh")
end

function tests.theWaysNotChosen_showFaintly()
    local c = Start({ mapID = 1429, x = 0.45, y = 0.7, level = 3 })
    local plan = Plan(c, { name = "Gadgetzan", mapID = 1446, x = 0.52, y = 0.28 })
    c.FG.MapPreview.Open()
    c:Advance(0.3)
    local distinct = 0
    for _, option in ipairs(plan.options) do
        if option.steps and not option.same and not option.noWay then distinct = distinct + 1 end
    end
    local alone = Strips(c)
    T.ok(alone > 0, "the chosen way")
    if distinct > 1 then
        local one = plan.selected
        for _, option in ipairs(plan.options) do
            if option ~= one then option.walks = nil end
        end
        c.FG.MapPreview._Redraw()
        T.ok(Strips(c) < alone, "with the others taken away there is less on the map")
    end
end

function tests.hoveringAStep_picksItOutWithoutMovingAnything()
    local c = Start()
    Plan(c, AUBERDINE)
    c.FG.MapPreview.Open()
    c:Advance(0.3)
    local viewed = c.env.WorldMapFrame:GetMapID()
    c.FG.MapPreview.Hover(1)
    T.eq(c.env.WorldMapFrame:GetMapID(), viewed, "the map stays where it is")
    c.FG.MapPreview.Hover(nil)
    T.eq(#c.errors, 0)
end

function tests.aJourneyAcrossContinents_canBeSteppedThrough()
    local c = Start()
    Plan(c, AUBERDINE)
    c.FG.MapPreview.Open()
    c:Advance(0.3)
    local legs = c.FG.MapPreview.Legs()
    T.eq(#legs, 2, "two lands")
    T.ok(legs[1].ci ~= legs[2].ci)
    local first = c.FG.RouteMap.MapID()
    c.FG.MapPreview.NextLeg()
    T.ok(c.FG.RouteMap.MapID() ~= first, "the map turns to the far side")
    c.FG.MapPreview.NextLeg()
    T.eq(c.FG.RouteMap.MapID(), legs[1].mapID, "and back round")
end

function tests.rides_areNamedOnTheMap()
    local c = Start()
    local plan = Plan(c, AUBERDINE)
    c.FG.MapPreview.Open()
    c:Advance(0.3)
    T.eq(plan.status, "ready")
    local tags = {}
    for _, mark in ipairs(c.FG.MapPreview._Marks()) do
        if mark:IsShown() and mark.tag:IsShown() then tags[#tags + 1] = mark.tag.text._text end
    end
    T.ok(#tags >= 1, "the boat's mark has words")
    T.has(table.concat(tags, ";"), "Auberdine", "and says where it goes: " .. table.concat(tags, ";"))
end

function tests.alternatives_sayHowTheyDiffer()
    local c = Start()
    local P = c.FG.Planner
    local a = { steps = { { kind = "taxi", text = "Fly" } }, total = 600, yards = 100, risk = { level = "low" }, quality = "detailed" }
    local b = { steps = { { kind = "travel", text = "Walk" } }, total = 900, yards = 900, risk = { level = "high" }, quality = "detailed" }
    local line = P.Compare(b, a)
    T.has(line, "+5 min", "the time")
    T.has(line, "no flight", "what it leaves out")
    T.has(line, "more on foot", "the walking")
    T.has(line, "more known hazards", "and the hazards")
    T.no(P.Compare(a, a), "nothing to say about itself")
end

function tests.identicalWays_areNotOfferedAsAChoice()
    local c = Start()
    local P = c.FG.Planner
    local base = { steps = {}, mode = { label = "MODE_FASTEST" } }
    local plan = { options = { base, { steps = {}, same = base, mode = { label = "MODE_ROADS" } } } }
    T.has(P.SameNote(plan, base), "Roads", "and it says so")
    T.no(P.SameNote({ options = { base } }, base), "nothing to say alone")
end

function tests.aRoute_saysHowSureItIs()
    local c = Start()
    local P = c.FG.Planner
    T.eq((P.Confidence({ quality = "detailed" })), "Fully mapped")
    T.eq((P.Confidence({ quality = "partial" })), "Partially estimated")
    T.eq((P.Confidence({ estimate = true })), "Estimated")
end

return tests
