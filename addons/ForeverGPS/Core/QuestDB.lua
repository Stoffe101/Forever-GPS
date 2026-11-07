-- The one file that reads Questie's modules, for quests not in the log. Everything comes
-- from the installed Questie as it is asked for: nothing here is a copy of its database,
-- and no quest data ships with Forever-GPS. Bind says plainly what it needs, so a Questie
-- that changes shows up as "not available", never as a wrong answer.
local FG = ForeverGPS
local QuestDB = {}
FG.QuestDB = QuestDB

local Q

local NEEDED = { "QueryQuestSingle", "QueryNPCSingle", "QueryObjectSingle", "QueryItemSingle", "IsDoable" }

local function Bind()
    if Q then return Q end
    local Loader = _G.QuestieLoader
    if not (Loader and Loader.ImportModule) then return nil end
    local db, zones = Loader:ImportModule("QuestieDB"), Loader:ImportModule("ZoneDB")
    if type(db) ~= "table" or type(zones) ~= "table" then return nil end
    for _, name in ipairs(NEEDED) do
        if type(db[name]) ~= "function" then return nil end
    end
    if type(db.QuestPointers) ~= "table" or type(zones.GetUiMapIdByAreaId) ~= "function" then return nil end
    Q = { db = db, zones = zones, professions = Loader:ImportModule("QuestieProfessions"),
          reputation = Loader:ImportModule("QuestieReputation") }
    return Q
end

-- Whether Questie is here, finished loading, and shaped as expected.
function QuestDB.Ready()
    return FG.QuestTargets.HasQuestie() and Bind() ~= nil
end

-- Questie went or came: bind again when next asked.
function QuestDB.Forget() Q = nil end

function QuestDB.Exists(id)
    return Q ~= nil and id ~= nil and Q.db.QuestPointers[id] ~= nil
end

function QuestDB.AllIds()
    local out = {}
    if not Q then return out end
    for id in pairs(Q.db.QuestPointers) do
        if type(id) == "number" then out[#out + 1] = id end
    end
    table.sort(out)
    return out
end

function QuestDB.Field(id, key)
    if not QuestDB.Exists(id) then return nil end
    return Q.db.QueryQuestSingle(id, key)
end

-- A list field, as a plain list however it is stored: empty when there is none.
function QuestDB.List(id, key)
    local value = QuestDB.Field(id, key)
    if type(value) == "table" then return value end
    if type(value) == "number" and value ~= 0 then return { value } end
    return {}
end

function QuestDB.Name(id)
    local name = QuestDB.Field(id, "name")
    return type(name) == "string" and name ~= "" and name or nil
end

function QuestDB.EntityName(kind, id)
    if not (Q and id) then return nil end
    local name
    if kind == "npc" then name = Q.db.QueryNPCSingle(id, "name")
    elseif kind == "object" then name = Q.db.QueryObjectSingle(id, "name")
    elseif kind == "item" then name = Q.db.QueryItemSingle(id, "name") end
    return type(name) == "string" and name or nil
end

function QuestDB.MapOfArea(areaId)
    if not (Q and areaId and areaId > 0) then return nil end
    return Q.zones:GetUiMapIdByAreaId(areaId)
end

function QuestDB.AreaName(areaId)
    local mapID = QuestDB.MapOfArea(areaId)
    local info = mapID and C_Map.GetMapInfo(mapID)
    return info and info.name or nil
end

-- Who starts a quest: { npcs, objects, items }, each a list of ids. Questie keeps these in
-- three positions, any of them absent.
local function Who(by)
    if type(by) ~= "table" then return { npcs = {}, objects = {}, items = {} } end
    return { npcs = by[1] or {}, objects = by[2] or {}, items = by[3] or {} }
end

function QuestDB.Starters(id) return Who(QuestDB.Field(id, "startedBy")) end
function QuestDB.Finishers(id) return Who(QuestDB.Field(id, "finishedBy")) end

-- The zone a quest belongs to: its own area, else where its giver stands. A negative
-- zoneOrSort is a category such as a class, not a place, so it says nothing here.
function QuestDB.ZoneOf(id)
    local area = QuestDB.Field(id, "zoneOrSort")
    if area and area > 0 then
        local name = QuestDB.AreaName(area)
        if name then return name, QuestDB.MapOfArea(area) end
    end
    local who = QuestDB.Starters(id)
    local npc, object = who.npcs[1], who.objects[1]
    local zoneID = npc and Q.db.QueryNPCSingle(npc, "zoneID") or (object and Q.db.QueryObjectSingle(object, "zoneID"))
    if zoneID and zoneID > 0 then return QuestDB.AreaName(zoneID), QuestDB.MapOfArea(zoneID) end
    return nil, nil
end

-- The side a quest is for, when it is for one.
function QuestDB.Side(id)
    local races = QuestDB.Field(id, "requiredRaces")
    local keys = Q and Q.db.raceKeys
    if not (races and races ~= 0 and keys) then return nil end
    if races == keys.ALL_ALLIANCE then return "Alliance" end
    if races == keys.ALL_HORDE then return "Horde" end
    return "some"
end

-- Where something stands. Questie's own spawns, through the extension's boundary.
function QuestDB.Spots(kind, id)
    return FG.Bridge.WorldSpots(kind, id) or {}
end

-- What drops an item, for a quest it starts: only ever what Questie records.
function QuestDB.ItemSources(id)
    if not Q then return { npcs = {}, objects = {} } end
    local npcs = Q.db.QueryItemSingle(id, "npcDrops")
    local objects = Q.db.QueryItemSingle(id, "objectDrops")
    return { npcs = type(npcs) == "table" and npcs or {}, objects = type(objects) == "table" and objects or {} }
end

-- ==== the character =========================================================

function QuestDB.IsDone(id)
    return C_QuestLog.IsQuestFlaggedCompleted(id) == true
end

function QuestDB.InLog(id)
    return C_QuestLog.IsOnQuest(id) == true
end

-- Questie's answer: can this character take it now, by every rule it knows.
function QuestDB.Doable(id)
    return QuestDB.Exists(id) and Q.db.IsDoable(id) == true
end

-- Why not: Questie's own reason and state, or nil on a Questie without it.
function QuestDB.Verdict(id)
    local fn = Q and Q.db.IsDoableVerbose
    if type(fn) ~= "function" or not Q.db.DoableStates then return nil end
    local ok, text, _, state = pcall(fn, id, false, true, true)
    if not ok then return nil end
    return state, text
end

function QuestDB.States() return Q and Q.db.DoableStates or {} end

-- What kind of quest: asked of Questie where it can say, and nil where it cannot.
function QuestDB.Is(id, kind)
    local fn = Q and Q.db[kind]
    if type(fn) ~= "function" or not QuestDB.Exists(id) then return false end
    local ok, yes = pcall(fn, id)
    return ok and yes == true
end

function QuestDB.FactionName(id)
    local rep = Q and Q.reputation
    local fn = rep and rep.GetFactionName
    return type(fn) == "function" and fn(id) or nil
end

function QuestDB.SkillName(id)
    local prof = Q and Q.professions
    local fn = prof and prof.GetProfessionName
    return type(fn) == "function" and fn(prof, id) or nil
end
