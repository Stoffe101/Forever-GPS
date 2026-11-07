-- Every quest Questie knows, findable: names, givers, zones, and which quests lead to which.
-- Built a few milliseconds a frame, once, the first time something wants it, and kept as
-- parallel lists of plain values, because there are thousands. It holds what is needed to
-- find a quest and no more: the details are read from Questie when a quest is opened.
local FG = ForeverGPS
local Index = {}
FG.QuestIndex = Index

local QuestDB = FG.QuestDB

local SLICE_MS, CHECK_EVERY = 3, 8
local MAX_RESULTS = 200
local TYPO_MAX = 2

local stage = "idle"         -- idle, reading or ready
local queue, at, driver
local ids, names, lows, givers, zones, maps, levels, needs, sides = {}, {}, {}, {}, {}, {}, {}, {}, {}
local rowOf = {}
local following, leading = {}, {}
local zoneRows = {}

local function Link(from, to)
    if not (from and to) or from == to then return end
    local after = following[from]
    if not after then
        after = {}
        following[from] = after
    end
    for i = 1, #after do
        if after[i] == to then return end
    end
    after[#after + 1] = to
end

local function Read(id)
    local name = QuestDB.Name(id)
    if not name then return end
    local n = #ids + 1
    ids[n], names[n], lows[n] = id, name, name:lower()
    rowOf[id] = n
    levels[n] = QuestDB.Field(id, "questLevel") or 0
    needs[n] = QuestDB.Field(id, "requiredLevel") or 0
    sides[n] = QuestDB.Side(id) or false
    local zone, mapID = QuestDB.ZoneOf(id)
    zones[n], maps[n] = zone or false, mapID or false
    if zone then
        local rows = zoneRows[zone]
        if not rows then
            rows = {}
            zoneRows[zone] = rows
        end
        rows[#rows + 1] = n
    end
    local who = QuestDB.Starters(id)
    local giver = QuestDB.EntityName("npc", who.npcs[1]) or QuestDB.EntityName("object", who.objects[1])
    givers[n] = giver and giver:lower() or false
    for _, pre in ipairs(QuestDB.List(id, "preQuestSingle")) do Link(pre, id) end
    for _, pre in ipairs(QuestDB.List(id, "preQuestGroup")) do Link(math.abs(pre), id) end
    local nextId = QuestDB.Field(id, "nextQuestInChain")
    if nextId and nextId ~= 0 then
        Link(id, nextId)
        leading[nextId] = leading[nextId] or {}
        table.insert(leading[nextId], id)
    end
end

local function Slice(frame)
    local stop = debugprofilestop() + SLICE_MS
    local n = 0
    FG.Metrics.Begin("questIndex")
    while queue[at] do
        Read(queue[at])
        at = at + 1
        n = n + 1
        if n % CHECK_EVERY == 0 and debugprofilestop() > stop then
            FG.Metrics.End("questIndex")
            return
        end
    end
    FG.Metrics.End("questIndex")
    frame:SetScript("OnUpdate", nil)
    queue, stage = nil, "ready"
    FG.Emit("questindex:ready")
end

-- Starts building, if it can and nothing has yet.
function Index.Warm()
    if stage ~= "idle" or not QuestDB.Ready() then return end
    stage, at = "reading", 1
    queue = QuestDB.AllIds()
    driver = driver or CreateFrame("Frame")
    driver:SetScript("OnUpdate", Slice)
end

function Index.Ready() return stage == "ready" end
function Index.Progress()
    if stage == "ready" then return 1 end
    if not queue or #queue == 0 then return 0 end
    return at / #queue
end
function Index.Count() return #ids end

function Index.Following(id) return following[id] or {} end
function Index.Leading(id) return leading[id] or {} end

-- A row's plain facts. Rows are small: they are read to fill a list.
function Index.Row(n)
    if not ids[n] then return nil end
    return { id = ids[n], name = names[n], level = levels[n], need = needs[n], zone = zones[n] or nil,
             mapID = maps[n] or nil, side = sides[n] or nil, giver = givers[n] or nil }
end

function Index.RowOf(id) return rowOf[id] end
function Index.Size() return #ids end

-- The sides this character cannot be on are left out of what a search offers.
local function ForThisSide(n)
    local side = sides[n]
    if not side or side == "some" then return true end
    return side == UnitFactionGroup("player")
end
Index.ForThisSide = ForThisSide

-- How well a row answers the words: lower is better, nil is not at all. Words may come in
-- any order, each found in the name, the giver or the zone.
local function Score(n, text, words)
    local low = lows[n]
    if low == text then return 0 end
    if low:sub(1, #text) == text then return 1 end
    local at1 = low:find(text, 1, true)
    if at1 then return at1 > 1 and low:sub(at1 - 1, at1 - 1) == " " and 2 or 3 end
    local giver, zone = givers[n], zones[n]
    if giver and giver:find(text, 1, true) then return 4 end
    if zone and zone:lower():find(text, 1, true) then return 5 end
    if #words < 2 then return nil end
    for _, word in ipairs(words) do
        if not (low:find(word, 1, true) or (giver and giver:find(word, 1, true))
            or (zone and zone:lower():find(word, 1, true))) then
            return nil
        end
    end
    return 6
end

local function Sorted(scored)
    table.sort(scored, function(a, b)
        if a.score ~= b.score then return a.score < b.score end
        if levels[a.n] ~= levels[b.n] then return levels[a.n] < levels[b.n] end
        return ids[a.n] < ids[b.n]
    end)
end

-- Rows answering text, best first: by id, by name in whole or part, by giver, by zone, by
-- several words at once, and a near miss when nothing else answers. everySide: quests for
-- the other side too. Bounded, and runs over a list of a few thousand short strings.
function Index.Find(text, everySide)
    local out = {}
    if stage ~= "ready" then return out end
    text = strtrim(text or ""):lower()
    if text == "" then return out end
    local asId = tonumber(text)
    if asId and rowOf[asId] then out[1] = rowOf[asId] end
    local words = {}
    for word in text:gmatch("%S+") do words[#words + 1] = word end
    local scored = {}
    for n = 1, #ids do
        if everySide or ForThisSide(n) then
            local score = Score(n, text, words)
            if score then scored[#scored + 1] = { n = n, score = score } end
        end
    end
    if #scored == 0 and #text >= 4 then
        local Distance = FG.Search._Distance
        for n = 1, #ids do
            if (everySide or ForThisSide(n)) and math.abs(#lows[n] - #text) <= TYPO_MAX then
                if Distance(lows[n], text, TYPO_MAX) <= TYPO_MAX then scored[#scored + 1] = { n = n, score = 7 } end
            end
        end
    end
    Sorted(scored)
    for i = 1, math.min(#scored, MAX_RESULTS) do
        if scored[i].n ~= out[1] then out[#out + 1] = scored[i].n end
    end
    return out
end

-- Every zone with quests in it, by name, with how many.
function Index.Zones()
    local out = {}
    for zone, rows in pairs(zoneRows) do out[#out + 1] = { zone = zone, count = #rows } end
    table.sort(out, function(a, b) return a.zone < b.zone end)
    return out
end

function Index.InZone(zone) return zoneRows[zone] or {} end

FG.On("quests:changed", function()
    -- A Questie that came late: nothing could be built before it did.
    if stage == "idle" then Index.Warm() end
end)
FG.On("window:shown", Index.Warm)
