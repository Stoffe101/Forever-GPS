-- GPS's side of what EasyFind's map tests hold for the map tab: its steps
-- at the pop-out's size, its end mark cleared by a right-click, its places
-- drawn through EasyFind's PlaceList.
local H = require("Harness")

local function Read(rel)
    local f = assert(io.open(H.Path(rel), "rb"))
    local src = f:read("*a")
    f:close()
    return src
end

local tests = {}

-- The steps beside the map read at the pop-out's size: the game's small type.
function tests.theMapStepsMatchThePopout()
    H.assertEq(tonumber(Read("GPS.lua"):match("local MAP_STEP_PX = (%d+)")), 10)
end

function tests.theRoutesEndMarkClearsTheRoute()
    local src = Read("Preview.lua")
    local hit = src:match('local hit = CreateFrame%("Button".-marks%.hit = hit')
    H.assertTrue(hit ~= nil, "a button over the end mark")
    H.assertTrue(hit:find('RegisterForClicks%("RightButtonUp"%)') ~= nil, "it takes a right-click")
    H.assertTrue(hit:find("GPS:Clear()", 1, true) ~= nil, "which ends the route")
    H.assertTrue(src:find("marks.hit:SetAllPoints(mark)", 1, true) ~= nil, "laid over whichever end mark shows")
end

function tests.thePlacesDrawThroughPlaceList()
    H.assertTrue(Read("GPS.lua"):find("ns.PlaceList.New(", 1, true) ~= nil, "GPS.lua draws its places through PlaceList")
end

local pass, fail, failures = H.runSuite("GPSCoreParts", tests)
return { pass = pass, fail = fail, failures = failures }
