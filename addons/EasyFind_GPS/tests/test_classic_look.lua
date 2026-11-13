-- The Classic theme's own controls (the red buttons) follow the theme
-- itself (ns.ClassicLook); only the frame art follows the border choice
-- (ns.IsClassicChrome). Picking the line border for the search bar took
-- the red buttons off every window (2026-10-27).
local H = require("Harness")

local tests = {}

function tests.redButtonsFollowTheLook()
    local f = assert(io.open(H.Path("GPS.lua"), "rb"))
    local src = f:read("*a")
    f:close()
    H.assertNil(src:find("IsClassicChrome() and ns.PaintRedButton", 1, true), "GPS.lua: red buttons by the look")
end

local pass, fail, failures = H.runSuite("ClassicLook", tests)
return { pass = pass, fail = fail, failures = failures }
