-- Search: one list from EasyFind's map search, the NPC catalog, the player's
-- quests, saved places and typed coordinates, with the context a result card
-- shows. Where a search asks for a kind of thing (any inn, any trainer), the
-- results are ordered by travel time as estimates arrive.
local _, FG = ...
local Search = {}
FG.Search = Search

local Bridge, Eta, Format, Quests, Saved = FG.Bridge, FG.Eta, FG.Format, FG.Quests, FG.Saved
local L = FG.L

local MAX_RESULTS = 30
local PRICED = 10            -- results that get a travel time, from the top

Search.FILTERS = {
    { key = "all", label = "CAT_ALL" },
    { key = "quests", label = "CAT_QUESTS" },
    { key = "services", label = "CAT_SERVICES" },
    { key = "trainers", label = "CAT_TRAINERS" },
    { key = "instances", label = "CAT_INSTANCES" },
    { key = "places", label = "CAT_PLACES" },
    { key = "npcs", label = "CAT_NPCS" },
}

-- What a filter shows with nothing typed.
Search.BROWSE = { services = "services", trainers = "trainer", instances = "dungeon" }

-- The quick services on the home view, each a query the search understands.
function Search.QuickServices()
    local _, class = UnitClass("player")
    local classTrainer = class and (class:sub(1, 1) .. class:sub(2):lower() .. " trainer") or "trainer"
    return {
        { label = "SVC_INN", query = "innkeeper", icon = "inn" },
        { label = "SVC_FLIGHT", query = "flight master", icon = "flight" },
        { label = "SVC_BANK", query = "bank", icon = "bank" },
        { label = "SVC_AUCTION", query = "auction house", icon = "auction" },
        { label = "SVC_MAIL", query = "mailbox", icon = "mail" },
        { label = "SVC_REPAIR", query = "repair", icon = "repair" },
        { label = "SVC_TRAINER", query = classTrainer, icon = "trainer" },
        { label = "SVC_VENDOR", query = "general goods", icon = "vendor" },
    }
end

-- ==== classifying a row =====================================================

local INSTANCE = { dungeon = "TYPE_DUNGEON", raid = "TYPE_RAID", delve = "TYPE_DELVE" }

-- The NPC catalog's service words, as they appear in a creature's keywords.
local SERVICE_WORDS = { flight = true, vendor = true, merchant = true, repair = true, stable = true, innkeeper = true,
                        inn = true, bank = true, banker = true, auctioneer = true, mail = true }

-- What a creature does for the player: "trainers", "services" or nil.
local function RoleOf(row)
    local role
    for _, word in ipairs(row.keywords or {}) do
        if type(word) == "string" then
            local low = word:lower()
            if low:find("trainer", 1, true) then return "trainers" end
            if SERVICE_WORDS[low] then role = "services" end
        end
    end
    return role
end

-- A creature's title ("Gryphon Master"): the catalog puts it first, capitalized,
-- ahead of its lower-case service words.
local function TitleOf(row)
    local first = row.keywords and row.keywords[1]
    if type(first) == "string" and first:match("^%u") then return first end
    return nil
end

local function Group(row)
    local c = row.category
    if row.questID or row.questId then return "quests" end
    if INSTANCE[c] or row.isDungeonEntrance then return "instances" end
    if c == "zone" or c == "subzone" or row.isZone then return "places" end
    if type(c) == "string" and (c:find("^classtrainer") or c:find("^prof_") or c:find("trainer", 1, true)) then return "trainers" end
    if c == "npc" then return RoleOf(row) or "npcs" end
    return "services"
end
Search._Group = Group

local function TypeLabel(row, group)
    if group == "instances" then return L[INSTANCE[row.entranceCategory or row.category] or "TYPE_DUNGEON"] end
    if group == "places" then return L[row.isZone and "TYPE_ZONE" or "TYPE_TOWN"] end
    if group == "trainers" then return L["TYPE_TRAINER"] end
    if group == "npcs" then return L["TYPE_NPC"] end
    if group == "quests" then return L["TYPE_QUEST"] end
    return L["TYPE_SERVICE"]
end

-- "World > Eastern Kingdoms" reads as its last part.
local function PlaceName(row)
    local zone = row.zoneName or row.pathPrefix
    if zone then
        local last = zone:match(".*>%s*(.+)$")
        return last or zone
    end
    return Bridge.MapName(row.coordMapID or row.mapID)
end

local function Subtitle(row, group)
    local parts = {}
    local place = PlaceName(row)
    if place and place ~= row.name then parts[#parts + 1] = place end
    parts[#parts + 1] = TitleOf(row) or TypeLabel(row, group)
    if row.spotCount and row.spotCount > 1 then parts[#parts + 1] = L["LOCATIONS_FMT"]:format(row.spotCount) end
    if row.matchNote then parts[#parts + 1] = row.matchNote end
    return table.concat(parts, " · ")
end

local function NewResult(row)
    local group = Group(row)
    local result = { name = row.name or "?", data = row, group = group, icon = row.icon, subtitle = Subtitle(row, group) }
    if row.npcID then
        local reaction = Bridge.NpcReaction(row.npcID)
        if reaction == 2 then
            result.note, result.noteTone = L["FACTION_HOSTILE"], "danger"
            result.hostile = true
        elseif reaction == 1 then
            result.note = L["FACTION_NEUTRAL"]
        end
    end
    return result
end

-- ==== coordinates ===========================================================

-- "45.2 60.1", "45,60": on the player's map. A leading name picks a zone.
local function ParseCoords(text)
    local name, a, b = text:match("^%s*(.-)[%s,]*(%d+%.?%d*)[%s,]+(%d+%.?%d*)%s*$")
    if not a then return nil end
    local x, y = tonumber(a), tonumber(b)
    if not (x and y) or x > 100 or y > 100 then return nil end
    return name ~= "" and name or nil, x / 100, y / 100
end
Search._ParseCoords = ParseCoords

local function ZoneNamed(name)
    for _, row in ipairs(Bridge.SearchPlaces(name)) do
        if row.isZone and not row.isDungeonEntrance then return row.zoneMapID or row.mapID end
    end
    return nil
end
Search.ZoneNamed = ZoneNamed

local function CoordResult(mapID, x, y)
    local zone = Bridge.MapName(mapID) or "?"
    local name = Format.Coords(x, y)
    return { name = name, group = "places", subtitle = zone .. " · " .. L["TYPE_COORDS"], iconArt = "pin",
             data = { name = zone .. " " .. name, mapID = mapID, x = x, y = y } }
end

function Search.CoordsFor(text)
    local name, x, y = ParseCoords(text)
    if not x then return nil end
    local mapID = name and ZoneNamed(name) or C_Map.GetBestMapForUnit("player")
    if not mapID then return nil end
    local result = CoordResult(mapID, x, y)
    if not Bridge.CanNavigate(result.data) then return nil end
    return result
end

-- The player's own pin on the world map, as a place to go.
function Search.MapPin()
    local wp = C_Map.GetUserWaypoint and C_Map.GetUserWaypoint()
    if not (wp and wp.uiMapID and wp.position) then return nil end
    local x, y = wp.position.x, wp.position.y
    local result = CoordResult(wp.uiMapID, x, y)
    result.name = L["MAP_PIN_NAME"]
    result.subtitle = (Bridge.MapName(wp.uiMapID) or "?") .. " · " .. Format.Coords(x, y)
    result.data.name = L["MAP_PIN_NAME"]
    return result
end

-- ==== running a search ======================================================

local function QuestResult(q)
    local status = Quests.Status(q)
    return { name = q.title, group = "quests", iconArt = q.complete and "turnin" or "quest", quest = q,
             subtitle = (q.zone and (q.zone .. " · ") or "") .. status }
end

local function SavedResults(text, out)
    local low = text:lower()
    local seen = {}
    for _, list in ipairs({ Saved.Favorites(), Saved.Recents() }) do
        for _, entry in ipairs(list) do
            local key = Saved.Key(entry.data)
            if not seen[key] and (entry.name or ""):lower():find(low, 1, true) then
                seen[key] = true
                out[#out + 1] = { name = entry.name, group = "places", data = entry.data, subtitle = entry.subtitle,
                                  icon = entry.icon, saved = true }
            end
        end
    end
end

-- results, info. info.kind: the query asks for a kind of thing, not one thing.
function Search.Run(text, filter)
    filter = filter or "all"
    text = strtrim(text or "")
    local results, info = {}, { text = text, kind = false }
    if text == "" and not Search.BROWSE[filter] then return results, info end
    local query = text ~= "" and text or Search.BROWSE[filter]
    if #query < 2 then return results, info end

    local coords = Search.CoordsFor(query)
    if coords then results[1] = coords end

    local seen = {}
    if filter == "all" or filter == "quests" then
        for _, q in ipairs(Quests.Match(query)) do results[#results + 1] = QuestResult(q) end
    end
    if filter == "all" or filter == "places" then SavedResults(query, results) end
    for i = 1, #results do
        if results[i].data then seen[Saved.Key(results[i].data)] = true end
    end

    if filter ~= "quests" then
        info.kind = Bridge.IsKindQuery(query)
        local rows = Bridge.SearchPlaces(query)
        for i = 1, #rows do
            if #results >= MAX_RESULTS then break end
            local row = rows[i]
            if not seen[Saved.Key(row)] and Bridge.CanNavigate(row) then
                local result = NewResult(row)
                if filter == "all" or result.group == filter then
                    results[#results + 1] = result
                    seen[Saved.Key(row)] = true
                end
            end
        end
        -- Hostile NPCs stay findable, after those that will talk to the player.
        local friendly, hostile = {}, {}
        for i = 1, #results do
            local list = results[i].hostile and hostile or friendly
            list[#list + 1] = results[i]
        end
        for i = 1, #hostile do friendly[#friendly + 1] = hostile[i] end
        results = friendly
    end
    return results, info
end

-- A generation number: an estimate for an old search is dropped.
local generation = 0

-- Prices the top results; onUpdate(results) after each. A search for a kind of
-- thing is then ordered by travel time, since any of them will do.
function Search.Price(results, info, onUpdate)
    generation = generation + 1
    local mine = generation
    local function Alive() return mine == generation end
    local pending = 0
    for i = 1, math.min(#results, PRICED) do
        local result = results[i]
        if result.data then
            local dest = Bridge.DestinationOf(result.data)
            pending = pending + 1
            Eta.Request(dest, function(value)
                pending = pending - 1
                result.eta = value
                result.priced = true
                if pending == 0 and info.kind then
                    table.sort(results, function(a, b)
                        local x, y = a.eta and a.eta.sec, b.eta and b.eta.sec
                        if x and y then return x < y end
                        if x or y then return x ~= nil end
                        return false
                    end)
                end
                onUpdate(results)
            end, Alive)
        end
    end
end

function Search.CancelPricing() generation = generation + 1 end

local function AtArea(target, area)
    local s = area.spot
    local data = {}
    for k, v in pairs(target.data) do data[k] = v end
    data.mapID, data.coordMapID, data.x, data.y, data.zoneName = s.mapID, s.mapID, s.x, s.y, area.zone
    target.data, target.area = data, area
    target.subtitle = area.zone
end

-- Plans the journey to one of a target's locations.
function Search.GoToArea(target, area)
    AtArea(target, area)
    FG.Planner.Inspect(target)
end

-- Plans the journey to a result: where it has several locations, the one the
-- route engine prices cheapest.
function Search.Inspect(result)
    local target = Search.Target(result)
    if not target.areas then return FG.Planner.Inspect(target) end
    FG.Planner.Hold(target)
    FG.Areas.Rank(target.areas, function(best)
        if best then Search.GoToArea(target, best) else FG.Planner.Inspect(target) end
    end)
end

-- The planner's target for a result.
function Search.Target(result)
    local target = { data = result.data, name = result.name, subtitle = result.subtitle, icon = result.icon,
                     iconArt = result.iconArt }
    local npcID = result.data and result.data.npcID
    if npcID then
        local spots = Bridge.NpcSpots(npcID)
        if spots and #spots > 1 then
            for i = 1, #spots do spots[i].name = result.name end
            local areas = FG.Areas.From(spots)
            if #areas > 1 then target.areas = areas end
        end
    end
    return target
end
