-- Saved settings: account-wide in ForeverGPSDB, per character in ForeverGPSCharDB.
local ADDON, FG = ...
local Settings = {}
FG.Settings = Settings

local SCHEMA = 1

local DEFAULTS = {
    schema = SCHEMA,
    theme = "obsidian",
    arrow = "hud",              -- hud, character, tomtom or off
    hud = { enabled = true, showNext = true, hideInCombat = false, locked = true, scale = 1 },
    window = { scale = 1 },
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
-- in, a new install starts without them; settings can bring the bar back.
local function FirstRun(db)
    if db.firstRunDone then return end
    db.firstRunDone = true
    local ef = EasyFind and EasyFind.db
    if ef then
        ef.tutorialDone = true
        ef.showForeverWelcome = false
        ef.visible = false
        ef.spotlightsDone = ef.spotlightsDone or {}
        ef.spotlightsDone.snippets31 = true
    end
end

function Settings.Load()
    ForeverGPSDB = ForeverGPSDB or {}
    ForeverGPSCharDB = ForeverGPSCharDB or {}
    Fill(ForeverGPSDB, DEFAULTS)
    Fill(ForeverGPSCharDB, CHAR_DEFAULTS)
    FG.db, FG.char = ForeverGPSDB, ForeverGPSCharDB
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
