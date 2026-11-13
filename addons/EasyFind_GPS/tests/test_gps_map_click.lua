-- Alt-click for directions (MapClick.lua): a spot on the world map
-- or the pin under the cursor, the game's waypoint pin naming it in its
-- tooltip, and a map pin linked in chat; a right-click on a pin opens its
-- menu with the directions, and so does one on a quest's objective area
-- where the map lets us claim the click (its zoom out skipped). Plain and
-- Shift clicks stay the game's (Shift shares a pin in chat), and so does
-- a right-click on the bare map.
local H = require("Harness")

local function Load(classic)
    local env = H.newEnv()
    if not classic then env.MapCanvasSecureUtil = {} end
    local ns = H.newNs(env)
    env.EasyFind._ns = ns
    local went, menus, stops = {}, {}, {}
    local routeOn, menuOpen = false, false
    ns.GPS = {
        NavigateTo = function(_, data) went[#went + 1] = data return true end,
        ShowGameMenu = function(_, defs) menus[#menus + 1] = defs return true end,
        CurrentRoute = function() return routeOn and {} or nil end,
    }
    ns.GPSTrip = { Insert = function(dest) stops[#stops + 1] = dest end }
    ns.L.GPS_MAP_POINT_FMT = "%s %.1f, %.1f"
    ns.Utils.RegisterEventIfValid = function(f, event) f:RegisterEvent(event) return true end
    ns.Utils.SafeAfter = function(_, fn) fn() end
    local alt = false
    env.IsAltKeyDown = function() return alt end
    env.C_QuestLog = { GetTitleForQuestID = function(id) return "Quest " .. id end }
    env.Menu = { GetManager = function() return { IsAnyMenuOpen = function() return menuOpen end } end }
    env.UIParent = { GetEffectiveScale = function() return 1 end }
    env.GetCursorPosition = function() return 100, 100 end
    local scripts, frames = {}, {}
    env.CreateFrame = function()
        local f = { events = {} }
        function f:SetScript(name, fn) self[name] = fn end
        function f:RegisterEvent(e) self.events[e] = true end
        function f:UnregisterAllEvents() self.events = {} end
        function f:SetSize() end
        function f:ClearAllPoints() end
        function f:SetPoint() end
        frames[#frames + 1] = f
        return f
    end
    local map = { mapID = 84, shown = true, over = true, cursor = { 0.25, 0.75 } }
    map.ScrollContainer = { IsMouseOver = function() return map.over end }
    function map:IsVisible() return self.shown end
    function map:IsShown() return self.shown end
    function map:GetMapID() return self.mapID end
    local turned = {}
    ns.MapSearch.TurnMap = function(id) turned[#turned + 1] = id map.mapID = id end
    function map:GetNormalizedCursorPosition() return self.cursor[1], self.cursor[2] end
    function map:HookScript(name, fn) scripts[name] = fn end
    function map:GetScript(name) return scripts[name] end
    map.blobs = {}
    function map:EnumeratePinsByTemplate(template)
        local i = 0
        return function()
            i = i + 1
            return template == "QuestBlobPinTemplate" and self.blobs[i] or nil
        end
    end
    local claim
    function map:AddCanvasClickHandler(fn, priority) claim = { fn = fn, priority = priority } end
    env.WorldMapFrame = map
    local foci = {}
    env.GetMouseFoci = function() return foci end
    env.C_Map = { GetMapInfo = function(id) return { name = "Map " .. id } end }
    local tip = { lines = {} }
    function tip:HookScript(_, fn) self.onShow = fn end
    function tip:GetOwner() return self.owner end
    function tip:AddLine(text) self.lines[#self.lines + 1] = text end
    function tip:Show() end
    env.GameTooltip = tip
    local itemRef
    env.hooksecurefunc = function(name, fn) if name == "SetItemRef" then itemRef = fn end end
    H.loadModule("MapClick.lua", env, ns)
    for _, f in ipairs(frames) do if f.OnEvent and f.events.PLAYER_LOGIN then f.OnEvent(f, "PLAYER_LOGIN") end end
    local watch = frames[1]
    return {
        went = went, map = map, tip = tip, foci = foci, scripts = scripts, turned = turned,
        menus = menus, stops = stops,
        alt = function(v) alt = v end,
        route = function(v) routeOn = v end,
        menuOpen = function(v) menuOpen = v end,
        press = function(button, between)
            watch.OnEvent(watch, "GLOBAL_MOUSE_DOWN", button or "LeftButton")
            if between then between() end
            watch.OnEvent(watch, "GLOBAL_MOUSE_UP", button or "LeftButton")
        end,
        link = function(link, button) itemRef(link, "[Map Pin]", button or "LeftButton") end,
        watching = function() return watch.events.GLOBAL_MOUSE_DOWN == true end,
        claim = function() return claim end,
        area = function(questID)
            local blob = { shown = true }
            function blob:IsShown() return self.shown end
            function blob:UpdateMouseOverTooltip(x, y)
                blob.asked = { x, y }
                return questID
            end
            map.blobs[#map.blobs + 1] = blob
            return blob
        end,
    }
end

local tests = {}

function tests.altClickOnTheMap_routesToTheSpot_andTheZoomGoesBack()
    local t = Load()
    t.scripts.OnShow(t.map)
    H.assertTrue(t.watching(), "the mouse watched while the map is up")
    t.alt(true)
    -- The game's own Alt-click zooms the map; the turn back goes through
    -- EasyFind's door, never a bare SetMapID.
    t.press(nil, function() t.map.mapID = 85 end)
    H.assertEq(#t.went, 1)
    H.assertEq(t.went[1].mapID, 84)
    H.assertEq(t.went[1].x, 0.25)
    H.assertEq(t.went[1].name, "Map 84 25.0, 75.0")
    H.assertEq(t.turned[1], 84, "the map turned back through MapSearch.TurnMap")
    H.assertEq(t.map.mapID, 84)
end

function tests.thePinUnderTheCursor_givesItsSpotAndName()
    local t = Load()
    t.scripts.OnShow(t.map)
    t.foci[1] = { owningMap = t.map, name = "Flight Master", GetPosition = function() return 0.5, 0.4 end }
    t.alt(true)
    t.press()
    H.assertEq(t.went[1].name, "Flight Master")
    H.assertEq(t.went[1].y, 0.4)
end

function tests.plainAndRightClicks_stayTheGames()
    local t = Load()
    t.scripts.OnShow(t.map)
    t.press()
    t.alt(true)
    t.press("RightButton")
    t.map.over = false
    t.press()
    H.assertEq(#t.went, 0)
end

function tests.theMapClosed_theMouseIsLeftAlone()
    local t = Load()
    t.scripts.OnShow(t.map)
    t.scripts.OnHide(t.map)
    H.assertFalse(t.watching())
end

function tests.theGamesWaypointPin_namesTheAltClick_otherTooltipsDoNot()
    local t = Load()
    t.tip.owner = { owningMap = t.map, CopySlashCommandToClipboard = function() end }
    t.tip.onShow(t.tip)
    H.assertEq(t.tip.lines[1], "GPS_ALT_CLICK_PIN")
    t.tip.lines = {}
    t.tip.owner = { owningMap = t.map }
    t.tip.onShow(t.tip)
    H.assertEq(#t.tip.lines, 0)
end

function tests.aMapPinLinkInChat_altClicked_routesThere()
    local t = Load()
    t.link("worldmap:84:5000:2500")
    H.assertEq(#t.went, 0, "a plain click is the game's: it sets the pin")
    t.alt(true)
    t.link("worldmap:84:5000:2500")
    H.assertEq(t.went[1].mapID, 84)
    H.assertEq(t.went[1].x, 0.5)
    H.assertEq(t.went[1].y, 0.25)
    t.link("item:1234")
    H.assertEq(#t.went, 1, "other links are not places")
end

function tests.aRightClickOnAPin_opensItsMenu_withTheDirections()
    local t = Load()
    t.scripts.OnShow(t.map)
    t.foci[1] = { owningMap = t.map, name = "Flight Master", GetPosition = function() return 0.5, 0.4 end }
    t.press("RightButton")
    H.assertEq(#t.menus, 1, "one menu, on the game's own")
    local defs = t.menus[1]
    H.assertEq(defs[1].kind, "title")
    H.assertEq(defs[1].label, "Flight Master")
    H.assertEq(defs[2].label, "GPS_MENU_EASYFIND_DIRECTIONS")
    H.assertEq(#defs, 2, "no route up: nothing to add a stop to")
    defs[2].onClick()
    H.assertEq(t.went[1].name, "Flight Master")
    H.assertEq(t.went[1].x, 0.5)
    H.assertEq(t.went[1].y, 0.4)
end

function tests.aQuestPin_isNamedByItsQuest_andJoinsARouteAsAStop()
    local t = Load()
    t.scripts.OnShow(t.map)
    t.foci[1] = { owningMap = t.map, questID = 42, GetPosition = function() return 0.1, 0.2 end }
    t.route(true)
    t.press("RightButton")
    local defs = t.menus[1]
    H.assertEq(defs[1].label, "Quest 42")
    H.assertEq(defs[3].label, "GPS_STOP_ADD")
    defs[3].onClick()
    H.assertEq(t.stops[1].name, "Quest 42")
    H.assertEq(t.stops[1].mapID, 84)
    H.assertEq(t.stops[1].x, 0.1)
    defs[2].onClick()
    H.assertEq(t.went[1].questID, 42, "its quest, tracked itself on the route's last step")
end

function tests.aRightClickOnTheBareMap_orUnderTheClientsOwnMenu_opensNothing()
    local t = Load()
    t.scripts.OnShow(t.map)
    t.press("RightButton")
    H.assertEq(#t.menus, 0, "the bare map keeps the game's zoom out")
    t.foci[1] = { owningMap = t.map, name = "X", GetPosition = function() return 0.5, 0.4 end }
    t.menuOpen(true)
    t.press("RightButton")
    H.assertEq(#t.menus, 0, "the client opened its own menu on that click")
    t.map.over = false
    t.menuOpen(false)
    t.press("RightButton")
    H.assertEq(#t.menus, 0, "off the map")
end

-- The map's right-click zooms out unless a click handler claims it
-- (MapCanvas_ScrollContainerMixin OnMouseUp): ours claims one on a target,
-- after the client's own handlers.
function tests.aRightClickOnAPin_isClaimed_soTheMapDoesNotZoomOut()
    local t = Load()
    local claim = t.claim()
    H.assertTrue(claim ~= nil, "the handler is on the map")
    H.assertTrue(claim.priority < 0, "after the client's own handlers")
    H.assertFalse(claim.fn(t.map, "RightButton"), "the bare map zooms out as before")
    t.foci[1] = { owningMap = t.map, name = "Flight Master", GetPosition = function() return 0.5, 0.4 end }
    H.assertTrue(claim.fn(t.map, "RightButton"))
    H.assertFalse(claim.fn(t.map, "LeftButton"), "a left click is the game's")
end

function tests.aRightClickOnAQuestsArea_opensItsMenu_andIsClaimed()
    local t = Load()
    t.scripts.OnShow(t.map)
    local blob = t.area(42)
    H.assertTrue(t.claim().fn(t.map, "RightButton"))
    H.assertEq(blob.asked[1], 0.25, "asked at the cursor, as for its tooltip")
    t.press("RightButton")
    local defs = t.menus[1]
    H.assertEq(defs[1].label, "Quest 42")
    defs[2].onClick()
    H.assertEq(t.went[1].x, 0.25)
    H.assertEq(t.went[1].y, 0.75)
    H.assertEq(t.went[1].name, "Quest 42")
end

function tests.outsideAQuestsArea_orItsLayerHidden_theMapZoomsOut()
    local t = Load()
    t.scripts.OnShow(t.map)
    local blob = t.area(nil)
    H.assertFalse(t.claim().fn(t.map, "RightButton"))
    blob.shown = false
    t.area(42).shown = false
    H.assertFalse(t.claim().fn(t.map, "RightButton"))
    t.press("RightButton")
    H.assertEq(#t.menus, 0)
end

-- Era, TBC and Mists call each handler bare, so the rest of every map
-- click would run as ours: no handler there, the pin menu as before.
function tests.whereTheMapCallsHandlersBare_noneIsAdded()
    local t = Load(true)
    H.assertNil(t.claim())
    t.scripts.OnShow(t.map)
    t.area(42)
    t.press("RightButton")
    H.assertEq(#t.menus, 0, "no quest areas without the claim")
    t.foci[1] = { owningMap = t.map, name = "Flight Master", GetPosition = function() return 0.5, 0.4 end }
    t.press("RightButton")
    H.assertEq(#t.menus, 1)
end

local pass, fail, failures = H.runSuite("GPSMapClick", tests)
return { pass = pass, fail = fail, failures = failures }
