-- Slash commands, key bindings and the addon compartment: thin doors onto the
-- window and the planner.
local FG = ForeverGPS
local L = FG.L
local Bridge, Search, Planner = FG.Bridge, FG.Search, FG.Planner

function FG.Toggle() FG.Window.Toggle() end
function FG.OpenQuests() FG.Window.Show("quests") end
function FG.StopNavigation() Bridge.Stop() end
function FG.QuickOpen() FG.Quick.Toggle() end

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

local function Save(rest)
    local ok, name = FG.Saved.AddHere(rest)
    FG.Print(ok and L["SAVED_DONE_FMT"]:format(name) or L["SAVED_FAILED"])
end

-- The destination as a line to pass on, cleaned of anything but its words.
local function Share()
    local plan = Planner.Current()
    local route = Bridge.Route()
    local dest = plan and plan.dest or route and route.dest
    if not (dest and dest.mapID and dest.x) then return FG.Print(L["SHARE_NOTHING"]) end
    FG.CopyBox.Show(FG.Saved.ShareLine(dest.name, Bridge.MapName(dest.mapID), dest.x, dest.y))
end

local COMMANDS = {
    go = function(rest) FG.Quick.Open(rest) end,
    save = Save,
    share = Share,
    trip = function() FG.Window.Show("trip") end,
    report = function() FG.CopyBox.Show(FG.Diagnostics.Report()) end,
    quests = FG.OpenQuests,
    stop = FG.StopNavigation,
    way = Way,
    hud = Hud,
    diag = function() FG.Diagnostics.Print() end,
    reset = function() FG.Settings.ResetPlaces() end,
}

local function Help()
    FG.Print(L["HELP_HEADER"])
    for _, key in ipairs({ "HELP_TOGGLE", "HELP_GO", "HELP_QUESTS", "HELP_TRIP", "HELP_WAY", "HELP_SAVE", "HELP_SHARE", "HELP_STOP",
                           "HELP_HUD", "HELP_DIAG", "HELP_REPORT", "HELP_RESET" }) do
        print("  " .. L[key])
    end
end

-- The old separate folders, left enabled by a hand upgrade: offered a way out, once a
-- session, because two copies of one addon cannot share a session.
local function OfferCleanup()
    local old = ForeverGPSPreflight.old
    if #old == 0 then return end
    StaticPopupDialogs["FOREVERGPS_OLD_FOLDERS"] = {
        text = L["OLD_FOLDERS_POPUP"], button1 = L["OLD_FOLDERS_DISABLE"], button2 = CANCEL,
        OnAccept = function()
            for _, name in ipairs(old) do pcall(C_AddOns.DisableAddOn, name) end
            ReloadUI()
        end,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }
    StaticPopup_Show("FOREVERGPS_OLD_FOLDERS")
end
FG.On("login", OfferCleanup)

SLASH_FOREVERGPS1, SLASH_FOREVERGPS2 = "/fgps", "/forevergps"
SlashCmdList["FOREVERGPS"] = function(input)
    input = strtrim(input or "")
    if input == "" then return FG.Toggle() end
    local word, rest = input:match("^(%S+)%s*(.-)$")
    local fn = COMMANDS[word:lower()]
    if fn then return fn(rest) end
    Help()
end
