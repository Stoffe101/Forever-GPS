-- A plain label for the known hazards on a route. It reads what the addon data
-- does know: creatures by level, enemy guards, enemy towns and enemy transport.
-- It cannot know about enemy players, and the words shown never suggest it can.
local _, FG = ...
local Risk = {}
FG.Risk = Risk

local Bridge = FG.Bridge
local L = FG.L

local TOWN_YARDS = 350       -- a walk this close to an enemy flight master passes its town
local SAMPLE_YARDS = 60      -- how often along a walk to look for one

local RANK = { low = 1, moderate = 2, high = 3 }

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
function Risk.Assess(route)
    local level, reasons, assessed = "low", {}, false
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
    for i = 1, #route.steps do
        local step = route.steps[i]
        if step.hostile then
            Add("high", L["RISK_REASON_ENEMY_RIDE"])
            assessed = true
        end
        if step.kind == "travel" and not step.corpse then
            local path, ci = Bridge.WalkOf(step, i, route)
            if path then
                assessed = true
                local d = Bridge.DeadlyAlong(path, ci)
                if d then
                    if d.guard then Add("high", L["RISK_REASON_GUARDS"]) end
                    if d.skull then Add("high", L["RISK_REASON_SKULL"])
                    elseif (d.n or 0) > 0 then Add("moderate", L["RISK_REASON_RED"]) end
                end
                TownsAlong(path, EnemyNodes(ci, faction), towns)
            end
        elseif step.kind ~= "travel" then
            assessed = true
        end
    end
    for name in pairs(towns) do Add("moderate", L["RISK_REASON_TOWN_FMT"]:format(name)) end
    table.sort(reasons)
    if not assessed then return { level = "unknown", reasons = {} } end
    return { level = level, reasons = reasons }
end

function Risk.Label(level)
    return L[({ low = "RISK_LOW", moderate = "RISK_MODERATE", high = "RISK_HIGH" })[level] or "RISK_UNKNOWN"]
end
