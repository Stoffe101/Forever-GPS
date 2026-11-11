-- A keyboard on screen, for typing with a controller: searches, quest searches, coordinates,
-- list and profile names. Its keys are ordinary buttons, so the controller moves over them
-- as over the rest of the window (UI/Focus.lua): confirm types, the context button deletes,
-- the search button accepts, back cancels and puts the text back as it was.
--
-- It types only into Forever-GPS's own boxes, never into chat or any of the game's, and does
-- nothing protected, so it is safe in combat. The text changes as typed, so a search's
-- results update above it with every letter.
--
-- SteamOS's own keyboard (Steam + X on a Steam Deck) also types into these boxes, as into
-- any text field: docs/CONTROLLER.md.
local FG = ForeverGPS
local Keyboard = {}
FG.PadKeyboard = Keyboard

local Kit, Theme = FG.Kit, FG.Theme
local L = FG.L

local LETTERS = { "1234567890", "qwertyuiop", "asdfghjkl'", "zxcvbnm,.-" }
local SYMBOLS = { "1234567890", ":;()!?&/#+", "@%=*\"_[]{}", "<>~|\\$^`,." }
local KEY_W, KEY_H, GAP = 34, 30, 4

local f, target, before, layer, surface

local function Write(text)
    if not target then return end
    target:SetText(text)
    target:SetCursorPosition(#text)
    -- As if typed: the box reacts as it does to a key.
    local changed = target:GetScript("OnTextChanged")
    if changed then changed(target, true) end
    f.shown:SetText(text ~= "" and text or " ")
end

local function Type(ch)
    if not target then return end
    local text = target:GetText() or ""
    local most = target.GetMaxLetters and target:GetMaxLetters() or 0
    if most > 0 and #text >= most then return end
    Write(text .. ch)
end

local function Erase()
    local text = target and target:GetText() or ""
    -- One character, however many bytes it takes.
    Write((text:gsub("[%z\1-\127\194-\244][\128-\191]*$", "")))
end

local function Layout()
    local rows = layer == "symbols" and SYMBOLS or LETTERS
    for r, row in ipairs(rows) do
        for c = 1, #row do
            local key = f.keys[r][c]
            local ch = row:sub(c, c)
            key.char = ch
            key.padKey = ch
            key:SetLabel(ch == " " and "" or ch)
        end
    end
    f.layerKey:SetLabel(layer == "symbols" and "abc" or "?!#")
end

local function Close(accept)
    if not f then return end
    local box = target
    f:Hide()
    target = nil
    if surface then
        local s = surface
        surface = nil
        FG.Focus.Pop(s)
    end
    if not box then return end
    if not accept then
        box:SetText(before or "")
        local changed = box:GetScript("OnTextChanged")
        if changed then changed(box, true) end
    elseif box.padAccept then
        box.padAccept(box)
    end
    FG.Emit("keyboard:closed", box, accept)
end
Keyboard.Close = Close

local function Build()
    f = CreateFrame("Frame", "ForeverGPSKeyboard", UIParent)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:Hide()
    f.back = Kit.Shape(f, 10, "BACKGROUND", 0)
    f.edge = Kit.Shape(f, 10, "BACKGROUND", 7, true)
    Theme.Paint(function(c)
        f.back:SetColor(c.window)
        f.edge:SetColor(c.lineStrong)
    end)
    f.shown = Kit.Text(f, "body", "text")
    f.shown:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
    f.shown:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -10)
    f.hint = Kit.Text(f, "small", "textDim")
    f.hint:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 8)
    f.hint:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 8)
    f.keys = {}
    local top = -34
    for r = 1, #LETTERS do
        f.keys[r] = {}
        for c = 1, 10 do
            local key = Kit.Button(f, { text = "", height = KEY_H, width = KEY_W, onClick = function(self) Type(self.char) end })
            key:SetPoint("TOPLEFT", f, "TOPLEFT", 12 + (c - 1) * (KEY_W + GAP), top - (r - 1) * (KEY_H + GAP))
            f.keys[r][c] = key
        end
    end
    local y = top - #LETTERS * (KEY_H + GAP)
    local function Wide(label, w, x, fn)
        local b = Kit.Button(f, { text = label, height = KEY_H, width = w, onClick = fn })
        b:SetPoint("TOPLEFT", f, "TOPLEFT", 12 + x, y)
        return b
    end
    local unit = KEY_W + GAP
    f.layerKey = Wide("?!#", unit * 2 - GAP, 0, function()
        layer = layer == "symbols" and "letters" or "symbols"
        Layout()
    end)
    f.space = Wide(L["KB_SPACE"], unit * 4 - GAP, unit * 2, function() Type(" ") end)
    f.erase = Wide(L["KB_ERASE"], unit * 2 - GAP, unit * 6, Erase)
    f.done = Wide(L["KB_DONE"], unit * 2 - GAP, unit * 8, function() Close(true) end)
    f:SetSize(24 + 10 * unit - GAP, 34 + (#LETTERS + 1) * unit + 30)
    layer = "letters"
    Layout()
end

-- Opens over a box of Forever-GPS's own: its text is kept, to put back on cancel.
function Keyboard.Open(box)
    local name = box and box.GetName and box:GetName()
    if not (name and name:find("^ForeverGPS")) then return false end
    if not f then Build() end
    if target and target ~= box then Close(true) end
    target, before = box, box:GetText() or ""
    box:ClearFocus()
    f.shown:SetText(before ~= "" and before or " ")
    local Pad = FG.Pad
    local function Glyph(id)
        local chord = Pad and Pad.Binding(id)
        return chord and Pad.Label(chord) or "?"
    end
    f.hint:SetText(L["KB_HINT_FMT"]:format(Glyph("confirm"), Glyph("context"), Glyph("search"), Glyph("back")))
    f:ClearAllPoints()
    local window = FG.Window.Frame()
    if window and window:IsShown() then
        f:SetPoint("BOTTOM", window, "BOTTOM", 0, 8)
    else
        f:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 40)
    end
    f:Show()
    f:Raise()
    surface = {
        root = f,
        first = function() return f.keys[2][1] end,
        onAction = function(id)
            if id == "context" then Erase() return true end
            if id == "search" then Close(true) return true end
            return false
        end,
        onBack = function() Close(false) end,
    }
    FG.Focus.Push(surface)
    return true
end

function Keyboard.IsOpen() return f ~= nil and f:IsShown() end

-- Where a character is on the keys now: { row, col }, for tests.
function Keyboard._Where(ch)
    local rows = layer == "symbols" and SYMBOLS or LETTERS
    for r, row in ipairs(rows) do
        local c = row:find(ch, 1, true)
        if c then return { row = r, col = c } end
    end
end
function Keyboard.Target() return target end

-- The window closing takes the keyboard with it, keeping what was typed.
FG.On("window:hidden", function() if target then Close(true) end end)
