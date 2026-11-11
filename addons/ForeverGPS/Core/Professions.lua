-- What this character can make, read from the game: professions and skill from
-- GetProfessions, recipes and their reagents from the profession window when it opens. The
-- client says each known recipe's colour at the current skill, but not the skills at which
-- it changes, so every colour seen is written down against the skill it was seen at, and
-- the turning points close in with use. Nothing here comes from another addon's data.
--
-- docs/PROFESSIONS.md has what is known for certain and what is estimated.
local FG = ForeverGPS
local Prof = {}
FG.Professions = Prof

local L = FG.L

-- The game's difficulty numbers: 0 orange (always), 1 yellow, 2 green, 3 grey (never).
Prof.ORANGE, Prof.YELLOW, Prof.GREEN, Prof.GREY = 0, 1, 2, 3

-- Professions that make nothing: there is no recipe plan for them, only skill.
local GATHERING = { [182] = true, [186] = true, [393] = true, [356] = true }   -- herbalism, mining, skinning, fishing

-- Rank names by the cap the game gives. The cap is the game's; only the name is ours.
local RANKS = { [75] = "RANK_APPRENTICE", [150] = "RANK_JOURNEYMAN", [225] = "RANK_EXPERT", [300] = "RANK_ARTISAN" }
local NEXT_CAP = { [75] = 150, [150] = 225, [225] = 300 }

local function Store()
    local c = FG.char
    if not c then return { list = {}, recipes = {} } end
    c.professions = c.professions or { list = {}, recipes = {} }
    return c.professions
end

-- ==== the character's professions ===========================================

local function Read(index)
    if not index then return nil end
    local name, icon, skill, max, _, _, skillLine = GetProfessionInfo(index)
    if not name then return nil end
    return { name = name, icon = icon, skill = skill or 0, max = max or 0, line = skillLine, gathering = GATHERING[skillLine] or false }
end

-- Reads every profession now. Cheap: five calls.
function Prof.Refresh()
    if not GetProfessions then return Store().list end
    local list = {}
    local p1, p2, archaeology, fishing, cooking, firstAid = GetProfessions()
    for _, index in ipairs({ p1 or false, p2 or false, cooking or false, firstAid or false, fishing or false, archaeology or false }) do
        local p = index and Read(index)
        if p then list[#list + 1] = p end
    end
    local store = Store()
    store.list, store.at = list, time()
    FG.Emit("professions:changed")
    return list
end

function Prof.List() return Store().list end

function Prof.Get(line)
    for _, p in ipairs(Store().list) do
        if p.line == line or p.name == line then return p end
    end
    return nil
end

function Prof.IsGathering(p) return p.gathering == true end

function Prof.RankName(max) return RANKS[max] and L[RANKS[max]] or nil end

-- The next rank and the cap it brings, from the cap the game says this character has.
-- ready: the skill has reached the current cap, so nothing more can be gained without it.
-- Whether a trainer will teach it sooner is the trainer's to say: docs/PROFESSIONS.md.
function Prof.NextRank(p)
    local nextCap = NEXT_CAP[p.max]
    if not nextCap then return nil end
    return { cap = nextCap, name = RANKS[nextCap] and L[RANKS[nextCap]], ready = p.skill >= p.max, close = p.skill >= p.max - 25 }
end

-- ==== recipes ===============================================================

local function Reagents(schematic)
    local out = {}
    for _, slot in ipairs(schematic and schematic.reagentSlotSchematics or {}) do
        local first = slot.reagents and slot.reagents[1]
        if first and first.itemID and (slot.quantityRequired or 0) > 0 and slot.reagentType ~= 0 then
            out[#out + 1] = { id = first.itemID, n = slot.quantityRequired }
        end
    end
    return out
end

-- Where a colour seen at a skill narrows the turning points: y the skill a recipe turns
-- yellow at, g green, x grey. Seen colour d at skill s puts every point up to d at or below
-- s, and the others above it. th[name.."lo"] and th[name.."hi"] are the narrowest bounds.
local POINTS = { "y", "g", "x" }
local function See(th, skill, diff)
    for k, name in ipairs(POINTS) do
        if diff >= k then
            th[name .. "hi"] = math.min(th[name .. "hi"] or skill, skill)
        else
            th[name .. "lo"] = math.max(th[name .. "lo"] or skill + 1, skill + 1)
        end
    end
end
Prof._See = See

-- What reading the profession window has done this session, for /fgps report. Confirmed in
-- the game (2.4's saved data): C_TradeSkillUI gives every recipe of the open profession,
-- learned or not, with outputs and reagents, and its recipe IDs are the spell IDs of the
-- client's data. Whether TRADE_SKILL_LIST_UPDATE always follows the window opening is not
-- confirmed, so the window opening also reads, and reads again, a few times, while the
-- list is empty or a learned recipe has no reagents yet.
Prof.status = { path = nil, events = {}, reads = 0, lastCount = 0, lastLearned = 0, missing = 0, matched = 0,
                lastError = nil, lastWhy = nil, at = nil }
local READ_TRIES, READ_GAP = 6, 1

-- Reads the open profession window's recipes. Returns how many were read, or nil and why:
-- "api" (no such API), "window" (none open), "not ready", "empty".
function Prof.ReadRecipes()
    local T = C_TradeSkillUI
    local status = Prof.status
    if not (T and T.GetAllRecipeIDs and T.GetRecipeInfo) then
        status.path, status.lastWhy = "missing", "api"
        return nil, "api"
    end
    status.path = "C_TradeSkillUI"
    if T.IsTradeSkillReady and not T.IsTradeSkillReady() then
        status.lastWhy = "not ready"
        return nil, "not ready"
    end
    local base = T.GetBaseProfessionInfo and T.GetBaseProfessionInfo()
    local line = base and base.professionID
    if not line or line == 0 then
        status.lastWhy = "window"
        return nil, "window"
    end
    local p = Prof.Get(line)
    local skill = base.skillLevel or (p and p.skill) or 0
    local ids = T.GetAllRecipeIDs() or {}
    if #ids == 0 then
        status.lastWhy = "empty"
        return nil, "empty"
    end
    local store = Store()
    local count, learned, missing, matched = 0, 0, 0, 0
    for _, id in ipairs(ids) do
        local info = T.GetRecipeInfo(id)
        if info and not info.isDummyRecipe then
            local r = store.recipes[id] or { id = id }
            store.recipes[id] = r
            r.name, r.icon, r.line, r.learned = info.name or r.name, info.icon or r.icon, line, info.learned and true or false
            r.diff = info.relativeDifficulty
            r.th = r.th or {}
            if r.learned and r.diff then See(r.th, skill, r.diff) end
            if not (r.out and r.reagents) and T.GetRecipeSchematic then
                local s = T.GetRecipeSchematic(id, false)
                if s and s.outputItemID then
                    r.out, r.qmin, r.qmax = s.outputItemID, s.quantityMin or 1, s.quantityMax or s.quantityMin or 1
                    r.reagents = Reagents(s)
                end
            end
            -- The client's data knows it too: its reagents stand in until the window's arrive.
            local d = Prof.Data(id)
            if d then
                matched = matched + 1
                if not r.out and d.out then r.out, r.qmin, r.qmax, r.fromData = d.out, d.count, d.count, true end
                if not r.reagents and #d.reagents > 0 then r.reagents, r.fromData = d.reagents, true end
            end
            if r.learned then
                learned = learned + 1
                if not (r.out and r.reagents) then missing = missing + 1 end
            end
            count = count + 1
        end
    end
    store.readAt = time()
    status.reads, status.lastCount, status.lastLearned, status.missing, status.matched = status.reads + 1, count, learned, missing, matched
    status.at, status.lastWhy, status.line = time(), missing > 0 and "partial" or "ok", line
    FG.Emit("recipes:changed", line)
    return count, missing > 0 and "partial" or nil
end

-- A read soon, once however many events ask for it; tried again a few times while the
-- window's data is not all there. Never more than READ_TRIES in a row.
local readWaits, readTries = false, 0
local function ReadSoon(delay)
    if readWaits then return end
    readWaits = true
    FG.After(delay or 0.3, function()
        readWaits = false
        local ok, n, why = pcall(Prof.ReadRecipes)
        if not ok then
            Prof.status.lastError = tostring(n)
            FG.Metrics.Note("recipe read failed: " .. tostring(n))
            return
        end
        if (not n or why) and readTries < READ_TRIES and Prof.status.windowOpen then
            readTries = readTries + 1
            ReadSoon(READ_GAP)
        else
            readTries = 0
        end
    end)
end
Prof._ReadSoon = ReadSoon

-- Unseen ground: a colour band assumed this wide past the last skill it was seen at.
local BAND = 10

-- The best guess at a turning point, and whether it is pinned down (bounds within 2). With
-- only a lower bound, "not yet" is all that is known: later is the guess, by the band.
local function Point(th, name, after)
    local lo, hi = th[name .. "lo"], th[name .. "hi"]
    if lo and hi then return math.floor((lo + hi) / 2), hi - lo <= 2 end
    if hi then return hi, false end
    if lo then return after(lo), false end
    return nil, false
end

-- ==== the client's recipe data ==============================================
-- Data/Recipes.lua: every recipe's reagents, output, the skill it is learned at, and the
-- skills where it turns yellow and grey, from the client's own tables (via profit, MIT:
-- THIRD_PARTY.md). Parsed on first use, one recipe at a time.

local parsed = {}
local SOURCE = { t = "trainer", i = "item", f = "trainer?", u = "unknown" }

local function Pairs(text)
    local out = {}
    for id, n in (text or ""):gmatch("(%d+):(%d+)") do out[#out + 1] = { id = tonumber(id), n = tonumber(n) } end
    return out
end

-- A recipe from the client's data: { id, line, out, count, reagents, learn, trainer,
-- yellow, grey, sources = { "trainer", ... }, items = { {id, n = skill} }, unsure }, or nil.
function Prof.Data(id)
    if parsed[id] ~= nil then return parsed[id] or nil end
    local packed = FG.RecipeData and FG.RecipeData.recipes[id]
    if not packed then
        parsed[id] = false
        return nil
    end
    local f = {}
    for field in (packed .. "|"):gmatch("([^|]*)|") do f[#f + 1] = field end
    local make = Pairs(f[2])[1]
    local lines = {}
    for line in (f[1] or ""):gmatch("%d+") do lines[tonumber(line)] = true end
    local d = { id = id, line = tonumber(f[1]:match("%d+")), lines = lines, out = make and make.id, count = make and make.n or 1,
                reagents = Pairs(f[3]), learn = tonumber(f[4]), trainer = tonumber(f[5]),
                yellow = tonumber(f[6]), grey = tonumber(f[7]), sources = {}, items = Pairs(f[9]),
                unsure = (f[10] or "") ~= "" }
    for letter in (f[8] or ""):gmatch("%a") do d.sources[#d.sources + 1] = SOURCE[letter] end
    parsed[id] = d
    return d
end

-- The chance a craft gives a point at skill s, whether that is sure, and what it rests on:
-- "client" (the game's own turning points), "seen" (this character's window, pinned down)
-- or "estimate". The rule is the long-standing one: always while orange, never once grey,
-- and between yellow and grey (grey - s) / (grey - yellow). It is not confirmed on Forever.
-- Turning points this character saw that disagree with the client's are believed instead.
function Prof.Chance(r, s)
    local th = r.th or {}
    local d = r.id and Prof.Data(r.id)
    if d and d.yellow and d.grey and d.grey > d.yellow then
        local fits = not ((th.xhi and th.xhi < d.grey) or (th.xlo and th.xlo > d.grey)
                          or (th.yhi and th.yhi < d.yellow) or (th.ylo and th.ylo > d.yellow))
        if fits then
            if s >= d.grey then return 0, true, "client" end
            if s < d.yellow then return 1, true, "client" end
            return (d.grey - s) / (d.grey - d.yellow), true, "client"
        end
        r.conflict = true
    end
    local y, ySure = Point(th, "y", function(lo) return lo + BAND / 2 end)
    local x, xSure = Point(th, "x", function(lo) return math.max(lo, y or lo) + 2 * BAND end)
    if not x and y then x = y + 2 * BAND end
    if not y and x then y = x - 2 * BAND end
    if not (y and x) then return nil, false end
    local sure = ySure and xSure
    local source = sure and "seen" or "estimate"
    if s >= x then return 0, xSure, xSure and "seen" or "estimate" end
    if s < y then return 1, ySure, ySure and "seen" or "estimate" end
    return math.max(0, math.min(1, (x - s) / math.max(1, x - y))), sure, source
end

-- Recipes of a profession this character has not learned, that can be learned somewhere:
-- from a trainer, or a recipe item. Shaped like a learned recipe, with learned = false and
-- data = the client's record. Recipes the client's data marks incomplete are left out.
function Prof.Obtainable(line)
    local out = {}
    local known = Store().recipes
    if not (FG.RecipeData and line) then return out end
    local name = C_Spell and C_Spell.GetSpellName
    for id in pairs(FG.RecipeData.recipes) do
        local d = Prof.Data(id)
        if d.lines[line] and d.out and not (known[id] and known[id].learned) and #d.sources > 0
            and d.sources[1] ~= "unknown" and not d.unsure then
            out[#out + 1] = { id = id, line = line, out = d.out, qmin = d.count, qmax = d.count, reagents = d.reagents,
                              learned = false, data = d, learnAt = d.learn or (d.items[1] and d.items[1].n),
                              name = name and name(id) or ("#" .. id) }
        end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

function Prof.Recipes(line)
    local out = {}
    for _, r in pairs(Store().recipes) do
        if not line or r.line == line then out[#out + 1] = r end
    end
    table.sort(out, function(a, b) return (a.name or "") < (b.name or "") end)
    return out
end

function Prof.Recipe(id) return Store().recipes[id] end

-- When the recipes were last read: a plan made before is out of date.
function Prof.ReadAt() return Store().readAt end

-- ==== events ================================================================

local function Saw(event)
    Prof.status.events[event] = (Prof.status.events[event] or 0) + 1
end

FG.OnEvent("SKILL_LINES_CHANGED", function()
    Saw("SKILL_LINES_CHANGED")
    Prof.Refresh()
end)
FG.OnEvent("TRADE_SKILL_SHOW", function()
    Saw("TRADE_SKILL_SHOW")
    Prof.status.windowOpen = true
    readTries = 0
    Prof.Refresh()
    ReadSoon(0.5)
end)
FG.OnEvent("TRADE_SKILL_LIST_UPDATE", function()
    Saw("TRADE_SKILL_LIST_UPDATE")
    ReadSoon(0.3)
end)
FG.OnEvent("TRADE_SKILL_DATA_SOURCE_CHANGED", function()
    Saw("TRADE_SKILL_DATA_SOURCE_CHANGED")
    ReadSoon(0.3)
end)
FG.OnEvent("TRADE_SKILL_CLOSE", function()
    Saw("TRADE_SKILL_CLOSE")
    Prof.status.windowOpen = false
end)
FG.On("login", function() FG.After(3, Prof.Refresh) end)
