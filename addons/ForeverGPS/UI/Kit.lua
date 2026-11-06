-- The widgets everything is built from. No templates: every piece is drawn here,
-- so the look stays one thing and nothing depends on Blizzard's frame art.
local _, FG = ...
local Kit = {}
FG.Kit = Kit

local Theme = FG.Theme
local C = Theme.C

local ROUNDED = FG.ART .. "rounded"
local ROUNDED_LINE = FG.ART .. "rounded-line"
local CORNER = 16 / 64       -- the texture's corner, as a share of it

local function Color(texture, color)
    texture:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
end
Kit.Tint = Color

local function Smooth(texture)
    if texture.SetSnapToPixelGrid then texture:SetSnapToPixelGrid(false) end
    if texture.SetTexelSnappingBias then texture:SetTexelSnappingBias(0) end
end

-- A rounded shape behind or on a frame: nine textures, tinted together.
-- shape:SetColor(color) recolors it.
function Kit.Shape(frame, radius, layer, sublevel, outline)
    local file = outline and ROUNDED_LINE or ROUNDED
    local a, b = CORNER, 1 - CORNER
    local parts = {}
    local function Part(l, r, t, u)
        local tex = frame:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel or 0)
        tex:SetTexture(file)
        tex:SetTexCoord(l, r, t, u)
        Smooth(tex)
        parts[#parts + 1] = tex
        return tex
    end
    local tl, tr, bl, br = Part(0, a, 0, a), Part(b, 1, 0, a), Part(0, a, b, 1), Part(b, 1, b, 1)
    tl:SetSize(radius, radius)
    tr:SetSize(radius, radius)
    bl:SetSize(radius, radius)
    br:SetSize(radius, radius)
    tl:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    tr:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    bl:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    br:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    local top, bottom = Part(a, b, 0, a), Part(a, b, b, 1)
    top:SetPoint("TOPLEFT", tl, "TOPRIGHT", 0, 0)
    top:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("TOPLEFT", bl, "TOPRIGHT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT", 0, 0)
    local left, right = Part(0, a, a, b), Part(b, 1, a, b)
    left:SetPoint("TOPLEFT", tl, "BOTTOMLEFT", 0, 0)
    left:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT", 0, 0)
    right:SetPoint("TOPLEFT", tr, "BOTTOMLEFT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT", 0, 0)
    local middle = Part(a, b, a, b)
    middle:SetPoint("TOPLEFT", tl, "BOTTOMRIGHT", 0, 0)
    middle:SetPoint("BOTTOMRIGHT", br, "TOPLEFT", 0, 0)
    local shape = {}
    function shape:SetColor(color)
        for i = 1, #parts do Color(parts[i], color) end
    end
    function shape:SetShown(on)
        for i = 1, #parts do parts[i]:SetShown(on) end
    end
    return shape
end

-- ==== text ==================================================================

-- A font that fails to load would leave the string unable to take text at all,
-- which would take the whole interface down with it.
function Kit.SetStyle(fs, style)
    local s = Theme.TEXT[style] or Theme.TEXT.body
    if not fs:SetFont(Theme.FONT[s[1]], s[2], "") then
        fs:SetFont(STANDARD_TEXT_FONT, s[2], "")
    end
end

-- A font string. color: a key of the palette. lines: 0 wraps freely; a number
-- caps it; nil keeps it on one line, cut with an ellipsis if it must be.
function Kit.Text(parent, style, color, lines)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    Kit.SetStyle(fs, style)
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    if lines then
        fs:SetWordWrap(true)
        if lines > 0 then fs:SetMaxLines(lines) end
    else
        fs:SetWordWrap(false)
    end
    fs.colorKey = color or "text"
    Theme.Paint(function(c)
        local v = c[fs.colorKey] or c.text
        fs:SetTextColor(v[1], v[2], v[3], v[4] or 1)
    end)
    function fs:SetColorKey(key)
        self.colorKey = key
        local v = C[key] or C.text
        self:SetTextColor(v[1], v[2], v[3], v[4] or 1)
    end
    return fs
end

-- ==== icons =================================================================

-- A square icon. SetIcon takes a file in Art ("boat"), a game file id, an
-- "atlas:" name, or a path. Art glyphs are tinted; game icons keep their colors.
function Kit.Icon(parent, size, color)
    local tex = parent:CreateTexture(nil, "ARTWORK")
    tex:SetSize(size, size)
    tex.colorKey = color or "glyph"
    local function Recolor()
        if tex.isGlyph then
            Color(tex, C[tex.colorKey] or C.glyph)
        else
            tex:SetVertexColor(1, 1, 1, 1)
        end
    end
    Theme.Paint(Recolor)
    function tex:SetIcon(icon)
        self.isGlyph = false
        if type(icon) == "string" and icon:find("^atlas:") then
            self:SetAtlas(icon:sub(7))
        elseif type(icon) == "string" and not icon:find("[\\/]") then
            self.isGlyph = true
            self:SetTexture(FG.ART .. icon)
        elseif icon then
            self:SetTexture(icon)
        end
        Recolor()
    end
    function tex:SetColorKey(key)
        self.colorKey = key
        Recolor()
    end
    return tex
end

-- ==== tooltips ==============================================================

-- Shows title and body on hover. Either may be a function, read when shown.
function Kit.Tooltip(widget, title, body)
    widget:HookScript("OnEnter", function(self)
        local t = type(title) == "function" and title() or title
        local b = type(body) == "function" and body() or body
        if not t then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(t, 1, 1, 1, 1, true)
        if b then GameTooltip:AddLine(b, 0.75, 0.78, 0.82, true) end
        GameTooltip:Show()
    end)
    widget:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- ==== buttons ===============================================================

local VARIANTS = {
    primary = { fill = "accent", hover = "accentHover", text = "onAccent" },
    ghost = { fill = "card", hover = "cardHover", text = "text", line = "line" },
    danger = { fill = "dangerSoft", hover = "dangerSoft", text = "danger", line = "danger" },
}

-- opts: text, icon, variant, height, width (nil fits the text), onClick.
function Kit.Button(parent, opts)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(opts.height or 30)
    b:RegisterForClicks("LeftButtonUp")
    b.fill = Kit.Shape(b, 6, "BACKGROUND", 1)
    b.edge = Kit.Shape(b, 6, "BACKGROUND", 2, true)
    b.label = Kit.Text(b, "label", "text")
    b.label:SetJustifyH("CENTER")
    b.label:SetJustifyV("MIDDLE")
    b.variant = opts.variant or "ghost"
    if opts.icon then
        b.glyph = Kit.Icon(b, 14, "text")
        b.glyph:SetIcon(opts.icon)
    end
    function b:Paint()
        local v = VARIANTS[self.variant]
        local hot = self:IsEnabled() and self:IsMouseOver()
        self.fill:SetColor(C[hot and v.hover or v.fill])
        self.edge:SetShown(v.line ~= nil)
        if v.line then self.edge:SetColor(C[v.line]) end
        self.label:SetColorKey(self:IsEnabled() and v.text or "textFaint")
        if self.glyph then self.glyph:SetColorKey(self:IsEnabled() and v.text or "textFaint") end
    end
    function b:Place()
        self.label:ClearAllPoints()
        local w = self.label:GetStringWidth()
        if self.glyph and w == 0 then
            self.glyph:ClearAllPoints()
            self.glyph:SetPoint("CENTER", self, "CENTER", 0, 0)
            self.label:SetPoint("CENTER", self, "CENTER", 0, 0)
        elseif self.glyph then
            self.glyph:ClearAllPoints()
            self.glyph:SetPoint("CENTER", self, "CENTER", -(w + 6) / 2, 0)
            self.label:SetPoint("LEFT", self.glyph, "RIGHT", 6, 0)
        else
            self.label:SetPoint("CENTER", self, "CENTER", 0, 0)
        end
        if opts.width == "fit" then self:SetWidth(w + (self.glyph and 40 or 24)) end
    end
    function b:SetLabel(text)
        self.label:SetText(text)
        self:Place()
    end
    function b:SetVariant(name)
        self.variant = name
        self:Paint()
    end
    b:SetScript("OnEnter", function(self) self:Paint() end)
    b:SetScript("OnLeave", function(self) self:Paint() end)
    b:SetScript("OnEnable", function(self) self:Paint() end)
    b:SetScript("OnDisable", function(self) self:Paint() end)
    if opts.onClick then b:SetScript("OnClick", function(self) opts.onClick(self) end) end
    if type(opts.width) == "number" then b:SetWidth(opts.width) end
    b:SetLabel(opts.text or "")
    Theme.Paint(function() b:Paint() end)
    return b
end

-- A bare glyph that lights up under the cursor.
function Kit.IconButton(parent, icon, size, tip, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size + 8, size + 8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.glyph = Kit.Icon(b, size, "textDim")
    b.glyph:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.glyph:SetIcon(icon)
    b.back = Kit.Shape(b, 5, "BACKGROUND", 1)
    b.back:SetShown(false)
    Theme.Paint(function(c) b.back:SetColor(c.cardHover) end)
    b:SetScript("OnEnter", function(self)
        self.glyph:SetColorKey("text")
        self.back:SetShown(true)
    end)
    b:SetScript("OnLeave", function(self)
        self.glyph:SetColorKey(self.activeKey or "textDim")
        self.back:SetShown(false)
    end)
    if onClick then b:SetScript("OnClick", function(self, button) onClick(self, button) end) end
    if tip then Kit.Tooltip(b, tip) end
    -- A resting color other than the default (a saved star stays gold).
    function b:SetActiveColor(key)
        self.activeKey = key
        self.glyph:SetColorKey(key or "textDim")
    end
    return b
end

-- A pill that is on or off. Sizes itself to its text.
function Kit.Chip(parent, text, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(24)
    b:RegisterForClicks("LeftButtonUp")
    b.fill = Kit.Shape(b, 12, "BACKGROUND", 1)
    b.edge = Kit.Shape(b, 12, "BACKGROUND", 2, true)
    b.label = Kit.Text(b, "caption", "textDim")
    b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.label:SetJustifyV("MIDDLE")
    function b:Paint()
        local on, hot = self.selected, self:IsMouseOver()
        self.fill:SetColor(on and C.accent or hot and C.cardHover or C.card)
        self.edge:SetColor(on and C.accent or C.line)
        self.label:SetColorKey(on and "onAccent" or self.dim and "textFaint" or hot and "text" or "textDim")
    end
    function b:SetSelected(on)
        self.selected = on
        self:Paint()
    end
    function b:SetLabel(value)
        self.label:SetText(value)
        self:SetWidth(self.label:GetStringWidth() + 22)
    end
    b:SetScript("OnEnter", function(self) self:Paint() end)
    b:SetScript("OnLeave", function(self) self:Paint() end)
    b:SetScript("OnClick", function(self) onClick(self) end)
    b:SetLabel(text)
    Theme.Paint(function() b:Paint() end)
    return b
end

-- Lays chips left to right, wrapping at width; returns the height used.
function Kit.FlowChips(chips, parent, width, gap, y)
    local x, row = 0, 0
    for i = 1, #chips do
        local chip = chips[i]
        local w = chip:GetWidth()
        if x > 0 and x + w > width then
            x, row = 0, row + 1
        end
        chip:ClearAllPoints()
        chip:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - row * (chip:GetHeight() + gap))
        x = x + w + gap
    end
    return #chips > 0 and (row + 1) * (chips[1]:GetHeight() + gap) - gap or 0
end

-- ==== bars and rules ========================================================

function Kit.Rule(parent, color)
    local tex = parent:CreateTexture(nil, "BORDER")
    tex:SetHeight(1)
    Theme.Paint(function(c)
        local v = c[color or "line"]
        tex:SetColorTexture(v[1], v[2], v[3], v[4] or 1)
    end)
    return tex
end

-- A thin rounded progress bar. SetValue(0..1).
function Kit.Bar(parent, height, color)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(height)
    f.track = Kit.Shape(f, height / 2, "BACKGROUND", 1)
    f.fillFrame = CreateFrame("Frame", nil, f)
    f.fillFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    f.fillFrame:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    f.fill = Kit.Shape(f.fillFrame, height / 2, "ARTWORK", 1)
    f.colorKey = color or "accent"
    Theme.Paint(function(c)
        f.track:SetColor(c.line)
        f.fill:SetColor(c[f.colorKey])
    end)
    function f:SetValue(v)
        self.value = math.max(0, math.min(1, v or 0))
        self:Layout()
    end
    function f:SetColorKey(key)
        self.colorKey = key
        self.fill:SetColor(C[key])
    end
    function f:Layout()
        local w = self:GetWidth() or 0
        self.fillFrame:SetWidth(math.max(height, w * (self.value or 0)))
        self.fillFrame:SetShown((self.value or 0) > 0)
    end
    f:SetScript("OnSizeChanged", function(self) self:Layout() end)
    return f
end

-- ==== settings controls =====================================================

function Kit.Check(parent, label, get, set)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(24)
    b:RegisterForClicks("LeftButtonUp")
    b.box = CreateFrame("Frame", nil, b)
    b.box:SetSize(16, 16)
    b.box:SetPoint("LEFT", b, "LEFT", 0, 0)
    b.fill = Kit.Shape(b.box, 4, "BACKGROUND", 1)
    b.edge = Kit.Shape(b.box, 4, "BACKGROUND", 2, true)
    b.mark = Kit.Icon(b.box, 12, "onAccent")
    b.mark:SetPoint("CENTER", b.box, "CENTER", 0, 0)
    b.mark:SetIcon("check")
    b.label = Kit.Text(b, "body", "text")
    b.label:SetPoint("LEFT", b.box, "RIGHT", 8, 0)
    b.label:SetPoint("RIGHT", b, "RIGHT", 0, 0)
    b.label:SetText(label)
    function b:Sync()
        local on = get()
        self.fill:SetColor(on and C.accent or C.field)
        self.edge:SetColor(on and C.accent or C.lineStrong)
        self.mark:SetShown(on and true or false)
    end
    b:SetScript("OnClick", function(self)
        set(not get())
        self:Sync()
    end)
    Theme.Paint(function() b:Sync() end)
    return b
end

-- A row of chips, one chosen. choices: { { value, label }, ... }.
function Kit.Choice(parent, choices, get, set)
    local f = CreateFrame("Frame", nil, parent)
    f.chips = {}
    function f:Sync()
        for i = 1, #self.chips do self.chips[i]:SetSelected(self.chips[i].value == get()) end
    end
    for i = 1, #choices do
        local chip = Kit.Chip(f, choices[i][2], function(self)
            set(self.value)
            f:Sync()
        end)
        chip.value = choices[i][1]
        f.chips[i] = chip
    end
    function f:Layout(width)
        local h = Kit.FlowChips(self.chips, self, width, 6, 0)
        self:SetHeight(h)
        return h
    end
    f:Sync()
    return f
end

-- A slider drawn as a bar. step: its grain.
function Kit.Scale(parent, low, high, step, get, set)
    local s = CreateFrame("Slider", nil, parent)
    s:SetOrientation("HORIZONTAL")
    s:SetHeight(18)
    s:SetMinMaxValues(low, high)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    s:EnableMouse(true)
    s.track = s:CreateTexture(nil, "BACKGROUND")
    s.track:SetHeight(4)
    s.track:SetPoint("LEFT", s, "LEFT", 0, 0)
    s.track:SetPoint("RIGHT", s, "RIGHT", 0, 0)
    s.thumb = s:CreateTexture(nil, "ARTWORK")
    s.thumb:SetTexture(FG.ART .. "circle")
    s.thumb:SetSize(14, 14)
    s:SetThumbTexture(s.thumb)
    Theme.Paint(function(c)
        s.track:SetColorTexture(c.line[1], c.line[2], c.line[3], 1)
        Color(s.thumb, c.accent)
    end)
    s:SetValue(get())
    s:SetScript("OnValueChanged", function(_, value, user)
        if user then set(math.floor(value / step + 0.5) * step) end
    end)
    return s
end

-- ==== menus =================================================================

local menu

-- A small popup under the anchor. rows: { label, onClick } each.
function Kit.Menu(anchor, rows)
    if not menu then
        menu = CreateFrame("Frame", "ForeverGPSMenu", UIParent)
        menu:SetFrameStrata("TOOLTIP")
        menu:SetClampedToScreen(true)
        menu:EnableMouse(true)
        menu.back = Kit.Shape(menu, 8, "BACKGROUND", 1)
        menu.edge = Kit.Shape(menu, 8, "BACKGROUND", 2, true)
        Theme.Paint(function(c)
            menu.back:SetColor(c.raised)
            menu.edge:SetColor(c.lineStrong)
        end)
        menu.rows = {}
        menu:Hide()
        menu:SetScript("OnEvent", function(self)
            if self:IsMouseOver() then return end
            self:Hide()
        end)
        menu:SetScript("OnShow", function(self) self:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
        menu:SetScript("OnHide", function(self) self:UnregisterEvent("GLOBAL_MOUSE_DOWN") end)
    end
    local width = 150
    for i = 1, #rows do
        local b = menu.rows[i]
        if not b then
            b = CreateFrame("Button", nil, menu)
            b:SetHeight(24)
            b:RegisterForClicks("LeftButtonUp")
            b.hover = b:CreateTexture(nil, "BACKGROUND")
            b.hover:SetAllPoints(b)
            b.hover:Hide()
            Theme.Paint(function(c) b.hover:SetColorTexture(c.cardHover[1], c.cardHover[2], c.cardHover[3], 1) end)
            b.label = Kit.Text(b, "body", "text")
            b.label:SetPoint("LEFT", b, "LEFT", 10, 0)
            b.label:SetJustifyV("MIDDLE")
            b:SetScript("OnEnter", function(self) self.hover:Show() end)
            b:SetScript("OnLeave", function(self) self.hover:Hide() end)
            menu.rows[i] = b
        end
        b.label:SetText(rows[i].label)
        width = math.max(width, b.label:GetStringWidth() + 24)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -4 - (i - 1) * 24)
        b:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -4, -4 - (i - 1) * 24)
        b:SetScript("OnClick", function()
            menu:Hide()
            rows[i].onClick()
        end)
        b:Show()
    end
    for i = #rows + 1, #menu.rows do menu.rows[i]:Hide() end
    menu:SetSize(width + 8, #rows * 24 + 8)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
    menu:Show()
    return menu
end
