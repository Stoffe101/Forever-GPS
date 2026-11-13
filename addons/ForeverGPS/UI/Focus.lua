-- Where the controller is in Forever-GPS's window, and what its buttons do there.
--
-- Every page is reached the same way, without code of its own: whatever can be clicked
-- in the window in front (buttons, chips, checks, list rows, edit boxes, sliders) can be
-- focused, and the direction pressed picks the nearest one that way, as the eye would.
-- A virtual list (UI/List.lua) is moved through by its items, not its frames: going
-- past the last row on screen scrolls the next one in, so every item can be reached,
-- however long the list. A focused item that goes away (a filter, new prices) gives its
-- place to the nearest one left.
--
-- Surfaces stack: the window, then the route map, the on-screen keyboard, a dialog. The
-- one on top gets the buttons; Back closes it and returns to the one below.
local FG = ForeverGPS
local Focus = {}
FG.Focus = Focus

local Kit, Theme = FG.Kit, FG.Theme

local cur               -- { frame } or { list, index, key }
local surfaces = {}     -- extra layers above the window: { root, onAction, onBack, first }
local ring

-- ==== the highlight =========================================================

local function Ring()
    if ring then return ring end
    ring = CreateFrame("Frame", "ForeverGPSFocusRing", UIParent)
    ring:SetFrameStrata("TOOLTIP")
    ring.edge = Kit.Shape(ring, 8, "OVERLAY", 7, true)
    ring.glow = Kit.Shape(ring, 8, "OVERLAY", 6)
    Theme.Paint(function(c)
        local a = c.accent
        ring.edge:SetColor({ a[1], a[2], a[3], 1 })
        ring.glow:SetColor({ a[1], a[2], a[3], 0.16 })
    end)
    ring:Hide()
    return ring
end

local function Visible(frame)
    return frame and frame.IsVisible and frame:IsVisible() and frame:GetWidth() > 1 and frame:GetHeight() > 1
end

-- The frame on screen for the focus: a list row is whichever row shows that item now.
local function FrameOf(c)
    if not c then return nil end
    if c.list then
        for _, row in ipairs(c.list.shown or {}) do
            if row.index == c.index then
                -- A control picked inside the row (a chip, a card's button), while it is there.
                if c.pick and c.pick:GetParent() == row and Visible(c.pick) then return c.pick end
                -- A row of chips or a card: its first control, not the row.
                return c.inner and c.inner(row) or row
            end
        end
        return nil
    end
    return c.frame
end

local noted
local function Show()
    local r = Ring()
    local frame = FrameOf(cur)
    -- A move of the focus, for the controller report.
    if frame ~= noted and FG.Pad and FG.Pad.Note then
        noted = frame
        FG.Pad.Note("focus", frame and (frame:GetName() or frame:GetObjectType()) or "none")
    end
    local strength = FG.Pad and FG.Pad.Settings().highlight or "strong"
    if not (frame and Visible(frame) and FG.Pad and FG.Pad.InUse() and strength ~= "off") then return r:Hide() end
    local pad = strength == "strong" and 3 or 1
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", frame, "TOPLEFT", -pad, pad)
    r:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", pad, -pad)
    r.glow:SetShown(strength == "strong")
    r:Show()
end
Focus.Show = Show

-- ==== what can be focused ===================================================

local function Clickable(obj)
    local kind = obj.GetObjectType and obj:GetObjectType()
    if kind == "EditBox" then return true end
    if obj.padAdjust then return true end
    if kind == "Button" or kind == "CheckButton" then
        if obj.padSkip then return false end
        return obj:GetScript("OnClick") ~= nil or obj:GetScript("OnMouseUp") ~= nil
    end
    return false
end

-- Every focusable frame shown under root, with the virtual list it belongs to.
local function Collect(root, out, list)
    if not Visible(root) then return out end
    if root ~= ring and Clickable(root) then out[#out + 1] = { frame = root, list = list } end
    local children = { root:GetChildren() }
    for i = 1, #children do
        local child = children[i]
        Collect(child, out, root.padList and root or list)
    end
    return out
end

local function Center(frame)
    local l, b, w, h = frame:GetRect()
    if not l then return nil end
    local s = frame:GetEffectiveScale()
    return (l + w / 2) * s, (b + h / 2) * s, w * s, h * s
end

-- A frame's edges on screen: left, right, bottom, top.
local function Edges(frame)
    local x, y, w, h = Center(frame)
    if not x then return nil end
    return x - w / 2, x + w / 2, y - h / 2, y + h / 2
end

-- The gap between two spans, 0 when they overlap.
local function Gap(a1, a2, b1, b2)
    return math.max(0, b1 - a2, a1 - b2)
end

-- The nearest candidate in a direction, the way the eye reads a page (the "beam" rule of
-- television and console interfaces):
--
--   - left and right stay on the row: anything overlapping the focus's row that way wins
--     over anything above or below it, however near that is;
--   - up and down keep to the column: a control straight below wins, unless another lies
--     wholly nearer than it;
--   - otherwise, edge to edge: the gap along the direction once, the gap across it twice,
--     and how far the centres are apart across it, a little.
--
-- So a wide button beside the focus is next, though its centre is far off, and a column of
-- tabs is not walked when the row has something that way.
local DIRS = { up = { 0, 1 }, down = { 0, -1 }, left = { -1, 0 }, right = { 1, 0 } }
local function Nearest(from, candidates, dir)
    local fx, fy = Center(from)
    if not fx then return candidates[1] end
    local fl, fr, fb, ft = Edges(from)
    local d = DIRS[dir]
    local horizontal = d[1] ~= 0
    local best, bestScore, bestFar
    local beam, beamScore, beamNear
    for _, c in ipairs(candidates) do
        if c.frame ~= from then
            local x, y = Center(c.frame)
            if x then
                local l, r, b, t = Edges(c.frame)
                local dx, dy = x - fx, y - fy
                -- Its centre must lie that way.
                if dx * d[1] + dy * d[2] > 1 then
                    local along, far, across, offset, overlap
                    if horizontal then
                        along = d[1] > 0 and math.max(0, l - fr) or math.max(0, fl - r)
                        far = d[1] > 0 and (r - fr) or (fl - l)
                        across, offset = Gap(fb, ft, b, t), math.abs(dy)
                        overlap = math.min(ft, t) - math.max(fb, b)
                    else
                        along = d[2] > 0 and math.max(0, b - ft) or math.max(0, fb - t)
                        far = d[2] > 0 and (t - ft) or (fb - b)
                        across, offset = Gap(fl, fr, l, r), math.abs(dx)
                        overlap = math.min(fr, r) - math.max(fl, l)
                    end
                    if overlap > 1 then
                        local score = along + offset * 0.1
                        if not beamScore or score < beamScore then beam, beamScore, beamNear = c, score, along end
                    else
                        local score = along + across * 2 + offset * 0.1
                        if not bestScore or score < bestScore then best, bestScore, bestFar = c, score, far end
                    end
                end
            end
        end
    end
    if not beam then return best end
    if horizontal or not best or beamNear < bestFar then return beam end
    return beamScore <= bestScore and beam or best
end

-- ==== the surfaces ==========================================================

function Focus.Push(surface)
    surfaces[#surfaces + 1] = surface
    surface.saved = cur
    cur = nil
    Focus.First()
end

function Focus.Pop(surface)
    for i = #surfaces, 1, -1 do
        if surfaces[i] == surface then
            table.remove(surfaces, i)
            cur = surface.saved
            break
        end
    end
    Show()
end

-- The surface in front. One whose frame went away without saying so is dropped.
local function Top()
    while #surfaces > 0 do
        local s = surfaces[#surfaces]
        if not s.root or s.root:IsShown() then return s end
        Focus.Pop(s)
    end
    return nil
end

local function Root()
    local top = Top()
    if top then return top.root end
    return FG.Window and FG.Window.Frame()
end

-- ==== lists =================================================================

local function ListOf(frame)
    local p = frame
    while p do
        if p.padList then return p end
        p = p:GetParent()
    end
    return nil
end

-- The first control shown in a frame, the frame itself first.
local function FirstClickable(frame)
    if Clickable(frame) and Visible(frame) then return frame end
    local children = { frame:GetChildren() }
    for i = 1, #children do
        if Visible(children[i]) then
            local c = FirstClickable(children[i])
            if c then return c end
        end
    end
    return nil
end

-- The control inside a list item to focus: its first, or the row itself, to read.
local function InnerOf()
    return function(row) return FirstClickable(row) or row end
end

-- Every item but headings and hints: a row that only says something can be read too.
local NOT_FOCUSABLE = { section = true, hint = true, spacer = true }
local function Focusable(item)
    return item ~= nil and not NOT_FOCUSABLE[item.kind]
end

local function KeyOf(item)
    return item and (item.name or item.title or (item.result and item.result.name) or item.text) or nil
end

local function AtIndex(list, i)
    local item = list.items[i]
    cur = { list = list, index = i, key = KeyOf(item), inner = item and InnerOf(item) }
    if list.Reveal then list:Reveal(i) end
    Show()
    if FG.Pad and FG.Pad.Settings().sound and PlaySound and SOUNDKIT then
        pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end
end

-- The next focusable item along a list, or nil past its end.
local function Step(list, i, delta)
    local n = #list.items
    local j = i + delta
    while j >= 1 and j <= n do
        if Focusable(list.items[j]) then return j end
        j = j + delta
    end
    return nil
end

-- The row of a list a frame is in.
local function RowOf(frame, list)
    local p = frame
    while p and p:GetParent() ~= list do p = p:GetParent() end
    return p
end

-- A frame focused: within a list, as its item (and the control picked inside it).
local function Land(c)
    if not c then return false end
    local list = c.list or ListOf(c.frame)
    local row = list and RowOf(c.frame, list)
    if row and row.index then
        AtIndex(list, row.index)
        if c.frame ~= row then cur.pick = c.frame end
    else
        cur = { frame = c.frame }
        -- A page that scrolls its own way (the settings) brings it into view.
        local p = c.frame
        while p do
            if p.padReveal then
                p.padReveal(c.frame)
                break
            end
            p = p:GetParent()
        end
    end
    Show()
    return true
end

-- ==== moving ================================================================

-- Something sensible to start on: what the page in front asks for, else the first
-- focusable thing on it.
function Focus.First()
    local top = Top()
    if top and top.first then
        local f = top.first()
        if f then
            cur = { frame = f }
            return Show()
        end
    end
    local root = Root()
    if not root then return end
    local wanted, scope
    if not top and FG.Window.FirstFocus then wanted, scope = FG.Window.FirstFocus() end
    if wanted and Visible(wanted) then
        Land({ frame = wanted })
        return
    end
    local all = Collect(scope and Visible(scope) and scope or root, {})
    if #all == 0 and scope then all = Collect(root, {}) end
    table.sort(all, function(a, b)
        local _, ay = Center(a.frame)
        local _, by = Center(b.frame)
        local ax = Center(a.frame)
        local bx = Center(b.frame)
        if math.abs((ay or 0) - (by or 0)) > 4 then return (ay or 0) > (by or 0) end
        return (ax or 0) < (bx or 0)
    end)
    if all[1] then Land(all[1]) end
end

local function Valid()
    if not cur then return false end
    if cur.list then
        if not Visible(cur.list) then return false end
        -- The item at that place may have changed: the same one, nearby, or the nearest.
        local item = cur.list.items[cur.index]
        if not (item and KeyOf(item) == cur.key and Focusable(item)) then
            local n = #cur.list.items
            for d = 0, n do
                for _, j in ipairs({ cur.index - d, cur.index + d }) do
                    local it = cur.list.items[j]
                    if it and Focusable(it) and KeyOf(it) == cur.key then
                        cur.index = j
                        return true
                    end
                end
            end
            local j = Step(cur.list, math.min(cur.index, n + 1), -1) or Step(cur.list, 0, 1)
            if not j then return false end
            cur.index, cur.key = j, KeyOf(cur.list.items[j])
            cur.inner = InnerOf(cur.list.items[j])
        end
        return true
    end
    return Visible(cur.frame)
end

function Focus.Move(dir)
    local root = Root()
    if not root then return end
    if not Valid() then return Focus.First() end
    local from = FrameOf(cur)
    -- Up and down a list go item by item, scrolling as needed.
    if cur.list and (dir == "up" or dir == "down") then
        local j = Step(cur.list, cur.index, dir == "down" and 1 or -1)
        if j then return AtIndex(cur.list, j) end
    end
    if not from then
        if cur.list and cur.list.Reveal then cur.list:Reveal(cur.index) end
        from = FrameOf(cur)
        if not from then return end
    end
    -- A slider: left and right change it.
    if from.padAdjust and (dir == "left" or dir == "right") then
        from.padAdjust(dir == "right" and 1 or -1)
        return Show()
    end
    local all = Collect(root, {})
    local list = cur.list
    if list then
        -- Leaving a list sideways or past its ends: what is next to it, not its other rows.
        local outside = {}
        for _, c in ipairs(all) do
            if ListOf(c.frame) ~= list or (dir == "left" or dir == "right") and c.frame:GetParent() == from:GetParent() then
                outside[#outside + 1] = c
            end
        end
        all = outside
    end
    local target = Nearest(from, all, dir)
    if target then Land(target) end
end

-- The list the focus is in, or the page's main one.
local function CurrentList()
    if cur and cur.list then return cur.list end
    local frame = FrameOf(cur)
    return frame and ListOf(frame) or nil
end

local function Scroll(pages, toEnd)
    local list = CurrentList()
    if not list then return end
    if toEnd then
        local j = toEnd == "top" and Step(list, 0, 1) or Step(list, #list.items + 1, -1)
        if j then return AtIndex(list, j) end
        return
    end
    local h = list:GetHeight()
    local target = list.offset + pages * h
    local i = cur and cur.list == list and cur.index or 1
    -- The first focusable item below (or above) a page away.
    local best = i
    for j = 1, #list.items do
        if Focusable(list.items[j]) and list.tops[j] then
            if pages > 0 and list.tops[j] >= target then best = j break end
            if pages < 0 and list.tops[j] <= target then best = j end
        end
    end
    AtIndex(list, best)
end

-- ==== doing =================================================================

local function Activate(context)
    if not Valid() then return Focus.First() end
    local frame = FrameOf(cur)
    if not frame then return end
    local kind = frame:GetObjectType()
    if kind == "EditBox" then
        if FG.PadKeyboard and FG.Pad.InUse() then
            FG.PadKeyboard.Open(frame)
        else
            frame:SetFocus()
        end
        return
    end
    if frame.padAdjust then return frame.padAdjust(context and -1 or 1) end
    if frame.Click then
        frame:Click(context and "RightButton" or "LeftButton")
    end
    -- What the click opened may have moved the focus: keep it in step.
    FG.After(0, Show)
end

local ACT = {
    up = function() Focus.Move("up") end,
    down = function() Focus.Move("down") end,
    left = function() Focus.Move("left") end,
    right = function() Focus.Move("right") end,
    confirm = function() Activate(false) end,
    context = function() Activate(true) end,
    pageUp = function() Scroll(-1) end,
    pageDown = function() Scroll(1) end,
    top = function() Scroll(0, "top") end,
    bottom = function() Scroll(0, "bottom") end,
}

-- An action, for the surface in front.
function Focus.Do(id)
    local top = Top()
    if top and top.onAction and top.onAction(id) then return Show() end
    if id == "back" then
        if top then
            if top.onBack then top.onBack() else Focus.Pop(top) end
            return Show()
        end
        if not FG.Window.Back() then FG.Window.Hide() end
        return FG.After(0, function() if not Valid() then Focus.First() end end)
    end
    local fn = ACT[id]
    if fn then return fn() end
    if not top and FG.Window.PadAction and FG.Window.PadAction(id) then
        return FG.After(0, function()
            if not Valid() then Focus.First() end
            Show()
        end)
    end
end

-- ==== the route map ========================================================
-- In front, it takes the buttons: left and right go step by step along the route, up
-- shows all of it, down the player's place, confirm starts the route, back closes it.

local mapSurface
-- The D-pad and A work on the map as anywhere: they move between its buttons (the bar's
-- next step, whole route, my position, Start navigation and close) and the marks on it,
-- and press the one selected. The shoulders and triggers step through the route, X shows
-- all of it, R3 and B close the map.
local STEP = { prevTab = -1, nextTab = 1, prevSub = -1, nextSub = 1 }
local function MapAction(id)
    local P = FG.MapPreview
    if STEP[id] then
        local legs = P.Legs and P.Legs() or {}
        local n = math.max(1, #legs)
        local dir = STEP[id]
        local at = P.Focused() or (dir > 0 and 0 or n + 1)
        local nextLeg = at + dir
        if nextLeg < 1 or nextLeg > n then P.Fit() else P.Focus(nextLeg) end
        return true
    elseif id == "context" then
        P.Fit()
        return true
    elseif id == "startNav" then
        local plan = FG.Planner.Current()
        if plan and plan.selected then FG.Planner.Start() end
        return true
    elseif id == "openMap" then
        FG.RouteMap.Hide()
        return true
    end
    return false
end

-- The map says when it shows and hides (true, false), however it was closed.
local function MapHidden()
    if not mapSurface then return end
    local s = mapSurface
    mapSurface = nil
    Focus.Pop(s)
end
FG.On("routemap:shown", function(shown)
    if shown == false then return MapHidden() end
    if mapSurface then return end
    mapSurface = { root = FG.RouteMap.Frame(), onAction = MapAction,
                   -- Starts on the bar's Start navigation, else what is first on the map.
                   first = function() return FG.MapPreview.FirstFocus and FG.MapPreview.FirstFocus() end,
                   -- Back to the window, the plan still there.
                   onBack = function() FG.RouteMap.Hide() end }
    Focus.Push(mapSurface)
    -- The bar is put on the map in the same moment the map opens, after this: once it is
    -- there, the focus starts on it.
    local s = mapSurface
    FG.After(0, function() if mapSurface == s and Top() == s then Focus.First() end end)
end)

-- Puts the focus on a frame a page chose (the first result after a search).
function Focus.To(frame)
    if not Visible(frame) then return false end
    cur = nil
    return Land({ frame = frame })
end

-- What the focus is on, for tests and the report.
function Focus.Current()
    if not cur then return nil end
    return FrameOf(cur), cur.list, cur.index
end

function Focus._Surfaces() return surfaces end    -- tests

function Focus.Reset()
    cur = nil
    surfaces = {}
    if ring then ring:Hide() end
end

-- A list drew again (a scroll, new prices): the ring follows its item, and the item is
-- found again if it moved.
FG.On("list:rendered", function(list)
    if cur and cur.list == list then
        Valid()
        Show()
    end
end)
FG.On("pad:input", function()
    if FG.Window and FG.Window.IsShown() and FG.Pad.InUse() and not cur then Focus.First() end
    Show()
end)
FG.On("window:shown", function()
    if FG.Pad and FG.Pad.InUse() then FG.After(0, Focus.First) end
end)
FG.On("window:hidden", function()
    cur = nil
    surfaces = {}
    if ring then ring:Hide() end
end)
