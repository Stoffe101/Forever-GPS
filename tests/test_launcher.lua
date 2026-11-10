-- One launcher: Forever-GPS's. EasyFind's own button, broker launcher and compartment
-- entries stayed in the folder until 2.3 and opened a search bar that stays hidden.
local T = require("support.t")
local Stack = require("support.stack")

local tests = {}

local function Start(opts)
    opts = opts or {}
    opts.launchers = true
    opts.mapID, opts.x, opts.y = 1453, 0.6, 0.6
    return Stack.new(opts)
end

local function Count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

function tests.afterLogin_nothingOfEasyFindsIsRegistered()
    local c = Start()
    c:Advance(5)
    for name in pairs(c.launchers.broker) do T.no(name:find("EasyFind", 1, true), "broker: " .. name) end
    for name in pairs(c.launchers.icons) do T.no(name:find("EasyFind", 1, true), "icon: " .. name) end
    for _, name in ipairs(c.launchers.compartment) do T.no(name:find("EasyFind", 1, true), "compartment: " .. name) end
    T.eq(Count(c.launchers.icons), 0, "no gatherer button at all")
    T.ok(c.env.ForeverGPSMinimapButton or c.FG.MinimapButton, "ours is there")
    T.eq(#c.errors, 0)
end

function tests.aReload_andEasyFindsOwnSwitch_doNotBringItBack()
    local c = Start()
    c:Advance(5)
    c.env.EasyFindDB.showMinimapButton = true
    c.env.EasyFind:UpdateMinimapButton()
    local d = Start({ saved = Stack.Saved(c) })
    d:Advance(5)
    T.eq(Count(d.launchers.broker), 0)
    T.eq(#d.launchers.compartment, 0)
    for _, f in pairs(d.named or {}) do
        local name = f.GetName and f:GetName() or ""
        if name:find("EasyFind", 1, true) and name:find("Minimap", 1, true) then T.no(f:IsShown(), name .. " shows") end
    end
end

function tests.slashCommand_stillOpensForeverGPS()
    local c = Start()
    c:Advance(1)
    c.env.SlashCmdList.FOREVERGPS("")
    T.ok(c.FG.Window.IsShown())
end

return tests
