-- A pin the map placed itself on the journey's end (Preview.lua
-- GamePinAtEnd): a quest's "?" or a flight master is the end's mark, so
-- nothing of ours covers it (the emblem, EasyFind's pin) and the line
-- stops at its edge. Before, a route to a quest turn-in drew our emblem
-- over the quest's "?". A quest's end with no such pin (a quest to take)
-- wears the game's quest button instead: its ring with the "!" of its
-- quest offers, or its turn-in "?".
local H = require("Harness")

local CANVAS_W, CANVAS_H = 1000, 800

local function Pin(x, y, width, shown)
    local p = { x = x, y = y, width = width, shown = shown ~= false }
    function p:GetPosition() return self.x, self.y end
    function p:IsShown() return self.shown end
    function p:GetWidth() return self.width end
    function p:GetScale() return 1 end
    return p
end

-- As the client's pools: pairs over the active set, three values that a
-- loop must take whole (keeping only the first broke on Forever).
local function Pool(pins)
    local active = {}
    for _, p in ipairs(pins) do active[p] = true end
    local pool = {}
    function pool:EnumerateActive() return pairs(active) end
    return pool
end

local function Load(pins, waypointPins)
    local f = assert(io.open(H.Path("Preview.lua"), "rb"))
    local src = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    local s = assert(src:find("local endSpot = {}", 1, true), "endSpot")
    local e = select(2, assert(src:find("MapSearch:PinRouteEnd(dest, x, y)\nend\n", s, true)))
    local pool, waypoints = Pool(pins), Pool(waypointPins or {})
    local canvas = { GetWidth = function() return CANVAS_W end, GetHeight = function() return CANVAS_H end }
    local env = setmetatable({
        ns = { MapSearch = { PinRouteEnd = function() end, GetActivePinState = function() return nil end } },
        World = function(p) return p.ci, p.wx, p.wy end,
        QuestGlyph = function() return nil end,
        C_Map = { GetMapPosFromWorldPos = function() return nil end },
        CreateVector2D = function(x, y) return { x = x, y = y } end,
        WorldMapFrame = { pinPools = { QuestPinTemplate = pool, WaypointLocationPinTemplate = waypoints } },
        Canvas = function() return canvas end,
        Preview = {},
    }, { __index = _G })
    return assert(load(src:sub(s, e) .. "\nreturn GamePinAtEnd", "=Preview.lua game pin", "t", env))()
end

local MAP = 1429
local function Route(x, y, mapID) return { dest = { name = "Turn in", mapID = mapID or MAP, x = x, y = y } } end

local tests = {}

function tests.theQuestsMarkOnTheEnd_isTheMark_withItsRadius()
    local mark = Pin(0.4, 0.6, 32)
    local GamePinAtEnd = Load({ Pin(0.1, 0.1, 32), mark })
    local pin, r = GamePinAtEnd(Route(0.4, 0.6), MAP)
    H.assertEq(pin, mark)
    H.assertEq(r, 16, "the line stops at its edge")
end

function tests.aPinBesideTheEnd_aHiddenOne_orALayer_isNot()
    -- 30 canvas units off, past a 16 unit radius.
    local GamePinAtEnd = Load({ Pin(0.43, 0.6, 32), Pin(0.4, 0.6, 32, false), Pin(0.4, 0.6, CANVAS_W) })
    H.assertNil(GamePinAtEnd(Route(0.4, 0.6), MAP))
end

-- The game's waypoint pin is the one GPS sets on each step's end: never
-- the place's own icon (our end mark stays over it).
function tests.theGamesWaypointPin_isNotThePlacesIcon()
    local GamePinAtEnd = Load({}, { Pin(0.4, 0.6, 32) })
    H.assertNil(GamePinAtEnd(Route(0.4, 0.6), MAP))
end

function tests.anEndOffTheMapShown_hasNone()
    local GamePinAtEnd = Load({ Pin(0.4, 0.6, 32) })
    H.assertNil(GamePinAtEnd(Route(0.4, 0.6, 1411), MAP))
end

-- The draw pass: the emblem, EasyFind's pin and the dismiss button stay
-- off a game pin on the end, and the last leg stops at its edge.
function tests.theDrawPass_leavesTheEndToIt()
    local f = assert(io.open(H.Path("Preview.lua"), "rb"))
    local src = f:read("*a")
    f:close()
    H.assertTrue(src:find("hovered.final and (gamePin or PinAtEnd(route, mapID))", 1, true) ~= nil, "no mark of ours")
    H.assertTrue(src:find("local destTrim = gamePin and gameR or", 1, true) ~= nil, "the line stops at its edge")
    H.assertTrue(src:find("if changed and not gamePin then PinEnd(route, mapID) end", 1, true) ~= nil,
        "no EasyFind pin placed on it")
    H.assertTrue(src:find("if gamePin and ns.MapSearch and ns.MapSearch.HideRouteEnd then", 1, true) ~= nil,
        "one placed before it came goes")
end

local function LoadQuestGlyph(atlases)
    local f = assert(io.open(H.Path("Preview.lua"), "rb"))
    local src = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    local s = assert(src:find("local QUEST_BUTTON, QUEST_EDGE", 1, true))
    local e = select(2, assert(src:find("Preview.QuestGlyph = QuestGlyph\n", s, true)))
    local env = setmetatable({
        Preview = {}, ns = {},
        C_Texture = { GetAtlasInfo = function(name) return atlases[name] and {} or nil end },
    }, { __index = _G })
    return assert(load(src:sub(s, e) .. "\nreturn QuestGlyph", "=Preview.lua quest glyph", "t", env))()
end

local RING = "UI-QuestPoi-QuestNumber"

function tests.aQuestToTake_wearsTheGamesOfferBang_aTurnInItsQuestionMark()
    local QuestGlyph = LoadQuestGlyph({ [RING] = true, QuestNormal = true, ["UI-QuestIcon-TurnIn-Normal"] = true })
    H.assertEq(QuestGlyph({ questMark = "offer" }), "QuestNormal")
    H.assertEq(QuestGlyph({ questMark = "turnin" }), "UI-QuestIcon-TurnIn-Normal")
    H.assertNil(QuestGlyph({ name = "Inn" }), "no quest: the emblem or its icon as before")
end

function tests.aClientWithoutTheGamesQuestButton_keepsTheOldMark()
    local QuestGlyph = LoadQuestGlyph({ QuestNormal = true })
    H.assertNil(QuestGlyph({ questMark = "offer" }), "no ring on this client")
end

-- The button replaces EasyFind's pin on the end (its icon in a dark well),
-- and the mark travels from the row to the route and on a new plan.
function tests.theQuestButton_isTheEndsMark_fromRowToRoute()
    local function Read(path)
        local f = assert(io.open(H.Path(path), "rb"))
        local src = f:read("*a")
        f:close()
        return src
    end
    local preview = Read("Preview.lua")
    H.assertTrue(preview:find("dest.zone or QuestGlyph(dest) or not", 1, true) ~= nil, "no EasyFind pin under it")
    H.assertTrue(preview:find("hovered.final and questGlyph then", 1, true) ~= nil, "drawn on the end")
    H.assertTrue(preview:find("questGlyph and px(QUEST_BUTTON) * QUEST_EDGE", 1, true) ~= nil, "the line stops at its ring")
    local gps = Read("GPS.lua")
    H.assertTrue(gps:find("questMark = data.questMark", 1, true) ~= nil, "the row's mark kept")
    H.assertTrue(gps:find("questMark = dest.questMark", 1, true) ~= nil, "and kept on a new plan")
    H.assertTrue(Read("QuestDirections.lua"):find("questMark = done and \"turnin\" or nil", 1, true) ~= nil,
        "a finished log quest is a turn-in")
end

-- The line runs under the map's own icons (it crossed a quest's "?" on
-- Forever, 2026-11-10): its own frame one above the zone highlight's layer,
-- shown with the marks' overlay, which stays over everything.
function tests.theLine_runsUnderTheMapsIcons()
    local f = assert(io.open(H.Path("Preview.lua"), "rb"))
    local src = f:read("*a")
    f:close()
    H.assertTrue(src:find("lines = Preview.NewLines(under, \"TOPLEFT\")", 1, true) ~= nil, "on its own frame")
    H.assertTrue(src:find("GetFrameLevelStart(\"PIN_FRAME_LEVEL_MAP_HIGHLIGHT\") + 1", 1, true) ~= nil,
        "just above the zone highlight, under every icon layer")
    H.assertTrue(src:find("overlay:SetScript(\"OnHide\", function() under:Hide() end)", 1, true) ~= nil,
        "hidden with the marks")
end

local pass, fail, failures = H.runSuite("GPSGamePinEnd", tests)
return { pass = pass, fail = fail, failures = failures }
