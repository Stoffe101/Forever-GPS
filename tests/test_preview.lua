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
    T.eq(c.env.WorldMapFrame:GetMapID(), 1439, "the last walk is in Darkshore")
    c.FG.MapPreview.Focus(3)
    T.eq(c.FG.MapPreview.Focused(), nil, "again shows them all")
end

function tests.opening_doesNothingWhenThereIsNothingToShow()
    local c = Start()
    T.no(c.FG.MapPreview.Open(), "no plan")
    T.eq(#c.errors, 0)
end

function tests.inCombat_theMapIsNotOpenedForYou()
    local c = Start()
    Plan(c, AUBERDINE)
    c.env.WorldMapFrame:Hide()
    c.player.combat = true
    T.no(c.FG.MapPreview.Open(), "left to the player")
    T.no(c.env.WorldMapFrame:IsShown())
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

return tests
