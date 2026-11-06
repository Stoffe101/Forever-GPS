-- Quick navigation: a small box in the middle of the screen. Type, press Enter, go.
-- The window stays out of the way; Shift-Enter looks the journey over there instead.
local _, FG = ...
local Quick = {}
FG.Quick = Quick

local Kit, Theme, Format = FG.Kit, FG.Theme, FG.Format
local Planner, Search = FG.Planner, FG.Search
local L = FG.L

local WIDTH, ROW_H, ROWS, HEAD_H = 420, 40, 6, 46
local DEBOUNCE = 0.14

local f
local results = {}
local cursor = 1
local token = 0
local startWhenReady = false

local function Paint()
    for i, row in ipairs(f.rows) do
        row.back:SetShown(i == cursor and row:IsShown())
    end
end

local function Fill()
    local shown = 0
    for i, row in ipairs(f.rows) do
        local result = results[i]
        row:SetShown(result ~= nil)
        if result then
            shown = i
            row.icon:SetIcon(result.iconArt or result.icon or "pin")
            row.name:SetText(result.name)
            row.sub:SetText(result.subtitle or "")
            row.eta:SetText(result.eta and L["ETA_SHORT_FMT"]:format(Format.Duration(result.eta.sec)) or "")
        end
    end
    f:SetHeight(HEAD_H + shown * ROW_H + (shown > 0 and 6 or 0))
    cursor = math.max(1, math.min(cursor, math.max(1, shown)))
    Paint()
end

local function Run()
    local text = strtrim(f.box:GetText())
    Search.CancelPricing()
    if text == "" then
        results = {}
        return Fill()
    end
    local all, info = Search.Run(text, "all")
    results = {}
    for i = 1, math.min(ROWS, #all) do results[i] = all[i] end
    cursor = 1
    Fill()
    Search.Price(results, info, Fill)
end

local function Close()
    f:Hide()
    Search.CancelPricing()
end

-- Goes, or with look on, opens the journey in the window to look it over.
function Quick.Choose(index, look)
    local result = results[index or cursor]
    if not result then return end
    Close()
    if result.quest then
        FG.Window.Show("quests")
        return FG.QuestsView.Focus(result.quest.questID)
    end
    Search.Inspect(result)
    if look then
        FG.Window.ShowRoute()
    else
        startWhenReady = true
    end
end

FG.On("plan:changed", function(plan)
    if not (startWhenReady and plan) then
        if not plan then startWhenReady = false end
        return
    end
    if plan.status == "ready" then
        startWhenReady = false
        Planner.Start()
    elseif plan.status == "failed" or plan.status == "unreachable" then
        startWhenReady = false
        FG.Print(plan.message or L["ROUTE_NO_WAY"])
    end
end)

local function MakeRow(i)
    local row = CreateFrame("Button", nil, f)
    row:SetHeight(ROW_H)
    row:RegisterForClicks("LeftButtonUp")
    row:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -HEAD_H - (i - 1) * ROW_H)
    row:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -HEAD_H - (i - 1) * ROW_H)
    row.back = Kit.Shape(row, 6, "BACKGROUND", 1)
    row.back:SetShown(false)
    Theme.Paint(function(c) row.back:SetColor(c.cardHover) end)
    row.icon = Kit.Icon(row, 22, "glyph")
    row.icon:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.eta = Kit.Text(row, "label", "text")
    row.eta:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.eta:SetJustifyH("RIGHT")
    row.name = Kit.Text(row, "label", "text")
    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 38, -6)
    row.name:SetPoint("TOPRIGHT", row, "TOPRIGHT", -70, -6)
    row.sub = Kit.Text(row, "small", "textDim")
    row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
    row.sub:SetPoint("TOPRIGHT", row.name, "BOTTOMRIGHT", 0, -2)
    row:SetScript("OnClick", function() Quick.Choose(i, IsShiftKeyDown()) end)
    row:SetScript("OnEnter", function()
        cursor = i
        Paint()
    end)
    row:Hide()
    return row
end

local function Build()
    f = CreateFrame("Frame", "ForeverGPSQuick", UIParent)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetPoint("TOP", UIParent, "TOP", 0, -160)
    f:Hide()
    tinsert(UISpecialFrames, "ForeverGPSQuick")
    f.back = Kit.Shape(f, 10, "BACKGROUND", 0)
    f.edge = Kit.Shape(f, 10, "BACKGROUND", 7, true)
    Theme.Paint(function(c)
        f.back:SetColor(c.window)
        f.edge:SetColor(c.lineStrong)
    end)
    f.glyph = Kit.Icon(f, 16, "accent")
    f.glyph:SetIcon("search")
    f.glyph:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -15)
    f.box = CreateFrame("EditBox", "ForeverGPSQuickBox", f)
    f.box:SetAutoFocus(false)
    if not f.box:SetFont(Theme.FONT.regular, 14, "") then f.box:SetFont(STANDARD_TEXT_FONT, 14, "") end
    f.box:SetTextColor(Theme.C.text[1], Theme.C.text[2], Theme.C.text[3], 1)
    f.box:SetPoint("TOPLEFT", f, "TOPLEFT", 40, -10)
    f.box:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -10)
    f.box:SetHeight(26)
    f.box:SetMaxLetters(64)
    f.box:SetAltArrowKeyMode(false)
    f.hint = Kit.Text(f, "body", "textFaint")
    f.hint:SetPoint("LEFT", f.box, "LEFT", 0, 0)
    f.hint:SetPoint("RIGHT", f.box, "RIGHT", 0, 0)
    f.hint:SetText(L["QUICK_HINT"])
    f.rows = {}
    for i = 1, ROWS do f.rows[i] = MakeRow(i) end
    f.box:SetScript("OnTextChanged", function(_, user)
        f.hint:SetShown(f.box:GetText() == "")
        if not user then return end
        token = token + 1
        local mine = token
        FG.After(DEBOUNCE, function()
            if mine == token and f:IsShown() then Run() end
        end)
    end)
    f.box:SetScript("OnEscapePressed", Close)
    f.box:SetScript("OnEnterPressed", function() Quick.Choose(cursor, IsShiftKeyDown()) end)
    f.box:SetScript("OnArrowPressed", function(_, key)
        local n = math.min(ROWS, #results)
        if n == 0 then return end
        if key == "DOWN" then cursor = cursor % n + 1 elseif key == "UP" then cursor = (cursor - 2) % n + 1 end
        Paint()
    end)
end

-- Opens the box, with text already in it when there is some.
function Quick.Open(text)
    if not f then Build() end
    f:SetWidth(math.min(WIDTH, UIParent:GetWidth() - 16))
    FG.Bridge.WarmSearch()
    f.box:SetText(text or "")
    f.hint:SetShown(f.box:GetText() == "")
    results, cursor = {}, 1
    f:Show()
    f.box:SetFocus()
    if text and text ~= "" then Run() else Fill() end
end

function Quick.Toggle()
    if f and f:IsShown() then Close() else Quick.Open() end
end

function Quick._Results() return results end    -- tests
