-- A tower with two zeppelins (GitHub EasyFind #26, Forever 2026-11-07):
-- "Board the zeppelin to Orgrimmar" at Tirisfal's tower did not say which
-- of its docks, the walk there was done 40 yd out (the other dock's master
-- stands 39 yd from Durotar's Undercity dock), and the other zeppelin
-- counted as boarded. The step names the dock's master and the tower's
-- side, the walk ends nearer that dock than any other, and only a ride
-- leaving that dock is the step's.
local H = require("Harness")
local Inflate = require("Inflate")

local tests = {}

local function Data(file, cap)
    local env = H.newEnv()
    local ns = H.newNs(env)
    env.EasyFind._ns = ns
    ns.Caps = { [cap] = true }
    H.loadModule(file, env, ns)
    return assert(ns.GPSData, file)
end

local function Engine(npcs)
    local env = H.newEnv()
    local ns = H.newNs(env)
    env.EasyFind._ns = ns
    ns.Caps = { forever = true }
    env.GetLocale = function() return "enUS" end
    H.loadModule("Locales/enUS.lua", env, ns)
    H.loadModule("Route.lua", env, ns)
    ns.Npcs = npcs
    return ns.GPSRoute, ns
end

local function Catalog(flavor)
    local env = H.newEnv()
    local ns = H.newNs(env)
    env.EasyFind._ns = ns
    ns.Caps = { [flavor:lower()] = true, instanceTable = true }
    env.GetLocale = function() return "enUS" end
    env.C_EncodingUtil = { DecodeBase64 = Inflate.DecodeBase64, DecompressString = function(s) return Inflate.Raw(s) end }
    ns.MapSearch = {}
    ns.MapSearchSearch = { PreparePOI = function(p) return p end }
    -- The catalog and its reader are EasyFind's own (Database, MapSearch).
    H.loadModule("Database/Npcs_" .. flavor .. ".lua", env, ns)
    H.loadModule("MapSearch/Npcs.lua", env, ns)
    return ns.Npcs
end

-- Each classic tower's docks, by where the zeppelin goes.
local DOCKS = {
    { name = "Tirisfal, to Orgrimmar", p = { ci = 0, wx = 2062, wy = 293 }, side = "GPS_SIDE_W", master = "Zapetta" },
    { name = "Tirisfal, to Grom'gol", p = { ci = 0, wx = 2063, wy = 235 }, side = "GPS_SIDE_E", master = "Hin Denburg" },
    { name = "Durotar, to Undercity", p = { ci = 1, wx = 1318, wy = -4658 }, side = "GPS_SIDE_SE", master = "Frezza" },
    { name = "Durotar, to Grom'gol", p = { ci = 1, wx = 1361, wy = -4631 }, side = "GPS_SIDE_NW", master = "Snurk Bucksquick" },
    { name = "Grom'gol, to Orgrimmar", p = { ci = 0, wx = -12464, wy = 232 }, side = "GPS_SIDE_S", master = "Nez'raz" },
    { name = "Grom'gol, to Undercity", p = { ci = 0, wx = -12407, wy = 212 }, side = "GPS_SIDE_N", master = "Squibby Overspeck" },
}

function tests.eachClassicTower_saysWhichSideEachDockIsOn()
    local Route = Engine(nil)
    for _, file in ipairs({ { "Data_Forever.lua", "forever" }, { "Data_Era.lua", "era" }, { "Data_TBC.lua", "tbc" } }) do
        local data = Data(file[1], file[2])
        for _, d in ipairs(DOCKS) do
            local others, side, gap = Route._TowerDocks(data, d.p, "zeppelin")
            H.assertEq(side, d.side, file[1] .. ": " .. d.name)
            H.assertEq(#others, 1, file[1] .. ": " .. d.name .. ", the tower's one other dock")
            H.assertTrue(gap > 45 and gap < 65, d.name .. ": the docks " .. tostring(gap) .. " yd apart")
        end
    end
end

-- Forever's own creatures: the master beside each dock, never the one
-- standing nearer the tower's other dock.
function tests.eachDock_namesTheMasterStandingAtIt()
    local Npcs = Catalog("Forever")
    local Route = Engine(nil)
    local data = Data("Data_Forever.lua", "forever")
    for _, d in ipairs(DOCKS) do
        local others = Route._TowerDocks(data, d.p, "zeppelin")
        H.assertEq(Npcs.TitledNear("Zeppelin Master", d.p.ci, d.p.wx, d.p.wy, 40, others), d.master, d.name)
    end
end

function tests.theStep_namesTheMasterAndTheSide()
    local Route = Engine({ TitledNear = function() return "Zapetta" end })
    local data = Data("Data_Forever.lua", "forever")
    local text, gap = Route._ZeppelinStep(data, DOCKS[1].p, "Orgrimmar")
    H.assertEq(text, "Board the zeppelin to Orgrimmar at Zapetta (west side)")
    H.assertTrue(gap > 55 and gap < 60)
    -- No catalog (Mists): the side alone.
    Route = Engine(nil)
    H.assertEq((Route._ZeppelinStep(data, DOCKS[1].p, "Orgrimmar")), "Board the zeppelin to Orgrimmar (west side)")
end

-- Tirisfal to Orgrimmar, no flights: the walk to the tower ends nearer
-- the Orgrimmar dock than the Grom'gol one, the step names the dock.
function tests.tirisfalToOrgrimmar_theWalkEndsAtItsDock()
    local env = H.newEnv()
    local ns = H.newNs(env)
    env.EasyFind._ns = ns
    ns.Caps = { forever = true }
    env.C_EncodingUtil = { DecodeBase64 = Inflate.DecodeBase64, DecompressString = function(s) return Inflate.Raw(s) end }
    env.GetSubZoneText = function() return "" end
    env.GetZoneText = function() return "" end
    env.GetLocale = function() return "enUS" end
    for _, f in ipairs({ "Walk_EasternKingdoms.lua", "Walk_Kalimdor.lua", "Floors.lua", "Nav.lua" }) do H.loadModule(f, env, ns) end
    ns.GPS = { PlayerWorldPos = function() return nil end }
    for _, f in ipairs({ "Locales/enUS.lua", "Data_Forever.lua", "Route.lua" }) do H.loadModule(f, env, ns) end
    ns.Npcs = { TitledNear = function(_, _, x) return x == 2062 and "Zapetta" or "Hin Denburg" end }
    env.CreateVector2D = function(x, y) return { x = x, y = y, GetXY = function(v) return v.x, v.y end } end
    local ORG = { 1338.46, -5083.21, 2273.88, -3680.6 }
    env.C_Map = {
        GetWorldPosFromMapPos = function(m, v)
            if m ~= 1454 then return nil end
            return 1, env.CreateVector2D(ORG[3] - v.y * (ORG[3] - ORG[1]), ORG[4] - v.x * (ORG[4] - ORG[2]))
        end,
        GetMapInfo = function(m) return { name = "Map " .. m } end,
    }
    local steps = ns.GPSRoute:Build({ name = "Orgrimmar", mapID = 1454, x = 0.5, y = 0.5, zone = true },
        { data = ns.GPSData, start = { ci = 0, wx = 2150, wy = 300, m = 1420, x = 0.6, y = 0.6 },
          faction = "Horde", canFly = false, groundSpeed = 7, known = {},
          owns = function() return false end, cooldown = function() return 0 end })
    local zep, walk
    for i, s in ipairs(steps or {}) do
        if s.kind == "zeppelin" then zep, walk = s, steps[i - 1] end
    end
    H.assertNotNil(zep, "a zeppelin step")
    H.assertEq(zep.text, "Board the zeppelin to Orgrimmar at Zapetta (west side)")
    H.assertTrue(walk and walk.approach, "the walk to the tower before it")
    H.assertTrue(walk.arriveYards and walk.arriveYards < 20, "done within " .. tostring(walk.arriveYards) .. " yd, not 40")
    H.assertEq(walk.go.wx, 2062, "the Orgrimmar dock")
end

-- A ride from the tower's other dock is not the step's.
function tests.theOtherZeppelin_isNotBoarded()
    local env = H.newEnv()
    local ns = H.newNs(env)
    env.EasyFind._ns = ns
    env.EasyFind.db = {}
    local pos = { ci = 0, x = 0, y = 0 }
    local clock = { t = 1000 }
    env.C_Map = {
        GetBestMapForUnit = function() return 5 end,
        GetPlayerMapPosition = function() return { GetXY = function() return 0.5, 0.5 end } end,
        GetWorldPosFromMapPos = function() return pos.ci, { GetXY = function() return pos.x, pos.y end } end,
    }
    env.IsPlayerMoving = function() return false end
    env.GetServerTime = function() return clock.t end
    env.GetRealmName = function() return "Realm" end
    ns.GPSData = { routes = {
        [302] = { period = 300, stops = { { ci = 1, wx = 1318, wy = -4658, at = 0 }, { ci = 0, wx = 2062, wy = 293, at = 150 } } },
        [301] = { period = 300, stops = { { ci = 0, wx = -12407, wy = 212, at = 0 }, { ci = 0, wx = 2063, wy = 235, at = 150 } } },
    } }
    H.loadModule("Boats.lua", env, ns)
    local Boats = ns.GPSBoats
    local function step(x, y)
        pos.x, pos.y = x, y
        clock.t = clock.t + 1
        Boats._Sample()
    end
    -- On the Grom'gol zeppelin's deck at Tirisfal, then carried off.
    step(2063, 238)
    step(2063, 238)
    step(2050, 238)
    H.assertTrue(Boats.Carried(), "carried")
    H.assertFalse(Boats.Aboard(0, 2050, 238, 0, 2062, 293), "not the Orgrimmar zeppelin")
    H.assertTrue(Boats.Aboard(0, 2050, 238, 0, 2063, 235), "the Grom'gol one")
end

local pass, fail, failures = H.runSuite("GPS zeppelin docks", tests)
return { pass = pass, fail = fail, failures = failures }
