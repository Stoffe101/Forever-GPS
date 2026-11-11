-- Find Quests: every quest Questie knows, whether it is in the log or not. By words, by
-- zone, by what this character can do now, and near where they stand. A row opens the
-- quest beside the list, or over it on a narrow window.
local FG = ForeverGPS
local View = {}
FG.ExplorerView = View

local Kit, Theme, Format, List = FG.Kit, FG.Theme, FG.Format, FG.List
local Browse, Index, QuestDB = FG.QuestBrowse, FG.QuestIndex, FG.QuestDB
local L = FG.L

local DEBOUNCE = 0.14
local ROW_H, SECTION_H, ZONE_H = 48, 26, 32
local FIELD_H = 34

local CHIPS = {
    { key = "available", label = "XF_AVAILABLE" }, { key = "soon", label = "XF_SOON" }, { key = "level", label = "XF_LEVEL" },
    { key = "chains", label = "XF_CHAINS" }, { key = "repeatable", label = "XF_REPEATABLE" },
    { key = "log", label = "XF_LOG" }, { key = "done", label = "XF_DONE" }, { key = "all", label = "XF_ALL" },
}

local f, list
local filter, zone, mode = "available", nil, "list"     -- mode: list, zones or near
local chosenZone = false     -- the player picked: stop following where they stand
local runToken = 0
local cursor = 0
local selected
local shown = {}             -- the last list asked for, for its notes

-- ==== rows ==================================================================

local function MakeResult(parent)
    local row = CreateFrame("Button", nil, parent)
    row:RegisterForClicks("LeftButtonUp")
    row.back = Kit.Shape(row, 7, "BACKGROUND", 1)
    row.back:SetShown(false)
    Theme.Paint(function(c) row.back:SetColor(c.cardHover) end)
    row.badge = CreateFrame("Frame", nil, row)
    row.badge:SetSize(28, 28)
    row.badge:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.badge.back = Kit.Shape(row.badge, 14, "BACKGROUND", 1)
    Theme.Paint(function(c) row.badge.back:SetColor(c.card) end)
    row.mark = Kit.Icon(row.badge, 14, "textDim")
    row.mark:SetPoint("CENTER", row.badge, "CENTER", 0, 0)
    row.level = Kit.Text(row, "label", "textDim")
    row.level:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    row.level:SetJustifyH("RIGHT")
    row.name = Kit.Text(row, "heading", "text")
    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 44, -8)
    row.name:SetPoint("TOPRIGHT", row, "TOPRIGHT", -48, -8)
    row.sub = Kit.Text(row, "small", "textDim")
    row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
    row.sub:SetPoint("TOPRIGHT", row.name, "BOTTOMRIGHT", 0, -2)
    row:SetScript("OnEnter", function(self) self.back:SetShown(true) end)
    row:SetScript("OnLeave", function(self) self.back:SetShown(self.index == cursor or self.item.row.id == selected) end)
    row:SetScript("OnClick", function(self) View.Open(self.item.row.id) end)
    return row
end

local function BindResult(row, item, index)
    local r, s = item.row, item.status
    row.item, row.index = item, index
    row.mark:SetIcon(s.icon)
    row.mark:SetColorKey(s.color)
    row.name:SetText(r.name)
    local parts = { s.word }
    if r.zone then parts[#parts + 1] = r.zone end
    if item.sec then parts[#parts + 1] = Format.About(item.sec)
    elseif item.yards then parts[#parts + 1] = Format.Yards(item.yards) end
    row.sub:SetText(table.concat(parts, " · "))
    row.level:SetText(r.level and r.level > 0 and r.level or "")
    row.back:SetShown(index == cursor or r.id == selected or row:IsMouseOver())
end

local function MakeCircuit(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.back = Kit.Shape(row, 7, "BACKGROUND", 1)
    Theme.Paint(function(c) row.back:SetColor(c.routeSoft) end)
    row.go = Kit.Button(row, { text = L["XF_PLAN_PICKUPS"], height = 24, width = "fit", onClick = function()
        View.PlanPickups()
    end })
    row.go:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.text = Kit.Text(row, "label", "text")
    row.text:SetPoint("LEFT", row, "LEFT", 10, 0)
    row.text:SetPoint("RIGHT", row.go, "LEFT", -8, 0)
    return row
end

local function MakeSection(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.label = Kit.Text(row, "caption", "textFaint")
    row.label:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 10, 6)
    row.label:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -10, 6)
    return row
end

local function MakeNote(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.title = Kit.Text(row, "label", "text", 0)
    row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -12)
    row.title:SetPoint("TOPRIGHT", row, "TOPRIGHT", -10, -12)
    row.body = Kit.Text(row, "small", "textDim", 0)
    row.body:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -4)
    row.body:SetPoint("TOPRIGHT", row.title, "BOTTOMRIGHT", 0, -4)
    return row
end

local function MakeZone(parent)
    local row = CreateFrame("Button", nil, parent)
    row:RegisterForClicks("LeftButtonUp")
    row.back = Kit.Shape(row, 7, "BACKGROUND", 1)
    row.back:SetShown(false)
    Theme.Paint(function(c) row.back:SetColor(c.cardHover) end)
    row.count = Kit.Text(row, "small", "textFaint")
    row.count:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    row.name = Kit.Text(row, "body", "text")
    row.name:SetPoint("LEFT", row, "LEFT", 10, 0)
    row.name:SetPoint("RIGHT", row.count, "LEFT", -8, 0)
    row:SetScript("OnEnter", function(self) self.back:SetShown(true) end)
    row:SetScript("OnLeave", function(self) self.back:SetShown(false) end)
    row:SetScript("OnClick", function(self) View.PickZone(self.item.zone) end)
    return row
end

local function Bind(row, item, index)
    if item.kind == "result" then BindResult(row, item, index)
    elseif item.kind == "section" then row.label:SetText(item.text)
    elseif item.kind == "circuit" then row.text:SetText(L["XF_PICKUPS_FMT"]:format(item.count))
    elseif item.kind == "zone" then
        row.item = item
        row.name:SetText(item.zone)
        row.count:SetText(item.count)
    elseif item.kind == "note" then
        row.title:SetText(item.title or "")
        row.body:SetText(item.body or "")
    end
end

local function Height(item, width)
    if item.kind == "result" then return ROW_H end
    if item.kind == "section" then return SECTION_H end
    if item.kind == "zone" then return ZONE_H end
    if item.kind == "circuit" then return 40 end
    local h = 24
    if item.title then h = h + FG.RoutePanel.TextHeight(item.title, width - 20, "label") end
    if item.body then h = h + 4 + FG.RoutePanel.TextHeight(item.body, width - 20, "small") end
    return h
end

-- ==== content ===============================================================

local function HereZone()
    return FG.Bridge.MapName(C_Map.GetBestMapForUnit("player"))
end

local function Heading()
    if mode == "near" then return L["XF_NEAR_TITLE"] end
    if zone then return zone end
    return L["XF_EVERYWHERE"]
end

local function ListItems(text)
    local items = {}
    shown = Browse.List({ text = text, zone = text == "" and zone or nil, filter = filter })
    if text == "" then items[1] = { kind = "section", text = Heading() } end
    for _, entry in ipairs(shown.items) do
        items[#items + 1] = { kind = "result", row = entry.row, status = entry.status }
    end
    if #shown.items == 0 then
        items[#items + 1] = { kind = "note", title = shown.partial and L["XF_CHECKING"] or L["XF_NONE"],
                              body = not shown.partial and L[text ~= "" and "XF_NONE_TEXT" or "XF_NONE_HINT"] or nil }
    elseif shown.capped then
        items[#items + 1] = { kind = "note", body = L["XF_CAPPED_FMT"]:format(#shown.items, shown.total) }
    end
    return items
end

local function NearItems()
    local items = { { kind = "section", text = L["XF_NEAR_TITLE"] } }
    if Browse.NearBusy() then
        items[#items + 1] = { kind = "note", title = L["XF_NEAR_BUSY"] }
        return items
    end
    for _, entry in ipairs(Browse.NearList()) do
        items[#items + 1] = { kind = "result", row = entry.row, status = entry.status, sec = entry.sec, yards = entry.yards }
    end
    if #items == 1 then
        items[2] = { kind = "note", title = L["XF_NEAR_NONE"], body = L["XF_NEAR_NONE_HINT"] }
    elseif #items > 2 then
        table.insert(items, 1, { kind = "circuit", count = #items - 1 })
    end
    return items
end

local function ZoneItems()
    local items = { { kind = "section", text = L["XF_PICK_ZONE"] } }
    for _, entry in ipairs(Index.Zones()) do
        items[#items + 1] = { kind = "zone", zone = entry.zone, count = entry.count }
    end
    return items
end

local function Items()
    if not QuestDB.Ready() then
        return { { kind = "note", title = L["XF_NO_QUESTIE"], body = L["XF_NO_QUESTIE_HINT"] } }
    end
    if not Index.Ready() then
        Index.Warm()
        return { { kind = "note", title = L["XF_READING_FMT"]:format(math.floor(Index.Progress() * 100)) } }
    end
    local text = strtrim(f.box:GetText())
    if text ~= "" then return ListItems(text) end
    if mode == "zones" then return ZoneItems() end
    if mode == "near" then return NearItems() end
    return ListItems("")
end

function View.Refresh(keepPlace)
    if not (f and f:IsVisible()) then return end
    cursor = 0
    list:SetItems(Items(), keepPlace)
    f.placeholder:SetShown(f.box:GetText() == "")
    f.zoneChip:SetLabel(zone or L["XF_ZONE"])
    f.zoneChip:SetSelected(mode == "zones" or zone ~= nil)
    f.nearChip:SetSelected(mode == "near")
    for _, chip in ipairs(f.chips) do
        if chip.key then chip:SetSelected(chip.key == filter and mode == "list") end
    end
end

local function Schedule()
    runToken = runToken + 1
    local token = runToken
    FG.After(DEBOUNCE, function()
        if token == runToken then View.Refresh(false) end
    end)
end

-- ==== doors =================================================================

function View.SetFilter(key)
    filter, mode = key, "list"
    if not Browse.Scanned() then Browse.Scan() end
    View.Refresh(false)
end

function View.PickZone(name)
    zone, mode, chosenZone = name, "list", true
    View.Refresh(false)
end

-- The list of zones; asked again with one picked, back to everywhere.
function View.ToggleZones()
    if zone and mode ~= "zones" then
        zone, chosenZone = nil, true
        return View.Refresh(false)
    end
    mode = mode == "zones" and "list" or "zones"
    View.Refresh(false)
end

function View.ShowNear()
    mode = "near"
    if not Browse.Near(function() View.Refresh(false) end) then
        FG.Print(L["ROUTE_UNKNOWN_POSITION"])
    end
    View.Refresh(false)
end

function View.PlanPickups()
    local ids = {}
    for _, entry in ipairs(Browse.NearList()) do ids[#ids + 1] = entry.row.id end
    return FG.Trip.PlanPickups(ids)
end

function View.Search(text)
    f.box:SetText(text or "")
    mode = "list"
    View.Refresh(false)
end

function View.Open(id)
    selected = id
    FG.Window.ShowQuest(id)
    list:Refresh()
end

function View.Selected() return selected end
function View.Mode() return mode end
function View.Zone() return zone end
function View.Filter() return filter end
function View.ItemsNow() return list.items end

local function Move(delta)
    local at = cursor
    for _ = 1, #list.items do
        at = at + delta
        if at < 1 then at = #list.items elseif at > #list.items then at = 1 end
        if list.items[at].kind == "result" then break end
    end
    if list.items[at] and list.items[at].kind == "result" then
        cursor = at
        list:Reveal(cursor)
        list:Refresh()
    end
end

local function Build(parent)
    f = CreateFrame("Frame", nil, parent)
    local field = CreateFrame("Frame", nil, f)
    field:SetHeight(FIELD_H)
    field:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    field:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    field.back = Kit.Shape(field, 8, "BACKGROUND", 1)
    field.edge = Kit.Shape(field, 8, "BACKGROUND", 2, true)
    field.glyph = Kit.Icon(field, 14, "textDim")
    field.glyph:SetIcon("search")
    field.glyph:SetPoint("LEFT", field, "LEFT", 11, 0)
    Theme.Paint(function(c)
        field.back:SetColor(c.field)
        field.edge:SetColor(c.lineStrong)
    end)
    f.box = CreateFrame("EditBox", "ForeverGPSExplorerBox", field)
    f.box:SetAutoFocus(false)
    if not f.box:SetFont(Theme.FONT.regular, 13, "") then f.box:SetFont(STANDARD_TEXT_FONT, 13, "") end
    f.box:SetTextColor(Theme.C.text[1], Theme.C.text[2], Theme.C.text[3], 1)
    f.box:SetPoint("LEFT", field, "LEFT", 33, 0)
    f.box:SetPoint("RIGHT", field, "RIGHT", -10, 0)
    f.box:SetHeight(24)
    f.box:SetMaxLetters(64)
    f.box:SetAltArrowKeyMode(false)
    f.placeholder = Kit.Text(field, "body", "textFaint")
    f.placeholder:SetPoint("LEFT", f.box, "LEFT", 0, 0)
    f.placeholder:SetPoint("RIGHT", f.box, "RIGHT", 0, 0)
    f.placeholder:SetText(L["XF_PLACEHOLDER"])
    f.box:SetScript("OnTextChanged", function(_, user)
        f.placeholder:SetShown(f.box:GetText() == "")
        if user then Schedule() end
    end)
    f.box:SetScript("OnEscapePressed", function(self)
        if self:GetText() ~= "" then
            self:SetText("")
            View.Refresh(false)
        else
            self:ClearFocus()
        end
    end)
    f.box:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        local item = list.items[cursor > 0 and cursor or 0]
        if not item then
            for _, candidate in ipairs(list.items) do
                if candidate.kind == "result" then
                    item = candidate
                    break
                end
            end
        end
        if item and item.kind == "result" then View.Open(item.row.id) end
    end)
    f.box:SetScript("OnArrowPressed", function(_, key)
        if key == "DOWN" then Move(1) elseif key == "UP" then Move(-1) end
    end)
    -- Done on the controller's keyboard: the search now, the selection on its first result.
    f.box.padAccept = function()
        runToken = runToken + 1
        View.Refresh(false)
        for _, row in ipairs(list.shown or {}) do
            if row.item and row.item.kind == "result" then return FG.Focus.To(row) end
        end
    end

    f.chips = {}
    f.nearChip = Kit.Chip(f, L["XF_NEAR"], function() View.ShowNear() end)
    Kit.Tooltip(f.nearChip, L["XF_NEAR_TT"])
    f.chips[1] = f.nearChip
    f.zoneChip = Kit.Chip(f, L["XF_ZONE"], function() View.ToggleZones() end)
    Kit.Tooltip(f.zoneChip, L["XF_ZONE_TT"])
    f.chips[2] = f.zoneChip
    for _, entry in ipairs(CHIPS) do
        local chip = Kit.Chip(f, L[entry.label], function(self) View.SetFilter(self.key) end)
        chip.key = entry.key
        f.chips[#f.chips + 1] = chip
    end

    list = List.New(f, {
        make = { result = MakeResult, section = MakeSection, note = MakeNote, zone = MakeZone, circuit = MakeCircuit },
        bind = Bind, height = Height,
    })
    f.list = list
    FG.On("questindex:ready", function() View.Refresh(false) end)
    FG.On("questscan:done", function() View.Refresh(true) end)
    FG.On("queststatus:changed", function()
        if f:IsVisible() then
            Browse.Scan()
            View.Refresh(true)
        end
    end)
    return f
end

function View.Layout()
    local width = f:GetWidth()
    local h = Kit.FlowChips(f.chips, f, width, 6, -(FIELD_H + 8))
    list:ClearAllPoints()
    list:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -(FIELD_H + 8) - h - 6)
    list:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
end

function View.Show()
    if not chosenZone and mode == "list" then
        local here = HereZone()
        zone = here and #Index.InZone(here) > 0 and here or nil
    end
    View.Layout()
    Index.Warm()
    Browse.Scan()
    View.Refresh(false)
end

function View.Get(parent) return f or Build(parent) end

-- For the controller: its box, for the search button (UI/MainWindow.lua).
function View.Box() return f and f.box end
