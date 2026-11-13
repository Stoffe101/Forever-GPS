-- Undercity's GPS data on every classic client (issue #25, 2026-11-01):
-- the Ruins of Lordaeron's throne room, on the city's own map, stands for
-- the zone (its map's middle lies underground, which a walk reached
-- through the sewers), so a walk there is cut where it enters the Ruins'
-- gate; its three lifts link the Ruins' hall to the city both ways.
local H = require("Harness")

local FILES = {
    { "Data_Era.lua", "era", 1458, 1420 },
    { "Data_Forever.lua", "forever", 1458, 1420 },
    { "Data_TBC.lua", "tbc", 1458, 1420 },
    { "Data_Mists.lua", "mists", 998, 18 },
}

local function Load(file, cap)
    local env = H.newEnv()
    local ns = H.newNs(env)
    env.EasyFind._ns = ns
    ns.Caps = { [cap] = true }
    H.loadModule(file, env, ns)
    return assert(ns.GPSData, file .. " sets ns.GPSData")
end

local tests = {}

function tests.theRuinsThroneRoom_standsForUndercity()
    for _, f in ipairs(FILES) do
        local data = Load(f[1], f[2])
        local gate = data.gates and data.gates[f[3]]
        H.assertNotNil(gate, f[1] .. ": Undercity's gate")
        H.assertEq(gate.m, f[3], f[1] .. ": on the city's own map, so the walk ends on entering it")
        H.assertEq(gate.ci, 0)
        H.assertEq(gate.wx, 1598, "between the three lifts")
        H.assertEq(gate.wy, 243)
        H.assertTrue(gate.x > 0.65 and gate.x < 0.66 and gate.y > 0.43 and gate.y < 0.44, f[1] .. ": its place on that map")
    end
end

function tests.theThreeLifts_linkTheHallAndTheCityBothWays()
    for _, f in ipairs(FILES) do
        local data = Load(f[1], f[2])
        local n = 0
        for _, e in ipairs(data.edges) do
            if e.kind == "elevator" and e.dest == "Undercity" then
                n = n + 1
                H.assertTrue(e.bidir, f[1] .. ": ridden both ways")
                H.assertEq(e.from.m, f[3])
                H.assertEq(e.to.m, f[3])
                H.assertEq(e.from.area, 153, "the Ruins' hall names the way up")
                H.assertEq(e.to.area, 1497, "the city names the way down")
                H.assertTrue(e.sec and e.sec > 0)
            end
        end
        H.assertEq(n, 3, f[1] .. ": three lifts")
    end
end

-- The ticker rides a lift by the level's name under the player, never by
-- distance: its far door stands a few yards from its near one.
function tests.theTicker_ridesALiftByTheLevelsName()
    local f = assert(io.open(H.Path("GPS.lua"), "rb"))
    local src = f:read("*a")
    f:close()
    H.assertTrue(src:find('if step.kind == "elevator" then', 1, true) ~= nil, "the lift's own rule")
    H.assertTrue(src:find("GetSubZoneText", 1, true) ~= nil, "by the level's name")
    -- The east lift reads the Ruins at both ends (/efd gpslift, 2026-11-04).
    H.assertTrue(src:find("if OnLift(step) then step.boarded = true end", 1, true) ~= nil, "its platform stood on")
    H.assertTrue(src:find("not (through and through >= 1)", 1, true) ~= nil, "then out through the far door")
    H.assertTrue(src:find("step.reached, step.liftLevel, step.boarded = nil, nil, nil", 1, true) ~= nil,
        "a step tracked anew forgets the level it was boarded on and its platform")
end

-- StepText cut from GPS.lua, the player at pos on continent 0.
local function StepTextAt(pos)
    local f = assert(io.open(H.Path("GPS.lua"), "rb"))
    local src = f:read("*a")
    f:close()
    local sizes = {}
    for _, name in ipairs({ "local LIFT_ABOARD", "local REACH_YARDS" }) do
        sizes[#sizes + 1] = assert(src:match("\n(" .. name .. "[^\n]*)"), name)
    end
    local s = assert(src:find("-- A spot's world place", 1, true), "SpotWorld not in GPS.lua")
    local e = assert(src:find("GPS.StepText = StepText", s, true), "end of StepText not found")
    local env = setmetatable({
        ns = {}, L = {}, sformat = string.format,
        PlayerWorldPos = function() return 0, pos.x, pos.y end,
        WorldPos = function() return nil end,
        DepartureText = function() return nil end,
    }, { __index = _G })
    local chunk = table.concat(sizes, "\n") .. "\n" .. src:sub(s, e - 1) .. "\nreturn StepText"
    return assert(load(chunk, "=GPS.lua StepText", "t", env))()
end

-- On the platform the step said to take the lift still (2026-11-03): the
-- platform is the middle of its two doors (the north lift's shaft at
-- 1596, 292 between its foot and top doors), where the step says ride it.
function tests.onTheLiftsPlatform_theStepSaysRideIt()
    local pos = {}
    local StepText = StepTextAt(pos)
    local step = { kind = "elevator", text = "Take the elevator up", aboardText = "Ride the elevator up",
                   go = { ci = 0, wx = 1596.2, wy = 302.4 }, arrive = { ci = 0, wx = 1596.0, wy = 282.7 } }
    pos.x, pos.y = 1596.2, 302.4
    H.assertEq(StepText(step, true), "Take the elevator up", "at its door, waiting")
    pos.x, pos.y = 1596, 292
    H.assertEq(StepText(step, true), "Ride the elevator up", "on the platform")
    H.assertEq(StepText(step, false), "Take the elevator up", "a step ahead says what it will be")
    step.aboardText = nil
    H.assertEq(StepText(step, true), "Take the elevator up", "no line for the platform: the step's own")
end

local pass, fail, failures = H.runSuite("GPS Undercity", tests)
return { pass = pass, fail = fail, failures = failures }
