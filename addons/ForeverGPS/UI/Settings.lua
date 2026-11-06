-- The settings page: a single scroll of the choices that matter.
local _, FG = ...
local View = {}
FG.SettingsView = View

local Kit, Theme = FG.Kit, FG.Theme
local Bridge = FG.Bridge
local L = FG.L

local f

local function Heading(parent, text)
    local fs = Kit.Text(parent, "caption", "textFaint")
    fs:SetText(text)
    return fs
end

local function Build(parent)
    f = CreateFrame("Frame", nil, parent)
    f.back = Kit.Shape(f, 8, "BACKGROUND", 1)
    Theme.Paint(function(c) f.back:SetColor(c.raised) end)
    f.items = {}
    -- sizing: "fill" takes the column, "flow" lays itself out to it, "own" keeps its size.
    local function Add(widget, height, sizing)
        f.items[#f.items + 1] = { widget = widget, height = height, sizing = sizing or "fill" }
        return widget
    end
    local function HudChanged() FG.Emit("settings:changed") end

    Add(Heading(f, L["SET_ARROW"]), 16, "own")
    local choices = { { "hud", L["SET_ARROW_HUD"] }, { "character", L["SET_ARROW_CHARACTER"] } }
    if FG.TomTom.Available() then choices[#choices + 1] = { "tomtom", L["SET_ARROW_TOMTOM"] } end
    choices[#choices + 1] = { "off", L["SET_ARROW_OFF"] }
    f.arrow = Add(Kit.Choice(f, choices, function() return FG.db.arrow end, function(value)
        FG.db.arrow = value
        FG.Journey.ApplyArrow()
    end), 30, "flow")

    Add(Heading(f, L["SET_THEME"]), 16, "own")
    f.theme = Add(Kit.Choice(f, { { "obsidian", L["THEME_OBSIDIAN"] }, { "glacier", L["THEME_GLACIER"] }, { "parchment", L["THEME_PARCHMENT"] } },
        function() return FG.db.theme end, function(value)
            FG.db.theme = value
            Theme.Apply(value)
        end), 30, "flow")

    Add(Kit.Check(f, L["SET_HUD"], function() return FG.db.hud.enabled end, function(on)
        FG.db.hud.enabled = on
        HudChanged()
    end), 26)
    Add(Kit.Check(f, L["SET_HUD_NEXT"], function() return FG.db.hud.showNext end, function(on)
        FG.db.hud.showNext = on
        HudChanged()
    end), 26)
    Add(Kit.Check(f, L["SET_HUD_COMBAT"], function() return FG.db.hud.hideInCombat end, function(on)
        FG.db.hud.hideInCombat = on
        HudChanged()
    end), 26)
    Add(Kit.Check(f, L["SET_AUTOCLOSE"], function() return FG.db.autoClose end, function(on)
        FG.db.autoClose = on
    end), 26)
    Add(Kit.Check(f, L["SET_EASYFIND_BAR"], Bridge.EasyFindBar, Bridge.SetEasyFindBar), 30)

    Add(Heading(f, L["SET_HUD_SCALE"]), 16, "own")
    Add(Kit.Scale(f, 0.7, 1.5, 0.05, function() return FG.db.hud.scale end, function(value)
        FG.db.hud.scale = value
        HudChanged()
    end), 28)
    Add(Heading(f, L["SET_WINDOW_SCALE"]), 16, "own")
    Add(Kit.Scale(f, 0.7, 1.3, 0.05, function() return FG.db.window.scale end, function(value)
        FG.db.window.scale = value
        FG.Window.ApplyScale()
    end), 28)
    Add(Kit.Button(f, { text = L["SET_RESET"], height = 26, width = "fit", onClick = function()
        FG.Settings.ResetPlaces()
    end }), 34, "own")
    return f
end

-- Lays the page out; on a window too short for it, the rows wrap into two columns.
function View.Layout()
    local PAD = 16
    local width = f:GetWidth() - PAD * 2
    local height = f:GetHeight() - PAD * 2
    local total = 0
    for _, item in ipairs(f.items) do total = total + item.height end
    local columns = total > height and width > 440 and 2 or 1
    local gap = 20
    local colWidth = (width - gap * (columns - 1)) / columns
    local x, y, column = 0, 0, 1
    local limit = columns == 2 and (total + 40) / 2 or math.huge
    for _, item in ipairs(f.items) do
        if columns == 2 and y >= limit and column == 1 then
            x, y, column = colWidth + gap, 0, 2
        end
        local w = item.widget
        w:ClearAllPoints()
        w:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + x, -(PAD + y))
        local h = item.height
        if item.sizing == "flow" then
            w:SetWidth(colWidth)
            h = w:Layout(colWidth) + 10
        elseif item.sizing == "fill" then
            w:SetWidth(colWidth)
        end
        y = y + h
    end
    if f.arrow then f.arrow:Sync() end
    if f.theme then f.theme:Sync() end
end

function View.Get(parent) return f or Build(parent) end
