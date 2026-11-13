-- What leads to a quest and what follows it, read from Questie's links.
--
-- The rules are Questie's own, kept in step with QuestieDB.IsDoable:
--   preQuestSingle   any one of these turned in. Takes the place of preQuestGroup
--   preQuestGroup    all of these turned in. A positive id also counts as done if a quest
--                    exclusive to it is. A negative id does not: it must be that quest
--   parentQuest      this one must be in the log, not finished
--   availableStartingWith   this one in the log or turned in
--   exclusiveTo      taking one closes the others
--   breadcrumbs      optional quests that lead here, never required
--
-- Everything here stops at a limit, because this is data from elsewhere: the real database
-- has a chain 30 long, 166 quests linked in one piece, one quest leading to 87 others, a
-- cycle (1516 and 1519) and a link to a quest it does not hold (2955).
local FG = ForeverGPS
local Chain = {}
FG.QuestChain = Chain

local QuestDB, Status = FG.QuestDB, FG.QuestStatus

local MAX_NODES = 120
local MAX_DEPTH = 64
Chain.MAX_NODES, Chain.MAX_DEPTH = MAX_NODES, MAX_DEPTH

local function Done(id) return QuestDB.IsDone(id) end

-- Whether a quest exclusive to this one has been turned in.
local function ExclusiveDone(id)
    for _, other in ipairs(QuestDB.List(id, "exclusiveTo")) do
        if Done(other) then return true end
    end
    return false
end

local function GroupEntryMet(entry)
    if entry < 0 then return Done(-entry) end
    return Done(entry) or ExclusiveDone(entry)
end

-- What a quest asks for first, as groups:
-- { kind = "any"|"all"|"active"|"started", ids, met, missing = ids Questie does not hold }
function Chain.Requirements(id)
    local out = {}
    local single = QuestDB.List(id, "preQuestSingle")
    if #single > 0 then
        local met = false
        for _, other in ipairs(single) do met = met or Done(other) end
        out[#out + 1] = { kind = "any", ids = single, met = met }
    else
        local group = QuestDB.List(id, "preQuestGroup")
        if #group > 0 then
            local met, ids = true, {}
            for i, entry in ipairs(group) do
                ids[i] = math.abs(entry)
                met = met and GroupEntryMet(entry)
            end
            out[#out + 1] = { kind = "all", ids = ids, raw = group, met = met }
        end
    end
    local parent = QuestDB.Field(id, "parentQuest")
    if parent and parent ~= 0 then
        out[#out + 1] = { kind = "active", ids = { parent }, met = QuestDB.InLog(parent) }
    end
    local starting = QuestDB.Field(id, "availableStartingWith")
    if starting and starting ~= 0 then
        out[#out + 1] = { kind = "started", ids = { starting }, met = QuestDB.InLog(starting) or Done(starting) }
    end
    for _, group in ipairs(out) do
        group.missing = {}
        for _, other in ipairs(group.ids) do
            if not QuestDB.Exists(other) then group.missing[#group.missing + 1] = other end
        end
    end
    return out
end

-- The quests right before this one.
function Chain.Before(id)
    local out, seen = {}, {}
    local function Add(other, optional)
        if other and other ~= id and not seen[other] then
            seen[other] = true
            out[#out + 1] = { id = other, optional = optional }
        end
    end
    for _, group in ipairs(Chain.Requirements(id)) do
        for _, other in ipairs(group.ids) do Add(other) end
    end
    for _, other in ipairs(QuestDB.List(id, "breadcrumbs")) do Add(other, true) end
    for _, other in ipairs(FG.QuestIndex.Leading(id)) do Add(other) end
    return out
end

-- The quests right after this one.
function Chain.After(id)
    local out, seen = {}, {}
    local function Add(other, optional)
        if other and other ~= id and not seen[other] then
            seen[other] = true
            out[#out + 1] = { id = other, optional = optional }
        end
    end
    local nextId = QuestDB.Field(id, "nextQuestInChain")
    if nextId and nextId ~= 0 then Add(nextId) end
    for _, other in ipairs(FG.QuestIndex.Following(id)) do Add(other) end
    local target = QuestDB.Field(id, "breadcrumbForQuestId")
    if target and target ~= 0 then Add(target, true) end
    return out
end

-- Every quest before and after this one, within limits, laid out by depth.
-- { nodes = { id -> { id, depth, before, after, optional, missing } },
--   rows = { { ids at a depth } }, linear, position, total, truncated, looped, gaps }
function Chain.Walk(id)
    local nodes, order = {}, {}
    local result = { nodes = nodes, truncated = false, looped = false, gaps = 0 }

    local function Node(at)
        local node = nodes[at]
        if node then return node end
        if #order >= MAX_NODES then
            result.truncated = true
            return nil
        end
        node = { id = at, before = {}, after = {}, known = QuestDB.Exists(at) }
        nodes[at] = node
        order[#order + 1] = at
        if not node.known then result.gaps = result.gaps + 1 end
        return node
    end

    local function Note(list, value)
        for i = 1, #list do
            if list[i] == value then return end
        end
        list[#list + 1] = value
    end

    -- Out from the quest in one direction only, so a sibling's branch stays out of it.
    local function Spread(start, step, field, back)
        local queue, at = { { start, 0 } }, 1
        local seen = { [start] = true }
        while queue[at] do
            local here, depth = queue[at][1], queue[at][2]
            at = at + 1
            if depth >= MAX_DEPTH then
                result.truncated = true
            elseif nodes[here] and nodes[here].known then
                for _, link in ipairs(step(here)) do
                    local node = Node(link.id)
                    if node then
                        node.optional = node.optional or link.optional
                        Note(nodes[here][field], link.id)
                        Note(node[back], here)
                        if not seen[link.id] then
                            seen[link.id] = true
                            queue[#queue + 1] = { link.id, depth + 1 }
                        end
                    end
                end
            end
        end
    end

    Node(id)
    Spread(id, Chain.Before, "before", "after")
    Spread(id, Chain.After, "after", "before")

    -- Depth: the longest way in, which a cycle must not be able to stretch for ever.
    local depthOf, marks = {}, {}
    local function Depth(at)
        if depthOf[at] then return depthOf[at] end
        if marks[at] then
            result.looped = true
            return 0
        end
        marks[at] = true
        local deepest = 0
        for _, before in ipairs(nodes[at].before) do
            deepest = math.max(deepest, Depth(before) + 1)
        end
        marks[at] = nil
        depthOf[at] = deepest
        return deepest
    end
    local rows, deepest = {}, 0
    for _, at in ipairs(order) do
        local depth = Depth(at)
        nodes[at].depth = depth
        deepest = math.max(deepest, depth + 1)
        rows[depth + 1] = rows[depth + 1] or {}
        table.insert(rows[depth + 1], at)
    end
    local packed = {}
    for depth = 1, deepest do
        if rows[depth] then
            table.sort(rows[depth])
            packed[#packed + 1] = rows[depth]
        end
    end
    result.rows = packed

    -- "3 of 7" only where that is the truth: one line, nothing cut, nothing unknown.
    local linear = not (result.truncated or result.looped) and result.gaps == 0 and #order > 1
    for _, at in ipairs(order) do
        local node = nodes[at]
        if #node.before > 1 or #node.after > 1 or node.optional then linear = false end
    end
    result.linear = linear
    result.total = #order
    if linear then
        result.position = nodes[id].depth + 1
        local doneCount = 0
        for _, at in ipairs(order) do
            if Done(at) then doneCount = doneCount + 1 end
        end
        result.done = doneCount
    end
    return result
end

local function Usable(id)
    local s = Status.Of(id)
    return s.key ~= "no" and s.key ~= "unknown"
end

-- The way to a quest: what to do, first thing first, as a list of steps. A step with more
-- than one id is a choice, of which any one will do; nothing chooses for the player.
-- { steps = { { ids, choice } }, first = step, blocked, gaps }
function Chain.Path(id)
    local steps, visited = {}, {}
    local out = { steps = steps, blocked = false, gaps = 0 }
    local budget = MAX_NODES

    local function Visit(at, depth)
        if visited[at] or budget <= 0 or depth > MAX_DEPTH then return end
        visited[at] = true
        budget = budget - 1
        if not QuestDB.Exists(at) then
            out.gaps = out.gaps + 1
            return
        end
        if Done(at) then return end
        if at ~= id and QuestDB.InLog(at) then
            steps[#steps + 1] = { ids = { at } }
            return
        end
        for _, group in ipairs(Chain.Requirements(at)) do
            if not group.met then
                if group.kind == "any" then
                    -- Real entries list a quest as its own alternative: 1516 is one.
                    local open, known = {}, false
                    for _, other in ipairs(group.ids) do
                        if other ~= at and QuestDB.Exists(other) then
                            known = true
                            if Usable(other) then open[#open + 1] = other end
                        end
                    end
                    if #open == 0 then
                        if known then out.blocked = true else out.gaps = out.gaps + 1 end
                    elseif #open == 1 then
                        Visit(open[1], depth + 1)
                    else
                        steps[#steps + 1] = { ids = open, choice = true }
                    end
                else
                    for i, other in ipairs(group.ids) do
                        local entry = group.raw and group.raw[i] or other
                        if not GroupEntryMet(entry) or group.kind ~= "all" then
                            if not QuestDB.Exists(other) then
                                out.gaps = out.gaps + 1
                            elseif not Usable(other) then
                                out.blocked = true
                            else
                                Visit(other, depth + 1)
                            end
                        end
                    end
                end
            end
        end
        if at ~= id then steps[#steps + 1] = { ids = { at } } end
    end

    Visit(id, 0)
    out.first = steps[1]
    return out
end

-- What this quest opens once it is turned in, for "next in chain".
function Chain.Opens(id)
    local out = {}
    for _, link in ipairs(Chain.After(id)) do
        if not link.optional and QuestDB.Exists(link.id) then out[#out + 1] = link.id end
    end
    return out
end
