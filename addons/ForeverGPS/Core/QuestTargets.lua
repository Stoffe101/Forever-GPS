-- Where a quest's parts are done, and which spot to go to. Spawns are grouped
-- into areas, the nearest few are priced by the route engine, and the closest by
-- travel time leads: not the closest on a straight line across a sea. A quest
-- with no reliable place says so instead of inventing a route.
--
-- FG.Areas works on any list of spots, NPC spawns as well as quest objectives.
local FG = ForeverGPS
local Areas = {}
FG.Areas = Areas
local Targets = {}
FG.QuestTargets = Targets

local Bridge, Eta, Quests = FG.Bridge, FG.Eta, FG.Quests
local L = FG.L

local CELL = 220             -- yards: spawns within about this form one area
local PRICED_NEAR = 5        -- the nearest areas priced on the player's continent
local PRICED_FAR = 3         -- and on others

-- ==== areas =================================================================

-- spots: { { mapID, x, y, name? }, ... }. Returns areas, each with its spots'
-- count, its zone, and a real spot near its middle to route to. apart: each spot
-- stands alone, for places where any one will do.
function Areas.From(spots, apart)
    local cells, out = {}, {}
    for i = 1, #spots do
        local s = spots[i]
        local ci, wx, wy = Bridge.WorldPos(s.mapID, s.x, s.y)
        if ci then
            local key = apart and i or ("%d:%d:%d"):format(ci, math.floor(wx / CELL), math.floor(wy / CELL))
            local area = cells[key]
            if not area then
                area = { ci = ci, sx = 0, sy = 0, n = 0, members = {}, zone = Bridge.MapName(s.mapID) }
                cells[key] = area
                out[#out + 1] = area
            end
            area.sx, area.sy, area.n = area.sx + wx, area.sy + wy, area.n + 1
            area.members[area.n] = { spot = s, wx = wx, wy = wy }
        end
    end
    for i = 1, #out do
        local a = out[i]
        a.wx, a.wy = a.sx / a.n, a.sy / a.n
        local best, bestD
        for j = 1, a.n do
            local m = a.members[j]
            local d = (m.wx - a.wx) ^ 2 + (m.wy - a.wy) ^ 2
            if not bestD or d < bestD then best, bestD = m.spot, d end
        end
        a.spot, a.members, a.sx, a.sy = best, nil, nil, nil
    end
    return out
end

-- Straight-line order from the player: this continent first.
local function ByDistance(areas, start)
    for i = 1, #areas do
        local a = areas[i]
        if start and a.ci == start.ci then
            a.yards = ((a.wx - start.wx) ^ 2 + (a.wy - start.wy) ^ 2) ^ 0.5
        else
            a.yards = nil
        end
    end
    table.sort(areas, function(p, q)
        if p.yards and q.yards then return p.yards < q.yards end
        if p.yards or q.yards then return p.yards ~= nil end
        return p.n > q.n
    end)
    return areas
end

-- The areas worth pricing: the nearest here and a few elsewhere.
local function Shortlist(areas)
    local out, near, far = {}, 0, 0
    for i = 1, #areas do
        local a = areas[i]
        if a.routable ~= false then
            if a.yards and near < PRICED_NEAR then
                near = near + 1
                out[#out + 1] = a
            elseif not a.yards and far < PRICED_FAR then
                far = far + 1
                out[#out + 1] = a
            end
        end
    end
    return out
end

local function Routable(area)
    local s = area.spot
    return Bridge.CanNavigate({ name = s.name or "?", mapID = s.mapID, x = s.x, y = s.y })
end

-- Orders areas by travel time as estimates arrive; done(best, basis) once they
-- are in. basis: "travel" when the engine priced it, "straight" otherwise.
function Areas.Rank(areas, done, alive)
    local start = Bridge.PlayerStart()
    ByDistance(areas, start)
    for i = 1, #areas do
        if areas[i].routable == nil then areas[i].routable = Routable(areas[i]) end
    end
    local list = Shortlist(areas)
    local waiting = #list
    if waiting == 0 then
        for i = 1, #areas do
            if areas[i].routable then return done(areas[i], "straight") end
        end
        return done(nil, nil)
    end
    local function Settle()
        local best, basis
        for i = 1, #list do
            local a = list[i]
            if a.sec and (not best or a.sec < best.sec) then best, basis = a, "travel" end
        end
        if not best then best, basis = list[1], "straight" end
        table.sort(areas, function(p, q)
            if p.sec and q.sec then return p.sec < q.sec end
            if p.sec or q.sec then return p.sec ~= nil end
            return false
        end)
        done(best, basis)
    end
    for i = 1, #list do
        local a = list[i]
        local s = a.spot
        Eta.Request({ mapID = s.mapID, x = s.x, y = s.y, name = s.name or "?" }, function(value)
            a.sec = value and value.sec or nil
            a.transports = value and value.transports or nil
            waiting = waiting - 1
            if waiting == 0 then Settle() end
        end, alive)
    end
end

-- ==== quest spots ===========================================================

local function Questie()
    local API = EasyFind and EasyFind.API
    if not (API and API.HasAction and API.HasAction("questie", "questSpots")) then return nil end
    return API
end

function Targets.HasQuestie()
    local API = Questie()
    return API ~= nil and API.CallAction("questie", "isReady") == true
end

-- Spot lists are facts about the game: kept for the session, per quest.
local spotCache = {}
local hadQuestie = false

-- Whether Questie came or went since this was last asked: what the quest list
-- worked out before then no longer holds.
function Targets.QuestieChanged()
    local has = Targets.HasQuestie()
    local changed = has ~= hadQuestie
    hadQuestie = has
    if changed then spotCache = {} end
    return changed
end

local function SpotsOf(questID)
    local hit = spotCache[questID]
    if hit then return hit end
    if not Targets.HasQuestie() then return nil end
    local data = EasyFind.API.CallAction("questie", "questSpots", questID)
    if type(data) ~= "table" then return nil end
    spotCache[questID] = data
    return data
end

local function NewTarget(kind, index, text, spots, done)
    local t = { kind = kind, index = index, text = text, done = done or false, areas = {} }
    if spots and #spots > 0 then
        t.areas = Areas.From(spots)
        t.spotCount = #spots
    end
    if #t.areas == 0 then
        t.status = "none"
        t.reason = L["QUEST_NO_DATA_LONG"]
    else
        t.status = "ok"
    end
    return t
end

-- Everything a quest can be navigated to right now.
-- { objectives = { target, ... }, turnIn = target or nil, marker = target or nil,
--   source = "questie" or "game" }
function Targets.For(q)
    local out = { objectives = {} }
    local data = SpotsOf(q.questID)
    out.source = data and "questie" or "game"
    for i = 1, #q.objectives do
        local o = q.objectives[i]
        local spots = data and data.objectives[i] and data.objectives[i].spots or nil
        local t = NewTarget("objective", i, o.text, spots, o.finished)
        if not data then t.reason = L["QUEST_NO_QUESTIE"] end
        out.objectives[i] = t
    end
    if data then
        local name = data.turnInName
        out.turnIn = NewTarget("turnin", nil, name and L["QUEST_TURN_IN_AT_FMT"]:format(name) or L["QUEST_TURN_IN"], data.turnIn)
    end
    -- The game's own mark: all there is without Questie, and a place for an
    -- objective Questie has none for.
    local mapID, x, y = Bridge.QuestSpot(q.questID)
    if mapID then
        local label = q.complete and L["QUEST_TURN_IN"] or L["QUEST_GAME_MARKER"]
        out.marker = NewTarget("marker", nil, label, { { mapID = mapID, x = x, y = y } })
        if q.complete and not out.turnIn then out.turnIn = out.marker end
    end
    if not out.turnIn then
        out.turnIn = NewTarget("turnin", nil, L["QUEST_TURN_IN"], nil)
    end
    return out
end

-- Checks a target's areas, priced and ordered; done(target) when it is settled.
function Targets.Resolve(target, done, alive)
    if target.status ~= "ok" then return done(target) end
    if target.settled then return done(target) end
    Areas.Rank(target.areas, function(best, basis)
        target.settled = true
        target.best, target.basis = best, basis
        if not best then
            target.status = "instance"
            target.reason = L["QUEST_INSTANCE_ONLY"]
        end
        done(target)
    end, alive)
end

-- The planner's target for going to an area of a quest's target.
function Targets.Destination(q, target, area)
    local s = area.spot
    local icon = target.kind == "turnin" and 132048 or 365195
    return {
        name = L["QUEST_DEST_FMT"]:format(q.title, target.text or ""),
        subtitle = area.zone,
        icon = icon,
        data = { name = q.title, mapID = s.mapID, x = s.x, y = s.y, icon = icon,
                 step = target.kind == "turnin" and target.text or nil },
        binding = { questID = q.questID, title = q.title, kind = target.kind, index = target.index },
        areas = target.areas, area = area,
    }
end

-- What the quest browser sorts and filters on: how near the closest thing left to
-- do is, on a straight line, and whether anything left has no known place. Cheap
-- enough to ask whenever the list is drawn: it reads areas that already exist.
-- { yards (nil when elsewhere), here, sameLand, missing }
function Targets.Facts(q, targets, start, mapID)
    local facts = { missing = false, here = false, sameLand = false }
    local function Look(target)
        if not target or target.done then return end
        if target.status ~= "ok" then
            if target.kind == "objective" then facts.missing = true end
            return
        end
        for _, area in ipairs(target.areas) do
            if area.spot.mapID == mapID then facts.here = true end
            if start and area.ci == start.ci then
                facts.sameLand = true
                local d = ((area.wx - start.wx) ^ 2 + (area.wy - start.wy) ^ 2) ^ 0.5
                if not facts.yards or d < facts.yards then facts.yards = d end
            end
        end
    end
    if q.complete then
        Look(targets.turnIn)
    else
        for i = 1, #targets.objectives do Look(targets.objectives[i]) end
        Look(targets.turnIn)
    end
    return facts
end

-- The first thing to do for a quest: the turn-in when it is done, else the
-- open objective reachable soonest once resolved. Used by the quest list's
-- one-click directions.
function Targets.FirstOpen(q, targets)
    if q.complete then return targets.turnIn end
    for i = 1, #targets.objectives do
        local t = targets.objectives[i]
        if not t.done and t.status == "ok" then return t end
    end
    return targets.marker
end

FG.On("quests:changed", function()
    -- Spots do not change, but a quest that left the log need not stay.
    for questID in pairs(spotCache) do
        if not Quests.Get(questID) then spotCache[questID] = nil end
    end
end)
