-- The game's waypoint and super-track, changed from GPS only through
-- GPS.GamePinChange (EasyFind's MapSearch.WaypointChange): under an open
-- world map a change rebuilds the game's waypoint pin in our name and its
-- Shift-click share is refused (CopyToClipboard). A bare ClearUserWaypoint
-- did it again (Forever, 2026-11-10).
local H = require("Harness")

local CALLS = { "SetUserWaypoint%(", "ClearUserWaypoint%(", "SetSuperTracked%w*%(", "ClearAllSuperTrackedVignettes%(" }

local tests = {}

function tests.noBareWaypointChangesOutsideTheWaits()
    local p = assert(io.popen('git -C "' .. H.ADDON_ROOT .. '" ls-files "*.lua"'))
    local bad = {}
    for path in p:lines() do
        if not (path:find("^tests/") or path:find("^dev/")) then
            local f = assert(io.open(H.ADDON_ROOT .. "/" .. path, "rb"))
            local n = 0
            for line in f:read("*a"):gmatch("([^\n]*)\n?") do
                n = n + 1
                line = line:gsub("\r$", "")
                local code = line:gsub("%-%-.*$", "")
                for _, call in ipairs(CALLS) do
                    if code:find(call) and not code:find("GamePinChange%(") and not code:find("WaypointChange%(")
                        and not code:find("^%s*local ") then
                        bad[#bad + 1] = path .. ":" .. n .. ": " .. line:gsub("^%s+", "")
                    end
                end
            end
            f:close()
        end
    end
    p:close()
    H.assertEq(#bad, 0, "change the game's waypoint through GPS.GamePinChange:\n  " .. table.concat(bad, "\n  "))
end

-- Mid-route, a game icon on the end hides EasyFind's route-end pin alone:
-- the route's waypoint and its tracking stay.
function tests.aGameIconOnTheEnd_hidesThePinAlone()
    local f = assert(io.open(H.Path("Preview.lua"), "rb"))
    local src = f:read("*a")
    f:close()
    H.assertTrue(src:find("ns.MapSearch:HideRouteEnd()", 1, true) ~= nil)
    H.assertTrue(src:find("ns.MapSearch:ClearRouteEnd()", 1, true) == nil, "never the whole clear mid-route")
end

local pass, fail, failures = H.runSuite("GPSWaypointWaits", tests)
return { pass = pass, fail = fail, failures = failures }
