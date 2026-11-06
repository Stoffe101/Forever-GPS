-- A fake of WoW's widget system that really lays frames out.
--
-- Frames, textures and font strings resolve their anchors to rectangles as the
-- client does, so tests can ask whether text clips, controls overlap or a
-- window leaves the screen at a given UI size. Font metrics are estimated, so
-- the numbers are close rather than exact: good for catching layouts that do
-- not fit, not for pixel-perfect claims.
--
-- Widget methods this file does not implement resolve to a recording no-op
-- (see UI.unknown), which lets upstream's large UI load. ForeverGPS's own calls
-- are held to a real list by tests/test_static.lua.
local UI = { unknown = {}, frames = {}, tickers = {}, epoch = 0 }

local mmax, mmin = math.max, math.min

local function round(v) return math.floor(v * 100 + 0.5) / 100 end

-- ==== text ==================================================================

local WIDE = "mwMW@%"
local NARROW = "ijlI.,:;'|!ft"

local function stripMarkup(s)
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = s:gsub("|T.-|t", "XX"):gsub("|A.-|a", "XX")
    s = s:gsub("|H.-|h(.-)|h", "%1")
    return s
end
UI.stripMarkup = stripMarkup

local function charWidth(ch, size)
    if ch == " " then return size * 0.3 end
    if WIDE:find(ch, 1, true) then return size * 0.92 end
    if NARROW:find(ch, 1, true) then return size * 0.33 end
    if ch:match("%u") then return size * 0.72 end
    if ch:match("%d") then return size * 0.66 end
    return size * 0.58
end

local function textWidth(s, size)
    local w = 0
    for ch in stripMarkup(s):gmatch(utf8 and utf8.charpattern or ".") do
        w = w + charWidth(ch:sub(1, 1), size)
    end
    return math.ceil(w)
end
UI.textWidth = textWidth

-- ==== regions ===============================================================

local Region = {}

local function newObject(kind, parent, name)
    local o = {
        _kind = kind, _parent = parent, _name = name, _points = {}, _shown = true, _scale = 1, _alpha = 1,
        _scripts = {}, _events = {}, _children = {}, _regions = {}, _level = 1, _strata = "MEDIUM",
    }
    if parent then
        local list = (kind == "Texture" or kind == "FontString") and parent._regions or parent._children
        list[#list + 1] = o
    end
    return o
end

function Region:GetObjectType() return self._kind end
function Region:IsObjectType(k) return self._kind == k end
function Region:GetName() return self._name end
function Region:GetParent() return self._parent end
function Region:SetParent(p)
    local old = self._parent
    if old then
        local list = (self._kind == "Texture" or self._kind == "FontString") and old._regions or old._children
        for i = #list, 1, -1 do
            if list[i] == self then table.remove(list, i) end
        end
    end
    self._parent = p
    if p then
        local list = (self._kind == "Texture" or self._kind == "FontString") and p._regions or p._children
        list[#list + 1] = self
    end
end
function Region:IsForbidden() return false end

function Region:SetPoint(point, a, b, c, d)
    local rel, relPoint, x, y
    if type(a) == "number" then x, y = a, b
    else
        rel = a
        if type(b) == "number" then x, y = b, c
        else relPoint, x, y = b, c, d end
    end
    if type(rel) == "string" then rel = UI.named and UI.named[rel] end
    for i = 1, #self._points do
        if self._points[i].point == point then table.remove(self._points, i) break end
    end
    self._points[#self._points + 1] = { point = point, rel = rel, relPoint = relPoint or point, x = x or 0, y = y or 0 }
    UI.epoch = (UI.epoch or 0) + 1
end
function Region:ClearAllPoints() self._points = {} UI.epoch = (UI.epoch or 0) + 1 end
function Region:GetNumPoints() return #self._points end
function Region:GetPoint(i)
    local p = self._points[i or 1]
    if p then return p.point, p.rel, p.relPoint, p.x, p.y end
end
function Region:SetAllPoints(rel)
    self:ClearAllPoints()
    rel = rel or self._parent
    self:SetPoint("TOPLEFT", rel, "TOPLEFT", 0, 0)
    self:SetPoint("BOTTOMRIGHT", rel, "BOTTOMRIGHT", 0, 0)
end
function Region:SetSize(w, h) self._w, self._h = w, h or w UI.epoch = (UI.epoch or 0) + 1 end
function Region:SetWidth(w) self._w = w UI.epoch = (UI.epoch or 0) + 1 end
function Region:SetHeight(h) self._h = h UI.epoch = (UI.epoch or 0) + 1 end
function Region:SetScale(s) self._scale = s UI.epoch = (UI.epoch or 0) + 1 end
function Region:GetScale() return self._scale end
function Region:GetEffectiveScale()
    local s, p = self._scale or 1, self._parent
    while p do s, p = s * (p._scale or 1), p._parent end
    return s
end
function Region:SetAlpha(a) self._alpha = a end
function Region:GetAlpha() return self._alpha end
function Region:GetEffectiveAlpha()
    local a, p = self._alpha or 1, self._parent
    while p do a, p = a * (p._alpha or 1), p._parent end
    return a
end
function Region:Show()
    if self._shown then return end
    self._shown = true
    if self._scripts.OnShow and self:IsVisible() then self._scripts.OnShow(self) end
end
function Region:Hide()
    if not self._shown then return end
    local was = self:IsVisible()
    self._shown = false
    if was and self._scripts.OnHide then self._scripts.OnHide(self) end
end
function Region:SetShown(v) if v then self:Show() else self:Hide() end end
function Region:IsShown() return self._shown end
function Region:IsVisible()
    local o = self
    while o do
        if not o._shown then return false end
        o = o._parent
    end
    return true
end

-- The screen rectangle: resolved per axis from the anchors, in screen pixels.
local H_OF = { LEFT = 0, TOPLEFT = 0, BOTTOMLEFT = 0, CENTER = 0.5, TOP = 0.5, BOTTOM = 0.5, RIGHT = 1, TOPRIGHT = 1, BOTTOMRIGHT = 1 }
local V_OF = { TOP = 1, TOPLEFT = 1, TOPRIGHT = 1, CENTER = 0.5, LEFT = 0.5, RIGHT = 0.5, BOTTOM = 0, BOTTOMLEFT = 0, BOTTOMRIGHT = 0 }

local rectOf
local function anchorPos(obj, p)
    local rel = p.rel or obj._parent
    local r = rel and rectOf(rel)
    if not r then return nil end
    local scale = obj:GetEffectiveScale()
    return r.l + (r.r - r.l) * H_OF[p.relPoint] + p.x * scale, r.b + (r.t - r.b) * V_OF[p.relPoint] + p.y * scale
end

rectOf = function(obj)
    if obj._cacheEpoch == UI.epoch and obj._rect then return obj._rect end
    if obj._resolving then return nil end
    obj._resolving = true
    local scale = obj:GetEffectiveScale()
    local left, right, cx, top, bottom, cy
    for i = 1, #obj._points do
        local p = obj._points[i]
        local x, y = anchorPos(obj, p)
        if x then
            local h, v = H_OF[p.point], V_OF[p.point]
            if h == 0 then left = x elseif h == 1 then right = x else cx = x end
            if v == 1 then top = y elseif v == 0 then bottom = y else cy = y end
        end
    end
    if (top or bottom) and cy then UI.NoteConflict(obj, "vertical") end
    if (left or right) and cx then UI.NoteConflict(obj, "horizontal") end
    local w = obj:_naturalWidth()
    local h = obj:_naturalHeight()
    w, h = w and w * scale, h and h * scale
    if left and right then w = right - left
    elseif left and w then right = left + w
    elseif right and w then left = right - w
    elseif cx and w then left, right = cx - w / 2, cx + w / 2
    elseif left and cx then right = cx + (cx - left) w = right - left
    elseif right and cx then left = cx - (right - cx) w = right - left end
    if top and bottom then h = top - bottom
    elseif top and h then bottom = top - h
    elseif bottom and h then top = bottom + h
    elseif cy and h then bottom, top = cy - h / 2, cy + h / 2
    elseif top and cy then bottom = cy - (top - cy) h = top - bottom
    elseif bottom and cy then top = cy + (cy - bottom) h = top - bottom end
    obj._resolving = nil
    if not (left and right and top and bottom) then return nil end
    obj._rect, obj._cacheEpoch = { l = left, r = right, t = top, b = bottom }, UI.epoch
    return obj._rect
end
UI.rectOf = rectOf

-- The client derives a size from any two anchors on an axis. A top with a center
-- (TOPLEFT plus RIGHT is the usual slip) gives a height nobody meant: recorded here
-- so a test can refuse it.
UI.conflicts = {}
function UI.NoteConflict(obj, axis)
    local parts = {}
    for i = 1, #obj._points do parts[i] = obj._points[i].point end
    local key = axis .. " " .. table.concat(parts, "+") .. " on " .. (obj._kind or "?") .. " " .. tostring(obj._text or obj._name or "")
    UI.conflicts[key] = (UI.conflicts[key] or 0) + 1
end

function Region:_naturalWidth() return self._w end
function Region:_naturalHeight() return self._h end
function Region:GetWidth()
    local r = rectOf(self)
    if r then return (r.r - r.l) / self:GetEffectiveScale() end
    return self:_naturalWidth() or 0
end
function Region:GetHeight()
    local r = rectOf(self)
    if r then return (r.t - r.b) / self:GetEffectiveScale() end
    return self:_naturalHeight() or 0
end
function Region:GetSize() return self:GetWidth(), self:GetHeight() end
function Region:GetLeft() local r = rectOf(self) return r and r.l / self:GetEffectiveScale() end
function Region:GetRight() local r = rectOf(self) return r and r.r / self:GetEffectiveScale() end
function Region:GetTop() local r = rectOf(self) return r and r.t / self:GetEffectiveScale() end
function Region:GetBottom() local r = rectOf(self) return r and r.b / self:GetEffectiveScale() end
function Region:GetCenter()
    local r = rectOf(self)
    if not r then return nil end
    local s = self:GetEffectiveScale()
    return (r.l + r.r) / 2 / s, (r.t + r.b) / 2 / s
end
function Region:GetRect()
    local r = rectOf(self)
    if not r then return nil end
    local s = self:GetEffectiveScale()
    return r.l / s, r.b / s, (r.r - r.l) / s, (r.t - r.b) / s
end
function Region:IsMouseOver() return UI.mouseOver == self end

-- ==== textures ==============================================================

local Texture = setmetatable({}, { __index = Region })
function Texture:SetTexture(t) self._tex = t self._color = nil end
function Texture:GetTexture() return self._tex end
function Texture:SetColorTexture(r, g, b, a) self._color = { r, g, b, a or 1 } self._tex = nil end
function Texture:SetVertexColor(r, g, b, a) self._tint = { r, g, b, a or 1 } end
function Texture:GetVertexColor() local c = self._tint or { 1, 1, 1, 1 } return c[1], c[2], c[3], c[4] end
function Texture:SetTexCoord(...) self._coords = { ... } end
function Texture:SetRotation(r) self._rotation = r end
function Texture:GetRotation() return self._rotation or 0 end
function Texture:SetAtlas(a) self._atlas = a end
function Texture:SetBlendMode(m) self._blend = m end
function Texture:SetDrawLayer(l, s) self._layer = l self._sub = s end
function Texture:SetDesaturated(v) self._desat = v end
function Texture:SetVertexOffset(i, x, y)
    self._vertex = self._vertex or {}
    self._vertex[i] = { x, y }
end
function Texture:SetSnapToPixelGrid() end
function Texture:SetTexelSnappingBias() end
function Texture:SetHorizTile() end
function Texture:SetVertTile() end
function Texture:SetGradient() end

-- ==== font strings ==========================================================

local FontString = setmetatable({}, { __index = Region })
function FontString:SetText(t) self._text = t and tostring(t) or "" UI.epoch = (UI.epoch or 0) + 1 end
function FontString:SetFormattedText(f, ...) self:SetText(f:format(...)) end
function FontString:GetText() return self._text or "" end
function FontString:SetFont(file, size, flags)
    self._font, self._size, self._flags = file, size, flags
    UI.epoch = (UI.epoch or 0) + 1
    return true
end
function FontString:GetFont() return self._font or "Fonts\\FRIZQT__.TTF", self._size or 12, self._flags end
function FontString:SetFontObject(o)
    self._fontObject = o
    if type(o) == "table" and o._size then self._size = o._size end
end
function FontString:SetTextColor(r, g, b, a) self._color = { r, g, b, a or 1 } end
function FontString:GetTextColor() local c = self._color or { 1, 1, 1, 1 } return c[1], c[2], c[3], c[4] end
function FontString:SetJustifyH(j) self._justifyH = j end
function FontString:SetJustifyV(j) self._justifyV = j end
function FontString:SetWordWrap(v) self._wrap = v end
function FontString:SetNonSpaceWrap() end
function FontString:SetMaxLines(n) self._maxLines = n end
function FontString:SetSpacing(s) self._spacing = s end
function FontString:SetShadowColor() end
function FontString:SetShadowOffset() end
function FontString:SetDrawLayer() end
function FontString:SetIndentedWordWrap() end

local function explicitWidth(fs)
    if fs._w then return fs._w end
    local has = {}
    for i = 1, #fs._points do
        local h = H_OF[fs._points[i].point]
        has[h] = true
    end
    if has[0] and has[1] then
        local r = rectOf(fs)
        return r and (r.r - r.l) / fs:GetEffectiveScale() or nil
    end
    return nil
end

-- Lines of wrapped text at the width, each a width in units.
local function layout(fs, width)
    local size = select(2, fs:GetFont())
    local lines, text = {}, stripMarkup(fs._text or "")
    if text == "" then return lines, size end
    for para in (text .. "\n"):gmatch("(.-)\n") do
        if not (width and fs._wrap ~= false) then
            lines[#lines + 1] = textWidth(para, size)
        else
            local cur = 0
            for word in para:gmatch("%S+") do
                local w = textWidth(word, size)
                local gap = cur > 0 and size * 0.28 or 0
                if cur > 0 and cur + gap + w > width then
                    lines[#lines + 1] = cur
                    cur = w
                else
                    cur = cur + gap + w
                end
            end
            lines[#lines + 1] = cur
        end
    end
    return lines, size
end

function FontString:_naturalWidth()
    if self._w then return self._w end
    local lines = layout(self, nil)
    local w = 0
    for i = 1, #lines do w = mmax(w, lines[i]) end
    return w
end
function FontString:_naturalHeight()
    if self._h then return self._h end
    local width
    local has = {}
    for i = 1, #self._points do has[H_OF[self._points[i].point]] = self._points[i] end
    if self._w then
        width = self._w
    elseif has[0] and has[1] then
        local a, b = anchorPos(self, has[0]), anchorPos(self, has[1])
        if a and b then width = (b - a) / self:GetEffectiveScale() end
    end
    local lines, size = layout(self, width)
    local n = mmax(1, #lines)
    if self._maxLines and self._maxLines > 0 then n = mmin(n, self._maxLines) end
    return n * (size * 1.22 + (self._spacing or 0))
end
function FontString:GetStringWidth()
    local lines = layout(self, explicitWidth(self))
    local w = 0
    for i = 1, #lines do w = mmax(w, lines[i]) end
    return w
end
function FontString:GetUnboundedStringWidth()
    local lines = layout(self, nil)
    local w = 0
    for i = 1, #lines do w = mmax(w, lines[i]) end
    return w
end
function FontString:GetStringHeight() return self:_naturalHeight() end
function FontString:GetNumLines() return #(layout(self, explicitWidth(self))) end
function FontString:GetLineHeight() return select(2, self:GetFont()) * 1.22 end
function FontString:IsTruncated()
    local width = explicitWidth(self)
    local lines = layout(self, width)
    if self._wrap == false and width then
        return lines[1] ~= nil and lines[1] > width + 0.5
    end
    if self._maxLines and self._maxLines > 0 and #lines > self._maxLines then return true end
    return false
end

-- ==== frames ================================================================

local Frame = setmetatable({}, { __index = Region })
function Frame:SetScript(name, fn) self._scripts[name] = fn UI.track(self) end
function Frame:GetScript(name) return self._scripts[name] end
function Frame:HasScript() return true end
function Frame:HookScript(name, fn)
    local prev = self._scripts[name]
    self._scripts[name] = function(...)
        if prev then prev(...) end
        fn(...)
    end
    UI.track(self)
end
function Frame:RegisterEvent(e) self._events[e] = true UI.track(self) end
function Frame:RegisterUnitEvent(e) self._events[e] = true UI.track(self) end
function Frame:UnregisterEvent(e) self._events[e] = nil end
function Frame:UnregisterAllEvents() self._events = {} end
function Frame:IsEventRegistered(e) return self._events[e] == true end
function Frame:CreateTexture(name, layer)
    local t = setmetatable(newObject("Texture", self, name), UI.mt.Texture)
    t._layer = layer
    return t
end
function Frame:CreateMaskTexture(name) return self:CreateTexture(name) end
function Frame:CreateFontString(name, layer, inherits)
    local f = setmetatable(newObject("FontString", self, name), UI.mt.FontString)
    f._layer = layer
    f._inherits = inherits
    if type(inherits) == "string" then f._size = 12 end
    return f
end
function Frame:CreateLine(name) return self:CreateTexture(name) end
function Frame:CreateAnimationGroup()
    return setmetatable({}, { __index = function(_, k)
        if k == "CreateAnimation" then
            return function() return setmetatable({}, { __index = function() return function() end end }) end
        end
        if k == "IsPlaying" then return function() return false end end
        return function() end
    end })
end
function Frame:SetFrameStrata(s) self._strata = s end
function Frame:GetFrameStrata() return self._strata end
function Frame:SetFrameLevel(l) self._level = l end
function Frame:GetFrameLevel() return self._level end
function Frame:SetToplevel() end
function Frame:SetClampedToScreen(v) self._clamped = v end
function Frame:IsClampedToScreen() return self._clamped end
function Frame:SetClampRectInsets() end
function Frame:SetMovable(v) self._movable = v end
function Frame:IsMovable() return self._movable end
function Frame:SetResizable(v) self._resizable = v end
function Frame:SetResizeBounds(a, b, c, d) self._bounds = { a, b, c, d } end
function Frame:EnableMouse(v) self._mouse = v end
function Frame:IsMouseEnabled() return self._mouse end
function Frame:EnableMouseWheel(v) self._wheel = v end
function Frame:EnableKeyboard(v) self._keyboard = v end
function Frame:SetPropagateKeyboardInput() end
function Frame:SetPropagateMouseClicks() end
function Frame:SetPropagateMouseMotion() end
function Frame:SetClipsChildren(v) self._clips = v end
function Frame:DoesClipChildren() return self._clips end
function Frame:RegisterForDrag() end
function Frame:StartMoving() end
function Frame:StartSizing() end
function Frame:StopMovingOrSizing() end
function Frame:SetUserPlaced() end
function Frame:SetHitRectInsets() end
function Frame:SetDontSavePosition() end
function Frame:SetFixedFrameStrata() end
function Frame:SetFixedFrameLevel() end
function Frame:SetIgnoreParentScale() end
function Frame:SetIgnoreParentAlpha() end
function Frame:Raise() end
function Frame:Lower() end
function Frame:GetChildren() return table.unpack(self._children) end
function Frame:GetRegions() return table.unpack(self._regions) end
function Frame:SetAttribute(k, v) self._attr = self._attr or {} self._attr[k] = v end
function Frame:GetAttribute(k) return self._attr and self._attr[k] end
function Frame:SetBackdrop() end
function Frame:SetBackdropColor() end
function Frame:SetBackdropBorderColor() end
function Frame:ApplyBackdrop() end

-- Buttons
local Button = setmetatable({}, { __index = Frame })
function Button:RegisterForClicks(...) self._clicks = { ... } end
function Button:Click(button)
    if self._disabled then return end
    if self._scripts.OnClick then self._scripts.OnClick(self, button or "LeftButton") end
end
function Button:Enable() self._disabled = nil end
function Button:Disable() self._disabled = true end
function Button:SetEnabled(v) self._disabled = not v or nil end
function Button:IsEnabled() return not self._disabled end
function Button:SetNormalTexture(t) self._normal = t end
function Button:SetCheckedTexture(t) self._checkedTex = t end
function Button:GetCheckedTexture() self._checkedObj = self._checkedObj or self:CreateTexture() return self._checkedObj end
function Button:SetChecked(v) self._checked = v end
function Button:GetChecked() return self._checked end
function Button:SetHighlightTexture(t) self._highlight = t end
function Button:SetPushedTexture(t) self._pushed = t end
function Button:SetDisabledTexture(t) self._disabledTex = t end
function Button:GetNormalTexture() self._normalObj = self._normalObj or self:CreateTexture() return self._normalObj end
function Button:GetHighlightTexture() return self._highlightObj or self:CreateTexture() end
function Button:GetPushedTexture() return self._pushedObj or self:CreateTexture() end
function Button:SetText(t) self._text = t end
function Button:GetText() return self._text end
function Button:SetFontString(fs) self._fs = fs end
function Button:GetFontString() return self._fs end

-- EditBoxes
local EditBox = setmetatable({}, { __index = Frame })
function EditBox:SetText(t)
    self._text = t or ""
    if self._scripts.OnTextChanged then self._scripts.OnTextChanged(self, false) end
end
function EditBox:GetText() return self._text or "" end
function EditBox:SetFontObject() end
function EditBox:SetFont(file, size, flags) self._font, self._size, self._flags = file, size, flags return true end
function EditBox:GetFont() return self._font, self._size or 12, self._flags end
function EditBox:SetTextColor() end
function EditBox:SetAutoFocus(v) self._autoFocus = v end
function EditBox:SetFocus() self._focused = true UI.focus = self if self._scripts.OnEditFocusGained then self._scripts.OnEditFocusGained(self) end end
function EditBox:ClearFocus()
    self._focused = nil
    if UI.focus == self then UI.focus = nil end
    if self._scripts.OnEditFocusLost then self._scripts.OnEditFocusLost(self) end
end
function EditBox:HasFocus() return self._focused == true end
function EditBox:SetMaxLetters() end
function EditBox:SetMultiLine() end
function EditBox:SetTextInsets() end
function EditBox:SetJustifyH() end
function EditBox:SetAltArrowKeyMode() end
function EditBox:HighlightText() end
function EditBox:SetCursorPosition() end
function EditBox:GetCursorPosition() return #(self._text or "") end
function EditBox:Insert(t) self:SetText((self._text or "") .. t) end
function EditBox:IsAutoFocus() return self._autoFocus end
function EditBox:SetHistoryLines() end
function EditBox:SetShadowColor() end
function EditBox:SetShadowOffset() end

-- Scroll frames, status bars, sliders, cooldowns, map canvases and so on
local ScrollFrame = setmetatable({}, { __index = Frame })
function ScrollFrame:SetScrollChild(c) self._child = c end
function ScrollFrame:GetScrollChild() return self._child end
function ScrollFrame:SetVerticalScroll(v) self._vscroll = v end
function ScrollFrame:GetVerticalScroll() return self._vscroll or 0 end
function ScrollFrame:SetHorizontalScroll() end
function ScrollFrame:GetHorizontalScroll() return 0 end
function ScrollFrame:GetVerticalScrollRange() return 0 end
function ScrollFrame:UpdateScrollChildRect() end

local StatusBar = setmetatable({}, { __index = Frame })
function StatusBar:SetMinMaxValues(a, b) self._min, self._max = a, b end
function StatusBar:GetMinMaxValues() return self._min or 0, self._max or 1 end
function StatusBar:SetValue(v) self._value = v end
function StatusBar:GetValue() return self._value or 0 end
function StatusBar:SetStatusBarTexture(t) self._barTex = t end
function StatusBar:SetStatusBarColor(r, g, b, a) self._barColor = { r, g, b, a or 1 } end
function StatusBar:GetStatusBarTexture() return self:CreateTexture() end
function StatusBar:SetOrientation() end
function StatusBar:SetFillStyle() end

local Slider = setmetatable({}, { __index = Frame })
function Slider:SetMinMaxValues(a, b) self._min, self._max = a, b end
function Slider:GetMinMaxValues() return self._min or 0, self._max or 1 end
function Slider:SetValue(v)
    self._value = v
    if self._scripts.OnValueChanged then self._scripts.OnValueChanged(self, v, false) end
end
function Slider:GetValue() return self._value or 0 end
function Slider:SetValueStep() end
function Slider:SetObeyStepOnDrag() end
function Slider:SetOrientation() end
function Slider:SetThumbTexture() end
function Slider:GetThumbTexture() return self:CreateTexture() end

-- ==== construction ==========================================================

-- A widget method by its verb; other capitalized keys are child fields
-- (frame.Texture) that are simply unset.
local VERBS = { "Set", "Get", "Is", "Has", "Can", "Enable", "Disable", "Register", "Unregister", "Create", "Clear", "Add", "Remove",
    "Stop", "Start", "Play", "Reset", "Update", "Refresh", "Show", "Hide", "Lock", "Unlock", "Adjust", "Flash", "Attach", "Detach" }
function UI.IsMethodName(k)
    for i = 1, #VERBS do
        if k:sub(1, #VERBS[i]) == VERBS[i] and k:sub(#VERBS[i] + 1, #VERBS[i] + 1):match("^%u?$") then return true end
    end
    return false
end

UI.mt = {}
local function makeMt(class)
    return {
        __index = function(t, k)
            local m = class[k]
            if m ~= nil then return m end
            -- Lowercase and underscored keys are fields; CamelCase names are
            -- widget methods, unknown to this fake: recorded, doing nothing.
            if type(k) == "string" and UI.IsMethodName(k) then
                return function()
                    UI.unknown[k] = (UI.unknown[k] or 0) + 1
                end
            end
            return nil
        end,
    }
end
UI.mt.Texture = makeMt(Texture)
UI.mt.FontString = makeMt(FontString)
UI.mt.Frame = makeMt(Frame)
UI.mt.Button = makeMt(Button)
UI.mt.EditBox = makeMt(EditBox)
UI.mt.ScrollFrame = makeMt(ScrollFrame)
UI.mt.StatusBar = makeMt(StatusBar)
UI.mt.Slider = makeMt(Slider)
UI.classes = { Texture = Texture, FontString = FontString, Frame = Frame, Button = Button, EditBox = EditBox, Slider = Slider }

local KIND = { CheckButton = "Button", DropdownButton = "Button" }

function UI.track(f)
    if not f._tracked then
        f._tracked = true
        UI.frames[#UI.frames + 1] = f
    end
end

function UI.CreateFrame(kind, name, parent)
    kind = KIND[kind] or kind or "Frame"
    local mt = UI.mt[kind] or UI.mt.Frame
    if parent == nil and UI.root then parent = nil end
    local f = setmetatable(newObject(kind, parent, name), mt)
    if parent then f._level = (parent._level or 0) + 1 end
    if name then
        UI.named = UI.named or {}
        UI.named[name] = f
    end
    if kind == "Frame" or UI.mt[kind] then UI.track(f) end
    return f
end

-- The screen: pixels wide and tall, and the UI scale, so UIParent holds
-- pixels / scale units, as the client's does.
function UI.NewScreen(pixelsW, pixelsH, scale)
    local root = UI.CreateFrame("Frame", "UIParent", nil)
    root._isRoot = true
    root._scale = scale or 1
    root._w, root._h = pixelsW / (scale or 1), pixelsH / (scale or 1)
    root._rect = { l = 0, r = pixelsW, t = pixelsH, b = 0 }
    root._cacheEpoch = nil
    -- The root's rectangle is the screen, whatever the epoch.
    function root:_screenRect() return self._rect end
    UI.root = root
    return root
end

local baseRect = rectOf
rectOf = function(obj)
    if obj._isRoot then return obj._rect end
    return baseRect(obj)
end
UI.rectOf = rectOf

-- Scripts on update, for every shown frame that has one.
function UI.RunUpdates(dt)
    for i = 1, #UI.frames do
        local f = UI.frames[i]
        local fn = f._scripts.OnUpdate
        if fn and f:IsVisible() then fn(f, dt) end
    end
end

function UI.Fire(event, ...)
    for i = 1, #UI.frames do
        local f = UI.frames[i]
        if f._events[event] and f._scripts.OnEvent then f._scripts.OnEvent(f, event, ...) end
    end
end

-- Walks a frame and everything under it: visit(obj, depth).
function UI.Walk(frame, visit, depth)
    depth = depth or 0
    visit(frame, depth)
    for i = 1, #frame._regions do
        if frame._regions[i]._shown then visit(frame._regions[i], depth + 1) end
    end
    for i = 1, #frame._children do
        if frame._children[i]._shown then UI.Walk(frame._children[i], visit, depth + 1) end
    end
end

UI.round = round

return UI
