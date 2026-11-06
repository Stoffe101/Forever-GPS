-- Favorites (shared by the account's characters) and recent destinations (each
-- character's own). What is stored is enough to route there again.
local FG = ForeverGPS
local Saved = {}
FG.Saved = Saved

local MAX_RECENT = 20
local MAX_JOURNEYS = 30
local FREQUENT_AFTER = 3     -- visits before a place counts as a regular one
local RESUME_SECONDS = 12 * 3600
local KEEP = { "name", "mapID", "x", "y", "isZone", "zoneMapID", "zoneMapType", "category", "icon", "zoneName", "isDungeonEntrance",
               "entranceMapID", "entranceX", "entranceY", "entranceCategory", "coordMapID", "npcID", "displayID", "pathPrefix" }

local function Slim(data)
    local out = {}
    for i = 1, #KEEP do out[KEEP[i]] = data[KEEP[i]] end
    return out
end

function Saved.Key(data)
    local x = data.x and ("%.3f"):format(data.x) or "-"
    local y = data.y and ("%.3f"):format(data.y) or "-"
    return ("%s|%s|%s|%s"):format(data.name or "?", data.zoneMapID or data.mapID or 0, x, y)
end

local function Entry(target)
    return { data = Slim(target.data), name = target.name or target.data.name, subtitle = target.subtitle, icon = target.icon }
end

local function IndexIn(list, key)
    for i = 1, #list do
        if Saved.Key(list[i].data) == key then return i end
    end
end

function Saved.AddRecent(target)
    if target.binding then return end    -- a quest lives in the quest log, not here
    local list = FG.char.recents
    local at = IndexIn(list, Saved.Key(target.data))
    local entry = Entry(target)
    if at then
        entry.count = (list[at].count or 1) + 1
        table.remove(list, at)
    end
    entry.count, entry.at = entry.count or 1, time()
    table.insert(list, 1, entry)
    for i = #list, MAX_RECENT + 1, -1 do list[i] = nil end
    FG.Emit("saved:changed")
end

-- The places gone to again and again, the most used first.
function Saved.Regulars()
    local out = {}
    for _, entry in ipairs(FG.char.recents) do
        if (entry.count or 1) >= FREQUENT_AFTER then out[#out + 1] = entry end
    end
    table.sort(out, function(a, b) return (a.count or 1) > (b.count or 1) end)
    return out
end

-- Journeys taken, the newest first: how long each took against what was planned.
function Saved.LogJourney(name, sec, planned)
    local list = FG.char.journeys
    table.insert(list, 1, { name = name, sec = sec, planned = planned, at = time() })
    for i = #list, MAX_JOURNEYS + 1, -1 do list[i] = nil end
end

function Saved.Journeys() return FG.char.journeys end

-- A journey stopped before it arrived, to pick up again.
function Saved.SetResume(name, data, stops)
    FG.char.resume = name and { name = name, data = data, stops = stops, at = time() } or nil
end

function Saved.Resume()
    local entry = FG.char.resume
    if entry and time() - entry.at > RESUME_SECONDS then
        FG.char.resume = nil
        return nil
    end
    return entry
end

function Saved.ClearRecents()
    FG.char.recents = {}
    FG.Emit("saved:changed")
end

-- Keeps where the player stands as a place to come back to.
function Saved.AddHere(name)
    local mapID = C_Map.GetBestMapForUnit("player")
    local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return false end
    local x, y = pos:GetXY()
    local zone = FG.Bridge.MapName(mapID) or "?"
    name = name and name ~= "" and name or FG.L["SAVED_HERE_FMT"]:format(zone, FG.Format.Coords(x, y))
    local target = { data = { name = name, mapID = mapID, x = x, y = y }, name = name, subtitle = zone, icon = "pin" }
    if Saved.IsFavorite(target.data) then return false end
    Saved.ToggleFavorite(target)
    return true, name
end

-- A place as a line to hand to someone. Names come from the game and from the
-- player, and a chat line is no place for links, colors or other markup.
function Saved.ShareLine(name, zone, x, y)
    local function Clean(text)
        return ((tostring(text or ""):gsub("|", ""):gsub("[%c<>%[%]{}]", ""):sub(1, 40)))
    end
    return ("%s: /fgps way %s %.1f %.1f"):format(Clean(name), Clean(zone), x * 100, y * 100)
end

function Saved.Recents() return FG.char.recents end
function Saved.Favorites() return FG.db.favorites end

function Saved.IsFavorite(data)
    return IndexIn(FG.db.favorites, Saved.Key(data)) ~= nil
end

function Saved.ToggleFavorite(target)
    local list = FG.db.favorites
    local at = IndexIn(list, Saved.Key(target.data))
    if at then
        table.remove(list, at)
    else
        table.insert(list, 1, Entry(target))
    end
    FG.Emit("saved:changed")
    return at == nil
end
