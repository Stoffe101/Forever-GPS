-- Finding quests that are not in the log: by words, by zone, by what can be done now, and
-- near the player. Status comes from QuestStatus and places from QuestTargets, so this only
-- chooses and orders. A list that needs every quest's status gets it from a scan a few
-- milliseconds a frame, and says so until it has finished.
local FG = ForeverGPS
local Browse = {}
FG.QuestBrowse = Browse

local Index, Status, QuestDB = FG.QuestIndex, FG.QuestStatus, FG.QuestDB
local Bridge = FG.Bridge

local SLICE_MS, CHECK_EVERY = 3, 8
local LIST_MAX = 200
local NEAR_YARDS = 2500      -- on this land and close enough to be worth pricing
local NEAR_PRICED = 8        -- how many get a real travel time
local LEVEL_BELOW, LEVEL_ABOVE = 5, 3

-- ==== the scan ==============================================================

local scan = { at = 1, epoch = 0, done = false }
local driver

local function Slice(frame)
    local stop = debugprofilestop() + SLICE_MS
    local size = Index.Size()
    FG.Metrics.Begin("questScan")
    while scan.at <= size do
        local row = Index.Row(scan.at)
        if row then Status.Of(row.id) end
        scan.at = scan.at + 1
        if scan.at % CHECK_EVERY == 0 and debugprofilestop() > stop then
            FG.Metrics.End("questScan")
            return
        end
    end
    FG.Metrics.End("questScan")
    frame:SetScript("OnUpdate", nil)
    scan.done = true
    FG.Emit("questscan:done")
end

-- Reads every quest's status once, or again after something changed them.
function Browse.Scan()
    if not Index.Ready() then return end
    if scan.done and scan.epoch == Status.Epoch() then return end
    scan.at, scan.done, scan.epoch = 1, false, Status.Epoch()
    driver = driver or CreateFrame("Frame")
    driver:SetScript("OnUpdate", Slice)
end

function Browse.Scanned() return scan.done and scan.epoch == Status.Epoch() end

-- ==== filters ===============================================================

Browse.FILTERS = { "available", "soon", "level", "chains", "repeatable", "log", "done", "all" }

local function NearLevel(row, level)
    local q = row.level > 0 and row.level or row.need
    return q >= level - LEVEL_BELOW and q <= level + LEVEL_ABOVE
end

local PASSES = {
    available = function(_, s) return Status.Open(s) end,
    -- Only an earlier quest stands in the way, or a few levels.
    soon = function(_, s) return s.key == "locked" or s.key == "level" end,
    level = function(row, s, level) return (Status.Open(s) or s.key == "locked") and NearLevel(row, level) end,
    chains = function(row, s) return (Status.Open(s) or s.key == "locked") and #Index.Following(row.id) > 0 end,
    repeatable = function(row, s) return s.key ~= "no" and QuestDB.Is(row.id, "IsRepeatable") end,
    log = function(_, s) return Status.Taken(s) end,
    done = function(_, s) return Status.Finished(s) end,
    all = function() return true end,
}

local function Order(a, b)
    if a.status.rank ~= b.status.rank then return a.status.rank < b.status.rank end
    if a.row.need ~= b.row.need then return a.row.need < b.row.need end
    return a.row.id < b.row.id
end

-- What answers: opts = { text, zone, filter }. { items, total, partial, capped }, each item
-- { row, status }. Words keep the order they were found in, since that is by relevance.
function Browse.List(opts)
    local rows, ranked
    if opts.text and opts.text ~= "" then
        rows, ranked = Index.Find(opts.text, opts.filter == "all"), true
    elseif opts.zone then
        rows = Index.InZone(opts.zone)
    else
        rows = {}
        for n = 1, Index.Size() do rows[n] = n end
    end
    -- A list of everything needs the scan; a zone or a search is short enough to read.
    local partial = #rows > LIST_MAX and not Browse.Scanned()
    if partial then Browse.Scan() end
    local level = UnitLevel("player")
    local pass = PASSES[opts.filter or "all"] or PASSES.all
    local items = {}
    for _, n in ipairs(rows) do
        local row = Index.Row(n)
        if row and (opts.filter == "all" or Index.ForThisSide(n)) then
            local s = Status.Of(row.id)
            if pass(row, s, level) then items[#items + 1] = { row = row, status = s } end
        end
    end
    if not ranked then table.sort(items, Order) end
    local total = #items
    for i = #items, LIST_MAX + 1, -1 do items[i] = nil end
    return { items = items, total = total, partial = partial, capped = total > LIST_MAX }
end

-- ==== near the player =======================================================

-- The first place a quest starts, on this land: how far, in a straight line.
local function StarterDistance(id, start)
    local who = QuestDB.Starters(id)
    local best
    local function Look(kind, ids)
        for i = 1, math.min(#ids, 3) do
            for _, s in ipairs(QuestDB.Spots(kind, ids[i])) do
                local ci, wx, wy = Bridge.WorldPos(s.mapID, s.x, s.y)
                if ci == start.ci then
                    local d = ((wx - start.wx) ^ 2 + (wy - start.wy) ^ 2) ^ 0.5
                    if not best or d < best then best = d end
                end
            end
        end
    end
    Look("npc", who.npcs)
    Look("object", who.objects)
    return best
end

local near = { list = {}, job = 0, busy = false }

-- Quests to pick up near the player, in three stages so none is dear: status narrows five
-- thousand to what is open, a straight line narrows that to what is close, and only the
-- closest few are priced by the route engine. done(list) with { row, status, yards, sec }.
function Browse.Near(done)
    local start = Bridge.PlayerStart()
    if not (start and Index.Ready()) then return false end
    near.job = near.job + 1
    near.busy = true
    local job, n, size = near.job, 1, Index.Size()
    local found = {}
    local frame = CreateFrame("Frame")
    local function Finish()
        table.sort(found, function(a, b) return a.yards < b.yards end)
        local pending = math.min(#found, NEAR_PRICED)
        for i = #found, pending + 1, -1 do found[i] = nil end
        near.busy = false
        if pending == 0 then
            near.list = found
            return done(found)
        end
        for i = 1, #found do
            local item = found[i]
            local spot = FG.QuestTargets.Starter(item.row.id)
            local best = spot and spot.areas[1] and spot.areas[1].spot
            if best then
                FG.Eta.Request({ mapID = best.mapID, x = best.x, y = best.y, name = best.name or "?" }, function(value)
                    item.sec = value and value.sec or nil
                    pending = pending - 1
                    if pending == 0 then
                        table.sort(found, function(a, b) return (a.sec or a.yards / 7) < (b.sec or b.yards / 7) end)
                        near.list = found
                        done(found)
                    end
                end, function() return job == near.job end)
            else
                pending = pending - 1
            end
        end
    end
    frame:SetScript("OnUpdate", function(self)
        if job ~= near.job then return self:SetScript("OnUpdate", nil) end
        local stop = debugprofilestop() + SLICE_MS
        FG.Metrics.Begin("questNear")
        while n <= size do
            local row = Index.Row(n)
            if row and Index.ForThisSide(n) then
                local s = Status.Of(row.id)
                if Status.Open(s) then
                    local yards = StarterDistance(row.id, start)
                    if yards and yards <= NEAR_YARDS then found[#found + 1] = { row = row, status = s, yards = yards } end
                end
            end
            n = n + 1
            if n % CHECK_EVERY == 0 and debugprofilestop() > stop then
                FG.Metrics.End("questNear")
                return
            end
        end
        FG.Metrics.End("questNear")
        self:SetScript("OnUpdate", nil)
        Finish()
    end)
    return true
end

function Browse.NearBusy() return near.busy end
function Browse.NearList() return near.list end

-- ==== one quest =============================================================

local function BitsOf(mask)
    local out, bit = {}, 1
    for i = 1, 12 do
        if mask % (bit * 2) >= bit then out[#out + 1] = i end
        bit = bit * 2
    end
    return out
end

local function ClassNames(mask)
    local out = {}
    for _, i in ipairs(BitsOf(mask)) do
        local name = GetClassInfo(i)
        if name then out[#out + 1] = name end
    end
    return out
end

local function Who(kindNames, who)
    local out = {}
    for _, id in ipairs(who.npcs) do
        out[#out + 1] = { kind = "npc", id = id, name = QuestDB.EntityName("npc", id) }
    end
    for _, id in ipairs(who.objects) do
        out[#out + 1] = { kind = "object", id = id, name = QuestDB.EntityName("object", id) }
    end
    if kindNames then
        for _, id in ipairs(who.items) do
            out[#out + 1] = { kind = "item", id = id, name = QuestDB.EntityName("item", id) }
        end
    end
    return out
end

-- Everything worth saying about one quest, read when it is opened.
function Browse.Details(id)
    if not QuestDB.Exists(id) then return nil end
    local zone, mapID = QuestDB.ZoneOf(id)
    local d = {
        id = id, name = QuestDB.Name(id) or ("#" .. id),
        level = QuestDB.Field(id, "questLevel"), need = QuestDB.Field(id, "requiredLevel"),
        maxLevel = QuestDB.Field(id, "requiredMaxLevel"), zone = zone, mapID = mapID,
        status = Status.Of(id), side = QuestDB.Side(id),
        starters = Who(true, QuestDB.Starters(id)), finishers = Who(false, QuestDB.Finishers(id)),
        objectives = QuestDB.List(id, "objectivesText"),
        requirements = FG.QuestChain.Requirements(id),
        exclusive = QuestDB.List(id, "exclusiveTo"), breadcrumbs = QuestDB.List(id, "breadcrumbs"),
        breadcrumbFor = QuestDB.Field(id, "breadcrumbForQuestId"),
        repeatable = QuestDB.Is(id, "IsRepeatable"), daily = QuestDB.Is(id, "IsDailyQuest"),
        dungeon = QuestDB.Is(id, "IsDungeonQuest"), raid = QuestDB.Is(id, "IsRaidQuest"), group = QuestDB.Is(id, "IsGroupQuest"),
    }
    local classes = QuestDB.Field(id, "requiredClasses")
    if classes and classes ~= 0 then d.classes = ClassNames(classes) end
    local skill = QuestDB.Field(id, "requiredSkill")
    if type(skill) == "table" then d.skill = { name = QuestDB.SkillName(skill[1]), value = skill[2] } end
    local rep = QuestDB.Field(id, "requiredMinRep")
    if type(rep) == "table" then d.rep = { name = QuestDB.FactionName(rep[1]), value = rep[2] } end
    local rewards = {}
    for _, pair in ipairs(QuestDB.List(id, "reputationReward")) do
        if type(pair) == "table" then rewards[#rewards + 1] = { name = QuestDB.FactionName(pair[1]), value = pair[2] } end
    end
    d.reputation = rewards
    return d
end

-- A name for a quest in a sentence: its own, or its id if Questie does not hold it.
function Browse.NameOf(id)
    return QuestDB.Name(id) or ("#" .. tostring(id))
end
