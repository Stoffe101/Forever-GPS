-- The one file that knows EasyFind's and EasyFind GPS's insides. Everything else
-- in Forever-GPS asks here, so an upstream update has a single place to break,
-- and `/fgps diag` a single place to report from.
local _, FG = ...
local Bridge = {}
FG.Bridge = Bridge

local function NS() return EasyFind and EasyFind._ns end
Bridge.NS = NS

local function GPS()
    local ns = NS()
    return ns and ns.GPS
end

-- EasyFind's API, when EasyFind_Questie offers this action.
local function QuestieAction(name)
    local API = EasyFind and EasyFind.API
    return API and API.HasAction and API.HasAction("questie", name) and API or nil
end

-- What navigation needs, by name: Bridge.Missing() lists what is absent.
local REQUIRED = {
    { "EasyFind", function() return EasyFind end },
    { "EasyFind.API", function() return EasyFind and EasyFind.API end },
    { "EasyFind GPS", function() local n = NS() return n and n.GPS end },
    { "GPS route engine", function() local n = NS() return n and n.GPSRoute end },
    { "Forever route data", function() local n = NS() return n and n.GPSData end },
    { "GPS.BuildRoute", function() local g = GPS() return g and g.BuildRoute end },
    { "GPS.Navigated", function() local g = GPS() return g and g.Navigated end },
    { "GPS.Plan", function() local g = GPS() return g and g.Plan end },
    { "GPS.Destination", function() local g = GPS() return g and g.Destination end },
    { "GPS.LeadsTo", function() local g = GPS() return g and g.LeadsTo end },
    { "GPS.CurrentRoute", function() local g = GPS() return g and g.CurrentRoute end },
    { "GPS.StepText", function() local g = GPS() return g and g.StepText end },
    { "GPS.PlayerStart", function() local g = GPS() return g and g.PlayerStart end },
}

function Bridge.Missing()
    local out = {}
    for i = 1, #REQUIRED do
        local ok, have = pcall(REQUIRED[i][2])
        if not (ok and have) then out[#out + 1] = REQUIRED[i][1] end
    end
    return out
end

function Bridge.Ready() return #Bridge.Missing() == 0 end

-- ==== the route =============================================================

function Bridge.Route()
    local g = GPS()
    return g and g.CurrentRoute and g.CurrentRoute() or nil
end

-- The route being followed: not yet arrived.
function Bridge.ActiveRoute()
    local route = Bridge.Route()
    if route and not route.arrived then return route end
    return nil
end

function Bridge.IsPlanning()
    local g = GPS()
    return g ~= nil and g.IsPlanning ~= nil and g:IsPlanning() or false
end

function Bridge.Stop()
    local g = GPS()
    if g and g.Clear then g:Clear({ stay = true }) end
end

function Bridge.StepText(step, active)
    local g = GPS()
    if not (g and step) then return "" end
    local ok, text = pcall(g.StepText, step, active)
    return ok and text or step.text or ""
end

function Bridge.Follow()
    local ns = NS()
    local f = ns and ns.GPSFollow
    return f and f.Now and f.Now() or nil
end

function Bridge.OnRide()
    local ns = NS()
    local b = ns and ns.GPSBoats
    return b and b.Carried and b.Carried() or false
end

-- ==== destinations ==========================================================

function Bridge.CanNavigate(data)
    local g = GPS()
    if not (g and data) then return false end
    local ok, can = pcall(g.CanNavigate, g, data)
    return ok and can == true
end

-- The route's destination for a search row or a { name, mapID, x, y } table.
function Bridge.DestinationOf(data)
    local g = GPS()
    return g.Destination(g.LeadsTo(data))
end

function Bridge.WorldPos(mapID, x, y)
    local g = GPS()
    if not (g and g.WorldPos) then return nil end
    return g.WorldPos(mapID, x, y)
end

function Bridge.PlayerStart()
    local g = GPS()
    return g and g.PlayerStart and g.PlayerStart() or nil
end

function Bridge.MapName(mapID)
    local info = mapID and C_Map.GetMapInfo(mapID)
    return info and info.name or nil
end

-- ==== searching =============================================================

-- The map search's places for a query. Its Show choices belong to the map tab
-- and leave creatures out by default, so they are lifted for this one search.
function Bridge.SearchPlaces(query)
    local g = GPS()
    if not (g and g.SearchPlaces and EasyFind.db) then return {} end
    local db = EasyFind.db
    local saved = db.mapTabFilters
    db.mapTabFilters = nil
    local ok, rows = pcall(g.SearchPlaces, query)
    db.mapTabFilters = saved
    if ok and rows then return rows end
    return {}
end

-- EasyFind walks every map for dungeons and raids once, in slices, and its first
-- search finds none until that is done. Asked ahead of the first search.
function Bridge.WarmSearch()
    local ns = NS()
    local MapSearch = ns and ns.MapSearch
    if MapSearch and MapSearch.HasGlobalInstanceCache and not MapSearch:HasGlobalInstanceCache()
        and MapSearch.RequestGlobalInstanceCache then
        pcall(MapSearch.RequestGlobalInstanceCache, MapSearch, function(ready)
            if ready and MapSearch.ResetSearchPoisCache then MapSearch.ResetSearchPoisCache() end
        end)
    end
    if ns and ns.GPSNpcs and ns.GPSNpcs.Load then pcall(ns.GPSNpcs.Load) end
    Bridge.StartWorldIndex()
end

-- Questie's names, indexed a few milliseconds a frame until done.
local WORLD_SLICE_MS = 3
local worldRunner
function Bridge.StartWorldIndex()
    if worldRunner or not QuestieAction("warmWorld") then return end
    worldRunner = CreateFrame("Frame")
    worldRunner:SetScript("OnUpdate", function(self)
        if Bridge.WarmWorld(WORLD_SLICE_MS) then self:SetScript("OnUpdate", nil) end
    end)
end

function Bridge.AreaName(area)
    if not area then return nil end
    local name = C_Map.GetAreaInfo(area)
    return type(name) == "string" and name ~= "" and name or nil
end

-- Every map and town the route data names: what a misspelling is checked against.
function Bridge.PlaceNames()
    local ns = NS()
    local data = ns and ns.GPSData
    local out, seen = {}, {}
    local function Add(name)
        if name and not seen[name] then
            seen[name] = true
            out[#out + 1] = name
        end
    end
    for _, node in pairs(data and data.nodes or {}) do Add((node.n or ""):gsub(",", " ")) end
    for area in pairs(data and data.binds or {}) do Add(Bridge.AreaName(area)) end
    for m in pairs(ns and ns.NPC_DATA and ns.NPC_DATA.planes or {}) do Add(Bridge.MapName(m)) end
    return out
end

-- Rides as the route data lists them.
function Bridge.TransportEdges()
    local ns = NS()
    return ns and ns.GPSData and ns.GPSData.edges or {}
end

-- ==== Questie's world =======================================================

-- A slice of building Questie's name index; true once it is built.
function Bridge.WarmWorld(budget)
    local API = QuestieAction("warmWorld")
    if not API then return true end
    return API.CallAction("questie", "warmWorld", budget) == true
end

function Bridge.FindWorld(query, limit)
    local API = QuestieAction("findWorld")
    return API and API.CallAction("questie", "findWorld", query, limit) or nil
end

function Bridge.WorldSpots(kind, id)
    local API = QuestieAction("worldSpots")
    return API and API.CallAction("questie", "worldSpots", kind, id) or nil
end

function Bridge.NpcKnown(npcID)
    local ns = NS()
    local N = ns and ns.GPSNpcs
    if not (N and N.HasID) then return false end
    local ok, has = pcall(N.HasID, npcID)
    return ok and has == true
end

function Bridge.IsKindQuery(query)
    local ns = NS()
    local fn = ns and ns.MapSearch and ns.MapSearch.NpcKindQuery
    if not fn then return false end
    local ok, kind = pcall(fn, query)
    return ok and kind == true
end

-- Every spot a creature stands at, { mapID, x, y } each.
function Bridge.NpcSpots(npcID)
    local ns = NS()
    local N = ns and ns.GPSNpcs
    if not (N and N.SpotsOf and npcID) then return nil end
    local ok, spots = pcall(N.SpotsOf, npcID)
    if not (ok and spots) then return nil end
    local out = {}
    for i = 1, #spots do
        local s = spots[i]
        out[i] = { mapID = s.m, x = s.x, y = s.y, spawns = s.spawns }
    end
    return out
end

-- 0 friendly, 1 neutral, 2 hostile to the player; nil when unknown.
function Bridge.NpcReaction(npcID)
    local ns = NS()
    local N = ns and ns.GPSNpcs
    if not (N and N.ReactionOf and npcID) then return nil end
    local ok, reaction = pcall(N.ReactionOf, npcID, UnitFactionGroup("player") == "Horde")
    return ok and reaction or nil
end

-- ==== planning ==============================================================

local function Copy(t)
    local out = {}
    for k, v in pairs(t or {}) do out[k] = v end
    return out
end

-- The ways of travel left out by the player's own choice.
function Bridge.BaseAvoid()
    return Copy(EasyFind.db and EasyFind.db.gpsAvoid)
end

function Bridge.AvoidKinds()
    local g = GPS()
    return g and g.AvoidKinds and g.AvoidKinds() or {}
end

function Bridge.SetAvoid(kind, on)
    local db = EasyFind.db
    if not db then return end
    db.gpsAvoid = db.gpsAvoid or {}
    db.gpsAvoid[kind] = on and true or nil
end

function Bridge.AvoidOn(kind)
    local db = EasyFind.db
    return db ~= nil and db.gpsAvoid ~= nil and db.gpsAvoid[kind] == true
end

-- What the active route was planned under.
function Bridge.RouteAvoid()
    local route = Bridge.ActiveRoute()
    return route and route.wayAvoid or (EasyFind.db and EasyFind.db.gpsAvoid) or nil
end

-- A plan in the planner's slices. Only one runs at a time and a newer one replaces
-- it, and a replaced plan's done is never called. So who owns the running plan
-- matters: a plan of ours gone out of date may be replaced; the engine's reroutes
-- and walks never are. Every plan passes through here to be told apart.
local planIsOurs, marking = false, false
local function MarkPlans()
    local g = GPS()
    if not g or g._fgpsPlan then return end
    g._fgpsPlan = g.Plan
    function g:Plan(...)
        planIsOurs, marking = marking, false
        return self._fgpsPlan(self, ...)
    end
end

function Bridge.PlanIsOurs() return planIsOurs and Bridge.IsPlanning() end

function Bridge.PlanOurs(build, done)
    MarkPlans()
    marking = true
    GPS():Plan(nil, build, function(...)
        planIsOurs = false
        return done(...)
    end, true)
end

function Bridge.BuildRoute(dest, avoid, draw)
    return GPS():BuildRoute(dest, nil, avoid, true, draw)
end

function Bridge.BuildTrip(stops, avoid, draw)
    return NS().GPSTrip.Build(stops, nil, avoid, true, draw)
end

-- A trip's stops not reached yet.
function Bridge.StopsAhead(route)
    local g = GPS()
    return g and g.StopsAhead and g.StopsAhead(route) or nil
end

-- A route the engine would give, priced with straight-line walks: the same
-- graph, flights, boats, faction rules and hearth as a real route, without
-- searching the walking grid, so it costs a millisecond rather than a slice.
function Bridge.EstimateRoute(dest, avoid, start)
    local ns = NS()
    local Route, data = ns.GPSRoute, ns.GPSData
    local ground = Route.GroundSpeed(data) or 7
    -- Ground yards run longer than the straight line by the engine's own 1.2.
    return Route:Build(dest, { start = start, canFly = true, flySpeed = ground / 1.2, groundSpeed = ground,
                               advise = false, avoid = avoid })
end

-- Comparing routes changes the walking grid's settings, and the active route's
-- drawn walks are keyed under them. Put back the ones the active route uses, or
-- the arrow would lose its walk.
function Bridge.RestoreNav()
    local ns = NS()
    local Nav = ns and ns.GPSNav
    if not (Nav and Nav.SetDanger) then return end
    local avoid = Bridge.RouteAvoid()
    local Npcs, Jumps = ns.GPSNpcs, ns.GPSJumps
    local danger = avoid and avoid.danger and Npcs and Npcs.DangerTiles
    Nav.SetDanger(danger and Npcs.DangerTiles(UnitLevel("player"), UnitFactionGroup("player")) or nil)
    Nav.SetRoads(avoid and avoid.offroad)
    if Nav.SetDropLimit then
        local route = Bridge.ActiveRoute()
        local start = route and route.from or Bridge.PlayerStart()
        local jumps = not (avoid and avoid.jumps)
        Nav.SetDropLimit(jumps and Jumps and start and Jumps.Limit(start.ci) or nil)
    end
end

-- Starts navigation with steps already planned, on the way they were planned.
function Bridge.Commit(dest, steps, total, advice, avoid, stops)
    local g = GPS()
    g.Navigated(dest, steps, total, advice, stops)
    local route = g.CurrentRoute()
    if route then route.wayAvoid = avoid end
    -- Its walks are drawn from the next frame on: under its own settings.
    Bridge.RestoreNav()
    return route
end

-- ==== risk's inputs =========================================================

function Bridge.WalkOf(step, index, route)
    local ns = NS()
    local Follow, Engine = ns.GPSFollow, ns.GPSRoute
    if not (Follow and Engine and Engine.WalkPath) then return nil end
    local sci, sx, sy = Follow.StartOf(route, index)
    local tci, tx, ty = Follow.World(step.go or step.arrive)
    if not (sci and sci == tci) then return nil end
    return Engine.WalkPath(sci, sx, sy, tx, ty, true, step.near), sci
end

-- A route's walks by step: { [index] = path }, read as they stand now. The engine
-- keys them under the grid's settings, so these are only found while those hold.
function Bridge.WalksOf(route)
    local out = {}
    for i, step in ipairs(route.steps) do
        if step.kind == "travel" and not step.fly and not step.corpse then
            local path = Bridge.WalkOf(step, i, route)
            if path then out[i] = path end
        end
    end
    return out
end

-- ==== drawing on the world map ==============================================

function Bridge.NewMapLines(parent)
    local ns = NS()
    local Preview = ns and ns.GPSPreview
    return Preview and Preview.NewLines and Preview.NewLines(parent, "TOPLEFT") or nil
end

function Bridge.LineColor(kind)
    local ns = NS()
    return ns.GPSPreview.LineColor(kind)
end

function Bridge.LineSpan()
    local ns = NS()
    return ns.GPSPreview.Span()
end

function Bridge.DangerColor()
    local ns = NS()
    return ns.GPSPreview.DANGER_COLOR
end

-- Screen pixels as canvas units, which change with the map's zoom.
function Bridge.CanvasPx(v)
    local ns = NS()
    return ns.UIToCanvas and ns.UIToCanvas(v) or v
end

-- The part of a segment in map fractions that lies on the map, as t0, t1; or nil.
function Bridge.ClipToMap(x0, y0, x1, y1)
    local ns = NS()
    return ns.GPSPreview._OnMap(x0, y0, x1, y1)
end

-- Traces a whole walk, marking its deadly stretches: pen(red), then to(x, y) per point.
function Bridge.TraceWalk(path, ci, pen, to)
    local ns = NS()
    ns.GPSPreview.Trace(path, ci, 1, path.pts[1], path.pts[2], 0, pen, to)
end

function Bridge.DeadlyAlong(path, ci)
    local ns = NS()
    local Npcs = ns and ns.GPSNpcs
    if not (Npcs and Npcs.DeadlyAlong) then return nil end
    return Npcs.DeadlyAlong(path, ci, UnitLevel("player"), UnitFactionGroup("player"))
end

function Bridge.FlightNodes()
    local ns = NS()
    return ns and ns.GPSData and ns.GPSData.nodes or {}
end

-- ==== other surfaces ========================================================

-- Where the game itself puts a quest; nil where it gives no place.
function Bridge.QuestSpot(questID)
    local g = GPS()
    if not (g and g.QuestSpot) then return nil end
    local ok, mapID, x, y = pcall(g.QuestSpot, questID)
    if ok then return mapID, x, y end
    return nil
end

-- EasyFind's arrow at the character stands down while another leads. Held here,
-- not written to its settings: removing Forever-GPS must leave EasyFind as it was.
local arrowHeld = false
function Bridge.HoldCharacterArrow(held)
    local ns = NS()
    local Arrow = ns and ns.GPSArrow
    if not (Arrow and Arrow.Refresh) then return end
    if not Arrow._ownRefresh then
        Arrow._ownRefresh = Arrow.Refresh
        function Arrow:Refresh()
            if not arrowHeld then return self._ownRefresh(self) end
            if self._driver then self._driver:SetScript("OnUpdate", nil) end
            if _G.EasyFindGPSArrow then _G.EasyFindGPSArrow:Hide() end
        end
    end
    arrowHeld = held
    Arrow:Refresh()
end

-- px, py, ax, ay, yards left: where the walk leads from here.
function Bridge.ArrowAim()
    local ns = NS()
    local Arrow = ns and ns.GPSArrow
    if Arrow and Arrow._Aim then return Arrow._Aim() end
    return nil
end

-- The direction from the player to (ax, ay), relative to where they face.
function Bridge.Bearing(ci, px, py, ax, ay)
    local ns = NS()
    local Arrow = ns and ns.GPSArrow
    return Arrow and Arrow._Bearing and Arrow._Bearing(ci, px, py, ax, ay) or nil
end

-- The route's beacon draws an edge arrow unless an arrow leads. fn: whether
-- ours does. Wrapped once, however often it is asked.
local claimed
function Bridge.ClaimGuiding(fn)
    local ns = NS()
    local Arrow = ns and ns.GPSArrow
    if claimed or not (Arrow and Arrow.Guiding) then return end
    claimed = true
    local own = Arrow.Guiding
    function Arrow:Guiding() return fn() or own(self) end
end

function Bridge.SetEasyFindBar(on)
    local ns = NS()
    local bar = ns and ns.Search
    if on and bar and bar.Show then bar:Show()
    elseif not on and bar and bar.Hide then bar:Hide() end
    if EasyFind.db then EasyFind.db.visible = on and true or false end
end

function Bridge.EasyFindBar()
    return EasyFind.db ~= nil and EasyFind.db.visible ~= false
end

-- Upstream's events: routeStarted(dest), arrived(dest), routeCleared.
function Bridge.Listen()
    local API = EasyFind and EasyFind.API
    if not (API and API.On) then return end
    API.On("gps", "routeStarted", function(dest) FG.Emit("route:started", dest) end)
    API.On("gps", "arrived", function(dest) FG.Emit("route:arrived", dest) end)
    API.On("gps", "routeCleared", function() FG.Emit("route:cleared") end)
end

FG.On("loaded", Bridge.Listen)
FG.On("login", function()
    FG.After(6, Bridge.WarmSearch)
    -- A route back from a reload redraws its walks from the next frame on: under
    -- its own settings, which nothing else has set yet this session.
    if Bridge.ActiveRoute() then Bridge.RestoreNav() end
end)
