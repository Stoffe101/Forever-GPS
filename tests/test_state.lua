-- State that must survive, or must not leak: what inspecting routes does to the
-- route being followed, what a route's own settings do to its walks, and what a
-- trip keeps when it is rebuilt. Every test here stands for a defect found in the
-- audit, on the real engine.
local T = require("support.t")
local Stack = require("support.stack")

local AUBERDINE = { name = "Auberdine", mapID = 1439, x = 0.37, y = 0.44 }

local function Start(opts)
    opts = opts or {}
    opts.mapID, opts.x, opts.y = opts.mapID or 1453, opts.x or 0.6, opts.y or 0.6
    return Stack.new(opts)
end

local function Plan(c, dest)
    local P = c.FG.Planner
    P.Inspect({ data = dest, name = dest.name })
    T.ok(Stack.Until(c, function()
        local p = P.Current()
        return p.status == "ready" or p.status == "failed" or p.status == "unreachable"
    end, 30), "the plan finishes")
    return P.Current()
end

local function Settings(c) return c.ns.GPSNav.epoch end

local function WalkOf(c, route, i)
    local Follow, Engine = c.ns.GPSFollow, c.ns.GPSRoute
    local sci, sx, sy = Follow.StartOf(route, i)
    local tci, tx, ty = Follow.World(route.steps[i].go or route.steps[i].arrive)
    return Engine.WalkPath(sci, sx, sy, tx, ty, true, route.steps[i].near)
end

local tests = {}

-- A started Safer route must have its walks drawn under Safer's settings.
function tests.aSaferRoute_keepsItsSettingsOnceStarted()
    local c = Start()
    local plan = Plan(c, AUBERDINE)
    local safer = plan.options[2]
    T.eq(safer.mode.key, "safer")
    c.FG.Planner.Select(safer)
    c.FG.Planner.Start()
    c:Advance(1)
    local route = c.FG.Bridge.ActiveRoute()
    T.ok(route.wayAvoid.danger, "the route says Safer")
    T.ok(Settings(c) >= 3, "and the grid is on Safer's settings: epoch " .. Settings(c))
end

function tests.aSaferRoute_keepsItsSettingsAcrossAReload()
    local c = Start()
    local plan = Plan(c, AUBERDINE)
    c.FG.Planner.Select(plan.options[2])
    c.FG.Planner.Start()
    c:Advance(1)
    local after = Start({ saved = Stack.Saved(c) })
    after:Advance(1)
    T.ok(after.FG.Bridge.Route().wayAvoid.danger, "still Safer")
    T.ok(Settings(after) >= 3, "and walks redrawn after a reload use its settings: epoch " .. Settings(after))
end

function tests.inspectingLeavesTheRouteUnderWayExactlyAsItWas()
    local c = Start()
    Plan(c, AUBERDINE)
    c.FG.Planner.Start()
    T.ok(Stack.Until(c, function() return c.FG.Bridge.ActiveRoute().others ~= nil end, 90), "settled")
    local route = c.FG.Bridge.ActiveRoute()
    local before = { active = route.active, total = route.total, steps = #route.steps, epoch = Settings(c), t = route.t }
    local walk = WalkOf(c, route, 1)
    T.ok(walk, "its walk is there")
    Plan(c, { name = "Westfall", mapID = 1436, x = 0.5, y = 0.5 })
    Plan(c, { name = "Duskwood", mapID = 1431, x = 0.5, y = 0.5 })
    c.FG.Planner.Clear()
    c:Advance(1)
    T.ok(c.FG.Bridge.ActiveRoute() == route, "the same route")
    T.eq(route.active, before.active)
    T.eq(route.total, before.total)
    T.eq(#route.steps, before.steps)
    T.eq(route.t, before.t, "not restarted")
    T.eq(Settings(c), before.epoch, "the grid is back on its settings")
    T.ok(WalkOf(c, route, 1) == walk, "and the very same walk is found")
end

local function Stop(name, mapID, x, y) return { name = name, mapID = mapID, x = x, y = y } end

local function Trip(c, stops)
    local GPS = c.ns.GPS
    local done
    GPS:Plan("trip", function() return c.ns.GPSTrip.Build(stops, nil, nil, true, "first") end, function(steps, total, advice)
        GPS.Navigated(stops[#stops], steps, total, advice, stops)
        done = true
    end)
    T.ok(Stack.Until(c, function() return done end, 40), "the trip plans")
    c:Advance(0.5)
    return c.FG.Bridge.ActiveRoute()
end

local function Stops3()
    return { Stop("One", 1429, 0.42, 0.65), Stop("Two", 1429, 0.32, 0.5), Stop("Three", 1436, 0.56, 0.47) }
end

function tests.aTrip_keepsItsStopsThroughReroutes()
    local c = Start({ mapID = 1429, x = 0.4, y = 0.6 })
    Trip(c, Stops3())
    local rebuilt = 0
    local real = c.ns.GPS.Rerouted
    c.ns.GPS.Rerouted = function(...)
        rebuilt = rebuilt + 1
        return real(...)
    end
    T.ok(Stack.Until(c, function() return c.FG.Bridge.ActiveRoute().others ~= nil end, 90), "settled")
    c:SetPlayer(1436, 0.2, 0.2)
    T.ok(Stack.Until(c, function() return rebuilt >= 1 end, 90), "rebuilt once")
    local route = c.FG.Bridge.ActiveRoute()
    T.ok(route.stops, "the stops are kept")
    T.eq(#route.stops, 3, "all three")
end

function tests.aTrip_doesNotGoBackToStopsAlreadyReached()
    local c = Start({ mapID = 1429, x = 0.4, y = 0.6 })
    local route = Trip(c, Stops3())
    -- Reach the end of the first stop's leg.
    local firstLeg
    for i, s in ipairs(route.steps) do
        if s.tripStop then
            firstLeg = i
            break
        end
    end
    T.ok(firstLeg, "the first leg ends at a stop")
    route.active = firstLeg + 1
    T.eq(#c.ns.GPS.StopsAhead(route), 2, "the first is behind")
    T.ok(Stack.Until(c, function() return c.FG.Bridge.ActiveRoute().others ~= nil end, 90), "settled")
    local rebuilt = 0
    local real = c.ns.GPS.Rerouted
    c.ns.GPS.Rerouted = function(...)
        rebuilt = rebuilt + 1
        return real(...)
    end
    c:SetPlayer(1436, 0.2, 0.2)
    T.ok(Stack.Until(c, function() return rebuilt >= 1 end, 90), "rebuilt")
    local now = c.FG.Bridge.ActiveRoute()
    T.eq(#now.stops, 2, "only what is left")
    T.eq(now.stops[1].name, "Two", "starting with the next one")
    for _, step in ipairs(now.steps) do
        T.no(step.tripStop and step.tripStop.name == "One", "the reached stop is not revisited")
    end
end

function tests.stopsAhead_survivesASavedRoute()
    -- Saved variables come back as copies, so a stop is matched by what it is.
    local c = Start({ mapID = 1429, x = 0.4, y = 0.6 })
    local route = Trip(c, Stops3())
    local firstLeg
    for i, s in ipairs(route.steps) do
        if s.tripStop then
            firstLeg = i
            break
        end
    end
    route.active = firstLeg + 1
    local after = Start({ saved = Stack.Saved(c), mapID = 1429, x = 0.4, y = 0.6 })
    local back = after.FG.Bridge.Route()
    T.ok(back and back.stops, "the trip came back")
    T.eq(#after.ns.GPS.StopsAhead(back), 2, "and knows what is behind it")
end

function tests.firstRun_leavesAnExistingEasyFindUserAlone()
    local c = Start({ saved = { EasyFindDB = { tutorialDone = true, visible = true, dbVersion = 27 } } })
    T.ok(c.env.EasyFind.db.visible ~= false, "their search bar stays")
end

function tests.firstRun_remembersWhatItChanged()
    local c = Start()
    local db = c.FG.db
    T.ok(db.easyFindBefore, "what it changed is kept, so it can be put back")
    T.ok(c.FG.Settings.RestoreEasyFind, "and there is a way to")
    c.FG.Settings.RestoreEasyFind()
    T.ok(c.env.EasyFind.db.visible ~= false, "the bar is back")
end

function tests.theHudArrow_writesNothingToEasyFindsSettings()
    local c = Start()
    T.eq(c.env.EasyFind.db.gpsArrow, nil, "removing Forever-GPS must leave EasyFind's arrow as it was")
    Plan(c, AUBERDINE)
    c.FG.Planner.Start()
    c:Advance(1)
    T.no(c.env.EasyFindGPSArrow and c.env.EasyFindGPSArrow:IsShown(), "and it stands down all the same")
    c.FG.db.arrow = "character"
    c.FG.Journey.ApplyArrow()
    c:Advance(0.5)
    T.eq(c.env.EasyFind.db.gpsArrow, nil, "choosing it writes nothing either")
end

function tests.settingsFrom1_0_0_survive()
    local c = Start({ saved = {
        ForeverGPSDB = { schema = 1, theme = "glacier", firstRunDone = true, arrow = "hud",
                         hud = { enabled = false, scale = 1.2 }, window = { scale = 0.9, width = 700 },
                         favorites = { { name = "Home", data = { name = "Home", mapID = 1429, x = 0.5, y = 0.5 } } } },
        ForeverGPSCharDB = { schema = 1, mode = "safer", recents = { { name = "Bank", data = { name = "Bank", mapID = 1453, x = 0.6, y = 0.8 } } } },
        EasyFindDB = { tutorialDone = true, gpsArrow = false, dbVersion = 27 },
    } })
    local db, char = c.FG.db, c.FG.char
    T.eq(db.theme, "glacier", "theme kept")
    T.eq(db.hud.enabled, false, "HUD choice kept")
    T.eq(db.hud.scale, 1.2)
    T.eq(db.window.width, 700)
    T.eq(#db.favorites, 1, "favorites kept")
    T.eq(#char.recents, 1, "recents kept")
    T.eq(char.mode, "safer")
    T.eq(db.schema, c.FG.Settings.SCHEMA, "and moved to the current schema")
    T.eq(c.env.EasyFind.db.gpsArrow, nil, "1.0.0's write to EasyFind's arrow setting is undone")
end

function tests.startingMidPlan_leavesTheGridAsTheRouteNeedsIt()
    local c = Stack.new({ ui = false, mapID = 1453, x = 0.6, y = 0.6 })
    local P, Nav = c.FG.Planner, c.ns.GPSNav
    P.Inspect({ data = { name = "Auberdine", mapID = 1439, x = 0.37, y = 0.44 }, name = "Auberdine" })
    T.ok(Stack.Until(c, function()
        local plan = P.Current()
        return plan.status == "partial"
    end, 30), "the first way is found")
    P.Start()
    T.ok(Stack.Until(c, function() return not c.FG.Bridge.IsPlanning() end, 30), "and the rest wind down")
    c:Advance(0.5)
    local left = Nav.epoch
    c.FG.Bridge.RestoreNav()
    T.eq(left, Nav.epoch, "the grid is back on the route's settings")
end

return tests
