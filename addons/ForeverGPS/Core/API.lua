-- Forever-GPS: the public API for other addons (ForeverGPS.API, version 2).
--
-- A small, versioned surface so an addon such as HarvestMate Enhanced can hand
-- a destination over and know, for certain, what happened to *its* journey,
-- without reaching into Forever-GPS's internals and without ever stopping a
-- journey the player chose. Additive only: later versions add, never change.
--
--   API.NavigateTo(spec) -> token | nil, reason
--       spec = { mapID, x, y, label?, source?, start? }
--       Plans a journey and shows it. With start = true (the player has just
--       asked for directions in the calling addon) the journey begins as soon as
--       it is planned; otherwise the player presses Go. Nothing protected runs.
--   API.Status(token)      "pending" | "active" | "arrived" | "cancelled" |
--                          "superseded" | "released" | "stale" | "unknown"
--   API.IsActive(token)    true while that journey is the one being followed
--   API.Current()          { token?, mapID, x, y, name } of the journey followed
--                          now (token only when it was started through the API)
--   API.Release(token)     stops the journey only if it is still that token's
--                          and still the one running; true if it did
--   API.EstimateSeconds(mapID, x, y)  travel estimate from here, or nil
--   API.On(event, fn)      "started" (token|nil, dest), "arrived" (token, dest),
--                          "cancelled" (token), "superseded" (token),
--                          "released" (token); v2 adds "ended" (token|nil, how)
--                          for every journey (how = "arrived" | "cleared") and
--                          "hold" (holdID, held, why)
--
-- Version 2 (additive):
--   API.HoldArrow(source, reason) -> holdID | nil, reason
--       While any hold stands no arrow of Forever-GPS points (HUD arrow,
--       EasyFind's character arrow, the TomTom mirror, the beacon's edge
--       arrow). The journey itself runs on untouched and the HUD keeps its
--       steps. For an addon that guides the player itself for a while. Holds
--       are not kept over /reload, and a journey the player starts afterwards
--       releases every hold: the player's newest choice leads.
--   API.ReleaseArrow(holdID) -> true if that hold stood
--   API.ArrowHeld()        true while any hold stands, then { {id, source, reason} }
--   API.HasTerrain(mapID)  whether the walking grid covers that map's continent
--   API.LocalPath(spec) -> result
--       spec = { mapID, ax, ay, bx, by (0-1 on mapID), maxPoints? (2-200, 64),
--                detour? (the most walk/straight ratio searched, 1.2-6, 4) }
--       One walk on foot on the walking grid, searched at once and bounded by
--       detour x the straight distance. It never changes the grid's settings
--       or the route being followed. result.status:
--         "straight"  the straight line is walkable (points: the two ends)
--         "path"      a way round: points { x1, y1, x2, y2, ... } on mapID
--         "detour"    no way within the detour bound (far round, or none)
--         "none"      no way on foot at all (another landmass, a closed cave)
--         "nodata"    no walking grid for that continent
--         "far"       ends more than LOCAL_MAX_YARDS apart: ask for shorter legs
--         "invalid"   bad input (reason says what)
--       Also yards (the walk), straight (yards), drops (falls above the safe
--       height), settings { roads, danger } (the grid settings it ran under).
--   API.LocalBound(mapID, ax, ay, bx, by) -> yards | nil
--       The least the walk can cost, from the grid's landmarks: a cheap test
--       of whether a leg can be straight at all, without a search.
--
-- A journey belongs to a token only from the moment a route starts whose
-- destination matches the request (same map, within MATCH_YARDS). Another
-- destination started meanwhile supersedes the request: that journey is the
-- player's. Duplicate events change nothing. The state survives /reload in
-- ForeverGPSCharDB.api and is checked against the route on login.
local FG = ForeverGPS
local Bridge, Planner = FG.Bridge, FG.Planner

local API = { VERSION = 1 }
FG.API = API

API.MATCH_YARDS = 80
local MAX_KEPT = 12

local listeners = { started = {}, arrived = {}, cancelled = {}, superseded = {}, released = {}, ended = {}, hold = {} }
local seq = 0

local function Store()
    if not FG.char then return { journeys = {}, order = {} } end
    local s = FG.char.api
    if type(s) ~= "table" or type(s.journeys) ~= "table" then
        s = { journeys = {}, order = {} }
        FG.char.api = s
    end
    s.order = type(s.order) == "table" and s.order or {}
    return s
end

local function Emit(event, ...)
    for _, fn in ipairs(listeners[event] or {}) do FG.Try(fn, ...) end
end

local function Set(j, state)
    if not j or j.state == state then return false end
    j.state = state
    j.changed = time()
    return true
end

local function Num(v) return type(v) == "number" and v == v and v or nil end

-- Same map (or the destination's zone) and within MATCH_YARDS in the world.
local function Matches(dest, want)
    if type(dest) ~= "table" or type(want) ~= "table" then return false end
    local dm, dx, dy = Num(dest.mapID or dest.m), Num(dest.x), Num(dest.y)
    if not (dm and dx and dy) then return false end
    local ci1, wx1, wy1 = Bridge.WorldPos(dm, dx, dy)
    local ci2, wx2, wy2 = Bridge.WorldPos(want.mapID, want.x, want.y)
    if ci1 and ci2 and wx1 and wx2 then
        if ci1 ~= ci2 then return false end
        return (wx1 - wx2) ^ 2 + (wy1 - wy2) ^ 2 <= API.MATCH_YARDS ^ 2
    end
    return dm == want.mapID and math.abs(dx - want.x) < 0.01 and math.abs(dy - want.y) < 0.01
end
API._Matches = Matches

local function Pending()
    local s = Store()
    for i = #s.order, 1, -1 do
        local j = s.journeys[s.order[i]]
        if j and j.state == "pending" then return j end
    end
end

local function Current()
    local s = Store()
    return s.current and s.journeys[s.current] or nil
end

local function Remember(j)
    local s = Store()
    s.journeys[j.token] = j
    s.order[#s.order + 1] = j.token
    while #s.order > MAX_KEPT do
        local old = table.remove(s.order, 1)
        if old ~= s.current then s.journeys[old] = nil end
    end
end

function API.NavigateTo(spec)
    if type(spec) ~= "table" then return nil, "spec must be a table" end
    local mapID, x, y = Num(spec.mapID), Num(spec.x), Num(spec.y)
    if not (mapID and x and y) or x < 0 or x > 1 or y < 0 or y > 1 then return nil, "mapID, x and y (0-1) are needed" end
    if not Bridge.Ready() then return nil, "Forever-GPS is not ready" end
    local name = type(spec.label) == "string" and spec.label:sub(1, 80) or nil
    local data = { name = name or ("Map " .. mapID), mapID = mapID, x = x, y = y }
    if not Bridge.CanNavigate(data) then return nil, "Forever-GPS cannot plan to that place" end
    -- An earlier request still waiting is replaced by this one.
    local older = Pending()
    if older then Set(older, "superseded") end
    seq = seq + 1
    local source = type(spec.source) == "string" and spec.source:gsub("[^%w_%-]", ""):sub(1, 32) or "addon"
    local token = ("%s-%d-%d"):format(source ~= "" and source or "addon", time(), seq)
    local j = { token = token, source = source, dest = { mapID = mapID, x = x, y = y, name = data.name },
                state = "pending", t = time(), start = spec.start == true }
    Remember(j)
    if FG.Window and FG.Window.Show then FG.Try(FG.Window.Show, "search") end
    Planner.Inspect({ data = data, name = data.name })
    if FG.Window and FG.Window.ShowRoute then FG.Try(FG.Window.ShowRoute) end
    j.plan = Planner.Current()
    return token
end

function API.Status(token)
    local j = Store().journeys[token]
    return j and j.state or "unknown"
end

function API.IsActive(token)
    local j = Store().journeys[token]
    if not (j and j.state == "active") then return false end
    local route = Bridge.ActiveRoute()
    return route ~= nil and Matches(route.dest, j.dest)
end

function API.Current()
    local route = Bridge.ActiveRoute()
    if not (route and route.dest) then return nil end
    local d = route.dest
    local j = Current()
    local token = j and j.state == "active" and Matches(d, j.dest) and j.token or nil
    return { token = token, mapID = d.mapID, x = d.x, y = d.y, name = d.name }
end

function API.Release(token)
    local s = Store()
    local j = s.journeys[token]
    if not (j and j.state == "active" and s.current == token) then return false end
    local route = Bridge.ActiveRoute()
    if not (route and Matches(route.dest, j.dest)) then return false end
    Set(j, "released")
    s.current = nil
    Bridge.Stop()
    Emit("released", token)
    return true
end

function API.EstimateSeconds(mapID, x, y)
    if not (FG.Eta and FG.Eta.Now) then return nil end
    local ok, dest = pcall(Bridge.DestinationOf, { mapID = mapID, x = x, y = y, name = "" })
    if not ok or not dest then return nil end
    local ok2, value = pcall(FG.Eta.Now, dest)
    if ok2 and type(value) == "table" and Num(value.sec) then return value.sec end
    return nil
end

function API.On(event, fn)
    if listeners[event] and type(fn) == "function" then
        table.insert(listeners[event], fn)
        return true
    end
    return false
end

-- Planned: start it when the caller asked for that.
FG.On("plan:done", function()
    local j = Pending()
    if not (j and j.start) then return end
    local p = Planner.Current()
    if p and p.status == "ready" and p == j.plan then Planner.Start() end
end)

FG.On("route:started", function(dest)
    local s = Store()
    local now = Current()
    if now and now.state == "active" and Matches(dest, now.dest) and not Pending() then return end   -- the same journey again
    local j = Pending()
    if j and Matches(dest, j.dest) then
        local was = Current()
        if was and was ~= j and was.state == "active" and Set(was, "superseded") then Emit("superseded", was.token) end
        Set(j, "active")
        s.current = j.token
        Emit("started", j.token, dest)
        return
    end
    -- Another destination: whatever the API had is now the player's journey.
    local was = Current()
    if was and was.state == "active" and Set(was, "superseded") then
        s.current = nil
        Emit("superseded", was.token)
    end
    if j and Set(j, "superseded") then Emit("superseded", j.token) end
    Emit("started", nil, dest)
end)

FG.On("route:arrived", function(dest)
    local j = Current()
    if j and j.state == "active" and Matches(dest, j.dest) and Set(j, "arrived") then
        Emit("arrived", j.token, dest)
    end
end)

FG.On("route:cleared", function()
    local s = Store()
    local j = Current()
    if j and j.state == "active" and Set(j, "cancelled") then
        s.current = nil
        Emit("cancelled", j.token)
    elseif j and j.state ~= "active" then
        s.current = nil
    end
end)

-- After a reload: a journey the API thought active must still be the route.
FG.On("login", function()
    local s = Store()
    local j = Current()
    if not j or j.state ~= "active" then return end
    local route = Bridge.ActiveRoute()
    if not (route and Matches(route.dest, j.dest)) then
        Set(j, "stale")
        s.current = nil
    end
end)

-- ==== version 2: holding the arrow ==========================================

API.VERSION = 2

local holds, holdN = {}, 0

local function Clean(v, n)
    if type(v) ~= "string" then return nil end
    v = v:gsub("%c", ""):sub(1, n)
    return v ~= "" and v or nil
end

local function ApplyHolds()
    if FG.Journey and FG.Journey.ApplyArrow then FG.Try(FG.Journey.ApplyArrow) end
end

function API.ArrowHeld()
    if next(holds) == nil then return false, {} end
    local list = {}
    for id, h in pairs(holds) do list[#list + 1] = { id = id, source = h.source, reason = h.reason } end
    table.sort(list, function(a, b) return a.id < b.id end)
    return true, list
end

function API.HoldArrow(source, reason)
    source = Clean(source, 32)
    if not source then return nil, "source is needed" end
    holdN = holdN + 1
    local id = ("hold-%s-%d"):format((source:gsub("[^%w_%-]", "")), holdN)
    holds[id] = { source = source, reason = Clean(reason, 80), t = time() }
    ApplyHolds()
    Emit("hold", id, true)
    return id
end

function API.ReleaseArrow(id)
    if id == nil or not holds[id] then return false end
    holds[id] = nil
    ApplyHolds()
    Emit("hold", id, false, "released")
    return true
end

local function DropHolds(why)
    if next(holds) == nil then return end
    local ids = {}
    for id in pairs(holds) do ids[#ids + 1] = id end
    for _, id in ipairs(ids) do holds[id] = nil end
    ApplyHolds()
    for _, id in ipairs(ids) do Emit("hold", id, false, why) end
end

-- A journey the player starts leads with its arrow, whoever held it. The same
-- journey reported again (a duplicate event) is not a new one.
local lastStarted
FG.On("route:started", function(dest)
    local same = lastStarted ~= nil and Matches(dest, lastStarted)
    local m = type(dest) == "table" and Num(dest.mapID or dest.m)
    lastStarted = m and { mapID = m, x = dest.x, y = dest.y } or nil
    if not same then DropHolds("new journey") end
end)

FG.On("route:arrived", function(dest)
    local j = Current()
    local token = j and j.state == "arrived" and Matches(dest, j.dest) and j.token or nil
    Emit("ended", token, "arrived")
end)

FG.On("route:cleared", function()
    lastStarted = nil
    Emit("ended", nil, "cleared")
end)

-- ==== version 2: walks on the walking grid ==================================

API.LOCAL_MAX_YARDS = 1500
local LOCAL_POINTS, LOCAL_POINTS_MAX = 64, 200

local function Unit(v)
    v = Num(v)
    return v and v >= 0 and v <= 1 and v or nil
end

local function Ends(mapID, ax, ay, bx, by)
    mapID, ax, ay, bx, by = Num(mapID), Unit(ax), Unit(ay), Unit(bx), Unit(by)
    if not (mapID and ax and ay and bx and by) then return nil, "mapID and four 0-1 coordinates are needed" end
    local ci, wax, way = Bridge.WorldPos(mapID, ax, ay)
    local ci2, wbx, wby = Bridge.WorldPos(mapID, bx, by)
    if not (ci and ci2 and wax and wbx) then return nil, "that map has no world position" end
    if ci ~= ci2 then return nil, "the ends are on different continents" end
    return ci, wax, way, wbx, wby
end

function API.HasTerrain(mapID)
    local Nav = Bridge.Nav()
    if not (Nav and Num(mapID)) then return false end
    local ci = Bridge.WorldPos(mapID, 0.5, 0.5)
    return ci ~= nil and Nav.Has(ci) or false
end

function API.LocalBound(mapID, ax, ay, bx, by)
    local Nav = Bridge.Nav()
    if not (Nav and Nav.Bound) then return nil end
    local ci, wax, way, wbx, wby = Ends(mapID, ax, ay, bx, by)
    if not ci or not Nav.Has(ci) then return nil end
    local ok, v = pcall(Nav.Bound, ci, wax, way, wbx, wby)
    return ok and Num(v) or nil
end

-- Keeps the turns that matter: drops points nearer than tol yards to the
-- line between the points kept around them (Douglas-Peucker); the ends stay.
local function Simplify(pts, tol)
    local n = #pts / 2
    if n <= 2 then return pts end
    local keep = { [1] = true, [n] = true }
    local stack = { { 1, n } }
    while #stack > 0 do
        local seg = table.remove(stack)
        local a, b = seg[1], seg[2]
        local ax, ay, bx, by = pts[2 * a - 1], pts[2 * a], pts[2 * b - 1], pts[2 * b]
        local dx, dy = bx - ax, by - ay
        local len2 = dx * dx + dy * dy
        local far, at = -1, nil
        for i = a + 1, b - 1 do
            local px, py = pts[2 * i - 1], pts[2 * i]
            local d
            if len2 == 0 then
                d = (px - ax) ^ 2 + (py - ay) ^ 2
            else
                local t = math.max(0, math.min(1, ((px - ax) * dx + (py - ay) * dy) / len2))
                d = (px - ax - t * dx) ^ 2 + (py - ay - t * dy) ^ 2
            end
            if d > far then far, at = d, i end
        end
        if at and far > tol * tol then
            keep[at] = true
            stack[#stack + 1] = { a, at }
            stack[#stack + 1] = { at, b }
        end
    end
    local out = {}
    for i = 1, n do
        if keep[i] then out[#out + 1], out[#out + 2] = pts[2 * i - 1], pts[2 * i] end
    end
    return out
end
API._Simplify = Simplify

local function GridSettings()
    local avoid = Bridge.RouteAvoid()
    return { roads = avoid and avoid.offroad and true or false, danger = avoid and avoid.danger and true or false }
end


-- Inside a batch's coroutine the grid's searches may yield (Nav.Pause), and
-- Lua 5.1 cannot yield through pcall: there they are called directly and the
-- coroutine's resume catches what fails.
local function Direct(fn, ...) return true, fn(...) end

local function Solve(spec, call)
    if type(spec) ~= "table" then return { status = "invalid", reason = "spec must be a table" } end
    local ci, wax, way, wbx, wby = Ends(spec.mapID, spec.ax, spec.ay, spec.bx, spec.by)
    if not ci then return { status = "invalid", reason = wax } end
    local mapID = spec.mapID
    local straight = math.sqrt((wbx - wax) ^ 2 + (wby - way) ^ 2)
    local out = { straight = straight, settings = GridSettings() }
    local Nav = Bridge.Nav()
    if not (Nav and Nav.Has(ci)) then
        out.status = "nodata"
        return out
    end
    if straight > API.LOCAL_MAX_YARDS then
        out.status = "far"
        return out
    end
    local maxPoints = math.floor(math.max(2, math.min(LOCAL_POINTS_MAX, Num(spec.maxPoints) or LOCAL_POINTS)))
    local detour = math.max(1.2, math.min(6, Num(spec.detour) or 4))
    local ok, clear = call(Nav.Straight, ci, wax, way, wbx, wby)
    if ok and clear == true then
        out.status, out.yards = "straight", straight
        out.points = { spec.ax, spec.ay, spec.bx, spec.by }
        return out
    end
    local limit = math.max(straight * detour, straight + 60)
    local okW, cost, beyond = call(Nav.Walk, ci, wax, way, wbx, wby, { limit = limit })
    if not okW then
        out.status, out.reason = "invalid", "the walking grid failed: " .. tostring(cost)
        return out
    end
    if not cost then
        out.status = beyond and "detour" or "none"
        return out
    end
    local okP, pts, _, walked, jumps = call(Nav.Path, ci, wax, way, wbx, wby, { limit = limit })
    if not (okP and type(pts) == "table" and #pts >= 4) then
        out.status = "detour"
        return out
    end
    -- Fewer points: pulled tighter until they fit.
    local tol = 2
    local simple = Simplify(pts, tol)
    while #simple / 2 > maxPoints and tol < 400 do
        tol = tol * 2
        simple = Simplify(pts, tol)
    end
    local flat = {}
    for i = 1, #simple - 1, 2 do
        local x, y = Bridge.MapPos(ci, simple[i], simple[i + 1], mapID)
        if not (x and y) then
            out.status, out.reason = "invalid", "a point fell off the map"
            return out
        end
        flat[#flat + 1], flat[#flat + 2] = x, y
    end
    flat[1], flat[2], flat[#flat - 1], flat[#flat] = spec.ax, spec.ay, spec.bx, spec.by
    out.status, out.points = "path", flat
    out.yards = Num(walked) or cost
    out.drops = jumps and #jumps or 0
    return out
end

-- One walk, searched at once (a long one can take a tenth of a second: for
-- many, or from a frame that must stay smooth, use API.LocalPaths).
function API.LocalPath(spec) return Solve(spec, pcall) end

-- ==== version 2: many walks, a few milliseconds a frame =====================
--   API.LocalPaths(spec, done) -> handle | nil, reason
--       spec = { mapID, legs = { { ax, ay, bx, by }, ... } (1-64),
--                maxPoints?, detour?, budgetMs? (1-12, the planner's own share) }
--       Searches each leg as API.LocalPath would, inside a coroutine that gives
--       the frame back when its budget is spent. While Forever-GPS plans a
--       route it waits, and a search a plan ran across is started again (the
--       grid's scratch is shared). done(results, handle) once all are found;
--       results[i] is leg i's result. handle:Cancel() stops it (done is not
--       called), handle:Status() is "queued" | "running" | "done" | "cancelled",
--       handle:Progress() the legs done and of how many.
API.LOCAL_LEGS_MAX = 64

local queue, driver = {}, nil

local function Leg(job, i)
    local leg = job.legs[i]
    local spec = { mapID = job.mapID, ax = leg[1], ay = leg[2], bx = leg[3], by = leg[4],
                   maxPoints = job.maxPoints, detour = job.detour }
    return coroutine.create(function() return Solve(spec, Direct) end)
end

local function Finish(job)
    table.remove(queue, 1)
    job.state = "done"
    if job.done then FG.Try(job.done, job.results, job.handle) end
end

local function Step()
    local job = queue[1]
    while job and job.state == "cancelled" do
        table.remove(queue, 1)
        job = queue[1]
    end
    if not job then
        if driver then driver:SetScript("OnUpdate", nil) end
        return
    end
    -- A plan of Forever-GPS's own runs: it owns the grid's planning scratch.
    if Bridge.IsPlanning() then return end
    local Nav = Bridge.Nav()
    if not Nav then
        for i = job.next, #job.legs do job.results[i] = { status = "nodata" } end
        return Finish(job)
    end
    if job.co and Bridge.PlanSerial() ~= job.serial then job.co = nil end   -- a plan ran across it
    job.state = "running"
    local stop = debugprofilestop() + job.budget
    repeat
        if not job.co then
            job.co, job.serial = Leg(job, job.next), Bridge.PlanSerial()
        end
        Nav.yieldCo, Nav.sliceEnd = job.co, stop
        local ok, res = coroutine.resume(job.co)
        Nav.yieldCo, Nav.sliceEnd = nil, nil
        if coroutine.status(job.co) ~= "dead" then return end   -- the budget is spent
        job.results[job.next] = ok and type(res) == "table" and res or { status = "invalid", reason = tostring(res) }
        job.next, job.co = job.next + 1, nil
        if job.next > #job.legs then return Finish(job) end
    until debugprofilestop() > stop
end

function API.LocalPaths(spec, done)
    if type(spec) ~= "table" or type(spec.legs) ~= "table" then return nil, "spec.legs is needed" end
    local n = #spec.legs
    if n < 1 or n > API.LOCAL_LEGS_MAX then return nil, ("1 to %d legs"):format(API.LOCAL_LEGS_MAX) end
    if not Num(spec.mapID) then return nil, "mapID is needed" end
    local legs = {}
    for i = 1, n do
        local l = spec.legs[i]
        if type(l) ~= "table" then return nil, "leg " .. i .. " is not a table" end
        legs[i] = { l[1] or l.ax, l[2] or l.ay, l[3] or l.bx, l[4] or l.by }
    end
    local budget = Num(spec.budgetMs) or Bridge.PlanBudget()
    local job = { mapID = spec.mapID, legs = legs, results = {}, next = 1, state = "queued",
                  maxPoints = spec.maxPoints, detour = spec.detour, budget = math.max(1, math.min(12, budget)),
                  done = type(done) == "function" and done or nil }
    local handle = {}
    function handle:Cancel()
        if job.state == "done" or job.state == "cancelled" then return false end
        job.state, job.co = "cancelled", nil
        return true
    end
    function handle:Status() return job.state end
    function handle:Progress() return job.next - 1, #job.legs end
    job.handle = handle
    queue[#queue + 1] = job
    if not driver then driver = CreateFrame("Frame") end
    driver:SetScript("OnUpdate", Step)
    return handle
end

-- ==== version 2: the nearest service ========================================
--   API.NavigateToService(kind, spec?) -> true, name | false, reason
--       kind = "mailbox" | "vendor" | "repair" | "inn" | "bank" | "auction" |
--       "trainer" (spec.profession = "Skinning" ...). Searches as "nearest
--       <kind>" in Forever-GPS (enemy ground passed over) and opens that
--       journey for the player to start with Go. A one-off trip: no token.
API.SERVICES = { mailbox = "mailbox", vendor = "general goods", repair = "repair", inn = "innkeeper",
                 bank = "bank", auction = "auction house" }

function API.NavigateToService(kind, spec)
    spec = type(spec) == "table" and spec or {}
    local query = API.SERVICES[kind]
    if kind == "trainer" and type(spec.profession) == "string" then
        query = spec.profession:gsub("[^%a ]", ""):sub(1, 30) .. " trainer"
    end
    if not query then return false, "unknown service" end
    if not Bridge.Ready() then return false, "Forever-GPS is not ready" end
    local ok, results = pcall(FG.Search.Run, "nearest " .. query)
    if not ok or type(results) ~= "table" then return false, "the search failed" end
    local pick
    for _, r in ipairs(results) do
        if not r.hostile then
            pick = r
            break
        end
    end
    if not pick then return false, "none found" end
    if FG.Window and FG.Window.Show then FG.Try(FG.Window.Show, "search") end
    Planner.Inspect(pick)
    if FG.Window and FG.Window.ShowRoute then FG.Try(FG.Window.ShowRoute) end
    return true, pick.name
end
