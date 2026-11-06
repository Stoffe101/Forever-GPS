-- The navigation HUD: what to do now, how far, how long, and what comes next. On
-- a ride it stops pointing and says which ride it is. The arrow's aim is EasyFind
-- GPS's own, so it follows the walk around bends rather than straight at the end.
local _, FG = ...
local HUD = {}
FG.HUD = HUD

local Kit, Theme, Format = FG.Kit, FG.Theme, FG.Format
local Bridge, Journey = FG.Bridge, FG.Journey
local L = FG.L

local WIDTH, HOME_Y = 330, -96
local MARGIN = 8
local ARROW_EVERY = 0.03
local TOAST_SECONDS = 6
local PI = math.pi

local f, view
local since = 0

local function Enabled() return FG.db and FG.db.hud.enabled end

function HUD.Guiding()
    return f ~= nil and f:IsVisible() and f.arrow:IsShown()
end

local function SavePlace()
    local point, _, relPoint, x, y = f:GetPoint(1)
    if point then FG.db.hud.point = { point, relPoint, x, y } end
end

local function Place()
    f:ClearAllPoints()
    local p = FG.db.hud.point
    if p then
        f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        f:SetPoint("TOP", UIParent, "TOP", 0, HOME_Y)
    end
end

local function ApplyLock()
    local locked = FG.db.hud.locked
    f.grip:SetShown(not locked)
    f:SetMovable(not locked)
end

-- Never wider than the screen, at any UI scale.
local function ApplyScale()
    local scale = FG.db.hud.scale or 1
    f:SetScale(scale)
    f:SetWidth(math.min(WIDTH, (UIParent:GetWidth() - MARGIN * 2) / scale))
end

local function ShowMenu()
    Kit.Menu(f, {
        { label = L["HUD_OPEN"], onClick = function() FG.Window.Show() end },
        { label = L["HUD_STOP"], onClick = function() Bridge.Stop() end },
        { label = L[FG.db.hud.locked and "HUD_UNLOCK" or "HUD_LOCK"], onClick = function()
            FG.db.hud.locked = not FG.db.hud.locked
            ApplyLock()
        end },
        { label = L["HUD_RESET"], onClick = function()
            FG.db.hud.point = nil
            Place()
        end },
    })
end

-- A teleport step: the spell or hearthstone, one click away. A secure button is
-- only ever touched out of combat, and it hangs from UIParent: a frame a secure
-- one is anchored to turns protected, and the HUD must stay free to hide and move
-- in a fight. So its anchor goes the moment combat starts.
local function MakeCastButton()
    local b = CreateFrame("Button", "ForeverGPSCastButton", UIParent, "SecureActionButtonTemplate")
    b:SetSize(36, 36)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(f:GetFrameLevel() + 5)
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("useOnKeyDown", false)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints(b)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:Hide()
    return b
end

local function SetCast(step)
    if InCombatLockdown() then return end
    if not f.cast then f.cast = MakeCastButton() end
    local b = f.cast
    local spell, item = step and step.spellID, step and step.itemID
    if not (step and step.kind == "teleport" and (spell or item)) then
        b:Hide()
        b:ClearAllPoints()
        return
    end
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -10)
    if item then
        b:SetAttribute("type", "item")
        b:SetAttribute("item", "item:" .. item)
        b.icon:SetTexture(C_Item.GetItemIconByID and C_Item.GetItemIconByID(item) or 134414)
    else
        b:SetAttribute("type", "spell")
        b:SetAttribute("spell", spell)
        b.icon:SetTexture(C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spell) or 134414)
    end
    b:Show()
end

local function Build()
    f = CreateFrame("Button", "ForeverGPSHUD", UIParent)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:RegisterForClicks("RightButtonUp")
    f:SetHeight(76)
    f:Hide()
    f.back = Kit.Shape(f, 10, "BACKGROUND", 1)
    f.edge = Kit.Shape(f, 10, "BACKGROUND", 2, true)
    Theme.Paint(function(c)
        f.back:SetColor(c.hud)
        f.edge:SetColor(c.line)
    end)
    f.arrow = Kit.Icon(f, 34, "route")
    f.arrow:SetIcon("nav-arrow")
    f.arrow:SetPoint("TOPLEFT", f, "TOPLEFT", 11, -11)
    f.glyph = Kit.Icon(f, 28, "route")
    f.glyph:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -14)
    f.title = Kit.Text(f, "heading", "text", 2)
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 56, -9)
    f.title:SetPoint("TOPRIGHT", f, "TOPRIGHT", -24, -9)
    f.meta = Kit.Text(f, "small", "textDim")
    f.meta:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -3)
    f.meta:SetPoint("TOPRIGHT", f.title, "BOTTOMRIGHT", 0, -3)
    f.nextLine = Kit.Text(f, "small", "textFaint")
    f.nextLine:SetPoint("TOPLEFT", f.meta, "BOTTOMLEFT", 0, -2)
    f.nextLine:SetPoint("TOPRIGHT", f.meta, "BOTTOMRIGHT", 0, -2)
    f.bar = Kit.Bar(f, 3, "route")
    f.bar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 7)
    f.bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 7)
    f.close = Kit.IconButton(f, "close", 9, L["HUD_STOP"], function() Bridge.Stop() end)
    f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -3)

    f.toast = CreateFrame("Frame", nil, f)
    f.toast:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -4)
    f.toast:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -4)
    f.toast:SetHeight(26)
    f.toast.back = Kit.Shape(f.toast, 7, "BACKGROUND", 1)
    Theme.Paint(function(c) f.toast.back:SetColor(c.hud) end)
    f.toast.text = Kit.Text(f.toast, "small", "text")
    f.toast.text:SetPoint("LEFT", f.toast, "LEFT", 10, 0)
    f.toast.text:SetPoint("RIGHT", f.toast, "RIGHT", -10, 0)
    f.toast:Hide()

    -- Dragged only when unlocked; a strip says so.
    f.grip = CreateFrame("Frame", nil, f)
    f.grip:SetAllPoints(f)
    f.grip:SetFrameLevel(f:GetFrameLevel() + 10)
    f.grip:EnableMouse(true)
    f.grip:RegisterForDrag("LeftButton")
    f.grip.fill = Kit.Shape(f.grip, 10, "OVERLAY", 1)
    Theme.Paint(function(c) f.grip.fill:SetColor(c.routeSoft) end)
    f.grip:SetScript("OnDragStart", function() f:StartMoving() end)
    f.grip:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        SavePlace()
    end)
    f.grip:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then ShowMenu() end
    end)

    f:SetScript("OnClick", function(_, button)
        if button == "RightButton" then ShowMenu() end
    end)
    f:SetScript("OnUpdate", function(_, elapsed) HUD.Spin(elapsed) end)

    ApplyScale()
    ApplyLock()
    Place()
end

-- Stops pointing and shows the step's own icon.
local function ShowGlyph(icon)
    f.arrow:Hide()
    f.glyph:SetIcon(icon)
    f.glyph:Show()
end

-- Turns the arrow; it only ever spins while it is on screen.
function HUD.Spin(elapsed)
    since = since + elapsed
    if since < ARROW_EVERY then return end
    since = 0
    if not (view and view.pointing and view.state == "moving" and Journey.ArrowMode() == "hud") then return end
    local heading = Journey.Heading()
    if heading then
        f.glyph:Hide()
        f.arrow:Show()
        f.arrow:SetRotation(heading)
    else
        ShowGlyph(view.icon)
    end
end

local function Meta(v)
    local parts = {}
    if v.yards then parts[#parts + 1] = Format.Yards(v.yards) end
    if v.state == "riding" and v.stepEta then parts[#parts + 1] = Format.Clock(v.stepEta) end
    if v.eta then parts[#parts + 1] = L["HUD_LEFT_FMT"]:format(Format.Duration(v.eta)) end
    if v.index and v.count then parts[#parts + 1] = L["HUD_STEP_FMT"]:format(v.index, v.count) end
    return table.concat(parts, " · ")
end

local function FitHeight()
    local h = 9 + f.title:GetStringHeight() + 3 + 13
    if f.nextLine:IsShown() then h = h + 15 end
    f:SetHeight(math.max(62, h + 16))
end

function HUD.Render(v)
    view = v
    if not (Enabled() and v) or (FG.db.hud.hideInCombat and InCombatLockdown()) then
        if f then
            SetCast(nil)
            f:Hide()
        end
        return
    end
    if not f then Build() end
    f.title:SetText(v.title)
    f.title:SetColorKey(v.hostile and "danger" or "text")
    f.meta:SetText(Meta(v))
    local showNext = v.nextText and FG.db.hud.showNext and v.state ~= "arrived"
    f.nextLine:SetShown(showNext and true or false)
    if showNext then f.nextLine:SetText(L["HUD_NEXT_FMT"]:format(v.nextText)) end
    f.bar:SetValue(v.progress or 0)
    f.bar:SetColorKey(v.state == "arrived" and "good" or "route")
    local arrow = v.pointing and v.state == "moving" and Journey.ArrowMode() == "hud"
    if not arrow then ShowGlyph(v.icon) end
    SetCast(v.state ~= "arrived" and v.step or nil)
    FitHeight()
    f:Show()
end

function HUD.Toast(text, questID)
    if not f then
        FG.Print(text)
        return
    end
    f.toast.text:SetText(text)
    f.toast:Show()
    f.toastFor = questID
    local shown = text
    FG.After(TOAST_SECONDS, function()
        if f.toast.text:GetText() == shown then f.toast:Hide() end
    end)
    FG.Print(text)
end

FG.On("journey:view", HUD.Render)
FG.On("toast", HUD.Toast)

FG.On("settings:changed", function()
    if f then
        ApplyScale()
        ApplyLock()
    end
    HUD.Render(Journey.View())
end)

FG.On("arrow:changed", function()
    if f then HUD.Render(Journey.View()) end
end)

FG.On("places:reset", function()
    if f then
        ApplyScale()
        Place()
    end
end)

-- The last moment a secure button may still be hidden and let go of.
FG.OnEvent("PLAYER_REGEN_DISABLED", function()
    if f and f.cast then
        f.cast:Hide()
        f.cast:ClearAllPoints()
    end
    if FG.db and FG.db.hud.hideInCombat then HUD.Render(view) end
end)
FG.OnEvent("PLAYER_REGEN_ENABLED", function()
    HUD.Render(Journey.View())
end)
