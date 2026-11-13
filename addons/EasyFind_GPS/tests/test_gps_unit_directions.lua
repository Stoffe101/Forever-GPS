-- Directions on a unit's right-click menu (QuestDirections.lua): an NPC
-- routes to the spot its search row shows, as typing its name and taking
-- its GPS button would; a party or raid member is followed, the route
-- planned again once it is 25 yards from the route's end. Players outside
-- the group and creatures the catalog lacks get no entry.
local H = require("Harness")

local function Load()
    local env = H.newEnv()
    local ns = H.newNs(env)
    env.EasyFind._ns = ns
    local t = { mods = {}, navigated = {}, units = {}, route = nil, planning = false, tickers = {} }
    ns.GPS = {
        IsPlanning = function() return t.planning end,
        CurrentRoute = function() return t.route end,
    }
    ns.Npcs = { SpotOfID = function(id)
        if id == 448 then return { name = "Hogger", npcID = 448, mapID = 1429, x = 0.3, y = 0.4, category = "npc" } end
    end }
    env.EasyFind.API = { CallAction = function(id, name, dest, opts)
        if id == "gps" and name == "navigate" then t.navigated[#t.navigated + 1] = { dest = dest, opts = opts } end
    end }
    env.Menu = { ModifyMenu = function(tag, fn) t.mods[tag] = fn end }
    local function U(unit) return t.units[unit] end
    env.UnitExists = function(u) return U(u) ~= nil end
    env.UnitIsPlayer = function(u) return U(u) and U(u).player or false end
    env.UnitIsUnit = function(a, b) return a == b end
    env.UnitInParty = function(u) return U(u) and U(u).party or false end
    env.UnitInRaid = function() return nil end
    env.UnitGUID = function(u) return U(u) and U(u).guid end
    env.UnitName = function(u) return U(u) and U(u).name end
    env.IsInRaid = function() return false end
    env.GetNumGroupMembers = function() return 2 end
    env.strsplit = function(sep, s)
        local out = {}
        for part in (s .. sep):gmatch("(.-)" .. sep) do out[#out + 1] = part end
        return table.unpack(out)
    end
    local function vec(x, y) return { x = x, y = y, GetXY = function(self) return self.x, self.y end } end
    env.CreateVector2D = vec
    env.C_Map = {
        GetBestMapForUnit = function(u) return U(u) and U(u).map end,
        GetPlayerMapPosition = function(_, u) return U(u) and U(u).pos and vec(U(u).pos[1], U(u).pos[2]) end,
        -- A map 1000 yards across.
        GetWorldPosFromMapPos = function(_, v) return 0, vec(v.x * 1000, v.y * 1000) end,
    }
    env.C_Timer = { NewTicker = function(sec, fn)
        local tk = { sec = sec, fn = fn, Cancel = function(self) self.cancelled = true end }
        t.tickers[#t.tickers + 1] = tk
        return tk
    end }
    env.C_QuestLog, env.GetQuestUiMapID = {}, nil   -- no quest placing: the search rows part returns early
    H.loadModule("QuestDirections.lua", env, ns)
    t.ns = ns
    return t
end

local function Menu(t, which, unit)
    local rows = {}
    local root = {}
    function root:CreateDivider() rows[#rows + 1] = "divider" end
    function root:CreateButton(label, fn) rows[#rows + 1] = { label = label, fn = fn } end
    t.mods["MENU_UNIT_" .. which](nil, root, { unit = unit })
    return rows
end

local tests = {}

function tests.anNpcsPortrait_routesToTheSpotItsRowShows()
    local t = Load()
    t.units.target = { guid = "Creature-0-1-2-3-448-0000ABCD", name = "Hogger" }
    local rows = Menu(t, "TARGET", "target")
    H.assertEq(rows[2].label, "GPS_MENU_EASYFIND_DIRECTIONS")
    rows[2].fn()
    H.assertEq(t.navigated[1].dest.name, "Hogger")
    H.assertEq(t.navigated[1].dest.x, 0.3)
    H.assertTrue(t.navigated[1].opts.popout, "as a search row's GPS button")
end

function tests.aCreatureTheCatalogLacks_orAPlayerOutsideTheGroup_getsNone()
    local t = Load()
    t.units.target = { guid = "Creature-0-1-2-3-99999-0000ABCD", name = "Nobody" }
    H.assertEq(#Menu(t, "TARGET", "target"), 0)
    t.units.target = { guid = "Player-1-0ABC", name = "Stranger", player = true, map = 1429, pos = { 0.5, 0.5 } }
    H.assertEq(#Menu(t, "TARGET", "target"), 0, "the client gives no spot for them")
end

function tests.aGroupMember_isFollowed_aNewRouteOnceFarFromItsEnd()
    local t = Load()
    local friend = { guid = "Player-1-0FED", name = "Friend", player = true, party = true, map = 1429, pos = { 0.5, 0.5 } }
    t.units.party1, t.units.party = friend, friend
    local rows = Menu(t, "PARTY", "party1")
    rows[2].fn()
    H.assertEq(t.navigated[1].dest.followGUID, "Player-1-0FED")
    local ticker = t.tickers[1]
    H.assertEq(ticker.sec, 3)
    t.route = { dest = { name = "Friend", mapID = 1429, x = 0.5, y = 0.5, followGUID = "Player-1-0FED" } }
    friend.pos = { 0.51, 0.5 }   -- 10 yards: the route stands
    ticker.fn()
    H.assertEq(#t.navigated, 1)
    friend.pos = { 0.55, 0.5 }   -- 50 yards: planned again, quietly
    ticker.fn()
    H.assertEq(#t.navigated, 2)
    H.assertTrue(t.navigated[2].opts.quiet)
    H.assertEq(t.navigated[2].dest.x, 0.55)
end

function tests.followingEnds_whenTheRouteIsAnothers_orTheMemberLeft()
    local t = Load()
    local friend = { guid = "Player-1-0FED", name = "Friend", player = true, party = true, map = 1429, pos = { 0.5, 0.5 } }
    t.units.party1 = friend
    Menu(t, "PARTY", "party1")[2].fn()
    t.route = { dest = { name = "Inn", mapID = 1429, x = 0.1, y = 0.1 } }
    t.tickers[1].fn()
    H.assertTrue(t.tickers[1].cancelled, "another route took over")
    Menu(t, "PARTY", "party1")[2].fn()
    t.route = { dest = { name = "Friend", mapID = 1429, x = 0.5, y = 0.5, followGUID = "Player-1-0FED" } }
    t.units.party1 = nil
    t.tickers[2].fn()
    H.assertTrue(t.tickers[2].cancelled, "left the group")
end

function tests.everyUnitMenuThatShowsANpcOrAMember_getsIt()
    local t = Load()
    for _, which in ipairs({ "TARGET", "FOCUS", "BOSS", "PARTY", "RAID_PLAYER", "RAID" }) do
        H.assertTrue(t.mods["MENU_UNIT_" .. which] ~= nil, which)
    end
end

local pass, fail, failures = H.runSuite("GPSUnitDirections", tests)
return { pass = pass, fail = fail, failures = failures }
