-- Following a route: the real EasyFind GPS ticker advances the steps while the
-- pretend player moves, and Forever-GPS's view and HUD follow along.
local T = require("support.t")
local Stack = require("support.stack")

local AUBERDINE = { name = "Auberdine", mapID = 1439, x = 0.37, y = 0.44 }

local function Start(opts)
    opts = opts or {}
    opts.mapID, opts.x, opts.y = opts.mapID or 1453, opts.x or 0.6, opts.y or 0.6
    return Stack.new(opts)
end

local function Go(c, dest)
    local P = c.FG.Planner
    P.Inspect({ data = dest or AUBERDINE, name = (dest or AUBERDINE).name })
    T.ok(Stack.Until(c, function() return P.Current().status == "ready" end, 30), "planned")
    P.Start()
    c:Advance(1.5)
    return c.FG.Bridge.ActiveRoute()
end

-- Puts the player where a step ends, and lets the ticker see it.
local function Reach(c, step)
    local p = step.arrive
    c:SetPlayer(p.m, p.x, p.y)
    c:Advance(2.2)
end

local tests = {}

function tests.theStepsAdvanceAsThePlayerTravels()
    local c = Start()
    local route = Go(c, nil)
    T.eq(route.active, 1)
    Reach(c, route.steps[1])
    T.eq(c.FG.Bridge.Route().active, 2, "at the dock: the boat is next")
    Reach(c, route.steps[2])
    T.eq(c.FG.Bridge.Route().active, 3, "across the sea: recognized on arrival, the walk is next")
    local last = route.steps[3]
    c:SetPlayer(last.arrive.m, last.arrive.x, last.arrive.y)
    c:Advance(2.2)
    T.ok(c.FG.Bridge.Route().arrived, "there")
end

function tests.theHud_namesTheBoatAndStopsPointing()
    local c = Start()
    local route = Go(c, nil)
    Reach(c, route.steps[1])
    local view = c.FG.Journey.View()
    T.eq(view.kind, "boat")
    T.has(view.title:lower(), "boat", "a boat instruction: " .. view.title)
    T.has(view.title, "Auberdine", "with where it goes")
    T.eq(view.index, 2)
    T.eq(view.count, 3)
    -- Aboard: carried, no straight-line arrow across the sea.
    c.ns.GPSBoats.Carried = function() return true end
    view = c.FG.Journey.View()
    T.eq(view.state, "riding")
    T.no(view.pointing, "nothing to point at on a boat")
    T.no(view.yards, "and no meaningless distance")
end

function tests.theHud_namesTheFlightWhileFlying()
    local c = Start({ mapID = 1455, x = 0.55, y = 0.48 })
    local Route = c.ns.GPSRoute
    Route.recordedKnown = { [6] = true, [7] = true }
    Route.ForgetKnown()
    local route = Go(c, { name = "Menethil Harbor", mapID = 1437, x = 0.1, y = 0.6 })
    local index
    for i, s in ipairs(route.steps) do
        if s.kind == "taxi" then index = i end
    end
    T.ok(index, "a flight step")
    route.active = index
    c.player.taxi = true
    local view = c.FG.Journey.View()
    T.eq(view.state, "riding")
    T.no(view.pointing, "flying: no arrow")
    T.has(view.title, "Menethil", "says where to")
end

function tests.nextStep_isTheNextOneNotThisOneAgain()
    local c = Start()
    Go(c, nil)
    local view = c.FG.Journey.View()
    T.has(view.nextText, "Board the boat", "what comes after: " .. tostring(view.nextText))
    T.lacks(view.nextText, "Go to the dock", "not this step again")
end

function tests.theView_followsDistanceAndProgress()
    local c = Start()
    Go(c, nil)
    local view = c.FG.Journey.View()
    T.ok(view.yards and view.yards > 100, "yards left on the walk: " .. tostring(view.yards))
    T.ok(view.eta and view.eta > 100, "time left")
    T.near(view.progress, 0, 0.1, "at the start")
end

function tests.wanderingOff_rebuildsTheRouteWithoutFlapping()
    local c = Start()
    local route = Go(c, nil)
    T.ok(route, "under way")
    local rebuilt = 0
    local real = c.ns.GPS.Rerouted
    c.ns.GPS.Rerouted = function(...)
        rebuilt = rebuilt + 1
        return real(...)
    end
    -- Four frames a second here, so planning takes game time it would not.
    c:SetPlayer(1429, 0.2, 0.8)
    c:Advance(60, 0.25)
    T.ok(rebuilt >= 1, "a new route from here")
    T.ok(rebuilt <= 2, "and once, not constantly: " .. rebuilt .. " in a minute")
    local now = c.FG.Bridge.ActiveRoute()
    T.eq(now.dest.name, "Auberdine", "to the same place")
    T.eq(now.active, 1, "from the start of the new way")
end

-- Upstream's parachute tip tried the route at "any drop" and left the grid there,
-- which lost the route's walks: off-route checks went quiet, and new walks could
-- cross lethal drops.
function tests.afterTheOtherWays_theGridIsBackOnTheRoutesSettings()
    local c = Start()
    local route = Go(c, nil)
    T.ok(Stack.Until(c, function() return route.others ~= nil end, 60), "the other ways are worked out")
    T.no(c.FG.Bridge.IsPlanning(), "and done")
    T.eq(c.ns.GPSNav.epoch % 3, 1, "the character's own drop limit, not unlimited")
    local Follow, Engine = c.ns.GPSFollow, c.ns.GPSRoute
    local sci, sx, sy = Follow.StartOf(route, 1)
    local tci, tx, ty = Follow.World(route.steps[1].go)
    T.eq(sci, tci)
    T.ok(Engine.WalkPath(sci, sx, sy, tx, ty, true, route.steps[1].near), "the route's walk can still be found")
end

function tests.aSmallDetour_doesNotReroute()
    local c = Start()
    local route = Go(c, nil)
    local rebuilt = 0
    local real = c.ns.GPS.Rerouted
    c.ns.GPS.Rerouted = function(...)
        rebuilt = rebuilt + 1
        return real(...)
    end
    c:SetPlayer(1453, 0.605, 0.605)
    c:Advance(12, 0.25)
    T.eq(rebuilt, 0, "a few yards off the line is no reason to replan")
    T.ok(c.FG.Bridge.ActiveRoute() == route, "the same route")
end

function tests.aRerouteInProgress_keepsTheModeChosen()
    local c = Start()
    local P = c.FG.Planner
    P.Inspect({ data = AUBERDINE, name = "Auberdine" })
    Stack.Until(c, function() return P.Current().status == "ready" end, 30)
    P.Select(P.Current().options[2])
    P.Start()
    c:Advance(1)
    local route = c.FG.Bridge.ActiveRoute()
    c:SetPlayer(1429, 0.2, 0.8)
    T.ok(Stack.Until(c, function() return c.FG.Bridge.ActiveRoute() ~= route end, 90), "a new route from here")
    T.ok(c.FG.Bridge.ActiveRoute().wayAvoid.danger, "still the safer way")
end

function tests.aReload_keepsTheRouteAndTheStep()
    local c = Start()
    local route = Go(c, nil)
    Reach(c, route.steps[1])
    T.eq(c.FG.Bridge.Route().active, 2)
    local saved = Stack.Saved(c)
    local after = Start({ saved = saved, mapID = c.player.mapID, x = c.player.x, y = c.player.y })
    after:Advance(1)
    local back = after.FG.Bridge.Route()
    T.ok(back, "the route survived")
    T.eq(back.dest.name, "Auberdine")
    T.eq(back.active, 2, "on the same step")
    local view = after.FG.Journey.View()
    T.ok(view and view.kind == "boat", "the HUD picks it up")
    T.ok(after.env.ForeverGPSHUD and after.env.ForeverGPSHUD:IsShown(), "shown without being asked")
end

function tests.aReload_afterTheQuestWentAway_stopsTheRoute()
    local quests = { { questID = 1, title = "Gone Soon", level = 5, objectives = {} } }
    local c = Start({ quests = quests })
    Go(c, nil)
    c.FG.Journey.Bind({ questID = 1, title = "Gone Soon", kind = "objective", index = 1 })
    local saved = Stack.Saved(c)
    local after = Start({ saved = saved, quests = {} })
    after:Advance(3)
    T.no(after.FG.Bridge.ActiveRoute(), "stopped")
    T.no(after.FG.Journey.Binding(), "and forgotten")
end

function tests.anOldRoute_isNotRevivedAfterHours()
    local c = Start()
    Go(c, nil)
    local saved = Stack.Saved(c)
    local after = Start({ saved = saved, now = c.now + 3 * 60 * 60 })
    after:Advance(1)
    T.no(after.FG.Bridge.Route(), "a route from another day is noise")
end

function tests.dying_leadsToTheCorpseThenCarriesOn()
    local c = Start()
    Go(c, nil)
    local steps = #c.FG.Bridge.Route().steps
    c.player.corpse = { x = 0.61, y = 0.61 }
    c.player.ghost = true
    c:Advance(2.2)
    local view = c.FG.Journey.View()
    T.eq(view.step.corpse, true, "the ghost goes to the corpse first")
    T.eq(c.FG.Bridge.Route().active, 1)
    c.player.ghost = false
    c.player.corpse = nil
    c:Fire("PLAYER_UNGHOST")
    c:Advance(2.2)
    T.eq(#c.FG.Bridge.Route().steps, steps, "risen: that step goes")
    T.no(c.FG.Journey.View().step.corpse, "and the route carries on")
end

function tests.stopping_clearsEverything()
    local c = Start()
    Go(c, nil)
    T.ok(c.env.ForeverGPSHUD:IsShown(), "HUD up")
    c.FG.StopNavigation()
    c:Advance(1)
    T.no(c.FG.Bridge.Route(), "no route")
    T.no(c.env.ForeverGPSHUD:IsShown(), "no HUD")
end

function tests.arriving_saysSoThenGoesAway()
    local c = Start()
    local route = Go(c, nil)
    for _, step in ipairs(route.steps) do Reach(c, step) end
    T.ok(c.FG.Bridge.Route().arrived, "arrived")
    T.has(c.FG.Journey.View().title, "Arrived", "the HUD says so")
    c:Advance(10)
    T.no(c.FG.Bridge.Route(), "and lets go")
    T.no(c.env.ForeverGPSHUD:IsShown())
end

function tests.aRouteStartedElsewhere_stillGetsTheHud()
    local c = Start()
    c.ns.GPS:NavigateTo({ name = "Auberdine", mapID = 1439, x = 0.37, y = 0.44 }, { quiet = true })
    T.ok(Stack.Until(c, function() return c.FG.Bridge.ActiveRoute() ~= nil end, 20), "planned by EasyFind GPS itself")
    c:Advance(1)
    T.ok(c.env.ForeverGPSHUD:IsShown(), "an Alt-click on the map still gets the HUD")
end

function tests.exactlyOneArrowLeads()
    local c = Start()
    Go(c, nil)
    local db = c.env.EasyFind.db
    T.eq(c.FG.db.arrow, "hud")
    T.no(c.env.EasyFindGPSArrow and c.env.EasyFindGPSArrow:IsShown(), "the HUD's arrow: EasyFind's own stands down")
    c.FG.db.arrow = "character"
    c.FG.Journey.ApplyArrow()
    c:Advance(0.5)
    T.ok(c.env.EasyFindGPSArrow and c.env.EasyFindGPSArrow:IsShown(), "at the character: EasyFind's own")
    T.eq(db.gpsArrow, nil, "and neither wrote to its settings")
    T.no(c.env.ForeverGPSHUD.arrow:IsShown(), "and the HUD's stands down")
end

function tests.theBeacon_knowsAnArrowLeads()
    local c = Start()
    Go(c, nil)
    c:Advance(1)
    T.ok(c.ns.GPSArrow:Guiding(), "so it draws no second, edge-of-screen arrow")
end

function tests.tomtom_isOptionalAndGetsOneWaypoint()
    local added, removed = {}, {}
    local TomTom = {
        AddWaypoint = function(_, m, x, y, opts)
            added[#added + 1] = { m = m, x = x, y = y, opts = opts }
            return #added
        end,
        RemoveWaypoint = function(_, uid) removed[#removed + 1] = uid end,
    }
    local c = Start({ tomtom = TomTom })
    c.FG.db.arrow = "tomtom"
    c.FG.Journey.ApplyArrow()
    local route = Go(c, nil)
    T.eq(#added, 1, "one waypoint")
    T.eq(added[1].opts.persistent, false, "that does not outlive the route")
    Reach(c, route.steps[1])
    c.ns.GPSBoats.Carried = function() return true end
    c:Advance(0.5)
    T.ok(#removed >= 1, "taken down at the boat: a line across the sea helps nobody")
    c.FG.StopNavigation()
    c:Advance(0.5)
    T.eq(#added, #removed, "and nothing is left behind")
end

function tests.withoutTomtom_itsSettingFallsBack()
    local c = Start()
    c.FG.db.arrow = "tomtom"
    T.eq(c.FG.Journey.ArrowMode(), "hud", "not installed: the HUD leads")
    Go(c, nil)
    T.eq(#c.errors, 0)
end

function tests.inCombat_nothingProtectedIsTouched()
    local c = Start()
    Go(c, nil)
    c.player.combat = true
    c:Fire("PLAYER_REGEN_DISABLED")
    c:Advance(1)
    c.FG.Window.Show("search")
    c:Advance(0.5)
    c.FG.Window.Hide()
    T.eq(#c.errors, 0, "the window and HUD work in combat")
    local cast = c.env.ForeverGPSCastButton
    T.ok(not cast or not cast:IsShown(), "the secure button is out of the way")
    T.ok(not cast or cast:GetNumPoints() == 0, "and holds no anchor that would protect the HUD")
end

function tests.aHearthStep_offersTheHearthstone()
    local c = Start({ bags = { [6948] = 1 } })
    local route = Go(c, nil)
    route.steps[1].kind = "teleport"
    route.steps[1].itemID = 6948
    route.steps[1].go = nil
    c:Advance(1)
    local cast = c.env.ForeverGPSCastButton
    T.ok(cast and cast:IsShown(), "the button is there")
    T.eq(cast:GetAttribute("type"), "item")
    T.eq(cast:GetAttribute("item"), "item:6948")
    T.ok(cast:GetParent() == c.env.UIParent, "and hangs from UIParent, never the HUD")
    T.no(c.FG.Journey.View().pointing, "a cast is nothing to walk to")
end

return tests
