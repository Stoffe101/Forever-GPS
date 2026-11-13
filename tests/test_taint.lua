-- The map taint: Blizzard's quest pins refreshed in our name, and refused in combat.
-- support/client.lua models that chain from the game's public UI source, and docs/TAINT.md
-- says what was found. A green run here shows the addon stays off every path the model
-- has. It cannot show the real client agrees: only a session in the game can.
local T = require("support.t")
local Stack = require("support.stack")

local AUBERDINE = { name = "Auberdine", mapID = 1439, x = 0.37, y = 0.44 }
local GOLDSHIRE = { name = "Goldshire", mapID = 1429, x = 0.42, y = 0.65 }

local function Start(opts)
    opts = opts or {}
    opts.mapID, opts.x, opts.y = opts.mapID or 1453, opts.x or 0.6, opts.y or 0.6
    return Stack.new(opts)
end

local function Plan(c, dest)
    local P = c.FG.Planner
    P.Inspect({ data = dest or AUBERDINE, name = (dest or AUBERDINE).name })
    T.ok(Stack.Until(c, function()
        local p = P.Current()
        return p.status == "ready" or p.status == "failed" or p.status == "unreachable"
    end, 30), "the plan finishes")
    c:Advance(0.3)
end

local function Go(c, dest)
    Plan(c, dest)
    c.FG.Planner.Start()
    c:Advance(1.5)
    return c.FG.Bridge.ActiveRoute()
end

local function Reach(c, step)
    local p = step.arrive
    c:SetPlayer(p.m, p.x, p.y)
    c:Advance(2.2)
end

local function Combat(c, on)
    c.player.combat = on
    c:Fire(on and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
    c:Advance(0.2)
end

-- Opens and closes the map by hand, which arms the quest pins' callback for good.
local function MapSeen(c)
    c:PlayerToggleMap()
    c:Advance(0.2)
    c:PlayerToggleMap()
    c:Advance(0.2)
end

local function Clean(c, label)
    local t = c.taint
    T.eq(#t.blocked, 0, (label or "") .. " nothing refused: " .. (t.blocked[1] and t.blocked[1].what or ""))
    T.eq(#t.mapWrites, 0, (label or "") .. " the game's map left alone: " .. (t.mapWrites[1] and t.mapWrites[1].what or ""))
    for _, call in ipairs(t.calls) do
        T.no(call.combat, (label or "") .. " nothing of the game's changed in a fight: " .. call.what)
        T.no(call.mapShown, (label or "") .. " nothing of the game's changed under the map: " .. call.what)
    end
    T.eq(#c.env.UISpecialFrames, 0, (label or "") .. " the game's Escape list left alone")
    T.eq(#c.errors, 0, (label or "") .. " no errors")
end

local tests = {}

-- ==== the reported error ====================================================

-- The map seen once, then a step of a journey changing in a fight: this is the stack.
function tests.aStepChangingInAFight_refreshesNoPinsInOurName()
    local c = Start()
    MapSeen(c)
    local route = Go(c)
    Combat(c, true)
    Reach(c, route.steps[1])
    T.eq(c.FG.Bridge.Route().active, 2, "the journey still moves on")
    Clean(c, "in a fight:")
    Combat(c, false)
    Clean(c, "after it:")
    local wp = c.waypoint
    T.ok(wp, "the waypoint catches up")
end

function tests.startingInAFight_waitsForItsEnd_andStillNavigates()
    local c = Start()
    MapSeen(c)
    Plan(c)
    Combat(c, true)
    c.FG.Planner.Start()
    c:Advance(1.5)
    T.ok(c.FG.Bridge.ActiveRoute(), "navigation does not wait")
    T.ok(c.FG.Journey.View(), "and the HUD has its view")
    T.eq(c.waypoint, nil, "the game's waypoint does")
    Combat(c, false)
    T.ok(c.waypoint, "placed once it ends")
    T.ok(c.superTrack.waypoint, "and the beacon lit")
    Clean(c)
end

function tests.underAnOpenMap_changesWaitForItToClose()
    local c = Start()
    c:PlayerToggleMap()
    Go(c)
    T.eq(c.waypoint, nil, "held")
    c:PlayerToggleMap()
    c:Advance(0.2)
    T.ok(c.waypoint, "placed on closing")
    Clean(c)
end

function tests.aFightAndAnOpenMap_bothHaveToEnd()
    local c = Start()
    c:PlayerToggleMap()
    Plan(c)
    Combat(c, true)
    c.FG.Planner.Start()
    c:Advance(1.5)
    c:PlayerToggleMap()
    c:Advance(0.2)
    T.eq(c.waypoint, nil, "the map closed in a fight: still held")
    Combat(c, false)
    T.ok(c.waypoint, "both over")
    Clean(c)
end

-- ==== what has to stay off the game's map ===================================

function tests.aPreview_neverTouchesTheGamesMap()
    local c = Start()
    Plan(c)
    local M = c.FG.MapPreview
    T.ok(M.Open(), "shown")
    T.no(c.env.WorldMapFrame:IsShown(), "on our own map, not the game's")
    T.ok(c.FG.RouteMap.Shown())
    M.Focus(3)
    M.Focus(3)
    M.NextLeg()
    M.NextLeg()
    M.Fit()
    M.ToPlayer()
    Clean(c)
end

function tests.aPreview_inAFight_isOurOwnFrame_soItOpens()
    local c = Start()
    Plan(c)
    Combat(c, true)
    T.ok(c.FG.MapPreview.Open(), "nothing protected is involved")
    T.ok(c.FG.RouteMap.Shown())
    Clean(c)
end

function tests.theRouteUnderWay_isShownOnOurOwnMapToo()
    local c = Start()
    Go(c)
    T.ok(c.FG.MapPreview.OpenActive(), "shown")
    T.no(c.env.WorldMapFrame:IsShown())
    T.ok(c.FG.RouteMap.Shown())
    Clean(c)
end

function tests.aMapThePlayerOpened_stillShowsThePreview_onWhateverTheyTurnedItTo()
    local c = Start()
    c:PlayerToggleMap()
    Plan(c)
    local drawn = c.FG.MapPreview._Lines().n
    T.ok(drawn > 0, "drawn over the player's own map")
    c:PlayerTurnsMap(1415)
    c.FG.MapPreview._Redraw()
    T.eq(c.env.WorldMapFrame:GetMapID(), 1415, "where they put it")
    T.eq(#c.taint.mapWrites, 0)
    c:PlayerToggleMap()
end

-- The stack with no setter of ours in it: an id we wrote, read by a clean refresh.
function tests.aQuestChangingInAFight_afterAPreview_findsNoTaintWaiting()
    local c = Start()
    MapSeen(c)
    Plan(c)
    c.FG.MapPreview.Open()
    c.FG.MapPreview.NextLeg()
    Combat(c, true)
    c:GameChangesSuperTrack(101)
    Clean(c)
end

-- ==== fewest changes ========================================================

function tests.aWholeJourney_makesFewChangesToTheGamesTracking()
    local c = Start()
    MapSeen(c)
    local route = Go(c)
    local tracked = 0
    for _, call in ipairs(c.taint.calls) do
        if call.what == "SetSuperTrackedUserWaypoint" then tracked = tracked + 1 end
    end
    T.eq(tracked, 1, "one to light the beacon")
    for i = 1, 2 do Reach(c, route.steps[i]) end
    tracked = 0
    for _, call in ipairs(c.taint.calls) do
        if call.what == "SetSuperTrackedUserWaypoint" then tracked = tracked + 1 end
    end
    T.ok(tracked <= 2, "steps move the waypoint, not the tracking: " .. tracked)
    Clean(c)
end

function tests.aChangeThatChangesNothing_isNotMade()
    local c = Start()
    Go(c)
    local before = #c.taint.refreshes
    local ns = c.FG.Bridge.NS()
    for _ = 1, 5 do ns.GPS.TrackGamePin(true) end
    T.eq(#c.taint.refreshes, before)
    T.eq(c.FG.Bridge.GameChanges().skipped > 0, true, "and it is counted")
end

function tests.withTheBeaconOff_noSuperTrackIsEverTouched()
    local c = Start()
    c.FG.db.map.beacon = false
    c.FG.Emit("settings:changed")
    MapSeen(c)
    local route = Go(c)
    Reach(c, route.steps[1])
    c.FG.Planner.Clear()
    c.FG.StopNavigation()
    c:Advance(1)
    T.eq(#c.taint.refreshes, 0, "no refresh in our name at all")
    T.no(c.superTrack.waypoint)
    Clean(c)
end

function tests.turningTheBeaconOffMidJourney_letsGoOfTheTracking_andNavigationGoesOn()
    local c = Start()
    Go(c)
    T.ok(c.superTrack.waypoint)
    c.FG.db.map.beacon = false
    c.FG.Emit("settings:changed")
    c:Advance(0.5)
    T.no(c.superTrack.waypoint, "let go")
    T.ok(c.FG.Bridge.ActiveRoute(), "the journey carries on")
    c.FG.db.map.beacon = true
    c.FG.Emit("settings:changed")
    c:Advance(0.5)
    T.ok(c.superTrack.waypoint, "taken up again")
end

function tests.thePlayersOwnWaypoint_isNotClearedByOneOfOursWaiting()
    local c = Start()
    Go(c)
    Combat(c, true)
    c.FG.StopNavigation()
    c:Advance(0.5)
    -- Their own, dropped by hand during the fight.
    c.waypoint = c.env.UiMapPoint.CreateFromCoordinates(1429, 0.2, 0.2)
    Combat(c, false)
    T.ok(c.waypoint, "theirs stays")
    T.near(c.waypoint.position.x, 0.2, 0.0001)
end

-- ==== the player's own tracking =============================================

function tests.aQuestThePlayerTracks_takesOver_andIsNotClearedByUs()
    local c = Start()
    Go(c)
    local calls = #c.taint.calls
    c:GameChangesSuperTrack(101)
    c:Advance(0.5)
    T.eq(c.superTrack.quest, 101, "theirs stands")
    for i = calls + 1, #c.taint.calls do
        T.ok(c.taint.calls[i].what ~= "SetSuperTrackedQuestID", "never cleared for them")
    end
    T.ok(c.FG.Bridge.ActiveRoute(), "the journey carries on")
    Clean(c)
end

function tests.nativePins_areNotWrittenTo()
    local c = Start()
    local src = c.FG.Bridge.NS().MapSearch
    T.eq(src.SyncGameWaypointPin(), nil, "the sync is gone")
    local fh = assert(io.open("build/assembled/ForeverGPS/Vendor/EasyFind/MapSearch/Pins.lua", "rb"))
    local text = fh:read("*a")
    fh:close()
    T.no(text:find("_easyfindOriginalScale", 1, true), "no field of ours on a game pin")
end

-- ==== the windows ===========================================================

function tests.escape_closesTheWindows_withoutTheGamesList()
    local c = Start({ ui = true })
    local FG = c.FG
    FG.Window.Show("search")
    c:Advance(0.2)
    T.eq(#c.env.UISpecialFrames, 0)
    T.ok(FG.Window.Frame():IsShown())
    local dispatch = c.env.EasyFindEscDispatch
    T.ok(dispatch, "the key's own button")
    dispatch._scripts.OnClick(dispatch)
    T.no(FG.Window.Frame():IsShown(), "closed by Escape")
end

-- ==== the whole lot, in one session =========================================

function tests.aSession_ofEverythingTheBriefNames()
    local c = Start({ ui = true })
    local FG = c.FG

    c:PlayerToggleMap() c:Advance(0.2)                               -- open
    c:PlayerTurnsMap(1415) c:Advance(0.2)                            -- a continent
    c:PlayerTurnsMap(1453) c:Advance(0.2)
    c:PlayerToggleMap() c:Advance(0.2)                               -- close
    local route = Go(c, AUBERDINE)                                   -- start
    Plan(c, GOLDSHIRE)                                               -- another way, previewed
    FG.MapPreview.Open()
    FG.RouteMap.Hide()
    FG.Planner.Clear()
    c:Fire("QUEST_ACCEPTED", 101)                                    -- accept
    c:GameChangesSuperTrack(101)
    c:Advance(0.5)
    c:Fire("QUEST_LOG_UPDATE")                                       -- an objective
    c:Advance(0.5)
    c:GameChangesSuperTrack(nil)                                     -- another quest
    c:Advance(0.5)
    c.env.ToggleQuestLog()                                           -- the quest log
    Combat(c, true)                                                  -- a fight
    Reach(c, route.steps[1])
    c:GameChangesSuperTrack(102)
    c:PlayerToggleMap() c:Advance(0.2)
    c:PlayerToggleMap() c:Advance(0.2)
    Combat(c, false)
    FG.StopNavigation()                                              -- stop
    c:Advance(0.5)
    Clean(c)
    T.eq(c.waypoint, nil, "nothing left behind")

    -- A reload, in the middle of a fight, with a journey under way.
    Go(c, AUBERDINE)
    local saved = Stack.Saved(c)
    local d = Start({ saved = saved, combat = true })
    d:MapSeenForReload()
    d:Advance(2)
    Clean(d, "after the reload:")
end

return tests
