-- The controller, for Forever-GPS's own window only. The game's gamepad UI keeps
-- movement, camera, targeting, combat and its menus; this never touches them outside
-- Forever-GPS, never in combat, and never changes the player's saved key bindings.
--
-- What the client gives (Blizzard's UI code of build 12.1.5.70783, the line WoW Forever
-- 1.60.1.70790 is built on; docs/CONTROLLER.md):
--   - pad buttons are binding keys: PAD1..PAD6, PADDUP/DOWN/LEFT/RIGHT, PADLSHOULDER,
--     PADRSHOULDER, PADLTRIGGER, PADRTRIGGER, PADLSTICK, PADRSTICK, PADBACK, PADFORWARD,
--     PADSYSTEM, PADSOCIAL, PADPADDLE1..4 (back paddles, as the client sees them);
--   - modifiers are whichever buttons the GamePadEmulateShift / Ctrl / Alt settings name:
--     with LT as Shift, "LT + D-pad up" arrives as SHIFT-PADDUP;
--   - GetBindingAction says what the game does with a key, GetBindingText draws its glyph
--     for the controller in use; GAME_PAD_ACTIVE_CHANGED says when the pad is in use;
--   - EnableGamePadButton, EnableKeyboard and override bindings are protected in combat.
--
-- How, after Easy Controller - Forever (https://github.com/moust4ki/EasyControllerWowForever,
-- commit cf2ad94, MIT License, Copyright (c) 2026 moust4ki, Licenses/EasyController-LICENSE.txt),
-- whose ConfigWindow.lua does this on Forever: while the window is open, its buttons are
-- priority override bindings that click hidden buttons; a button already held when the
-- window opens is bound only once released (its release is the game's); capture is a
-- frame that takes the pad and the keyboard, with a timeout. Added here: a secure state
-- handler drops every binding the moment combat starts, so in a fight the controller is
-- always the game's; bindings come back after combat if the window is still open.
local FG = ForeverGPS
local Pad = {}
FG.Pad = Pad

local L = FG.L

-- ==== actions ===============================================================
-- ctx: "world" (anywhere in the game: opening Forever-GPS), "ui" (inside its window),
-- "map" (with the route map in front). key: the text key of its name.
Pad.ACTIONS = {
    { id = "toggle", ctx = "world", key = "PAD_A_TOGGLE" },
    { id = "up", ctx = "ui", key = "PAD_A_UP", repeats = true },
    { id = "down", ctx = "ui", key = "PAD_A_DOWN", repeats = true },
    { id = "left", ctx = "ui", key = "PAD_A_LEFT", repeats = true },
    { id = "right", ctx = "ui", key = "PAD_A_RIGHT", repeats = true },
    { id = "confirm", ctx = "ui", key = "PAD_A_CONFIRM" },
    { id = "back", ctx = "ui", key = "PAD_A_BACK" },
    { id = "context", ctx = "ui", key = "PAD_A_CONTEXT" },
    { id = "search", ctx = "ui", key = "PAD_A_SEARCH" },
    { id = "home", ctx = "ui", key = "PAD_A_HOME" },
    { id = "prevTab", ctx = "ui", key = "PAD_A_PREVTAB" },
    { id = "nextTab", ctx = "ui", key = "PAD_A_NEXTTAB" },
    { id = "prevSub", ctx = "ui", key = "PAD_A_PREVSUB" },
    { id = "nextSub", ctx = "ui", key = "PAD_A_NEXTSUB" },
    { id = "pageUp", ctx = "ui", key = "PAD_A_PAGEUP", repeats = true },
    { id = "pageDown", ctx = "ui", key = "PAD_A_PAGEDOWN", repeats = true },
    { id = "top", ctx = "ui", key = "PAD_A_TOP" },
    { id = "bottom", ctx = "ui", key = "PAD_A_BOTTOM" },
    { id = "startNav", ctx = "ui", key = "PAD_A_START" },
    { id = "stopNav", ctx = "ui", key = "PAD_A_STOP" },
    { id = "showRoute", ctx = "ui", key = "PAD_A_ROUTE" },
    { id = "openMap", ctx = "ui", key = "PAD_A_MAP" },
    { id = "save", ctx = "ui", key = "PAD_A_SAVE" },
    { id = "replan", ctx = "ui", key = "PAD_A_REPLAN" },
    { id = "help", ctx = "ui", key = "PAD_A_HELP" },
}
local BY_ID = {}
for _, a in ipairs(Pad.ACTIONS) do BY_ID[a.id] = a end
Pad.BY_ID = BY_ID

-- ==== presets ===============================================================
-- Inside the window every button is Forever-GPS's while it is open (and never in combat),
-- so LB/RB can change tabs there; outside it only "toggle" is bound, and only with consent
-- (Settings, Controller), since whatever the game does with that button is replaced.
local COMMON = {
    up = "PADDUP", down = "PADDDOWN", left = "PADDLEFT", right = "PADDRIGHT",
    confirm = "PAD1", back = "PAD2", context = "PAD3", search = "PAD4",
    prevTab = "PADLSHOULDER", nextTab = "PADRSHOULDER", prevSub = "PADLTRIGGER", nextSub = "PADRTRIGGER",
    openMap = "PADRSTICK", showRoute = "PADLSTICK", help = "PADBACK",
}
local function With(extra)
    local out = {}
    for k, v in pairs(COMMON) do out[k] = v end
    for k, v in pairs(extra or {}) do out[k] = v end
    return out
end
Pad.PRESETS = {
    { id = "deck", key = "PAD_PRESET_DECK", glyphs = "auto",
      bindings = With({ toggle = "PADPADDLE1", pageUp = "PADPADDLE2", pageDown = "PADPADDLE4", startNav = "PADPADDLE3" }) },
    { id = "xbox", key = "PAD_PRESET_XBOX", glyphs = "letters", bindings = With() },
    { id = "playstation", key = "PAD_PRESET_PS", glyphs = "shapes", bindings = With() },
    { id = "minimal", key = "PAD_PRESET_MINIMAL", glyphs = "auto",
      bindings = { up = "PADDUP", down = "PADDDOWN", left = "PADDLEFT", right = "PADDRIGHT", confirm = "PAD1", back = "PAD2" } },
}
local PRESET = {}
for _, p in ipairs(Pad.PRESETS) do PRESET[p.id] = p end
Pad.PRESET = PRESET

-- Actions without which the window cannot be used: never left without a button.
Pad.ESSENTIAL = { up = true, down = true, confirm = true, back = true }

-- ==== saved state ===========================================================

local function Copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

local function DB()
    FG.db.pad = FG.db.pad or {}
    local db = FG.db.pad
    db.profiles = db.profiles or {}
    if not next(db.profiles) then
        db.profiles[L["PAD_PROFILE_DECK"]] = { preset = "deck", bindings = Copy(PRESET.deck.bindings) }
        db.profiles[L["PAD_PROFILE_PAD"]] = { preset = "xbox", bindings = Copy(PRESET.xbox.bindings) }
    end
    db.active = db.active or { handheld = L["PAD_PROFILE_DECK"], desktop = L["PAD_PROFILE_PAD"] }
    db.settings = db.settings or {}
    local s = db.settings
    if s.mode == nil then s.mode = "auto" end            -- auto, desktop, handheld
    if s.input == nil then s.input = "auto" end          -- auto, pad, mouse
    if s.stick == nil then s.stick = false end           -- left stick moves the selection
    if s.repeatDelay == nil then s.repeatDelay = 0.35 end
    if s.repeatRate == nil then s.repeatRate = 0.09 end
    if s.highlight == nil then s.highlight = "strong" end
    if s.sound == nil then s.sound = true end
    if s.worldConsent == nil then s.worldConsent = false end
    return db
end
Pad.DB = DB
function Pad.Settings() return DB().settings end

-- The layout in use: handheld or desktop, then the profile for it (this character's
-- choice first, when set).
function Pad.Layout()
    local s = Pad.Settings()
    if s.mode == "handheld" or s.mode == "desktop" then return s.mode end
    return Pad.SmallScreen() and Pad.InUse() and "handheld" or "desktop"
end

function Pad.ProfileName()
    local db = DB()
    local mine = FG.char and FG.char.padProfile
    if mine and db.profiles[mine] then return mine end
    local name = db.active[Pad.Layout()]
    if not db.profiles[name] then name = next(db.profiles) end
    return name
end

function Pad.Profile()
    return DB().profiles[Pad.ProfileName()]
end

-- An action's chord, or nil.
function Pad.Binding(id)
    local p = Pad.Profile()
    local b = p and p.bindings[id]
    return b ~= "" and b or nil
end

-- ==== the controller in use =================================================

local inUse = false
function Pad.InUse()
    local s = Pad.Settings()
    if s.input == "pad" then return true end
    if s.input == "mouse" then return false end
    return inUse
end

function Pad.Enabled()
    if C_GamePad and C_GamePad.IsEnabled then
        local ok, on = pcall(C_GamePad.IsEnabled)
        if ok then return on and true or false end
    end
    return GetCVar and GetCVar("GamePadEnable") == "1" or false
end

-- A small screen: the UI's own height in pixels, not a guess at a device.
function Pad.SmallScreen()
    if not GetPhysicalScreenSize then return false end
    -- Both values: "f and f()" would keep only the first.
    local w, h = GetPhysicalScreenSize()
    return (h and h <= 900 and w and w <= 1600) and true or false
end

-- The last things that happened to the controller, for /fgps pad: events, focus moves and
-- the actions the game blocked. Kinds, names of frames and times only.
local journal = {}
local JOURNAL_MAX = 40
function Pad.Note(kind, text)
    journal[#journal + 1] = ("%.1f %s %s"):format(GetTime(), kind, tostring(text or ""))
    if #journal > JOURNAL_MAX then table.remove(journal, 1) end
end
function Pad.Journal() return journal end

-- The game's own Gamepad UI is on (Core/Preflight.lua says why that matters).
function Pad.GamepadUI() return ForeverGPSPreflight.GamepadUI() end

local blocked = { all = 0, ours = 0 }
function Pad.Blocked() return blocked end
local function Blocked(kind)
    return function(addon, fn)
        blocked.all = blocked.all + 1
        if addon == FG.ADDON then blocked.ours = blocked.ours + 1 end
        Pad.Note(kind, tostring(addon) .. " " .. tostring(fn))
    end
end
FG.OnEvent("ADDON_ACTION_BLOCKED", Blocked("blocked"))
FG.OnEvent("ADDON_ACTION_FORBIDDEN", Blocked("forbidden"))
FG.OnEvent("INPUT_DEVICE_INTERFACE_TRANSITION", function(new, old)
    Pad.Note("interface", tostring(old) .. " to " .. tostring(new))
    FG.Emit("pad:gamepadui", Pad.GamepadUI())
end)

FG.OnEvent("GAME_PAD_ACTIVE_CHANGED", function(active)
    inUse = active and true or false
    Pad.Note("active", inUse)
    FG.Emit("pad:input", inUse)
end)
FG.OnEvent("GAME_PAD_CONNECTED", function()
    Pad.Note("connected")
    FG.Emit("pad:input", inUse)
end)
FG.OnEvent("GAME_PAD_DISCONNECTED", function()
    Pad.Note("disconnected")
    inUse = false
    -- A capture waiting for a controller button ends with the controller.
    Pad.StopLearning()
    FG.Emit("pad:input", false)
end)

-- ==== chords and modifiers ==================================================

local EMULATE = { SHIFT = "GamePadEmulateShift", CTRL = "GamePadEmulateCtrl", ALT = "GamePadEmulateAlt" }
local MOD_ORDER = { "ALT", "CTRL", "SHIFT" }

-- The modifier a pad button stands for in this client's gamepad settings, if any.
function Pad.ModifierOf(button)
    for mod, cvar in pairs(EMULATE) do
        if GetCVar and GetCVar(cvar) == button then return mod end
    end
    return nil
end

-- "SHIFT-PADDUP" -> "SHIFT", "PADDUP".
function Pad.Split(chord)
    local mods, key = {}, chord
    while true do
        local m, rest = key:match("^(%u+)%-(.+)$")
        if not (m and EMULATE[m]) then break end
        mods[#mods + 1], key = m, rest
    end
    return mods, key
end

-- The chord for a button pressed with modifiers held (in the game's order).
function Pad.Chord(button, held)
    local parts = {}
    for _, m in ipairs(MOD_ORDER) do
        if held[m] then parts[#parts + 1] = m .. "-" end
    end
    return table.concat(parts) .. button
end

-- A chord's label: the game's glyphs when it draws them, a modifier shown as the button
-- the controller uses for it.
function Pad.Label(chord)
    if not chord then return L["PAD_UNBOUND"] end
    local mods, key = Pad.Split(chord)
    local alone = #mods == 0 and Pad.ModifierOf(key)
    if alone then return L["PAD_MOD_ALONE_FMT"]:format(Pad.KeyLabel(key), alone) end
    local parts = {}
    for _, m in ipairs(mods) do
        local button = GetCVar and GetCVar(EMULATE[m])
        parts[#parts + 1] = (button and button ~= "" and button ~= "none") and Pad.KeyLabel(button) or m
    end
    parts[#parts + 1] = Pad.KeyLabel(key)
    return table.concat(parts, " + ")
end

local NAMES = { PAD1 = "A", PAD2 = "B", PAD3 = "X", PAD4 = "Y", PADDUP = "Up", PADDDOWN = "Down", PADDLEFT = "Left",
                PADDRIGHT = "Right", PADLSHOULDER = "LB", PADRSHOULDER = "RB", PADLTRIGGER = "LT", PADRTRIGGER = "RT",
                PADLSTICK = "L3", PADRSTICK = "R3", PADBACK = "View", PADFORWARD = "Menu", PADPADDLE1 = "L4",
                PADPADDLE2 = "L5", PADPADDLE3 = "R4", PADPADDLE4 = "R5" }
Pad.NAMES = NAMES

function Pad.KeyLabel(key)
    if GetBindingText then
        local ok, text = pcall(GetBindingText, key, 1)
        if ok and type(text) == "string" and text ~= "" and text ~= key then return text end
    end
    return NAMES[key] or key
end

-- What the game itself does with a chord: its binding's name, or nil.
function Pad.GameAction(chord)
    if not GetBindingAction then return nil end
    local ok, action = pcall(GetBindingAction, chord)
    if not ok or not action or action == "" then return nil end
    return action, _G["BINDING_NAME_" .. action] or action
end

-- A chord that is only one of the controller's modifiers (LT as Shift...): the game
-- keeps it for the modifier, so it does nothing alone.
function Pad.ModifierOnly(chord)
    if not chord then return false end
    local mods, key = Pad.Split(chord)
    return #mods == 0 and Pad.ModifierOf(key) ~= nil
end

-- The Forever-GPS action that already uses a chord in the same context, if another.
function Pad.Clash(id, chord)
    local ctx = BY_ID[id].ctx
    for _, a in ipairs(Pad.ACTIONS) do
        if a.id ~= id and Pad.Binding(a.id) == chord and (a.ctx == ctx or a.ctx == "world" or ctx == "world") then return a.id end
    end
    return nil
end

-- ==== changing bindings =====================================================

local undo

-- Sets an action's chord (nil: none). how, when another action has it: "swap" gives
-- that one this action's old chord, "replace" leaves it without. Returns false and why
-- when it would leave the window unusable.
function Pad.Set(id, chord, how)
    local p = Pad.Profile()
    local old = p.bindings[id]
    if not chord and Pad.ESSENTIAL[id] then return false, "essential" end
    local other = chord and Pad.Clash(id, chord)
    if other then
        if how == "swap" then
            if not old and Pad.ESSENTIAL[other] then return false, "essential" end
            undo = { profile = Pad.ProfileName(), changes = { { id, old }, { other, p.bindings[other] } } }
            p.bindings[other] = old
        elseif how == "replace" then
            if Pad.ESSENTIAL[other] then return false, "essential" end
            undo = { profile = Pad.ProfileName(), changes = { { id, old }, { other, p.bindings[other] } } }
            p.bindings[other] = nil
        else
            return false, "clash", other
        end
    else
        undo = { profile = Pad.ProfileName(), changes = { { id, old } } }
    end
    p.bindings[id] = chord
    p.preset = p.preset and (p.preset:find("custom", 1, true) and p.preset or p.preset .. "+custom") or "custom"
    Pad.Apply()
    FG.Emit("pad:bindings")
    return true
end

function Pad.Undo()
    if not undo then return false end
    local p = DB().profiles[undo.profile]
    if p then
        for _, c in ipairs(undo.changes) do p.bindings[c[1]] = c[2] end
    end
    undo = nil
    Pad.Apply()
    FG.Emit("pad:bindings")
    return true
end

function Pad.CanUndo() return undo ~= nil end

-- One action back to its preset's chord.
function Pad.Reset(id)
    local p = Pad.Profile()
    local base = PRESET[(p.preset or "xbox"):match("^(%a+)")] or PRESET.xbox
    return Pad.Set(id, base.bindings[id], "swap")
end

-- The whole profile back to a preset.
function Pad.ResetAll(preset)
    local p = Pad.Profile()
    local base = PRESET[preset or (p.preset or "xbox"):match("^(%a+)")] or PRESET.xbox
    undo = { profile = Pad.ProfileName(), changes = {} }
    for _, a in ipairs(Pad.ACTIONS) do undo.changes[#undo.changes + 1] = { a.id, p.bindings[a.id] } end
    p.bindings, p.preset = Copy(base.bindings), base.id
    Pad.Apply()
    FG.Emit("pad:bindings")
end

-- ==== profiles ==============================================================

function Pad.Profiles()
    local out = {}
    for name in pairs(DB().profiles) do out[#out + 1] = name end
    table.sort(out)
    return out
end

-- Uses a profile for the current layout (handheld or desktop), or for this character.
function Pad.Use(name, forCharacter)
    local db = DB()
    if not db.profiles[name] then return false end
    if forCharacter then
        FG.char.padProfile = name
    else
        if FG.char then FG.char.padProfile = nil end
        db.active[Pad.Layout()] = name
    end
    Pad.Apply()
    FG.Emit("pad:bindings")
    return true
end

local function Unique(base)
    local db, name, n = DB(), base, 2
    while db.profiles[name] do
        name = ("%s %d"):format(base, n)
        n = n + 1
    end
    return name
end

function Pad.NewProfile(preset, name)
    local base = PRESET[preset] or PRESET.xbox
    name = Unique(name or L[base.key])
    DB().profiles[name] = { preset = base.id, bindings = Copy(base.bindings) }
    Pad.Use(name)
    return name
end

function Pad.Duplicate(name)
    local db = DB()
    local from = db.profiles[name or Pad.ProfileName()]
    if not from then return nil end
    local copy = Unique((name or Pad.ProfileName()) .. " " .. L["PAD_COPY"])
    db.profiles[copy] = { preset = from.preset, bindings = Copy(from.bindings) }
    Pad.Use(copy)
    return copy
end

function Pad.Rename(old, new)
    local db = DB()
    new = new and new:gsub("^%s+", ""):gsub("%s+$", "")
    if not (db.profiles[old] and new and new ~= "" and not db.profiles[new]) then return false end
    db.profiles[new], db.profiles[old] = db.profiles[old], nil
    for k, v in pairs(db.active) do if v == old then db.active[k] = new end end
    if FG.char and FG.char.padProfile == old then FG.char.padProfile = new end
    FG.Emit("pad:bindings")
    return true
end

-- Never the last one: there is always a profile to fall back on.
function Pad.Delete(name)
    local db = DB()
    if not db.profiles[name] or #Pad.Profiles() <= 1 then return false end
    db.profiles[name] = nil
    local first = Pad.Profiles()[1]
    for k, v in pairs(db.active) do if v == name then db.active[k] = first end end
    if FG.char and FG.char.padProfile == name then FG.char.padProfile = nil end
    Pad.Apply()
    FG.Emit("pad:bindings")
    return true
end

-- ==== taking the buttons ====================================================

-- Owns the window's bindings. A secure state handler: when combat starts it drops them
-- itself (protected code cannot be called from here then), so in a fight the controller
-- is always the game's.
local owner, world
local buttons = {}
local held = {}          -- chords bound only once their button is released
local watch              -- runs only while one of those waits
local capturing = false
local pending = false    -- the window wants the pad, after combat
local repeating          -- an action repeated while its button is held

-- A binding owner that lets go of its bindings itself the moment combat starts: a
-- secure state handler, whose restricted snippet may still do that in combat.
local function CombatSafeOwner(name)
    local f = CreateFrame("Frame", name, UIParent, "SecureHandlerStateTemplate")
    f:SetAttribute("_onstate-fgpscombat", [[
        if newstate == "1" then self:ClearBindings() end
    ]])
    if RegisterStateDriver then RegisterStateDriver(f, "fgpscombat", "[combat] 1; 0") end
    return f
end

-- Two owners: the window's buttons (while it is open) and the one that opens it from
-- anywhere. Neither keeps a button in combat: there, every button is the game's.
local function Owner()
    if owner then return owner end
    owner = CombatSafeOwner("ForeverGPSPadOwner")
    world = CombatSafeOwner("ForeverGPSPadWorld")
    return owner
end

-- A hidden button per action, clicked by its binding: down starts, up stops a repeat.
local function ButtonFor(id)
    if buttons[id] then return buttons[id] end
    local b = CreateFrame("Button", "ForeverGPSPad_" .. id, UIParent)
    b:RegisterForClicks("AnyDown", "AnyUp")
    b:SetScript("OnClick", function(_, _, down) Pad.Press(id, down ~= false) end)
    buttons[id] = b
    return b
end

-- The bindings we hold, by owner: what the report shows, and nothing else reads.
local owned = {}
local function Own(f, priority, chord, id)
    SetOverrideBindingClick(f, priority, chord, ButtonFor(id):GetName())
    owned[f] = owned[f] or {}
    owned[f][chord] = id
end
local function Release(f)
    ClearOverrideBindings(f)
    owned[f] = nil
end
function Pad.Held()
    local function List(f)
        local out = {}
        for chord, id in pairs(f and owned[f] or {}) do out[#out + 1] = chord .. "=" .. id end
        table.sort(out)
        return out
    end
    return List(owner), List(world)
end

-- Whether the player let the open-from-anywhere button work while playing. The consent is
-- for one button: changing the button, switching profile or undoing never carries it to
-- another, so no button the game uses is taken without being asked about.
function Pad.WorldConsented()
    local s, chord = Pad.Settings(), Pad.Binding("toggle")
    return chord ~= nil and s.worldConsent == true and s.worldChord == chord
end

function Pad.SetWorldConsent(on)
    local s = Pad.Settings()
    s.worldConsent = on and true or false
    s.worldChord = on and Pad.Binding("toggle") or nil
    Pad.ApplyWorld()
    FG.Emit("pad:bindings")
end

-- The world binding: opening Forever-GPS from anywhere. Only with the player's consent,
-- because whatever the game does with that button is replaced while Forever-GPS is loaded.
-- Never in combat: it is dropped as combat starts and put back after.
function Pad.ApplyWorld()
    if InCombatLockdown() then
        pending = true
        return false
    end
    Owner()
    Release(world)
    if Pad.WorldConsented() then
        Own(world, false, Pad.Binding("toggle"), "toggle")
    end
    return true
end

local function Bind(chord, id)
    local _, key = Pad.Split(chord)
    -- A modifier of the controller's own (LT as Shift...) is not a button to bind alone.
    if Pad.ModifierOf(key) and chord == key then return end
    if IsKeyDown and IsKeyDown(key) then
        held[chord] = id
        if watch then watch:Show() end
        return
    end
    Own(owner, true, chord, id)
end

-- The left stick, when the player asks for it: past STICK_AT it moves the selection,
-- again while held. Off by default: whether the game also moves the character while a
-- frame hears the stick is not confirmed on Forever (docs/CONTROLLER.md).
local STICK_AT, STICK_BACK = 0.6, 0.35
local stick
local function Stick(on)
    if not stick then
        stick = CreateFrame("Frame", "ForeverGPSPadStick", UIParent)
        stick:SetScript("OnGamePadStick", function(self, which, x, y, len)
            if which ~= "Left" then return end
            local dir
            if (len or 0) >= STICK_AT then
                if math.abs(x) > math.abs(y) then dir = x > 0 and "right" or "left" else dir = y > 0 and "up" or "down" end
            elseif (len or 0) > STICK_BACK and self.dir then
                dir = self.dir
            end
            if dir ~= self.dir then
                if self.dir then Pad.Press(self.dir, false) end
                self.dir = dir
                if dir then Pad.Press(dir, true) end
            end
        end)
    end
    if stick.EnableGamePadStick then stick:EnableGamePadStick(on and Pad.Settings().stick or false) end
    stick:SetShown(on and Pad.Settings().stick or false)
    if not on and stick.dir then
        Pad.Press(stick.dir, false)
        stick.dir = nil
    end
end
Pad._Stick = function() return stick end

-- Gives the window's buttons to Forever-GPS (on) or back to the game (off).
function Pad.Capture(on)
    if InCombatLockdown() then
        pending = on
        return false
    end
    Owner()
    Release(owner)
    held = {}
    capturing = on and true or false
    pending = false
    if on then
        for _, a in ipairs(Pad.ACTIONS) do
            local chord = Pad.Binding(a.id)
            if chord then Bind(chord, a.id) end
        end
    end
    Stick(capturing)
    FG.Emit("pad:capture", capturing)
    return true
end

function Pad.Capturing() return capturing and not InCombatLockdown() end

-- After a change: the window's buttons again if it has them, and the world's.
function Pad.Apply()
    Pad.ApplyWorld()
    if capturing then Pad.Capture(true) end
end

-- Buttons held when the window opened: theirs once released. Hidden, so not running,
-- while none waits.
watch = CreateFrame("Frame")
watch:Hide()
watch:SetScript("OnUpdate", function(self, elapsed)
    self.t = (self.t or 0) + elapsed
    if self.t < 0.1 then return end
    self.t = 0
    if not next(held) then return self:Hide() end
    if InCombatLockdown() then return end
    for chord, id in pairs(held) do
        local _, key = Pad.Split(chord)
        if not IsKeyDown(key) then
            held[chord] = nil
            if capturing then Own(owner, true, chord, id) end
        end
    end
end)

FG.OnEvent("PLAYER_REGEN_DISABLED", function()
    -- The event comes just before the lockdown, while protected changes are still
    -- allowed: the window's bindings go now (the state handler drops them too, in case).
    -- Remember to take them back. The stick's frame, hidden, hears nothing.
    if capturing then pending = true end
    capturing = false
    if owner and not InCombatLockdown() then
        Release(owner)
        Release(world)
    end
    held = {}
    if stick then
        stick:Hide()
        if stick.dir then Pad.Press(stick.dir, false) stick.dir = nil end
    end
    repeating = nil
    FG.Emit("pad:capture", false)
end)
FG.OnEvent("PLAYER_REGEN_ENABLED", function()
    local wanted = pending
    pending = false
    if wanted and FG.Window and FG.Window.IsShown() then Pad.Capture(true) end
    -- The world button was dropped as combat started, whatever else happened: back now.
    Pad.ApplyWorld()
end)
FG.On("login", function()
    DB()
    Pad.ApplyWorld()
end)

-- ==== pressing ==============================================================

local repeater = CreateFrame("Frame")
repeater:Hide()
repeater:SetScript("OnUpdate", function(self)
    if not repeating then return self:Hide() end
    local now = GetTime()
    if now >= repeating.at then
        repeating.at = now + Pad.Settings().repeatRate
        Pad.Do(repeating.id)
    end
end)

-- A binding pressed (down) or released.
function Pad.Press(id, down)
    if not down then
        if repeating and repeating.id == id then repeating = nil end
        return
    end
    inUse = true
    Pad.Do(id)
    if BY_ID[id] and BY_ID[id].repeats then
        repeating = { id = id, at = GetTime() + Pad.Settings().repeatDelay }
        repeater:Show()
    end
end

-- Runs an action: Forever-GPS opening, or what the window in front does with it.
function Pad.Do(id)
    FG.Metrics.Begin("padAction")
    if id == "toggle" then
        FG.Toggle()
    elseif FG.Focus then
        FG.Focus.Do(id)
    end
    FG.Metrics.End("padAction")
    FG.Emit("pad:action", id)
end

-- Showing the window takes the pad when it is in use; hiding gives it back.
FG.On("window:shown", function()
    if Pad.Enabled() then Pad.Capture(true) end
end)
FG.On("window:hidden", function()
    -- A capture waiting for a press ends with the window: nothing keeps listening.
    Pad.StopLearning()
    Pad.Capture(false)
end)

-- ==== learning a binding ====================================================

local learner
-- Waits for one press, of the pad or the keyboard: done(chord) or done(nil) on cancel or
-- after `timeout` seconds. The pad's back button alone cancels unless back is what is
-- being set. Never in combat: protected functions are needed to hear the pad.
function Pad.Learn(id, done, timeout)
    if InCombatLockdown() then return false, "combat" end
    if not learner then
        learner = CreateFrame("Frame", "ForeverGPSPadLearner", UIParent)
        learner:SetFrameStrata("FULLSCREEN_DIALOG")
        learner:SetSize(1, 1)
        learner:SetPoint("CENTER")
        learner:Hide()
        local function Finish(chord)
            if not learner:IsShown() then return end
            learner:Hide()
            if learner.timer then learner.timer:Cancel() end
            if not InCombatLockdown() then
                learner:EnableKeyboard(false)
                if learner.EnableGamePadButton then learner:EnableGamePadButton(false) end
            end
            if (capturing or learner.wasCapturing) and FG.Window and FG.Window.IsShown() then Pad.Capture(true) end
            local cb = learner.done
            learner.done = nil
            if cb then cb(chord) end
        end
        learner.Finish = Finish
        local function Held()
            return { SHIFT = IsShiftKeyDown and IsShiftKeyDown(), CTRL = IsControlKeyDown and IsControlKeyDown(),
                     ALT = IsAltKeyDown and IsAltKeyDown() }
        end
        learner:SetScript("OnGamePadButtonDown", function(self, button)
            -- A controller's own modifier pressed alone: wait for the button with it.
            if Pad.ModifierOf(button) then return end
            local mods = Held()
            if button == Pad.Binding("back") and self.id ~= "back" and not (mods.SHIFT or mods.CTRL or mods.ALT) then
                return Finish(nil)
            end
            Finish(Pad.Chord(button, mods))
        end)
        learner:SetScript("OnKeyDown", function(_, key)
            if key == "ESCAPE" then return Finish(nil) end
            if key:find("SHIFT$") or key:find("CTRL$") or key:find("ALT$") then return end
            Finish(Pad.Chord(key, Held()))
        end)
    end
    learner.id, learner.done, learner.wasCapturing = id, done, capturing
    -- The window's own bindings would take the press first: off while learning.
    if capturing then
        Owner()
        Release(owner)
    end
    learner:EnableKeyboard(true)
    learner:SetPropagateKeyboardInput(false)
    if learner.EnableGamePadButton then learner:EnableGamePadButton(true) end
    learner:Show()
    learner.timer = C_Timer.NewTimer(timeout or 10, function() learner.Finish(nil) end)
    return true
end

function Pad.Learning() return learner ~= nil and learner:IsShown() end
function Pad.StopLearning() if learner then learner.Finish(nil) end end

-- Combat starting mid-capture: the frame cannot stay, it lets go at once.
FG.OnEvent("PLAYER_REGEN_DISABLED", function()
    if learner and learner:IsShown() then
        learner:Hide()
        if not InCombatLockdown() then
            learner:EnableKeyboard(false)
            if learner.EnableGamePadButton then learner:EnableGamePadButton(false) end
        end
        if learner.timer then learner.timer:Cancel() end
        local cb = learner.done
        learner.done = nil
        if cb then cb(nil, "combat") end
    end
end)

-- ==== the report ============================================================
-- /fgps pad, and the controller lines of /fgps report. Settings, states and names of our own
-- frames: nothing about the character, the realm or the account.

local OTHERS = { "ConsolePort", "EasyController", "DeckForever", "Questie", "TomTom", "ClassicUIForever" }

local function Device()
    if not (C_GamePad and C_GamePad.GetActiveDeviceID) then return "no C_GamePad" end
    local ok, id = pcall(C_GamePad.GetActiveDeviceID)
    if not ok or not id then return "none active" end
    local state = C_GamePad.GetDeviceMappedState and select(2, pcall(C_GamePad.GetDeviceMappedState, id))
    local style = type(state) == "table" and state.labelStyle
    return ("device %s, labels %s"):format(tostring(id), tostring(style))
end

local function Present(name)
    local value = _G
    for part in name:gmatch("[^%.]+") do
        value = type(value) == "table" and value[part] or nil
    end
    return value ~= nil
end
local NEEDED = { "C_GamePad.IsEnabled", "C_InputInterfaceStyle.GetCurrentStyle", "SetOverrideBindingClick", "ClearOverrideBindings",
                 "RegisterStateDriver", "GetBindingAction", "GetBindingText", "IsKeyDown", "GetPhysicalScreenSize" }

function Pad.ReportLines()
    local s, out = Pad.Settings(), {}
    local missing = {}
    for _, name in ipairs(NEEDED) do if not Present(name) then missing[#missing + 1] = name end end
    out[#out + 1] = ("Controller: enabled %s, in use %s, %s; the game's Gamepad UI %s"):format(tostring(Pad.Enabled()),
        tostring(Pad.InUse()), Device(), Pad.GamepadUI() and "ON (Forever-GPS stands aside where it would taint it)" or "off")
    out[#out + 1] = ("Controller settings: input %s, layout %s (%s), profile %s (%s), stick %s, open from anywhere %s"):format(
        tostring(s.input), Pad.Layout(), tostring(s.mode), tostring(Pad.ProfileName()), tostring(Pad.Profile() and Pad.Profile().preset),
        tostring(s.stick), Pad.WorldConsented() and ("allowed for " .. tostring(Pad.Binding("toggle"))) or "not allowed")
    local window, anywhere = Pad.Held()
    out[#out + 1] = ("Bindings held: window %d%s, open from anywhere %s; capturing %s, waiting for a press %s, in combat %s"):format(
        #window, #window > 0 and (" (" .. table.concat(window, " ") .. ")") or "", #anywhere > 0 and table.concat(anywhere, " ") or "none",
        tostring(Pad.Capturing()), tostring(Pad.Learning()), tostring(InCombatLockdown()))
    local focus = FG.Focus and FG.Focus.Current()
    out[#out + 1] = ("Focus: %s"):format(focus and (focus.GetName and focus:GetName() or focus.GetObjectType and focus:GetObjectType()) or "none")
    out[#out + 1] = ("Blocked actions the game reported this session: %d, %d of them Forever-GPS's"):format(blocked.all, blocked.ours)
    local others = {}
    for _, name in ipairs(OTHERS) do
        if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(name) then
            local version = C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(name, "Version")
            others[#others + 1] = name .. (version and (" " .. version) or "")
        end
    end
    out[#out + 1] = "Addons loaded alongside: " .. (#others > 0 and table.concat(others, ", ") or "none of " .. table.concat(OTHERS, ", "))
    out[#out + 1] = #missing == 0 and "Controller API: all present" or ("Controller API MISSING: " .. table.concat(missing, ", "))
    return out
end

-- The whole controller report, to copy: the lines, then what happened lately.
function Pad.Report()
    local version, build = GetBuildInfo()
    local out = { ("Forever-GPS %s controller report, client %s build %s"):format(tostring(FG.VERSION), tostring(version), tostring(build)) }
    for _, line in ipairs(Pad.ReportLines()) do out[#out + 1] = line end
    out[#out + 1] = ("Taint log: %s"):format(tostring(GetCVar and GetCVar("taintLog") or "off"))
    out[#out + 1] = "Recent:"
    for _, line in ipairs(journal) do out[#out + 1] = "  " .. line end
    return table.concat(out, "\n")
end
