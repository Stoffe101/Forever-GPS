-- Undercity's stacked floors on the shipped Era grid (Floors.lua with
-- Floors_Era.lua): a route to an auctioneer ended on the upper ring above
-- the auction house, the grid's highest floor there (2026-11-03). A spot
-- takes the floor at its spawn's height, the player the floor the client
-- names by sub-zone, and walks and arrivals keep to those floors.
local H = require("Harness")
local Inflate = require("Inflate")

local tests = {}

local TILE = 1600 / 3
local ORIGIN = 32 * TILE
local CAIN = { 1648.2, 224.2, -56.8 }          -- an auctioneer, on the auction house floor
local BAT_HANDLER = { 1567.1, 266.3, -43.0 }   -- on the upper ring
local NORTH_FOOT = { 1596.2, 302.4 }           -- the north elevator's foot door
local NORTH_TOP = { 1596.0, 282.7 }            -- and its top one in the Ruins

-- Each client's grid and table; Forever's Undercity is a model of its own.
local CLIENTS = {
    { caps = "era", walk = "Walk_EasternKingdoms_Era.lua", floors = "Floors_Era.lua", data = "Data_Era.lua", cells = 5000 },
    { caps = "tbc", walk = "Walk_EasternKingdoms_TBC.lua", floors = "Floors_TBC.lua", data = "Data_TBC.lua", cells = 5000 },
    { caps = "forever", walk = "Walk_EasternKingdoms.lua", kalimdor = "Walk_Kalimdor.lua", floors = "Floors_Forever.lua",
      data = "Data_Forever.lua", cells = 2000, kalimdorCells = 1000 },
}

local function Load(client, player)
    local env = H.newEnv()
    local ns = H.newNs(env)
    env.EasyFind._ns = ns
    ns.Caps = { [client.caps] = true }
    env.C_EncodingUtil = { DecodeBase64 = Inflate.DecodeBase64, DecompressString = function(s) return Inflate.Raw(s) end }
    env.GetSubZoneText = function() return player.sub end
    env.GetZoneText = function() return player.zone or "Undercity" end
    env.GetLocale = function() return "enUS" end
    H.loadModule(client.walk, env, ns)
    if client.kalimdor then H.loadModule(client.kalimdor, env, ns) end
    H.loadModule(client.floors, env, ns)
    H.loadModule("Floors.lua", env, ns)
    H.loadModule("Nav.lua", env, ns)
    ns.GPS = { PlayerWorldPos = function() if player.x then return player.ci or 0, player.x, player.y end end }
    return ns, env
end

local function Era(player) return Load(CLIENTS[1], player) end

local function U16(s, i)
    local hi, lo = s:byte(2 * i - 1, 2 * i)
    return hi * 256 + lo
end

-- The height Nav puts (x, y) at on continent ci (0 unless given), and the
-- heights of every floor stacked in that cell.
local function HeightAt(ns, x, y, ci)
    ci = ci or 0
    local key, g, cell = ns.GPSNav.Probe(ci, x, y, false, true)
    local t = ns.GPSNav._worlds[ci].tiles[key]
    local first, n = U16(t.cf, cell + 1), U16(t.cf, cell + 2) - U16(t.cf, cell + 1)
    local all = {}
    for rank = 0, n - 1 do all[#all + 1] = ns.GPSFloors.Height(ci, key, cell, rank) end
    return ns.GPSFloors.Height(ci, key, cell, g - first), all
end

-- Each stacked cell's floor count on the client's shipped grid, per
-- continent in its table; the counts by continent.
local function MatchedCells(client)
    local ns = Load(client, { sub = "" })
    local Nav, checked = ns.GPSNav, {}
    for ci, data in pairs(ns.GPSFloorData) do
        checked[ci] = 0
        for key, s in pairs(data.cells) do
            local tx, ty = math.floor(key / 64), key % 64
            Nav.Probe(ci, ORIGIN - ty * TILE - TILE / 2, ORIGIN - tx * TILE - TILE / 2, false, true)
            local t = Nav._worlds[ci].tiles[key]
            H.assertNotNil(t, "continent " .. ci .. " tile " .. key .. " on the grid")
            local i = 1
            while i <= #s do
                local cell, n = tonumber(s:sub(i, i + 3), 16), tonumber(s:sub(i + 4, i + 4), 16)
                local shipped = U16(t.cf, cell + 2) - U16(t.cf, cell + 1)
                if shipped ~= n then
                    H.assertEq(shipped, n, "continent " .. ci .. " tile " .. key .. " cell " .. cell .. " floors")
                end
                checked[ci] = checked[ci] + 1
                i = i + 5 + 4 * n
            end
        end
    end
    return checked
end

-- A stacked cell of the Cavern of Mists (the cave at the Wailing Caverns'
-- entrance) on Forever: the cave's floor under the Barrens' hill. Its
-- floors are named only by their zone (the cave's pieces carry none).
local function CavernCell(ns)
    local data = ns.GPSFloorData[1]
    local cave = data.cities[1].box
    for key, s in pairs(data.cells) do
        local tx, ty = math.floor(key / 64), key % 64
        local i = 1
        while i <= #s do
            local cell, n = tonumber(s:sub(i, i + 3), 16), tonumber(s:sub(i + 4, i + 4), 16)
            local zoneNamed = false
            for r = 0, n - 1 do
                if tonumber(s:sub(i + 7 + 4 * r, i + 8 + 4 * r), 16) == 255 then zoneNamed = true end
            end
            local row, col = math.floor(cell / 133), cell % 133
            local x = ORIGIN - ty * TILE - TILE + (row + 0.5) * TILE / 133
            local y = ORIGIN - tx * TILE - TILE + (col + 0.5) * TILE / 133
            if n >= 2 and zoneNamed and x >= cave[1] and x <= cave[3] and y >= cave[2] and y <= cave[4] then
                return x, y
            end
            i = i + 5 + 4 * n
        end
    end
end

-- Inside the cave the client calls the place Wailing Caverns; on the hill
-- over it, the Barrens: the same spot takes the cave's floor only there.
function tests.theCavesFloor_isTakenWhereTheClientNamesTheCave()
    local player = { ci = 1, sub = "", zone = "Wailing Caverns" }
    local ns = Load(CLIENTS[3], player)
    local x, y = CavernCell(ns)
    H.assertNotNil(x, "a stacked cell of the Cavern of Mists")
    player.x, player.y = x, y
    local h, all = HeightAt(ns, x, y, 1)
    table.sort(all)
    H.assertTrue(#all >= 2, "floors stack there")
    H.assertEq(h, all[1], "in the cave: its floor, the lowest")
    player.zone = "The Barrens"
    ns = Load(CLIENTS[3], player)
    local above = HeightAt(ns, x, y, 1)
    H.assertTrue(above == nil or above > all[1], "on the hill: not the cave's floor")
end

function tests.eachTableMatchesItsShippedGrid()
    for _, client in ipairs(CLIENTS) do
        local checked = MatchedCells(client)
        H.assertTrue((checked[0] or 0) > client.cells, client.floors .. ": Undercity's stacked cells: " .. tostring(checked[0]))
        if client.kalimdor then
            H.assertTrue((checked[1] or 0) > client.kalimdorCells,
                client.floors .. ": Kalimdor's stacked cells: " .. tostring(checked[1]))
        end
    end
end

function tests.aSpotTakesItsSpawnsFloor()
    local ns = Era({ sub = "" })
    H.assertTrue(math.abs(HeightAt(ns, CAIN[1], CAIN[2]) - CAIN[3]) < 1.5, "the auctioneer on the auction house floor")
    H.assertTrue(math.abs(HeightAt(ns, NORTH_FOOT[1], NORTH_FOOT[2]) + 41) < 1.5, "the elevator's foot in the city")
    H.assertNil(HeightAt(ns, NORTH_TOP[1], NORTH_TOP[2]), "its top in the Ruins: one floor, nothing to pick")
end

-- The east hall's floor is a "Canals" piece of the city's model.
function tests.thePlayerTakesTheFloorNamedLikeTheSubZone()
    local player = { x = CAIN[1], y = CAIN[2], sub = "Canals" }
    local ns = Era(player)
    H.assertTrue(math.abs(HeightAt(ns, CAIN[1], CAIN[2]) - CAIN[3]) < 1.5, "Canals: the auction house floor")
    player.sub = "Trade Quarter"
    H.assertTrue(math.abs(HeightAt(ns, CAIN[1], CAIN[2]) - BAT_HANDLER[3]) < 1.5, "Trade Quarter: the ring above it")
    player.x, player.y = BAT_HANDLER[1], BAT_HANDLER[2]
    H.assertTrue(math.abs(HeightAt(ns, BAT_HANDLER[1], BAT_HANDLER[2]) - BAT_HANDLER[3]) < 1.5, "the ring")
end

-- A trip from the north auctioneers drew its walk to the elevator through
-- the sewers once the player had left: no spawn by the start, the Ruins
-- over it was taken (2026-11-04).
local NORTH_AH = { 1656.7, 255.4 }

function tests.aTripsStart_keepsItsFloorOnceThePlayerHasLeft()
    local player = { x = NORTH_AH[1], y = NORTH_AH[2], sub = "Canals" }
    local ns, env = Era(player)
    H.assertTrue(math.abs(HeightAt(ns, NORTH_AH[1], NORTH_AH[2]) + 62) < 1.5, "the auction house floor, standing there")
    player.x, player.y, player.sub = NORTH_TOP[1], NORTH_TOP[2], "Ruins of Lordaeron"
    env._clock.now = env._clock.now + 1
    H.assertTrue(math.abs(HeightAt(ns, NORTH_AH[1], NORTH_AH[2]) + 62) < 1.5, "and with the player in the Ruins")
    local cost = ns.GPSNav.Walk(0, NORTH_AH[1], NORTH_AH[2], NORTH_FOOT[1], NORTH_FOOT[2])
    H.assertTrue(cost ~= nil and cost < 400, "to the elevator's foot in the city: " .. tostring(cost))
end

-- Where the ring and the Ruins stack, the client already says Canals.
function tests.aSubZoneNamingNoFloorHere_takesTheFloorOfThatNameBeside()
    local spot = { 1643.7, 255.4 }
    local ns = Era({ x = spot[1], y = spot[2], sub = "Canals" })
    local h = HeightAt(ns, spot[1], spot[2])
    H.assertTrue(h ~= nil and h < 0, "a city floor, not the Ruins over it: " .. tostring(h))
end

function tests.fromTheRing_theWalkGoesDownToTheAuctionHouse()
    local ns = Era({ x = BAT_HANDLER[1], y = BAT_HANDLER[2], sub = "Trade Quarter" })
    local straight = math.sqrt((CAIN[1] - BAT_HANDLER[1]) ^ 2 + (CAIN[2] - BAT_HANDLER[2]) ^ 2)
    -- Ended on the Ruins over him, the walk left the city: 2059 yd.
    local cost = ns.GPSNav.Walk(0, BAT_HANDLER[1], BAT_HANDLER[2], CAIN[1], CAIN[2])
    H.assertTrue(cost ~= nil and cost > straight and cost < 300,
        string.format("down the city's ways: %s yd for %.0f straight", tostring(cost), straight))
end

-- From the Ruins the auction house is no short walk: the route rides an
-- elevator down (the Ruins' floors lay over it, so the walk crossed them
-- straight before); on foot only the long way round through the sewers.
function tests.fromTheRuins_noShortWalkDown()
    local ns = Era({ x = NORTH_TOP[1], y = NORTH_TOP[2], sub = "Ruins of Lordaeron" })
    local round = ns.GPSNav.Walk(0, NORTH_TOP[1], NORTH_TOP[2], CAIN[1], CAIN[2])
    H.assertTrue(round == nil or round > 1000, "only the long way round: " .. tostring(round))
    local foot = ns.GPSNav.Walk(0, NORTH_FOOT[1], NORTH_FOOT[2], CAIN[1], CAIN[2])
    H.assertTrue(foot ~= nil and foot < 300, "from the elevator's foot, a short one: " .. tostring(foot))
end

-- Each Undercity elevator a client's data lists: down from its door in the
-- Ruins to the city's, up the other way, by the doors' heights.
function tests.theElevators_downIntoTheCity_upOut()
    for _, client in ipairs(CLIENTS) do
        local ns, env = Load(client, { sub = "" })
        H.loadModule("Route.lua", env, ns)
        local f = assert(io.open(H.Path(client.data), "rb"))
        local lifts = 0
        for line in f:read("*a"):gmatch("[^\n]+") do
            if line:find('kind = "elevator"', 1, true) and line:find("Undercity", 1, true) then
                local fx, fy = line:match("from = {[^}]*wx = ([%-%d%.]+), wy = ([%-%d%.]+)")
                local tx, ty = line:match("to = {[^}]*wx = ([%-%d%.]+), wy = ([%-%d%.]+)")
                local a = { ci = 0, wx = tonumber(fx), wy = tonumber(fy) }
                local b = { ci = 0, wx = tonumber(tx), wy = tonumber(ty) }
                H.assertEq(ns.GPSRoute._LiftKey(a, b), "GPS_STEP_ELEVATOR_DOWN", client.data .. ": " .. line:sub(1, 70))
                H.assertEq(ns.GPSRoute._LiftKey(b, a), "GPS_STEP_ELEVATOR_UP", client.data .. ": and back up")
                lifts = lifts + 1
            end
        end
        f:close()
        H.assertEq(lifts, 3, client.data .. ": Undercity's three elevators")
    end
end

-- A route's lift step carries the line for its platform, up or down: on
-- board it said to take the elevator still (2026-11-03).
function tests.aLiftsStep_saysToRideItOnBoard()
    local ns, env = Era({ sub = "" })
    for _, file in ipairs({ "Locales/enUS.lua", "Data_Era.lua", "Route.lua" }) do H.loadModule(file, env, ns) end
    env.CreateVector2D = function(x, y) return { x = x, y = y, GetXY = function(v) return v.x, v.y end } end
    env.C_Map = { GetWorldPosFromMapPos = function(_, v) return 0, env.CreateVector2D(v.x, v.y) end,
                  GetMapInfo = function(m) return { name = "Map " .. m } end }
    local function Lift(from, to)
        local steps = ns.GPSRoute:Build({ name = "There", mapID = 1, x = to[1], y = to[2] },
            { data = ns.GPSData, start = { ci = 0, wx = from[1], wy = from[2], m = 1458, x = 0.5, y = 0.5 },
              faction = "Horde", canFly = false, groundSpeed = 7, known = false,
              owns = function() return false end, cooldown = function() return 0 end })
        for _, s in ipairs(steps or {}) do if s.kind == "elevator" then return s end end
    end
    -- From the ring out north of the Ruins, and from the Ruins down to Cain.
    local up = Lift(BAT_HANDLER, { 1900, 240 })
    H.assertNotNil(up, "out of the city by a lift")
    H.assertEq(up.text, "Take the elevator up")
    H.assertEq(up.aboardText, "Ride the elevator up")
    local down = Lift(NORTH_TOP, CAIN)
    H.assertNotNil(down, "into the city by a lift")
    H.assertEq(down.aboardText, "Ride the elevator down")
end

function tests.onTheRingAboveIt_notArrived()
    local player = { x = CAIN[1], y = CAIN[2], sub = "Trade Quarter" }
    local ns = Era(player)
    H.assertFalse(ns.GPSFloors.SameLevel(0, CAIN[1], CAIN[2]), "the ring over the auctioneer")
    player.sub = "Canals"
    H.assertTrue(ns.GPSFloors.SameLevel(0, CAIN[1], CAIN[2]), "beside the auctioneer")
end

-- The Royal Quarter lies under a Tirisfal lake, and the bake once took
-- every floor under the water for the lake's (2026-11-07): from the ring
-- the walk went out and round by the sewers, 1,880 yd.
function tests.theRoyalQuarter_walkedToThroughTheCity()
    for _, client in ipairs(CLIENTS) do
        local ns = Load(client, { sub = "" })
        local cost = ns.GPSNav.Walk(0, 1385.1, 341.7, 1341.7, 310.2)
        H.assertTrue(cost ~= nil and cost < 700, client.walk .. ": ring to Royal Quarter " .. tostring(cost))
    end
end

local pass, fail, failures = H.runSuite("GPS floors", tests)
return { pass = pass, fail = fail, failures = failures }
