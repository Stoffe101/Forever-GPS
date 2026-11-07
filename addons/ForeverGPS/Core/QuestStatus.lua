-- Where this character stands with a quest. Questie's IsDoable decides, so there is one
-- eligibility engine and not two. This only sorts its answer into words a player can use,
-- and never treats a missing fact as proof of anything: a quest Questie cannot speak for
-- is "unknown", and one with no known starter is only "likely".
local FG = ForeverGPS
local Status = {}
FG.QuestStatus = Status

local QuestDB = FG.QuestDB
local L = FG.L

-- key -> { word, icon, color, rank: lower lists first }
local KINDS = {
    turnin = { "QS_TURNIN", "turnin", "good", 1 },
    active = { "QS_ACTIVE", "quest", "route", 2 },
    available = { "QS_AVAILABLE", "quest", "good", 3 },
    likely = { "QS_LIKELY", "quest", "warn", 4 },
    level = { "QS_LEVEL_FMT", "clock", "textDim", 5 },
    locked = { "QS_LOCKED", "lock", "textDim", 6 },
    gated = { "QS_GATED", "lock", "textDim", 7 },
    no = { "QS_NO", "close", "textFaint", 8 },
    done = { "QS_DONE", "check", "textFaint", 9 },
    unknown = { "QS_UNKNOWN", "warning", "textFaint", 10 },
}

local epoch = 1
local memo = {}

-- What moves a status: not a kill, only what these say.
local function Changed()
    epoch = epoch + 1
    memo = {}
    FG.Emit("queststatus:changed")
end

function Status.Epoch() return epoch end
Status.Forget = Changed

-- The game's completed list catches up a moment after a turn-in, so that is read twice.
local function ChangedSoon()
    Changed()
    FG.After(1, Changed)
end

FG.OnEvent("QUEST_ACCEPTED", Changed)
FG.OnEvent("QUEST_REMOVED", ChangedSoon)
FG.OnEvent("QUEST_TURNED_IN", ChangedSoon)
FG.OnEvent("PLAYER_LEVEL_UP", Changed)
FG.OnEvent("SKILL_LINES_CHANGED", Changed)
FG.OnEvent("PLAYER_ENTERING_WORLD", Changed)
FG.On("quests:changed", function()
    -- A quest finishing changes "in progress" to "ready", which nothing else announces.
    local changed = false
    for id, s in pairs(memo) do
        if (s.key == "active" or s.key == "turnin")
            and (s.key == "turnin") ~= (C_QuestLog.IsComplete(id) == true) then
            memo[id], changed = nil, true
        end
    end
    if changed then FG.Emit("queststatus:changed") end
end)
FG.OnEvent("UPDATE_FACTION", function()
    -- Reputation moves at every kill for some, and only a handful of quests ask for it.
    for id, s in pairs(memo) do
        if s.rep then memo[id] = nil end
    end
end)

local function Make(key, extra)
    local kind = KINDS[key]
    local s = extra or {}
    s.key, s.icon, s.color, s.rank = key, kind[2], kind[3], kind[4]
    s.word = s.word or L[kind[1]]
    return s
end

local UNKNOWN

-- Questie's reasons, sorted. A state missing here is one this has never met, and says
-- "not available" with Questie's own words, rather than guessing.
local function KindOfState(name)
    if name == "AVAILABLE" or name == "PARENT_ACTIVE" then return "available" end
    if name == "COMPLETED" then return "done" end
    if name == "QUEST_LOG" then return "active" end
    if name == "LEVEL_TOO_LOW" then return "level" end
    if name == "NO_PREQUESTSINGLE" or name == "NO_PREQUESTGROUP" or name == "PARENT_INACTIVE"
        or name == "ENABLING_QUEST_MISSING" then
        return "locked"
    end
    if name == "MISSING_REPUTATION" or name == "PROFESSION_SKILL" or name == "PROFESSION_MISSING" or name == "PROFESSION_RANK"
        or name == "PROFESSION_SPECIALIZATION" or name == "SPELL_MISSING" or name == "MISSING_ACHIEVEMENT" then
        return "gated"
    end
    return "no"
end

local stateNames
local function StateName(state)
    if not stateNames then
        stateNames = {}
        for name, value in pairs(QuestDB.States()) do stateNames[value] = name end
    end
    return stateNames[state]
end

local function HasStarter(id)
    local who = QuestDB.Starters(id)
    return #who.npcs > 0 or #who.objects > 0 or #who.items > 0
end

local function Work(id, level)
    if not QuestDB.Exists(id) then return UNKNOWN end
    if QuestDB.InLog(id) then
        return Make(C_QuestLog.IsComplete(id) == true and "turnin" or "active")
    end
    if QuestDB.IsDone(id) then return Make("done") end
    local need = QuestDB.Field(id, "requiredLevel")
    local rep = (QuestDB.Field(id, "requiredMinRep") or QuestDB.Field(id, "requiredMaxRep")) and true or nil
    if QuestDB.Doable(id) then
        if need and need > level then
            return Make("level", { need = need, word = L["QS_LEVEL_FMT"]:format(need), rep = rep })
        end
        if not HasStarter(id) then return Make("likely", { rep = rep, why = L["QS_LIKELY_WHY"] }) end
        return Make("available", { rep = rep })
    end
    local state, text = QuestDB.Verdict(id)
    if not state then return Make("no", { rep = rep, why = L["QS_NO_REASON"] }) end
    local name = StateName(state)
    local key = KindOfState(name)
    if key == "available" then
        -- Hidden in Questie by hand: its verdict says yes and its list leaves it out.
        return Make("no", { rep = rep, why = L["QS_HIDDEN"] })
    end
    if key == "level" then return Make("level", { need = need, word = L["QS_LEVEL_FMT"]:format(need or 0), rep = rep }) end
    return Make(key, { rep = rep, state = name, why = text })
end

-- A quest's status: { key, word, icon, color, rank, need?, why? }.
function Status.Of(id)
    if not QuestDB.Ready() then
        UNKNOWN = UNKNOWN or Make("unknown", { why = L["QUEST_NO_QUESTIE"] })
        return UNKNOWN
    end
    UNKNOWN = UNKNOWN or Make("unknown", { why = L["QS_UNKNOWN_WHY"] })
    local hit = memo[id]
    if hit then return hit end
    local s = Work(id, UnitLevel("player"))
    memo[id] = s
    return s
end

function Status.Open(s) return s.key == "available" or s.key == "likely" end
function Status.Finished(s) return s.key == "done" end
function Status.Taken(s) return s.key == "active" or s.key == "turnin" end
