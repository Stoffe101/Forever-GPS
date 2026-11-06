-- The map's end emblem is solid (WorldPin.NewEmblem's solid, Preview.lua):
-- a disc in the theme's fill under the shape, masked round and repainted
-- with the theme. Open, the map's pins and art showed through its glass.
-- The world beacon keeps the open look.
local H = require("Harness")

local function Read(rel)
    local f = assert(io.open(H.Path(rel), "rb"))
    local s = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    return s
end

local tests = {}

function tests.theEmblemOffersASolidDisc()
    local src = Read("WorldPin.lua")
    local s = assert(src:find("function WorldPin.NewEmblem(parent, solid)", 1, true), "the option")
    local e = assert(src:find("\nend\n", s, true))
    local body = src:sub(s, e)
    H.assertTrue(body:find("if solid then", 1, true) ~= nil)
    H.assertTrue(body:find('ns.PORTRAIT_ALPHA_MASK, "CLAMPTOBLACKADDITIVE"', 1, true) ~= nil, "masked round")
    H.assertTrue(body:find('Tint(disc, "disc"', 1, true) ~= nil, "a theme role: repainted with the theme")
    H.assertTrue(body:find("function seat:Fit(size)", 1, true) ~= nil, "sized by the call that sizes the frame")
    H.assertTrue(body:find("disc:SetSize(size * DISC, size * DISC)", 1, true) ~= nil)
    H.assertTrue(body:find("HookScript", 1, true) == nil, "no size or show event: none runs while the map sizes it hidden")
    H.assertTrue(src:find("\n        disc = (pal and (pal.windowFillBottom or pal.windowFill))", 1, true) ~= nil,
        "the role is the theme's window fill")
end

function tests.theMapsEndIsSolid_theBeaconIsNot()
    local preview = Read("Preview.lua")
    H.assertTrue(preview:find("ns.GPSWorldPin.NewEmblem(overlay, true)", 1, true) ~= nil)
    H.assertTrue(preview:find("if mark.Fit then mark:Fit(size) else mark:SetSize(size, size) end", 1, true) ~= nil,
        "the map sizes the emblem through Fit")
    local pin = Read("WorldPin.lua")
    local n = 0
    for _ in pin:gmatch("NewEmblem%([%w_]+, true%)") do n = n + 1 end
    H.assertEq(n, 0, "the beacon's emblem stays open")
end

local pass, fail, failures = H.runSuite("GPSEndDisc", tests)
return { pass = pass, fail = fail, failures = failures }
