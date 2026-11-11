-- Slash commands, key bindings and the addon compartment: thin doors onto the
-- window and the planner.
local FG = ForeverGPS
local L = FG.L
local Bridge, Search, Planner = FG.Bridge, FG.Search, FG.Planner

function FG.Toggle() FG.Window.Toggle() end
function FG.OpenQuests() FG.Window.Show("quests") end
function FG.StopNavigation() Bridge.Stop() end
function FG.QuickOpen() FG.Quick.Toggle() end

-- The journey last stopped short, looked at again.
function FG.Resume()
    local entry = FG.Saved.Resume()
    if not entry then return FG.Print(L["RESUME_NOTHING"]) end
    if entry.stops and #entry.stops > 1 then
        Planner.Inspect({ stops = entry.stops, name = entry.name, data = entry.data, trip = true })
    else
        Planner.Inspect({ data = entry.data, name = entry.name })
    end
    FG.Window.ShowRoute()
end

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

-- Directions to whatever is targeted, by name.
function FG.DirectionsToTarget()
    local name = UnitName("target")
    if not name then return FG.Print(L["TARGET_NONE"]) end
    local results = Search.Run(name, "all")
    for _, result in ipairs(results) do
        if result.data and result.name == name then
            Search.Inspect(result)
            return FG.Window.ShowRoute()
        end
    end
    FG.Print(L["TARGET_UNKNOWN_FMT"]:format(name))
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

-- A quest by name or id, opened if there is one clear answer, otherwise listed.
local function FindQuest(rest)
    FG.Window.Show("quests")
    FG.QuestsView.SetMode("find")
    if rest == "" then return end
    FG.ExplorerView.Search(rest)
    local rows = FG.QuestIndex.Find(rest)
    if tonumber(rest) and rows[1] then FG.ExplorerView.Open(FG.QuestIndex.Row(rows[1]).id) end
end

local COMMANDS = {
    go = function(rest) FG.Quick.Open(rest) end,
    quest = FindQuest,
    target = FG.DirectionsToTarget,
    resume = function() FG.Resume() end,
    save = Save,
    share = Share,
    trip = function() FG.Window.Show("trip") end,
    report = function() FG.CopyBox.Show(FG.Diagnostics.Report()) end,
    quests = FG.OpenQuests,
    stop = FG.StopNavigation,
    way = Way,
    hud = Hud,
    diag = function() FG.Diagnostics.Print() end,
    alert = function(rest) FG.Commands.Alert(rest) end,
    alerts = function() FG.Commands.Alert("") end,
    reset = function() FG.Settings.ResetPlaces() end,
}

-- "1g20s", "35s", "120c" or plain copper, to copper.
local function ParseMoney(text)
    text = (text or ""):lower():gsub("%s", "")
    if text:match("^%d+$") then return tonumber(text) end
    local g, s, c = text:match("(%d+)g"), text:match("(%d+)s"), text:match("(%d+)c")
    if not (g or s or c) then return nil end
    return (tonumber(g) or 0) * 10000 + (tonumber(s) or 0) * 100 + (tonumber(c) or 0)
end

FG.Commands = FG.Commands or {}

-- /fgps alert <item> <price>: say when new prices list it at or under that. "off" clears
-- it; with nothing, lists the alerts.
function FG.Commands.Alert(rest)
    local H = FG.PriceHistory
    local id = tonumber((rest or ""):match("item:(%d+)") or (rest or ""):match("^(%d+)%s"))
    if not id then
        local any = false
        for item, a in pairs(FG.db.alerts or {}) do
            any = true
            FG.Print(L["ALERT_LIST_FMT"]:format(FG.Item.Label(item), FG.Fares.Money(a.below)))
        end
        if not any then FG.Print(L["ALERT_NONE"]) end
        return
    end
    local tail = rest:match("|r%s*(.*)$") or rest:match("^%d+%s+(.*)$") or ""
    if tail:lower() == "off" then
        H.SetAlert(id, nil)
        return FG.Print(L["ALERT_OFF_FMT"]:format(FG.Item.Label(id)))
    end
    local below = ParseMoney(tail)
    if not below or below <= 0 then return FG.Print(L["ALERT_HOW"]) end
    H.SetAlert(id, below)
    FG.Print(L["ALERT_SET_FMT"]:format(FG.Item.Label(id), FG.Fares.Money(below)))
end
FG.Commands._ParseMoney = ParseMoney

local function Help()
    FG.Print(L["HELP_HEADER"])
    for _, key in ipairs({ "HELP_TOGGLE", "HELP_GO", "HELP_TARGET", "HELP_QUESTS", "HELP_QUEST", "HELP_TRIP", "HELP_WAY", "HELP_SAVE", "HELP_SHARE", "HELP_RESUME", "HELP_STOP",
                           "HELP_HUD", "HELP_DIAG", "HELP_REPORT", "HELP_ALERT", "HELP_RESET" }) do
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
