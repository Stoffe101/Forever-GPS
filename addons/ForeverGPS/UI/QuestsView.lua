-- From Your Quests: the quest log as places to go. Each quest opens into its
-- unfinished objectives and its turn-in, each with where it is, how long the
-- journey takes, and a route when one can honestly be offered.
local _, FG = ...
local View = {}
FG.QuestsView = View

local Kit, Theme, Format, List = FG.Kit, FG.Theme, FG.Format, FG.List
local Planner, Quests, Targets = FG.Planner, FG.Quests, FG.QuestTargets
local L = FG.L

local QUEST_H, ZONE_H = 60, 26

local f, list
local expanded = {}          -- questID -> true
local resolved = {}          -- questID -> targets from QuestTargets.For
local epoch = 0              -- estimates from before a change are dropped

-- ==== rows ==================================================================

local function MakeZone(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.label = Kit.Text(row, "caption", "textFaint")
    row.label:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 10, 6)
    row.label:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -10, 6)
    return row
end

local function MakeQuest(parent)
    local row = CreateFrame("Button", nil, parent)
    row:RegisterForClicks("LeftButtonUp")
    row.back = Kit.Shape(row, 7, "BACKGROUND", 1)
    row.back:SetShown(false)
    Theme.Paint(function(c) row.back:SetColor(c.cardHover) end)
    row.badge = CreateFrame("Frame", nil, row)
    row.badge:SetSize(30, 30)
    row.badge:SetPoint("LEFT", row, "LEFT", 10, 0)
    row.badge.back = Kit.Shape(row.badge, 15, "BACKGROUND", 1)
    Theme.Paint(function(c) row.badge.back:SetColor(c.card) end)
    row.level = Kit.Text(row.badge, "label", "textDim")
    row.level:SetPoint("CENTER", row.badge, "CENTER", 0, 0)
    row.level:SetJustifyV("MIDDLE")
    row.level:SetJustifyH("CENTER")
    row.chevron = Kit.Icon(row, 11, "textFaint")
    row.chevron:SetPoint("RIGHT", row, "RIGHT", -12, 0)
    row.next = Kit.IconButton(row, "nav-arrow", 13, L["QUEST_NEXT"], function(self)
        View.GoNext(self:GetParent().item.quest)
    end)
    row.next:SetPoint("RIGHT", row, "RIGHT", -28, 0)
    row.name = Kit.Text(row, "heading", "text")
    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 50, -9)
    row.name:SetPoint("TOPRIGHT", row, "TOPRIGHT", -56, -9)
    row.status = Kit.Text(row, "small", "textDim")
    row.status:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
    row.status:SetPoint("TOPRIGHT", row.name, "BOTTOMRIGHT", 0, -2)
    row.bar = Kit.Bar(row, 3, "accent")
    row.bar:SetPoint("TOPLEFT", row.status, "BOTTOMLEFT", 0, -5)
    row.bar:SetPoint("TOPRIGHT", row.status, "BOTTOMRIGHT", 0, -5)
    row:SetScript("OnEnter", function(self) self.back:SetShown(true) end)
    row:SetScript("OnLeave", function(self) self.back:SetShown(false) end)
    row:SetScript("OnClick", function(self) View.Toggle(self.item.quest.questID) end)
    return row
end

local STATUS_COLOR = { ready = "good", failed = "danger", open = "textDim" }

local function BindQuest(row, item)
    local q = item.quest
    row.level:SetText(q.level and q.level > 0 and q.level or "?")
    row.name:SetText(q.title)
    local status, state = Quests.Status(q)
    row.status:SetText(status)
    row.status:SetColorKey(STATUS_COLOR[state])
    row.bar:SetColorKey(state == "ready" and "good" or "accent")
    row.bar:SetValue(Quests.Progress(q))
    row.chevron:SetIcon(expanded[q.questID] and "chevron-down" or "chevron-right")
    row.back:SetShown(row:IsMouseOver())
end

local function MakeTarget(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.mark = Kit.Icon(row, 13, "textDim")
    row.mark:SetPoint("TOPLEFT", row, "TOPLEFT", 24, -9)
    row.go = Kit.Button(row, { text = L["QUEST_GO"], height = 24, width = "fit", onClick = function(self)
        View.Go(self:GetParent().item)
    end })
    row.go:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -6)
    row.text = Kit.Text(row, "body", "text", 0)
    row.text:SetPoint("TOPLEFT", row, "TOPLEFT", 44, -7)
    row.place = Kit.Text(row, "small", "textDim", 0)
    row.place:SetPoint("TOPLEFT", row.text, "BOTTOMLEFT", 0, -2)
    row.place:SetPoint("TOPRIGHT", row.text, "BOTTOMRIGHT", 0, -2)
    return row
end

-- Where a target is, in a line.
local function PlaceLine(target)
    if target.status ~= "ok" then return target.reason end
    if not target.settled then return L["QUEST_FINDING"] end
    local best = target.best
    if not best then return target.reason end
    local parts = { best.zone or "?" }
    if best.sec then parts[#parts + 1] = L["ETA_SHORT_FMT"]:format(Format.Duration(best.sec)) end
    if best.transports then parts[#parts + 1] = best.transports end
    if #target.areas > 1 then parts[#parts + 1] = L["QUEST_AREAS_FMT"]:format(#target.areas) end
    return table.concat(parts, " · ")
end

local function TargetText(item)
    local o = item.objective
    return o and o.text or item.target.text or ""
end

local function BindTarget(row, item)
    local target = item.target
    local can = target.status == "ok" and not target.done and target.settled and target.best ~= nil
    row.mark:SetIcon(target.done and "check" or target.kind == "turnin" and "turnin" or "pin")
    row.mark:SetColorKey(target.done and "good" or target.status == "ok" and "accent" or "textFaint")
    row.go:SetShown(can and true or false)
    local right = can and (row.go:GetWidth() + 14) or 10
    row.text:SetPoint("TOPRIGHT", row, "TOPRIGHT", -right, -7)
    row.text:SetText(TargetText(item))
    row.text:SetColorKey(target.done and "textFaint" or "text")
    local place = not target.done and PlaceLine(target) or nil
    row.place:SetText(place or "")
    row.place:SetShown(place ~= nil)
    row.place:SetColorKey(target.status == "ok" and "textDim" or "textFaint")
end

local function TargetHeight(item, width)
    local room = width - 44 - 96
    local h = FG.RoutePanel.TextHeight(TargetText(item), room, "body") + 14
    if not item.target.done then
        local place = PlaceLine(item.target)
        if place then h = h + 2 + FG.RoutePanel.TextHeight(place, room, "small") end
    end
    return math.max(36, h)
end

local function MakeNote(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.text = Kit.Text(row, "small", "textDim", 0)
    row.text:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -8)
    row.text:SetPoint("TOPRIGHT", row, "TOPRIGHT", -10, -8)
    return row
end

local function MakeEmpty(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.title = Kit.Text(row, "label", "text", 0)
    row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -16)
    row.title:SetPoint("TOPRIGHT", row, "TOPRIGHT", -10, -16)
    row.body = Kit.Text(row, "small", "textDim", 0)
    row.body:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -4)
    row.body:SetPoint("TOPRIGHT", row.title, "BOTTOMRIGHT", 0, -4)
    return row
end

local function Bind(row, item)
    if item.kind == "quest" then BindQuest(row, item)
    elseif item.kind == "zone" then row.label:SetText(item.text)
    elseif item.kind == "target" then BindTarget(row, item)
    elseif item.kind == "note" then row.text:SetText(item.text)
    elseif item.kind == "empty" then
        row.title:SetText(L["QUESTS_EMPTY"])
        row.body:SetText(L["QUESTS_EMPTY_HINT"])
    end
end

local function Height(item, width)
    if item.kind == "quest" then return QUEST_H end
    if item.kind == "zone" then return ZONE_H end
    if item.kind == "target" then return TargetHeight(item, width) end
    if item.kind == "empty" then return 70 end
    if item.kind == "note" then return 14 + FG.RoutePanel.TextHeight(item.text, width - 20, "small") end
    return QUEST_H
end

-- ==== content ===============================================================

-- Prices a target once. The answer always arrives in a later frame: this runs
-- while the list is being built, which must not rebuild itself.
local function Settle(target)
    if target.settled or target.resolving or target.status ~= "ok" then return end
    target.resolving = true
    local mine = epoch
    Targets.Resolve(target, function()
        target.resolving = nil
        FG.After(0, function()
            if mine == epoch and f:IsVisible() then View.Refresh(true) end
        end)
    end, function() return mine == epoch end)
end

-- The rows under an open quest: what is left to do, and what is done.
local function AddTargets(items, q)
    local targets = resolved[q.questID]
    if not targets then
        targets = Targets.For(q)
        resolved[q.questID] = targets
    end
    if q.failed then return end
    if not q.complete then
        local anyPlace = false
        for i = 1, #q.objectives do
            local target = targets.objectives[i]
            if target then
                items[#items + 1] = { kind = "target", quest = q, target = target, objective = q.objectives[i] }
                if target.status == "ok" then anyPlace = true end
                Settle(target)
            end
        end
        if not anyPlace and targets.marker then
            items[#items + 1] = { kind = "target", quest = q, target = targets.marker }
            Settle(targets.marker)
        end
    end
    local turnIn = targets.turnIn
    if turnIn then
        items[#items + 1] = { kind = "target", quest = q, target = turnIn }
        Settle(turnIn)
    end
end

local function Items()
    local items = {}
    local quests = Quests.All()
    if #quests == 0 then
        items[1] = { kind = "empty" }
        return items
    end
    if not Targets.HasQuestie() then
        items[#items + 1] = { kind = "note", text = L["QUEST_NO_QUESTIE"] }
    end
    local zone
    for _, q in ipairs(quests) do
        if q.zone ~= zone then
            zone = q.zone
            if zone then items[#items + 1] = { kind = "zone", text = zone } end
        end
        items[#items + 1] = { kind = "quest", quest = q }
        if expanded[q.questID] then AddTargets(items, q) end
    end
    return items
end

function View.Refresh(keepPlace)
    if f and f:IsVisible() then list:SetItems(Items(), keepPlace) end
end

function View.Toggle(questID)
    expanded[questID] = not expanded[questID] or nil
    View.Refresh(true)
end

function View.Focus(questID)
    expanded[questID] = true
    View.Refresh(false)
    for i, item in ipairs(list.items) do
        if item.kind == "quest" and item.quest.questID == questID then list:Reveal(i) end
    end
end

-- Directions to an objective or the turn-in, at its closest area.
function View.Go(item)
    local target, q = item.target, item.quest
    if not target.best then return end
    Planner.Inspect(Targets.Destination(q, target, target.best))
    FG.Window.ShowRoute()
end

-- Directions to whatever this quest needs next: its turn-in once it is done, else
-- its first open objective with a place. A quest with neither opens instead, which
-- says why.
function View.GoNext(q)
    local target = Targets.FirstOpen(q, Targets.For(q))
    if not (target and target.status == "ok") then
        expanded[q.questID] = true
        return View.Refresh(true)
    end
    Targets.Resolve(target, function()
        if target.best then
            Planner.Inspect(Targets.Destination(q, target, target.best))
            FG.Window.ShowRoute()
        else
            expanded[q.questID] = true
            View.Refresh(true)
        end
    end)
end

local function Build(parent)
    f = CreateFrame("Frame", nil, parent)
    list = List.New(f, {
        make = { zone = MakeZone, quest = MakeQuest, target = MakeTarget, note = MakeNote, empty = MakeEmpty },
        bind = Bind, height = Height,
    })
    list:SetAllPoints(f)
    f.list = list
    FG.On("quests:changed", function()
        epoch = epoch + 1
        wipe(resolved)
        View.Refresh(true)
    end)
    return f
end

function View.Show() View.Refresh(false) end

function View.Get(parent) return f or Build(parent) end
