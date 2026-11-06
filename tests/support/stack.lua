-- The whole product loaded into the fake client: real EasyFind, real EasyFind GPS
-- with its real data and walking grid, and Forever-GPS on top. Only Questie is a
-- stand-in, because it is a separate install this repository does not carry.
local Client = require("support.client")

local Stack = {}

-- A Questie as EasyFind_Questie binds to it. quests[id]: { name, objectives =
-- { { type, id, text } }, finisher = npcID }. npcs[id]: { name, spawns }.
local function InstallQuestie(c, data)
    local env = c.env
    c.addons.Questie = true
    local npcs, quests, objects = data.npcs or {}, data.quests or {}, data.objects or {}
    local db = {
        QuestPointers = {}, NPCPointers = {}, ObjectPointers = {},
        QueryQuestSingle = function(id, field)
            local q = quests[id]
            if not q then return nil end
            if field == "finishedBy" then return q.finisher and { { q.finisher } } or nil end
            return q[field]
        end,
        QueryNPCSingle = function(id, field) return npcs[id] and npcs[id][field] end,
        QueryObjectSingle = function(id, field) return objects[id] and objects[id][field] end,
        QueryItemSingle = function() return nil end,
        GetQuest = function(id)
            local q = quests[id]
            if not q then return nil end
            local list = {}
            for i, o in ipairs(q.objectives or {}) do
                list[i] = { Type = o.type or "monster", Id = o.id, Text = o.text }
            end
            return { name = q.name, ObjectiveData = list }
        end,
        IsDoable = function() return true end,
    }
    for id in pairs(quests) do db.QuestPointers[id] = true end
    for id in pairs(npcs) do db.NPCPointers[id] = true end
    for id in pairs(objects) do db.ObjectPointers[id] = true end
    local zones = { GetUiMapIdByAreaId = function(_, area) return data.areaMaps and data.areaMaps[area] end }
    env.QuestieLoader = { ImportModule = function(_, name)
        if name == "QuestieDB" then return db end
        if name == "ZoneDB" then return zones end
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
    local skip = opts.ui == false and function(file) return file:find("^UI/") end or nil
    c:LoadAddon("ForeverGPS", skip)
    if c.importing then c.env.ForeverGPSImported = c.importing end
    c:Login()
    -- Questie's own database takes a while on a real login; questieLate holds it back.
    function c:QuestieReady()
        for _, fn in ipairs(self.questieReady or {}) do fn() end
    end
    if not opts.questieLate then c:QuestieReady() end
    c.env.EasyFind._ns.GPSNpcs.Load()
    c.env.EasyFind._ns.GPSNpcs.LoadGoods()
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
