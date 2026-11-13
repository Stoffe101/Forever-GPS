-- WoW Forever's own Gamepad UI (Options, Gamepad, "Enable Gamepad UI"). Under it, whatever
-- addon code does that runs the Gamepad UI's bookkeeping in its own execution taints it,
-- and Blizzard's restricted SetPreferredGamepadInteractTarget() is then blocked again and
-- again, blamed on the addon: the errors players report. tests/support/gamepadui.lua
-- records each such act while the Gamepad UI is on. With it on, Forever-GPS and the
-- EasyFind parts it carries must do none; with it off, everything works as before.
local T = require("support.t")
local Stack = require("support.stack")

local tests = {}

local AUBERDINE = { name = "Auberdine", mapID = 1439, x = 0.37, y = 0.44 }
local QUESTIE = {
    areaMaps = { [12] = 1429 },
    npcs = { [240] = { name = "Marshal Dughan", spawns = { [12] = { { 42.1, 65.9 } } } },
             [299] = { name = "Young Wolf", spawns = { [12] = { { 43, 72 }, { 44, 73 } } } } },
    quests = { [33] = { name = "Wolves Across the Border", objectives = { { id = 299, text = "Young Wolf" } }, finisher = 240 } },
}
local LOG = {
    { questID = 33, title = "Wolves Across the Border", level = 6, header = "Elwynn Forest", poi = { mapID = 1429, x = 0.43, y = 0.72 },
      objectives = { { text = "Young Wolf slain: 3/8", numFulfilled = 3, numRequired = 8, finished = false } } },
}

local function Start(gamepadUI)
    local c = Stack.new({ mapID = 1453, x = 0.6, y = 0.6, questie = QUESTIE, quests = LOG })
    c:Advance(0.5)
    c.FG.Pad.DB().introDone = true
    c:SetGamepadUI(gamepadUI)
    c.gamepadTaint = {}
    return c, c.FG
end

local function Plan(c, dest)
    local P = c.FG.Planner
    P.Inspect({ data = dest, name = dest.name })
    T.ok(Stack.Until(c, function()
        local p = P.Current()
        return p and (p.status == "ready" or p.status == "failed" or p.status == "unreachable")
    end, 30), "the plan finishes")
    c:Advance(0.3)
end

local function Clean(c, what)
    local seen = {}
    for _, t in ipairs(c.gamepadTaint) do seen[#seen + 1] = t.what .. " (" .. tostring(t.detail) .. ")" end
    T.eq(#seen, 0, what .. ": nothing that taints the Gamepad UI: " .. table.concat(seen, "; "))
end

local function UnderGameMap(c, frame)
    local map, p = c.env.WorldMapFrame, frame
    while p do
        if p == map then return true end
        p = p:GetParent()
    end
    return false
end

-- ==== the game's world map ===================================================

function tests.theGameMap_getsNothingOfOurs()
    local c, FG = Start(true)
    Plan(c, AUBERDINE)
    c:PlayerToggleMap()
    c:Advance(1)
    local overlay = c.env.ForeverGPSMapPreview
    T.ok(not (overlay and overlay:IsVisible() and UnderGameMap(c, overlay)), "our preview is not drawn on the game's map")
    local gps = c.env.EasyFindGPSPreview
    T.ok(not (gps and gps:IsVisible() and UnderGameMap(c, gps)), "nor EasyFind GPS's route")
    -- The journey still shows on our own map.
    T.ok(FG.MapPreview.Open(), "our own map shows it")
    c:Advance(0.3)
    T.ok(FG.MapPreview._Lines() and FG.MapPreview._Lines().n > 0, "with its line")
    c:PlayerToggleMap()
    c:Advance(0.3)
    Clean(c, "the map opened and closed with a journey planned")
    T.eq(#c.errors, 0, tostring(c.errors[1]))
end

function tests.withoutTheGamepadUI_theGameMapShowsTheJourneyAsBefore()
    local c = Start(false)
    c.env.WorldMapFrame:Show()
    Plan(c, AUBERDINE)
    c:Advance(0.3)
    local overlay = c.env.ForeverGPSMapPreview
    T.ok(overlay and overlay:IsVisible() and UnderGameMap(c, overlay), "drawn on the game's map, as in 2.5 and 2.6")
end

function tests.turningTheGamepadUIOn_midSession_takesEffect()
    local c, FG = Start(false)
    c.env.WorldMapFrame:Show()
    Plan(c, AUBERDINE)
    c:Advance(0.3)
    c.env.WorldMapFrame:Hide()
    c:SetGamepadUI(true)
    c.gamepadTaint = {}
    c:PlayerToggleMap()
    c:Advance(1)
    local overlay = c.env.ForeverGPSMapPreview
    T.ok(not (overlay:IsVisible() and UnderGameMap(c, overlay)), "the next opening of the map is left alone")
    Clean(c, "after the switch")
    local journal = table.concat(FG.Pad.Journal(), "\n")
    T.ok(journal:find("interface", 1, true), "the switch is in the controller report")
end

-- ==== the game's menus =======================================================

function tests.theGamesMenus_getNoEntriesOfOurs()
    local c = Start(true)
    for _, name in ipairs({ "MENU_QUEST_MAP_LOG_TITLE", "MENU_QUEST_OBJECTIVE_TRACKER", "MENU_UNIT_TARGET", "MENU_UNIT_PLAYER",
                            "MENU_UNIT_PARTY", "MENU_WATCH_FRAME_LINK" }) do
        local items = c:PlayerOpensGameMenu(name, { questID = 33 }, { unit = "target" })
        T.eq(#items, 0, name .. ": opens as the game's own")
    end
    Clean(c, "the game's menus")
end

function tests.withoutTheGamepadUI_theQuestMenuStillOffersDirections()
    local c = Start(false)
    local items = c:PlayerOpensGameMenu("MENU_QUEST_MAP_LOG_TITLE", { questID = 33 })
    local labels = {}
    for _, item in ipairs(items) do labels[#labels + 1] = tostring(item.label) end
    T.ok(#items > 0, "Directions in the quest's menu, as before: " .. table.concat(labels, ", "))
end

-- ==== Forever-GPS itself, with the controller ===============================

function tests.everyPage_withTheController_underTheGamepadUI()
    local c, FG = Start(true)
    FG.Bridge.WarmSearch()
    c:Advance(1)
    c:PadPress("PADDDOWN")
    FG.Window.Show("search")
    c:Advance(0.3)
    FG.SearchView.Query("auberdine")
    c:Advance(1)
    FG.Focus.To(FG.SearchView.FirstFocus())
    c:PadPress("PAD1")
    T.ok(Stack.Until(c, function() local p = FG.Planner.Current() return p and p.status == "ready" end, 30), "planned with A")
    c:Advance(0.3)
    c:PadPress("PADRSTICK")          -- our map
    c:Advance(0.3)
    T.ok(FG.RouteMap.Shown(), "our map opens")
    c:PadPress("PADRSHOULDER")
    c:PadPress("PAD3")
    c:PadPress("PAD2")
    for _ = 1, 4 do
        c:PadPress("PADRSHOULDER")
        c:Advance(0.3)
        for _, b in ipairs({ "PADDDOWN", "PADDDOWN", "PADDRIGHT", "PADDUP", "PAD3" }) do
            c:PadPress(b)
            c:Advance(0.05)
        end
        c:PadPress("PAD2")
    end
    FG.Window.Show("quests")
    FG.QuestsView.SetMode("find")
    T.ok(Stack.Until(c, FG.QuestIndex.Ready, 10), "the quest index builds")
    FG.ExplorerView.Open(33)
    c:Advance(1)
    FG.QuestDetail.ShowOnMap()
    c:Advance(0.5)
    FG.RouteMap.Hide()
    FG.Window.Show("settings")
    FG.SettingsView.SelectByLabel("SETG_CONTROLLER")
    c:Advance(0.2)
    T.ok(FG.Pad.ReportLines()[1]:find("Gamepad UI ON", 1, true), "the report says the Gamepad UI is on")
    FG.Window.Hide()
    c:Advance(0.3)
    Clean(c, "a whole session of Forever-GPS by controller")
    T.eq(#c.blocked, 0, "nothing protected tried in combat")
    T.eq(#c.errors, 0, tostring(c.errors[1]))
end

function tests.theOldFoldersNotice_isNotAPopup_underTheGamepadUI()
    local c, FG = Start(true)
    c.printed = {}
    local save = c.env.ForeverGPSPreflight.old
    c.env.ForeverGPSPreflight.old = { "EasyFind" }
    FG.Emit("login")
    c.env.ForeverGPSPreflight.old = save
    Clean(c, "the old-folders notice")
    local said = table.concat(c.printed, "\n")
    T.ok(said:find("old EasyFind", 1, true), "said in the chat instead")
end

-- ==== the report =============================================================

function tests.theControllerReport_saysWhatABlockedActionWas()
    local c, FG = Start(true)
    c:Fire("ADDON_ACTION_FORBIDDEN", "SomeBagAddon", "SetPreferredGamepadInteractTarget()")
    c:Fire("ADDON_ACTION_BLOCKED", "ForeverGPS", "SetPreferredGamepadInteractTarget()")
    local report = FG.Pad.Report()
    T.ok(report:find("this session: 2, 1 of them Forever-GPS's", 1, true), "counted, ours apart")
    T.ok(report:find("SomeBagAddon SetPreferredGamepadInteractTarget", 1, true), "and named, with the function")
    T.ok(report:find("Gamepad UI ON", 1, true), "the Gamepad UI state")
    T.no(report:find("Tester", 1, true), "no character name")
    T.ok(FG.Diagnostics.Report():find("Gamepad UI", 1, true), "in /fgps report too")
end

return tests
