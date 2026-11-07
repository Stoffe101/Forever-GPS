-- One quest, in full: where this character stands with it, where it starts, what has to
-- come first and how the chain runs. Everything a list row could not say. Nothing here acts
-- by itself: directions are planned and shown, and started only by the player.
local FG = ForeverGPS
local Detail = {}
FG.QuestDetail = Detail

local Kit, Theme, Format, List = FG.Kit, FG.Theme, FG.Format, FG.List
local Browse, Chain, Status, Targets = FG.QuestBrowse, FG.QuestChain, FG.QuestStatus, FG.QuestTargets
local Planner = FG.Planner
local L = FG.L

local BACK_MAX = 12
local RAIL_X = 19

local f, list
local current
local trail = {}             -- quests opened on the way here, for Back

-- ==== rows ==================================================================

local function MakeHead(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.name = Kit.Text(row, "title", "text", 0)
    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -8)
    row.name:SetPoint("TOPRIGHT", row, "TOPRIGHT", -10, -8)
    row.mark = Kit.Icon(row, 13, "textDim")
    row.mark:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -7)
    row.word = Kit.Text(row, "label", "text")
    row.word:SetPoint("LEFT", row.mark, "RIGHT", 6, 0)
    row.word:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    row.facts = Kit.Text(row, "small", "textDim", 0)
    row.facts:SetPoint("TOPLEFT", row.mark, "BOTTOMLEFT", 0, -6)
    row.facts:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    return row
end

local function FactsLine(d)
    local parts = {}
    if d.level and d.level > 0 then parts[#parts + 1] = L["XD_LEVEL_FMT"]:format(d.level) end
    if d.need and d.need > 0 and d.need ~= d.level then parts[#parts + 1] = L["XD_NEED_FMT"]:format(d.need) end
    if d.zone then parts[#parts + 1] = d.zone end
    parts[#parts + 1] = L["XD_ID_FMT"]:format(d.id)
    if d.dungeon then parts[#parts + 1] = L["XD_DUNGEON"] end
    if d.raid then parts[#parts + 1] = L["XD_RAID"] end
    if d.group then parts[#parts + 1] = L["XD_GROUP"] end
    if d.repeatable then parts[#parts + 1] = L["XD_REPEATABLE"] end
    if d.daily then parts[#parts + 1] = L["XD_DAILY"] end
    return table.concat(parts, " · ")
end

local function MakeActions(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.go = Kit.Button(row, { text = L["XD_DIRECTIONS"], variant = "primary", height = 28, width = "fit", onClick = function()
        Detail.Go()
    end })
    row.go:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -6)
    row.map = Kit.Button(row, { text = L["XD_SHOW_ON_MAP"], height = 28, width = "fit", onClick = function() Detail.ShowOnMap() end })
    row.map:SetPoint("LEFT", row.go, "RIGHT", 6, 0)
    row.add = Kit.IconButton(row, "plus", 11, L["XD_ADD_STOP"], function() Detail.AddStop() end)
    row.add:SetPoint("LEFT", row.map, "RIGHT", 4, 0)
    return row
end

local function MakeSection(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.label = Kit.Text(row, "caption", "textFaint")
    row.label:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 10, 5)
    row.label:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -10, 5)
    return row
end

local function MakeText(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.mark = Kit.Icon(row, 12, "textDim")
    row.mark:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -5)
    row.text = Kit.Text(row, "small", "textDim", 0)
    row.text:SetPoint("TOPLEFT", row, "TOPLEFT", 28, -4)
    row.text:SetPoint("TOPRIGHT", row, "TOPRIGHT", -10, -4)
    return row
end

-- A place something can be done, with its way there.
local function MakePlace(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.mark = Kit.Icon(row, 13, "textDim")
    row.mark:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -9)
    row.go = Kit.Button(row, { text = L["QUEST_GO"], height = 24, width = "fit", onClick = function(self)
        Detail.GoTo(self:GetParent().item)
    end })
    row.go:SetPoint("TOPRIGHT", row, "TOPRIGHT", -6, -6)
    row.text = Kit.Text(row, "body", "text", 0)
    row.text:SetPoint("TOPLEFT", row, "TOPLEFT", 30, -7)
    row.place = Kit.Text(row, "small", "textDim", 0)
    row.place:SetPoint("TOPLEFT", row.text, "BOTTOMLEFT", 0, -2)
    row.place:SetPoint("TOPRIGHT", row.text, "BOTTOMRIGHT", 0, -2)
    return row
end

local function PlaceLine(target)
    if target.status ~= "ok" then return target.reason end
    if not target.settled then return L["QUEST_FINDING"] end
    if not target.best then return target.reason end
    local parts = { target.best.zone or "?" }
    if target.best.sec then parts[#parts + 1] = Format.About(target.best.sec) end
    if target.best.transports then parts[#parts + 1] = target.best.transports end
    if #target.areas > 1 then parts[#parts + 1] = L["QUEST_AREAS_FMT"]:format(#target.areas) end
    return table.concat(parts, " · ")
end

-- A quest on the chain's line: its dot on the rail, its name, its state.
local function MakeNode(parent)
    local row = CreateFrame("Button", nil, parent)
    row:RegisterForClicks("LeftButtonUp")
    row.back = Kit.Shape(row, 6, "BACKGROUND", 1)
    row.back:SetShown(false)
    Theme.Paint(function(c) row.back:SetColor(c.cardHover) end)
    row.rail = row:CreateTexture(nil, "BORDER")
    row.rail:SetWidth(2)
    row.rail:SetPoint("TOP", row, "TOPLEFT", RAIL_X, 0)
    row.rail:SetPoint("BOTTOM", row, "BOTTOMLEFT", RAIL_X, 0)
    Theme.Paint(function(c) row.rail:SetColorTexture(c.lineStrong[1], c.lineStrong[2], c.lineStrong[3], 1) end)
    row.ball = CreateFrame("Frame", nil, row)
    row.ball:SetSize(20, 20)
    row.ball:SetPoint("LEFT", row, "LEFT", RAIL_X - 10, 0)
    row.ball.back = Kit.Shape(row.ball, 10, "ARTWORK", 1)
    Theme.Paint(function(c) row.ball.back:SetColor(c.window) end)
    row.mark = Kit.Icon(row.ball, 11, "textDim")
    row.mark:SetPoint("CENTER", row.ball, "CENTER", 0, 0)
    row.mark:SetDrawLayer("OVERLAY")
    row.name = Kit.Text(row, "body", "text")
    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 38, -5)
    row.name:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -5)
    row.word = Kit.Text(row, "small", "textDim")
    row.word:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -1)
    row.word:SetPoint("TOPRIGHT", row.name, "BOTTOMRIGHT", 0, -1)
    row:SetScript("OnEnter", function(self) self.back:SetShown(true) end)
    row:SetScript("OnLeave", function(self) self.back:SetShown(self.item.id == current) end)
    row:SetScript("OnClick", function(self) Detail.Open(self.item.id) end)
    return row
end

local function Bind(row, item)
    row.item = item
    local kind = item.kind
    if kind == "head" then
        local d = item.d
        row.name:SetText(d.name)
        row.mark:SetIcon(d.status.icon)
        row.mark:SetColorKey(d.status.color)
        row.word:SetText(d.status.word)
        row.facts:SetText(FactsLine(d))
    elseif kind == "actions" then
        row.go:SetLabel(item.label)
        row.go:SetShown(item.canGo)
        row.map:ClearAllPoints()
        if item.canGo then
            row.map:SetPoint("LEFT", row.go, "RIGHT", 6, 0)
        else
            row.map:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -6)
        end
        row.add:SetShown(item.canAdd)
    elseif kind == "section" then
        row.label:SetText(item.text)
    elseif kind == "text" then
        row.mark:SetIcon(item.icon or "dot")
        row.mark:SetColorKey(item.color or "textFaint")
        row.text:SetText(item.text)
        row.text:SetColorKey(item.tone or "textDim")
    elseif kind == "place" then
        local target = item.target
        row.mark:SetIcon(item.icon or "pin")
        row.mark:SetColorKey(target.status == "ok" and "accent" or "textFaint")
        local can = target.status == "ok" and target.settled and target.best ~= nil and not item.lookOnly
        row.go:SetShown(can and true or false)
        row.text:SetPoint("TOPRIGHT", row, "TOPRIGHT", can and -(row.go:GetWidth() + 12) or -10, -7)
        row.text:SetText(target.text or "")
        row.place:SetText(PlaceLine(target) or "")
    elseif kind == "node" then
        local s = item.status
        row.mark:SetIcon(s.icon)
        row.mark:SetColorKey(s.color)
        row.name:SetText(item.name)
        row.name:SetColorKey(item.known and "text" or "textFaint")
        local word = item.optional and L["XD_OPTIONAL_FMT"]:format(s.word) or s.word
        row.word:SetText(word)
        row.back:SetShown(item.id == current or row:IsMouseOver())
        row.rail:SetShown(item.rail)
    end
end

local function Height(item, width)
    local kind = item.kind
    if kind == "head" then
        return 44 + FG.RoutePanel.TextHeight(item.d.name, width - 20, "title")
            + FG.RoutePanel.TextHeight(FactsLine(item.d), width - 20, "small")
    end
    if kind == "actions" then return 40 end
    if kind == "section" then return 26 end
    if kind == "text" then return 8 + FG.RoutePanel.TextHeight(item.text, width - 38, "small") end
    if kind == "node" then return 40 end
    if kind == "place" then
        local room = width - 30 - 70
        return 14 + FG.RoutePanel.TextHeight(item.target.text or "", room, "body") + 2
            + FG.RoutePanel.TextHeight(PlaceLine(item.target) or " ", room, "small")
    end
    return 24
end

-- ==== content ===============================================================

local function NameOfStep(step)
    local names = {}
    for i, id in ipairs(step.ids) do names[i] = Browse.NameOf(id) end
    return table.concat(names, L["XD_OR"])
end

local function Settle(target)
    if not target or target.settled or target.resolving or target.status ~= "ok" then return end
    target.resolving = true
    local id = current
    Targets.Resolve(target, function()
        target.resolving = nil
        FG.After(0, function()
            if id == current then Detail.Refresh(true) end
        end)
    end, function() return id == current end)
end

local function AddChain(items, id)
    local chain = Chain.Walk(id)
    if chain.total < 2 then return end
    local title = chain.linear and L["XD_CHAIN_PART_FMT"]:format(chain.position, chain.total) or L["XD_CHAIN"]
    items[#items + 1] = { kind = "section", text = title }
    local rows = chain.rows
    for r, ids in ipairs(rows) do
        if #ids > 1 then items[#items + 1] = { kind = "text", text = L["XD_BRANCH"], icon = "chevron-down" } end
        for _, at in ipairs(ids) do
            local node = chain.nodes[at]
            items[#items + 1] = { kind = "node", id = at, name = Browse.NameOf(at), known = node.known, optional = node.optional,
                                  status = Status.Of(at), rail = r < #rows }
        end
    end
    if chain.truncated then items[#items + 1] = { kind = "text", text = L["XD_CHAIN_CUT"], icon = "warning", color = "warn" } end
    if chain.looped then items[#items + 1] = { kind = "text", text = L["XD_CHAIN_LOOP"], icon = "warning", color = "warn" } end
    if chain.gaps > 0 then items[#items + 1] = { kind = "text", text = L["XD_CHAIN_GAP"], icon = "warning", color = "warn" } end
end

local function RequirementLine(group)
    local names = {}
    for i, other in ipairs(group.ids) do names[i] = Browse.NameOf(other) end
    local list_ = table.concat(names, ", ")
    if group.kind == "any" then return L[#names > 1 and "XD_REQ_ANY_FMT" or "XD_REQ_ONE_FMT"]:format(list_) end
    if group.kind == "all" then return L[#names > 1 and "XD_REQ_ALL_FMT" or "XD_REQ_ONE_FMT"]:format(list_) end
    if group.kind == "active" then return L["XD_REQ_ACTIVE_FMT"]:format(list_) end
    return L["XD_REQ_STARTED_FMT"]:format(list_)
end

local function AddRequirements(items, d)
    local rows = {}
    local function Line(met, text)
        rows[#rows + 1] = { kind = "text", text = text, icon = met and "check" or met == false and "close" or "dot",
                            color = met and "good" or met == false and "danger" or "textFaint" }
    end
    if d.need and d.need > 0 then Line(UnitLevel("player") >= d.need, L["XD_REQ_LEVEL_FMT"]:format(d.need)) end
    if d.maxLevel and d.maxLevel > 0 then Line(UnitLevel("player") <= d.maxLevel, L["XD_REQ_MAX_LEVEL_FMT"]:format(d.maxLevel)) end
    if d.side == "Alliance" or d.side == "Horde" then
        Line(d.side == UnitFactionGroup("player"), L["XD_REQ_SIDE_FMT"]:format(d.side))
    elseif d.side == "some" then
        Line(nil, L["XD_REQ_RACES"])
    end
    if d.classes and #d.classes > 0 then Line(d.status.state ~= "WRONG_CLASS", table.concat(d.classes, ", ")) end
    if d.skill then Line(d.status.state ~= "PROFESSION_SKILL" and d.status.state ~= "PROFESSION_MISSING" or false,
        L["XD_REQ_SKILL_FMT"]:format(d.skill.name or "?", d.skill.value or 0)) end
    if d.rep then Line(d.status.state ~= "MISSING_REPUTATION", L["XD_REQ_REP_FMT"]:format(d.rep.name or "?", d.rep.value or 0)) end
    for _, group in ipairs(d.requirements) do Line(group.met, RequirementLine(group)) end
    if #d.exclusive > 0 then
        local names = {}
        for i, other in ipairs(d.exclusive) do names[i] = Browse.NameOf(other) end
        Line(nil, L["XD_REQ_EXCLUSIVE_FMT"]:format(table.concat(names, ", ")))
    end
    if d.breadcrumbFor and d.breadcrumbFor ~= 0 then Line(nil, L["XD_BREADCRUMB_FMT"]:format(Browse.NameOf(d.breadcrumbFor))) end
    if #rows == 0 then return end
    items[#items + 1] = { kind = "section", text = L["XD_REQUIREMENTS"] }
    for _, row in ipairs(rows) do items[#items + 1] = row end
end

-- What this quest's button does, whatever the character's state with it.
local function Primary(d)
    local key = d.status.key
    if key == "active" or key == "turnin" then return L["XD_OPEN_LOG"], true end
    if key == "done" or key == "no" then return nil, false end
    if key == "locked" then
        local path = Chain.Path(d.id)
        if path.first and not path.first.choice then return L["XD_GO_FIRST"], true end
        return nil, false
    end
    return L["XD_DIRECTIONS"], true
end

local function Items()
    local d = Browse.Details(current)
    if not d then
        return { { kind = "text", text = L["XD_UNKNOWN"], icon = "warning", color = "warn" } }
    end
    local label, canGo = Primary(d)
    local items = { { kind = "head", d = d },
                    { kind = "actions", label = label or "", canGo = canGo, canAdd = Status.Open(d.status) } }
    if d.status.why then items[#items + 1] = { kind = "text", text = d.status.why, icon = "warning", color = "textFaint" } end

    local key = d.status.key
    if key ~= "done" then
        local path = Chain.Path(d.id)
        if #path.steps > 0 or path.blocked then
            items[#items + 1] = { kind = "section", text = L["XD_FIRST"] }
            for i, step in ipairs(path.steps) do
                local any = step.choice and L["XD_ONE_OF_FMT"]:format(NameOfStep(step)) or NameOfStep(step)
                items[#items + 1] = { kind = "text", text = ("%d. %s"):format(i, any), icon = step.choice and "chevron-right" or "quest",
                                      color = i == 1 and "accent" or "textFaint", tone = i == 1 and "text" or "textDim" }
            end
            if path.blocked then items[#items + 1] = { kind = "text", text = L["XD_PATH_BLOCKED"], icon = "warning", color = "warn" } end
            if path.gaps > 0 then items[#items + 1] = { kind = "text", text = L["XD_PATH_GAP"], icon = "warning", color = "warn" } end
        end
    end

    local all = Targets.Explore(d.id)
    if all.start then
        items[#items + 1] = { kind = "section", text = L["XD_STARTS"] }
        items[#items + 1] = { kind = "place", target = all.start, role = "start", icon = "quest", lookOnly = key == "no" }
        Settle(all.start)
    end
    if all.turnIn and all.turnIn.status == "ok" then
        items[#items + 1] = { kind = "section", text = L["XD_ENDS"] }
        items[#items + 1] = { kind = "place", target = all.turnIn, role = "turnin", icon = "turnin", lookOnly = key == "no" }
        Settle(all.turnIn)
    end
    AddRequirements(items, d)
    AddChain(items, d.id)
    if #d.objectives > 0 then
        items[#items + 1] = { kind = "section", text = L["XD_ABOUT"] }
        for _, line in ipairs(d.objectives) do
            if type(line) == "string" then items[#items + 1] = { kind = "text", text = line, icon = "dot" } end
        end
    end
    if #d.reputation > 0 then
        items[#items + 1] = { kind = "section", text = L["XD_REWARDS"] }
        for _, r in ipairs(d.reputation) do
            items[#items + 1] = { kind = "text", text = L["XD_REWARD_REP_FMT"]:format(r.value or 0, r.name or "?"), icon = "star-line" }
        end
    end
    return items
end

function Detail.Refresh(keepPlace)
    if f and f:IsVisible() and current then
        list:SetItems(Items(), keepPlace)
        f.back:SetShown(#trail > 0)
    end
end

-- ==== doors =================================================================

function Detail.Show(id)
    current = id
    wipe(trail)
    Detail.Refresh(false)
end

-- Another quest from this one, with Back to return.
function Detail.Open(id)
    if id == current then return end
    if current then
        trail[#trail + 1] = current
        if #trail > BACK_MAX then table.remove(trail, 1) end
    end
    current = id
    Detail.Refresh(false)
end

function Detail.Back()
    local id = table.remove(trail)
    if id then
        current = id
        Detail.Refresh(false)
    end
end

function Detail.Current() return current end
function Detail.ItemsNow() return list.items end

local function Quest() return { questID = current, title = Browse.NameOf(current) } end

-- Plans the way to a place of this quest. The route panel takes over, and starting it stays
-- the player's click: a journey under way is not touched by looking at another.
local function PlanTo(q, target)
    if not (target and target.best) then return false end
    Planner.Inspect(Targets.Destination(q, target, target.best))
    FG.Window.ShowRoute()
    return true
end

function Detail.GoTo(item)
    PlanTo(Quest(), item.target)
end

local function GoToStart(id)
    local target = Targets.Starter(id)
    if not (target and target.status == "ok") then return false end
    local q = { questID = id, title = Browse.NameOf(id) }
    Targets.Resolve(target, function() PlanTo(q, target) end)
    return true
end

-- The main button: the start, or the first thing that has to come before it, or back to the
-- quest log for one already there.
function Detail.Go()
    local s = Status.Of(current)
    if Status.Taken(s) then
        FG.Window.Show("quests")
        FG.QuestsView.SetMode("log")
        return FG.QuestsView.Focus(current)
    end
    if s.key == "locked" then
        local path = Chain.Path(current)
        if path.first and not path.first.choice then
            return GoToStart(path.first.ids[1])
        end
        return false
    end
    return GoToStart(current)
end

-- Everything known about where this quest happens, on our own map.
function Detail.ShowOnMap()
    local all = Targets.Explore(current)
    local places = {}
    local function Add(target, role, title)
        for _, area in ipairs(target and target.areas or {}) do
            places[#places + 1] = { mapID = area.spot.mapID, x = area.spot.x, y = area.spot.y, role = role,
                                    title = title or target.text, body = area.zone }
        end
    end
    Add(all.start, "start")
    for _, target in ipairs(all.objectives) do Add(target, "objective") end
    Add(all.turnIn, "turnin")
    if #places == 0 then return FG.Print(L["XD_NO_PLACES"]) end
    FG.MapPreview.ShowPlaces(Browse.NameOf(current), places)
end

function Detail.AddStop()
    local target = Targets.Starter(current)
    if not (target and target.status == "ok") then return end
    local q = Quest()
    Targets.Resolve(target, function()
        if not target.best then return end
        local stop = FG.Trip.FromTarget(Targets.Destination(q, target, target.best))
        if not stop then return end
        local _, why = FG.Trip.Add(stop)
        if why then FG.Print(why) end
    end)
end

local function Build(parent)
    f = CreateFrame("Frame", nil, parent)
    f.back = Kit.IconButton(f, "back", 12, L["XD_BACK"], function() Detail.Back() end)
    f.back:SetPoint("TOPRIGHT", f, "TOPRIGHT", -28, -2)
    f.back:Hide()
    f.close = Kit.IconButton(f, "close", 10, L["XD_CLOSE"], function() FG.Window.CloseQuest() end)
    f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    list = List.New(f, {
        make = { head = MakeHead, actions = MakeActions, section = MakeSection, text = MakeText, place = MakePlace, node = MakeNode },
        bind = Bind, height = Height,
    })
    list:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    list:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    f.list = list
    f.close:SetFrameLevel(list:GetFrameLevel() + 30)
    f.back:SetFrameLevel(list:GetFrameLevel() + 30)
    FG.On("queststatus:changed", function() Detail.Refresh(true) end)
    return f
end

function Detail.Get(parent) return f or Build(parent) end
