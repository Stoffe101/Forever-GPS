-- A stop on the way with a face or icon of its own is marked on the map
-- with it, as the journey's end is, not with the stop disc over the
-- place's own pin (Thrall's, 2026-10-27); only the journey's end takes
-- the right-click that ends the route. Each leg's last step says which
-- stop it reaches (Trip.lua, Trip.Build) for that.
local H = require("Harness")

local function Read(rel)
    local f = assert(io.open(H.Path(rel), "rb"))
    local src = f:read("*a")
    f:close()
    return src
end

local function LoadTrip()
    local env = H.newEnv()
    local ns = H.newNs(env)
    env.EasyFind._ns = ns
    ns.GPS = {
        CurrentRoute = function() return nil end,
        WorldPos = function(mapID, x, y) return 0, mapID * 100 + x, y end,
        BuildRoute = function(_, dest) return { { kind = "travel", name = dest.name } }, 10, nil end,
    }
    H.loadModule("Trip.lua", env, ns)
    return ns.GPSTrip
end

local tests = {}

-- Under its own name: a crossing's step carries its stop number as
-- step.stop, and the map indexed that number (2026-10-27).
function tests.eachLegsLastStepKnowsItsStop()
    local Trip = LoadTrip()
    local a, b = { name = "A", mapID = 1 }, { name = "B", mapID = 2 }
    local steps = Trip.Build({ a, b })
    H.assertEq(steps[1].tripStop, a)
    H.assertEq(steps[2].tripStop, b)
    H.assertNil(steps[1].stop, "a crossing's stop number keeps its field")
end

function tests.aStopWearsItsOwnIcon()
    local src = Read("Preview.lua")
    H.assertTrue(src:find("hovered%.final and route%.dest or hovered%.step%.tripStop") ~= nil,
        "the leg's end: the destination or the trip's stop")
    H.assertTrue(src:find("hovered%.step%.stop%f[^%w_]") == nil, "never the crossing's stop number")
    H.assertTrue(src:find("if hovered%.final then%s+marks%.hit:SetAllPoints%(mark%)") ~= nil,
        "the right-click hit on the journey's end alone")
end

-- The journey's end wears the map's own pin (round icon, glow, the arrow
-- above) whichever way it was picked: a pick in the pop-out or a trip's
-- field never reached the map tab's pin, so only map tab picks had it
-- (2026-10-27). Placed as the route or the map shown changes, and again
-- as the map opens; a pin cleared by hand stays cleared meanwhile. Not on
-- a pin the map placed itself (test_gps_game_pin_end.lua).
function tests.theEndWearsTheMapsPinFromAnyPick()
    local src = Read("Preview.lua")
    H.assertTrue(src:find("local changed = drawn%.route ~= route or drawn%.map ~= mapID") ~= nil
        and src:find("if changed and not gamePin then PinEnd%(route, mapID%) end") ~= nil,
        "placed as the route or the map changes")
    H.assertTrue(src:find("drawn%.map = nil%s+since = 0%.1") ~= nil, "and again as the map opens")
    H.assertTrue(src:find("and %(dest%.icon or dest%.displayID or dest%.category%)%) then return end") ~= nil,
        "a place with a face, an icon or a kind gets the pin; a map click (none of those) keeps the emblem alone")
    H.assertTrue(src:find("local x, y = EndOnMap%(route, mapID%)%s+if not x or PinAtEnd%(route, mapID%) then return end%s+MapSearch:PinRouteEnd%(dest, x, y%)") ~= nil,
        "on the spot where the end falls on the map shown, its own map or another")
    H.assertTrue(src:find("if hovered and hovered%.b and hovered%.final and %(gamePin or PinAtEnd%(route, mapID%)%) then") ~= nil,
        "with the pin on the end, nothing of ours is drawn over it")
    local nav = Read("MapSearch/Navigation.lua")
    H.assertTrue(nav:find("function MapSearch:PinRouteEnd%(dest, x, y%)%s+if self%._previewing") ~= nil)
    H.assertTrue(nav:find("pinHoverClearsOverride = false%s+self:ShowWaypointAt%(x, y, dest%.icon, dest%.category, nil, dest%.displayID%)") ~= nil,
        "the pin stays until a right-click, as a direct map tab pick's")
end

-- Clear route left the end's pin when the click that started the route
-- had placed it (the Greater Duskbat's face stayed on the map,
-- 2026-11-02): the pin on the journey's end goes with the route either way.
function tests.theEndsPinGoesWithTheRoute()
    local src = Read("GPS.lua")
    local s = assert(src:find("function GPS:Clear(opts)", 1, true))
    local e = assert(src:find("\nend\n", s, true))
    local body = src:sub(s, e)
    local pin = body:find("MapSearch:ClearPinAt(dest.mapID, dest.x, dest.y)", 1, true)
    H.assertTrue(pin ~= nil, "the pin at the route's end cleared")
    H.assertTrue(pin < body:find("CharDB()", 1, true), "before the route is let go")
end

local pass, fail, failures = H.runSuite("GPSStopMark", tests)
return { pass = pass, fail = fail, failures = failures }
