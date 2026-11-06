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

-- A plan in the planner's slices. Only one runs at a time and a newer one
-- replaces it, so callers wait for IsPlanning to clear first. done(...) gets
-- what build returns, and is simply not called if a newer plan took over.
function Bridge.Plan(build, done)
    GPS():Plan(nil, build, done, true)
end

function Bridge.BuildRoute(dest, avoid, draw)
    return GPS():BuildRoute(dest, nil, avoid, true, draw)
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
        local start = Bridge.PlayerStart()
        local jumps = not (avoid and avoid.jumps)
        Nav.SetDropLimit(jumps and Jumps and start and Jumps.Limit(start.ci) or nil)
    end
end

-- Starts navigation with steps already planned, on the way they were planned.
function Bridge.Commit(dest, steps, total, advice, avoid)
    local g = GPS()
    g.Navigated(dest, steps, total, advice)
    local route = g.CurrentRoute()
    if route then route.wayAvoid = avoid end
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

function Bridge.SetCharacterArrow(on)
    local ns = NS()
    if EasyFind.db then EasyFind.db.gpsArrow = on end
    if ns and ns.GPSArrow and ns.GPSArrow.Refresh then ns.GPSArrow:Refresh() end
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
FG.On("login", function() FG.After(6, Bridge.WarmSearch) end)
