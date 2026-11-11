-- A scrolling list that only ever builds the rows that fit. Items may differ in
-- height and in kind; rows are reused by kind. Thirty search results or a full
-- quest log cost a handful of frames.
local FG = ForeverGPS
local List = {}
FG.List = List

local Kit, Theme = FG.Kit, FG.Theme

local WHEEL_STEP = 56
local THUMB_MIN = 24

-- opts.make[kind](parent) builds a row; opts.bind(row, item, index) fills it.
-- opts.height(item, width) gives an item's height.
function List.New(parent, opts)
    local list = CreateFrame("Frame", nil, parent)
    list:SetClipsChildren(true)
    list.padList = true       -- moved through by its items (UI/Focus.lua)
    list:EnableMouseWheel(true)
    list.items, list.offset, list.total = {}, 0, 0
    list.tops, list.heights = {}, {}
    list.pool, list.shown = {}, {}

    local thumb = CreateFrame("Frame", nil, list)
    thumb:SetWidth(4)
    thumb:SetFrameLevel(list:GetFrameLevel() + 20)
    thumb.back = Kit.Shape(thumb, 2, "OVERLAY", 1)
    Theme.Paint(function(c) thumb.back:SetColor(c.lineStrong) end)
    thumb:Hide()
    list.thumb = thumb

    local function Acquire(kind)
        local pool = list.pool[kind]
        if not pool then
            pool = {}
            list.pool[kind] = pool
        end
        local row = table.remove(pool)
        if not row then
            row = opts.make[kind](list)
            row.kind = kind
        end
        row:Show()
        return row
    end

    local function ReleaseAll()
        for i = #list.shown, 1, -1 do
            local row = list.shown[i]
            row:Hide()
            local pool = list.pool[row.kind]
            pool[#pool + 1] = row
            list.shown[i] = nil
        end
    end

    function list:Width()
        return self:GetWidth() - (self.total > self:GetHeight() and 8 or 0)
    end

    -- Rows are measured at the width they are drawn at. With a scrollbar they draw 8
    -- narrower, so a list that scrolls is measured again at that width: text measured
    -- wider than it is drawn takes a line more than its row has, and runs into the next.
    local function MeasureAt(self, width)
        local y = 0
        for i = 1, #self.items do
            local h = opts.height(self.items[i], width)
            self.tops[i], self.heights[i] = y, h
            y = y + h
        end
        for i = #self.items + 1, #self.tops do self.tops[i], self.heights[i] = nil, nil end
        self.total = y
    end

    function list:Measure()
        local width = self:GetWidth()
        MeasureAt(self, width)
        -- Narrower is never shorter, so it still scrolls and draws at that width.
        if self.total > self:GetHeight() then MeasureAt(self, width - 8) end
    end

    function list:Render()
        ReleaseAll()
        local height, width = self:GetHeight(), self:Width()
        if height <= 0 or width <= 0 then return end
        for i = 1, #self.items do
            local top = self.tops[i]
            local h = self.heights[i]
            if top + h > self.offset and top < self.offset + height then
                local item = self.items[i]
                local row = Acquire(item.kind or "row")
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", self, "TOPLEFT", 0, self.offset - top)
                row:SetWidth(width)
                row:SetHeight(h)
                row.item, row.index = item, i
                opts.bind(row, item, i)
                self.shown[#self.shown + 1] = row
            end
        end
        local scrollable = self.total > height
        FG.Emit("list:rendered", self)
        thumb:SetShown(scrollable)
        if scrollable then
            local h = math.max(THUMB_MIN, height * height / self.total)
            local room = height - h
            thumb:ClearAllPoints()
            thumb:SetHeight(h)
            thumb:SetPoint("TOPRIGHT", self, "TOPRIGHT", -1, -(self.offset / (self.total - height)) * room)
        end
    end

    function list:Clamp()
        local most = math.max(0, self.total - self:GetHeight())
        self.offset = math.max(0, math.min(most, self.offset))
    end

    -- keepPlace: an update of what is on screen, not a new list.
    function list:SetItems(items, keepPlace)
        self.items = items
        self:Measure()
        if not keepPlace then self.offset = 0 end
        self:Clamp()
        self:Render()
    end

    function list:Refresh()
        self:Measure()
        self:Clamp()
        self:Render()
    end

    -- Brings item i on screen.
    function list:Reveal(i)
        local top, h = self.tops[i], self.heights[i]
        if not top then return end
        local height = self:GetHeight()
        if top < self.offset then self.offset = top
        elseif top + h > self.offset + height then self.offset = top + h - height end
        self:Clamp()
        self:Render()
    end

    list:SetScript("OnMouseWheel", function(self, delta)
        self.offset = self.offset - delta * WHEEL_STEP
        self:Clamp()
        self:Render()
    end)
    list:SetScript("OnSizeChanged", function(self) self:Refresh() end)
    return list
end
