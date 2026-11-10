-- Which trainer can teach what, as each trainer's own window has said. A title such as
-- "Alchemy Trainer" says nothing about the ranks taught, and no data here says it either:
-- when a trainer's window opens, what it offers is written down, for every character on
-- the account. Until then a trainer is "not visited", and ranked after one that is known
-- to teach the rank needed, never before. Search then orders by travel time within each.
--
-- What is kept is keyed by numbers, never by words: the trainer's NPC ID, the profession's
-- skill line ID (171 is Alchemy) and the rank's cap (225 is Expert). Words are only read
-- from the same client, in the same language, to find those numbers.
--
-- The window comes in two shapes, and both are read:
--   current  GetTrainerServiceInfo -> name, type, icon, level. The next rank is its own
--            service, GetTrainerServiceStepIndex(); GetTrainerTradeskillRankValues() is
--            the player's skill and cap in this profession.
--   classic  GetTrainerServiceInfo -> name, rank, type. Every rank is listed.
-- A rank's cap comes from the player's cap (the next one up), or from the skill it needs
-- (Journeyman 50, Expert 125, Artisan 200), and only last from its rank word.
local FG = ForeverGPS
local Trainers = {}
FG.Trainers = Trainers

local L = FG.L

local TYPES = { available = true, unavailable = true, used = true, header = true }
local NEXT_CAP = { [0] = 75, [75] = 150, [150] = 225, [225] = 300 }
local ENGLISH = { [164] = "Blacksmithing", [165] = "Leatherworking", [171] = "Alchemy", [182] = "Herbalism",
                  [185] = "Cooking", [186] = "Mining", [197] = "Tailoring", [202] = "Engineering", [333] = "Enchanting",
                  [356] = "Fishing", [393] = "Skinning", [129] = "First Aid" }
local WORD_CAP = { apprentice = 75, journeyman = 150, expert = 225, artisan = 300 }
Trainers.LINES = ENGLISH

local function DB()
    FG.db.trainers = FG.db.trainers or {}
    return FG.db.trainers
end

local function NpcID(guid)
    local kind, _, _, _, _, id = strsplit("-", guid or "")
    if kind ~= "Creature" then return nil end
    return tonumber(id)
end

-- The cap a rank brings, from the skill it needs.
local function CapOfSkill(rank)
    if type(rank) ~= "number" then return nil end
    if rank >= 200 then return 300 end
    if rank >= 125 then return 225 end
    if rank >= 50 then return 150 end
    return 75
end

-- A rank word, in this client's language or English, to a cap.
function Trainers.CapOfWord(word)
    word = (word or ""):lower()
    if word == "" then return nil end
    for cap, key in pairs({ [75] = "RANK_APPRENTICE", [150] = "RANK_JOURNEYMAN", [225] = "RANK_EXPERT", [300] = "RANK_ARTISAN" }) do
        if L[key] and L[key]:lower() == word then return cap end
    end
    return WORD_CAP[word]
end

-- The skill line of a profession by its name in this client: the character's own
-- professions (GetProfessionInfo, in the client's language), then English. Another
-- character's professions count too, once seen. In another language a profession no
-- character on the account has is not recognised, and its trainer's ranks not kept.
function Trainers.LineOf(name)
    if type(name) ~= "string" or name == "" then return nil end
    local want = name:lower()
    for _, p in ipairs(FG.Professions.List()) do
        if p.name and p.name:lower() == want then return p.line end
    end
    local seen = FG.db.professionNames or {}
    for line, shown in pairs(seen) do
        if shown:lower() == want then return line end
    end
    for line, english in pairs(ENGLISH) do
        if english:lower() == want then return line end
    end
    return nil
end

-- A profession's name to show: this client's, or English.
function Trainers.NameOf(line)
    local p = FG.Professions.Get(line)
    if p then return p.name end
    return (FG.db.professionNames or {})[line] or ENGLISH[line]
end

-- Every profession name this client has shown, for every character on the account.
FG.On("professions:changed", function()
    FG.db.professionNames = FG.db.professionNames or {}
    for _, p in ipairs(FG.Professions.List()) do
        if p.line and p.name then FG.db.professionNames[p.line] = p.name end
    end
end)

-- The service's name and type, whichever shape the window has. rank: the classic rank
-- text. shape: "current" or "classic".
local function Service(i)
    local name, second, third = GetTrainerServiceInfo(i)
    if TYPES[second] then return name, second, nil, "current" end
    return name, third, second, "classic"
end

-- The profession a service belongs to.
local function ServiceLine(i, fallback)
    local named = GetTrainerServiceSkillLine and GetTrainerServiceSkillLine(i)
    local line = Trainers.LineOf(named)
    if line then return line end
    local skill = GetTrainerServiceSkillReq and GetTrainerServiceSkillReq(i)
    return Trainers.LineOf(skill) or fallback
end

local function Requirements(i)
    local _, skillRank = nil, nil
    if GetTrainerServiceSkillReq then _, skillRank = GetTrainerServiceSkillReq(i) end
    local level = GetTrainerServiceLevelReq and GetTrainerServiceLevelReq(i) or nil
    if not level then level = select(4, GetTrainerServiceInfo(i)) end
    local cost = GetTrainerServiceCost and GetTrainerServiceCost(i) or nil
    return skillRank, type(level) == "number" and level or nil, cost
end

local function LineRecord(entry, line)
    entry.lines[line] = entry.lines[line] or { ranks = {}, none = {} }
    return entry.lines[line]
end

-- Everything a trainer's window offers. Called on TRAINER_SHOW.
function Trainers.Learn()
    local id = NpcID(UnitGUID and UnitGUID("npc"))
    if not (id and GetNumTrainerServices and GetTrainerServiceInfo) then return nil end
    local who = (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
    local entry = { name = UnitName("npc"), at = time(), by = who, lines = {}, services = 0, recipes = 0 }
    local count = GetNumTrainerServices()
    local step = GetTrainerServiceStepIndex and GetTrainerServiceStepIndex() or nil
    local shape
    local _, rankMax = nil, nil
    if GetTrainerTradeskillRankValues then _, rankMax = GetTrainerTradeskillRankValues() end
    local main
    for i = 1, count do
        local name, kind, rankText, seenShape = Service(i)
        shape = shape or seenShape
        if kind ~= "header" and name then
            entry.services = entry.services + 1
            local line = ServiceLine(i, main)
            main = main or line
            local skillRank, level, cost = Requirements(i)
            local cap
            if step == i then
                cap = (rankMax and NEXT_CAP[rankMax]) or CapOfSkill(skillRank)
            elseif seenShape == "classic" and line then
                -- Classic: a rank is a service named for the profession, with a rank word.
                local word = rankText or name:match("^(%S+)")
                local pname = Trainers.NameOf(line)
                local namedRank = Trainers.CapOfWord(word)
                    and (name:lower():find((pname or "\0"):lower(), 1, true) or rankText ~= nil)
                if namedRank then cap = CapOfSkill(skillRank) or Trainers.CapOfWord(word) end
            end
            if cap and line then
                LineRecord(entry, line).ranks[cap] = { cap = cap, name = name, skill = skillRank, level = level,
                                                       cost = cost, state = kind, how = step == i and "step" or "list" }
            elseif line then
                entry.recipes = entry.recipes + 1
                LineRecord(entry, line)
            end
        end
    end
    -- The current window shows only the next rank. None shown: this trainer does not
    -- teach the rank after the player's cap, as of this visit.
    if shape == "current" and not step and main and rankMax and NEXT_CAP[rankMax] then
        LineRecord(entry, main).none[NEXT_CAP[rankMax]] = true
    end
    -- The classic window lists every rank it teaches: one missing is not taught.
    if shape == "classic" and main then LineRecord(entry, main).full = true end
    -- What earlier visits learned stays, unless this one says otherwise.
    local old = DB()[id]
    if old and old.lines then
        for line, rec in pairs(old.lines) do
            local now = LineRecord(entry, line)
            for cap, r in pairs(rec.ranks or {}) do
                if not now.ranks[cap] and not now.none[cap] then now.ranks[cap] = r end
            end
            for cap in pairs(rec.none or {}) do
                if not now.ranks[cap] then now.none[cap] = true end
            end
        end
    end
    DB()[id] = entry
    FG.Emit("trainers:changed", id)
    return entry
end
FG.OnEvent("TRAINER_SHOW", function() FG.After(0.2, Trainers.Learn) end)

-- A record from 2.3 (ranks without a profession) is dropped on first read: it could not
-- tell Expert Alchemy from Expert Tailoring. The trainer reads as not visited again.
function Trainers.Known(npcID)
    local entry = DB()[npcID]
    if entry and not entry.lines then
        DB()[npcID] = nil
        return nil
    end
    return entry
end

-- Whether a trainer teaches this profession's rank with this cap: true (and the rank's
-- record), false, or nil when unknown.
function Trainers.Teaches(npcID, line, cap)
    local entry = Trainers.Known(npcID)
    if not entry or not line then return nil end
    local rec = entry.lines[line]
    if not rec then
        -- Seen teaching other professions and never this one.
        if next(entry.lines) then return false end
        return nil
    end
    if rec.ranks[cap] then return true, rec.ranks[cap] end
    if rec.none[cap] or rec.full then return false end
    return nil
end

-- A trainer for a profession's rank: "teaches" (with its rank record), "no", or
-- "unknown". cap defaults to the profession's next rank; with none, nil.
function Trainers.ForCap(npcID, line, cap)
    local yes, rank = Trainers.Teaches(npcID, line, cap)
    if yes then return "teaches", rank end
    if yes == false then return "no" end
    return "unknown"
end

function Trainers.ForNext(npcID, profession)
    local next = FG.Professions.NextRank(profession)
    if not next then return nil end
    return Trainers.ForCap(npcID, profession.line, next.cap)
end

-- The order a search shows trainers in: teaches the rank, not visited, cannot.
Trainers.ORDER = { teaches = 1, unknown = 2, no = 3 }

-- A line for a trainer's row: what it is known to teach. want: { line, cap }.
function Trainers.Badge(npcID, profession, want)
    local state, rank
    if want then
        state, rank = Trainers.ForCap(npcID, want.line, want.cap)
    else
        state, rank = Trainers.ForNext(npcID, profession)
    end
    if state == "teaches" then
        local line = want and want.line or profession and profession.line
        local label = FG.Professions.RankName(rank.cap)
        label = label and line and (label .. " " .. (Trainers.NameOf(line) or "")) or rank.name
        local parts = { L["TRAINER_TEACHES_FMT"]:format(label) }
        if rank.cost and rank.cost > 0 then parts[#parts + 1] = FG.Fares.Money(rank.cost) end
        if rank.state == "used" then parts[#parts + 1] = L["TRAINER_LEARNED"] end
        return table.concat(parts, " \194\183 "), "good"
    end
    if state == "no" then return L["TRAINER_CANNOT"], "textFaint" end
    if state == "unknown" then return L["TRAINER_UNVISITED"], "textDim" end
    return nil
end

-- What a search asks for: { line, name, cap, profession (the character's, if any) }, or
-- nil. "alchemy trainer", "expert alchemy trainer", "artisan blacksmithing".
function Trainers.Query(text)
    text = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local trainer = text:find("trainer", 1, true) ~= nil
    local rest = text:gsub("%s*trainers?%s*$", "")
    local word, body = rest:match("^(%S+)%s+(.+)$")
    local cap = word and Trainers.CapOfWord(word)
    if not cap then body = rest end
    local line = Trainers.LineOf(body)
    if not line then return nil end
    -- A bare profession name is a place search; it asks for trainers with "trainer" or a rank.
    if not (trainer or cap) then return nil end
    local p = FG.Professions.Get(line)
    return { line = line, name = Trainers.NameOf(line), cap = cap, profession = p }
end

-- The profession a search is about, when it asks for a trainer of one the character has.
function Trainers.ProfessionOf(text)
    local q = Trainers.Query(text)
    return q and q.profession or nil
end
