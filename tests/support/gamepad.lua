-- The controller, as the client delivers it (Blizzard's UI code of build 12.1.5.70783, the
-- line WoW Forever 1.60.1 is built on; docs/CONTROLLER.md):
--   - a pad button is a key name (PAD1, PADDUP...); the buttons the GamePadEmulateShift /
--     Ctrl / Alt settings name act as modifiers, so LT held with the D-pad is SHIFT-PADDUP;
--   - a shown frame with EnableGamePadButton hears the button first (OnGamePadButtonDown);
--   - then the override bindings: each owner keeps its own, a priority one wins, and among
--     equals the latest; clearing an owner's leaves the others';
--   - then the game's own binding;
--   - a binding to click a button clicks it down, and up again on release;
--   - EnableGamePadButton, EnableGamePadStick, EnableKeyboard and override bindings are
--     protected: in combat lockdown they are refused, as the game refuses them
--     (client.blocked, with where from in client.blockedAt);
--   - PLAYER_REGEN_DISABLED comes just before the lockdown: its handlers may still make
--     protected changes, the last moment to, as addons that bind keys rely on;
--   - a secure state handler's snippet runs when its state changes, even in combat.
--
--     client:PadPress("PAD1")            -- pressed and released
--     client:PadPress("PADDDOWN", { hold = true }) ... client:PadRelease("PADDDOWN")
--     client:PadStick(0, -1)             -- the left stick
--     client:SetCombat(true)
local Pad = {}

function Pad.Install(client, env, UI)
    client.bindingSets = {}        -- owner -> { [chord] = { priority, button | action, order } }
    client.gameBindings = client.gameBindings or {}
    client.gameActions = {}        -- what reached the game
    client.held = {}
    client.blocked, client.blockedAt = {}, {}
    client.cvars = client.cvars or { GamePadEnable = "1", GamePadEmulateShift = "PADLTRIGGER", GamePadEmulateCtrl = "PADRTRIGGER",
                                     GamePadEmulateAlt = "none" }
    client.drivers = {}
    local order = 0

    local function Blocked(what)
        if client.player.combat then
            client.blocked[#client.blocked + 1] = what
            client.blockedAt[#client.blocked] = debug.traceback("", 3)
            return true
        end
        return false
    end
    UI.Protected = function(what) return not Blocked(what) end

    local function Set(owner, priority, key, entry)
        order = order + 1
        entry.priority, entry.order, entry.owner = priority and true or false, order, owner
        client.bindingSets[owner] = client.bindingSets[owner] or {}
        client.bindingSets[owner][key] = entry
    end
    env.SetOverrideBindingClick = function(owner, priority, key, button)
        if Blocked("SetOverrideBindingClick") then return end
        Set(owner, priority, key, { button = button })
    end
    env.SetOverrideBinding = function(owner, priority, key, action)
        if Blocked("SetOverrideBinding") then return end
        Set(owner, priority, key, { action = action })
    end
    env.ClearOverrideBindings = function(owner)
        if Blocked("ClearOverrideBindings") then return end
        client.bindingSets[owner] = nil
    end

    -- The override that wins for a chord, if any.
    local function Override(chord)
        local best
        for _, set in pairs(client.bindingSets) do
            local e = set[chord]
            if e and (not best or (e.priority and not best.priority) or (e.priority == best.priority and e.order > best.order)) then
                best = e
            end
        end
        return best
    end
    client.Override = function(_, chord) return Override(chord) end
    -- Every chord bound by these owners' overrides.
    client.OverridesOf = function(_, ...)
        local out = {}
        for _, owner in ipairs({ ... }) do
            for chord in pairs(client.bindingSets[owner] or {}) do out[#out + 1] = chord end
        end
        return out
    end

    env.GetBindingAction = function(key) return client.gameBindings[key] or "" end
    env.IsKeyDown = function(key) return client.held[key] == true end
    env.GetCVar = function(name) return client.cvars[name] end
    env.C_GamePad = { IsEnabled = function() return client.cvars.GamePadEnable == "1" end }
    env.GetPhysicalScreenSize = function() return client.root._rect.r, client.root._rect.t end
    local function Mod(name)
        return function()
            local button = client.cvars[name]
            return button and client.held[button] == true or false
        end
    end
    env.IsShiftKeyDown, env.IsControlKeyDown, env.IsAltKeyDown =
        Mod("GamePadEmulateShift"), Mod("GamePadEmulateCtrl"), Mod("GamePadEmulateAlt")
    env.RegisterStateDriver = function(frame, state, cond)
        client.drivers[#client.drivers + 1] = { frame = frame, state = state, cond = cond }
    end
    env.UnregisterStateDriver = function() end
    -- The template's restricted snippet: only what Forever-GPS's uses is understood.
    local function RunDrivers()
        for _, d in ipairs(client.drivers) do
            if d.cond:find("[combat]", 1, true) then
                local newstate = client.player.combat and "1" or "0"
                local snippet = d.frame:GetAttribute("_onstate-" .. d.state) or ""
                if snippet:find("ClearBindings", 1, true) and newstate == "1" then client.bindingSets[d.frame] = nil end
            end
        end
    end

    function client:SetCombat(on)
        if on then
            self:Fire("PLAYER_REGEN_DISABLED")
            self.player.combat = true
            RunDrivers()
        else
            self.player.combat = false
            RunDrivers()
            self:Fire("PLAYER_REGEN_ENABLED")
        end
    end

    local function Chord(button)
        local mods = {}
        for _, pair in ipairs({ { "ALT", "GamePadEmulateAlt" }, { "CTRL", "GamePadEmulateCtrl" }, { "SHIFT", "GamePadEmulateShift" } }) do
            local m = client.cvars[pair[2]]
            if m and m ~= button and client.held[m] then mods[#mods + 1] = pair[1] .. "-" end
        end
        return table.concat(mods) .. button
    end

    local function Listening()
        for i = #UI.frames, 1, -1 do
            local f = UI.frames[i]
            if f._padButtons and f:IsVisible() and f._scripts.OnGamePadButtonDown then return f end
        end
    end

    local function Click(name, down)
        local b = UI.named and UI.named[name] or env[name]
        if b and b._scripts.OnClick then b._scripts.OnClick(b, "LeftButton", down) end
    end

    local function IsModifier(button)
        for _, name in ipairs({ "GamePadEmulateShift", "GamePadEmulateCtrl", "GamePadEmulateAlt" }) do
            if client.cvars[name] == button then return true end
        end
        return false
    end

    -- A button pressed: who hears it, as the client decides. "frame", "addon", "modifier"
    -- or "game".
    function client:PadPress(button, opts)
        opts = opts or {}
        UI.frames, UI.named = self.frames, self.named
        -- The client says so when the controller becomes the input in use, not at each press.
        if not self.padActive then
            self.padActive = true
            self:Fire("GAME_PAD_ACTIVE_CHANGED", true)
        end
        self.held[button] = true
        local frame = Listening()
        if frame then
            frame._scripts.OnGamePadButtonDown(frame, button)
            if not opts.hold then self:PadRelease(button) end
            return "frame"
        end
        local o = Override(Chord(button))
        if o and o.button then
            Click(o.button, true)
            self.pressed = self.pressed or {}
            self.pressed[button] = o.button
            if not opts.hold then self:PadRelease(button) end
            return "addon"
        end
        -- A controller's own modifier alone is no binding.
        if IsModifier(button) then return "modifier" end
        local chord = Chord(button)
        self.gameActions[#self.gameActions + 1] = self.gameBindings[chord] or chord
        if not opts.hold then self.held[button] = nil end
        return "game"
    end

    function client:PadRelease(button)
        self.held[button] = nil
        local frame = Listening()
        if frame and frame._scripts.OnGamePadButtonUp then frame._scripts.OnGamePadButtonUp(frame, button) end
        local name = self.pressed and self.pressed[button]
        if name then
            self.pressed[button] = nil
            Click(name, false)
        end
    end

    -- The mouse or keyboard taken up again.
    function client:MouseUsed()
        if self.padActive then
            self.padActive = false
            self:Fire("GAME_PAD_ACTIVE_CHANGED", false)
        end
    end

    -- The left stick, as frames that hear it get it.
    function client:PadStick(x, y)
        local len = math.sqrt(x * x + y * y)
        for i = 1, #UI.frames do
            local f = UI.frames[i]
            if f._padStick and f:IsVisible() and f._scripts.OnGamePadStick then f._scripts.OnGamePadStick(f, "Left", x, y, len) end
        end
    end
end

return Pad
