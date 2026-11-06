-- The journey panel: what the planner found, the ways to choose from and how they
-- differ, each step in order, and the buttons that show it on the map and start it.
-- With nothing being inspected it shows the route under way; with neither, a short
-- invitation.
local _, FG = ...
local Panel = {}
FG.RoutePanel = Panel

local Kit, Theme, Format, Kinds, List = FG.Kit, FG.Theme, FG.Format, FG.Kinds, FG.List
local Bridge, Planner, Risk, Saved, Trip = FG.Bridge, FG.Planner, FG.Risk, FG.Saved, FG.Trip
local L = FG.L

local PAD = 14
local SHORT_HEIGHT = 400     -- below this, the steps come before the extras
local MENU_ROWS = 8          -- locations listed; the map shows them all
local FOOT_H = 34

local AVOIDS = { { "taxi", "AVOID_TAXI" }, { "boat", "AVOID_BOAT" }, { "zeppelin", "AVOID_ZEPPELIN" },
                 { "portal", "AVOID_PORTAL" }, { "teleport", "AVOID_TELEPORT" } }

local RISK_COLOR = { low = "good", moderate = "warn", high = "danger", unknown = "textFaint" }
local QUALITY_COLOR = { detailed = "good", partial = "warn", estimate = "warn" }

-- The steps a panel lists, whichever route they belong to. Stops still ahead are
-- counted, since that is how a trip names the one to skip.
local function StepItems(steps, active, doneBefore)
    local items, ahead = {}, 0
    local focus = FG.MapPreview.Focused()
    local count = #steps
    for i = 1, count do
        local step = steps[i]
        local item = { kind = "step", step = step, number = i, active = active == i, done = doneBefore and i < doneBefore,
                       focused = focus == i, first = i == 1, last = i == count }
        if active and step.tripStop and i >= active then
            ahead = ahead + 1
            item.stopAhead = ahead
        end
        items[i] = item
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

-- The line that runs through the steps, joining each to the next.
local function Rail(row)
    local tex = row:CreateTexture(nil, "BORDER")
    tex:SetWidth(2)
    Theme.Paint(function(c) tex:SetColorTexture(c.line[1], c.line[2], c.line[3], 1) end)
    return tex
end

local function MakeStep(parent)
    local row = CreateFrame("Button", nil, parent)
    row:RegisterForClicks("LeftButtonUp")
    row.back = Kit.Shape(row, 6, "BACKGROUND", 1)
    row.back:SetShown(false)
    row.icon = Kit.Icon(row, 16, "glyph")
    row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -8)
    row.railIn = Rail(row)
    row.railIn:SetPoint("TOP", row, "TOPLEFT", 16, 0)
    row.railIn:SetPoint("BOTTOM", row.icon, "TOP", 0, 2)
    row.railOut = Rail(row)
    row.railOut:SetPoint("TOP", row.icon, "BOTTOM", 0, -2)
    row.railOut:SetPoint("BOTTOM", row, "BOTTOMLEFT", 16, 0)
    row.text = Kit.Text(row, "body", "text", 0)
    row.text:SetPoint("TOPLEFT", row, "TOPLEFT", 32, -7)
    row.text:SetPoint("TOPRIGHT", row, "TOPRIGHT", -56, -7)
    row.time = Kit.Text(row, "small", "textDim")
    row.time:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -8)
    row.time:SetJustifyH("RIGHT")
    row.detail = Kit.Text(row, "small", "textFaint")
    row.detail:SetPoint("TOPLEFT", row.text, "BOTTOMLEFT", 0, -2)
    row.detail:SetPoint("TOPRIGHT", row.text, "BOTTOMRIGHT", 0, -2)
    row.skip = Kit.IconButton(row, "close", 8, L["TRIP_SKIP"], function(self)
        Trip.SkipStop(self:GetParent().item.stopAhead)
    end)
    row.skip:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -4, 3)
    row:SetScript("OnEnter", function(self)
        if not self.item.active then
            self.back:SetColor(Theme.C.cardHover)
            self.back:SetShown(true)
        end
    end)
    row:SetScript("OnLeave", function(self) Panel.PaintStep(self, self.item) end)
    row:SetScript("OnClick", function(self) Panel.FocusStep(self.item.number) end)
    return row
end

local function StepDetail(step)
    if step.hostile then return L["STEP_ENEMY_RIDE"] end
    if step.wait and step.wait > 0 and step.edgeSec then
        return L["STEP_RIDE_WAIT_FMT"]:format(Format.Duration(step.edgeSec), Format.Duration(step.wait))
    end
    return nil
end

function Panel.PaintStep(row, item)
    local lit = item.active or item.focused
    row.back:SetShown(lit == true)
    if lit then row.back:SetColor(item.active and Theme.C.routeSoft or Theme.C.cardHover) end
end

local function BindStep(row, item)
    local step = item.step
    row.icon:SetIcon(Kinds.Info(step).icon)
    row.icon:SetColorKey(item.active and "route" or item.done and "textFaint" or step.hostile and "danger" or "glyph")
    row.text:SetText(StepText(item))
    row.text:SetColorKey(item.done and "textFaint" or "text")
    row.time:SetText(step.sec and step.sec > 0 and Format.Duration(step.sec) or "")
    local detail = StepDetail(step)
    row.detail:SetText(detail or "")
    row.detail:SetShown(detail ~= nil)
    row.railIn:SetShown(not item.first)
    row.railOut:SetShown(not item.last)
    row.skip:SetShown(item.stopAhead ~= nil)
    Panel.PaintStep(row, item)
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
    f.quality = Kit.Text(f, "small", "good")
    f.quality:SetJustifyH("RIGHT")
    f.qualityHit = CreateFrame("Frame", nil, f)
    f.qualityHit:EnableMouse(true)
    Kit.Tooltip(f.qualityHit, function()
        local plan = Planner.Current()
        return plan and plan.selected and Planner.Confidence(plan.selected) or nil
    end, function()
        local plan = Planner.Current()
        return plan and plan.selected and select(2, Planner.Confidence(plan.selected)) or nil
    end)

    -- The ways to choose from, and how the chosen one differs.
    f.modes = {}
    for i, mode in ipairs(Planner.MODES) do
        local chip = Kit.Chip(f, L[mode.label], function(self)
            if self.option then Planner.Select(self.option) end
        end)
        chip.mode = mode
        Kit.Tooltip(chip, L[mode.label], L[mode.tip])
        f.modes[i] = chip
    end
    f.compare = Kit.Text(f, "small", "textDim", 2)
    f.note = Kit.Text(f, "small", "warn", 2)

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

    f.mapButton = Kit.Button(f, { icon = "map", height = FOOT_H, width = FOOT_H, onClick = function() Panel.ShowOnMap() end })
    Kit.Tooltip(f.mapButton, L["ROUTE_SHOW_MAP"], L["ROUTE_SHOW_MAP_TT"])
    f.tripButton = Kit.Button(f, { icon = "plus", height = FOOT_H, width = FOOT_H, onClick = function() Panel.AddToTrip() end })
    Kit.Tooltip(f.tripButton, L["TRIP_ADD"], L["TRIP_ADD_TT"])
    f.go = Kit.Button(f, { text = L["ROUTE_START"], variant = "primary", height = FOOT_H, icon = "nav-arrow", onClick = function()
        Panel.Go()
    end })
    FG.On("plan:changed", Panel.Render)
    FG.On("journey:step", Panel.Render)
    FG.On("route:cleared", Panel.Render)
    FG.On("preview:focus", Panel.Render)
    FG.On("trip:changed", Panel.Render)
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

local CONTENT = { "time", "via", "riskIcon", "risk", "riskHit", "quality", "qualityHit", "strip", "go", "mapButton", "avoidLabel" }

local function ShowContent(on)
    for _, key in ipairs(CONTENT) do f[key]:SetShown(on) end
    stepList:SetShown(on)
    for i = 1, #f.modes do f.modes[i]:SetShown(on) end
    for i = 1, #f.avoids do f.avoids[i]:SetShown(on) end
    if not on then
        f.place:Hide()
        f.compare:Hide()
        f.note:Hide()
        f.tripButton:Hide()
    end
end

-- A wrapped line in the column, at y; returns the y under it.
local function PlaceLine(fs, text, y, width)
    fs:SetShown(text ~= nil)
    if not text then return y end
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
    fs:SetWidth(width)
    fs:SetText(text)
    return y - fs:GetStringHeight() - 6
end

-- The hazards on the left of a line, how sure the route is on the right.
local function PlaceSummary(option, y, width)
    local risk = option and option.risk
    f.riskIcon:SetShown(risk ~= nil)
    f.risk:SetShown(risk ~= nil)
    f.riskHit:SetShown(risk ~= nil)
    local quality = option and Planner.Confidence(option)
    f.quality:SetShown(quality ~= nil)
    f.qualityHit:SetShown(quality ~= nil)
    if quality then
        f.quality:SetText(quality)
        f.quality:SetColorKey(QUALITY_COLOR[option.quality] or "textFaint")
        f.quality:ClearAllPoints()
        f.quality:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y)
        f.qualityHit:ClearAllPoints()
        f.qualityHit:SetPoint("TOPLEFT", f.quality, "TOPLEFT", -2, 2)
        f.qualityHit:SetPoint("BOTTOMRIGHT", f.quality, "BOTTOMRIGHT", 2, -2)
    end
    if risk then
        local key = RISK_COLOR[risk.level] or "textFaint"
        f.riskIcon:ClearAllPoints()
        f.riskIcon:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y - 1)
        f.riskIcon:SetColorKey(key)
        f.risk:ClearAllPoints()
        f.risk:SetPoint("LEFT", f.riskIcon, "RIGHT", 5, 0)
        f.risk:SetWidth(math.max(1, width - 25 - (quality and f.quality:GetStringWidth() or 0)))
        f.risk:SetText(Risk.Label(risk.level, risk))
        f.risk:SetColorKey(key)
        f.riskHit:ClearAllPoints()
        f.riskHit:SetPoint("TOPLEFT", f.riskIcon, "TOPLEFT", 0, 2)
        f.riskHit:SetPoint("BOTTOMRIGHT", f.risk, "BOTTOMRIGHT", 0, -2)
    end
    return (risk or quality) and y - 18 or y
end

local function PlaceFooter(trip)
    f.mapButton:ClearAllPoints()
    f.mapButton:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, PAD)
    f.tripButton:SetShown(trip)
    local before = f.mapButton
    if trip then
        f.tripButton:ClearAllPoints()
        f.tripButton:SetPoint("LEFT", f.mapButton, "RIGHT", 6, 0)
        before = f.tripButton
    end
    f.go:ClearAllPoints()
    f.go:SetPoint("TOPLEFT", before, "TOPRIGHT", 6, 0)
    f.go:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD)
end

-- Places everything under the header, top down, with the steps taking the rest.
local function Stack(steps, option, opts)
    local width = f:GetWidth() - PAD * 2
    local short = f:GetHeight() < SHORT_HEIGHT
    local showAvoid = opts.avoid and not short
    local y = -(f.title:GetStringHeight() + PAD + (f.subtitle:IsShown() and 16 or 0) + 10)
    f.time:ClearAllPoints()
    f.time:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
    f.via:ClearAllPoints()
    f.via:SetPoint("BOTTOMLEFT", f.time, "BOTTOMRIGHT", 8, 3)
    f.via:SetWidth(math.max(1, width - f.time:GetStringWidth() - 8))
    y = PlaceSummary(option, y - 30, width) - 4
    if opts.modes then
        local visible = {}
        for i = 1, #f.modes do
            if f.modes[i]:IsShown() then visible[#visible + 1] = f.modes[i] end
        end
        local h = Kit.FlowChips(visible, f, width, 6, 0)
        for _, chip in ipairs(visible) do
            local _, rel, _, x, cy = chip:GetPoint(1)
            chip:ClearAllPoints()
            chip:SetPoint("TOPLEFT", rel, "TOPLEFT", x + PAD, cy + y)
        end
        y = y - h - 6
    end
    y = PlaceLine(f.compare, not short and opts.compare or nil, y, width)
    if f.place:IsShown() then
        f.place:ClearAllPoints()
        f.place:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
        f.place:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y)
        y = y - 30
    end
    y = PlaceLine(f.note, not short and opts.note or nil, y, width)
    f.strip:SetShown(not short)
    if not short then
        f.strip:ClearAllPoints()
        f.strip:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
        f.strip:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y)
        FillStrip(steps, width)
        y = y - 24
    end
    -- The bottom, up.
    PlaceFooter(opts.trip == true)
    local bottom = PAD + FOOT_H + 8
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

-- A way the same as another is no choice to offer: its chip goes, and the line
-- under the chips says so.
local function FillModes(plan)
    for _, chip in ipairs(f.modes) do
        local option
        for _, o in ipairs(plan.options) do
            if o.mode == chip.mode then option = o end
        end
        local usable = option and option.steps and not option.noWay and not option.same
        local waiting = option and not option.builtAt
        chip.option = usable and option or nil
        chip.dim = not usable
        chip:SetLabel(usable and (L[chip.mode.label] .. "  " .. Format.Duration(option.total)) or L[chip.mode.label])
        chip:SetShown((usable or waiting) and true or false)
        chip:SetSelected(usable and plan.selected == option or false)
    end
end

local function Compared(plan, option)
    local base = Planner.Base(plan)
    if option ~= base then return Planner.Compare(option, base) end
    return Planner.SameNote(plan, option)
end

local function PlanNote(target, option)
    if option.estimate then return L["ROUTE_ESTIMATE_NOTE"] end
    if target.predicted then return L["ROUTE_PREDICTED"] end
    return nil
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
    local stop = not target.trip and Trip.FromTarget(target) or nil
    Stack(option.steps, option, { modes = true, avoid = true, compare = Compared(plan, option), note = PlanNote(target, option),
                                  trip = stop ~= nil })
    if stop then
        f.tripButton.glyph:SetIcon(Trip.Has(stop) and "check" or "plus")
        f.tripButton:SetEnabled(not Trip.Has(stop))
    end
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
    Stack(route.steps, nil, { note = Planner.Tip(route.advice) })
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

function Panel.ShowOnMap()
    if Planner.Current() then
        FG.MapPreview.Open()
    else
        FG.MapPreview.OpenActive()
    end
end

-- Picks a step out on the map; the map opens if it was closed.
function Panel.FocusStep(index)
    if Planner.Current() then FG.MapPreview.Focus(index) end
end

function Panel.AddToTrip()
    local plan = Planner.Current()
    local stop = plan and plan.target and Trip.FromTarget(plan.target)
    if not stop then return end
    local _, why = Trip.Add(stop)
    if why then FG.Print(why) end
end

-- The menu of a target's other locations, the quickest first; a long list stays
-- on the map, where the rest can be seen and picked.
function Panel.PickArea(anchor)
    local plan = Planner.Current()
    local target = plan and plan.target
    if not (target and target.areas) then return end
    local rows = {}
    for i, area in ipairs(target.areas) do
        if i > MENU_ROWS then
            rows[#rows + 1] = { label = L["ROUTE_MORE_ON_MAP_FMT"]:format(#target.areas - MENU_ROWS), onClick = function()
                FG.MapPreview.Open()
            end }
            break
        end
        local time = area.sec and L["ETA_SHORT_FMT"]:format(Format.Duration(area.sec)) or nil
        rows[#rows + 1] = {
            label = time and ("%s  %s"):format(area.zone or "?", time) or (area.zone or "?"),
            onClick = function() FG.Search.GoToArea(target, area) end,
        }
    end
    Kit.Menu(anchor, rows)
end

function Panel.Get(parent) return f or Build(parent) end
