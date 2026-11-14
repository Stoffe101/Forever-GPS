-- ForeverGPS.API v2 on the real route engine and the real walking grid:
-- holding the arrow (another addon guides for a while; the journey runs on),
-- the "ended" event, and walks on foot for another addon's local routes.
local T = require("support.t")
local Stack = require("support.stack")

local GOLDSHIRE = { mapID = 1429, x = 0.42, y = 0.65 }
local SENTINEL = { mapID = 1436, x = 0.56, y = 0.47 }
-- Pairs whose straight line the walking grid does not walk (found with
-- build/probe_localpath.lua): Redridge across the hills, Elwynn's north.
local REDRIDGE = { mapID = 1433, ax = 0.3936, ay = 0.4670, bx = 0.4453, by = 0.4082 }
local ELWYNN_N = { mapID = 1429, ax = 0.2957, ay = 0.2507, bx = 0.3147, by = 0.2289 }

local function Start(opts)
    opts = opts or {}
    opts.mapID, opts.x, opts.y = opts.mapID or 1429, opts.x or 0.48, opts.y or 0.42
    return Stack.new(opts)
end

local function Go(c, dest, label, start)
    local token = c.FG.API.NavigateTo({ mapID = dest.mapID, x = dest.x, y = dest.y, label = label or "Farm",
                                        source = "TestAddon", start = start ~= false })
    T.ok(token, "a token")
    T.ok(Stack.Until(c, function() return c.FG.Bridge.ActiveRoute() ~= nil end, 30), "journey running")
    return token
end

-- The player starts a journey in Forever-GPS itself.
local function PlayerGoes(c, dest, name)
    c.FG.Planner.Inspect({ data = { name = name, mapID = dest.mapID, x = dest.x, y = dest.y }, name = name })
    T.ok(Stack.Until(c, function() return c.FG.Planner.Current().status == "ready" end, 30), "planned")
    c.FG.Planner.Start()
    c:Advance(0.5)
end

local tests = {}

function tests.version2_isAdvertised()
    local c = Start()
    T.ok(c.FG.API.VERSION >= 2)
    for _, fn in ipairs({ "HoldArrow", "ReleaseArrow", "ArrowHeld", "LocalPath", "LocalPaths", "LocalBound", "HasTerrain" }) do
        T.eq(type(c.FG.API[fn]), "function", fn)
    end
end

function tests.holdingTheArrow_hidesEveryArrow_butTheJourneyRunsOn()
    local c = Start()
    PlayerGoes(c, SENTINEL, "Sentinel Hill")
    T.eq(c.FG.Journey.ArrowMode(), "hud")
    local id = c.FG.API.HoldArrow("HarvestMateEnhanced", "guiding a farming loop")
    T.ok(id, "a hold")
    T.eq(c.FG.Journey.ArrowMode(), "held")
    local held, list = c.FG.API.ArrowHeld()
    T.ok(held)
    T.eq(list[1].source, "HarvestMateEnhanced")
    T.ok(c.FG.Bridge.ActiveRoute(), "the player's journey still runs")
    c:Advance(2)
    T.ok(c.FG.Bridge.ActiveRoute(), "and keeps running")
    T.ok(c.FG.API.ReleaseArrow(id), "released")
    T.eq(c.FG.Journey.ArrowMode(), "hud", "the arrow is back as the player set it")
    T.no(c.FG.API.ReleaseArrow(id), "a second release does nothing")
    T.no((c.FG.API.ArrowHeld()))
end

function tests.characterArrowMode_isHeldToo_andComesBack()
    local c = Start()
    c.FG.db.arrow = "character"
    c.FG.Journey.ApplyArrow()
    PlayerGoes(c, SENTINEL, "Sentinel Hill")
    local id = c.FG.API.HoldArrow("HarvestMateEnhanced")
    T.eq(c.FG.Journey.ArrowMode(), "held")
    local arrow = c.env.EasyFindGPSArrow
    if arrow then T.no(arrow:IsShown(), "EasyFind's arrow is hidden") end
    c.FG.API.ReleaseArrow(id)
    T.eq(c.FG.Journey.ArrowMode(), "character")
end

function tests.aJourneyThePlayerStartsLater_releasesEveryHold()
    local c = Start()
    local seen = {}
    c.FG.API.On("hold", function(id, held, why) seen[#seen + 1] = tostring(held) .. ":" .. tostring(why) end)
    PlayerGoes(c, SENTINEL, "Sentinel Hill")
    c.FG.API.HoldArrow("HarvestMateEnhanced")
    -- The same journey reported twice is not a new one.
    c.FG.Emit("route:started", c.FG.Bridge.ActiveRoute().dest)
    T.ok((c.FG.API.ArrowHeld()), "a duplicate event keeps the hold")
    PlayerGoes(c, GOLDSHIRE, "Goldshire")
    T.no((c.FG.API.ArrowHeld()), "the player's newest journey leads")
    T.eq(seen[#seen], "false:new journey")
    T.eq(c.FG.Journey.ArrowMode(), "hud")
end

function tests.holdsAreNotKeptOverAReload()
    local c = Start()
    c.FG.API.HoldArrow("HarvestMateEnhanced")
    local c2 = Start({ saved = Stack.Saved(c) })
    T.no((c2.FG.API.ArrowHeld()))
end

function tests.badHolds_areRefused()
    local c = Start()
    local id, why = c.FG.API.HoldArrow(nil)
    T.eq(id, nil)
    T.ok(why)
    T.no(c.FG.API.ReleaseArrow("nonsense"))
    T.no(c.FG.API.ReleaseArrow(nil))
end

function tests.endedIsReported_forEveryJourney()
    local c = Start()
    local ended = {}
    c.FG.API.On("ended", function(token, how) ended[#ended + 1] = tostring(token) .. ":" .. how end)
    PlayerGoes(c, SENTINEL, "Sentinel Hill")
    c.FG.StopNavigation()
    c:Advance(0.2)
    T.eq(ended[#ended], "nil:cleared", "the player's own journey ending is told too")
    local token = Go(c, GOLDSHIRE)
    c:SetPlayer(GOLDSHIRE.mapID, GOLDSHIRE.x, GOLDSHIRE.y)
    T.ok(Stack.Until(c, function() return c.FG.API.Status(token) == "arrived" end, 20), "arrived")
    T.eq(ended[#ended], token .. ":arrived")
end

-- ==== walks =================================================================

local function OnMap(points)
    for i = 1, #points do
        if not (points[i] >= 0 and points[i] <= 1) then return false end
    end
    return #points % 2 == 0
end

function tests.localPath_goesRoundWhatTheStraightLineCannotWalk()
    local c = Start()
    T.ok(c.FG.API.HasTerrain(1433))
    local epoch = c.ns.GPSNav.epoch
    for _, leg in ipairs({ REDRIDGE, ELWYNN_N }) do
        local r = c.FG.API.LocalPath(leg)
        T.eq(r.status, "path", "a way round")
        T.ok(r.yards > r.straight * 1.3, ("longer than the line (%.0f vs %.0f)"):format(r.yards, r.straight))
        T.ok(#r.points >= 6, "with turns")
        T.ok(#r.points / 2 <= 64, "within the default point bound")
        T.ok(OnMap(r.points), "every point on the map")
        T.eq(r.points[1], leg.ax)
        T.eq(r.points[#r.points], leg.by)
        local bound = c.FG.API.LocalBound(leg.mapID, leg.ax, leg.ay, leg.bx, leg.by)
        T.ok(bound == nil or bound <= r.yards * 1.1, "the bound is a lower bound")
    end
    T.eq(c.ns.GPSNav.epoch, epoch, "the grid's settings are as they were")
end

function tests.localPath_saysStraightWhereTheLineIsWalkable()
    local c = Start()
    local r = c.FG.API.LocalPath({ mapID = 1429, ax = 0.42, ay = 0.65, bx = 0.43, by = 0.655 })
    T.eq(r.status, "straight")
    T.eq(#r.points, 4)
    T.near(r.yards, r.straight, 0.01)
end

function tests.localPath_boundsPointsAndDistance_andRefusesBadInput()
    local c = Start()
    local r = c.FG.API.LocalPath({ mapID = REDRIDGE.mapID, ax = REDRIDGE.ax, ay = REDRIDGE.ay, bx = REDRIDGE.bx,
                                   by = REDRIDGE.by, maxPoints = 4 })
    T.eq(r.status, "path")
    T.ok(#r.points / 2 <= 4, "pulled to four points")
    T.eq(c.FG.API.LocalPath({ mapID = 1429, ax = 0.05, ay = 0.1, bx = 0.95, by = 0.9 }).status, "far")
    T.eq(c.FG.API.LocalPath({ mapID = 1429, ax = 2, ay = 0, bx = 0, by = 0 }).status, "invalid")
    T.eq(c.FG.API.LocalPath("Elwynn").status, "invalid")
    T.eq(c.FG.API.LocalPath({ mapID = 99999, ax = 0.1, ay = 0.1, bx = 0.2, by = 0.2 }).status, "invalid")
end

function tests.localPath_withoutTheGrid_saysNoData()
    local c = Start()
    c.ns.GPSNav = nil
    T.eq(c.FG.API.LocalPath(REDRIDGE).status, "nodata")
    T.no(c.FG.API.HasTerrain(1433))
end

function tests.localPaths_runAFewMillisecondsAFrame_andMatchTheOneAtATimeAnswer()
    local c = Start()
    local legs = {
        { REDRIDGE.ax, REDRIDGE.ay, REDRIDGE.bx, REDRIDGE.by },
        { REDRIDGE.bx, REDRIDGE.by, REDRIDGE.ax, REDRIDGE.ay },
        { 0.40, 0.45, 0.41, 0.46 },
    }
    -- Each look at the clock costs 0.5 ms: the searches must yield to fit.
    c.cpuStep = 0.5
    local got, frames
    local handle = c.FG.API.LocalPaths({ mapID = 1433, legs = legs, budgetMs = 4 }, function(results) got = results end)
    T.ok(handle)
    T.eq(handle:Status(), "queued")
    frames = 0
    while not got and frames < 20000 do
        c:Advance(0.02, 0.02)
        frames = frames + 1
    end
    c.cpuStep = nil
    T.ok(got, "finished")
    T.ok(frames > 3, "across several frames (" .. frames .. ")")
    T.eq(handle:Status(), "done")
    local done, of = handle:Progress()
    T.eq(done, 3)
    T.eq(of, 3)
    local one = c.FG.API.LocalPath(REDRIDGE)
    T.eq(got[1].status, one.status)
    T.near(got[1].yards, one.yards, 1)
    T.eq(got[2].status, "path")
    T.eq(c.ns.GPSNav.yieldCo, nil, "the grid is left as it was")
    T.eq(c.ns.GPSNav.sliceEnd, nil)
end

function tests.localPaths_canBeCancelled_andRefuseBadInput()
    local c = Start()
    local called = false
    local handle = c.FG.API.LocalPaths({ mapID = 1433, legs = { { REDRIDGE.ax, REDRIDGE.ay, REDRIDGE.bx, REDRIDGE.by } } },
        function() called = true end)
    T.ok(handle:Cancel())
    c:Advance(1)
    T.no(called, "a cancelled batch never answers")
    T.eq(handle:Status(), "cancelled")
    T.no(handle:Cancel())
    T.eq(c.FG.API.LocalPaths({ mapID = 1433, legs = {} }), nil)
    local many = {}
    for i = 1, 65 do many[i] = { 0.4, 0.4, 0.41, 0.41 } end
    T.eq(c.FG.API.LocalPaths({ mapID = 1433, legs = many }), nil)
    T.eq(c.FG.API.LocalPaths({ legs = { { 0.4, 0.4, 0.41, 0.41 } } }), nil)
end

function tests.localPaths_waitWhileAJourneyIsPlanned_andLeaveItsWalksAlone()
    local c = Start()
    local token = Go(c, SENTINEL)
    local route = c.FG.Bridge.ActiveRoute()
    local walks = 0
    for _ in pairs(c.FG.Bridge.WalksOf(route)) do walks = walks + 1 end
    local epoch = c.ns.GPSNav.epoch
    local got
    c.FG.API.LocalPaths({ mapID = 1433, legs = { { REDRIDGE.ax, REDRIDGE.ay, REDRIDGE.bx, REDRIDGE.by } } },
        function(r) got = r end)
    -- A plan of the player's starts at the same moment.
    c.FG.Planner.Inspect({ data = { name = "Goldshire", mapID = GOLDSHIRE.mapID, x = GOLDSHIRE.x, y = GOLDSHIRE.y },
                           name = "Goldshire" })
    T.ok(Stack.Until(c, function() return got ~= nil end, 60), "finished once the plan was done")
    T.eq(got[1].status, "path")
    T.eq(c.ns.GPSNav.epoch, epoch, "settings untouched")
    local after = 0
    for _ in pairs(c.FG.Bridge.WalksOf(route)) do after = after + 1 end
    T.eq(after, walks, "the journey's drawn walks are all still there")
    T.eq(c.FG.API.Status(token), "active", "and the journey is unchanged")
end

return tests
