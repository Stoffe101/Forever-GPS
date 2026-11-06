-- Saved settings: account-wide in ForeverGPSDB, per character in ForeverGPSCharDB.
local ADDON, FG = ...
local Settings = {}
FG.Settings = Settings

local SCHEMA = 2
Settings.SCHEMA = SCHEMA

local DEFAULTS = {
    schema = SCHEMA,
    theme = "obsidian",
    arrow = "hud",              -- hud, character, tomtom or off
    hud = { enabled = true, mode = "standard", showNext = true, showEta = true, hideInCombat = false, autoHide = false,
            locked = true, opacity = 0.86, font = "normal", arrowStyle = "solid" },
    window = {},
    map = { preview = true, areas = true },
    search = { prices = true, world = true },
    quests = { offerNext = true },
    minimap = { shown = true, angle = 215 },
    reducedMotion = false,
    autoClose = true,
    favorites = {},
    firstRunDone = false,
}

local CHAR_DEFAULTS = {
    schema = SCHEMA,
    recents = {},
    mode = "fastest",
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

-- EasyFind ships a welcome and its own search bar. With Forever-GPS as the way
-- in, a fresh install starts without them. Someone who already uses EasyFind
-- keeps it as it is, and what is changed is kept, so it can be put back.
local function FirstRun(db)
    local ef = EasyFind and EasyFind.db
    if db.firstRunDone or not ef then return end
    db.firstRunDone = true
    if ef.tutorialDone then return end
    db.easyFindBefore = { visible = ef.visible, showForeverWelcome = ef.showForeverWelcome }
    ef.tutorialDone = true
    ef.showForeverWelcome = false
    ef.visible = false
    ef.spotlightsDone = ef.spotlightsDone or {}
    ef.spotlightsDone.snippets31 = true
end

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

-- Puts back what the first run changed in EasyFind.
function Settings.RestoreEasyFind()
    local ef, before = EasyFind and EasyFind.db, FG.db.easyFindBefore
    if not ef then return end
    if before then ef.showForeverWelcome = before.showForeverWelcome end
    FG.Bridge.SetEasyFindBar(not before or before.visible ~= false)
    FG.db.easyFindBefore = nil
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
    FirstRun(FG.db)
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
