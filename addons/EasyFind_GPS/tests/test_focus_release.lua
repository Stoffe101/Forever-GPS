-- An edit box of ours drops its focus on a click anywhere but on it
-- (EasyFind's Utils.ReleaseFocusOnOutsideClick): the client kept the GPS
-- boxes focused through clicks elsewhere on Era (2026-10-28).
local H = require("Harness")

local function Read(rel)
    local f = assert(io.open(H.Path(rel), "rb"))
    local src = f:read("*a")
    f:close()
    return src
end

local tests = {}

function tests.everySearchBoxOfTheGpsReleases()
    H.assertTrue(Read("GPS.lua"):find("box:SetMaxLetters%(60%)%s+Utils%.ReleaseFocusOnOutsideClick%(box%)") ~= nil,
        "the GPS search box")
    H.assertTrue(Read("Trip.lua"):find("box:SetMaxLetters%(60%)%s+ns%.Utils%.ReleaseFocusOnOutsideClick%(box%)") ~= nil,
        "a trip's field")
end

local pass, fail, failures = H.runSuite("FocusRelease", tests)
return { pass = pass, fail = fail, failures = failures }
