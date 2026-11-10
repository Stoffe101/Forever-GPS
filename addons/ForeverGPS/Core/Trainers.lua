-- Which trainer can teach what, as each trainer's own window has said. A title such as
-- "Alchemy Trainer" says nothing about the ranks taught, and no data here says it either:
-- when a trainer's window opens, what it offers is written down, for every character on
-- the account. Until then a trainer is "not visited", and ranked after one that is known
-- to teach the rank needed, never before. Search then orders by travel time within each.
local FG = ForeverGPS
local Trainers = {}
FG.Trainers = Trainers

local L = FG.L

local function DB()
    FG.db.trainers = FG.db.trainers or {}
    return FG.db.trainers
end

local function NpcID(guid)
    local kind, _, _, _, _, id = strsplit("-", guid or "")
    if kind ~= "Creature" then return nil end
    return tonumber(id)
end

-- Rank words as the game writes them in a trainer's window, matched to a cap.
local RANK_CAP = { Apprentice = 75, Journeyman = 150, Expert = 225, Artisan = 300 }

-- Everything a trainer's window offers. Called on TRAINER_SHOW.
function Trainers.Learn()
    local id = NpcID(UnitGUID and UnitGUID("npc"))
    if not (id and GetNumTrainerServices and GetTrainerServiceInfo) then return nil end
    local entry = { name = UnitName("npc"), at = time(), ranks = {}, services = 0 }
    for i = 1, GetNumTrainerServices() do
        local name, rank, category = GetTrainerServiceInfo(i)
        if category ~= "header" and name then
            entry.services = entry.services + 1
            local cap = rank and RANK_CAP[rank] or RANK_CAP[(name:match("^(%a+)") or "")]
            if cap then
                local skill, skillRank = nil, nil
                if GetTrainerServiceSkillReq then skill, skillRank = GetTrainerServiceSkillReq(i) end
                local level = GetTrainerServiceLevelReq and GetTrainerServiceLevelReq(i) or nil
                local cost = GetTrainerServiceCost and GetTrainerServiceCost(i) or nil
                entry.ranks[#entry.ranks + 1] = { cap = cap, name = name, skill = skillRank, skillName = skill, level = level,
                                                  cost = cost, available = category == "available" }
                entry.profession = entry.profession or skill
            end
        end
    end
    DB()[id] = entry
    FG.Emit("trainers:changed", id)
    return entry
end
FG.OnEvent("TRAINER_SHOW", function() FG.After(0.2, Trainers.Learn) end)

function Trainers.Known(npcID) return DB()[npcID] end

-- Whether a trainer teaches the rank with this cap: true, false, or nil (not visited, or it
-- teaches another profession). Its requirements, when the window gave them.
function Trainers.Teaches(npcID, cap)
    local entry = DB()[npcID]
    if not entry then return nil end
    for _, r in ipairs(entry.ranks) do
        if r.cap == cap then return true, r end
    end
    return false
end

-- A trainer for a profession's next rank: "teaches" (with its rank record), "no", or
-- "unknown". With no next rank, nil.
function Trainers.ForNext(npcID, profession)
    local next = FG.Professions.NextRank(profession)
    if not next then return nil end
    local yes, rank = Trainers.Teaches(npcID, next.cap)
    if yes then return "teaches", rank end
    if yes == false then return "no" end
    return "unknown"
end

-- The order a search shows trainers in: teaches the next rank, not visited, cannot.
Trainers.ORDER = { teaches = 1, unknown = 2, no = 3 }

-- A line for a trainer's row: what it is known to teach.
function Trainers.Badge(npcID, profession)
    local state, rank = Trainers.ForNext(npcID, profession)
    if state == "teaches" then
        local parts = { L["TRAINER_TEACHES_FMT"]:format(rank.name) }
        if rank.cost and rank.cost > 0 then parts[#parts + 1] = FG.Fares.Money(rank.cost) end
        return table.concat(parts, " \194\183 "), "good"
    end
    if state == "no" then return L["TRAINER_CANNOT"], "textFaint" end
    if state == "unknown" then return L["TRAINER_UNVISITED"], "textDim" end
    return nil
end

-- The profession a search is about, when it asks for a trainer of one the character has.
function Trainers.ProfessionOf(text)
    text = (text or ""):lower()
    if not text:find("trainer", 1, true) then return nil end
    for _, p in ipairs(FG.Professions.List()) do
        if text:find(p.name:lower(), 1, true) then return p end
    end
    return nil
end
