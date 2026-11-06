-- A button on the minimap's edge: left click opens the window, right click the quick
-- box. Dragged around the rim; gone entirely when the setting says so.
local _, FG = ...
local Button = {}
FG.MinimapButton = Button

local Kit, Theme = FG.Kit, FG.Theme
local L = FG.L

local SIZE, RIM = 30, 6      -- how far outside the minimap's edge it sits
local Atan2 = math.atan2 or math.atan

local b

local function Place()
    local angle = math.rad(FG.db.minimap.angle or 215)
    local r = Minimap:GetWidth() / 2 + RIM
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

local function FollowCursor()
    local x, y = Minimap:GetCenter()
    if not x then return end
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    FG.db.minimap.angle = math.deg(Atan2(cy / scale - y, cx / scale - x)) % 360
    Place()
end

local function Build()
    b = CreateFrame("Button", "ForeverGPSMinimapButton", Minimap)
    b:SetSize(SIZE, SIZE)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b.back = Kit.Shape(b, SIZE / 2, "BACKGROUND", 1)
    Theme.Paint(function(c) b.back:SetColor(c.window) end)
    b.icon = Kit.Icon(b, 18, "accent")
    b.icon:SetIcon("logo")
    b.icon:SetPoint("CENTER", b, "CENTER", 0, 0)
    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then FG.Quick.Toggle() else FG.Window.Toggle() end
    end)
    b:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", FollowCursor) end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    Kit.Tooltip(b, L["ADDON_NAME"], L["MINIMAP_TT"])
    Place()
end

function Button.Sync()
    local on = FG.db.minimap.shown and Minimap ~= nil
    if on and not b then Build() end
    if b then b:SetShown(on and true or false) end
end

FG.On("login", Button.Sync)
FG.On("settings:changed", Button.Sync)
