-- Favorites (shared by the account's characters) and recent destinations (each
-- character's own). What is stored is enough to route there again.
local _, FG = ...
local Saved = {}
FG.Saved = Saved

local MAX_RECENT = 12
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
    if at then table.remove(list, at) end
    table.insert(list, 1, Entry(target))
    for i = #list, MAX_RECENT + 1, -1 do list[i] = nil end
    FG.Emit("saved:changed")
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
