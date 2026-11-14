-- Forever-GPS: the public API for other addons (ForeverGPS.API, version 1).
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
--                          "released" (token)
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

local listeners = { started = {}, arrived = {}, cancelled = {}, superseded = {}, released = {} }
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
