-- A zone as the journey's end (Preview.lua EndOnMap, PinEnd): its middle
-- is the end, marked with the emblem, never the map's pin (a zone has no
-- spot for one). Before, a zone had no end at all: a route to Loch Modan
-- ended in a bare line.
local H = require("Harness")

local function Load(pinned)
    local f = assert(io.open(H.Path("Preview.lua"), "rb"))
    local src = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    local s = assert(src:find("local endSpot = {}", 1, true), "endSpot")
    local e = select(2, assert(src:find("MapSearch:PinRouteEnd(dest, x, y)\nend\n", s, true)))
    local env = setmetatable({
        ns = { MapSearch = { PinRouteEnd = function(_, dest, x, y) pinned[#pinned + 1] = { dest = dest, x = x, y = y } end,
                             GetActivePinState = function() return nil end } },
        World = function(p) return p.ci, p.wx, p.wy end,
        C_Map = { GetMapPosFromWorldPos = function() return nil end },
        CreateVector2D = function(x, y) return { x = x, y = y } end,
    }, { __index = _G })
    return assert(load(src:sub(s, e) .. "\nreturn EndOnMap, PinEnd", "=Preview.lua end", "t", env))()
end

local LOCH_MODAN = 48
local tests = {}

function tests.aZonesMiddleIsTheEnd_withTheEmblemNotThePin()
    local pinned = {}
    local EndOnMap, PinEnd = Load(pinned)
    local route = { dest = { name = "Loch Modan", mapID = LOCH_MODAN, x = 0.5, y = 0.5, zone = true, icon = 1 } }
    local x, y = EndOnMap(route, LOCH_MODAN)
    H.assertEq(x, 0.5)
    H.assertEq(y, 0.5)
    PinEnd(route, LOCH_MODAN)
    H.assertEq(#pinned, 0, "no map pin on a zone: the emblem marks it")
end

function tests.aSpotStillGetsTheMapsPin()
    local pinned = {}
    local EndOnMap, PinEnd = Load(pinned)
    local route = { dest = { name = "Thelsamar Inn", mapID = LOCH_MODAN, x = 0.34, y = 0.49, icon = 1 } }
    H.assertEq(EndOnMap(route, LOCH_MODAN), 0.34)
    PinEnd(route, LOCH_MODAN)
    H.assertEq(#pinned, 1)
    H.assertEq(pinned[1].x, 0.34)
end

local pass, fail, failures = H.runSuite("GPSZoneEnd", tests)
return { pass = pass, fail = fail, failures = failures }
