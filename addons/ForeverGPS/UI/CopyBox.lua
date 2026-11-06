-- A box of text to copy: the game cannot reach the clipboard itself, so the text is
-- selected and the player presses Ctrl-C.
local _, FG = ...
local CopyBox = {}
FG.CopyBox = CopyBox

local Kit, Theme = FG.Kit, FG.Theme
local L = FG.L

local WIDTH, HEIGHT, MARGIN = 620, 420, 8
local WHEEL = 40

local f
local offset = 0

local function Scroll()
    local most = math.max(0, f.box:GetHeight() - f.clip:GetHeight())
    offset = math.max(0, math.min(most, offset))
    f.box:ClearAllPoints()
    f.box:SetPoint("TOPLEFT", f.clip, "TOPLEFT", 0, offset)
    f.box:SetPoint("TOPRIGHT", f.clip, "TOPRIGHT", 0, offset)
end

local function Build()
    f = CreateFrame("Frame", "ForeverGPSCopyBox", UIParent)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:Hide()
    tinsert(UISpecialFrames, "ForeverGPSCopyBox")
    f.back = Kit.Shape(f, 10, "BACKGROUND", 0)
    f.edge = Kit.Shape(f, 10, "BACKGROUND", 7, true)
    Theme.Paint(function(c)
        f.back:SetColor(c.window)
        f.edge:SetColor(c.lineStrong)
    end)
    f.title = Kit.Text(f, "label", "text")
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -12)
    f.title:SetPoint("TOPRIGHT", f, "TOPRIGHT", -34, -12)
    f.title:SetText(L["COPY_TITLE"])
    f.close = Kit.IconButton(f, "close", 10, nil, function() f:Hide() end)
    f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
    f.clip = CreateFrame("Frame", nil, f)
    f.clip:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -36)
    f.clip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 14)
    f.clip:SetClipsChildren(true)
    f.clip:EnableMouseWheel(true)
    f.clip:SetScript("OnMouseWheel", function(_, delta)
        offset = offset - delta * WHEEL
        Scroll()
    end)
    f.box = CreateFrame("EditBox", "ForeverGPSCopyEdit", f.clip)
    f.box:SetMultiLine(true)
    f.box:SetAutoFocus(false)
    if not f.box:SetFont(Theme.FONT.regular, 11, "") then f.box:SetFont(STANDARD_TEXT_FONT, 11, "") end
    f.box:SetTextColor(Theme.C.text[1], Theme.C.text[2], Theme.C.text[3], 1)
    f.box:SetScript("OnEscapePressed", function() f:Hide() end)
    -- Read only: whatever was typed goes back to what is being copied.
    f.box:SetScript("OnTextChanged", function(self, user)
        if user then
            self:SetText(f.text)
            self:HighlightText()
        end
    end)
end

function CopyBox.Show(text)
    if not f then Build() end
    f:SetSize(math.min(WIDTH, UIParent:GetWidth() - MARGIN * 2), math.min(HEIGHT, UIParent:GetHeight() - MARGIN * 2))
    f.text, offset = text, 0
    f.box:SetText(text)
    local width = f:GetWidth() - 28
    f.box:SetHeight(math.max(f.clip:GetHeight(), FG.RoutePanel.TextHeight(text, width, "small") + 24))
    Scroll()
    f:Show()
    f.box:SetFocus()
    f.box:HighlightText()
end
