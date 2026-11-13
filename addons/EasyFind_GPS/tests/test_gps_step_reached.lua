-- A route told to hearth and fly to Thunder Bluff kept saying "Hearth"
-- after the player had flown straight there (Forever, 2026-11-10):
-- while a crossing is the step, a later step the player stands at is
-- taken up (GPS.lua GPS.StepReached), and standing on the destination's
-- map well away from where the crossing set out counts as off the route
-- (OffRoute), so the route starts over from here.
local H = require("Harness")

local function Source()
    local f = assert(io.open(H.Path("GPS.lua"), "rb"))
    local src = f:read("*a")
    f:close()
    return src
end

local function Slice(src, head)
    local s = assert(src:find(head, 1, true), head .. " not in GPS.lua")
    local _, e = src:find("\nend\r?\n", s)
    return src:sub(s, e)
end

local function Env(onMap)
    return setmetatable({
        GPS = {}, ns = {},
        ARRIVE = { yards = 40, spot = 8, cross = 300 }, LEFT_DOCK_YARDS = 400, OFF_ROUTE_YARDS = 250,
        PointWorld = function(p) if p then return p.ci, p.wx, p.wy end end,
        OnMap = function(mapID) return mapID == onMap end,
        ToSegment = function() return 0 end,
    }, { __index = _G })
end

-- Hearth to the inn at 0,0; fly from its master at 50,0 to Thunder Bluff's
-- at 5000,0; walk to the apothecary at 5300,0.
local function Route()
    return { active = 1, dest = { mapID = 1456 }, from = { ci = 1, wx = -2000, wy = 0 }, steps = {
        { kind = "teleport", arrive = { ci = 1, wx = 0, wy = 0 } },
        { kind = "taxi", go = { ci = 1, wx = 50, wy = 0 }, arrive = { ci = 1, wx = 5000, wy = 0 } },
        { kind = "travel", go = { ci = 1, wx = 5000, wy = 0 }, arrive = { ci = 1, wx = 5300, wy = 0 } },
    } }
end

local function Reached()
    local env = Env()
    assert(load(Slice(Source(), "function GPS.StepReached(route, ci, px, py)"), "=GPS.lua StepReached", "t", env))()
    return env.GPS.StepReached
end

local function OffRoute(onMap)
    local env = Env(onMap)
    return assert(load(Slice(Source(), "local function OffRoute(route, ci, px, py)") .. "\nreturn OffRoute",
        "=GPS.lua OffRoute", "t", env))()
end

local tests = {}

function tests.flownThere_theWalkIsTakenUp()
    local reached, route = Reached(), Route()
    H.assertEq(reached(route, 1, 5010, 5), 3, "at Thunder Bluff's flight master: the flight is behind, the walk is on")
    H.assertEq(reached(route, 1, 60, 0), 2, "at the inn's flight master: the hearth is behind, the flight is on")
    H.assertEq(reached(route, 1, 5290, 0), "arrive", "at the apothecary: the journey is over")
end

function tests.elsewhere_nothingChanges()
    local reached, route = Reached(), Route()
    H.assertNil(reached(route, 1, -1500, 0), "still at the start")
    H.assertNil(reached(route, 1, 2500, 0), "half way, by no step's spot")
    H.assertNil(reached(route, 0, 5010, 5), "another continent")
    route.active = 3
    H.assertNil(reached(route, 1, 60, 0), "a walk is the step: its own detours are the reroute's")
end

function tests.onTheDestinationsMap_awayFromTheStart_isOffTheRoute()
    local route = Route()
    H.assertTrue(OffRoute(1456)(route, 1, 4000, 200), "in Thunder Bluff, far from where the hearth was planned")
    H.assertFalse(OffRoute(1456)(route, 1, -1900, 0), "in Thunder Bluff where the plan set out: a hearth across the city")
    H.assertFalse(OffRoute(1413)(route, 1, 4000, 200), "not on the destination's map: the crossing stands")
    route.dest.zone = true
    H.assertFalse(OffRoute(1456)(route, 1, 4000, 200), "a zone destination arrives on its own")
end

function tests.theTickerAsksIt()
    local src = Source()
    H.assertTrue(src:find("local reached = GPS.StepReached(route, ci, px, py)", 1, true) ~= nil,
        "the route's tick takes up a reached step")
end

local pass, fail, failures = H.runSuite("GPSStepReached", tests)
return { pass = pass, fail = fail, failures = failures }
