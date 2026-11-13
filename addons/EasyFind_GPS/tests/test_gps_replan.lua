-- A route planned again keeps its start: one from a place set in the From
-- field sets out from that place until the player reaches it, from the
-- player from then on, and its drawn way begins where the plan set out
-- (a route from The Crossroads was drawn from where the player stood, and
-- a start over dropped the start and the stops, 2026-11-08).
local H = require("Harness")

local function Source()
    local f = assert(io.open(H.Path("GPS.lua"), "rb"))
    local src = f:read("*a")
    f:close()
    return src
end

-- GPS.lua from anchor a to the end of the function last starts.
local function Slice(src, a, last)
    local s = assert(src:find(a, 1, true), a)
    local at = assert(src:find(last, s, true), last)
    local _, e = assert(src:find("\nend\r?\n", at))
    return src:sub(s, e)
end

local PLAYER = { m = 1, x = 0.5, y = 0.5, ci = 1, wx = 500, wy = 500 }
local ORIGIN = { m = 2, x = 0.2, y = 0.3, ci = 1, wx = 200, wy = 300 }

local function Load(route)
    local src = Source()
    local GPS, built, char = {}, {}, { route = route }
    local ns = { GPSTrip = { Build = function(stops, _, _, _, _, from)
        built.from, built.stops = from, stops
        return {}, 1
    end } }
    function GPS.PlayerStart() return PLAYER end
    function GPS:BuildRoute(dest, _, _, _, _, from)
        built.from, built.dest = from, dest
        return {}, 1
    end
    function GPS:Plan(_, build, done) done(build()) end
    function GPS:IsPlanning() return false end
    function GPS.ViaLeft() return nil end
    local env = setmetatable({ GPS = GPS, ns = ns, closing = {}, time = os.time,
        Route = function() return char.route end, CharDB = function() return char end,
        TrackStep = function() end, UnitIsGhost = function() return false end }, { __index = _G })
    local code = Slice(src, "function GPS.RouteStart(route)", "function GPS:BuildStops(route")
        .. Slice(src, "function GPS.Replanned(route", "function GPS.Rerouted(route")
        .. Slice(src, "function GPS.StopAdded(route", "function GPS.StopAdded(route")
        .. "\nreturn Reroute"
    local Reroute = assert(load(code, "=GPS.lua replan", "t", env))()
    return GPS, built, char, Reroute
end

local tests = {}

function tests.aRouteFromAPlace_plansAgainFromIt_untilReached()
    local GPS, built, char = Load({ dest = { name = "Thunder Bluff" }, origin = ORIGIN })
    GPS:BuildStops(char.route, nil, nil, true, "first")
    H.assertEq(built.from, ORIGIN, "from the start as set")
    H.assertEq(built.dest.name, "Thunder Bluff")
end

function tests.aRouteReached_orFromHere_plansAgainFromThePlayer()
    local GPS, built, char = Load({ dest = { name = "Thunder Bluff" }, origin = ORIGIN, joined = true })
    GPS:BuildStops(char.route)
    H.assertEq(built.from, false, "the player, whatever start is set")
    char.route = { dest = { name = "Thunder Bluff" } }
    GPS:BuildStops(char.route)
    H.assertEq(built.from, false)
end

function tests.aTripFromAPlace_startsItsFirstLegThere()
    local stops = { { name = "Ratchet" }, { name = "Thunder Bluff" } }
    local GPS, built, char = Load({ dest = { name = "Thunder Bluff" }, stops = stops, origin = ORIGIN })
    GPS:BuildStops(char.route)
    H.assertEq(built.from, ORIGIN)
    H.assertEq(built.stops, stops)
end

function tests.aStartOver_keepsTheStartAndStops_untilReached()
    local stops, skip = { { name = "Thunder Bluff" } }, { [7] = true }
    local _, built, char, Reroute = Load({ dest = { name = "Thunder Bluff" }, origin = ORIGIN, stops = stops,
                                           skipLearn = skip, report = {} })
    local before = char.route
    Reroute(before)
    local r = char.route
    H.assertTrue(r ~= before, "a new plan")
    H.assertEq(built.from, ORIGIN, "planned from the start as set")
    H.assertEq(r.origin, ORIGIN)
    H.assertEq(r.stops, stops)
    H.assertEq(r.skipLearn, skip)
    H.assertEq(r.from.wx, 200, "drawn from the start as set")
    H.assertEq(r.report.re, 1)
end

function tests.aStartOver_afterReachingTheStart_setsOutFromThePlayer()
    local _, built, char, Reroute = Load({ dest = { name = "Thunder Bluff" }, origin = ORIGIN, joined = true })
    Reroute(char.route)
    local r = char.route
    H.assertEq(built.from, false)
    H.assertEq(r.from.wx, 500, "drawn from the player")
    H.assertEq(r.origin, ORIGIN, "the start as set stays the trip's")
    H.assertTrue(r.joined, "reached stays reached")
end

function tests.aStopAdded_drawsFromWhereThePlanSetOut()
    local GPS, _, char = Load({ dest = { name = "Thunder Bluff" }, origin = ORIGIN, report = {} })
    GPS.StopAdded(char.route, nil, { id = 3 }, { { kind = "travel" } }, 10, nil)
    H.assertEq(char.route.from.wx, 200, "from the start as set")
    H.assertEq(char.route.report.via, 3)
    char.route.joined = true
    GPS.StopAdded(char.route, nil, {}, {}, 5, nil)
    H.assertEq(char.route.from.wx, 500, "from the player once the start is reached")
    H.assertEq(char.route.total, 5)
end

-- BuildRoute with no way through the data: a plain leg from its start.
-- false sets out from the player with a start set; nil from that start.
local function LoadBuild()
    local src = Source()
    local GPS = { PlayerStart = function() return { m = 1, x = 0.5, y = 0.5, ci = 2, wx = 500, wy = 500 } end }
    local env = setmetatable({ GPS = GPS, ns = {}, StartPoint = function() return ORIGIN end,
        WorldPos = function(_, x, y) return 2, x, y end, PlayerWorldPos = function() return 2, 500, 500 end,
        L = { GPS_STEP_NO_WAY_FMT = "no way to %s", GPS_STEP_TRAVEL_FMT = "to %s" }, sformat = string.format },
        { __index = _G })
    local code = Slice(src, "function GPS:BuildRoute(dest, via, avoid, quick, draw, startFrom, dropLimit)",
                       "function GPS:BuildRoute(dest")
    assert(load(code, "=GPS.lua BuildRoute", "t", env))()
    return GPS
end

function tests.buildRoute_falseSetsOutFromThePlayer_nilFromTheStartAsSet()
    local GPS = LoadBuild()
    local dest = { name = "Thunder Bluff", mapID = 1, x = 0.5, y = 0.5 }
    local steps = GPS:BuildRoute(dest, nil, nil, true, "first", false)
    H.assertNil(steps[1].noWay, "the player's continent is the spot's")
    steps = GPS:BuildRoute(dest, nil, nil, true, "first")
    H.assertTrue(steps[1].noWay, "the start as set is on another continent")
    steps = GPS:BuildRoute(dest, nil, nil, true, "first", ORIGIN)
    H.assertTrue(steps[1].noWay)
end

local pass, fail, failures = H.runSuite("GPSReplan", tests)
return { pass = pass, fail = fail, failures = failures }
