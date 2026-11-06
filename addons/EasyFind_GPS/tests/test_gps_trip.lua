-- Tests for Trip.lua: stops planned leg by leg, each from the
-- stop before, and the stop list's edits planning the trip again.
local H = require("Harness")

local function Load(opts)
    local env = H.newEnv()
    local ns = H.newNs(env)
    env.EasyFind._ns = ns
    local legs = {}
    local route = { dest = { name = "C", mapID = 3, x = 0.5, y = 0.5 }, stops = opts and opts.stops }
    ns.GPS = {
        CurrentRoute = function() return route end,
        WorldPos = function(mapID, x, y) return 0, mapID * 100 + x, y end,
        BuildRoute = function(_, dest, via, _, _, _, from)
            legs[#legs + 1] = { dest = dest.name, from = from and from.name, via = via }
            local sec = dest.sec
            if sec == "none" then sec = nil elseif sec == nil then sec = 10 end
            return { { kind = "travel", name = dest.name } }, sec, { tips = dest.name }
        end,
        Plan = function(_, _, build, done) done(build()) end,
        Navigated = function(dest, steps, total, advice, stops)
            route.planned = { dest = dest, steps = steps, total = total, advice = advice, stops = stops }
        end,
        Open = function() end,
        Clear = function() route.cleared = true end,
    }
    H.loadModule("Trip.lua", env, ns)
    return ns.GPSTrip, route, legs, ns
end

-- The route ahead: one walk east on continent 1 from (0, 0) to (1000, 0),
-- 100 seconds; spots are world yards. now: the arrow's place on it.
local function Walking(ns, route, now)
    route.steps = { { kind = "travel", sec = 100, arrive = { ci = 1, wx = 1000, wy = 0 } } }
    ns.GPSData = {}
    ns.GPSRoute = {
        GroundSpeed = function() return 10 end,
        WalkPath = function() return { pts = { 0, 0, 1000, 0 }, len = 1000 } end,
    }
    ns.GPSFollow = {
        Now = function() return now end,
        StartOf = function() return 1, 0, 0 end,
    }
    ns.GPS.WorldPos = function(_, x, y) return 1, x, y end
end

local function near(a, b) return math.abs(a - b) < 0.01 end

local tests = {}

function tests.build_plansEachLegFromTheStopBefore()
    local Trip, _, legs = Load()
    local a = { name = "A", mapID = 1, x = 0.2, y = 0.3, sec = 5 }
    local b = { name = "B", mapID = 2, x = 0.4, y = 0.4, sec = 7 }
    local c = { name = "C", mapID = 3, x = 0.5, y = 0.5, sec = 9 }
    local steps, total, advice = Trip.Build({ a, b, c }, "via", nil, true, "first")
    H.assertEq(#steps, 3)
    H.assertEq(total, 21)
    H.assertEq(advice.tips, "A", "the first leg's advice")
    H.assertNil(legs[1].from, "the first leg from the start as set")
    H.assertEq(legs[1].via, "via")
    H.assertEq(legs[2].from, "A")
    H.assertNil(legs[2].via, "the stop to learn is on the first leg only")
    H.assertEq(legs[3].from, "B")
end

function tests.build_unpricedLegLeavesNoTotal()
    local Trip = Load()
    local _, total = Trip.Build({ { name = "A", mapID = 1 }, { name = "B", mapID = 2, sec = "none" } })
    H.assertNil(total)
end

-- The editor's drag (Editor:LayDrag): the dragged row rides with the
-- cursor, the others step into the order its drop makes, and the button
-- up ends it whether or not the grip hears the drop (a grip hidden
-- mid-drag left the drag on, its line and grip stuck, 2026-10-27).
local function LoadDrag(cursor, laid, reordered)
    local f = assert(io.open(H.Path("Trip.lua"), "rb"))
    local src = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    local s = assert(src:find("\nlocal function CursorY(ed)", 1, true), "the drag's start")
    local e = assert(src:find("\n-- A row's mark,", s, true), "the drag's end")
    local Editor = {}
    local env = setmetatable({
        Editor = Editor, mmax = math.max, mmin = math.min,
        Lay = function(_, row, slot, y) laid[row.name] = { slot = slot, y = y } end,
        GetCursorPosition = function() return 0, cursor.y end,
        IsMouseButtonDown = function() return cursor.down end,
        Trip = { Reorder = function(i, j) reordered[#reordered + 1] = { i, j } end },
        Route = function() return {} end,
        GetTime = function() return 0 end,
    }, { __index = _G })
    assert(load(src:sub(s, e), "=Trip.lua drag", "t", env))()
    return Editor
end

-- Three rows 30 tall from the editor's top at 300: tops 300, 270, 240.
local function DragEditor(cursor, laid, reordered)
    local Editor = LoadDrag(cursor, laid, reordered)
    local ed = { orderRows = {} }
    for k, v in pairs(Editor) do ed[k] = v end
    for k = 1, 3 do
        ed.orderRows[k] = { name = "row" .. k, index = k - 1, canDrag = true, level = 5, alpha = 1,
            GetTop = function() return 300 - (k - 1) * 30 end, GetHeight = function() return 30 end,
            GetFrameLevel = function(self) return self.level end,
            SetFrameLevel = function(self, l) self.level = l end,
            SetAlpha = function(self, a) self.alpha = a end,
            IsMouseOver = function() return false end,
            grip = { SetShown = function(self, on) self.shown = on end } }
    end
    function ed:GetTop() return 300 end
    function ed:GetEffectiveScale() return 1 end
    function ed:Watch() end
    function ed:Refresh() self.refreshed = (self.refreshed or 0) + 1 end
    return ed
end

function tests.drag_theOthersStepAsideAndTheDropReorders()
    local cursor, laid, reordered = { y = 230, down = true }, {}, {}
    local ed = DragEditor(cursor, laid, reordered)
    local row3 = ed.orderRows[3]
    ed:DragStart(row3)
    H.assertEq(ed.drag, 3)
    H.assertEq(row3.level, 15, "lifted over the others")
    cursor.y = 295   -- above the first row's middle
    ed:OnUpdate()
    H.assertEq(ed.dropAt, 1)
    H.assertEq(laid.row1.slot, 2); H.assertEq(laid.row1.y, 30)
    H.assertEq(laid.row2.slot, 3); H.assertEq(laid.row2.y, 60)
    H.assertEq(laid.row3.slot, 1); H.assertEq(laid.row3.y, 0, "held within the rows' span")
    H.assertTrue(row3.grip.shown, "the dragged row's grip stays")
    cursor.y = 262   -- above the second row's middle
    ed:OnUpdate()
    H.assertEq(ed.dropAt, 2)
    H.assertEq(laid.row1.slot, 1)
    H.assertEq(laid.row2.slot, 3)
    H.assertEq(laid.row3.slot, 2); H.assertEq(laid.row3.y, 28, "under the cursor, as grabbed")
    cursor.down = false
    ed:OnUpdate()
    H.assertNil(ed.drag, "the button up ends the drag")
    H.assertEq(reordered[1][1], 3); H.assertEq(reordered[1][2], 2)
    H.assertEq(row3.level, 5); H.assertEq(row3.alpha, 1)
    H.assertNil(ed.refreshed, "the reorder lays the rows again, not a refresh")
end

function tests.drag_droppedInPlaceOrOnChangedRowsOnlyRefreshes()
    local cursor, laid, reordered = { y = 230, down = true }, {}, {}
    local ed = DragEditor(cursor, laid, reordered)
    ed:DragStart(ed.orderRows[3])
    ed:OnUpdate()
    H.assertEq(ed.dropAt, 3)
    cursor.down = false
    ed:OnUpdate()
    H.assertEq(#reordered, 0)
    H.assertEq(ed.refreshed, 1)
    cursor.down = true
    ed:DragStart(ed.orderRows[2])
    ed.orderRows[3] = nil   -- the rows changed under the drag
    ed:OnUpdate()
    H.assertNil(ed.drag)
    H.assertEq(#reordered, 0)
    H.assertEq(ed.refreshed, 2)
end

function tests.edits_changeTheStopsAndPlanAgain()
    local Trip, route = Load({ stops = { { name = "A", mapID = 1 }, { name = "B", mapID = 2 }, { name = "C", mapID = 3 } } })
    Trip.Move(3, 1)
    H.assertEq(route.stops[1].name, "C")
    H.assertEq(route.planned.stops[1].name, "C", "planned again in the new order")
    H.assertEq(route.planned.dest.name, "B", "the last stop is the destination")
    Trip.Remove(1)
    H.assertEq(#route.stops, 2)
    Trip.Add({ name = "D", mapID = 4 })
    H.assertEq(route.stops[3].name, "D")
    H.assertEq(#route.planned.steps, 3, "three legs planned")
    Trip.Replace(2, { name = "E", mapID = 5 })
    H.assertEq(route.planned.stops[2].name, "E")
    Trip.Remove(1)
    Trip.Remove(1)
    Trip.Remove(1)
    H.assertTrue(route.cleared, "no stop left: the route is cleared")
end

function tests.navigate_keepsAnOldRoutesOneDestination()
    local Trip, route = Load()
    H.assertTrue(Trip.Navigate({ quiet = true }))
    H.assertEq(route.planned.stops[1].name, "C")
    H.assertEq(#route.planned.stops, 1)
end

function tests.insert_aStopBeforeTheDestination()
    local Trip, route = Load()
    Trip.Insert({ name = "Inn", mapID = 9 })
    H.assertEq(route.stops[1].name, "Inn")
    H.assertEq(route.stops[2].name, "C", "the destination stays last")
    H.assertEq(route.planned.dest.name, "C")
end

-- The extra way through a spot, off the walk, at the walk's own pace
-- (100 s for 1000 yards); five minutes at most.
function tests.detour_theExtraWayAtTheWalksPace()
    local Trip, route, _, ns = Load()
    Walking(ns, route)
    local detour = Trip.Detour(route)
    H.assertTrue(near(detour(1, 500, 100), 1.98), "100 yards off the middle")
    H.assertTrue(near(detour(1, 500, 1900), 292.94), "just within five minutes")
    H.assertNil(detour(1, 500, 2000), "past five minutes")
    H.assertNil(detour(2, 500, 0), "another continent")
end

function tests.detour_onlyTheWayAhead()
    local Trip, route, _, ns = Load()
    -- The player 600 yards along: a spot by the start is behind them.
    Walking(ns, route, { route = route, index = 1, seg = 1, px = 600, py = 0,
                         path = { pts = { 0, 0, 1000, 0 }, len = 1000 } })
    H.assertTrue(near(Trip.Detour(route)(1, 100, 0), 100), "back 500 yards and on again")
    route.steps[1].kind = "taxi"
    H.assertNil(Trip.Detour(route), "no stop on a flight")
end

function tests.along_theLeastOutOfTheWayFirst()
    local Trip, route, _, ns = Load()
    Walking(ns, route)
    ns.GPS.CanNavigate = function() return true end
    ns.GPS.EtaText = function(sec) return math.floor(sec / 60 + 0.5) .. " min" end
    ns.L.GPS_ALONG_ADDS_FMT, ns.L.GPS_ALONG_ON_WAY = "+%s", "on the way"
    ns.GPS.SearchPlaces = function()
        return {
            { name = "Far", mapID = 1, x = 500, y = 1500 },
            { name = "Near", mapID = 1, x = 500, y = 100 },
            { name = "Off", mapID = 1, x = 500, y = 5000 },
            { name = "Catalog", mapID = 1, x = 500, y = 0, catalog = true },
        }
    end
    local asked
    ns.GPSNpcs = {
        Append = function(out, _, q, _, _, along)
            asked = q
            if along(1, 500, 50) then out[#out + 1] = { name = "Innkeeper", mapID = 1, x = 500, y = 50 } end
        end,
    }
    local list, secs = Trip.AlongPlaces("inn")
    H.assertEq(asked, "inn", "the creatures searched along the way")
    H.assertEq(#list, 3, "the one too far off and the search's own creature left out")
    H.assertEq(list[1].name, "Innkeeper")
    H.assertEq(list[2].name, "Near")
    H.assertEq(list[3].name, "Far")
    H.assertEq(Trip.AddsText(secs[list[2]]), "on the way")
    H.assertEq(Trip.AddsText(secs[list[3]]), "+4 min")
end

-- A creature EasyFind lists itself comes once: the catalog is told the
-- names the places kept (Innkeeper Renee twice, 2026-11-03).
function tests.along_aCreatureThePlacesKeptComesOnce()
    local Trip, route, _, ns = Load()
    Walking(ns, route)
    ns.GPS.CanNavigate = function() return true end
    ns.GPS.SearchPlaces = function()
        return { { name = "Innkeeper Renee", nameLower = "innkeeper renee", mapID = 1, x = 500, y = 100 },
                 { name = "Innkeeper Far", mapID = 1, x = 500, y = 5000 } }
    end
    local told
    ns.GPSNpcs = {
        Append = function(out, nameSet)
            told = nameSet
            for _, name in ipairs({ "Innkeeper Renee", "Innkeeper Far", "Innkeeper Norman" }) do
                local low = name:lower()
                if not (nameSet and nameSet[low]) then
                    out[#out + 1] = { name = name, nameLower = low, mapID = 1, x = 500, y = 60 }
                end
            end
        end,
    }
    local list = Trip.AlongPlaces("inn")
    H.assertTrue(told and told["innkeeper renee"], "the catalog is told the places kept")
    H.assertNil(told["innkeeper far"], "not a place off the way: the catalog's nearer one may come")
    local seen = {}
    for _, r in ipairs(list) do
        H.assertNil(seen[r.name], r.name .. " once")
        seen[r.name] = true
    end
    H.assertEq(#list, 3)
end

-- Editor:ShowHits and DropHits cut from Trip.lua: in a window with a list
-- of its own a field's finds go there, never into a panel under the field.
local function EditorHits()
    local f = assert(io.open(H.Path("Trip.lua"), "rb"))
    local src = f:read("*a")
    f:close()
    local s = assert(src:find("function Editor:ShowHits", 1, true), "Editor:ShowHits not in Trip.lua")
    local e = assert(src:find("-- Per-frame work only while", s, true), "end of DropHits not found")
    local env = setmetatable({ Editor = {} }, { __index = _G })
    assert(load(src:sub(s, e - 1), "=Trip.lua hits", "t", env))()
    return env.Editor
end

function tests.windowFinds_listInTheWindow()
    local Editor = EditorHits()
    local shown = false
    local frame = { ShowHits = function(_, results) shown = results end }
    local drop = { shown = true, Hide = function(self) self.shown = false end }
    local ed = setmetatable({ frame = frame, drop = drop, editing = { index = 1 } }, { __index = Editor })
    local finds = { { name = "Tanaris" } }
    ed:ShowHits(finds)
    H.assertTrue(shown == finds, "the window lists them")
    H.assertFalse(drop.shown, "the panel under the field stays away")
    H.assertTrue(frame.hitsFor == ed, "the window's rows pick for this field")
    ed:DropHits()
    H.assertNil(shown, "put away with the field")
    H.assertNil(frame.hitsFor)
end

-- A place picked for a trip's field never reached the map tab's recent
-- searches (2026-11-02): what was typed joins them, as a pick from the
-- map tab's own list does, before the field is cleared.
function tests.aFieldsPick_joinsTheRecentSearches()
    local f = assert(io.open(H.Path("Trip.lua"), "rb"))
    local src = f:read("*a")
    f:close()
    local s = assert(src:find("function Editor:Pick(data)", 1, true))
    local push = src:find("ns.MapTab:PushRecentSearch(row.box:GetText())", s, true)
    local clear = src:find("row.box:ClearFocus()", s, true)
    H.assertTrue(push ~= nil, "the typed words pushed")
    H.assertTrue(clear ~= nil and push < clear, "read before the field is cleared")
end

-- Editor:LayAlong cut from Trip.lua with the sizes it reads there.
local function EditorLayAlong()
    local f = assert(io.open(H.Path("Trip.lua"), "rb"))
    local src = f:read("*a")
    f:close()
    local sizes = {}
    for _, name in ipairs({ "local ROW_H, ADD_H", "local ALONG_H", "local RING =" }) do
        sizes[#sizes + 1] = assert(src:match("\n(" .. name:gsub("%p", "%%%0") .. "[^\n]*)"), name)
    end
    local s = assert(src:find("function Editor:LayAlong", 1, true), "Editor:LayAlong not in Trip.lua")
    local e = assert(src:find("\nfunction Editor:", s + 1, true), "end of LayAlong not found")
    local env = setmetatable({ Editor = {}, mmax = math.max }, { __index = _G })
    assert(load(table.concat(sizes, "\n") .. "\n" .. src:sub(s, e), "=Trip.lua along", "t", env))()
    return env.Editor
end

-- The add row (rowW wide) with its words and the along click's.
local function AlongRow(rowW, addW, alongW)
    local along = { shown = true, points = {} }
    function along:SetShown(v) self.shown = v and true or false end
    function along:IsShown() return self.shown end
    function along:ClearAllPoints() self.points = {} end
    function along:SetPoint(point, _, rel) self.points[#self.points + 1] = point .. ">" .. rel end
    function along:SetWidth(w) self.w = w end
    function along:SetHeight(h) self.h = h end
    local text = {
        GetStringWidth = function() return alongW end,
        GetStringHeight = function() return 12 end,
        SetJustifyH = function(self, j) self.justify = j end,
    }
    local ed = setmetatable({
        alongBtn = along, alongText = text,
        add = { GetWidth = function() return rowW end },
        addText = { GetStringWidth = function() return addW end },
    }, { __index = EditorLayAlong() })
    return ed, along, text
end

-- Search along the route sat only in the window's menu (2026-11-03):
-- the add row's other click, at its right end.
function tests.along_atTheAddRowsEnd_whereBothFit()
    local ed, along, text = AlongRow(260, 80, 90)
    H.assertEq(ed:LayAlong({}), 0, "no line of its own")
    H.assertTrue(along.shown, "shown with a way ahead")
    H.assertEq(along.points[1], "TOPRIGHT>TOPRIGHT", "at the row's right end")
    H.assertEq(text.justify, "RIGHT")
    H.assertTrue(along.w >= 90, "its click as wide as its words")
end

-- Narrow, or in a longer language: under the add row's words, never over them.
function tests.along_aLineUnderTheWords_whereNot()
    local ed, along, text = AlongRow(200, 90, 110)
    local h = ed:LayAlong({})
    H.assertTrue(h >= 12, "the line it adds: " .. h)
    H.assertEq(along.points[1], "TOPLEFT>BOTTOMLEFT", "under the add row")
    H.assertEq(along.points[2], "TOPRIGHT>BOTTOMRIGHT", "its words wrap in the row's width")
    H.assertEq(text.justify, "LEFT")
end

function tests.along_goneWithNoWayAhead()
    local ed, along = AlongRow(260, 80, 90)
    H.assertEq(ed:LayAlong(nil), 0)
    H.assertFalse(along.shown, "no route")
    along.shown = true
    H.assertEq(ed:LayAlong({ arrived = true }), 0)
    H.assertFalse(along.shown, "arrived")
end

-- The click opens the along field as the menu's row does, and the add
-- row's place counts the line it takes.
function tests.along_wiredLikeTheMenusRow()
    local f = assert(io.open(H.Path("Trip.lua"), "rb"))
    local src = f:read("*a")
    f:close()
    H.assertTrue(src:find('along:SetScript("OnClick", function() ns.GPS:SearchAlong(frame) end)', 1, true) ~= nil,
        "the click")
    H.assertTrue(src:find("y = y + ADD_H + self:LayAlong(route)", 1, true) ~= nil, "its line counted")
end

-- "You have arrived" sat at the window's edge, left of the time line and
-- the steps (2026-11-02): the announcement starts where the time line's
-- text does, past the grip and the marks' column.
function tests.theArrivalLinesUpWithTheTimeLine()
    local f = assert(io.open(H.Path("Trip.lua"), "rb"))
    local src = f:read("*a")
    f:close()
    H.assertTrue(src:find('frame.eta:SetPoint("TOPLEFT", ed, "BOTTOMLEFT", GRIP_W + MARK / 2 + shift, -4)', 1, true) ~= nil,
        "the time line's inset")
    H.assertTrue(src:find("ed.emptyX, ed.emptyStepsY = GRIP_W + MARK / 2 + shift,", 1, true) ~= nil,
        "the announcement's the same")
end

local pass, fail, failures = H.runSuite("GPSTrip", tests)
return { pass = pass, fail = fail, failures = failures }
