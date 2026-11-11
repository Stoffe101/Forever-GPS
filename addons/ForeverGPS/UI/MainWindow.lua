-- The window. On a wide screen the list and the journey sit side by side; on a
-- narrow one (a small resolution at a large UI scale) they take turns. It always
-- fits the screen it is on, and it never needs to stay open while traveling.
local FG = ForeverGPS
local Window = {}
FG.Window = Window

local Kit, Theme = FG.Kit, FG.Theme
local Bridge, Planner = FG.Bridge, FG.Planner
local L = FG.L

local PREFERRED_W, PREFERRED_H = 880, 580
local MIN_W, MIN_H = 300, 240
local TWO_COLUMNS_AT = 700       -- wide enough for a list and a journey
local PANEL_SHARE = 0.44         -- of the content, for the journey
local MARGIN = 8                 -- kept clear around the window on screen
local PAD = 12
local HEADER_H = 46

local f
local view = "search"            -- search, quests, professions, trip or settings
local lastView = "search"         -- where Back from the settings returns
local showRoute = false          -- narrow layout: the journey has the screen
local showQuest = false          -- a quest is open in the journey's place
local compact = false

function Window.IsCompact() return compact end

local function Parent() return UIParent end

-- Handheld (a Steam Deck in the hand, docs/CONTROLLER.md): the window fills the screen,
-- a little larger, one column, so text reads and rows are easy to land on.
local HANDHELD_SCALE = 1.12
function Window.Handheld() return FG.Pad ~= nil and FG.Pad.Layout() == "handheld" end

local function Scale()
    return FG.Settings.WindowScale() * (Window.Handheld() and HANDHELD_SCALE or 1)
end

-- The largest the window may be at its own scale.
local function Limits()
    local scale = Scale()
    return (Parent():GetWidth() - MARGIN * 2) / scale, (Parent():GetHeight() - MARGIN * 2) / scale
end

local function Fit()
    local maxW, maxH = Limits()
    local w = math.min(FG.db.window.width or PREFERRED_W, maxW)
    local h = math.min(FG.db.window.height or PREFERRED_H, maxH)
    if Window.Handheld() then w, h = maxW, maxH end
    f:SetSize(math.max(math.min(MIN_W, maxW), w), math.max(math.min(MIN_H, maxH), h))
end

local function Place()
    f:ClearAllPoints()
    if Window.Handheld() then return f:SetPoint("CENTER", UIParent, "CENTER", 0, 0) end
    local p = FG.db.window.point
    if p then
        f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

local function SavePlace()
    local point, _, relPoint, x, y = f:GetPoint(1)
    if point then FG.db.window.point = { point, relPoint, x, y } end
end

-- ==== layout ================================================================

local HINTS_H = 24
local function Layout()
    local width = f:GetWidth()
    compact = width < TWO_COLUMNS_AT or Window.Handheld()
    local contentW = width - PAD * 2
    local panelW = compact and contentW or math.floor(contentW * PANEL_SHARE)
    local left, right, settings = f.left, f.right, f.settingsPage

    local showSettings = view == "settings"
    settings:SetShown(showSettings)
    local listOn = not showSettings and (not compact or not showRoute)
    local routeOn = not showSettings and (not compact or showRoute)
    left:SetShown(listOn)
    right:SetShown(routeOn)
    f.route:SetShown(not showQuest)
    f.detail:SetShown(showQuest)
    f.searchPage:SetShown(view == "search" and listOn)
    f.questsPage:SetShown(view == "quests" and listOn)
    f.tripPage:SetShown(view == "trip" and listOn)
    f.professionsPage:SetShown(view == "professions" and listOn)

    -- The controller's button line at the foot takes its own room.
    local foot = f.hints and f.hints:IsShown() and HINTS_H or PAD
    left:ClearAllPoints()
    left:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -HEADER_H)
    if compact then
        left:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, foot)
    else
        left:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(PAD * 2 + panelW), foot)
    end
    right:ClearAllPoints()
    right:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -HEADER_H)
    right:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, foot)
    settings:ClearAllPoints()
    settings:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -HEADER_H)
    settings:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, foot)
    right:SetWidth(panelW)

    -- The tabs give way to the window's width; the title goes first.
    f.title:SetShown(width >= 460)
    f.tabs.search:ClearAllPoints()
    if f.title:IsShown() then
        f.tabs.search:SetPoint("LEFT", f.title, "RIGHT", 14, 0)
    else
        f.tabs.search:SetPoint("LEFT", f.logo, "RIGHT", 8, 0)
    end
    f.tabs.search:SetSelected(view == "search")
    f.tabs.quests:SetSelected(view == "quests")
    f.tabs.trip:SetSelected(view == "trip")
    f.tabs.professions:SetSelected(view == "professions")
    Window.UpdateStatus()

    if view == "settings" then FG.SettingsView.Layout() end
    if f.searchPage:IsShown() then FG.SearchView.Layout() end
    if f.questsPage:IsShown() then FG.QuestsView.Layout() end
    if f.professionsPage:IsShown() then FG.ProfessionsView.Layout() end
end

local function ShowContent()
    Layout()
    if f.searchPage:IsVisible() then FG.SearchView.Show() end
    if f.questsPage:IsVisible() then FG.QuestsView.Show() end
    if f.tripPage:IsVisible() then FG.TripView.Show() end
    if f.professionsPage:IsVisible() then FG.ProfessionsView.Show() end
    if f.route:IsVisible() then FG.RoutePanel.Render() end
    if f.detail:IsVisible() then FG.QuestDetail.Refresh(true) end
end

-- ==== building ==============================================================

local function Build()
    f = CreateFrame("Frame", "ForeverGPSWindow", UIParent)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:SetResizable(true)
    f:EnableMouse(true)
    f:Hide()
    Bridge.CloseOnEscape(f, function() Window.Hide() end)
    f.back = Kit.Shape(f, 12, "BACKGROUND", 0)
    f.edge = Kit.Shape(f, 12, "BACKGROUND", 7, true)
    Theme.Paint(function(c)
        f.back:SetColor(c.window)
        f.edge:SetColor(c.line)
    end)

    -- The header, which also moves the window.
    f.header = CreateFrame("Frame", nil, f)
    f.header:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    f.header:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    f.header:SetHeight(HEADER_H)
    f.header:EnableMouse(true)
    f.header:RegisterForDrag("LeftButton")
    f.header:SetScript("OnDragStart", function() f:StartMoving() end)
    f.header:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        SavePlace()
    end)
    f.logo = Kit.Icon(f.header, 20, "accent")
    f.logo:SetIcon("logo")
    f.logo:SetPoint("LEFT", f.header, "LEFT", PAD + 2, 0)
    f.title = Kit.Text(f.header, "title", "text")
    f.title:SetText(L["ADDON_NAME"])
    f.title:SetPoint("LEFT", f.logo, "RIGHT", 8, 0)

    f.tabs = {}
    f.tabs.search = Kit.Chip(f.header, L["TAB_SEARCH"], function() Window.Show("search") end)
    f.tabs.quests = Kit.Chip(f.header, L["QUESTS_TITLE"], function() Window.Show("quests") end)
    f.tabs.quests:SetPoint("LEFT", f.tabs.search, "RIGHT", 6, 0)
    f.tabs.professions = Kit.Chip(f.header, L["PV_TAB"], function() Window.Show("professions") end)
    f.tabs.professions:SetPoint("LEFT", f.tabs.quests, "RIGHT", 6, 0)
    f.tabs.trip = Kit.Chip(f.header, L["TRIP_TITLE"], function() Window.Show("trip") end)
    f.tabs.trip:SetPoint("LEFT", f.tabs.professions, "RIGHT", 6, 0)

    f.close = Kit.IconButton(f.header, "close", 12, nil, function() Window.Hide() end)
    f.close:SetPoint("RIGHT", f.header, "RIGHT", -8, 0)
    f.gear = Kit.IconButton(f.header, "gear", 14, L["SETTINGS_TITLE"], function()
        Window.Show(view == "settings" and "search" or "settings")
    end)
    f.gear:SetPoint("RIGHT", f.close, "LEFT", -2, 0)
    f.status = Kit.Text(f.header, "small", "route")
    f.status:SetPoint("RIGHT", f.gear, "LEFT", -8, 0)
    f.status:SetJustifyH("RIGHT")

    f.left = CreateFrame("Frame", nil, f)
    f.right = CreateFrame("Frame", nil, f)
    f.searchPage = FG.SearchView.Get(f.left)
    f.searchPage:SetAllPoints(f.left)
    f.questsPage = FG.QuestsView.Get(f.left)
    f.questsPage:SetAllPoints(f.left)
    f.tripPage = FG.TripView.Get(f.left)
    f.tripPage:SetAllPoints(f.left)
    f.professionsPage = FG.ProfessionsView.Get(f.left)
    f.professionsPage:SetAllPoints(f.left)
    f.route = FG.RoutePanel.Get(f.right)
    f.route:SetAllPoints(f.right)
    f.detail = FG.QuestDetail.Get(f.right)
    f.detail:SetAllPoints(f.right)
    f.detail:Hide()
    f.settingsPage = FG.SettingsView.Get(f)
    f.settingsPage:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -HEADER_H)
    f.settingsPage:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD)
    f.settingsPage:Hide()

    -- The corner that resizes it.
    f.grip = CreateFrame("Button", nil, f)
    f.grip.padSkip = true      -- a mouse handle: the controller passes it by
    f.grip:SetSize(16, 16)
    f.grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    f.grip.glyph = Kit.Icon(f.grip, 9, "textFaint")
    f.grip.glyph:SetIcon("chevron-down")
    f.grip.glyph:SetPoint("BOTTOMRIGHT", f.grip, "BOTTOMRIGHT", -2, 2)
    f.grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    f.grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        FG.db.window.width, FG.db.window.height = f:GetWidth(), f:GetHeight()
        SavePlace()
        Fit()
        ShowContent()
    end)

    f:SetScript("OnSizeChanged", function()
        if f:IsShown() then Layout() end
    end)
    f:HookScript("OnShow", function() FG.Emit("window:shown") end)
    f:HookScript("OnHide", function() FG.Emit("window:hidden") end)
    f.hints = Kit.Text(f, "small", "textDim")
    f.hints:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, 4)
    f.hints:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -24, 4)
    f.hints:Hide()
    Window.ApplyScale()
    Fit()
    Place()
end

-- ==== doors =================================================================

function Window.ApplyScale()
    if not f then return end
    f:SetScale(Scale())
    Place()
    local maxW, maxH = Limits()
    f:SetResizeBounds(math.min(MIN_W, maxW), math.min(MIN_H, maxH), maxW, maxH)
    Fit()
    if f:IsShown() then ShowContent() end
end

function Window.Show(page)
    if not f then Build() end
    if page and page ~= view and view ~= "settings" then lastView = view end
    view = page or view
    -- Reopened mid-journey on a narrow window, the journey is what was wanted.
    showRoute = page == nil and Bridge.ActiveRoute() ~= nil
    Fit()
    f:Show()
    ShowContent()
end

function Window.Hide()
    if f then f:Hide() end
end

function Window.Toggle()
    if f and f:IsShown() then Window.Hide() else Window.Show() end
end

function Window.IsShown() return f ~= nil and f:IsShown() end

-- Narrow layout: the journey takes the screen, Back returns to the list.
function Window.ShowRoute()
    if not f then Build() end
    if not f:IsShown() then
        f:Show()
    end
    if view == "settings" then view = "search" end
    showRoute, showQuest = true, false
    Layout()
    FG.RoutePanel.Render()
end

function Window.ShowList()
    showRoute = false
    Planner.Clear()
    ShowContent()
end

-- A quest beside the list, or over it on a narrow window.
function Window.ShowQuest(id)
    if not f then Build() end
    if not f:IsShown() then f:Show() end
    if view == "settings" then view = "quests" end
    showRoute, showQuest = true, true
    Layout()
    FG.QuestDetail.Show(id)
end

-- Back to the list and to the journey, whichever the panel held before.
function Window.CloseQuest()
    showRoute, showQuest = false, false
    ShowContent()
end

function Window.IsShowingQuest() return showQuest end

FG.On("plan:changed", function(plan)
    -- Done with a route looked at from a quest: the quest again.
    if not plan and f and f:IsShown() and FG.QuestDetail.Current() and view == "quests" and FG.QuestsView.Mode() == "find"
        and not Bridge.ActiveRoute() then
        showRoute, showQuest = true, true
        Layout()
        FG.QuestDetail.Refresh(true)
    end
end)

function Window.Frame() return f end
function Window.View() return view end

-- ==== the controller ========================================================

local ORDER = { "search", "quests", "professions", "trip", "settings" }

-- Back: one step out (a quest, the journey on a narrow window, the settings); false
-- when there is nothing to go back from, and the window closes.
function Window.Back()
    if not (f and f:IsShown()) then return false end
    if showQuest then
        Window.CloseQuest()
        return true
    end
    if compact and showRoute then
        Window.ShowList()
        return true
    end
    if view == "settings" then
        Window.Show(lastView ~= "settings" and lastView or "search")
        return true
    end
    return false
end

-- Where the controller starts on each page: a frame, or (nil, the part of the window to
-- start in), so it starts on the page and not on the tabs above it.
function Window.FirstFocus()
    if not f then return nil end
    if view == "search" and FG.SearchView.FirstFocus and not (compact and showRoute) then return FG.SearchView.FirstFocus() end
    if view == "settings" then
        local chip = FG.SettingsView.FirstFocus and FG.SettingsView.FirstFocus()
        if chip then return chip end
        return nil, f.settingsPage
    end
    if showRoute and f.right:IsShown() and (compact or not f.left:IsShown()) then return nil, f.right end
    return nil, f.left
end

local function Cycle(dir)
    local i = 1
    for k, key in ipairs(ORDER) do if key == view then i = k end end
    Window.Show(ORDER[(i - 1 + dir) % #ORDER + 1])
end

local SUB = {
    professions = function(dir) return FG.ProfessionsView.Cycle and FG.ProfessionsView.Cycle(dir) end,
    settings = function(dir) return FG.SettingsView.Cycle and FG.SettingsView.Cycle(dir) end,
    quests = function(dir) return FG.QuestsView.Cycle and FG.QuestsView.Cycle(dir) end,
    search = function(dir) return FG.SearchView.Cycle and FG.SearchView.Cycle(dir) end,
}

-- The window's own pad actions; true when one was done.
function Window.PadAction(id)
    if id == "prevTab" or id == "nextTab" then
        Cycle(id == "nextTab" and 1 or -1)
    elseif id == "prevSub" or id == "nextSub" then
        local fn = SUB[view]
        if fn then fn(id == "nextSub" and 1 or -1) end
    elseif id == "search" then
        -- The page's own search: the Quest Explorer's on it, else the main one.
        local box
        if view == "quests" and FG.QuestsView.Mode() == "find" then
            box = FG.ExplorerView.Box()
        else
            Window.Show("search")
            box = FG.SearchView.Box and FG.SearchView.Box()
        end
        if box and FG.PadKeyboard then FG.PadKeyboard.Open(box) end
    elseif id == "home" then
        Window.Show("search")
    elseif id == "startNav" then
        local plan = Planner.Current()
        if plan and plan.selected then Planner.Start() end
    elseif id == "stopNav" then
        Bridge.Stop()
    elseif id == "showRoute" then
        if Bridge.ActiveRoute() or Planner.Current() then Window.ShowRoute() end
    elseif id == "openMap" then
        if not FG.MapPreview.Open() then FG.MapPreview.OpenActive() end
    elseif id == "save" then
        local plan = Planner.Current()
        if plan and plan.target then FG.Saved.ToggleFavorite(plan.target) end
    elseif id == "replan" then
        Planner.Replan()
    elseif id == "help" then
        Window.Show("settings")
        if FG.SettingsView.SelectByLabel then FG.SettingsView.SelectByLabel("SETG_CONTROLLER") end
    else
        return false
    end
    return true
end

local HINTS = { { "confirm", "PAD_HINT_confirm" }, { "back", "PAD_HINT_back" }, { "search", "PAD_HINT_search" },
                { "prevTab", "PAD_HINT_prevTab" }, { "context", "PAD_HINT_context" } }

-- A line at the foot of the window with the buttons that matter here, while the pad is
-- the input in use.
function Window.UpdateHints()
    if not f then return end
    local Pad = FG.Pad
    local on = (Pad and Pad.InUse() and Pad.Capturing()) and true or false
    local changed = f.hints:IsShown() ~= on
    f.hints:SetShown(on)
    if changed and f:IsShown() then Layout() end
    if not on then return end
    local parts = {}
    for _, hint in ipairs(HINTS) do
        local chord = Pad.Binding(hint[1])
        if chord then parts[#parts + 1] = Pad.Label(chord) .. " " .. L[hint[2]] end
    end
    -- Read at arm's length on a handheld: a size up there.
    Kit.SetStyle(f.hints, Window.Handheld() and "body" or "small", 0, "")
    f.hints:SetText(table.concat(parts, "   \194\183   "))
end
FG.On("pad:capture", Window.UpdateHints)
FG.On("pad:input", function()
    Window.UpdateHints()
    if f and f:IsShown() then Window.ApplyScale() end
end)
FG.On("pad:bindings", Window.UpdateHints)
FG.On("pad:layout", function() if f then Window.ApplyScale() end end)

-- A line in the header for the journey under way, where there is room for it.
function Window.UpdateStatus()
    if not (f and f:IsShown()) then return end
    local route = Bridge.ActiveRoute()
    local count = FG.Trip.Count()
    f.tabs.trip:SetLabel(count > 0 and L["TRIP_COUNT_FMT"]:format(count) or L["TRIP_TITLE"])
    local text
    if route and f:GetWidth() >= 620 then
        local left = FG.Format.Duration(route.eta or route.total)
        text = left and L["STATUS_NAVIGATING_FMT"]:format(left) or L["ROUTE_ACTIVE"]
    end
    f.status:SetShown(text ~= nil)
    if text and f.status:GetText() ~= text then f.status:SetText(text) end
end

FG.On("journey:view", Window.UpdateStatus)
FG.On("route:cleared", Window.UpdateStatus)
FG.On("trip:changed", Window.UpdateStatus)

FG.On("places:reset", function()
    if not f then return end
    Fit()
    Place()
end)

local function ScreenChanged()
    if f then Window.ApplyScale() end
end
FG.OnEvent("UI_SCALE_CHANGED", ScreenChanged)
FG.OnEvent("DISPLAY_SIZE_CHANGED", ScreenChanged)

FG.On("login", function()
    if not Bridge.Ready() then
        FG.Print(L["NOT_READY"])
    end
end)
