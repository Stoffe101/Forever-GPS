-- ForeverGPS.API v1 on the real route engine (real EasyFind GPS, real data):
-- tokens, ownership, arrival, cancellation, another destination taking over,
-- release that never stops someone else's journey, reload, bad input.
local T = require("support.t")
local Stack = require("support.stack")

local GOLDSHIRE = { mapID = 1429, x = 0.42, y = 0.65 }
local SENTINEL = { mapID = 1436, x = 0.56, y = 0.47 }

local function Start(opts)
    opts = opts or {}
    opts.mapID, opts.x, opts.y = opts.mapID or 1429, opts.x or 0.48, opts.y or 0.42
    return Stack.new(opts)
end

local function Events(c)
    local seen = {}
    for _, e in ipairs({ "started", "arrived", "cancelled", "superseded", "released" }) do
        c.FG.API.On(e, function(token) seen[#seen + 1] = e .. ":" .. tostring(token) end)
    end
    return seen
end

local function Count(seen, prefix)
    local n = 0
    for _, e in ipairs(seen) do if e:sub(1, #prefix) == prefix then n = n + 1 end end
    return n
end

-- Requests a journey with start = true and waits until it runs.
local function Go(c, dest, label)
    local token = c.FG.API.NavigateTo({ mapID = dest.mapID, x = dest.x, y = dest.y, label = label or "Farm",
                                        source = "TestAddon", start = true })
    T.ok(token, "a token")
    T.ok(Stack.Until(c, function() return c.FG.API.Status(token) == "active" end, 30), "started once planned")
    return token
end

local tests = {}

function tests.aRequestBecomesActiveOnlyWhenItsJourneyStarts()
    local c = Start()
    local seen = Events(c)
    local token = c.FG.API.NavigateTo({ mapID = GOLDSHIRE.mapID, x = GOLDSHIRE.x, y = GOLDSHIRE.y, source = "TestAddon" })
    T.eq(c.FG.API.Status(token), "pending", "waiting for the player to press Go")
    T.no(c.FG.API.IsActive(token))
    T.ok(Stack.Until(c, function() return c.FG.Planner.Current().status == "ready" end, 30), "planned")
    T.eq(c.FG.API.Status(token), "pending", "without start = true nothing starts by itself")
    c.FG.Planner.Start()
    c:Advance(0.5)
    T.eq(c.FG.API.Status(token), "active")
    T.ok(c.FG.API.IsActive(token))
    T.eq(c.FG.API.Current().token, token, "Current names the token")
    T.eq(Count(seen, "started:" .. token), 1, "one started event")
end

function tests.arrivalIsReportedOnce_andTheLaterClearIsNotACancel()
    local c = Start()
    local seen = Events(c)
    local token = Go(c, GOLDSHIRE)
    c:SetPlayer(GOLDSHIRE.mapID, GOLDSHIRE.x, GOLDSHIRE.y)
    T.ok(Stack.Until(c, function() return c.FG.API.Status(token) == "arrived" end, 20), "arrived")
    c:Advance(30)   -- Forever-GPS clears an arrived route after a moment
    T.eq(c.FG.API.Status(token), "arrived", "still arrived, not cancelled")
    T.eq(Count(seen, "arrived:"), 1)
    T.eq(Count(seen, "cancelled:"), 0)
end

function tests.thePlayerCancelling_isACancel()
    local c = Start()
    local seen = Events(c)
    local token = Go(c, GOLDSHIRE)
    c.FG.StopNavigation()
    c:Advance(0.2)
    T.eq(c.FG.API.Status(token), "cancelled")
    T.eq(Count(seen, "cancelled:" .. token), 1)
end

function tests.anotherDestination_supersedes_andReleaseNeverStopsIt()
    local c = Start()
    local seen = Events(c)
    local token = Go(c, GOLDSHIRE)
    -- The player picks somewhere else in Forever-GPS.
    c.FG.Planner.Inspect({ data = { name = "Sentinel Hill", mapID = SENTINEL.mapID, x = SENTINEL.x, y = SENTINEL.y },
                           name = "Sentinel Hill" })
    T.ok(Stack.Until(c, function() return c.FG.Planner.Current().status == "ready" end, 30), "planned")
    c.FG.Planner.Start()
    c:Advance(0.5)
    T.eq(c.FG.API.Status(token), "superseded")
    T.eq(Count(seen, "superseded:" .. token), 1)
    T.eq(c.FG.API.Current().token, nil, "the running journey is the player's")
    T.no(c.FG.API.Release(token), "Release refuses")
    T.ok(c.FG.Bridge.ActiveRoute(), "and the player's journey keeps running")
end

function tests.releaseStopsOnlyItsOwnJourney_once()
    local c = Start()
    local token = Go(c, GOLDSHIRE)
    T.ok(c.FG.API.Release(token), "released")
    T.no(c.FG.Bridge.ActiveRoute(), "the journey stopped")
    T.eq(c.FG.API.Status(token), "released")
    T.no(c.FG.API.Release(token), "a second release does nothing")
end

function tests.duplicateEvents_changeNothing()
    local c = Start()
    local seen = Events(c)
    local token = Go(c, GOLDSHIRE)
    local dest = c.FG.Bridge.ActiveRoute().dest
    c.FG.Emit("route:started", dest)
    c.FG.Emit("route:started", dest)
    T.eq(Count(seen, "started:" .. token), 1, "started once")
    T.eq(c.FG.API.Status(token), "active")
end

function tests.afterAReload_aJourneyThatEnded_isStale()
    local c = Start()
    local token = Go(c, GOLDSHIRE)
    -- The route vanished while the UI reloaded.
    c.env.EasyFind._ns.GPS:Clear()
    c.FG.char.api.journeys[token].state = "active"
    c.FG.char.api.current = token
    c.FG.Emit("login")
    T.eq(c.FG.API.Status(token), "stale")
end

function tests.badInput_isRefused_withAReason()
    local c = Start()
    local token, why = c.FG.API.NavigateTo({ mapID = 1429, x = 3, y = 0.5 })
    T.eq(token, nil)
    T.ok(why, "says why")
    token, why = c.FG.API.NavigateTo("Goldshire")
    T.eq(token, nil)
    T.ok(why)
    T.eq(c.FG.API.Status("nonsense"), "unknown")
end

function tests.estimateSeconds_givesATime()
    local c = Start()
    local secs = c.FG.API.EstimateSeconds(SENTINEL.mapID, SENTINEL.x, SENTINEL.y)
    T.ok(type(secs) == "number" and secs > 0, "seconds: " .. tostring(secs))
end

return tests
