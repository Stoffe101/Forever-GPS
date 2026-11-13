-- Kalimdor's lifts in each client's data: no walk climbs onto Thunder
-- Bluff's mesas or Freewind Post's, so with no flight point known the
-- route from Orgrimmar was a straight line (Forever, 2026-11-07).
local H = require("Harness")
local Inflate = require("Inflate")

local tests = {}

-- Thunder Bluff's map (1456) and Orgrimmar's (1454) on Kalimdor.
local RECTS = {
    [1456] = { -1545.83, -527.08, -850.0, 516.67 },
    [1454] = { 1338.46, -5083.21, 2273.88, -3680.6 },
}

local CLIENTS = {
    { caps = "forever", walk = "Walk_Kalimdor.lua", data = "Data_Forever.lua", lifts = 4 },
    { caps = "era", walk = "Walk_Kalimdor_Era.lua", data = "Data_Era.lua", lifts = 4 },
    { caps = "tbc", walk = "Walk_Kalimdor_TBC.lua", data = "Data_TBC.lua", lifts = 4 },
    -- Thousand Needles flooded: Thunder Bluff's two only.
    { caps = "mists", walk = "Walk_Kalimdor_Mists.lua", data = "Data_Mists.lua", lifts = 2 },
}

local function Source(file)
    local f = assert(io.open(H.Path(file), "rb"))
    local src = f:read("*a")
    f:close()
    return src
end

function tests.eachClientsData_hasKalimdorsLifts()
    for _, c in ipairs(CLIENTS) do
        local n = 0
        for line in Source(c.data):gmatch("[^\n]+") do
            if line:find('kind = "elevator"', 1, true) and line:find("ci = 1,", 1, true) then n = n + 1 end
        end
        H.assertEq(n, c.lifts, c.data .. ": Kalimdor's lifts")
    end
end

local function Route(client)
    local env = H.newEnv()
    local ns = H.newNs(env)
    env.EasyFind._ns = ns
    ns.Caps = { [client.caps] = true }
    env.C_EncodingUtil = { DecodeBase64 = Inflate.DecodeBase64, DecompressString = function(s) return Inflate.Raw(s) end }
    env.GetSubZoneText = function() return "" end
    env.GetZoneText = function() return "" end
    env.GetLocale = function() return "enUS" end
    for _, f in ipairs({ client.walk, "Floors.lua", "Nav.lua" }) do H.loadModule(f, env, ns) end
    ns.GPS = { PlayerWorldPos = function() return nil end }
    for _, f in ipairs({ "Locales/enUS.lua", client.data, "Route.lua" }) do H.loadModule(f, env, ns) end
    env.CreateVector2D = function(x, y) return { x = x, y = y, GetXY = function(v) return v.x, v.y end } end
    env.C_Map = {
        GetWorldPosFromMapPos = function(m, v)
            local r = RECTS[m]
            if not r then return nil end
            return 1, env.CreateVector2D(r[3] - v.y * (r[3] - r[1]), r[4] - v.x * (r[4] - r[2]))
        end,
        GetMapInfo = function(m) return { name = "Map " .. m } end,
    }
    return function(dest)
        return ns.GPSRoute:Build(dest,
            { data = ns.GPSData, start = { ci = 1, wx = 1630, wy = -4420, m = 1454, x = 0.5, y = 0.5 },
              faction = "Horde", canFly = false, groundSpeed = 7, known = {},
              owns = function() return false end, cooldown = function() return 0 end })
    end
end

local function Lift(steps)
    for _, s in ipairs(steps or {}) do if s.kind == "elevator" then return s end end
end

-- The city is reached at a lift's foot: the game puts you on its map there.
function tests.orgrimmarToThunderBluff_noFlightKnown_endsAtALiftsFoot()
    for _, c in ipairs({ CLIENTS[1], CLIENTS[2] }) do
        local steps = Route(c)({ name = "Thunder Bluff", mapID = 1456, x = 0.5, y = 0.5, zone = true })
        H.assertTrue(steps ~= nil and #steps > 0, c.data .. ": a way there")
        H.assertNil(Lift(steps), c.data .. ": no lift up after arriving")
        local last = steps and steps[#steps].arrive
        H.assertTrue(last ~= nil and (last.wx + 1029) ^ 2 + (last.wy + 30) ^ 2 < 15 * 15,
            c.data .. ": at the east lift's foot, the nearer from Orgrimmar")
    end
end

-- A spot up on the mesa: the walk rides a lift.
function tests.orgrimmarToTheMesa_noFlightKnown_ridesALift()
    for _, c in ipairs({ CLIENTS[1], CLIENTS[2] }) do
        local steps = Route(c)({ name = "Mesa", mapID = 1456, x = 0.4375, y = 0.5317 })
        H.assertNotNil(Lift(steps), c.data .. ": up a lift onto the mesa")
    end
end

local pass, fail, failures = H.runSuite("GPS Kalimdor lifts", tests)
return { pass = pass, fail = fail, failures = failures }
