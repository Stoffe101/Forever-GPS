-- A plain label for the known hazards on a route. It reads what the addon data
-- does know: creatures by level, enemy guards, enemy towns and enemy transport.
-- It cannot know about enemy players, and the words shown never suggest it can.
local FG = ForeverGPS
local Risk = {}
FG.Risk = Risk

local Bridge = FG.Bridge
local L = FG.L

local TOWN_YARDS = 350       -- a walk this close to an enemy flight master passes its town
local SAMPLE_YARDS = 60      -- how often along a walk to look for one

local RANK = { low = 1, contested = 2, moderate = 3, high = 4 }

local ENEMY_TOWN_YARDS = 450 -- this close to a flight master, a spot is that town's

-- Who holds a zone, by the game's own home territories. Anything else is contested.
local HOME = {
    Alliance = { [1429] = true, [1426] = true, [1436] = true, [1432] = true, [1438] = true, [1439] = true,
                 [1453] = true, [1455] = true, [1457] = true },
    Horde = { [1411] = true, [1412] = true, [1413] = true, [1420] = true, [1421] = true,
              [1454] = true, [1456] = true, [1458] = true },
}

local function Enemy(faction) return faction == "Horde" and "Alliance" or "Horde" end

-- "home", "enemy" or "contested", for a zone and the player's faction.
function Risk.ZoneControl(mapID, faction)
    faction = faction or UnitFactionGroup("player")
    if HOME[faction] and HOME[faction][mapID] then return "home" end
    if HOME[Enemy(faction)] and HOME[Enemy(faction)][mapID] then return "enemy" end
    return "contested"
end

-- Whether a world spot stands in an enemy town: the nearest flight master within
-- reach belongs to the other side, or, with none near, the zone is the enemy's own.
-- mapID may be left out where only the town matters.
function Risk.EnemyGround(ci, wx, wy, mapID)
    local faction = UnitFactionGroup("player")
    local best, bestD
    for _, node in pairs(Bridge.FlightNodes()) do
        if node.ci == ci and node.wx then
            local d = (node.wx - wx) ^ 2 + (node.wy - wy) ^ 2
            if d <= ENEMY_TOWN_YARDS * ENEMY_TOWN_YARDS and (not bestD or d < bestD) then best, bestD = node, d end
        end
    end
    if best then return best.faction ~= nil and best.faction ~= faction end
    return mapID ~= nil and Risk.ZoneControl(mapID, faction) == "enemy"
end

local function Worse(a, b)
    return (RANK[b] or 0) > (RANK[a] or 0) and b or a
end

-- The enemy towns on a continent, by their flight masters.
local function EnemyNodes(ci, faction)
    local out = {}
    for _, node in pairs(Bridge.FlightNodes()) do
        if node.ci == ci and node.faction and node.faction ~= faction and node.wx then
            out[#out + 1] = node
        end
    end
    return out
end

local function TownName(node) return (node.n or "?"):match("^[^,]+") end

-- Enemy towns a drawn walk passes, added to names once each.
local function TownsAlong(path, nodes, names)
    local pts, stride = path.pts, 0
    for i = 1, #pts - 1, 2 do
        stride = stride - 1
        if stride <= 0 then
            stride = math.max(1, math.floor(SAMPLE_YARDS / 10))
            local x, y = pts[i], pts[i + 1]
            for j = 1, #nodes do
                local n = nodes[j]
                if (x - n.wx) ^ 2 + (y - n.wy) ^ 2 <= TOWN_YARDS * TOWN_YARDS then names[TownName(n)] = true end
            end
        end
    end
end

-- { level = "low"|"moderate"|"high"|"unknown", reasons = { text, ... } }
-- route: anything Bridge.WalkOf can read a walk's ends from ({ steps, from }).
-- walks: its walks by step, when the caller holds them.
function Risk.Assess(route, walks)
    local level, reasons, assessed, deadly = "low", {}, false, false
    local seen = {}
    local function Add(rank, text)
        level = Worse(level, rank)
        if not seen[text] then
            seen[text] = true
            reasons[#reasons + 1] = text
        end
    end
    local faction = UnitFactionGroup("player")
    local towns = {}
    local contested, approach = {}, false
    local lastWalk
    for i = #route.steps, 1, -1 do
        if route.steps[i].kind == "travel" then
            lastWalk = i
            break
        end
    end
    for i = 1, #route.steps do
        local step = route.steps[i]
        if step.hostile then
            Add("high", L["RISK_REASON_ENEMY_RIDE"])
            assessed = true
        end
        if step.kind == "travel" and not step.corpse then
            local path, ci
            if walks then path = walks[i] end
            if path then
                ci = route.from and route.from.ci
                if i > 1 and route.steps[i - 1].arrive then ci = route.steps[i - 1].arrive.ci or ci end
            else
                path, ci = Bridge.WalkOf(step, i, route)
            end
            if path then
                assessed = true
                local d = Bridge.DeadlyAlong(path, ci)
                if d and (d.guard or d.skull or (d.n or 0) > 0) then deadly = true end
                if d then
                    if d.guard then Add("high", L["RISK_REASON_GUARDS"]) end
                    if d.skull then Add("high", L["RISK_REASON_SKULL"])
                    elseif (d.n or 0) > 0 then Add("moderate", L["RISK_REASON_RED"]) end
                    if i == lastWalk and (d.guard or d.skull) then approach = true end
                end
                TownsAlong(path, EnemyNodes(ci, faction), towns)
            end
            -- Worth a word, not a warning: walks only take drops a fall survives.
            if Bridge.DropNote(step) then Add("low", L["RISK_REASON_DROP"]) end
            local zone = step.mapID and Risk.ZoneControl(step.mapID, faction)
            if zone == "contested" then contested[Bridge.MapName(step.mapID) or "?"] = true end
        elseif step.kind ~= "travel" then
            assessed = true
        end
    end
    for name in pairs(towns) do Add("moderate", L["RISK_REASON_TOWN_FMT"]:format(name)) end
    for name in pairs(contested) do Add("contested", L["RISK_REASON_CONTESTED_FMT"]:format(name)) end
    table.sort(reasons)
    if not assessed then return { level = "unknown", reasons = {} } end
    return { level = level, reasons = reasons, approach = approach, deadly = deadly, assessed = true }
end

local LABELS = { low = "RISK_LOW", contested = "RISK_CONTESTED", moderate = "RISK_MODERATE", high = "RISK_HIGH" }

function Risk.Label(level, risk)
    if level == "high" and risk and risk.approach then return L["RISK_HIGH_APPROACH"] end
    return L[LABELS[level] or "RISK_UNKNOWN"]
end
