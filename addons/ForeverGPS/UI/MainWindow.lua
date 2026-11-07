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
local view = "search"            -- search, quests, trip or settings
local showRoute = false          -- narrow layout: the journey has the screen
local showQuest = false          -- a quest is open in the journey's place
local compact = false

function Window.IsCompact() return compact end

local function Parent() return UIParent end

-- The largest the window may be at its own scale.
local function Limits()
    local scale = FG.Settings.WindowScale()
    return (Parent():GetWidth() - MARGIN * 2) / scale, (Parent():GetHeight() - MARGIN * 2) / scale
end

local function Fit()
    local maxW, maxH = Limits()
    local w = math.min(FG.db.window.width or PREFERRED_W, maxW)
    local h = math.min(FG.db.window.height or PREFERRED_H, maxH)
    f:SetSize(math.max(math.min(MIN_W, maxW), w), math.max(math.min(MIN_H, maxH), h))
end

local function Place()
    f:ClearAllPoints()
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

local function Layout()
    local width = f:GetWidth()
    compact = width < TWO_COLUMNS_AT
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

    left:ClearAllPoints()
    left:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -HEADER_H)
    if compact then
        left:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD)
    else
        left:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(PAD * 2 + panelW), PAD)
    end
    right:ClearAllPoints()
    right:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -HEADER_H)
    right:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD)
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
    Window.UpdateStatus()

    if view == "settings" then FG.SettingsView.Layout() end
    if f.searchPage:IsShown() then FG.SearchView.Layout() end
    if f.questsPage:IsShown() then FG.QuestsView.Layout() end
end

local function ShowContent()
    Layout()
    if f.searchPage:IsVisible() then FG.SearchView.Show() end
    if f.questsPage:IsVisible() then FG.QuestsView.Show() end
    if f.tripPage:IsVisible() then FG.TripView.Show() end
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
    f.tabs.trip = Kit.Chip(f.header, L["TRIP_TITLE"], function() Window.Show("trip") end)
    f.tabs.trip:SetPoint("LEFT", f.tabs.quests, "RIGHT", 6, 0)

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
    Window.ApplyScale()
    Fit()
    Place()
end

-- ==== doors =================================================================

function Window.ApplyScale()
    if not f then return end
    f:SetScale(FG.Settings.WindowScale())
    local maxW, maxH = Limits()
    f:SetResizeBounds(math.min(MIN_W, maxW), math.min(MIN_H, maxH), maxW, maxH)
    Fit()
    if f:IsShown() then ShowContent() end
end

function Window.Show(page)
    if not f then Build() end
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
