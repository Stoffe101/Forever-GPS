-- The search side: the box, the categories, and result cards. With nothing typed
-- it is a home screen: nearby services, the map pin, favorites and recents.
local FG = ForeverGPS
local View = {}
FG.SearchView = View

local Kit, Theme, Format, List = FG.Kit, FG.Theme, FG.Format, FG.List
local Bridge, Saved, Search = FG.Bridge, FG.Saved, FG.Search
local L = FG.L

local DEBOUNCE = 0.14
local CARD_H, SECTION_H, TILE_H = 54, 26, 40

local f, list
local filter = "all"
local runToken = 0
local results, info = {}, {}
local cursor = 0

-- ==== rows ==================================================================

local function MakeCard(parent)
    local row = CreateFrame("Button", nil, parent)
    row:RegisterForClicks("LeftButtonUp")
    row.back = Kit.Shape(row, 7, "BACKGROUND", 1)
    row.back:SetShown(false)
    Theme.Paint(function(c) row.back:SetColor(c.cardHover) end)
    row.icon = Kit.Icon(row, 28, "glyph")
    row.icon:SetPoint("LEFT", row, "LEFT", 10, 0)
    row.eta = Kit.Text(row, "label", "text")
    row.eta:SetPoint("TOPRIGHT", row, "TOPRIGHT", -10, -11)
    row.eta:SetJustifyH("RIGHT")
    row.via = Kit.Text(row, "small", "textFaint")
    row.via:SetPoint("TOPRIGHT", row.eta, "BOTTOMRIGHT", 0, -3)
    row.via:SetJustifyH("RIGHT")
    row.name = Kit.Text(row, "heading", "text")
    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 48, -10)
    row.sub = Kit.Text(row, "small", "textDim")
    row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
    row.sub:SetPoint("TOPRIGHT", row.name, "BOTTOMRIGHT", 0, -3)
    row:SetScript("OnEnter", function(self) self.back:SetShown(true) end)
    row:SetScript("OnLeave", function(self) self.back:SetShown(self.index == cursor) end)
    row:SetScript("OnClick", function(self) View.Open(self.item.result) end)
    return row
end

local function EtaLine(result)
    if result.quest then return nil, nil end
    if result.eta then
        return Format.About(result.eta.sec), result.eta.transports
    end
    if result.priced then return nil, L["NO_ROUTE_SHORT"] end
    return nil, nil
end

local function BindCard(row, item)
    local result = item.result
    row.icon:SetIcon(result.iconArt or result.icon or "pin")
    row.name:SetText(result.name)
    row.sub:SetText(result.subtitle or "")
    local eta, via = EtaLine(result)
    if result.note then via = result.note end
    row.eta:SetText(eta or "")
    row.via:SetText(via or "")
    row.via:SetColorKey(result.noteTone == "danger" and "danger" or "textFaint")
    -- The right column takes what it needs; the name fills the rest.
    local right = math.max(row.eta:GetStringWidth(), row.via:GetStringWidth())
    local room = right > 0 and right + 18 or 10
    row.name:SetPoint("TOPRIGHT", row, "TOPRIGHT", -room, -10)
    row.back:SetShown(item.index == cursor or row:IsMouseOver())
end

local function MakeSection(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.label = Kit.Text(row, "caption", "textFaint")
    row.label:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 10, 6)
    row.label:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -10, 6)
    return row
end

local function MakeHint(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.title = Kit.Text(row, "label", "text", 0)
    row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -12)
    row.title:SetPoint("TOPRIGHT", row, "TOPRIGHT", -10, -12)
    row.body = Kit.Text(row, "small", "textDim", 0)
    row.body:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -4)
    row.body:SetPoint("TOPRIGHT", row.title, "BOTTOMRIGHT", 0, -4)
    return row
end

-- A line of what might be useful now, from Core/Suggest.lua.
local function MakeSuggest(parent)
    local row = CreateFrame("Button", nil, parent)
    row:RegisterForClicks("LeftButtonUp")
    row.back = Kit.Shape(row, 6, "BACKGROUND", 1)
    row.back:SetShown(false)
    Theme.Paint(function(c) row.back:SetColor(c.cardHover) end)
    row.icon = Kit.Icon(row, 15, "accent")
    row.icon:SetPoint("LEFT", row, "LEFT", 12, 0)
    row.text = Kit.Text(row, "body", "text")
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 10, 0)
    row.text:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    row:SetScript("OnEnter", function(self) self.back:SetShown(true) end)
    row:SetScript("OnLeave", function(self) self.back:SetShown(false) end)
    row:SetScript("OnClick", function(self) self.item.line.run() end)
    return row
end

local function MakeTiles(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.tiles = {}
    for i = 1, 4 do
        local tile = CreateFrame("Button", nil, row)
        tile:RegisterForClicks("LeftButtonUp")
        tile.back = Kit.Shape(tile, 6, "BACKGROUND", 1)
        tile.icon = Kit.Icon(tile, 16, "accent")
        tile.icon:SetPoint("LEFT", tile, "LEFT", 9, 0)
        tile.label = Kit.Text(tile, "small", "text")
        tile.label:SetPoint("LEFT", tile.icon, "RIGHT", 7, 0)
        tile.label:SetPoint("RIGHT", tile, "RIGHT", -6, 0)
        Theme.Paint(function(c) tile.back:SetColor(c.card) end)
        tile:SetScript("OnEnter", function(self) self.back:SetColor(Theme.C.cardHover) end)
        tile:SetScript("OnLeave", function(self) self.back:SetColor(Theme.C.card) end)
        tile:SetScript("OnClick", function(self) View.Query(self.query) end)
        row.tiles[i] = tile
    end
    return row
end

local function BindTiles(row, item)
    local n = #item.tiles
    local gap, width = 6, row:GetWidth() - 12
    local w = (width - gap * (n - 1)) / n
    for i, tile in ipairs(row.tiles) do
        local entry = item.tiles[i]
        tile:SetShown(entry ~= nil)
        if entry then
            tile:ClearAllPoints()
            tile:SetPoint("TOPLEFT", row, "TOPLEFT", 6 + (i - 1) * (w + gap), -3)
            tile:SetSize(w, TILE_H - 6)
            tile.icon:SetIcon(entry.icon)
            tile.label:SetText(L[entry.label])
            tile.query = entry.query
        end
    end
end

local function Bind(row, item, index)
    item.index = index
    if item.kind == "card" then BindCard(row, item)
    elseif item.kind == "section" then row.label:SetText(item.text)
    elseif item.kind == "hint" then
        row.title:SetText(item.title or "")
        row.body:SetText(item.body or "")
    elseif item.kind == "tiles" then BindTiles(row, item)
    elseif item.kind == "suggest" then
        row.icon:SetIcon(item.line.icon)
        row.text:SetText(item.line.text)
        row.back:SetShown(row:IsMouseOver())
    end
end

local function Height(item, width)
    if item.kind == "card" then return CARD_H end
    if item.kind == "section" then return SECTION_H end
    if item.kind == "tiles" then return TILE_H end
    if item.kind == "suggest" then return 30 end
    if item.kind == "hint" then
        local h = 18
        if item.title then h = h + FG.RoutePanel.TextHeight(item.title, width - 20, "label") end
        if item.body then h = h + 4 + FG.RoutePanel.TextHeight(item.body, width - 20, "small") end
        return h
    end
    return CARD_H
end

-- ==== what the list shows ===================================================

local function SavedCards(items, heading, entries, most, skip)
    local shown = {}
    for _, entry in ipairs(entries) do
        if #shown >= (most or #entries) then break end
        if not (skip and skip[Saved.Key(entry.data)]) then shown[#shown + 1] = entry end
    end
    if #shown == 0 then return {} end
    items[#items + 1] = { kind = "section", text = heading }
    local keys = {}
    for _, entry in ipairs(shown) do
        keys[Saved.Key(entry.data)] = true
        items[#items + 1] = { kind = "card", result = { name = entry.name, subtitle = entry.subtitle, icon = entry.icon, data = entry.data } }
    end
    return keys
end

-- What is under way, or was stopped: the first thing to see on opening the window.
local function NowItems(items)
    local route = Bridge.ActiveRoute()
    if route then
        items[#items + 1] = { kind = "section", text = L["HOME_NOW"] }
        local left = Format.Duration(route.eta or route.total)
        items[#items + 1] = { kind = "card", result = { name = route.dest and route.dest.name or "?", iconArt = "nav-arrow", active = true,
            subtitle = left and L["HOME_NOW_LEFT_FMT"]:format(left) or L["ROUTE_ACTIVE"] } }
        return
    end
    local stopped = Saved.Resume()
    if stopped then
        items[#items + 1] = { kind = "section", text = L["HOME_RESUME"] }
        items[#items + 1] = { kind = "card", result = { name = stopped.name, iconArt = "nav-arrow", resume = true, subtitle = L["HOME_RESUME_SUB"] } }
    end
end

local function TileRows(items, tiles, width)
    local cols = width >= 400 and 4 or 2
    for i = 1, #tiles, cols do
        local row = {}
        for j = i, math.min(i + cols - 1, #tiles) do row[#row + 1] = tiles[j] end
        items[#items + 1] = { kind = "tiles", tiles = row }
    end
end

local function HomeItems()
    local items = {}
    NowItems(items)
    local lines = FG.Suggest.List()
    if #lines > 0 then
        items[#items + 1] = { kind = "section", text = L["HOME_SUGGEST"] }
        for _, line in ipairs(lines) do items[#items + 1] = { kind = "suggest", line = line } end
    end
    items[#items + 1] = { kind = "section", text = L["HOME_QUICK"] }
    TileRows(items, Search.QuickServices(), list:GetWidth())
    local pin = Search.MapPin()
    if pin then
        items[#items + 1] = { kind = "card", result = pin }
    end
    SavedCards(items, L["HOME_FAVORITES"], Saved.Favorites())
    local regular = SavedCards(items, L["HOME_REGULAR"], Saved.Regulars(), 3)
    SavedCards(items, L["HOME_RECENT"], Saved.Recents(), 6, regular)
    if #Saved.Recents() == 0 then items[#items + 1] = { kind = "hint", title = L["HOME_TIPS_TITLE"], body = L["HOME_TIPS"] } end
    items[#items + 1] = { kind = "hint", body = L["MAP_HINT"] }
    return items
end

local function SavedItems()
    local items = {}
    SavedCards(items, L["HOME_FAVORITES"], Saved.Favorites())
    SavedCards(items, L["HOME_RECENT"], Saved.Recents())
    if #items == 0 then items[1] = { kind = "hint", title = L["HOME_EMPTY"] } end
    return items
end

local function ResultItems()
    local items = {}
    if info.corrected then
        items[1] = { kind = "hint", body = L["SEARCH_CORRECTED_FMT"]:format(info.corrected) }
    end
    if info.unknown then
        items[#items + 1] = { kind = "hint", body = L["SEARCH_FLIGHT_UNKNOWN"] }
    end
    for i = 1, #results do
        items[#items + 1] = { kind = "card", result = results[i] }
    end
    if #results == 0 then
        local text = strtrim(f.box:GetText())
        items[1] = { kind = "hint", title = L[filter == "all" and "NO_RESULTS" or "FILTER_EMPTY"]:format(text), body = L["NO_RESULTS_HINT"] }
    end
    return items
end

local function ShowResults(keepPlace)
    list:SetItems(ResultItems(), keepPlace)
end

local function Run()
    cursor = 0
    local text = strtrim(f.box:GetText())
    Search.CancelPricing()
    f.placeholder:SetShown(text == "")
    f.clear:SetShown(text ~= "")
    if filter == "saved" then return list:SetItems(SavedItems()) end
    if text == "" and not Search.BROWSE[filter] then return list:SetItems(HomeItems()) end
    results, info = Search.Run(text, filter)
    ShowResults(false)
    Search.Price(results, info, function() ShowResults(true) end)
end

local function Schedule()
    runToken = runToken + 1
    local token = runToken
    FG.After(DEBOUNCE, function()
        if token == runToken and f:IsVisible() then Run() end
    end)
end

-- ==== acting on it ==========================================================

function View.Open(result)
    if result.explorer then
        FG.Window.Show("quests")
        FG.QuestsView.SetMode("find")
        return FG.ExplorerView.Open(result.explorer)
    end
    if result.active then return FG.Window.ShowRoute() end
    if result.resume then return FG.Resume() end
    if result.quest then
        FG.Window.Show("quests")
        FG.QuestsView.Focus(result.quest.questID)
        return
    end
    Search.Inspect(result)
    FG.Window.ShowRoute()
end

function View.Query(text)
    f.box:SetText(text)
    Run()
end

local function CardIndexes()
    local out = {}
    for i, item in ipairs(list.items) do
        if item.kind == "card" then out[#out + 1] = i end
    end
    return out
end

local function Move(delta)
    local cards = CardIndexes()
    if #cards == 0 then return end
    local at = 0
    for i = 1, #cards do
        if cards[i] == cursor then at = i end
    end
    at = math.max(1, math.min(#cards, at + delta))
    cursor = cards[at]
    list:Reveal(cursor)
end

-- ==== building ==============================================================

local function Build(parent)
    f = CreateFrame("Frame", nil, parent)

    local field = CreateFrame("Frame", nil, f)
    field:SetHeight(38)
    field:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    field:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    field.back = Kit.Shape(field, 8, "BACKGROUND", 1)
    field.edge = Kit.Shape(field, 8, "BACKGROUND", 2, true)
    field.glyph = Kit.Icon(field, 15, "textDim")
    field.glyph:SetIcon("search")
    field.glyph:SetPoint("LEFT", field, "LEFT", 12, 0)
    Theme.Paint(function(c)
        field.back:SetColor(c.field)
        field.edge:SetColor(c.lineStrong)
    end)

    f.box = CreateFrame("EditBox", "ForeverGPSSearchBox", field)
    f.box:SetAutoFocus(false)
    if not f.box:SetFont(Theme.FONT.regular, 13, "") then f.box:SetFont(STANDARD_TEXT_FONT, 13, "") end
    f.box:SetTextColor(Theme.C.text[1], Theme.C.text[2], Theme.C.text[3], 1)
    f.box:SetPoint("LEFT", field, "LEFT", 36, 0)
    f.box:SetPoint("RIGHT", field, "RIGHT", -32, 0)
    f.box:SetHeight(26)
    f.box:SetMaxLetters(64)
    f.box:SetAltArrowKeyMode(false)
    f.placeholder = Kit.Text(field, "body", "textFaint")
    f.placeholder:SetPoint("LEFT", f.box, "LEFT", 0, 0)
    f.placeholder:SetPoint("RIGHT", f.box, "RIGHT", 0, 0)
    f.placeholder:SetText(L["WHERE_TO"])
    f.clear = Kit.IconButton(field, "close", 10, nil, function()
        f.box:SetText("")
        f.box:SetFocus()
        Run()
    end)
    f.clear:SetPoint("RIGHT", field, "RIGHT", -6, 0)
    f.clear:Hide()

    f.box:SetScript("OnTextChanged", function(_, user)
        if user then Schedule() end
        f.placeholder:SetShown(f.box:GetText() == "")
    end)
    f.box:SetScript("OnEscapePressed", function(self)
        if self:GetText() ~= "" then
            self:SetText("")
            Run()
        else
            self:ClearFocus()
        end
    end)
    f.box:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        local cards = CardIndexes()
        local at = cursor > 0 and cursor or cards[1]
        local item = at and list.items[at]
        if item and item.result then View.Open(item.result) end
    end)
    f.box:SetScript("OnArrowPressed", function(_, key)
        if key == "DOWN" then Move(1) elseif key == "UP" then Move(-1) end
    end)

    f.chips = {}
    local function AddChip(key, label)
        local chip = Kit.Chip(f, L[label], function(self)
            filter = self.key
            for i = 1, #f.chips do f.chips[i]:SetSelected(f.chips[i].key == filter) end
            Run()
        end)
        chip.key = key
        chip:SetSelected(key == filter)
        f.chips[#f.chips + 1] = chip
    end
    for _, entry in ipairs(Search.FILTERS) do
        if entry.key ~= "quests" then AddChip(entry.key, entry.label) end
    end
    AddChip("saved", "CAT_SAVED")

    list = List.New(f, {
        make = { card = MakeCard, section = MakeSection, hint = MakeHint, tiles = MakeTiles, suggest = MakeSuggest },
        bind = Bind, height = Height,
    })
    f.list = list
    local function HomeChanged()
        if f:IsVisible() and strtrim(f.box:GetText()) == "" then Run() end
    end
    -- A search has done its job once the journey starts: the window next opens on that.
    FG.On("route:committed", function() f.box:SetText("") end)
    FG.On("saved:changed", HomeChanged)
    FG.On("targets:warm", HomeChanged)
    FG.On("route:cleared", HomeChanged)
    return f
end

function View.Layout()
    local width = f:GetWidth()
    local h = Kit.FlowChips(f.chips, f, width, 6, -46)
    list:ClearAllPoints()
    list:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -46 - h - 8)
    list:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
end

function View.Show()
    View.Layout()
    Bridge.WarmSearch()
    Run()
    f.box:SetFocus()
end

function View.Get(parent) return f or Build(parent) end

function View._Results() return results end    -- tests
