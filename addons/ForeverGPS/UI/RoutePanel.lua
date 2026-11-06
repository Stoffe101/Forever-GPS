-- The journey panel: what the planner found, the ways to choose from, each step
-- in order, and the button that starts it. With nothing being inspected it shows
-- the route under way; with neither, a short invitation.
local _, FG = ...
local Panel = {}
FG.RoutePanel = Panel

local Kit, Theme, Format, Kinds, List = FG.Kit, FG.Theme, FG.Format, FG.Kinds, FG.List
local Bridge, Planner, Risk, Saved = FG.Bridge, FG.Planner, FG.Risk, FG.Saved
local L = FG.L

local PAD = 14
local SHORT_HEIGHT = 400     -- below this, the steps come before the extras

local AVOIDS = { { "taxi", "AVOID_TAXI" }, { "boat", "AVOID_BOAT" }, { "zeppelin", "AVOID_ZEPPELIN" },
                 { "portal", "AVOID_PORTAL" }, { "teleport", "AVOID_TELEPORT" } }

local RISK_COLOR = { low = "good", moderate = "warn", high = "danger", unknown = "textFaint" }

-- The steps a panel lists, whichever route they belong to.
local function StepItems(steps, active, doneBefore)
    local items = {}
    for i = 1, #steps do
        local step = steps[i]
        items[i] = { kind = "step", step = step, number = i, active = active == i, done = doneBefore and i < doneBefore }
    end
    return items
end

local measure

local function TextHeight(text, width, style)
    if not measure then
        -- Shown but unseen: a hidden string's metrics are not reliable.
        measure = UIParent:CreateFontString(nil, "OVERLAY")
        measure:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
        measure:SetAlpha(0)
        measure:SetWordWrap(true)
    end
    Kit.SetStyle(measure, style)
    measure:SetWidth(width)
    measure:SetText(text or "")
    return measure:GetStringHeight()
end
Panel.TextHeight = TextHeight

local function StepText(item)
    return item.active and Bridge.StepText(item.step, true) or (item.step.reachText and item.step.approach and item.step.reachText) or item.step.text or ""
end

local function MakeStep(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.back = Kit.Shape(row, 6, "BACKGROUND", 1)
    row.back:SetShown(false)
    row.icon = Kit.Icon(row, 16, "glyph")
    row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -8)
    row.text = Kit.Text(row, "body", "text", 0)
    row.text:SetPoint("TOPLEFT", row, "TOPLEFT", 32, -7)
    row.text:SetPoint("TOPRIGHT", row, "TOPRIGHT", -56, -7)
    row.time = Kit.Text(row, "small", "textDim")
    row.time:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -8)
    row.time:SetJustifyH("RIGHT")
    row.detail = Kit.Text(row, "small", "textFaint")
    row.detail:SetPoint("TOPLEFT", row.text, "BOTTOMLEFT", 0, -2)
    row.detail:SetPoint("TOPRIGHT", row.text, "BOTTOMRIGHT", 0, -2)
    return row
end

local function StepDetail(step)
    if step.hostile then return L["STEP_ENEMY_RIDE"] end
    if step.wait and step.wait > 0 and step.edgeSec then
        return L["STEP_RIDE_WAIT_FMT"]:format(Format.Duration(step.edgeSec), Format.Duration(step.wait))
    end
    return nil
end

local function BindStep(row, item)
    local step = item.step
    row.icon:SetIcon(Kinds.Info(step).icon)
    row.icon:SetColorKey(item.active and "route" or item.done and "textFaint" or "glyph")
    row.text:SetText(StepText(item))
    row.text:SetColorKey(item.done and "textFaint" or "text")
    row.time:SetText(step.sec and step.sec > 0 and Format.Duration(step.sec) or "")
    local detail = StepDetail(step)
    row.detail:SetText(detail or "")
    row.detail:SetShown(detail ~= nil)
    row.back:SetShown(item.active == true)
    if item.active then row.back:SetColor(Theme.C.routeSoft) end
end

local function StepHeight(item, width)
    local h = TextHeight(StepText(item), width - 84, "body") + 14
    if StepDetail(item.step) then h = h + 15 end
    return math.max(32, h)
end

-- ==== building ==============================================================

local f, stepList

local function Build(parent)
    f = CreateFrame("Frame", nil, parent)
    f.back = Kit.Shape(f, 8, "BACKGROUND", 1)
    Theme.Paint(function(c) f.back:SetColor(c.raised) end)

    f.backButton = Kit.IconButton(f, "back", 14, L["ROUTE_BACK"], function() FG.Window.ShowList() end)
    f.backButton:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -8)
    f.star = Kit.IconButton(f, "star-line", 15, nil, function()
        local plan = Planner.Current()
        if plan and plan.target then
            Saved.ToggleFavorite(plan.target)
            Panel.Render()
        end
    end)
    f.star:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -8)
    Kit.Tooltip(f.star, function()
        local plan = Planner.Current()
        return plan and plan.target and L[Saved.IsFavorite(plan.target.data) and "ROUTE_UNFAVORITE" or "ROUTE_FAVORITE"] or nil
    end)
    f.title = Kit.Text(f, "heading", "text", 2)
    f.subtitle = Kit.Text(f, "small", "textDim")

    -- The invitation, or what went wrong.
    f.empty = CreateFrame("Frame", nil, f)
    f.empty:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -PAD)
    f.empty:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD)
    f.emptyIcon = Kit.Icon(f.empty, 34, "textFaint")
    f.emptyIcon:SetPoint("BOTTOM", f.empty, "CENTER", 0, 24)
    f.emptyTitle = Kit.Text(f.empty, "heading", "text", 2)
    f.emptyTitle:SetPoint("TOPLEFT", f.empty, "LEFT", 0, 12)
    f.emptyTitle:SetPoint("TOPRIGHT", f.empty, "RIGHT", 0, 12)
    f.emptyTitle:SetJustifyH("CENTER")
    f.emptyBody = Kit.Text(f.empty, "small", "textDim", 0)
    f.emptyBody:SetPoint("TOPLEFT", f.emptyTitle, "BOTTOMLEFT", 0, -6)
    f.emptyBody:SetPoint("TOPRIGHT", f.emptyTitle, "BOTTOMRIGHT", 0, -6)
    f.emptyBody:SetJustifyH("CENTER")

    -- The summary.
    f.time = Kit.Text(f, "display", "text")
    f.via = Kit.Text(f, "small", "textDim")
    f.riskIcon = Kit.Icon(f, 12, "good")
    f.riskIcon:SetIcon("shield")
    f.risk = Kit.Text(f, "small", "good")
    f.riskHit = CreateFrame("Frame", nil, f)
    f.riskHit:EnableMouse(true)
    Kit.Tooltip(f.riskHit, function()
        local plan = Planner.Current()
        local option = plan and plan.selected
        return option and option.risk and Risk.Label(option.risk.level) or nil
    end, function()
        local plan = Planner.Current()
        local option = plan and plan.selected
        local lines = {}
        for _, reason in ipairs(option and option.risk and option.risk.reasons or {}) do lines[#lines + 1] = reason end
        lines[#lines + 1] = L["RISK_DISCLAIMER"]
        return table.concat(lines, "\n")
    end)

    -- The ways to choose from.
    f.modes = {}
    for i, mode in ipairs(Planner.MODES) do
        local chip = Kit.Chip(f, L[mode.label], function(self)
            if self.option then Planner.Select(self.option) end
        end)
        chip.mode = mode
        Kit.Tooltip(chip, L[mode.label], function()
            return chip.same and L["ROUTE_SAME_AS_FASTEST"] or L[mode.tip]
        end)
        f.modes[i] = chip
    end

    -- Which of several locations.
    f.place = Kit.Button(f, { text = "", height = 24, icon = "pin", onClick = function(self) Panel.PickArea(self) end })

    -- The route's shape: icons and times in a line.
    f.strip = CreateFrame("Frame", nil, f)
    f.strip:SetHeight(18)
    f.stripParts = {}

    stepList = List.New(f, { make = { step = MakeStep }, bind = BindStep, height = StepHeight })

    f.avoidLabel = Kit.Text(f, "caption", "textFaint")
    f.avoidLabel:SetText(L["ROUTE_AVOID"])
    f.avoids = {}
    for i, entry in ipairs(AVOIDS) do
        local chip = Kit.Chip(f, L[entry[2]], function(self)
            Bridge.SetAvoid(self.key, not Bridge.AvoidOn(self.key))
            self:SetSelected(Bridge.AvoidOn(self.key))
            Planner.Replan()
        end)
        chip.key = entry[1]
        chip:SetHeight(20)
        f.avoids[i] = chip
    end

    f.go = Kit.Button(f, { text = L["ROUTE_START"], variant = "primary", height = 34, icon = "nav-arrow", onClick = function()
        Panel.Go()
    end })
    FG.On("plan:changed", Panel.Render)
    FG.On("journey:step", Panel.Render)
    FG.On("route:cleared", Panel.Render)
    return f
end

-- ==== the route's shape =====================================================

local function StripPart(i)
    local part = f.stripParts[i]
    if part then return part end
    part = CreateFrame("Frame", nil, f.strip)
    part:SetHeight(18)
    part.icon = Kit.Icon(part, 14, "glyph")
    part.icon:SetPoint("LEFT", part, "LEFT", 0, 0)
    part.time = Kit.Text(part, "caption", "textDim")
    part.time:SetPoint("LEFT", part.icon, "RIGHT", 3, 0)
    part.arrow = Kit.Icon(part, 8, "textFaint")
    part.arrow:SetIcon("chevron-right")
    part.arrow:SetPoint("LEFT", part.time, "RIGHT", 5, 0)
    f.stripParts[i] = part
    return part
end

local function FillStrip(steps, width)
    local segments = Kinds.Segments(steps)
    local x = 0
    local shown = 0
    for i, seg in ipairs(segments) do
        local part = StripPart(i)
        part.icon:SetIcon(seg.icon)
        part.time:SetText(Format.Duration(seg.sec))
        local w = 17 + part.time:GetStringWidth()
        local last = i == #segments
        part.arrow:SetShown(not last)
        local full = w + (last and 0 or 16)
        if x + w > width then
            part:Hide()
        else
            part:ClearAllPoints()
            part:SetPoint("LEFT", f.strip, "LEFT", x, 0)
            part:SetWidth(w)
            part:Show()
            shown = shown + 1
        end
        x = x + full
    end
    for i = #segments + 1, #f.stripParts do f.stripParts[i]:Hide() end
    return shown
end

-- ==== rendering =============================================================

local function ShowEmpty(icon, title, body)
    f.empty:Show()
    f.emptyIcon:SetIcon(icon)
    f.emptyTitle:SetText(title)
    f.emptyBody:SetText(body or "")
    f.title:Hide()
    f.subtitle:Hide()
    f.star:Hide()
end

local function SetHeader(title, subtitle, favorite)
    f.empty:Hide()
    local left = f.backButton:IsShown() and 30 or PAD
    f.title:ClearAllPoints()
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", left, -PAD)
    f.title:SetPoint("TOPRIGHT", f, "TOPRIGHT", -38, -PAD)
    f.subtitle:ClearAllPoints()
    f.subtitle:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -2)
    f.subtitle:SetPoint("TOPRIGHT", f.title, "BOTTOMRIGHT", 0, -2)
    f.title:SetText(title or "")
    f.subtitle:SetText(subtitle or "")
    f.title:Show()
    f.subtitle:SetShown(subtitle ~= nil)
    if favorite == nil then
        f.star:Hide()
    else
        f.star:Show()
        f.star.glyph:SetIcon(favorite and "star" or "star-line")
        f.star:SetActiveColor(favorite and "accent" or nil)
    end
end

local CONTENT = { "time", "via", "riskIcon", "risk", "riskHit", "strip", "go", "avoidLabel" }

local function ShowContent(on)
    for _, key in ipairs(CONTENT) do f[key]:SetShown(on) end
    stepList:SetShown(on)
    for i = 1, #f.modes do f.modes[i]:SetShown(on) end
    for i = 1, #f.avoids do f.avoids[i]:SetShown(on) end
    if not on then f.place:Hide() end
end

-- Places everything under the header, top down, with the steps taking the rest.
local function Stack(steps, option, showModes, showAvoid)
    local width = f:GetWidth() - PAD * 2
    local short = f:GetHeight() < SHORT_HEIGHT
    showAvoid = showAvoid and not short
    local y = -(f.title:GetStringHeight() + PAD + (f.subtitle:IsShown() and 16 or 0) + 10)
    f.time:ClearAllPoints()
    f.time:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
    f.via:ClearAllPoints()
    f.via:SetPoint("BOTTOMLEFT", f.time, "BOTTOMRIGHT", 8, 3)
    f.via:SetWidth(math.max(1, width - f.time:GetStringWidth() - 8))
    y = y - 30
    local risk = option and option.risk
    f.riskIcon:SetShown(risk ~= nil)
    f.risk:SetShown(risk ~= nil)
    f.riskHit:SetShown(risk ~= nil)
    if risk then
        local key = RISK_COLOR[risk.level] or "textFaint"
        f.riskIcon:ClearAllPoints()
        f.riskIcon:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y - 1)
        f.riskIcon:SetColorKey(key)
        f.risk:ClearAllPoints()
        f.risk:SetPoint("LEFT", f.riskIcon, "RIGHT", 5, 0)
        f.risk:SetWidth(math.max(1, width - 17))
        f.risk:SetText(Risk.Label(risk.level))
        f.risk:SetColorKey(key)
        f.riskHit:ClearAllPoints()
        f.riskHit:SetPoint("TOPLEFT", f.riskIcon, "TOPLEFT", 0, 2)
        f.riskHit:SetPoint("BOTTOMRIGHT", f.risk, "BOTTOMRIGHT", 0, -2)
        y = y - 18
    end
    y = y - 4
    if showModes then
        local h = Kit.FlowChips(f.modes, f, width, 6, 0)
        for i = 1, #f.modes do
            local chip = f.modes[i]
            local _, rel, _, x, cy = chip:GetPoint(1)
            chip:ClearAllPoints()
            chip:SetPoint("TOPLEFT", rel, "TOPLEFT", x + PAD, cy + y)
        end
        y = y - h - 8
    end
    if f.place:IsShown() then
        f.place:ClearAllPoints()
        f.place:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
        f.place:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y)
        y = y - 30
    end
    f.strip:SetShown(not short)
    if not short then
        f.strip:ClearAllPoints()
        f.strip:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
        f.strip:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y)
        FillStrip(steps, width)
        y = y - 24
    end
    -- The bottom, up.
    local bottom = PAD
    f.go:ClearAllPoints()
    f.go:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, bottom)
    f.go:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, bottom)
    bottom = bottom + 34 + 8
    f.avoidLabel:SetShown(showAvoid)
    for i = 1, #f.avoids do f.avoids[i]:SetShown(showAvoid) end
    if showAvoid then
        for i = 1, #f.avoids do f.avoids[i]:SetSelected(Bridge.AvoidOn(f.avoids[i].key)) end
        local labelW = f.avoidLabel:GetStringWidth() + 8
        local h = Kit.FlowChips(f.avoids, f, width - labelW, 4, 0)
        for i = 1, #f.avoids do
            local chip = f.avoids[i]
            local _, rel, _, x, cy = chip:GetPoint(1)
            chip:ClearAllPoints()
            chip:SetPoint("BOTTOMLEFT", rel, "BOTTOMLEFT", x + PAD + labelW, bottom + h - 20 + cy)
        end
        f.avoidLabel:ClearAllPoints()
        f.avoidLabel:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, bottom + h - 15)
        bottom = bottom + h + 8
    end
    stepList:ClearAllPoints()
    stepList:SetPoint("TOPLEFT", f, "TOPLEFT", PAD - 6, y)
    stepList:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(PAD - 6), bottom)
end

local function FillModes(plan)
    for _, chip in ipairs(f.modes) do
        local option
        for _, o in ipairs(plan.options) do
            if o.mode == chip.mode then option = o end
        end
        chip.option = option and option.steps and not option.noWay and not option.same and option or nil
        chip.same = option ~= nil and option.same == true
        local label = L[chip.mode.label]
        if option and option.same then
            chip.dim = true
        elseif option and option.steps and not option.noWay then
            chip.dim = false
            label = label .. "  " .. Format.Duration(option.total)
        else
            chip.dim = true
        end
        chip:SetLabel(label)
        chip:SetShown(option ~= nil)
        chip:SetSelected(option ~= nil and plan.selected == option)
    end
end

local function RenderPlan(plan)
    local target = plan.target or {}
    local favorite = target.data and Saved.IsFavorite(target.data) or false
    if plan.status == "failed" or plan.status == "unreachable" then
        ShowContent(false)
        ShowEmpty("warning", plan.status == "failed" and (target.name or "?") or L["ROUTE_NO_WAY_TITLE"], plan.message)
        return
    end
    if not plan.selected then
        ShowContent(false)
        ShowEmpty("clock", target.name or "?", L["ROUTE_PLANNING"])
        return
    end
    SetHeader(target.name, target.subtitle, favorite)
    local option = plan.selected
    ShowContent(true)
    f.time:SetText(Format.Duration(option.total) or "?")
    f.via:SetText(option.estimate and L["ROUTE_ESTIMATE_ONLY"] or Kinds.Summary(option.steps))
    FillModes(plan)
    local areas = target.areas
    f.place:SetShown(areas ~= nil and #areas > 1)
    if areas and #areas > 1 then
        local at = target.area
        f.place:SetLabel(("%s  (%s)"):format(at and at.zone or "?", L["LOCATIONS_FMT"]:format(#areas)))
    end
    Stack(option.steps, option, true, true)
    stepList:SetItems(StepItems(option.steps), true)
    local active = Bridge.ActiveRoute()
    local same = active and active.dest and plan.dest and active.dest.name == plan.dest.name and active.dest.mapID == plan.dest.mapID
    f.go:SetLabel(L[same and "ROUTE_STOP" or "ROUTE_START"])
    f.go:SetVariant(same and "danger" or "primary")
    f.go:SetEnabled(option.steps ~= nil)
    f.goStops = same
end

local function RenderActive(route)
    SetHeader(route.dest and route.dest.name or "?", L["ROUTE_ACTIVE"], nil)
    ShowContent(true)
    f.time:SetText(Format.Duration(route.eta or route.total) or "?")
    f.via:SetText(Kinds.Summary(route.steps))
    for i = 1, #f.modes do f.modes[i]:Hide() end
    f.place:Hide()
    Stack(route.steps, nil, false, false)
    local active = route.active or 1
    stepList:SetItems(StepItems(route.steps, active, active), true)
    stepList:Reveal(active)
    f.go:SetLabel(L["ROUTE_STOP"])
    f.go:SetVariant("danger")
    f.go:SetEnabled(true)
    f.goStops = true
end

function Panel.Render()
    if not (f and f:IsVisible()) then return end
    f.backButton:SetShown(FG.Window.IsCompact())
    local plan = Planner.Current()
    local route = Bridge.ActiveRoute()
    if plan then
        RenderPlan(plan)
    elseif route then
        RenderActive(route)
    else
        ShowContent(false)
        ShowEmpty("pin", L["ROUTE_EMPTY_TITLE"], L["ROUTE_EMPTY"])
    end
end

function Panel.Go()
    if f.goStops then
        Bridge.Stop()
        Planner.Clear()
        return
    end
    if Planner.Start() and FG.db.autoClose then FG.Window.Hide() end
end

-- The menu of a target's other locations.
function Panel.PickArea(anchor)
    local plan = Planner.Current()
    local target = plan and plan.target
    if not (target and target.areas) then return end
    local rows = {}
    for _, area in ipairs(target.areas) do
        local time = area.sec and L["ETA_SHORT_FMT"]:format(Format.Duration(area.sec)) or nil
        rows[#rows + 1] = {
            label = time and ("%s  %s"):format(area.zone or "?", time) or (area.zone or "?"),
            onClick = function() FG.Search.GoToArea(target, area) end,
        }
    end
    Kit.Menu(anchor, rows)
end

function Panel.Get(parent) return f or Build(parent) end
