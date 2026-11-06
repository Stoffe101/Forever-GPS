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

function tests.settingsFrom2_0_0_survive()
    local c = Start({ saved = {
        ForeverGPSDB = { schema = 2, theme = "parchment", firstRunDone = true, arrow = "tomtom",
                         easyFindBefore = { visible = true }, reducedMotion = true,
                         hud = { enabled = true, mode = "detailed", opacity = 0.5, scale = 1.3, point = { "TOP", "TOP", 10, -200 } },
                         window = { scale = 1.1, width = 900, point = { "CENTER", "CENTER", 40, 20 } },
                         map = { preview = false }, minimap = { shown = false, angle = 90 },
                         favorites = { { name = "Home", data = { name = "Home", mapID = 1429, x = 0.5, y = 0.5 } } } },
        ForeverGPSCharDB = { schema = 2, mode = "roads", recents = { { name = "Bank", data = { name = "Bank", mapID = 1453, x = 0.6, y = 0.8 } } } },
    } })
    local db, char = c.FG.db, c.FG.char
    T.eq(db.theme, "parchment", "theme kept")
    T.eq(db.arrow, "tomtom", "arrow kept")
    T.eq(db.reducedMotion, true)
    T.eq(db.hud.mode, "detailed", "HUD kept")
    T.eq(db.hud.opacity, 0.5)
    T.eq(db.hud.scale, 1.3)
    T.eq(db.hud.point[4], -200, "and where it sits")
    T.eq(db.window.width, 900, "window kept")
    T.eq(db.window.point[3], 40)
    T.eq(db.map.preview, false, "map choices kept")
    T.eq(db.minimap.angle, 90)
    T.eq(#db.favorites, 1, "favorites kept")
    T.eq(#char.recents, 1, "recents kept")
    T.eq(char.mode, "roads", "the way picked first kept")
    T.eq(db.schema, c.FG.Settings.SCHEMA, "moved to the current schema")
    T.no(db.easyFindBefore, "what no longer means anything is gone")
    T.eq(c.env.EasyFind.db.visible, false, "and the bar stays away, with no saved settings of its own")
end

local function Imported(extra)
    local data = { id = "test", accounts = { {
        gpsAvoid = { boat = true },
        gpsBoats = { ["Realm"] = { [11616] = { epoch = 100, seen = 50 } } },
        gpsChar = { ["Name-Realm"] = { flights = { [6] = true, [7] = true } } },
        gpsHearth = { ["Name-Realm"] = { m = 1429, x = 0.4, y = 0.6 } },
        visible = true, someBarSetting = 3,
    } } }
    for k, v in pairs(extra or {}) do data[k] = v end
    return data
end

function tests.whatTheOldFoldersSaved_comesAcross()
    local c = Start({ saved = { ForeverGPSImported = Imported() } })
    local ef = c.env.EasyFind.db
    T.ok(ef.gpsChar["Name-Realm"].flights[7], "flight paths come across")
    T.eq(ef.gpsBoats["Realm"][11616].epoch, 100, "boat timings")
    T.eq(ef.gpsHearth["Name-Realm"].m, 1429, "the hearth")
    T.ok(ef.gpsAvoid.boat, "what was avoided")
    T.no(ef.someBarSetting, "and nothing of the old search bar's")
    T.eq(ef.visible, false, "which stays away")
    T.eq(c.env.ForeverGPSDB.importedFrom, "test", "noted as done")
end

function tests.anImport_appliesOnceAndNeverOverwrites()
    local c = Start({ saved = {
        ForeverGPSImported = Imported(),
        ForeverGPSDB = { importedFrom = "older" },
        EasyFindDB = { gpsChar = { ["Name-Realm"] = { flights = { [6] = false } }, ["Other-Realm"] = { flights = { [9] = true } } } },
    } })
    local ef = c.env.EasyFind.db
    T.eq(ef.gpsChar["Name-Realm"].flights[6], false, "what is here now stands")
    T.ok(ef.gpsChar["Name-Realm"].flights[7], "what is missing is added")
    T.ok(ef.gpsChar["Other-Realm"].flights[9], "others untouched")
    local again = Start({ saved = {
        ForeverGPSImported = Imported(),
        ForeverGPSDB = { importedFrom = "test" },
        EasyFindDB = { gpsChar = {} },
    } })
    T.no(again.env.EasyFind.db.gpsChar["Name-Realm"], "a second login changes nothing")
end

function tests.theHudArrow_writesNothingToEasyFindsSettings()
    local c = Start()
    T.eq(c.env.EasyFind.db.gpsArrow, nil, "the character arrow's own setting is left alone")
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
    T.eq(db.hud.scale, 1.2, "a chosen size kept")
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
