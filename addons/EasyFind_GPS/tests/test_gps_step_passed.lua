-- A walk's step is done once its spot is passed on the way to the next
-- walk's (GPS.lua GPS.StepPassed): a corner cut past the step's pin never
-- leads back to it (it did, on Forever, until 250 yd off).
local H = require("Harness")

local function Load()
    local f = assert(io.open(H.Path("GPS.lua"), "rb"))
    local src = f:read("*a")
    f:close()
    local s = assert(src:find("function GPS.StepPassed(route, ci, px, py)", 1, true), "GPS.StepPassed not in GPS.lua")
    local _, e = src:find("\nend\r?\n", s)
    local GPS = {}
    local env = setmetatable({
        GPS = GPS,
        PointWorld = function(p) if p then return p.ci, p.wx, p.wy end end,
    }, { __index = _G })
    assert(load(src:sub(s, e), "=GPS.lua StepPassed", "t", env))()
    -- The step's spot at 0,0, the next walk's 1000 yd west.
    local route = { active = 1, steps = {
        { kind = "travel", arrive = { ci = 1, wx = 0, wy = 0 } },
        { kind = "travel", arrive = { ci = 1, wx = -1000, wy = 0 } },
    } }
    return GPS.StepPassed, route
end

local tests = {}

function tests.walkedPastThePin_nearerTheNextSpot_isDone()
    local Passed, route = Load()
    H.assertTrue(Passed(route, 1, -60, 80), "100 yd beside the pin and on past it")
    H.assertTrue(Passed(route, 1, -200, -100), "well past it, still within reach")
end

function tests.beforeThePin_orFarFromIt_isNot()
    local Passed, route = Load()
    H.assertTrue(not Passed(route, 1, 200, 0), "still coming to it")
    H.assertTrue(not Passed(route, 1, -5, 0), "abreast of it by a step: the arrival ring takes that")
    H.assertTrue(not Passed(route, 1, -400, 300), "500 yd from it: the reroute takes that")
    H.assertTrue(not Passed(route, 2, -60, 80), "on another continent")
end

function tests.onlyAWalkOnToAWalk()
    local Passed, route = Load()
    route.steps[2].kind = "taxi"
    H.assertTrue(not Passed(route, 1, -60, 80), "a flight boards at the spot")
    route.steps[2].kind = "travel"
    route.steps[1].kind = "learn"
    H.assertTrue(not Passed(route, 1, -60, 80), "a flight master to learn stays a stop")
    route.steps[1].kind = "travel"
    route.steps[1].inside = true
    H.assertTrue(not Passed(route, 1, -60, 80), "a building's hall is walked into")
    route.steps[1].inside = nil
    route.steps[2] = nil
    H.assertTrue(not Passed(route, 1, -60, 80), "the last step arrives at its spot")
end

function tests.theTickerAsksIt()
    local f = assert(io.open(H.Path("GPS.lua"), "rb"))
    local src = f:read("*a")
    f:close()
    H.assertTrue(src:find("if not planned and GPS.StepPassed(route, ci, px, py) then", 1, true) ~= nil,
        "the route's tick ends a passed step")
end

local pass, fail, failures = H.runSuite("GPSStepPassed", tests)
return { pass = pass, fail = fail, failures = failures }
