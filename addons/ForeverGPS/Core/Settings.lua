-- Saved settings: account-wide in ForeverGPSDB, per character in ForeverGPSCharDB.
local FG = ForeverGPS
local ADDON = FG.ADDON
local Settings = {}
FG.Settings = Settings

local SCHEMA = 3
Settings.SCHEMA = SCHEMA

local DEFAULTS = {
    schema = SCHEMA,
    theme = "obsidian",
    arrow = "hud",              -- hud, character, tomtom or off
    hud = { enabled = true, mode = "standard", showNext = true, showEta = true, hideInCombat = false, autoHide = false,
            locked = true, opacity = 0.86, font = "normal", arrowStyle = "solid", outline = false, sound = false },
    window = {},
    map = { preview = true, areas = true, beacon = true },
    search = { prices = true, world = true },
    quests = { offerNext = true },
    minimap = { shown = true, angle = 215 },
    reducedMotion = false,
    autoClose = true,
    favorites = {},
}

local CHAR_DEFAULTS = {
    schema = SCHEMA,
    recents = {},
    mode = "fastest",
    trip = {},
    savedTrips = {},
    journeys = {},
}

local function Fill(into, from)
    for key, value in pairs(from) do
        if into[key] == nil then
            if type(value) == "table" then
                into[key] = {}
                Fill(into[key], value)
            else
                into[key] = value
            end
        elseif type(value) == "table" and type(into[key]) == "table" then
            Fill(into[key], value)
        end
    end
end
Settings._Fill = Fill

-- Each step takes settings from one schema to the next. 1.0.0 turned EasyFind's
-- character arrow off in EasyFind's own settings; that is now held at run time,
-- so the old write is undone unless the character arrow was the one chosen.
local MIGRATIONS = {
    [1] = function(db)
        local ef = EasyFind and EasyFind.db
        if ef and ef.gpsArrow == false and db.arrow ~= "off" then ef.gpsArrow = nil end
        -- 1.0.0 stored its default sizes; a size left at the default is no choice.
        if db.hud and db.hud.scale == 1 then db.hud.scale = nil end
        if db.window and db.window.scale == 1 then db.window.scale = nil end
    end,
    -- 2.1.0 is one addon: there is no separate EasyFind left to put back.
    [2] = function(db)
        db.easyFindBefore, db.firstRunDone = nil, nil
    end,
}

-- A UI scale addon can leave UIParent as tall as the screen in pixels, where a
-- window sized for 768 units reads small. Below that, sizes stay as they are.
local ROOMY_HEIGHT, ROOMY_SCALE = 1000, 1.25

local function ScaleFor(chosen)
    if chosen then return chosen end
    return UIParent:GetHeight() >= ROOMY_HEIGHT and ROOMY_SCALE or 1
end

function Settings.WindowScale() return ScaleFor(FG.db.window.scale) end
function Settings.HudScale() return ScaleFor(FG.db.hud.scale) end

local function Migrate(db)
    for from = (db.schema or 1), SCHEMA - 1 do
        if MIGRATIONS[from] then FG.Try(MIGRATIONS[from], db) end
    end
    db.schema = SCHEMA
end

function Settings.Load()
    ForeverGPSDB = ForeverGPSDB or {}
    ForeverGPSCharDB = ForeverGPSCharDB or {}
    local existing = ForeverGPSDB.schema
    Fill(ForeverGPSDB, DEFAULTS)
    Fill(ForeverGPSCharDB, CHAR_DEFAULTS)
    FG.db, FG.char = ForeverGPSDB, ForeverGPSCharDB
    ForeverGPSDB.schema = existing or SCHEMA
    Migrate(ForeverGPSDB)
    ForeverGPSCharDB.schema = SCHEMA
end

function Settings.ResetPlaces()
    local db = FG.db
    db.hud.point, db.window.point, db.window.width, db.window.height = nil, nil, nil, nil
    FG.Emit("places:reset")
end

FG.OnEvent("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    Settings.Load()
    FG.Emit("loaded")
end)

FG.OnEvent("PLAYER_LOGIN", function()
    if not FG.db then Settings.Load() end
    FG.Emit("login")
end)
