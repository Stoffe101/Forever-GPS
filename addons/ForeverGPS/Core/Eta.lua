-- Travel-time estimates for lists: "how far is this, really?" for search results
-- and quest areas. Each is the route engine's own graph with straight-line
-- walks (Bridge.EstimateRoute), so a boat, a flight or a hearth counts, and a
-- place across a sea reads as far as it is. Run in small slices while nothing
-- else plans, and remembered briefly.
local _, FG = ...
local Eta = {}
FG.Eta = Eta

local Bridge = FG.Bridge

local BUDGET_MS = 4          -- a frame's work at most
local CELL = 40              -- yards the player may move before estimates refresh
local KEEP_SECONDS = 60
local MAX_KEPT = 256

local queue, head, tail = {}, 1, 0
local cache, cached = {}, 0
local runner

local function Key(dest, cell, avoidKey)
    return ("%s:%.3f:%.3f:%s:%s"):format(dest.mapID or 0, dest.x or 0, dest.y or 0, cell, avoidKey)
end

local function AvoidKey(avoid)
    local parts = {}
    for k, v in pairs(avoid or {}) do
        if v then parts[#parts + 1] = k end
    end
    table.sort(parts)
    return table.concat(parts, ",")
end

local function Remember(key, value)
    if cached >= MAX_KEPT then
        cache, cached = {}, 0
    end
    if not cache[key] then cached = cached + 1 end
    cache[key] = { value = value, at = GetTime() }
end

-- { sec, transports } or false (no way), estimated now.
function Eta.Now(dest, avoid, start)
    start = start or Bridge.PlayerStart()
    if not (start and dest) then return nil end
    local cell = ("%d:%d:%d"):format(start.ci, math.floor(start.wx / CELL), math.floor(start.wy / CELL))
    avoid = avoid or Bridge.RouteAvoid()
    local key = Key(dest, cell, AvoidKey(avoid))
    local hit = cache[key]
    if hit and GetTime() - hit.at < KEEP_SECONDS then return hit.value end
    local ok, steps, total = pcall(Bridge.EstimateRoute, dest, avoid, start)
    local value = false
    if ok and steps and total then
        value = { sec = total, transports = FG.Kinds.Summary(steps) }
    elseif not ok then
        geterrorhandler()(steps)
    end
    Remember(key, value)
    return value
end

local function Pump()
    if Bridge.IsPlanning() then return end
    local stop = debugprofilestop() + BUDGET_MS
    while head <= tail do
        local job = queue[head]
        queue[head] = nil
        head = head + 1
        if job.alive() then
            job.done(Eta.Now(job.dest))
        end
        if debugprofilestop() >= stop then return end
    end
    head, tail = 1, 0
    runner:SetScript("OnUpdate", nil)
end

-- Asks for dest's estimate; done(value) comes in a later frame, while alive()
-- still says the asker cares.
function Eta.Request(dest, done, alive)
    if not runner then runner = CreateFrame("Frame") end
    tail = tail + 1
    queue[tail] = { dest = dest, done = done, alive = alive or function() return true end }
    runner:SetScript("OnUpdate", Pump)
end

-- Where the player can learn a new flight path, the known set moved.
function Eta.Forget() cache, cached = {}, 0 end

-- After EasyFind GPS has recorded what the flight master showed.
FG.OnEvent("TAXIMAP_OPENED", function() FG.After(0.2, Eta.Forget) end)
FG.OnEvent("HEARTHSTONE_BOUND", Eta.Forget)
