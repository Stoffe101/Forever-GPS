-- Slash commands, key bindings and the addon compartment: thin doors onto the
-- window and the planner.
local _, FG = ...
local L = FG.L
local Bridge, Search, Planner = FG.Bridge, FG.Search, FG.Planner

function FG.Toggle() FG.Window.Toggle() end
function FG.OpenQuests() FG.Window.Show("quests") end
function FG.StopNavigation() Bridge.Stop() end

-- ForeverGPS_OnCompartmentClick is named in the TOC.
function ForeverGPS_OnCompartmentClick() FG.Toggle() end

local function Way(rest)
    local result = Search.CoordsFor(rest)
    if result then
        FG.Window.Show("search")
        Planner.Inspect(Search.Target(result))
        return
    end
    local name = Search._ParseCoords(rest)
    if name then
        FG.Print(L["WAY_NO_ZONE"]:format(name))
    else
        FG.Print(L["WAY_BAD"])
    end
end

local function Hud(rest)
    if rest == "unlock" or rest == "lock" then
        FG.db.hud.locked = rest == "lock"
    else
        FG.db.hud.enabled = not FG.db.hud.enabled
    end
    FG.Emit("settings:changed")
end

local COMMANDS = {
    quests = FG.OpenQuests,
    stop = FG.StopNavigation,
    way = Way,
    hud = Hud,
    diag = function() FG.Diagnostics.Print() end,
    reset = function() FG.Settings.ResetPlaces() end,
}

local function Help()
    FG.Print(L["HELP_HEADER"])
    for _, key in ipairs({ "HELP_TOGGLE", "HELP_QUESTS", "HELP_WAY", "HELP_STOP", "HELP_HUD", "HELP_DIAG", "HELP_RESET" }) do
        print("  " .. L[key])
    end
end

SLASH_FOREVERGPS1, SLASH_FOREVERGPS2 = "/fgps", "/forevergps"
SlashCmdList["FOREVERGPS"] = function(input)
    input = strtrim(input or "")
    if input == "" then return FG.Toggle() end
    local word, rest = input:match("^(%S+)%s*(.-)$")
    local fn = COMMANDS[word:lower()]
    if fn then return fn(rest) end
    Help()
end
