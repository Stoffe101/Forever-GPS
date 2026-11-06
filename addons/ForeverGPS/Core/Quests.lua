-- The quest log as Forever-GPS reads it: titles, levels, zone headers, objectives
-- and progress, straight from the client, so it works with or without Questie.
-- Read lazily and only after the log changed; QUEST_LOG_UPDATE fires constantly.
local FG = ForeverGPS
local Quests = {}
FG.Quests = Quests

local L = FG.L
local QL = C_QuestLog

local THROTTLE = 0.3

local snapshot, byID = {}, {}
local dirty = true
local waiting = false

-- Objectives as { index, text, finished, have, need }.
local function NativeObjectives(questID)
    local out = {}
    local list = QL.GetQuestObjectives and QL.GetQuestObjectives(questID)
    for i = 1, list and #list or 0 do
        local o = list[i]
        out[i] = { index = i, text = o.text or "", finished = o.finished == true,
                   have = o.numFulfilled, need = o.numRequired, type = o.type }
    end
    return out
end

local function IsComplete(questID)
    return QL.IsComplete ~= nil and QL.IsComplete(questID) == true
end

local function IsFailed(questID)
    return QL.IsFailed ~= nil and QL.IsFailed(questID) == true
end

local function Read()
    local out, index = {}, {}
    local header
    local count = QL.GetNumQuestLogEntries and QL.GetNumQuestLogEntries() or 0
    for i = 1, count do
        local info = QL.GetInfo(i)
        if info then
            if info.isHeader then
                header = info.title
            elseif not info.isHidden and info.questID and info.questID > 0 then
                local q = {
                    questID = info.questID, title = info.title or "?", level = info.level, zone = header,
                    complete = IsComplete(info.questID), failed = IsFailed(info.questID),
                    objectives = NativeObjectives(info.questID),
                }
                out[#out + 1] = q
                index[q.questID] = q
            end
        end
    end
    return out, index
end

local function Refresh()
    if not dirty then return end
    dirty = false
    snapshot, byID = Read()
end

function Quests.All()
    Refresh()
    return snapshot
end

function Quests.Get(questID)
    Refresh()
    return byID[questID]
end

-- How many objectives are still open.
function Quests.Left(q)
    local n = 0
    for i = 1, #q.objectives do
        if not q.objectives[i].finished then n = n + 1 end
    end
    return n
end

-- One line of status: its words, and "ready", "failed" or "open".
function Quests.Status(q)
    if q.failed then return L["QUEST_FAILED"], "failed" end
    if q.complete then return L["QUEST_READY"], "ready" end
    local left = Quests.Left(q)
    if #q.objectives == 0 then return L["QUEST_NO_OBJECTIVES"], "open" end
    if left == 1 then return L["QUEST_LEFT_ONE"], "open" end
    return L["QUEST_LEFT_FMT"]:format(left), "open"
end

-- 0 to 1 across the quest's objectives.
function Quests.Progress(q)
    if q.complete then return 1 end
    local sum, n = 0, #q.objectives
    if n == 0 then return 0 end
    for i = 1, n do
        local o = q.objectives[i]
        if o.finished then sum = sum + 1
        elseif o.need and o.need > 0 then sum = sum + math.min(1, (o.have or 0) / o.need) end
    end
    return sum / n
end

function Quests.Match(text)
    local out, low = {}, text:lower()
    for _, q in ipairs(Quests.All()) do
        if q.title:lower():find(low, 1, true) then out[#out + 1] = q end
    end
    return out
end

local function Changed()
    dirty = true
    if waiting then return end
    waiting = true
    FG.After(THROTTLE, function()
        waiting = false
        FG.Emit("quests:changed")
    end)
end

FG.OnEvent("QUEST_LOG_UPDATE", Changed)
FG.OnEvent("QUEST_ACCEPTED", Changed)
FG.OnEvent("QUEST_REMOVED", Changed)
FG.OnEvent("QUEST_TURNED_IN", Changed)
FG.OnEvent("UNIT_QUEST_LOG_CHANGED", function(unit)
    if unit == "player" then Changed() end
end)
