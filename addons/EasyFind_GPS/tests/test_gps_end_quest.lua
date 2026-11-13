-- A route's last step to a quest in the log tracks the quest itself
-- (GPS.EndQuest, TrackStep): the game's waypoint pin, set on each step's
-- end, drew over the quest's own icon after the map reopened (Forever,
-- 2026-11-10). The beacon stands on the tracked quest, and the watch that
-- lets go of the route when the player picks a quest leaves this one be.
local H = require("Harness")

local function Read(path)
    local f = assert(io.open(H.Path(path), "rb"))
    local src = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    return src
end

local function LoadEndQuest(inLog, superTrack)
    local src = Read("GPS.lua")
    local s = assert(src:find("function GPS.EndQuest(route, index)", 1, true))
    local _, e = assert(src:find("\nend\n", s, true))
    local env = setmetatable({
        GPS = {},
        C_SuperTrack = superTrack ~= false and { SetSuperTrackedQuestID = function() end } or nil,
        C_QuestLog = { GetLogIndexForQuestID = function(id) return inLog[id] end },
    }, { __index = _G })
    assert(load(src:sub(s, e), "=GPS.lua EndQuest", "t", env))()
    return env.GPS.EndQuest
end

local function Route(questID, n)
    local steps = {}
    for i = 1, n do steps[i] = { kind = "travel" } end
    return { dest = { name = "Turn in", questID = questID }, steps = steps }
end

local tests = {}

function tests.theLastStepToALogQuest_tracksTheQuest()
    local EndQuest = LoadEndQuest({ [42] = 3 })
    H.assertEq(EndQuest(Route(42, 3), 3), 42)
    H.assertNil(EndQuest(Route(42, 3), 2), "earlier steps keep the game's pin")
end

function tests.aQuestNotInTheLog_orNoQuestTracking_keepsThePin()
    H.assertNil(LoadEndQuest({})(Route(42, 1), 1), "a quest to take: our button, the pin under it")
    H.assertNil(LoadEndQuest({ [42] = 1 }, false)(Route(42, 1), 1), "a client without quest tracking")
    H.assertNil(LoadEndQuest({ [42] = 1 })(Route(nil, 1), 1), "no quest")
end

function tests.trackStep_theWatch_andTheBeacon_takeTheQuest()
    local gps = Read("GPS.lua")
    H.assertTrue(gps:find("local quest = GPS.EndQuest(route, index)", 1, true) ~= nil)
    H.assertTrue(gps:find("if step.inside or quest then GPS.DropPin(route) end", 1, true) ~= nil,
        "the pin a step before set goes")
    H.assertTrue(gps:find("if not route.untracked then GPS.TrackQuest(quest) end", 1, true) ~= nil)
    H.assertTrue(gps:find("ST.GetSuperTrackedQuestID() == route.questTracked then\n                return", 1, true) ~= nil,
        "the watch leaves the route's own quest be")
    H.assertTrue(gps:find("questID = data.questID", 1, true) ~= nil and gps:find("questID = dest.questID", 1, true) ~= nil,
        "the quest kept from the row and on a new plan")
    local pin = Read("WorldPin.lua")
    H.assertTrue(pin:find("return ST.GetSuperTrackedQuestID() == route.questTracked", 1, true) ~= nil,
        "the beacon stands on the tracked quest")
    H.assertTrue(Read("QuestDirections.lua"):find("questID = questID }", 1, true) ~= nil)
end

local pass, fail, failures = H.runSuite("GPSEndQuest", tests)
return { pass = pass, fail = fail, failures = failures }
