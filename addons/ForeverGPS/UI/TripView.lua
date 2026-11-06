-- Quest Circuit and trips on screen: the stops, in the order they will be visited,
-- with what moves them, and the buttons that find the best order and plan it.
local FG = ForeverGPS
local View = {}
FG.TripView = View

local Kit, Theme, List = FG.Kit, FG.Theme, FG.List
local Trip = FG.Trip
local L = FG.L

local STOP_H, FOOT_H, ROW_GAP = 50, 30, 6

local f, list
local working = false

local function MakeStop(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.back = Kit.Shape(row, 7, "BACKGROUND", 1)
    Theme.Paint(function(c) row.back:SetColor(c.card) end)
    row.number = Kit.Text(row, "label", "accent")
    row.number:SetPoint("LEFT", row, "LEFT", 12, 0)
    row.number:SetJustifyV("MIDDLE")
    row.remove = Kit.IconButton(row, "close", 9, L["TRIP_REMOVE"], function(self)
        Trip.Remove(self:GetParent().item.number)
    end)
    row.remove:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.down = Kit.IconButton(row, "chevron-down", 10, L["TRIP_DOWN"], function(self)
        local i = self:GetParent().item.number
        Trip.Move(i, i + 1)
    end)
    row.down:SetPoint("RIGHT", row.remove, "LEFT", 0, 0)
    row.up = Kit.IconButton(row, "chevron-up", 10, L["TRIP_UP"], function(self)
        local i = self:GetParent().item.number
        Trip.Move(i, i - 1)
    end)
    row.up:SetPoint("RIGHT", row.down, "LEFT", 0, 0)
    row.name = Kit.Text(row, "label", "text")
    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 34, -9)
    row.name:SetPoint("TOPRIGHT", row.up, "TOPLEFT", -4, -3)
    row.sub = Kit.Text(row, "small", "textDim")
    row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
    row.sub:SetPoint("TOPRIGHT", row.name, "BOTTOMRIGHT", 0, -3)
    return row
end

-- The space between two cards. A frame of its own: a child frame laid over a row
-- to leave a gap would paint over the row's text.
local function MakeGap(parent) return CreateFrame("Frame", nil, parent) end

local function MakeHint(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.title = Kit.Text(row, "label", "text", 0)
    row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -14)
    row.title:SetPoint("TOPRIGHT", row, "TOPRIGHT", -10, -14)
    row.title:SetText(L["TRIP_EMPTY"])
    row.body = Kit.Text(row, "small", "textDim", 0)
    row.body:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -4)
    row.body:SetPoint("TOPRIGHT", row.title, "BOTTOMRIGHT", 0, -4)
    row.body:SetText(L["TRIP_EMPTY_HINT"])
    return row
end

local function Bind(row, item)
    if item.kind ~= "stop" then return end
    local stop, count = item.stop, Trip.Count()
    row.number:SetText(item.number)
    row.name:SetText(stop.name or "?")
    row.sub:SetText(stop.subtitle or "")
    row.up:SetShown(item.number > 1)
    row.down:SetShown(item.number < count)
end

local HEIGHTS = { stop = STOP_H, gap = ROW_GAP, hint = 90 }

local function Height(item) return HEIGHTS[item.kind] end

local function Items()
    local items = {}
    for i, stop in ipairs(Trip.List()) do
        if i > 1 then items[#items + 1] = { kind = "gap" } end
        items[#items + 1] = { kind = "stop", stop = stop, number = i }
    end
    if #items == 0 then items[1] = { kind = "hint" } end
    return items
end

function View.Refresh()
    if not (f and f:IsVisible()) then return end
    list:SetItems(Items(), true)
    local count = Trip.Count()
    f.order:SetEnabled(count >= 2 and not working)
    f.plan:SetEnabled(count >= 1)
    f.clear:SetEnabled(count >= 1)
end

function View.Optimize()
    working = true
    f.order:SetLabel(L["TRIP_WORKING"])
    View.Refresh()
    Trip.Optimize(function(problem)
        working = false
        f.order:SetLabel(L["TRIP_OPTIMIZE"])
        if problem then FG.Print(problem) end
        View.Refresh()
    end)
end

local function Build(parent)
    f = CreateFrame("Frame", nil, parent)
    list = List.New(f, { make = { stop = MakeStop, gap = MakeGap, hint = MakeHint }, bind = Bind, height = Height })
    list:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    list:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, FOOT_H + 8)
    f.list = list
    f.plan = Kit.Button(f, { text = L["TRIP_PREVIEW"], variant = "primary", height = FOOT_H, onClick = function()
        Trip.Preview()
        FG.Window.ShowRoute()
    end })
    f.order = Kit.Button(f, { text = L["TRIP_OPTIMIZE"], height = FOOT_H, width = "fit", onClick = View.Optimize })
    Kit.Tooltip(f.order, L["TRIP_OPTIMIZE"], L["TRIP_OPTIMIZE_TT"])
    f.clear = Kit.Button(f, { text = L["TRIP_CLEAR"], height = FOOT_H, width = "fit", onClick = function() Trip.Clear() end })
    f.clear:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    f.order:SetPoint("LEFT", f.clear, "RIGHT", 6, 0)
    f.plan:SetPoint("BOTTOMLEFT", f.order, "BOTTOMRIGHT", 6, 0)
    f.plan:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    FG.On("trip:changed", View.Refresh)
    return f
end

function View.Show() View.Refresh() end

function View.Get(parent) return f or Build(parent) end
