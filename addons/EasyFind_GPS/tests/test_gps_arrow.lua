-- Tests for Arrow.lua and Follow.lua: the arrow at the character
-- aims a little ahead along the walk, turns at its bends, leads alongside
-- the walk a few yards out, and finds the walk again when the player strays.
local H = require("Harness")

-- An L-shaped walk in world yards: 100 north, then 100 west (opts.ty: fewer);
-- found from where the player stands, or with planned, from where the route
-- was planned. opts.pts draws another walk from its ends. With opts.planner,
-- only the walk from the planned start is drawn; others wait for
-- planner.draw(), as the game's planner draws them in its slices.
local function fresh(planned, opts)
    opts = opts or {}
    local env = H.newEnv()
    local ns = H.newNs(env)
    env.EasyFind._ns = ns
    env.UIParent = H.newFrame()
    local now = { t = 100 }
    env.GetTime = function() return now.t end
    local player = { x = 0, y = 0 }
    local finds = {}
    local clear = { v = true }
    local route = { steps = { { kind = "travel", go = { ci = 1, wx = opts.tx or 100, wy = opts.ty or 100 } } }, active = 1,
                    from = planned and { ci = 1, wx = 0, wy = 0 } or nil }
    local planner = { asked = {}, drawn = {} }
    local function key(sx, sy, tx, ty) return sx .. ":" .. sy .. ">" .. tx .. ":" .. ty end
    function planner.draw()
        for _, a in ipairs(planner.asked) do planner.drawn[key(a[1], a[2], a[3], a[4])] = true end
    end
    ns.GPS = {
        CurrentRoute = function() return route end,
        PlayerWorldPos = function() return 1, player.x, player.y end,
        DrawWalk = function(_, sx, sy, tx, ty) planner.asked[#planner.asked + 1] = { sx, sy, tx, ty } return true end,
    }
    ns.GPSRoute = {
        WalkPath = function(_, sx, sy, tx, ty, lazy)
            if opts.planner and lazy and not (sx == 0 and sy == 0) and not planner.drawn[key(sx, sy, tx, ty)] then
                return nil
            end
            finds[#finds + 1] = { sx, sy, tx, ty }
            local pts = { sx, sy, 100, sy, tx, ty }
            if opts.pts then pts = opts.pts(sx, sy, tx, ty) end
            if pts == false then return false end
            local cum, len = { 0 }, 0
            for v = 2, #pts / 2 do
                len = len + math.sqrt((pts[2 * v - 1] - pts[2 * v - 3]) ^ 2 + (pts[2 * v] - pts[2 * v - 2]) ^ 2)
                cum[v] = len
            end
            return { pts = pts, cum = cum, len = len }
        end,
    }
    ns.GPSNav = { Straight = function() return clear.v end }
    H.loadModule("Follow.lua", env, ns)
    H.loadModule("Arrow.lua", env, ns)
    return ns.GPSArrow._Aim, player, finds, now, clear, planner, ns
end

-- The L-shaped walk from the planned start; a straight way from anywhere else.
local function straightOff(sx, sy, tx, ty)
    if sx == 0 and sy == 0 then return { 0, 0, 100, 0, tx, ty } end
    return { sx, sy, tx, ty }
end

local tests = {}

function tests.alongAStraightRunItPointsAhead()
    local Aim, player = fresh()
    player.x = 50
    local px, py, ax, ay, left = Aim()
    H.assertEq(px, 50)
    H.assertEq(py, 0)
    H.assertEq(ax, 75, "a little ahead along the walk")
    H.assertEq(ay, 0)
    H.assertEq(left, 150, "the yards left on the walk")
end

function tests.nearABendItPointsRoundIt()
    local Aim, player = fresh(false, { ty = 30 })
    player.x = 95
    local _, _, ax, ay = Aim()
    H.assertEq(ax, 100)
    H.assertEq(ay, 20, "past the bend, not at the spot straight ahead")
end

function tests.aWalkHardlyLongerThanTheLineAimsAtTheSpot()
    -- From (0,0) to (100,100) by way of (52,48): a wiggle, not a way round.
    local Aim, player = fresh(true, { pts = function(sx, sy, tx, ty) return { sx, sy, 52, 48, tx, ty } end })
    player.x, player.y = 0, 0
    local _, _, ax, ay = Aim()
    H.assertEq(ax, 100, "the spot itself, not a point along the wiggle")
    H.assertEq(ay, 100)
end

function tests.aWayRoundHardlyLongerIsFollowed()
    -- From (0,0) to (100,0) by way of (50,-20): only 8% longer, but 20 yards
    -- off the line, as a walk out along a pier to its end.
    local Aim, player = fresh(true, { ty = 0, pts = function(sx, sy, tx, ty) return { sx, sy, 50, -20, tx, ty } end })
    player.x, player.y = 0, 0
    local _, _, ax, ay = Aim()
    H.assertTrue(ay < -5, "along the walk, not across to the spot")
    H.assertTrue(ax > 20 and ax < 30)
end

-- A straight walk 1000 yd east; 40 yd off it at 50 yd along, the way back
-- joins it 240 yd ahead (six times the yards off), at (290, 0).
local LONG = { tx = 1000, ty = 0, pts = straightOff }
local WAY_BACK = math.sqrt(240 ^ 2 + 40 ^ 2)

function tests.aWalkFoundAgainIsDrawnByThePlanner()
    local Aim, player, _, now, _, planner = fresh(true, { planner = true, tx = 1000, ty = 0, pts = straightOff })
    player.x = 50
    Aim()
    H.assertEq(#planner.asked, 0, "the walk from the planned start is drawn already")
    player.y = 40
    now.t = now.t + 5
    local _, _, ax, ay = Aim()
    H.assertEq(#planner.asked, 1, "a walk from here is asked of the planner")
    H.assertEq(planner.asked[1][2], 40)
    H.assertEq(ax, 75, "the drawn walk meanwhile, led back alongside it")
    H.assertEq(ay, 10)
    now.t = now.t + 1
    Aim()
    H.assertEq(#planner.asked, 1, "asked once while it draws")
    planner.draw()
    now.t = now.t + 1
    local left
    _, _, ax, ay, left = Aim()
    H.assertTrue(ax > 70 and ax < 80 and ay > 30 and ay < 40, "then along the way back, at a shallow angle: " .. ax .. "," .. ay)
    H.assertTrue(math.abs(left - (WAY_BACK + 710)) < 0.01, "the way back, then the walk's rest: " .. left)
end

-- Straying 40 yd off the walk at 50 yd along: the way back joins it far
-- ahead, at (290, 0), and the arrow leads along that way at once.
function tests.offTheWayItLeadsBackOntoTheWalkAhead()
    local Aim, player, finds, now = fresh(true, LONG)
    player.x = 50
    Aim()
    player.y = 40
    now.t = now.t + 5
    local _, _, ax, ay, left = Aim()
    H.assertEq(finds[#finds][3], 290, "the way back asked to a point far ahead on the walk")
    H.assertEq(finds[#finds][4], 0)
    H.assertTrue(ax > 70 and ay < 40 and ay > 30, "led along the way back: " .. ax .. "," .. ay)
    H.assertTrue(math.abs(left - (WAY_BACK + 710)) < 0.01, "the walk's rest kept: " .. left)
    now.t = now.t + 1
    player.x, player.y = 74, 36
    Aim()
    H.assertEq(#finds, 2, "on the way back: nothing asked again")
end

-- Keeping on 40 yd beside the walk: the way back is asked anew from where
-- the player stands once he has strayed from it, each to a point far ahead
-- of him on the walk, so the arrow never turns back to where it was last
-- asked; at that shallow angle only now and then, not every second.
function tests.besideTheWalkTheWayBackSlidesAlong()
    local Aim, player, finds, now = fresh(true, LONG)
    player.x = 50
    Aim()
    player.y = 40
    now.t = now.t + 5
    Aim()
    H.assertEq(#finds, 2)
    local asked = 2
    for _ = 1, 20 do
        now.t = now.t + 1
        player.x = player.x + 7
        local px, _, ax = Aim()
        H.assertTrue(ax > px, "the arrow leads ahead: " .. ax .. " from " .. px)
        if #finds > asked then
            asked = #finds
            H.assertEq(finds[asked][1], player.x, "asked anew from where the player stands")
            H.assertEq(finds[asked][2], 40)
            H.assertTrue(finds[asked][3] >= player.x + 80, "to a point far ahead on the walk: " .. finds[asked][3])
        end
    end
    H.assertTrue(asked >= 5 and asked <= 10, "asked now and then over 20 s: " .. (asked - 2) .. " times")
end

-- A way back asked of the planner runs it, and the planner redraws every
-- surface as it starts: a reader called in the middle of the follower's
-- own reading gets the frame before's whole one, never a half-built one
-- with no path (the minimap flashed a straight line to the step's end
-- once a second beside the walk, 2026-11-01).
function tests.aReaderMidReadingGetsTheLastWholeOne()
    local Aim, player, _, now, _, planner, ns = fresh(true, { planner = true, pts = straightOff })
    local Follow, draw = ns.GPSFollow, ns.GPS.DrawWalk
    local seen
    ns.GPS.DrawWalk = function(...)
        seen = Follow.Now()
        return draw(...)
    end
    player.x = 50
    Aim()
    player.y = 40
    now.t = now.t + 5
    local f = Follow.Now()
    H.assertEq(#planner.asked, 1, "the way back asked")
    H.assertTrue(seen ~= nil and seen ~= f, "a reading mid-ask: the one before")
    H.assertTrue(seen.path == f.path and seen.path ~= false, "with its path, not the half-built one's none")
    H.assertEq(seen.py, 0, "taken where the player stood the frame before")
    H.assertEq(f.py, 40, "the reading after the ask is this frame's")
end

-- On a way back from off the walk, the reading carries the walk's own way
-- behind it, up to abreast of where the player left it: drawn as walked.
function tests.theWayBackKeepsTheWalkBehindIt()
    local Aim, player, _, now, _, _, ns = fresh(true, { pts = straightOff })
    player.x = 50
    Aim()
    player.y = 40
    now.t = now.t + 5
    Aim()
    local f = ns.GPSFollow.Now()
    H.assertEq(f.path.pts[1], 50, "the way followed starts where the player stands")
    H.assertEq(f.path.pts[2], 40)
    local trail = f.trail
    H.assertTrue(trail ~= nil, "with the walk's own way behind it")
    H.assertEq(trail.path.pts[1], 0, "from the walk's start")
    H.assertEq(trail.seg, 1, "its stretches up to abreast of the player")
    H.assertEq(trail.x, 50, "to the point abreast of him")
    H.assertEq(trail.y, 0)
    player.y = 0
    now.t = now.t + 5
    Aim()
    f = ns.GPSFollow.Now()
    H.assertTrue(f.trail ~= nil, "kept while the way back is followed")
end

-- With no way back onto the walk, the whole way from here takes over as
-- soon as the planner has drawn it; till then the arrow keeps to the walk.
local function wayRound(sx, sy, tx, ty)
    if sx == 0 and sy == 0 then return { 0, 0, 500, 0, tx, ty } end
    if not (tx == 500 and ty == 500) then return false end
    return { sx, sy, tx, ty }
end

function tests.withNoWayBackAWholeWayTakesOverOnceDrawn()
    local Aim, player, _, now, _, planner = fresh(true, { planner = true, tx = 500, ty = 500, pts = wayRound })
    player.x = 50
    Aim()
    player.y = 40
    now.t = now.t + 5
    local _, _, _, ay = Aim()
    H.assertTrue(ay < 30, "the drawn walk while the way back is asked: " .. ay)
    planner.draw()
    now.t = now.t + 1
    _, _, _, ay = Aim()
    H.assertTrue(ay < 30, "no way back: the whole way asked, the walk meanwhile: " .. ay)
    H.assertEq(#planner.asked, 2)
    planner.draw()
    now.t = now.t + 1
    _, _, _, ay = Aim()
    H.assertEq(ay, 500, "drawn: taken at once, straight along it to the spot")
end

-- The way back onto the walk goes far round (300 yd south and back for 40
-- yd off): the arrow leads along it, and the straight way from here takes
-- over as soon as it is drawn, being far shorter.
function tests.aWayBackFarRoundGivesWayToAWholeWay()
    local Aim, player, _, now, _, planner = fresh(true, { planner = true, tx = 500, ty = 500,
        pts = function(sx, sy, tx, ty)
            if sx == 0 and sy == 0 then return { 0, 0, 500, 0, tx, ty } end
            if not (tx == 500 and ty == 500) then return { sx, sy, sx, -300, tx, -300, tx, ty } end
            return { sx, sy, tx, ty }
        end })
    player.x = 50
    Aim()
    player.y = 40
    now.t = now.t + 5
    Aim()
    planner.draw()
    now.t = now.t + 1
    local _, _, ax, ay = Aim()
    H.assertTrue(ax == 50 and ay < 40, "along the way back meanwhile: " .. ax .. "," .. ay)
    H.assertEq(#planner.asked, 2, "far round: the whole way from here asked")
    planner.draw()
    now.t = now.t + 1
    _, _, _, ay = Aim()
    H.assertEq(ay, 500, "the whole way taken: straight to the spot")
end

-- Just off a lift, its top door 21 yd from its foot: a way from the player
-- there started on the Ruins and ran through the sewers (2026-11-04). By
-- the lift the walk keeps to its own way; walked off, ways from here again.
function tests.besideTheLiftJustTaken_theWalkKeepsToItsOwnWay()
    local Aim, player, _, now, _, planner, ns = fresh(false, { planner = true, tx = 500, ty = 500, pts = wayRound })
    local route = ns.GPS.CurrentRoute()
    local walkStep = route.steps[1]
    route.steps = { { kind = "elevator", go = { ci = 1, wx = 0, wy = 21 }, arrive = { ci = 1, wx = 0, wy = 0 } }, walkStep }
    route.active = 2
    player.x, player.y = 0, 21
    for _ = 1, 4 do
        Aim()
        planner.draw()
        now.t = now.t + 5
    end
    local _, _, _, ay = Aim()
    H.assertTrue(ay < 30, "along the walk from the lift's foot: " .. ay)
    H.assertEq(#planner.asked, 0, "no way asked from the player beside the lift")
    player.x, player.y = 0, 60
    for _ = 1, 3 do
        Aim()
        planner.draw()
        now.t = now.t + 5
    end
    H.assertTrue(#planner.asked > 0, "walked off: a way from here again")
end

-- A lift's step, replayed from a ride down Undercity's east lift (/efd
-- gpslift, 2026-11-04): on its platform the arrow turned back to the door
-- boarded, and stepped off the far side the follower asked a way back to
-- that door from the city level, out through the sewers (1788 yd).
function tests.aLiftsStep_inItsShaftAimsAtItsFarDoor_neverWalksBack()
    local Aim, player, _, now, _, planner, ns = fresh(false, { planner = true })
    local route = ns.GPS.CurrentRoute()
    route.steps = { { kind = "elevator", go = { ci = 1, wx = 0, wy = 19 }, arrive = { ci = 1, wx = 0, wy = 0 } } }
    player.x, player.y = 0, 9.5
    local _, _, ax, ay = Aim()
    H.assertTrue(ax == 0 and ay == 0, "on the platform: the far door: " .. tostring(ax) .. "," .. tostring(ay))
    player.x, player.y = 12, -15
    for _ = 1, 4 do
        _, _, ax, ay = Aim()
        planner.draw()
        now.t = now.t + 5
    end
    H.assertTrue(ax == 0 and ay == 0, "stepped off at an angle: still the far door")
    H.assertEq(#planner.asked, 0, "no way on foot asked from the player")
    H.assertEq(ns.GPSFollow.ThroughLift(route.steps[1], 1, 0, 9.5), 0.5, "the platform: half way through")
end

function tests.aWayNoFasterIsNeverTaken()
    local Aim, player, finds, now = fresh(true, { pts = function(sx, sy, tx, ty)
        if sx == 0 and sy == 0 then return { 0, 0, 100, 0, tx, ty } end
        return { sx, sy, sx, -200, 100, -200, tx, ty }
    end })
    player.x = 50
    Aim()
    player.y = 40
    for _ = 1, 6 do
        now.t = now.t + 5
        player.x = player.x - 21
        local _, _, _, ay = Aim()
        H.assertTrue(ay <= 30, "kept to the drawn walk: " .. ay)
    end
    H.assertTrue(#finds > 2, "asked again further on: " .. #finds)
end

function tests.offTheWayTheWalkIsFoundAgain()
    local Aim, player, finds, now = fresh()
    player.x = 50
    Aim()
    H.assertEq(#finds, 1)
    player.y = 40
    now.t = now.t + 5
    Aim()
    H.assertEq(#finds, 2, "found again from where the player stands")
    H.assertEq(finds[2][2], 40)
end

function tests.closeToTheWayItKeepsTheWalk()
    local Aim, player, finds, now = fresh()
    player.x = 30
    Aim()
    player.x, player.y = 60, 5
    now.t = now.t + 5
    Aim()
    H.assertEq(#finds, 1, "a few yards off is still on the way")
end

function tests.theWalkRunsFromWhereTheRouteWasPlanned()
    local Aim, player, finds = fresh(true)
    player.x = 50
    Aim()
    H.assertEq(finds[1][1], 0)
    H.assertEq(finds[1][2], 0)
end

local function near(a, b) return math.abs(a - b) < 1e-9 end

function tests.besideTheWalkItLeadsAlongside()
    local Aim, player = fresh(true)
    player.x, player.y = 50, 6
    local _, _, ax, ay = Aim()
    H.assertTrue(near(ax, 75))
    H.assertTrue(near(ay, 6), "alongside the walk, not back onto it: " .. ay)
end

function tests.fartherOutItLeadsBackToTheLane()
    local Aim, player = fresh(true)
    player.x, player.y = 50, 15
    local _, _, ax, ay = Aim()
    H.assertTrue(near(ax, 75))
    H.assertTrue(near(ay, 10), "back to 10 yd beside the walk: " .. ay)
end

function tests.withSomethingBetweenItLeadsOntoTheWalk()
    local Aim, player, _, _, clear = fresh(true)
    clear.v = false
    player.x, player.y = 50, 6
    local _, _, ax, ay = Aim()
    H.assertTrue(near(ax, 75))
    H.assertTrue(near(ay, 0))
end

function tests.nearTheEndItMakesForTheSpot()
    local Aim, player = fresh(true)
    player.x, player.y = 106, 90
    local _, _, ax, ay, left = Aim()
    H.assertTrue(near(left, 10))
    H.assertTrue(near(ax, 100) and near(ay, 100), "the spot itself: " .. ax .. "," .. ay)
end

-- The bearing reads north and west off the map, whichever way the world's
-- coordinates run: map up is north, map left is west.
local function bearingWith(toWorld)
    local env = H.newEnv()
    local ns = H.newNs(env)
    env.EasyFind._ns = ns
    env.UIParent = H.newFrame()
    env.C_Map = { GetBestMapForUnit = function() return 7 end }
    ns.GPSRoute = { WorldPos = function(_, x, y) return 1, toWorld(x, y) end }
    H.loadModule("Follow.lua", env, ns)
    H.loadModule("Arrow.lua", env, ns)
    return ns.GPSArrow._Bearing
end

function tests.bearingFromNorthTowardWest()
    -- x north, y west
    local Bearing = bearingWith(function(mx, my) return (0.5 - my) * 1000, (0.5 - mx) * 1000 end)
    H.assertTrue(near(Bearing(1, 0, 0, 10, 0), 0), "north is straight on")
    H.assertTrue(near(Bearing(1, 0, 0, 0, 10), math.pi / 2), "west a quarter turn left")
    -- x east, y north: the same places, other numbers
    Bearing = bearingWith(function(mx, my) return (mx - 0.5) * 1000, (0.5 - my) * 1000 end)
    H.assertTrue(near(Bearing(1, 0, 0, 0, 10), 0), "north is straight on")
    H.assertTrue(near(Bearing(1, 0, 0, -10, 0), math.pi / 2), "west a quarter turn left")
end

local pass, fail, failures = H.runSuite("GPSArrow", tests)
return { pass = pass, fail = fail, failures = failures }
