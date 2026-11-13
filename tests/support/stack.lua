-- The whole product loaded into the fake client: real EasyFind, real EasyFind GPS
-- with its real data and walking grid, and Forever-GPS on top. Only Questie is a
-- stand-in, because it is a separate install this repository does not carry.
local Client = require("support.client")

local Stack = {}

-- Questie's own states, by number, as its DoableStates has them.
local STATES = { AVAILABLE = 0, COMPLETED = 1, QUEST_LOG = 2, BLACKLISTED = 3, EXCEED_REPUTATION = 4, PARENT_ACTIVE = 5, WRONG_RACE = 6,
    NO_PREQUESTSINGLE = 7, WRONG_CLASS = 8, MISSING_REPUTATION = 9, PROFESSION_SKILL = 10, NO_PREQUESTGROUP = 11, PARENT_INACTIVE = 12,
    NEXTQUESTINCHAIN_ACTIVE_OR_COMPLETED = 13, EXCLUSIVE_COMPLETED = 14, EXCLUSIVE_IN_QUEST_LOG = 15, LEVEL_TOO_HIGH = 25, LEVEL_TOO_LOW = 26,
    EVENT_INACTIVE = 22, ENABLING_QUEST_MISSING = 28, PROFESSION_MISSING = 29, SPELL_MISSING = 18 }

-- The rules as QuestieDB.IsDoable and IsDoableVerbose have them. q.stop names a state for
-- what depends on a character this client does not model: race, class, reputation, skill.
local function Verdict(c, quests, id)
    local q = quests[id]
    local done = c.completed
    local function InLog(other) return c.env.C_QuestLog.IsOnQuest(other) end
    if done[id] then return "COMPLETED" end
    if InLog(id) then return "QUEST_LOG" end
    if q.stop then return q.stop end
    if q.exclusiveTo then
        for _, other in ipairs(q.exclusiveTo) do
            if done[other] then return "EXCLUSIVE_COMPLETED" end
            if InLog(other) then return "EXCLUSIVE_IN_QUEST_LOG" end
        end
    end
    if q.requiredMaxLevel and c.player.level > q.requiredMaxLevel then return "LEVEL_TOO_HIGH" end
    if q.requiredLevel and c.player.level < q.requiredLevel then return "LEVEL_TOO_LOW" end
    if q.preQuestSingle then
        local any = false
        for _, other in ipairs(q.preQuestSingle) do any = any or done[other] end
        if not any then return "NO_PREQUESTSINGLE" end
    elseif q.preQuestGroup then
        for _, entry in ipairs(q.preQuestGroup) do
            if entry < 0 then
                if not done[-entry] then return "NO_PREQUESTGROUP" end
            elseif not done[entry] then
                local pre = quests[entry]
                local any = false
                for _, other in ipairs(pre and pre.exclusiveTo or {}) do any = any or done[other] end
                if not any then return "NO_PREQUESTGROUP" end
            end
        end
    end
    if q.parentQuest and not InLog(q.parentQuest) then return "PARENT_INACTIVE" end
    if q.nextQuestInChain and (done[q.nextQuestInChain] or InLog(q.nextQuestInChain)) then
        return "NEXTQUESTINCHAIN_ACTIVE_OR_COMPLETED"
    end
    if q.availableStartingWith and not (done[q.availableStartingWith] or InLog(q.availableStartingWith)) then
        return "ENABLING_QUEST_MISSING"
    end
    return "AVAILABLE"
end

-- A Questie as EasyFind_Questie binds to it. quests[id]: { name, objectives =
-- { { type, id, text } }, finisher = npcID, starter = npcID }, plus any of Questie's own
-- field names. npcs[id]: { name, spawns }.
local function InstallQuestie(c, data)
    local env = c.env
    c.addons.Questie = true
    local npcs, quests, objects, items = data.npcs or {}, data.quests or {}, data.objects or {}, data.items or {}
    local db = {
        QuestPointers = {}, NPCPointers = {}, ObjectPointers = {},
        QueryQuestSingle = function(id, field)
            local q = quests[id]
            if not q then return nil end
            if field == "finishedBy" then return q.finishedBy or (q.finisher and { { q.finisher } }) or nil end
            if field == "startedBy" then return q.startedBy or (q.starter and { { q.starter } }) or nil end
            return q[field]
        end,
        QueryNPCSingle = function(id, field) return npcs[id] and npcs[id][field] end,
        QueryObjectSingle = function(id, field) return objects[id] and objects[id][field] end,
        QueryItemSingle = function(id, field) return items[id] and items[id][field] end,
        GetQuest = function(id)
            local q = quests[id]
            if not q then return nil end
            local list = {}
            for i, o in ipairs(q.objectives or {}) do
                list[i] = { Type = o.type or "monster", Id = o.id, Text = o.text }
            end
            return { name = q.name, ObjectiveData = list }
        end,
        -- A level is left to the caller here, as Questie leaves it to its own list.
        IsDoable = function(id)
            local v = Verdict(c, quests, id)
            return v == "AVAILABLE" or v == "LEVEL_TOO_LOW" or (data.doable and data.doable[id]) or false
        end,
        IsDoableVerbose = not data.noVerbose and function(id)
            local v = Verdict(c, quests, id)
            return "Unavailable: " .. v, v ~= "AVAILABLE", STATES[v]
        end or nil,
        DoableStates = STATES,
        raceKeys = { ALL_ALLIANCE = 77, ALL_HORDE = 178 },
        IsRepeatable = function(id) return quests[id] and quests[id].repeatable == true end,
        IsDungeonQuest = function(id) return quests[id] and quests[id].dungeon == true end,
    }
    for id in pairs(quests) do db.QuestPointers[id] = true end
    for id in pairs(npcs) do db.NPCPointers[id] = true end
    for id in pairs(objects) do db.ObjectPointers[id] = true end
    local zones = { GetUiMapIdByAreaId = function(_, area) return data.areaMaps and data.areaMaps[area] end }
    env.QuestieLoader = { ImportModule = function(_, name)
        if name == "QuestieDB" then return db end
        if name == "ZoneDB" then return zones end
        if name == "QuestieReputation" then return { GetFactionName = function(id) return "Faction " .. id end } end
        if name == "QuestieProfessions" then return { GetProfessionName = function(_, id) return "Skill " .. id end } end
        return {}
    end }
    local ready = {}
    env.Questie = { API = {
        RegisterOnReady = function(fn) ready[#ready + 1] = fn end,
        RegisterForQuestUpdates = function() end,
    } }
    c.questieReady = ready
end

-- opts: Client.new's, plus questie = { npcs, quests, areaMaps }, ui = false to
-- leave the window and HUD out, saved = { ForeverGPSDB, ForeverGPSCharDB, EasyFindDB }.
function Stack.new(opts)
    opts = opts or {}
    local c = Client.new(opts)
    if opts.saved then
        c.env.ForeverGPSDB = opts.saved.ForeverGPSDB
        c.importing = opts.saved.ForeverGPSImported
        c.env.ForeverGPSCharDB = opts.saved.ForeverGPSCharDB
        c.env.EasyFindDB = opts.saved.EasyFindDB
        c.env.EasyFindCharDB = opts.saved.EasyFindCharDB
    end
    if opts.questie then InstallQuestie(c, opts.questie) end
    if opts.tomtom then c.env.TomTom = opts.tomtom; c.addons.TomTom = true end
    -- A button gatherer's libraries and the game's addon compartment, counting what
    -- registers with them.
    if opts.launchers then
        local seen = { broker = {}, icons = {}, compartment = {} }
        c.launchers = seen
        local broker = {
            NewDataObject = function(_, name, obj) seen.broker[name] = obj return obj end,
            GetDataObjectByName = function(_, name) return seen.broker[name] end,
        }
        local icon = { Register = function(_, name) seen.icons[name] = true end, Show = function() end, Hide = function() end,
                       GetMinimapButton = function() return nil end, IsRegistered = function(_, name) return seen.icons[name] end }
        c.env.LibStub = setmetatable({}, { __call = function(_, name)
            if name == "LibDataBroker-1.1" then return broker end
            if name == "LibDBIcon-1.0" then return icon end
        end })
        c.env.AddonCompartmentFrame = { RegisterAddon = function(_, entry) seen.compartment[#seen.compartment + 1] = entry.text end }
    end
    local skip = opts.ui == false and function(file) return file:find("^UI/") end or nil
    c:LoadAddon("ForeverGPS", skip)
    if c.importing then c.env.ForeverGPSImported = c.importing end
    c:Login()
    -- Questie's own database takes a while on a real login; questieLate holds it back.
    function c:QuestieReady()
        for _, fn in ipairs(self.questieReady or {}) do fn() end
    end
    if not opts.questieLate then c:QuestieReady() end
    -- The creature catalog: EasyFind's own from 5.3.0, the GPS's before it.
    local catalog = c.env.EasyFind._ns.Npcs or c.env.EasyFind._ns.GPSNpcs
    catalog.Load()
    if catalog.LoadGoods then catalog.LoadGoods() end
    c.FG = c.env.ForeverGPS
    c.ns = c.env.EasyFind._ns
    c.errors = {}
    return c
end

-- Pumps the client until pred() holds; false after limit seconds of game time.
function Stack.Until(c, pred, limit)
    local waited = 0
    limit = limit or 30
    while waited < limit do
        if pred() then return true end
        c:Advance(0.05, 0.05)
        waited = waited + 0.05
    end
    return pred() and true or false
end

-- The saved variables as a /reload would hand them to the next session.
function Stack.Saved(c)
    return {
        ForeverGPSDB = Client.Clone(c.env.ForeverGPSDB),
        ForeverGPSCharDB = Client.Clone(c.env.ForeverGPSCharDB),
        EasyFindDB = Client.Clone(c.env.EasyFindDB),
        EasyFindCharDB = Client.Clone(c.env.EasyFindCharDB),
    }
end

return Stack
