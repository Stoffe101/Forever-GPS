-- The navigation HUD: what to do now, how far, how long, and what comes next. On
-- a ride it stops pointing and says which ride it is. The arrow's aim is EasyFind
-- GPS's own, so it follows the walk around bends rather than straight at the end;
-- this only eases it, so it turns rather than twitches.
local FG = ForeverGPS
local HUD = {}
FG.HUD = HUD

local Kit, Theme, Format = FG.Kit, FG.Theme, FG.Format
local Bridge, Journey = FG.Bridge, FG.Journey
local L = FG.L

local HOME_Y, MARGIN = -96, 8
local ARROW_EVERY = 0.03
local ARROW_RATE = 12        -- how quickly the arrow closes on its aim, per second
local ARROW_STILL = 0.02     -- radians: closer than this it stays put
local REDUCED_EVERY = 0.25   -- with reduced motion it turns in steps, this often
local REDUCED_STEP = math.pi / 12
local TOAST_SECONDS = 6
local TWO_PI = math.pi * 2

-- How much each size shows.
local LAYOUT = {
    compact = { width = 250, arrow = 24, pad = 7, lines = 1, text = 44 },
    standard = { width = 330, arrow = 34, pad = 10, lines = 2, text = 56, next = true, bar = true },
    detailed = { width = 390, arrow = 38, pad = 11, lines = 3, text = 62, next = true, bar = true, detail = true },
    -- A handheld screen: compact, but wide enough and two lines, so what to do is not cut off.
    handheld = { width = 380, arrow = 30, pad = 9, lines = 2, text = 52, bar = true },
}
local FONT_DELTA = { small = -1, normal = 0, large = 2 }

local f, toast, view
local since = 0
local aim                    -- the arrow's rotation now

local function Enabled() return FG.db and FG.db.hud.enabled end
local function Handheld() return FG.Window and FG.Window.Handheld and FG.Window.Handheld() end
local function Look()
    if Handheld() and FG.db.hud.handheldCompact ~= false then return LAYOUT.handheld end
    return LAYOUT[FG.db.hud.mode] or LAYOUT.standard
end

-- Places a controller can choose (Settings, Controller): the top, its corners, the foot.
HUD.SPOTS = {
    top = { "TOP", "TOP", 0, HOME_Y },
    topleft = { "TOPLEFT", "TOPLEFT", 24, -24 },
    topright = { "TOPRIGHT", "TOPRIGHT", -24, -200 },
    bottom = { "BOTTOM", "BOTTOM", 0, 150 },
}

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
    local scale = FG.Settings.HudScale()
    f:SetScale(scale)
    f:SetWidth(math.min(Look().width, (UIParent:GetWidth() - MARGIN * 2) / scale))
end

local function PaintBack()
    local c = Theme.C.hud
    f.back:SetColor({ c[1], c[2], c[3], FG.db and FG.db.hud.opacity or c[4] })
end

-- Sizes and text follow the settings.
local function ApplyLook()
    local look = Look()
    local delta = FONT_DELTA[FG.db.hud.font] or 0
    f.arrow:SetSize(look.arrow, look.arrow)
    f.arrow:ClearAllPoints()
    f.arrow:SetPoint("TOPLEFT", f, "TOPLEFT", look.pad, -look.pad)
    f.arrow:SetIcon(FG.db.hud.arrowStyle == "chevron" and "nav-chevron" or "nav-arrow")
    f.glyph:SetSize(look.arrow - 6, look.arrow - 6)
    f.glyph:ClearAllPoints()
    f.glyph:SetPoint("TOPLEFT", f, "TOPLEFT", look.pad + 3, -look.pad - 3)
    f.title:ClearAllPoints()
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", look.text, -look.pad + 1)
    f.title:SetPoint("TOPRIGHT", f, "TOPRIGHT", -24, -look.pad + 1)
    f.title:SetMaxLines(look.lines)
    local flags = FG.db.hud.outline and "OUTLINE" or ""
    Kit.SetStyle(f.title, "heading", delta, flags)
    Kit.SetStyle(f.meta, "small", delta, flags)
    Kit.SetStyle(f.detail, "small", delta, flags)
    Kit.SetStyle(f.nextLine, "small", delta, flags)
    f.bar:SetShown(look.bar == true)
    PaintBack()
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

-- A line under the HUD, its own frame: it outlives the route it speaks of.
local function BuildToast()
    toast = CreateFrame("Frame", "ForeverGPSToast", UIParent)
    toast:SetFrameStrata("MEDIUM")
    toast:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -4)
    toast:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -4)
    toast.back = Kit.Shape(toast, 7, "BACKGROUND", 1)
    Theme.Paint(function(c) toast.back:SetColor(c.hud) end)
    toast.text = Kit.Text(toast, "small", "text")
    toast.detail = Kit.Text(toast, "small", "textDim")
    toast.action = Kit.Button(toast, { text = L["QUEST_SHOW_ROUTE"], height = 22, width = "fit", onClick = function()
        local q = toast.questID and FG.Quests.Get(toast.questID)
        if q then FG.QuestsView.GoNext(q) end
        toast:Hide()
    end })
    toast.action:SetPoint("RIGHT", toast, "RIGHT", -3, 0)
    toast:Hide()
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
        PaintBack()
        f.edge:SetColor(c.line)
    end)
    f.arrow = Kit.Icon(f, 34, "route")
    f.glyph = Kit.Icon(f, 28, "route")
    f.title = Kit.Text(f, "heading", "text", 2)
    f.meta = Kit.Text(f, "small", "textDim")
    f.meta:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -3)
    f.meta:SetPoint("TOPRIGHT", f.title, "BOTTOMRIGHT", 0, -3)
    f.detail = Kit.Text(f, "small", "textDim")
    f.detail:SetPoint("TOPLEFT", f.meta, "BOTTOMLEFT", 0, -2)
    f.detail:SetPoint("TOPRIGHT", f.meta, "BOTTOMRIGHT", 0, -2)
    f.nextLine = Kit.Text(f, "small", "textFaint")
    f.bar = Kit.Bar(f, 3, "route")
    f.bar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 7)
    f.bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 7)
    f.close = Kit.IconButton(f, "close", 9, L["HUD_STOP"], function() Bridge.Stop() end)
    f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -3)

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

    BuildToast()
    ApplyLook()
    ApplyScale()
    ApplyLock()
    Place()
end

-- Stops pointing and shows the step's own icon.
local function ShowGlyph(icon)
    f.arrow:Hide()
    aim = nil
    f.glyph:SetIcon(icon)
    f.glyph:Show()
end

-- The next rotation on the way from where the arrow is to where it should be.
local function Eased(goal, elapsed)
    if not aim then return goal end
    local gap = (goal - aim + math.pi) % TWO_PI - math.pi
    if math.abs(gap) < ARROW_STILL then return aim end
    return aim + gap * (1 - math.exp(-ARROW_RATE * elapsed))
end
HUD._Eased = Eased

-- Turns the arrow; it only ever spins while it is on screen.
function HUD.Spin(elapsed)
    since = since + elapsed
    local reduced = FG.db.reducedMotion
    if since < (reduced and REDUCED_EVERY or ARROW_EVERY) then return end
    local step = since
    since = 0
    if not (view and view.pointing and view.state == "moving" and Journey.ArrowMode() == "hud") then return end
    local heading = Journey.Heading()
    if not heading then return ShowGlyph(view.icon) end
    f.glyph:Hide()
    f.arrow:Show()
    aim = reduced and math.floor(heading / REDUCED_STEP + 0.5) * REDUCED_STEP or Eased(heading, step)
    f.arrow:SetRotation(aim)
end

local function Meta(v, look)
    local parts = {}
    if v.took then parts[#parts + 1] = L["HUD_TOOK_FMT"]:format(Format.Duration(v.took)) end
    if v.yards then parts[#parts + 1] = Format.Yards(v.yards) end
    if v.state == "waiting" then
        parts[#parts + 1] = v.leaves and L["HUD_LEAVES_FMT"]:format(Format.Clock(v.leaves)) or L["HUD_NO_TIMETABLE"]
    end
    if v.state == "riding" and v.stepEta then parts[#parts + 1] = L["HUD_ABOUT_FMT"]:format(Format.Clock(v.stepEta)) end
    if v.eta and FG.db.hud.showEta then parts[#parts + 1] = L["HUD_LEFT_FMT"]:format(Format.Duration(v.eta)) end
    if v.state == "moving" and v.index and v.count and look ~= LAYOUT.compact then
        parts[#parts + 1] = L["HUD_STEP_FMT"]:format(v.index, v.count)
    end
    return table.concat(parts, " \194\183 ")
end

-- The extra line in the largest size: what the turn ahead is, or the ride.
local function Detail(v)
    if v.turn then return L[v.turn.side == "left" and "HUD_TURN_LEFT_FMT" or "HUD_TURN_RIGHT_FMT"]:format(Format.Yards(v.turn.yards)) end
    if v.dest then return L["HUD_TO_FMT"]:format(v.dest) end
    return nil
end

local function PlaceLines(look, nextShown)
    f.nextLine:ClearAllPoints()
    local over = f.detail:IsShown() and f.detail or f.meta
    f.nextLine:SetPoint("TOPLEFT", over, "BOTTOMLEFT", 0, -2)
    f.nextLine:SetPoint("TOPRIGHT", over, "BOTTOMRIGHT", 0, -2)
    local h = look.pad - 1 + f.title:GetStringHeight() + 3 + f.meta:GetStringHeight()
    if f.detail:IsShown() then h = h + 2 + f.detail:GetStringHeight() end
    if nextShown then h = h + 2 + f.nextLine:GetStringHeight() end
    h = h + look.pad + (look.bar and 6 or 0)
    f:SetHeight(math.max(look.arrow + look.pad * 2, h))
end

function HUD.Render(v)
    view = v
    local hidden = not (Enabled() and v) or (FG.db.hud.hideInCombat and InCombatLockdown())
        or (v and v.state == "riding" and FG.db.hud.autoHide)
    if hidden then
        if f then
            SetCast(nil)
            f:Hide()
        end
        return
    end
    if not f then Build() end
    local look = Look()
    f.title:SetText(v.title)
    f.title:SetColorKey(v.hostile and "danger" or "text")
    f.meta:SetText(Meta(v, look))
    local detail = look.detail and Detail(v) or nil
    f.detail:SetShown(detail ~= nil)
    f.detail:SetText(detail or "")
    local showNext = look.next and v.nextText and FG.db.hud.showNext and v.state ~= "arrived"
    f.nextLine:SetShown(showNext and true or false)
    if showNext then f.nextLine:SetText(L["HUD_NEXT_FMT"]:format(v.nextText)) end
    f.bar:SetValue(v.progress or 0)
    f.bar:SetColorKey(v.state == "arrived" and "good" or "route")
    local arrow = v.pointing and v.state == "moving" and Journey.ArrowMode() == "hud"
    if not arrow then ShowGlyph(v.icon) end
    SetCast(v.state ~= "arrived" and v.step or nil)
    PlaceLines(look, showNext)
    f:Show()
end

-- A line of news; with a quest, a button to the route that comes next. quiet: news
-- of the moment, not worth a line in the chat as well.
function HUD.Toast(text, questID, detail, quiet)
    if not f then Build() end
    local right = questID and -(toast.action:GetWidth() + 10) or -10
    toast:SetHeight(detail and 44 or 28)
    toast.text:ClearAllPoints()
    toast.text:SetPoint("TOPLEFT", toast, "TOPLEFT", 10, -7)
    toast.text:SetPoint("TOPRIGHT", toast, "TOPRIGHT", right, -7)
    toast.detail:ClearAllPoints()
    toast.detail:SetPoint("TOPLEFT", toast.text, "BOTTOMLEFT", 0, -3)
    toast.detail:SetPoint("TOPRIGHT", toast.text, "BOTTOMRIGHT", 0, -3)
    toast.text:SetText(text)
    toast.detail:SetText(detail or "")
    toast.detail:SetShown(detail ~= nil)
    toast.action:SetShown(questID ~= nil)
    toast.questID = questID
    toast:Show()
    local shown = text
    FG.After(TOAST_SECONDS * (questID and 3 or 1), function()
        if toast.text:GetText() == shown then toast:Hide() end
    end)
    if not quiet then FG.Print(detail and (text .. " " .. detail) or text) end
end

function HUD.ToastFrame() return toast end

FG.On("journey:view", HUD.Render)
FG.On("toast", HUD.Toast)

-- A sound for having arrived, for anyone not watching the screen.
FG.On("journey:arrived", function()
    if FG.db.hud.sound and PlaySound then PlaySound(SOUNDKIT and SOUNDKIT.MAP_PING or 3175, "SFX") end
end)

FG.On("settings:changed", function()
    if f then
        ApplyLook()
        ApplyScale()
        ApplyLock()
    end
    HUD.Render(Journey.View())
end)

FG.On("arrow:changed", function()
    if f then HUD.Render(Journey.View()) end
end)

-- A spot chosen with the controller: the HUD goes there, as a drag would put it.
function HUD.MoveTo(spot)
    local s = HUD.SPOTS[spot]
    if not s then return false end
    FG.db.hud.point = { s[1], s[2], s[3], s[4] }
    FG.db.hud.spot = spot
    if f then Place() end
    return true
end
function HUD.Spot() return FG.db.hud.point and FG.db.hud.spot or "top" end

local function Relook()
    if not f then return end
    ApplyLook()
    ApplyScale()
    HUD.Render(Journey.View())
end
FG.On("pad:layout", Relook)
FG.On("pad:input", Relook)

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
