-- The first file the addon loads, ahead of everything under Vendor/.
--
-- EasyFind's search bar and welcome are never Forever-GPS's interface, and what the old
-- separate folders saved has to arrive before the vendored code reads its settings. The
-- assembly has EasyFind call Settle the moment it has them, so none of this depends on
-- which frame hears ADDON_LOADED first.
--
-- The old folders must also be gone. Two copies of one addon in one session fight over the
-- same global names, so if they are still there the player is told, once.
local OLD_FOLDERS = { "EasyFind", "EasyFind_Calc", "EasyFind_Clipboard", "EasyFind_GPS", "EasyFind_Guide", "EasyFind_Icons", "EasyFind_Items",
                      "EasyFind_Onboarding", "EasyFind_Options", "EasyFind_Questie", "EasyFind_Quicklists", "EasyFind_Settings", "EasyFind_Snippets" }

local Loaded = C_AddOns and C_AddOns.IsAddOnLoaded

-- Which old folders loaded this session.
local function OldAddons()
    local out = {}
    for _, name in ipairs(OLD_FOLDERS) do
        if Loaded and Loaded(name) then out[#out + 1] = name end
    end
    return out
end

ForeverGPSPreflight = { old = OldAddons(), folders = OLD_FOLDERS }

-- WoW Forever's own Gamepad UI (Options, Gamepad, "Enable Gamepad UI"): Blizzard's
-- Blizzard_Gamepad* modules, which keep their focus and binding bookkeeping in shared
-- tables. Whatever an addon does that runs that bookkeeping in its own execution (adds an
-- entry to a Blizzard menu, opens its own Blizzard-style menu or popup, opens or closes a
-- Blizzard panel, makes a frame under an open Blizzard panel) taints it, and from then on
-- Blizzard's own restricted SetPreferredGamepadInteractTarget() is blocked and blamed on
-- that addon, again at every target change. While it is on, everything of ours that would
-- do that stands aside: docs/CONTROLLER.md, "The game's Gamepad UI".
-- Read only: asking the style taints nothing.
function ForeverGPSPreflight.GamepadUI()
    local api, kinds = C_InputInterfaceStyle, Enum and Enum.InputDeviceInterfaceType
    if not (api and api.GetCurrentStyle and kinds and kinds.Gamepad ~= nil) then return false end
    return api.GetCurrentStyle() == kinds.Gamepad
end

-- Adds what is missing, and leaves what is already there: nothing newer is overwritten.
local function Fill(into, from)
    for key, value in pairs(from) do
        if into[key] == nil then
            into[key] = value
        elseif type(into[key]) == "table" and type(value) == "table" then
            Fill(into[key], value)
        end
    end
end

-- What the separate EasyFind folders saved, when tools/migrate_saved.py found any. All of
-- EasyFind GPS's own state is under these keys: flight paths, the route, the hearth, boats.
local function Import(db)
    local data = ForeverGPSImported
    if not data then return end
    ForeverGPSImported = nil     -- held only for this: it is not worth its memory after
    ForeverGPSDB = ForeverGPSDB or {}
    if ForeverGPSDB.importedFrom == data.id then return end
    ForeverGPSDB.importedFrom = data.id
    for _, old in ipairs(data.accounts or {}) do
        for key, value in pairs(old) do
            if type(key) == "string" and key:sub(1, 3) == "gps" then
                if db[key] == nil then
                    db[key] = value
                elseif type(db[key]) == "table" and type(value) == "table" then
                    Fill(db[key], value)
                end
            end
        end
    end
end

-- Called by the vendored EasyFind as soon as it has its settings.
function ForeverGPSPreflight.Settle(db)
    db.tutorialDone = true
    db.showForeverWelcome = false
    db.visible = false
    db.spotlightsDone = db.spotlightsDone or {}
    db.spotlightsDone.snippets31 = true
    Import(db)
end
