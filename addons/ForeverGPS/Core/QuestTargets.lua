-- Where a quest's parts are done, and which spot to go to. Spawns are grouped
-- into areas, the nearest few are priced by the route engine, and the closest by
-- travel time leads: not the closest on a straight line across a sea. A quest
-- with no reliable place says so instead of inventing a route.
--
-- FG.Areas works on any list of spots, NPC spawns as well as quest objectives.
local FG = ForeverGPS
local Areas = {}
FG.Areas = Areas
local Targets = {}
FG.QuestTargets = Targets

local Bridge, Eta, Quests = FG.Bridge, FG.Eta, FG.Quests
local L = FG.L

local CELL = 220             -- yards: spawns within about this form one area
local PRICED_NEAR = 5        -- the nearest areas priced on the player's continent
local PRICED_FAR = 3         -- and on others

-- ==== areas =================================================================

-- spots: { { mapID, x, y, name? }, ... }. Returns areas, each with its spots'
-- count, its zone, and a real spot near its middle to route to. apart: each spot
-- stands alone, for places where any one will do.
function Areas.From(spots, apart)
    local cells, out = {}, {}
    for i = 1, #spots do
        local s = spots[i]
        local ci, wx, wy = Bridge.WorldPos(s.mapID, s.x, s.y)
        if ci then
            local key = apart and i or ("%d:%d:%d"):format(ci, math.floor(wx / CELL), math.floor(wy / CELL))
            local area = cells[key]
            if not area then
                area = { ci = ci, sx = 0, sy = 0, n = 0, members = {}, zone = Bridge.MapName(s.mapID) }
                cells[key] = area
                out[#out + 1] = area
            end
            area.sx, area.sy, area.n = area.sx + wx, area.sy + wy, area.n + 1
            area.members[area.n] = { spot = s, wx = wx, wy = wy }
        end
    end
    for i = 1, #out do
        local a = out[i]
        a.wx, a.wy = a.sx / a.n, a.sy / a.n
        local best, bestD
        for j = 1, a.n do
            local m = a.members[j]
            local d = (m.wx - a.wx) ^ 2 + (m.wy - a.wy) ^ 2
            if not bestD or d < bestD then best, bestD = m.spot, d end
        end
        a.spot, a.members, a.sx, a.sy = best, nil, nil, nil
    end
    return out
end

-- Straight-line order from the player: this continent first.
local function ByDistance(areas, start)
    for i = 1, #areas do
        local a = areas[i]
        if start and a.ci == start.ci then
            a.yards = ((a.wx - start.wx) ^ 2 + (a.wy - start.wy) ^ 2) ^ 0.5
        else
            a.yards = nil
        end
    end
    table.sort(areas, function(p, q)
        if p.yards and q.yards then return p.yards < q.yards end
        if p.yards or q.yards then return p.yards ~= nil end
        return p.n > q.n
    end)
    return areas
end

-- The areas worth pricing: the nearest here and a few elsewhere.
local function Shortlist(areas)
    local out, near, far = {}, 0, 0
    for i = 1, #areas do
        local a = areas[i]
        if a.routable ~= false then
            if a.yards and near < PRICED_NEAR then
                near = near + 1
                out[#out + 1] = a
            elseif not a.yards and far < PRICED_FAR then
                far = far + 1
                out[#out + 1] = a
            end
        end
    end
    return out
end

local function Routable(area)
    local s = area.spot
    return Bridge.CanNavigate({ name = s.name or "?", mapID = s.mapID, x = s.x, y = s.y })
end

-- Orders areas by travel time as estimates arrive; done(best, basis) once they
-- are in. basis: "travel" when the engine priced it, "straight" otherwise.
function Areas.Rank(areas, done, alive)
    local start = Bridge.PlayerStart()
    ByDistance(areas, start)
    for i = 1, #areas do
        if areas[i].routable == nil then areas[i].routable = Routable(areas[i]) end
    end
    local list = Shortlist(areas)
    local waiting = #list
    if waiting == 0 then
        for i = 1, #areas do
            if areas[i].routable then return done(areas[i], "straight") end
        end
        return done(nil, nil)
    end
    local function Settle()
        local best, basis
        for i = 1, #list do
            local a = list[i]
            if a.sec and (not best or a.sec < best.sec) then best, basis = a, "travel" end
        end
        if not best then best, basis = list[1], "straight" end
        table.sort(areas, function(p, q)
            if p.sec and q.sec then return p.sec < q.sec end
            if p.sec or q.sec then return p.sec ~= nil end
            return false
        end)
        done(best, basis)
    end
    for i = 1, #list do
        local a = list[i]
        local s = a.spot
        Eta.Request({ mapID = s.mapID, x = s.x, y = s.y, name = s.name or "?" }, function(value)
            a.sec = value and value.sec or nil
            a.transports = value and value.transports or nil
            waiting = waiting - 1
            if waiting == 0 then Settle() end
        end, alive)
    end
end

-- ==== quest spots ===========================================================

local function Questie()
    local API = EasyFind and EasyFind.API
    if not (API and API.HasAction and API.HasAction("questie", "questSpots")) then return nil end
    return API
end

function Targets.HasQuestie()
    local API = Questie()
    return API ~= nil and API.CallAction("questie", "isReady") == true
end

-- Spot lists are facts about the game: kept for the session, per quest.
local spotCache, starterCache, exploreCache = {}, {}, {}
local hadQuestie = false

-- Whether Questie came or went since this was last asked: what the quest list
-- worked out before then no longer holds.
function Targets.QuestieChanged()
    local has = Targets.HasQuestie()
    local changed = has ~= hadQuestie
    hadQuestie = has
    if changed then
        spotCache, starterCache, exploreCache = {}, {}, {}
        FG.QuestDB.Forget()
    end
    return changed
end

local function SpotsOf(questID)
    local hit = spotCache[questID]
    if hit then return hit end
    if not Targets.HasQuestie() then return nil end
    local data = EasyFind.API.CallAction("questie", "questSpots", questID)
    if type(data) ~= "table" then return nil end
    spotCache[questID] = data
    return data
end

local function NewTarget(kind, index, text, spots, done)
    local t = { kind = kind, index = index, text = text, done = done or false, areas = {} }
    if spots and #spots > 0 then
        t.areas = Areas.From(spots)
        t.spotCount = #spots
    end
    if #t.areas == 0 then
        t.status = "none"
        t.reason = L["QUEST_NO_DATA_LONG"]
    else
        t.status = "ok"
    end
    return t
end

-- Everything a quest can be navigated to right now.
-- { objectives = { target, ... }, turnIn = target or nil, marker = target or nil,
--   source = "questie" or "game" }
function Targets.For(q)
    local out = { objectives = {} }
    local data = SpotsOf(q.questID)
    out.source = data and "questie" or "game"
    for i = 1, #q.objectives do
        local o = q.objectives[i]
        local spots = data and data.objectives[i] and data.objectives[i].spots or nil
        local t = NewTarget("objective", i, o.text, spots, o.finished)
        if not data then t.reason = L["QUEST_NO_QUESTIE"] end
        out.objectives[i] = t
    end
    if data then
        local name = data.turnInName
        out.turnIn = NewTarget("turnin", nil, name and L["QUEST_TURN_IN_AT_FMT"]:format(name) or L["QUEST_TURN_IN"], data.turnIn)
    end
    -- The game's own mark: all there is without Questie, and a place for an
    -- objective Questie has none for.
    local mapID, x, y = Bridge.QuestSpot(q.questID)
    if mapID then
        local label = q.complete and L["QUEST_TURN_IN"] or L["QUEST_GAME_MARKER"]
        out.marker = NewTarget("marker", nil, label, { { mapID = mapID, x = x, y = y } })
        if q.complete and not out.turnIn then out.turnIn = out.marker end
    end
    if not out.turnIn then
        out.turnIn = NewTarget("turnin", nil, L["QUEST_TURN_IN"], nil)
    end
    return out
end

-- ==== quests not in the log =================================================

local MAX_ITEM_SOURCES = 8

-- Where a quest is picked up. Every giver counts: a quest with several is taken wherever
-- the journey is shortest. An object is said to be one, because no one stands there. An item
-- has no place of its own, so only what Questie records as dropping it is offered, and it
-- says that is where the item comes from, never that someone there gives the quest.
function Targets.Starter(id)
    local hit = starterCache[id]
    if hit then return hit end
    local QuestDB = FG.QuestDB
    if not QuestDB.Ready() or not QuestDB.Exists(id) then return nil end
    local who = QuestDB.Starters(id)
    local spots, text, kind = {}, nil, nil
    for _, npc in ipairs(who.npcs) do
        kind = kind or "npc"
        for _, s in ipairs(QuestDB.Spots("npc", npc)) do spots[#spots + 1] = s end
    end
    for _, object in ipairs(who.objects) do
        kind = kind or "object"
        for _, s in ipairs(QuestDB.Spots("object", object)) do spots[#spots + 1] = s end
    end
    if kind == "npc" then
        text = L["QUEST_START_NPC_FMT"]:format(QuestDB.EntityName("npc", who.npcs[1]) or "?")
    elseif kind == "object" then
        text = L["QUEST_START_OBJECT_FMT"]:format(QuestDB.EntityName("object", who.objects[1]) or "?")
    end
    local item = who.items[1]
    if not kind and item then
        kind = "item"
        local name = QuestDB.EntityName("item", item) or "?"
        local sources = QuestDB.ItemSources(item)
        local first
        for i = 1, math.min(#sources.npcs, MAX_ITEM_SOURCES) do
            first = first or QuestDB.EntityName("npc", sources.npcs[i])
            for _, s in ipairs(QuestDB.Spots("npc", sources.npcs[i])) do spots[#spots + 1] = s end
        end
        for i = 1, math.min(#sources.objects, MAX_ITEM_SOURCES) do
            first = first or QuestDB.EntityName("object", sources.objects[i])
            for _, s in ipairs(QuestDB.Spots("object", sources.objects[i])) do spots[#spots + 1] = s end
        end
        text = first and L["QUEST_START_ITEM_FROM_FMT"]:format(name, first) or L["QUEST_START_ITEM_FMT"]:format(name)
    end
    local t = NewTarget("start", nil, text or L["QUEST_START_UNKNOWN"], spots)
    t.starterKind = kind
    if t.status ~= "ok" then
        t.reason = kind == "item" and L["QUEST_START_ITEM_NO_PLACE"] or (kind and L["QUEST_START_NO_PLACE"] or L["QUEST_START_UNKNOWN"])
    end
    starterCache[id] = t
    return t
end

-- Everything a quest not in the log can be shown or navigated to.
function Targets.Explore(id)
    local hit = exploreCache[id]
    if hit then return hit end
    local out = { start = Targets.Starter(id), objectives = {} }
    local data = SpotsOf(id)
    if data then
        for i, o in ipairs(data.objectives) do
            out.objectives[i] = NewTarget("objective", i, o.text, o.spots)
        end
        local name = data.turnInName
        out.turnIn = NewTarget("turnin", nil, name and L["QUEST_TURN_IN_AT_FMT"]:format(name) or L["QUEST_TURN_IN"], data.turnIn)
    end
    exploreCache[id] = out
    return out
end

-- What makes a quest's targets out of date: its parts finishing, not its counters.
local function Signature(q)
    local parts = { q.complete and "c" or "o" }
    for i = 1, #q.objectives do parts[#parts + 1] = q.objectives[i].finished and "1" or "0" end
    return table.concat(parts)
end

local entries = {}           -- questID -> { sig, targets }

-- A quest's targets, worked out once for as long as they hold. A busy quest log does
-- not cost a scan of every quest at each kill.
function Targets.Of(q)
    local sig = Signature(q)
    local entry = entries[q.questID]
    if not entry or entry.sig ~= sig then
        entry = { sig = sig, targets = Targets.For(q) }
        entries[q.questID] = entry
    end
    return entry
end

-- The same, when it is already worked out; nil rather than working it out now.
function Targets.Peek(q)
    local entry = entries[q.questID]
    return entry and entry.sig == Signature(q) and entry or nil
end

local WARM_SLICE_MS = 3
local warmer

-- Works every quest's places out a few milliseconds a frame, so that opening the
-- window never has to do it all at once.
function Targets.Warm()
    local list, i = Quests.All(), 1
    warmer = warmer or CreateFrame("Frame")
    warmer:SetScript("OnUpdate", function(self)
        local stop = debugprofilestop() + WARM_SLICE_MS
        while list[i] do
            Targets.Of(list[i])
            i = i + 1
            if debugprofilestop() > stop then return end
        end
        self:SetScript("OnUpdate", nil)
        FG.Emit("targets:warm")
    end)
end

-- Whether an entry is still the one in use.
function Targets.Current(q, entry) return entries[q.questID] == entry end

function Targets.ForgetAll() entries = {} end

-- The door to an instance, for what is done inside one: nowhere in it can be walked to,
-- but the way in is a place like any other.
local function EntranceOf(zone)
    if not zone then return nil end
    for _, row in ipairs(Bridge.SearchPlaces(zone)) do
        if row.isDungeonEntrance and row.x and Bridge.CanNavigate(row) then return row end
    end
    return nil
end

-- Checks a target's areas, priced and ordered; done(target) when it is settled.
function Targets.Resolve(target, done, alive)
    if target.status ~= "ok" then return done(target) end
    if target.settled then return done(target) end
    Areas.Rank(target.areas, function(best, basis)
        target.settled = true
        target.best, target.basis = best, basis
        if not best then
            local zone = target.areas[1] and target.areas[1].zone
            local door = EntranceOf(zone)
            if door then
                local mapID = door.coordMapID or door.mapID
                target.best = { spot = { mapID = mapID, x = door.x, y = door.y, name = door.name }, zone = L["QUEST_ENTRANCE_FMT"]:format(zone) }
                target.entrance = true
            else
                target.status = "instance"
                target.reason = L["QUEST_INSTANCE_ONLY"]
            end
        end
        done(target)
    end, alive)
end

-- The planner's target for going to an area of a quest's target.
function Targets.Destination(q, target, area)
    local s = area.spot
    local icon = target.kind == "turnin" and 132048 or target.kind == "start" and 132049 or 365195
    return {
        name = L["QUEST_DEST_FMT"]:format(q.title, target.text or ""),
        subtitle = area.zone,
        icon = icon,
        data = { name = q.title, mapID = s.mapID, x = s.x, y = s.y, icon = icon,
                 step = target.kind == "turnin" and target.text or nil },
        binding = { questID = q.questID, title = q.title, kind = target.kind, index = target.index },
        areas = target.areas, area = area,
    }
end

-- What the quest browser sorts and filters on: how near the closest thing left to
-- do is, on a straight line, and whether anything left has no known place. Cheap
-- enough to ask whenever the list is drawn: it reads areas that already exist.
-- { yards (nil when elsewhere), here, sameLand, missing }
function Targets.Facts(q, targets, start, mapID)
    local facts = { missing = false, here = false, sameLand = false }
    local function Look(target)
        if not target or target.done then return end
        if target.status ~= "ok" then
            if target.kind == "objective" then facts.missing = true end
            return
        end
        for _, area in ipairs(target.areas) do
            if area.spot.mapID == mapID then facts.here = true end
            if start and area.ci == start.ci then
                facts.sameLand = true
                local d = ((area.wx - start.wx) ^ 2 + (area.wy - start.wy) ^ 2) ^ 0.5
                if not facts.yards or d < facts.yards then facts.yards = d end
            end
        end
    end
    if q.complete then
        Look(targets.turnIn)
    else
        for i = 1, #targets.objectives do Look(targets.objectives[i]) end
        Look(targets.turnIn)
    end
    return facts
end

-- The first thing to do for a quest: the turn-in when it is done, else the
-- open objective reachable soonest once resolved. Used by the quest list's
-- one-click directions.
function Targets.FirstOpen(q, targets)
    if q.complete then return targets.turnIn end
    for i = 1, #targets.objectives do
        local t = targets.objectives[i]
        if not t.done and t.status == "ok" then return t end
    end
    return targets.marker
end

FG.On("quests:changed", function()
    if Targets.QuestieChanged() then entries = {} end
    -- Spots do not change, but a quest that left the log need not stay.
    for questID in pairs(spotCache) do
        if not Quests.Get(questID) then spotCache[questID] = nil end
    end
    for questID in pairs(entries) do
        if not Quests.Get(questID) then entries[questID] = nil end
    end
    Targets.Warm()
end)

-- After login, once Questie has had time to be ready.
FG.On("login", function() FG.After(8, Targets.Warm) end)
