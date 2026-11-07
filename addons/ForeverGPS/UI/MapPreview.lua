-- The journey on a map before it is taken: on our own map (UI/RouteMap.lua), or over the
-- game's map when the player has it open. A layer of its own, with nothing shared with
-- the route being followed: it draws what a plan holds, using EasyFind GPS's line
-- renderer, and it starts nothing. An active route keeps its own line underneath in its
-- own colors, so the two read apart.
--
-- This never opens, closes or turns the game's map. That is the player's alone: an id
-- written from here would stay tainted for every refresh that reads it (docs/TAINT.md).
--
-- Walks follow the ground. A crossing is a straight line only where one is true (a
-- flight, a boat on its own continent); across continents the legs stand apart on
-- their own maps, joined by labeled marks, never by a line through the world.
local FG = ForeverGPS
local MapPreview = {}
FG.MapPreview = MapPreview

local Bridge, Format, Kinds, Kit, Theme = FG.Bridge, FG.Format, FG.Kinds, FG.Kit, FG.Theme
local L = FG.L

local mmin, mmax = math.min, math.max

-- Magenta, because nothing on the map's art is: it reads on snow, sand, forest and
-- sea, and it can never be taken for the active route's blue.
local WALK_COLOR = { 0.98, 0.32, 0.86 }
local FADED_ALPHA, BRIGHT_ALPHA = 0.45, 1
local CROSSING = { taxi = true, boat = true, ferry = true, zeppelin = true, skyship = true, tram = true }
local MARK, DEST_MARK, AREA_MARK = 26, 34, 15     -- sizes on screen
local TAG_FONT = 11
local OTHER_COLOR, OTHER_ALPHA, OTHER_SPAN = { 0.92, 0.92, 0.98 }, 0.5, 0.55     -- the ways not chosen
local THROTTLE = 0.1

local overlay, lines, banner, driver
local marks = {}
local shown                  -- { option, target, focus }
local since = 0
local drawn = {}

local function GameMap() return WorldMapFrame end

-- Where to draw: our own map, else the game's if the player has it open. Each answers
-- with its canvas, the map on it, and how many canvas units a screen pixel is.
local function Surface()
    local own = FG.RouteMap
    if own and own.Shown() then return own.Canvas(), own.MapID(), false, own.Frame() end
    local map = GameMap()
    local canvas = map and map:IsShown() and map.ScrollContainer and map.ScrollContainer.Child
    if canvas then return canvas, map:GetMapID(), true, map.ScrollContainer end
    return nil
end

local onGame = false
local function Px(v) return onGame and Bridge.CanvasPx(v) or v end

-- ==== map geometry ==========================================================

-- World yards to a map's fractions, from three of its corners.
local projections = {}
local function Projection(mapID)
    local p = projections[mapID]
    if p ~= nil then return p end
    p = false
    local c0, x0, y0 = Bridge.WorldPos(mapID, 0, 0)
    local c1, x1, y1 = Bridge.WorldPos(mapID, 1, 0)
    local c2, x2, y2 = Bridge.WorldPos(mapID, 0, 1)
    if c0 and c0 == c1 and c0 == c2 then
        local ux, uy, vx, vy = x1 - x0, y1 - y0, x2 - x0, y2 - y0
        local det = ux * vy - vx * uy
        if det ~= 0 then p = { ci = c0, x0 = x0, y0 = y0, ux = ux, uy = uy, vx = vx, vy = vy, det = det } end
    end
    projections[mapID] = p
    return p
end

local function Frac(p, wx, wy)
    local dx, dy = wx - p.x0, wy - p.y0
    return (dx * p.vy - p.vx * dy) / p.det, (p.ux * dy - dx * p.uy) / p.det
end

local function World(point)
    if not point then return nil end
    if point.wx and point.ci then return point.ci, point.wx, point.wy end
    return Bridge.WorldPos(point.m, point.x, point.y)
end

local function StartOf(option, i)
    local step = option.steps[i]
    if step.from then return step.from end
    if i > 1 then return option.steps[i - 1].arrive end
    return option.from
end

-- Where a leg runs from and to.
local function Ends(option, i)
    local step = option.steps[i]
    if CROSSING[step.kind] then return step.go or StartOf(option, i), step.arrive end
    return StartOf(option, i), step.go or step.arrive
end

-- A point on the map shown, as fractions, or nil off it.
local function OnMapPoint(p, point)
    local ci, wx, wy = World(point)
    if not (p and ci == p.ci) then return nil end
    local x, y = Frac(p, wx, wy)
    if x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    return x, y
end

-- The smallest map holding every point, climbing from the first one's own.
local function SmallestMap(mapID, points)
    local depth = 0
    while mapID and depth < 8 do
        local p = Projection(mapID)
        local all = p ~= false
        for i = 1, all and #points or 0 do
            if not OnMapPoint(p, points[i]) then all = false end
        end
        if all then return mapID end
        local info = C_Map.GetMapInfo(mapID)
        local parent = info and info.parentMapID
        if not parent or parent == 0 or (info.mapType and info.mapType <= 1) then break end
        mapID, depth = parent, depth + 1
    end
    return nil
end

-- The map to show a leg on, or for the whole of what lies on one continent.
local function MapForLeg(option, i)
    local step = option.steps[i]
    local a, b = Ends(option, i)
    return SmallestMap(step.mapID or (b and b.m), { a, b }) or step.mapID or (b and b.m)
end
MapPreview._MapForLeg = MapForLeg

local function MapForJourney(option)
    local here = option.from
    local points = {}
    for i = 1, #option.steps do
        local a, b = Ends(option, i)
        if here and a and World(a) == here.ci then points[#points + 1] = a end
        if here and b and World(b) == here.ci then points[#points + 1] = b end
    end
    local first = option.steps[1]
    return SmallestMap(first.mapID or (here and here.m), points) or (here and here.m) or first.mapID
end
MapPreview._MapForJourney = MapForJourney

-- ==== drawing a line ========================================================

-- The line being traced, in canvas pixels, clipped to the map a piece at a time.
local pts, pen = {}, { n = 0 }

local function PenUp()
    if pen.n >= 4 then lines:Line(pts, pen.n, pen.span, pen.round, pen.color, pen.alpha, 0) end
    pen.n = 0
end

local function Pen(color, alpha)
    PenUp()
    pen.color, pen.alpha, pen.x = color, alpha, nil
end

local function PenTo(x, y)
    local x0, y0 = pen.x, pen.y
    pen.x, pen.y = x, y
    if not x0 then return end
    local t0, t1 = Bridge.ClipToMap(x0, y0, x, y)
    if not t0 then return PenUp() end
    if t0 > 0 or pen.n == 0 then
        PenUp()
        pts[1], pts[2] = (x0 + (x - x0) * t0) * pen.cw, -(y0 + (y - y0) * t0) * pen.ch
        pen.n = 2
    end
    pts[pen.n + 1], pts[pen.n + 2] = (x0 + (x - x0) * t1) * pen.cw, -(y0 + (y - y0) * t1) * pen.ch
    pen.n = pen.n + 2
    if t1 < 1 then PenUp() end
end

local function TraceWalk(p, path, ci, color, alpha)
    local trace = function(red) Pen(red and Bridge.DangerColor() or color, alpha) end
    local to = function(x, y) PenTo(Frac(p, x, y)) end
    Bridge.TraceWalk(path, ci, trace, to)
end

-- The ways not chosen, thin and pale under the chosen one, so a choice can be seen.
local function DrawOthers(p)
    local plan = FG.Planner.Current()
    if not plan then return end
    local span = pen.span
    pen.span = span * OTHER_SPAN
    for _, other in ipairs(plan.options) do
        if other ~= shown.option and other.walks and not other.same and not other.noWay then
            for i in ipairs(other.steps or {}) do
                local path = other.walks[i]
                local ci = path and path.pts and World(StartOf(other, i))
                if ci == p.ci then TraceWalk(p, path, ci, OTHER_COLOR, OTHER_ALPHA) end
            end
        end
    end
    PenUp()
    pen.span = span
end

-- ==== marks =================================================================

local function NewMark(i)
    local m = CreateFrame("Button", nil, overlay)
    m:RegisterForClicks("LeftButtonUp")
    m.disc = m:CreateTexture(nil, "ARTWORK", nil, 1)
    m.disc:SetTexture(FG.ART .. "circle")
    m.disc:SetAllPoints(m)
    m.ring = m:CreateTexture(nil, "ARTWORK", nil, 2)
    m.ring:SetTexture(FG.ART .. "ring")
    m.ring:SetAllPoints(m)
    m.glyph = m:CreateTexture(nil, "ARTWORK", nil, 3)
    m.glyph:SetPoint("TOPLEFT", m, "TOPLEFT", 0, 0)
    m.glyph:SetPoint("BOTTOMRIGHT", m, "BOTTOMRIGHT", 0, 0)
    -- What a ride is, in words beside it: a line ending at a dock says nothing alone.
    m.tag = CreateFrame("Frame", nil, m)
    m.tag.back = Kit.Shape(m.tag, 4, "BACKGROUND", 1)
    Theme.Paint(function(c) m.tag.back:SetColor(c.hud) end)
    m.tag.text = Kit.Text(m.tag, "caption", "text")
    m.tag.text:SetPoint("LEFT", m.tag, "LEFT", 0, 0)
    m.tag:Hide()
    m:SetScript("OnEnter", function(self)
        if not self.tipTitle then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tipTitle, 1, 1, 1, 1, true)
        if self.tipBody then GameTooltip:AddLine(self.tipBody, 0.75, 0.78, 0.82, true) end
        GameTooltip:Show()
    end)
    m:SetScript("OnLeave", function() GameTooltip:Hide() end)
    m:SetScript("OnClick", function(self)
        if self.onClick then self.onClick() end
    end)
    marks[i] = m
    return m
end

local function PlaceMark(i, x, y, size, opts)
    local m = marks[i] or NewMark(i)
    local px = Px(size)
    m:SetFrameLevel(overlay:GetFrameLevel() + 20 + i)
    m:ClearAllPoints()
    m:SetSize(px, px)
    m:SetPoint("CENTER", overlay, "TOPLEFT", x * pen.cw, -y * pen.ch)
    local fill, line = opts.fill or Theme.C.window, opts.line or WALK_COLOR
    m.disc:SetVertexColor(fill[1], fill[2], fill[3], 1)
    m.ring:SetVertexColor(line[1], line[2], line[3], 1)
    m.glyph:SetTexture(FG.ART .. (opts.icon or "pin"))
    local glyph = opts.glyphColor or { 1, 1, 1 }
    m.glyph:SetVertexColor(glyph[1], glyph[2], glyph[3], 1)
    m.glyph:ClearAllPoints()
    local inset = px * 0.2
    m.glyph:SetPoint("TOPLEFT", m, "TOPLEFT", inset, -inset)
    m.glyph:SetPoint("BOTTOMRIGHT", m, "BOTTOMRIGHT", -inset, inset)
    m.tipTitle, m.tipBody, m.onClick = opts.title, opts.body, opts.onClick
    m.tag:SetShown(opts.tag ~= nil)
    if opts.tag then
        local font = Px(TAG_FONT)
        if not m.tag.text:SetFont(Theme.FONT.medium, font, "") then m.tag.text:SetFont(STANDARD_TEXT_FONT, font, "") end
        m.tag.text:ClearAllPoints()
        m.tag.text:SetPoint("LEFT", m.tag, "LEFT", Px(6), 0)
        m.tag.text:SetText(opts.tag)
        m.tag:SetSize(m.tag.text:GetStringWidth() + Px(12), Px(TAG_FONT + 8))
        m.tag:ClearAllPoints()
        m.tag:SetPoint("LEFT", m, "RIGHT", Px(4), 0)
    end
    m:Show()
    return m
end

local function StepTip(step)
    local time = step.sec and step.sec > 0 and Format.Duration(step.sec) or nil
    return step.text or Kinds.Label(step), time
end

-- The marks a leg needs: where a ride is boarded, where it lands, and for a leg
-- whose far end is on another continent, what happens next.
local function LegMarks(option, i, p, n)
    local step = option.steps[i]
    if step.approach or step.kind == "travel" or step.kind == "seam" then return n end
    local info = Kinds.Info(step)
    local a, b = Ends(option, i)
    local color = Bridge.LineColor(step.kind)
    local title, body = StepTip(step)
    local onClick = function() MapPreview.Focus(i) end
    local x, y = OnMapPoint(p, a)
    if x and step.kind ~= "teleport" then
        n = n + 1
        PlaceMark(n, x, y, MARK, { icon = info.icon, line = color, title = title, body = body, onClick = onClick,
                                   tag = step.reach or step.text })
    end
    local ax, ay = OnMapPoint(p, b)
    if ax then
        n = n + 1
        local landing = L["MAP_LANDS_FMT"]:format(Kinds.Label(step))
        PlaceMark(n, ax, ay, MARK * 0.8, { icon = info.icon, line = color, title = landing, body = step.text, onClick = onClick,
                                           tag = landing })
    end
    return n
end

-- The other places a destination stands, to choose from on the map.
local function AreaMarks(target, p, n)
    if not FG.db.map.areas then return n end
    for _, area in ipairs(target and target.areas or {}) do
        if area ~= target.area and area.spot then
            local x, y = OnMapPoint(p, { m = area.spot.mapID, x = area.spot.x, y = area.spot.y })
            if x then
                n = n + 1
                local body = area.sec and L["ETA_SHORT_FMT"]:format(Format.Duration(area.sec)) or nil
                PlaceMark(n, x, y, AREA_MARK, { icon = "dot", line = Theme.C.lineStrong, title = area.zone, body = body,
                    onClick = function() FG.Search.GoToArea(target, area) end })
            end
        end
    end
    return n
end

-- ==== the layer =============================================================

local function Build(canvas)
    overlay = CreateFrame("Frame", "ForeverGPSMapPreview", canvas)
    overlay:EnableMouse(false)
    lines = Bridge.NewMapLines(overlay)
    return lines ~= nil
end

-- The layer moved onto the surface that is showing.
local function Mount(canvas, game)
    if overlay and overlay:GetParent() == canvas then return end
    overlay:SetParent(canvas)
    overlay:ClearAllPoints()
    overlay:SetAllPoints(canvas)
    overlay:SetFrameStrata("HIGH")
    overlay:SetFrameLevel(game and 320 or canvas:GetFrameLevel() + 20)
    wipe(drawn)
end

local function Draw()
    local canvas, mapID, game = Surface()
    if not (canvas and shown) then
        if overlay then overlay:Hide() end
        return
    end
    if not overlay and not Build(canvas) then return end
    Mount(canvas, game)
    onGame = game
    local cw, ch = canvas:GetWidth(), canvas:GetHeight()
    local option = shown.option
    local zoom = Px(1)
    local plan = FG.Planner.Current()
    local ways = plan and #plan.options or 0
    local focus = shown.hover or shown.focus
    if plan then
        ways = 0
        for _, o in ipairs(plan.options) do
            if o.walks then ways = ways + 1 end
        end
    end
    if drawn.option == option and drawn.map == mapID and drawn.cw == cw and drawn.ch == ch and drawn.focus == focus
        and drawn.target == shown.target and drawn.area == shown.target.area and drawn.zoom == zoom and drawn.ways == ways then
        return
    end
    drawn.option, drawn.map, drawn.cw, drawn.ch, drawn.focus = option, mapID, cw, ch, focus
    drawn.zoom, drawn.ways = zoom, ways
    drawn.target, drawn.area = shown.target, shown.target.area
    FG.Metrics.Begin("mapDraw")
    local p = Projection(mapID)
    pen.span, pen.round, pen.cw, pen.ch, pen.n = Px(Bridge.LineSpan()), Px(20), cw, ch, 0
    lines:Begin()
    local n = 0
    if p then
        DrawOthers(p)
        for i, step in ipairs(option.steps) do
            local alpha = (not focus or focus == i) and BRIGHT_ALPHA or FADED_ALPHA
            if step.kind ~= "teleport" then
                local path = option.walks and option.walks[i]
                if path and path.pts then
                    local ci = World(StartOf(option, i))
                    if ci == p.ci then TraceWalk(p, path, ci, WALK_COLOR, alpha) end
                else
                    local a, b = Ends(option, i)
                    local aci, ax, ay = World(a)
                    local bci, bx, by = World(b)
                    -- Straight only within a continent: a crossing between two has no line.
                    if aci and aci == bci and aci == p.ci then
                        local color = CROSSING[step.kind] and Bridge.LineColor(step.kind) or WALK_COLOR
                        Pen(color, alpha)
                        PenTo(Frac(p, ax, ay))
                        PenTo(Frac(p, bx, by))
                    end
                end
            end
        end
    end
    PenUp()
    lines:Finish()
    if p then
        for i = 1, #option.steps do n = LegMarks(option, i, p, n) end
        n = AreaMarks(shown.target, p, n)
        local start = option.from
        local sx, sy = OnMapPoint(p, start)
        if sx then
            n = n + 1
            PlaceMark(n, sx, sy, MARK * 0.72, { icon = "dot", line = { 1, 1, 1 }, title = L["MAP_YOU"] })
        end
        local last = option.steps[#option.steps]
        local dx, dy = OnMapPoint(p, last and (last.go or last.arrive))
        if dx then
            n = n + 1
            PlaceMark(n, dx, dy, DEST_MARK, { icon = "flag", fill = WALK_COLOR, line = { 1, 1, 1 },
                title = shown.target.name, body = shown.target.subtitle })
        end
    end
    for i = n + 1, #marks do marks[i]:Hide() end
    overlay:Show()
    FG.Metrics.End("mapDraw")
end
MapPreview._Draw = Draw

local function Tick(_, elapsed)
    since = since + elapsed
    if since < THROTTLE then return end
    since = 0
    Draw()
end

local function Watch()
    if not driver then driver = CreateFrame("Frame") end
    driver:SetScript("OnUpdate", (shown and Surface()) and Tick or nil)
end

-- ==== the banner on the map =================================================

local function BuildBanner()
    banner = CreateFrame("Frame", "ForeverGPSMapBanner", UIParent)
    banner:SetHeight(38)
    banner:EnableMouse(true)
    banner.back = Kit.Shape(banner, 8, "BACKGROUND", 1)
    banner.edge = Kit.Shape(banner, 8, "BACKGROUND", 2, true)
    Theme.Paint(function(c)
        banner.back:SetColor(c.hud)
        banner.edge:SetColor(c.lineStrong)
    end)
    banner.dot = banner:CreateTexture(nil, "ARTWORK")
    banner.dot:SetTexture(FG.ART .. "circle")
    banner.dot:SetSize(10, 10)
    banner.dot:SetPoint("LEFT", banner, "LEFT", 12, 0)
    banner.dot:SetVertexColor(WALK_COLOR[1], WALK_COLOR[2], WALK_COLOR[3], 1)
    banner.title = Kit.Text(banner, "label", "text")
    banner.title:SetPoint("LEFT", banner.dot, "RIGHT", 8, 0)
    banner.go = Kit.Button(banner, { text = L["ROUTE_START"], variant = "primary", height = 26, width = "fit", onClick = function()
        FG.Planner.Start()
    end })
    banner.close = Kit.IconButton(banner, "close", 10, L["MAP_CLOSE_PREVIEW"], function() MapPreview.Close() end)
    banner.close:SetPoint("RIGHT", banner, "RIGHT", -6, 0)
    banner.go:SetPoint("RIGHT", banner.close, "LEFT", -4, 0)
    banner.you = Kit.IconButton(banner, "locate", 14, L["MAP_RETURN"], function() MapPreview.ToPlayer() end)
    banner.you:SetPoint("RIGHT", banner.go, "LEFT", -4, 0)
    banner.fit = Kit.IconButton(banner, "fit", 14, L["MAP_FIT"], function() MapPreview.Fit() end)
    banner.fit:SetPoint("RIGHT", banner.you, "LEFT", 0, 0)
    banner.leg = Kit.IconButton(banner, "chevron-right", 12, L["MAP_NEXT_LEG"], function() MapPreview.NextLeg() end)
    banner.leg:SetPoint("RIGHT", banner.fit, "LEFT", 0, 0)
    banner:Hide()
end

-- The banner sits on whichever surface is showing, and with none it is hidden.
local function MountBanner(host, game)
    banner:SetParent(host)
    banner:SetFrameStrata("HIGH")
    banner:SetFrameLevel(game and 340 or host:GetFrameLevel() + 60)
    banner:ClearAllPoints()
    banner:SetPoint("TOP", game and host or FG.RouteMap.Canvas(), "TOP", 0, -8)
end

local function ShowBanner()
    if not banner then BuildBanner() end
    local _, _, game, host = Surface()
    if not (shown and host) then return banner:Hide() end
    MountBanner(host, game)
    local option = shown.option
    banner.title:SetText(L[shown.active and "MAP_ROUTE_FMT" or "MAP_PREVIEW_FMT"]:format(shown.target.name or "?", Format.Duration(option.total) or "?"))
    banner.go:SetShown(not shown.active)
    banner:SetWidth(mmin(mmax(400, banner.title:GetStringWidth() + banner.go:GetWidth() + 152), 700))
    banner.leg:SetShown(#MapPreview.Legs() > 1)
    banner:Show()
end

-- ==== doors =================================================================

local function Sync(plan)
    local option = plan and plan.selected
    local wanted = FG.db.map.preview or (shown and shown.asked)
    if shown and shown.active and not option then
        ShowBanner()
        Draw()
        return Watch()
    end
    if option and option.steps and not option.noWay and wanted then
        if not shown or shown.option ~= option or shown.target ~= plan.target then
            shown = { option = option, target = plan.target, asked = shown and shown.target == plan.target and shown.asked }
        end
    else
        shown = nil
    end
    if not shown then
        if overlay then overlay:Hide() end
        if banner then banner:Hide() end
        wipe(drawn)
        FG.RouteMap.Hide()
    else
        ShowBanner()
        Draw()
    end
    Watch()
end

FG.On("plan:changed", Sync)
FG.On("route:cleared", function()
    if shown and shown.active then
        shown = nil
        Sync(FG.Planner.Current())
    end
end)
FG.On("routemap:shown", function()
    wipe(drawn)
    if shown then ShowBanner() end
    Watch()
    Draw()
end)
FG.On("settings:changed", function()
    wipe(drawn)
    Sync(FG.Planner.Current())
end)

-- The whole journey on our own map, or one step of it.
function MapPreview.Open(index)
    -- Asked for by name, it shows even with the automatic preview turned off.
    if not shown then
        local plan = FG.Planner.Current()
        if not (plan and plan.selected) then return false end
        shown = { option = plan.selected, target = plan.target, asked = true }
        Sync(plan)
    end
    if not shown then return false end
    FG.RouteMap.Show(index and MapForLeg(shown.option, index) or MapForJourney(shown.option))
    ShowBanner()
    Watch()
    Draw()
    return true
end

-- Picks out one step, on the panel or the map; again, or nil, shows them all.
function MapPreview.Focus(index)
    if not shown then return end
    shown.focus = shown.focus ~= index and index or nil
    MapPreview.Open(shown.focus)
    FG.Emit("preview:focus", shown.focus)
end

-- A step under the cursor in the panel, lit for as long as it is there.
function MapPreview.Hover(index)
    if not shown or shown.hover == index then return end
    shown.hover = index
    Draw()
end

-- The land each part of the journey stands on, in order: on a map of one continent the
-- rest of a journey cannot be seen, so these are what to step through.
function MapPreview.Legs()
    local out, seen = {}, {}
    if not shown then return out end
    local option = shown.option
    for i, step in ipairs(option.steps) do
        if step.kind ~= "teleport" then
            local _, b = Ends(option, i)
            for _, point in ipairs({ StartOf(option, i) or false, b or false }) do
                local ci = point and World(point)
                if ci and not seen[ci] then
                    seen[ci] = true
                    out[#out + 1] = { ci = ci, index = i, mapID = point.m or MapForLeg(option, i) }
                end
            end
        end
    end
    return out
end

-- On to the next land of the journey, round to the first.
function MapPreview.NextLeg()
    local legs = MapPreview.Legs()
    if not shown or #legs < 2 then return end
    shown.leg = (shown.leg or 1) % #legs + 1
    FG.RouteMap.Show(legs[shown.leg].mapID)
    Draw()
end

-- The whole journey again, with no step picked out.
function MapPreview.Fit()
    if not shown then return end
    shown.focus = nil
    MapPreview.Open()
    FG.Emit("preview:focus", nil)
end

-- Back to where the player stands; the preview stays.
function MapPreview.ToPlayer()
    local mapID = C_Map.GetBestMapForUnit("player")
    if mapID then FG.RouteMap.Show(mapID) end
    Draw()
end

-- The route under way, drawn from what the journey holds: EasyFind GPS's own line lives
-- on the game's map, and is there whenever the player opens it.
function MapPreview.OpenActive()
    local route = Bridge.ActiveRoute()
    if not route then return false end
    local step = route.steps[route.active or 1]
    if not shown or not shown.active then
        shown = { active = true, asked = true, target = { name = route.dest and route.dest.name },
                  option = { steps = route.steps, walks = Bridge.WalksOf(route), from = route.from, total = route.total } }
    end
    FG.RouteMap.Show(step and step.mapID or C_Map.GetBestMapForUnit("player"))
    ShowBanner()
    Watch()
    Draw()
    return true
end

-- Done with what is showing: a plan's preview goes with its plan.
function MapPreview.Close()
    if shown and shown.active then
        shown = nil
        return Sync(FG.Planner.Current())
    end
    FG.Planner.Clear()
    FG.RouteMap.Hide()
end

function MapPreview.Focused() return shown and shown.focus or nil end
function MapPreview.Showing() return shown ~= nil end

local function Hook()
    local map = GameMap()
    if not map or MapPreview.hooked then return end
    MapPreview.hooked = true
    map:HookScript("OnShow", function()
        wipe(drawn)
        if shown then ShowBanner() end
        Watch()
        Draw()
    end)
    map:HookScript("OnHide", function()
        if shown then ShowBanner() end
        Watch()
    end)
end

FG.On("login", Hook)
FG.On("theme:changed", function()
    wipe(drawn)
    Draw()
end)

-- Test seam: the strips drawn now.
function MapPreview._Lines() return lines end
function MapPreview._Marks() return marks end


function MapPreview._Current() return shown end
function MapPreview._Redraw()
    wipe(drawn)
    Draw()
end
