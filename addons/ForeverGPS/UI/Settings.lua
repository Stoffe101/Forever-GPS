-- The settings page: each group of choices on its own, with a rail to move between
-- them. Every control here changes something real, straight away; a setting nothing
-- reads does not get a control.
local _, FG = ...
local View = {}
FG.SettingsView = View

local Kit, Theme = FG.Kit, FG.Theme
local Bridge = FG.Bridge
local L = FG.L

local PAD = 14
local RAIL_W = 118           -- a rail of groups beside the page, on a wide enough window
local RAIL_AT = 520
local WHEEL = 48

local f
local current = 1

local function Percent(value) return ("%d%%"):format(math.floor(value * 100 + 0.5)) end

local function HudChanged() FG.Emit("settings:changed") end

local function ModeChoices()
    local out = {}
    for _, mode in ipairs(FG.Planner.MODES) do out[#out + 1] = { mode.key, L[mode.label] } end
    return out
end

local function ArrowChoices()
    local choices = { { "hud", L["SET_ARROW_HUD"] }, { "character", L["SET_ARROW_CHARACTER"] } }
    if FG.TomTom.Available() then choices[#choices + 1] = { "tomtom", L["SET_ARROW_TOMTOM"] } end
    choices[#choices + 1] = { "off", L["SET_ARROW_OFF"] }
    return choices
end

-- Each group adds its controls through ui: heading, check, choice, scale, button, note.
local GROUPS = {
    { label = "SETG_NAVIGATION", build = function(ui)
        ui.heading("SET_ARROW")
        ui.choice(ArrowChoices(), function() return FG.db.arrow end, function(value)
            FG.db.arrow = value
            FG.Journey.ApplyArrow()
        end)
        ui.heading("SET_DEFAULT_WAY")
        ui.choice(ModeChoices(), function() return FG.char.mode end, function(value) FG.char.mode = value end)
        ui.check("SET_AUTOCLOSE", function() return FG.db.autoClose end, function(on) FG.db.autoClose = on end)
    end },
    { label = "SETG_MAP", build = function(ui)
        ui.check("SET_MAP_PREVIEW", function() return FG.db.map.preview end, function(on)
            FG.db.map.preview = on
            FG.Emit("settings:changed")
        end)
        ui.check("SET_MAP_AREAS", function() return FG.db.map.areas end, function(on)
            FG.db.map.areas = on
            FG.Emit("settings:changed")
        end)
        ui.note("SET_MAP_NOTE")
    end },
    { label = "SETG_HUD", build = function(ui)
        ui.check("SET_HUD", function() return FG.db.hud.enabled end, function(on)
            FG.db.hud.enabled = on
            HudChanged()
        end)
        ui.heading("SET_HUD_MODE")
        ui.choice({ { "compact", L["HUD_MODE_COMPACT"] }, { "standard", L["HUD_MODE_STANDARD"] }, { "detailed", L["HUD_MODE_DETAILED"] } },
            function() return FG.db.hud.mode end, function(value)
                FG.db.hud.mode = value
                HudChanged()
            end)
        ui.check("SET_HUD_NEXT", function() return FG.db.hud.showNext end, function(on)
            FG.db.hud.showNext = on
            HudChanged()
        end)
        ui.check("SET_HUD_ETA", function() return FG.db.hud.showEta end, function(on)
            FG.db.hud.showEta = on
            HudChanged()
        end)
        ui.check("SET_HUD_COMBAT", function() return FG.db.hud.hideInCombat end, function(on)
            FG.db.hud.hideInCombat = on
            HudChanged()
        end)
        ui.check("SET_HUD_AUTOHIDE", function() return FG.db.hud.autoHide end, function(on)
            FG.db.hud.autoHide = on
            HudChanged()
        end)
        ui.check("SET_HUD_LOCK", function() return FG.db.hud.locked end, function(on)
            FG.db.hud.locked = on
            HudChanged()
        end)
        ui.heading("SET_HUD_SCALE")
        ui.scale(0.7, 1.5, 0.05, function() return FG.db.hud.scale end, function(value)
            FG.db.hud.scale = value
            HudChanged()
        end, Percent)
        ui.heading("SET_HUD_OPACITY")
        ui.scale(0.3, 1, 0.05, function() return FG.db.hud.opacity end, function(value)
            FG.db.hud.opacity = value
            HudChanged()
        end, Percent)
        ui.heading("SET_HUD_FONT")
        ui.choice({ { "small", L["SIZE_SMALL"] }, { "normal", L["SIZE_NORMAL"] }, { "large", L["SIZE_LARGE"] } },
            function() return FG.db.hud.font end, function(value)
                FG.db.hud.font = value
                HudChanged()
            end)
        ui.heading("SET_HUD_ARROW")
        ui.choice({ { "solid", L["ARROW_SOLID"] }, { "chevron", L["ARROW_CHEVRON"] } },
            function() return FG.db.hud.arrowStyle end, function(value)
                FG.db.hud.arrowStyle = value
                HudChanged()
            end)
    end },
    { label = "SETG_SEARCH", build = function(ui)
        ui.check("SET_SEARCH_PRICES", function() return FG.db.search.prices end, function(on) FG.db.search.prices = on end)
        ui.check("SET_SEARCH_WORLD", function() return FG.db.search.world end, function(on) FG.db.search.world = on end)
        ui.button("SET_CLEAR_RECENTS", function() FG.Saved.ClearRecents() end)
    end },
    { label = "SETG_QUESTS", build = function(ui)
        ui.check("SET_QUEST_NEXT", function() return FG.db.quests.offerNext end, function(on) FG.db.quests.offerNext = on end)
    end },
    { label = "SETG_APPEARANCE", build = function(ui)
        ui.heading("SET_THEME")
        ui.choice({ { "obsidian", L["THEME_OBSIDIAN"] }, { "glacier", L["THEME_GLACIER"] }, { "parchment", L["THEME_PARCHMENT"] } },
            function() return FG.db.theme end, function(value)
                FG.db.theme = value
                Theme.Apply(value)
            end)
        ui.heading("SET_WINDOW_SCALE")
        ui.scale(0.7, 1.3, 0.05, function() return FG.db.window.scale end, function(value)
            FG.db.window.scale = value
            FG.Window.ApplyScale()
        end, Percent)
        ui.check("SET_REDUCED_MOTION", function() return FG.db.reducedMotion end, function(on) FG.db.reducedMotion = on end)
    end },
    { label = "SETG_INTEGRATIONS", build = function(ui)
        ui.check("SET_MINIMAP", function() return FG.db.minimap.shown end, function(on)
            FG.db.minimap.shown = on
            FG.Emit("settings:changed")
        end)
        ui.check("SET_EASYFIND_BAR", Bridge.EasyFindBar, Bridge.SetEasyFindBar)
        ui.button("SET_RESTORE_EASYFIND", function() FG.Settings.RestoreEasyFind() end, "SET_RESTORE_EASYFIND_TT")
        ui.status(function()
            return L[FG.QuestTargets.HasQuestie() and "SET_QUESTIE_ON" or "SET_QUESTIE_OFF"]
        end)
        ui.status(function()
            return L[FG.TomTom.Available() and "SET_TOMTOM_ON" or "SET_TOMTOM_OFF"]
        end)
    end },
    { label = "SETG_ADVANCED", build = function(ui)
        ui.button("SET_RESET", function() FG.Settings.ResetPlaces() end)
        ui.button("SET_REPORT", function() FG.CopyBox.Show(FG.Diagnostics.Report()) end, "SET_REPORT_TT")
    end },
}

local function BuildGroup(group)
    local items = {}
    -- sizing: "fill" takes the column, "flow" lays itself out to it, "own" keeps its size.
    local function Add(widget, height, sizing, extra)
        local item = { widget = widget, height = height, sizing = sizing or "fill" }
        for k, v in pairs(extra or {}) do item[k] = v end
        items[#items + 1] = item
        widget:Hide()
        return widget
    end
    local content = f.content
    local ui = {}
    function ui.heading(key)
        local fs = Kit.Text(content, "caption", "textFaint")
        fs:SetText(L[key])
        Add(fs, 18, "own")
    end
    function ui.check(key, get, set) Add(Kit.Check(content, L[key], get, set), 26) end
    function ui.choice(choices, get, set) Add(Kit.Choice(content, choices, get, set), 30, "flow") end
    function ui.scale(low, high, step, get, set, shown) Add(Kit.Scale(content, low, high, step, get, set, shown), 28) end
    function ui.button(key, fn, tip)
        local b = Kit.Button(content, { text = L[key], height = 26, width = "fit", onClick = fn })
        if tip then Kit.Tooltip(b, L[key], L[tip]) end
        Add(b, 34, "own")
    end
    function ui.note(key)
        local fs = Kit.Text(content, "small", "textDim", 0)
        fs:SetText(L[key])
        Add(fs, 34)
    end
    function ui.status(read)
        local fs = Kit.Text(content, "small", "textDim")
        Add(fs, 20, nil, { read = read })
    end
    group.build(ui)
    group.items = items
end

local function PlaceRail(width)
    local rail = width >= RAIL_AT
    if rail then
        for i, chip in ipairs(f.rail) do
            chip:SetWidth(RAIL_W - 8)
            chip:ClearAllPoints()
            chip:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -8 - (i - 1) * 30)
        end
        f.content:ClearAllPoints()
        f.content:SetPoint("TOPLEFT", f, "TOPLEFT", RAIL_W + 4, -8)
        f.content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)
    else
        for _, chip in ipairs(f.rail) do chip:SetLabel(chip.text) end
        local h = Kit.FlowChips(f.rail, f, width - 16, 4, 0)
        for _, chip in ipairs(f.rail) do
            local _, rel, _, x, y = chip:GetPoint(1)
            chip:ClearAllPoints()
            chip:SetPoint("TOPLEFT", rel, "TOPLEFT", x + 8, y - 8)
        end
        f.content:ClearAllPoints()
        f.content:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -8 - h - 6)
        f.content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)
    end
end

-- Places the group's controls at the current scroll; the clip hides what is past it.
local function PlaceItems()
    local group = GROUPS[current]
    local width = f.content:GetWidth() - PAD * 2
    local y = 0
    for _, item in ipairs(group.items) do
        local w = item.widget
        w:Show()
        if item.read then w:SetText(item.read()) end
        w:ClearAllPoints()
        w:SetPoint("TOPLEFT", f.content, "TOPLEFT", PAD, f.scroll - PAD - y)
        local h = item.height
        if item.sizing == "flow" then
            w:SetWidth(width)
            h = w:Layout(width) + 10
            w:Sync()
        elseif item.sizing == "fill" then
            w:SetWidth(width)
            if item.widget.Sync then item.widget:Sync() end
        end
        item.top, item.h = y, h
        y = y + h
    end
    f.total = y + PAD * 2
    local room = f.content:GetHeight()
    local scrollable = f.total > room
    f.thumb:SetShown(scrollable)
    if scrollable then
        local h = math.max(24, room * room / f.total)
        f.thumb:ClearAllPoints()
        f.thumb:SetHeight(h)
        f.thumb:SetPoint("TOPRIGHT", f.content, "TOPRIGHT", -1, -(f.scroll / (f.total - room)) * (room - h))
    end
end

local function Clamp()
    f.scroll = math.max(0, math.min(math.max(0, (f.total or 0) - f.content:GetHeight()), f.scroll))
end

function View.Select(index)
    for _, item in ipairs(GROUPS[current].items or {}) do item.widget:Hide() end
    current = index
    if not GROUPS[index].items then BuildGroup(GROUPS[index]) end
    for i, chip in ipairs(f.rail) do chip:SetSelected(i == index) end
    f.scroll = 0
    PlaceItems()
end

-- Brings one control of the open group on screen.
function View.Reveal(item)
    local room = f.content:GetHeight()
    if item.top < f.scroll then
        f.scroll = item.top
    elseif item.top + item.h + PAD * 2 > f.scroll + room then
        f.scroll = item.top + item.h + PAD * 2 - room
    end
    Clamp()
    PlaceItems()
end

function View.Groups() return GROUPS end

local function Build(parent)
    f = CreateFrame("Frame", nil, parent)
    f.back = Kit.Shape(f, 8, "BACKGROUND", 1)
    Theme.Paint(function(c) f.back:SetColor(c.raised) end)
    f.scroll, f.total = 0, 0
    f.rail = {}
    for i, group in ipairs(GROUPS) do
        local chip = Kit.Chip(f, L[group.label], function() View.Select(i) end)
        chip.text = L[group.label]
        f.rail[i] = chip
    end
    f.content = CreateFrame("Frame", nil, f)
    f.content:SetClipsChildren(true)
    f.content:EnableMouseWheel(true)
    f.content:SetScript("OnMouseWheel", function(_, delta)
        f.scroll = f.scroll - delta * WHEEL
        Clamp()
        PlaceItems()
    end)
    f.thumb = CreateFrame("Frame", nil, f.content)
    f.thumb:SetWidth(4)
    f.thumb.back = Kit.Shape(f.thumb, 2, "OVERLAY", 1)
    Theme.Paint(function(c) f.thumb.back:SetColor(c.lineStrong) end)
    f.thumb:Hide()
    BuildGroup(GROUPS[current])
    return f
end

function View.Layout()
    PlaceRail(f:GetWidth())
    for i, chip in ipairs(f.rail) do chip:SetSelected(i == current) end
    PlaceItems()
    Clamp()
    PlaceItems()
end

function View.Get(parent) return f or Build(parent) end
