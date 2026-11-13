-- WoW Forever's own Gamepad UI, as far as an addon can taint it. From Blizzard's UI code of
-- the Forever client, build 1.60.1.70938 (Gethe/wow-ui-source, branch forever):
--
--   - C_InputInterfaceStyle.GetCurrentStyle() is Enum.InputDeviceInterfaceType.Gamepad
--     while it is on; INPUT_DEVICE_INTERFACE_TRANSITION(new, old) says when that changes.
--   - Its focus and binding bookkeeping (Blizzard_GamepadSharedUtility's
--     FrameControlsManager and InputBindingManager, Blizzard_GamepadSmartNavigation) runs
--     inside whatever execution shows a menu (MenuProxy.OnShow), a popup, a panel
--     (UIParentPanelManager.ShowUIPanel / HideUIPanel), opens or closes the bags, or makes
--     a frame under an open managed panel (SmartNavigation post-hooks CreateFrame).
--   - Done by addon code, that bookkeeping is written tainted, and Blizzard's restricted
--     SetPreferredGamepadInteractTarget() (HasRestrictions) is blocked at the next target
--     change, and the next, blamed on the addon.
--
-- So while it is on, each of those, when addon code does it, is recorded in
-- client.gamepadTaint: { what = ..., detail = ... }. The player opening a game menu
-- (client:PlayerOpensGameMenu) or the map (client:PlayerToggleMap) is the game's own doing,
-- but what addon hooks and menu modifiers do inside it is still addon code, and counts.
--
--     client:SetGamepadUI(true)
--     client:PlayerOpensGameMenu("MENU_QUEST_MAP_LOG_TITLE", { questID = 33 })   -- its entries
local GamepadUI = {}

function GamepadUI.Install(client, env)
    client.gamepadUI = false
    client.gamepadTaint = {}
    client.menuModifiers = {}
    local function Taint(what, detail)
        if client.gamepadUI then
            client.gamepadTaint[#client.gamepadTaint + 1] = { what = what, detail = detail,
                                                              where = client.traceTaint and debug.traceback("", 3) or nil }
        end
    end

    env.C_InputInterfaceStyle = { GetCurrentStyle = function() return client.gamepadUI and 1 or 0 end }
    rawset(env.Enum, "InputDeviceInterfaceType", { Mkb = 0, Gamepad = 1 })

    function client:SetGamepadUI(on)
        local old = self.gamepadUI and 1 or 0
        self.gamepadUI = on and true or false
        self:Fire("INPUT_DEVICE_INTERFACE_TRANSITION", self.gamepadUI and 1 or 0, old)
    end

    -- A menu description: what the modifiers add to it.
    local function Root()
        local root = { items = {} }
        local function add(kind)
            return function(_, label)
                root.items[#root.items + 1] = { kind = kind, label = label }
                return setmetatable({}, { __index = function() return function() end end })
            end
        end
        root.CreateButton, root.CreateDivider, root.CreateCheckbox = add("button"), add("divider"), add("checkbox")
        root.CreateTitle, root.CreateRadio = add("title"), add("radio")
        return root
    end

    env.Menu = { ModifyMenu = function(name, fn)
        client.menuModifiers[name] = client.menuModifiers[name] or {}
        table.insert(client.menuModifiers[name], fn)
    end }
    -- The player opens one of the game's menus: Blizzard runs each modifier; anything one
    -- writes into the description is addon-written data the gamepad registration reads.
    function client:PlayerOpensGameMenu(name, owner, contextData)
        local root = Root()
        for _, fn in ipairs(self.menuModifiers[name] or {}) do fn(owner or {}, root, contextData or {}) end
        if #root.items > 0 then Taint("entry in a game menu", name) end
        return root.items
    end

    env.MenuUtil = { CreateContextMenu = function(owner)
        Taint("context menu built with the game's menu system", owner and owner.GetName and owner:GetName())
        return setmetatable({}, { __index = function() return function() end end })
    end }
    env.StaticPopup_Show = function(name) Taint("popup", name) end

    for _, name in ipairs({ "ShowUIPanel", "HideUIPanel", "ToggleQuestLog", "QuestMapFrame_OpenToQuestDetails", "ToggleWorldMap",
                            "OpenWorldMap", "ToggleBackpack", "OpenAllBags", "CloseAllBags" }) do
        local original = env[name]
        env[name] = function(...)
            Taint("a game panel opened or closed from addon code", name)
            if original then return original(...) end
        end
    end

    -- SmartNavigation's CreateFrame hook: a frame made under the open world map.
    local create = env.CreateFrame
    env.CreateFrame = function(kind, name, parent, ...)
        local f = create(kind, name, parent, ...)
        local map = env.WorldMapFrame
        if parent and map and map:IsShown() then
            local p = parent
            while p do
                if p == map then
                    Taint("frame made under the open world map", name or kind)
                    break
                end
                p = p.GetParent and p:GetParent() or nil
            end
        end
        return f
    end
end

return GamepadUI
