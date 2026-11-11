-- Settings, Controller: the layout, the profile, and every action's button, changed by
-- pressing the new one. All of it works with the controller itself: a binding is changed
-- with the buttons it is about, and there is always a way back (Undo, Reset, /fgps).
local FG = ForeverGPS
local PadSettings = {}
FG.PadSettings = PadSettings

local Kit, Theme = FG.Kit, FG.Theme
local L = FG.L

local function Pad() return FG.Pad end

-- ==== the dialog ============================================================
-- One frame over the window for every question: press a button, a clash, a native
-- conflict. Its buttons are focused like the window's; back is Cancel.

local dialog, surface

local function Dialog()
    if dialog then return dialog end
    dialog = CreateFrame("Frame", "ForeverGPSPadDialog", UIParent)
    dialog:SetFrameStrata("DIALOG")
    dialog:SetToplevel(true)
    dialog:EnableMouse(true)
    dialog:SetSize(380, 150)
    dialog:Hide()
    dialog.back = Kit.Shape(dialog, 10, "BACKGROUND", 0)
    dialog.edge = Kit.Shape(dialog, 10, "BACKGROUND", 7, true)
    Theme.Paint(function(c)
        dialog.back:SetColor(c.window)
        dialog.edge:SetColor(c.accent)
    end)
    dialog.title = Kit.Text(dialog, "heading", "text", 2)
    dialog.title:SetPoint("TOPLEFT", dialog, "TOPLEFT", 14, -12)
    dialog.title:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -14, -12)
    dialog.body = Kit.Text(dialog, "small", "textDim", 0)
    dialog.body:SetPoint("TOPLEFT", dialog.title, "BOTTOMLEFT", 0, -6)
    dialog.body:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -14, -40)
    dialog.buttons = {}
    for i = 1, 4 do
        local b = Kit.Button(dialog, { text = "", height = 26, width = "fit", onClick = function(self)
            if self.run then self.run() end
        end })
        dialog.buttons[i] = b
    end
    return dialog
end

local function CloseDialog()
    if not dialog then return end
    dialog:Hide()
    if surface then
        local s = surface
        surface = nil
        FG.Focus.Pop(s)
    end
    if dialog.ticker then dialog.ticker:Cancel() end
end

-- Asks: title, body, and up to four { label, run } choices. The last is Cancel.
local function Ask(title, body, choices)
    local d = Dialog()
    d.title:SetText(title)
    d.body:SetText(body or "")
    local x = -14
    local need = 28
    for i = 1, #choices do
        d.buttons[i]:SetLabel(choices[i][1])
        need = need + d.buttons[i]:GetWidth() + 8
    end
    d:SetWidth(math.max(380, need))
    for i = 4, 1, -1 do
        local b = d.buttons[i]
        local choice = choices[i]
        b:SetShown(choice ~= nil)
        if choice then
            b:SetLabel(choice[1])
            b.run = function()
                CloseDialog()
                if choice[2] then choice[2]() end
            end
            b:ClearAllPoints()
            b:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", x, 12)
            x = x - b:GetWidth() - 8
        end
    end
    d:ClearAllPoints()
    d:SetPoint("CENTER", FG.Window.Frame() or UIParent, "CENTER", 0, 0)
    d.choices = choices
    d:Show()
    d:Raise()
    if not surface then
        surface = { root = d, onBack = function()
            local last = d.choices[#d.choices]
            CloseDialog()
            if last and last[2] then last[2]() end
        end }
        surface.first = function()
            for i = 1, 4 do if d.buttons[i]:IsShown() then return d.buttons[i] end end
        end
        FG.Focus.Push(surface)
    else
        FG.Focus.First()
    end
end
PadSettings._Ask = Ask
function PadSettings.DialogShown() return dialog ~= nil and dialog:IsShown() end

-- The question on screen answered with its last choice (Cancel), as Back does.
function PadSettings.Dismiss()
    if not (dialog and dialog:IsShown()) then return false end
    local last = dialog.choices and dialog.choices[#dialog.choices]
    CloseDialog()
    if last and last[2] then last[2]() end
    return true
end
function PadSettings.DialogButtons() return dialog and dialog.buttons or {} end

local function ActionName(id) return L[Pad().BY_ID[id].key] end

-- After a press: the game's own use (for the button that works everywhere), a clash with
-- another action, or simply saved.
--
-- The open-from-anywhere button, when the game uses it, is asked about first: nothing is
-- saved or bound until the player chooses. "world" is consent to take it while playing,
-- "window" is only to close the window, "free" a button the game does nothing with.
local function Settle(id, chord, use)
    local P = Pad()
    if id == "toggle" and not use then
        local _, gameName = P.GameAction(chord)
        if gameName then
            return Ask(L["PAD_NATIVE_TITLE_FMT"]:format(P.Label(chord)), L["PAD_NATIVE_BODY_FMT"]:format(gameName), {
                { L["PAD_NATIVE_USE"], function() Settle(id, chord, "world") end },
                { L["PAD_NATIVE_WINDOW_ONLY"], function() Settle(id, chord, "window") end },
                { L["PAD_CHOOSE_ANOTHER"], function() PadSettings.Change(id) end },
                { L["PAD_CANCEL"] },
            })
        end
        use = "free"
    end
    -- Once the button is saved: the consent, for this button only.
    local function Saved()
        if id ~= "toggle" then return end
        P.SetWorldConsent(use ~= "window")
    end
    local ok, why, other = P.Set(id, chord)
    if ok then return Saved() end
    if why == "clash" then
        local function Resolve(how)
            local done, err = P.Set(id, chord, how)
            if done then return Saved() end
            if err == "essential" then Ask(L["PAD_ESSENTIAL_TITLE"], L["PAD_ESSENTIAL_BODY"], { { L["PAD_OK"] } }) end
        end
        return Ask(L["PAD_CLASH_TITLE_FMT"]:format(P.Label(chord)), L["PAD_CLASH_BODY_FMT"]:format(ActionName(other), ActionName(id)), {
            { L["PAD_SWAP"], function() Resolve("swap") end },
            { L["PAD_REPLACE"], function() Resolve("replace") end },
            { L["PAD_CANCEL"] },
        })
    end
    if why == "essential" then
        Ask(L["PAD_ESSENTIAL_TITLE"], L["PAD_ESSENTIAL_BODY"], { { L["PAD_OK"] } })
    end
end

-- Change: waits for a press, then settles it. Never in combat (the pad cannot be heard
-- then without protected calls): it says so instead.
function PadSettings.Change(id)
    local P = Pad()
    if InCombatLockdown() then
        return Ask(L["PAD_COMBAT_TITLE"], L["PAD_COMBAT_BODY"], { { L["PAD_OK"] } })
    end
    local d = Dialog()
    local left = 10
    Ask(L["PAD_PRESS_TITLE_FMT"]:format(ActionName(id)),
        L["PAD_PRESS_BODY_FMT"]:format(P.Label(P.Binding("back")), left), { { L["PAD_CANCEL"], function() P.StopLearning() end } })
    d.ticker = C_Timer.NewTicker(1, function()
        left = left - 1
        if left >= 0 and d:IsShown() then
            d.body:SetText(L["PAD_PRESS_BODY_FMT"]:format(P.Label(P.Binding("back")), left))
        end
    end, 10)
    P.Learn(id, function(chord, why)
        CloseDialog()
        if why == "combat" then return Ask(L["PAD_COMBAT_TITLE"], L["PAD_COMBAT_BODY"], { { L["PAD_OK"] } }) end
        if chord then Settle(id, chord) end
    end, 10)
end

-- ==== the rows ==============================================================

-- One action: its name, its button (with the game's glyph), Change and Reset.
local function BindingRow(parent, id)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(30)
    row.name = Kit.Text(row, "body", "text")
    row.name:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.name:SetText(ActionName(id))
    row.reset = Kit.Button(row, { text = L["PAD_RESET_ONE"], height = 24, width = "fit", onClick = function()
        local ok, why = Pad().Reset(id)
        if not ok and why == "clash" then PadSettings.Change(id) end
    end })
    row.reset:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.change = Kit.Button(row, { text = L["PAD_CHANGE"], height = 24, width = "fit", onClick = function() PadSettings.Change(id) end })
    row.change:SetPoint("RIGHT", row.reset, "LEFT", -6, 0)
    row.glyph = Kit.Text(row, "label", "accent")
    row.glyph:SetPoint("RIGHT", row.change, "LEFT", -10, 0)
    row.glyph:SetJustifyH("RIGHT")
    row.name:SetPoint("RIGHT", row.glyph, "LEFT", -8, 0)
    function row:Sync()
        local chord = Pad().Binding(id)
        row.glyph:SetText(Pad().Label(chord))
    end
    row:Sync()
    row.action = id
    return row
end

-- The profiles: one chip each (the one in use selected), then what can be done with them.
local function ProfileWidget(parent)
    local w = CreateFrame("Frame", nil, parent)
    w.chips = {}
    w.tools = {}
    local function Tool(key, fn)
        local b = Kit.Button(w, { text = L[key], height = 24, width = "fit", onClick = fn })
        w.tools[#w.tools + 1] = b
        return b
    end
    Tool("PAD_NEW", function()
        local P = Pad()
        Ask(L["PAD_NEW_TITLE"], L["PAD_NEW_BODY"], {
            { L["PAD_PRESET_DECK"], function() P.NewProfile("deck") end },
            { L["PAD_PRESET_XBOX"], function() P.NewProfile("xbox") end },
            { L["PAD_CANCEL"] },
        })
    end)
    Tool("PAD_DUPLICATE", function() Pad().Duplicate() end)
    Tool("PAD_RENAME", function() PadSettings.Rename() end)
    Tool("PAD_DELETE", function()
        local P = Pad()
        local name = P.ProfileName()
        Ask(L["PAD_DELETE_TITLE_FMT"]:format(name), L["PAD_DELETE_BODY"], {
            { L["PAD_DELETE"], function()
                if not P.Delete(name) then Ask(L["PAD_LAST_TITLE"], L["PAD_LAST_BODY"], { { L["PAD_OK"] } }) end
            end },
            { L["PAD_CANCEL"] },
        })
    end)
    function w:Sync()
        local names = Pad().Profiles()
        for _, c in ipairs(w.chips) do c:Hide() end
        for i, name in ipairs(names) do
            local chip = w.chips[i]
            if not chip then
                chip = Kit.Chip(w, "", function(picked) Pad().Use(picked.profile) end)
                w.chips[i] = chip
            end
            chip.profile = name
            chip:SetLabel(name)
            chip:SetSelected(name == Pad().ProfileName())
            chip:Show()
        end
    end
    function w:Layout(width)
        local shown = {}
        for _, c in ipairs(w.chips) do if c:IsShown() then shown[#shown + 1] = c end end
        local h = Kit.FlowChips(shown, w, width, 6, 0)
        local h2 = Kit.FlowChips(w.tools, w, width, 6, -(h + 8))
        w:SetHeight(h + 8 + h2)
        return h + 8 + h2
    end
    w:Sync()
    return w
end

-- A name typed for the profile in use, with the on-screen keyboard when the pad is used.
function PadSettings.Rename()
    local P = Pad()
    local box = PadSettings.NameBox()
    box:SetText(P.ProfileName())
    box.padAccept = function(self)
        local new = self:GetText()
        if not P.Rename(P.ProfileName(), new) then
            Ask(L["PAD_RENAME_FAIL_TITLE"], L["PAD_RENAME_FAIL_BODY"], { { L["PAD_OK"] } })
        end
    end
    if P.InUse() and FG.PadKeyboard then
        FG.PadKeyboard.Open(box)
    else
        box:Show()
        box:SetFocus()
    end
end

local nameBox
function PadSettings.NameBox()
    if nameBox then return nameBox end
    nameBox = CreateFrame("EditBox", "ForeverGPSPadNameBox", UIParent)
    nameBox:SetAutoFocus(false)
    nameBox:SetMaxLetters(32)
    nameBox:SetSize(200, 24)
    nameBox:SetPoint("CENTER")
    nameBox:SetFrameStrata("DIALOG")
    if not nameBox:SetFont(Theme.FONT.regular, 13, "") then nameBox:SetFont(STANDARD_TEXT_FONT, 13, "") end
    nameBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        self:Hide()
        if self.padAccept then self.padAccept(self) end
    end)
    nameBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        self:Hide()
    end)
    nameBox:Hide()
    return nameBox
end

-- ==== the group =============================================================

local LAYOUTS = { { "auto", "PAD_LAYOUT_AUTO" }, { "desktop", "PAD_LAYOUT_DESKTOP" }, { "handheld", "PAD_LAYOUT_HANDHELD" } }
local INPUTS = { { "auto", "PAD_INPUT_AUTO" }, { "pad", "PAD_INPUT_PAD" }, { "mouse", "PAD_INPUT_MOUSE" } }
local HIGHLIGHTS = { { "strong", "PAD_HL_STRONG" }, { "subtle", "PAD_HL_SUBTLE" }, { "off", "PAD_HL_OFF" } }
local SPOTS = { { "top", "PAD_SPOT_TOP" }, { "topleft", "PAD_SPOT_TOPLEFT" }, { "topright", "PAD_SPOT_TOPRIGHT" },
                { "bottom", "PAD_SPOT_BOTTOM" } }

local function Choices(list)
    local out = {}
    for _, c in ipairs(list) do out[#out + 1] = { c[1], L[c[2]] } end
    return out
end

function PadSettings.Build(ui)
    local P = Pad()
    ui.heading("PAD_H_LAYOUT")
    ui.choice(Choices(LAYOUTS), function() return P.Settings().mode end, function(value)
        P.Settings().mode = value
        P.Apply()
        FG.Emit("pad:layout")
    end)
    ui.heading("PAD_H_INPUT")
    ui.choice(Choices(INPUTS), function() return P.Settings().input end, function(value)
        P.Settings().input = value
        FG.Emit("pad:input", P.InUse())
    end)
    ui.heading("PAD_H_PROFILE")
    ui.custom(ProfileWidget, 70, "flow")
    ui.check("PAD_FOR_CHARACTER", function() return FG.char and FG.char.padProfile ~= nil end, function(on)
        P.Use(P.ProfileName(), on)
    end)
    ui.heading("PAD_H_OPEN")
    ui.custom(function(parent) return BindingRow(parent, "toggle") end, 30, "fill")
    ui.check("PAD_WORLD_CONSENT", function() return P.WorldConsented() end, function(on) P.SetWorldConsent(on) end)
    ui.status(function()
        local chord = P.Binding("toggle")
        if not chord then return L["PAD_WORLD_NONE"] end
        -- Both values: "chord and f()" would keep only the first.
        local _, game = P.GameAction(chord)
        if game then return L["PAD_WORLD_GAME_FMT"]:format(game) end
        return L["PAD_WORLD_FREE"]
    end)
    ui.heading("PAD_H_CONTROLS")
    ui.note("PAD_CONTROLS_NOTE")
    ui.note("PAD_MOD_NOTE")
    for _, a in ipairs(P.ACTIONS) do
        if a.ctx ~= "world" then ui.custom(function(parent) return BindingRow(parent, a.id) end, 30, "fill") end
    end
    ui.button("PAD_UNDO", function() if not P.Undo() then Ask(L["PAD_NOTHING_UNDO"], "", { { L["PAD_OK"] } }) end end)
    ui.heading("PAD_H_RESET")
    ui.choice((function()
        local out = {}
        for _, p in ipairs(P.PRESETS) do out[#out + 1] = { p.id, L[p.key] } end
        return out
    end)(), function() return ((P.Profile().preset or ""):match("^(%a+)")) end, function(value)
        Ask(L["PAD_RESET_TITLE_FMT"]:format(L[P.PRESET[value].key]), L["PAD_RESET_BODY"], {
            { L["PAD_RESET_ALL"], function() P.ResetAll(value) end },
            { L["PAD_CANCEL"] },
        })
    end)
    ui.heading("PAD_H_FEEL")
    ui.check("PAD_STICK", function() return P.Settings().stick end, function(on) P.Settings().stick = on end)
    ui.heading("PAD_REPEAT")
    ui.scale(0.15, 0.8, 0.05, function() return P.Settings().repeatDelay end, function(value) P.Settings().repeatDelay = value end,
        function(value) return ("%.2f s"):format(value) end)
    ui.heading("PAD_HIGHLIGHT")
    ui.choice(Choices(HIGHLIGHTS), function() return P.Settings().highlight end, function(value)
        P.Settings().highlight = value
        FG.Focus.Show()
    end)
    ui.check("PAD_SOUND", function() return P.Settings().sound end, function(on) P.Settings().sound = on end)
    ui.heading("PAD_H_HUD")
    ui.check("PAD_HUD_COMPACT", function() return FG.db.hud.handheldCompact ~= false end, function(on)
        FG.db.hud.handheldCompact = on
        FG.Emit("settings:changed")
    end)
    ui.choice(Choices(SPOTS), function() return FG.HUD.Spot() end, function(value) FG.HUD.MoveTo(value) end)
    ui.button("PAD_INTRO_AGAIN", function() PadSettings.Intro(true) end)
    ui.note("PAD_STEAM_NOTE")
end

-- What the buttons do, said once when a controller first drives the window: the buttons
-- named as this profile has them. Skip, or Open the controller settings. Again from there.
function PadSettings.Intro(again)
    local P = Pad()
    local db = P.DB()
    if db.introDone and not again then return false end
    if InCombatLockdown() then return false end
    db.introDone = true
    local function G(id) return P.Label(P.Binding(id)) end
    local body = L["PAD_INTRO_BODY_FMT"]:format(G("up"), G("confirm"), G("back"), G("search"), G("prevTab"), G("nextTab"),
        G("context"), G("openMap"))
    Ask(L["PAD_INTRO_TITLE"], body, {
        { L["PAD_INTRO_SETTINGS"], function()
            FG.Window.Show("settings")
            if FG.SettingsView.SelectByLabel then FG.SettingsView.SelectByLabel("SETG_CONTROLLER") end
        end },
        { L["PAD_INTRO_SKIP"] },
    })
    return true
end
FG.On("pad:input", function(active)
    if active and FG.Window.IsShown() and Pad().InUse() and not Pad().DB().introDone then
        FG.After(0, function() PadSettings.Intro(false) end)
    end
end)
FG.On("window:shown", function()
    if Pad().InUse() and not Pad().DB().introDone then FG.After(0, function() PadSettings.Intro(false) end) end
end)

FG.On("window:hidden", function()
    PadSettings.Dismiss()
    if nameBox and nameBox:IsShown() then
        nameBox:ClearFocus()
        nameBox:Hide()
    end
end)

FG.On("pad:bindings", function()
    -- The rows say what is bound now.
    for _, group in ipairs(FG.SettingsView.Groups()) do
        if group.label == "SETG_CONTROLLER" then
            for _, item in ipairs(group.items or {}) do
                if item.widget.Sync then item.widget:Sync() end
            end
        end
    end
end)
