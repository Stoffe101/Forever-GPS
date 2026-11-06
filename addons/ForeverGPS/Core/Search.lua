-- Search: one list from EasyFind's map search, the NPC catalog, Questie's world,
-- the transport network, the player's quests, saved places and typed coordinates.
--
-- It works in stages, so typing never waits on routing: names are matched at once,
-- from indexes; the top results are then priced in later frames by the engine's
-- straight-line estimate; and only the destination picked gets a full ground route.
-- Where a search asks for a kind of thing (any inn), the list ends up in order of
-- travel time, and a row standing for many places picks the one quickest to reach.
local FG = ForeverGPS
local Search = {}
FG.Search = Search

local Bridge, Eta, Format, Quests, Risk, Saved = FG.Bridge, FG.Eta, FG.Format, FG.Quests, FG.Risk, FG.Saved
local L = FG.L

local MAX_RESULTS = 30
local PRICED = 10            -- results that get a travel time, from the top
local MAX_QUERY = 64
local WORLD_ROWS = 8         -- rows from Questie's world in one search
local MAX_FIX = 2            -- spelling distance tolerated

Search.FILTERS = {
    { key = "all", label = "CAT_ALL" },
    { key = "quests", label = "CAT_QUESTS" },
    { key = "services", label = "CAT_SERVICES" },
    { key = "trainers", label = "CAT_TRAINERS" },
    { key = "travel", label = "CAT_TRAVEL" },
    { key = "instances", label = "CAT_INSTANCES" },
    { key = "places", label = "CAT_PLACES" },
    { key = "npcs", label = "CAT_NPCS" },
}

-- What a filter shows with nothing typed.
Search.BROWSE = { services = "services", trainers = "trainer", instances = "dungeon", travel = "transport" }

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

-- ==== understanding what was typed ==========================================

-- Words that ask for the nearest of something rather than name it.
local NEAREST_WORDS = { nearest = true, closest = true, any = true, nearby = true }
-- Words that carry no meaning in a place search.
local STOP_WORDS = { the = true, a = true, an = true, find = true, where = true, is = true, go = true, to = true,
                     me = true, my = true, take = true, near = true, some = true, ["for"] = true, a2 = true }
-- What players call things, as the search knows them. Whole phrase first.
local PHRASES = {
    ah = "auction house", fp = "flight master", fm = "flight master", ["flight path"] = "flight master",
    flightpath = "flight master", ["flight point"] = "flight master", flights = "flight master", gryphon = "flight master",
    hearth = "innkeeper", hearthstone = "innkeeper", tavern = "innkeeper", rest = "innkeeper",
    innkeep = "innkeeper", post = "mailbox", mail = "mailbox", letterbox = "mailbox", banker = "bank", vault = "bank",
    auctioneer = "auction house", auction = "auction house", smith = "blacksmith", anvil = "repair", repairs = "repair",
    shop = "vendor", store = "vendor", merchant = "vendor", goods = "general goods",
    stable = "stable master", stablemaster = "stable master", wm = "weapon master", weaponmaster = "weapon master",
    ship = "boat", zep = "zeppelin", subway = "tram", profession = "trainer", skills = "trainer", xp = "trainer",
}

-- Asking for what this character can use, not for a word. "my trainer" is a class trainer.
local function OwnTrainer()
    local _, class = UnitClass("player")
    return class and (class:sub(1, 1) .. class:sub(2):lower() .. " trainer") or "trainer"
end

-- Flight paths not yet learned: a question about the player, not about a place.
local LEARN_PHRASES = { ["flights to learn"] = true, ["flight paths to learn"] = true, ["learn flights"] = true,
                        ["learn flight paths"] = true, ["unlearned flights"] = true, ["unlearned flight paths"] = true,
                        ["new flight paths"] = true, ["new flights"] = true, ["flights i need"] = true }

-- The query as the search should read it, and whether it asked for "the nearest".
local function Normalize(text)
    text = text:lower():gsub("%s+", " ")
    if text == "my trainer" or text == "class trainer" then return OwnTrainer():lower(), true end
    local words, nearest = {}, false
    for word in text:gmatch("%S+") do
        if NEAREST_WORDS[word] then nearest = true
        elseif not STOP_WORDS[word] then words[#words + 1] = word end
    end
    local phrase = table.concat(words, " ")
    if phrase == "" then return strtrim(text), false end
    if PHRASES[phrase] then return PHRASES[phrase], nearest end
    for i = 1, #words do
        -- "auction house" typed in full is already what "auction" would become.
        local means, after = PHRASES[words[i]], words[i + 1]
        if means and not (after and means:find(after, 1, true)) then words[i] = means end
    end
    return table.concat(words, " "), nearest
end
Search._Normalize = Normalize

-- ==== spelling ==============================================================

-- Edit distance, stopping as soon as it passes limit. Bounded by the word's length,
-- so it costs nothing on a short vocabulary.
local function Distance(a, b, limit)
    local la, lb = #a, #b
    if math.abs(la - lb) > limit then return limit + 1 end
    local prev, cur = {}, {}
    for j = 0, lb do prev[j] = j end
    for i = 1, la do
        cur[0] = i
        local best, ca = i, a:byte(i)
        for j = 1, lb do
            local cost = ca == b:byte(j) and 0 or 1
            local v = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            cur[j] = v
            if v < best then best = v end
        end
        if best > limit then return limit + 1 end
        prev, cur = cur, prev
    end
    return prev[lb]
end
Search._Distance = Distance

local vocabulary

-- Zone, town and service words: all a misspelling is worth checking against.
local function Vocabulary()
    if vocabulary then return vocabulary end
    vocabulary = {}
    local seen = {}
    local function Add(text)
        for word in (text or ""):lower():gmatch("[%a']+") do
            if #word >= 4 and not seen[word] then
                seen[word] = true
                vocabulary[#vocabulary + 1] = word
            end
        end
    end
    for _, name in ipairs(Bridge.PlaceNames()) do Add(name) end
    for _, phrase in pairs(PHRASES) do Add(phrase) end
    for _, word in ipairs({ "innkeeper", "mailbox", "bank", "repair", "trainer", "vendor", "zeppelin", "dungeon", "raid",
                            "tram", "portal", "boat", "stable", "master" }) do Add(word) end
    return vocabulary
end

-- The query with each unknown word replaced by the word it was surely meant to be;
-- nil when nothing is close enough to be sure of.
local function Corrected(query)
    local changed, words = false, {}
    for word in query:gmatch("%S+") do
        local best, bestD = nil, MAX_FIX + 1
        if #word >= 4 then
            for _, known in ipairs(Vocabulary()) do
                if known == word then best, bestD = nil, 0 break end
                local d = Distance(word, known, math.min(MAX_FIX, bestD))
                if d < bestD then best, bestD = known, d end
            end
        end
        if best and bestD > 0 and bestD <= MAX_FIX then
            words[#words + 1] = best
            changed = true
        else
            words[#words + 1] = word
        end
    end
    return changed and table.concat(words, " ") or nil
end
Search._Corrected = Corrected

-- ==== classifying a row =====================================================

local INSTANCE = { dungeon = "TYPE_DUNGEON", raid = "TYPE_RAID", delve = "TYPE_DELVE" }
local TRAVEL = { flightmaster = true, boat = true, zeppelin = true, portal = true, tram = true }

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
    if TRAVEL[c] then return "travel" end
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
    if group == "travel" then return L["TYPE_TRAVEL"] end
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
    if row.allInstances and #row.allInstances > 1 then
        result.instances = row.allInstances
    elseif group ~= "places" and group ~= "instances" and row.x and not result.hostile then
        -- A service in an enemy town is still a place, but not one to send anyone
        -- to without saying so.
        local ci, wx, wy = Bridge.WorldPos(row.coordMapID or row.mapID, row.x, row.y)
        if ci and Risk.EnemyGround(ci, wx, wy, row.coordMapID or row.mapID) then
            result.note, result.noteTone, result.hostile = L["FACTION_ENEMY_TOWN"], "danger", true
        end
    end
    return result
end

-- ==== coordinates ===========================================================

-- "45.2 60.1", "45,60", "45.2/60.1", "/way 45 60": on the player's map. A name before or
-- after them picks a zone.
local function ParseCoords(text)
    text = text:gsub("^%s*/?way%s+", "")
    local name, a, b = text:match("^%s*(.-)[%s,:]*(%d+%.?%d*)[%s,/]+(%d+%.?%d*)%s*$")
    if not a then
        a, b, name = text:match("^%s*(%d+%.?%d*)[%s,/]+(%d+%.?%d*)[%s,:]+(%a.-)%s*$")
    end
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

local function CoordResult(mapID, x, y)
    local zone = Bridge.MapName(mapID) or "?"
    local name = Format.Coords(x, y)
    return { name = name, group = "places", subtitle = zone .. " · " .. L["TYPE_COORDS"], iconArt = "pin",
             data = { name = zone .. " " .. name, mapID = mapID, x = x, y = y } }
end

function Search.CoordsFor(text)
    local name, x, y = ParseCoords(text)
    if not x then return nil end
    -- A zone typed but not found is not the zone the player happens to stand in.
    local mapID
    if name then mapID = ZoneNamed(name) else mapID = C_Map.GetBestMapForUnit("player") end
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

-- ==== the transport network =================================================

-- What each way of travel answers to.
local TRANSPORT_WORDS = {
    boat = "boat ship ferry dock harbor pier", ferry = "boat ship ferry dock harbor pier",
    zeppelin = "zeppelin zep tower airship", skyship = "skyship airship",
    tram = "tram subway deeprun", portal = "portal",
}

local transports

-- Every ride this character may take, each as a place to go to board it.
local function Transports()
    if transports then return transports end
    transports = {}
    local faction = UnitFactionGroup("player")
    local seen = {}
    for _, e in ipairs(Bridge.TransportEdges()) do
        local words = TRANSPORT_WORDS[e.kind]
        local p = e.from
        if words and p and (not e.faction or e.faction == faction) and not e.race then
            local key = ("%s|%s|%.2f|%.2f"):format(e.n or "?", p.m or 0, p.x or 0, p.y or 0)
            if not seen[key] then
                seen[key] = true
                local place = Bridge.AreaName(p.area) or Bridge.MapName(p.m) or "?"
                local fake = { kind = e.kind }
                transports[#transports + 1] = {
                    name = e.n or "?", group = "travel", iconArt = FG.Kinds.Info(fake).icon,
                    subtitle = place .. " · " .. FG.Kinds.Label(fake),
                    words = (words .. " " .. (e.n or "") .. " " .. place .. " " .. (e.dest or "")):lower(),
                    data = { name = e.n or "?", mapID = p.m, x = p.x, y = p.y, step = e.n },
                }
            end
        end
    end
    return transports
end

local function TransportResults(query, out)
    local anyMatch = query == "transport" or query == "transports" or query == "travel"
    for _, row in ipairs(Transports()) do
        local all = true
        for word in query:gmatch("%S+") do
            if not row.words:find(word, 1, true) then all = false end
        end
        if (all or anyMatch) and Bridge.CanNavigate(row.data) then
            out[#out + 1] = { name = row.name, group = row.group, iconArt = row.iconArt, subtitle = row.subtitle, data = row.data }
        end
    end
end

-- ==== flight paths to learn ==================================================

local function LearnResults(out)
    for _, node in ipairs(Bridge.UnlearnedFlights()) do
        local data = { name = node.name, mapID = node.m, x = node.x, y = node.y }
        if Bridge.CanNavigate(data) then
            out[#out + 1] = { name = node.name:match("^[^,]+") or node.name, group = "travel", iconArt = "flight", data = data,
                              subtitle = (Bridge.MapName(node.m) or "?") .. " \194\183 " .. L["SEARCH_FLIGHT_TO_LEARN"] }
        end
    end
end

-- ==== Questie's world =======================================================

-- Creatures and objects only Questie knows: common mobs, herbs, veins and chests.
-- Read from the installed addon as asked for, never copied.
local function WorldResults(query, listed, out)
    if not FG.db.search.world then return end
    local found = Bridge.FindWorld(query, WORLD_ROWS)
    for _, entry in ipairs(found or {}) do
        if not (entry.kind == "npc" and Bridge.NpcKnown(entry.id)) and not listed[entry.name] then
            local spots = Bridge.WorldSpots(entry.kind, entry.id)
            local first = spots and spots[1]
            if first then
                listed[entry.name] = true
                local parts = {}
                if entry.zone then parts[#parts + 1] = entry.zone end
                parts[#parts + 1] = entry.title or L[entry.kind == "object" and "TYPE_OBJECT" or "TYPE_NPC"]
                if #spots > 1 then parts[#parts + 1] = L["SPAWNS_FMT"]:format(#spots) end
                out[#out + 1] = {
                    name = entry.name, group = "npcs", iconArt = entry.kind == "object" and "pin" or "walk",
                    subtitle = table.concat(parts, " · "), spots = spots, world = true,
                    data = { name = entry.name, mapID = first.mapID, x = first.x, y = first.y },
                }
            end
        end
    end
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

-- The results for an understood query, in the filter.
local function Gather(query, filter, info)
    local results = {}
    local coords = Search.CoordsFor(query)
    if coords then results[1] = coords end

    local seen, names = {}, {}
    if filter == "all" or filter == "quests" then
        for _, q in ipairs(Quests.Match(query)) do results[#results + 1] = QuestResult(q) end
    end
    if filter == "all" or filter == "places" then SavedResults(query, results) end
    for i = 1, #results do
        if results[i].data then seen[Saved.Key(results[i].data)] = true end
    end
    if filter == "quests" then return results end

    info.kind = info.kind or Bridge.IsKindQuery(query)
    local rows = Bridge.SearchPlaces(query)
    for i = 1, #rows do
        if #results >= MAX_RESULTS then break end
        local row = rows[i]
        if not seen[Saved.Key(row)] and Bridge.CanNavigate(row) then
            local result = NewResult(row)
            if filter == "all" or result.group == filter then
                results[#results + 1] = result
                seen[Saved.Key(row)] = true
                names[result.name] = true
            end
        end
    end
    if filter == "all" or filter == "travel" then TransportResults(query, results) end
    if (filter == "all" or filter == "npcs") and #results < MAX_RESULTS then WorldResults(query, names, results) end

    -- Hostile NPCs stay findable, after those that will talk to the player.
    local friendly, hostile = {}, {}
    for i = 1, #results do
        local list = results[i].hostile and hostile or friendly
        list[#list + 1] = results[i]
    end
    for i = 1, #hostile do friendly[#friendly + 1] = hostile[i] end
    return friendly
end

-- results, info. info.kind: the query asks for a kind of thing, not one thing.
-- info.corrected: what it was read as, when the spelling needed help.
function Search.Run(text, filter)
    filter = filter or "all"
    text = strtrim(text or ""):sub(1, MAX_QUERY)
    local info = { text = text, kind = false }
    if text == "" and not Search.BROWSE[filter] then return {}, info end
    FG.Metrics.Begin("search")
    local query, nearest = Normalize(text ~= "" and text or Search.BROWSE[filter])
    if #query < 2 then
        FG.Metrics.End("search")
        return {}, info
    end
    info.query, info.kind = query, nearest
    if LEARN_PHRASES[text:lower()] then
        local results = {}
        LearnResults(results)
        info.kind = true
        info.learn = true
        info.unknown = Bridge.KnownFlights() == nil
        FG.Metrics.End("search")
        return results, info
    end
    local results = Gather(query, filter, info)
    if #results == 0 then
        local fixed = Corrected(query)
        if fixed then
            results = Gather(fixed, filter, info)
            if #results > 0 then info.corrected = fixed end
        end
    end
    FG.Metrics.End("search")
    return results, info
end

-- ==== travel time ===========================================================

-- A generation number: an estimate for an old search is dropped.
local generation = 0

local function Spots(result)
    local out = {}
    for _, s in ipairs(result.instances) do
        out[#out + 1] = { mapID = s.coordMapID or s.mapID, x = s.x, y = s.y, name = result.name }
    end
    return out
end

-- A row's places as areas to choose among, each its own: any one will do, so
-- nothing is merged, and enemy ground is passed over while friendly ground remains.
local function Candidates(result)
    local areas = FG.Areas.From(Spots(result), true)
    local usable = {}
    for _, area in ipairs(areas) do
        area.enemy = Risk.EnemyGround(area.ci, area.wx, area.wy, area.spot.mapID)
        if not area.enemy then usable[#usable + 1] = area end
    end
    return #usable > 0 and usable or areas
end

local function AtArea(data, area)
    local s = area.spot
    local copy = {}
    for k, v in pairs(data) do copy[k] = v end
    copy.mapID, copy.coordMapID, copy.x, copy.y, copy.zoneName = s.mapID, s.mapID, s.x, s.y, area.zone
    return copy
end

-- Moves a many-place row onto the place quickest to reach.
local function PriceInstances(result, alive, done)
    local areas = Candidates(result)
    FG.Areas.Rank(areas, function(best, basis)
        if not alive() then return end
        if best then
            result.data = AtArea(result.data, best)
            result.basis = basis
            result.areas, result.area = areas, best
            result.eta = best.sec and { sec = best.sec, transports = best.transports } or nil
            result.priced = true
            result.subtitle = (best.zone or "?") .. " · " .. L["LOCATIONS_FMT"]:format(#result.instances)
        end
        done()
    end, alive)
end

local function ByTravelTime(a, b)
    local x, y = a.eta and a.eta.sec, b.eta and b.eta.sec
    if x and y then return x < y end
    if x or y then return x ~= nil end
    return false
end

-- Prices the top results; onUpdate(results) after each. A search for a kind of
-- thing is then ordered by travel time, since any of them will do.
function Search.Price(results, info, onUpdate)
    generation = generation + 1
    if not FG.db.search.prices then return end
    local mine = generation
    local function Alive() return mine == generation end
    local pending = 0
    local function Done()
        pending = pending - 1
        if pending == 0 and info.kind then table.sort(results, ByTravelTime) end
        onUpdate(results)
    end
    for i = 1, math.min(#results, PRICED) do
        local result = results[i]
        if result.data then
            pending = pending + 1
            if result.instances then
                PriceInstances(result, Alive, Done)
            else
                Eta.Request(Bridge.DestinationOf(result.data), function(value)
                    result.eta, result.priced = value, true
                    Done()
                end, Alive)
            end
        end
    end
end

function Search.CancelPricing() generation = generation + 1 end

-- ==== going there ===========================================================

-- Plans the journey to one of a target's locations.
function Search.GoToArea(target, area)
    target.data, target.area = AtArea(target.data, area), area
    target.subtitle = area.zone
    FG.Planner.Inspect(target)
end

-- The planner's target for a result.
function Search.Target(result)
    local target = { data = result.data, name = result.name, subtitle = result.subtitle, icon = result.icon,
                     iconArt = result.iconArt, predicted = result.world }
    if result.areas then
        target.areas, target.area = result.areas, result.area
        return target
    end
    if result.instances then
        target.areas = Candidates(result)
        return target
    end
    local spots = result.spots
    local npcID = result.data and result.data.npcID
    if not spots and npcID then
        spots = Bridge.NpcSpots(npcID)
        for i = 1, spots and #spots or 0 do spots[i].name = result.name end
    end
    if spots and #spots > 1 then
        local areas = FG.Areas.From(spots)
        if #areas > 1 then target.areas = areas end
        target.predicted = true
    end
    return target
end

-- Plans the journey to a result: where it has several locations, the one the
-- route engine prices cheapest.
function Search.Inspect(result)
    local target = Search.Target(result)
    if not target.areas or target.area then return FG.Planner.Inspect(target) end
    FG.Planner.Hold(target)
    FG.Areas.Rank(target.areas, function(best)
        if best then Search.GoToArea(target, best) else FG.Planner.Inspect(target) end
    end)
end
