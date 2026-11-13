-- The GPS windows sit on the game windows' layer (GPS.lua
-- GPS.RaiseLikeAWindow): over the bars, under a bag opened after them.
local H = require("Harness")

local function Source()
    local f = assert(io.open(H.Path("GPS.lua"), "rb"))
    local src = f:read("*a")
    f:close()
    return src
end

local function Body(src, head)
    local s = assert(src:find(head, 1, true), head .. " not in GPS.lua")
    local _, e = src:find("\nend\r?\n", s)
    return src:sub(s, e)
end

local tests = {}

function tests.thePopout_isAWindowAmongWindows()
    local body = Body(Source(), "local function BuildPopout()")
    H.assertTrue(body:find('f:SetFrameStrata("MEDIUM")', 1, true) ~= nil, "on the windows' layer")
    H.assertTrue(body:find("GPS.RaiseLikeAWindow(f)", 1, true) ~= nil, "raised on open and click")
    H.assertTrue(not body:find('SetFrameStrata("HIGH")', 1, true), "never over the bags")
end

function tests.theFloatingSection_isAWindowAmongWindows()
    local src = Source()
    H.assertTrue(Body(src, "local function BuildDock()"):find("GPS.RaiseLikeAWindow(f)", 1, true) ~= nil,
        "raised on open and click")
    local float = Body(src, "function GPS.FloatDockAt(left, top)")
    H.assertTrue(float:find('dockFrame:SetFrameStrata("MEDIUM")', 1, true) ~= nil, "on the windows' layer")
    H.assertTrue(float:find("dockFrame.Lift()", 1, true) ~= nil, "a docked section raised as it floats")
    H.assertTrue(not float:find('SetFrameStrata("HIGH")', 1, true), "never over the bags")
end

function tests.aClickInIt_raisesIt_andItsCastButtons()
    local src = Source()
    local body = Body(src, "function GPS.RaiseLikeAWindow(window)")
    local env = setmetatable({ GPS = {}, castButtons = {}, Utils = {} }, { __index = _G })
    local raised, registered = 0, {}
    env.Utils.RegisterEventIfValid = function(frame, event) registered[frame] = event end
    env.InCombatLockdown = function() return false end
    local function Frame(parent)
        local f = { parent = parent, scripts = {}, level = 10, shown = true }
        function f:GetParent() return self.parent end
        function f:IsForbidden() return false end
        function f:IsVisible() return true end
        function f:IsShown() return self.shown end
        function f:SetScript(name, fn) self.scripts[name] = fn end
        function f:UnregisterEvent() registered[self] = nil end
        function f:GetFrameLevel() return self.level end
        function f:SetFrameLevel(l) self.level = l end
        function f:Raise() raised = raised + 1 self.level = self.level + 100 end
        return f
    end
    env.CreateFrame = function(_, _, parent) return Frame(parent) end
    local window, bag = Frame(nil), Frame(nil)
    local row = Frame(window)
    local btn = Frame(nil)
    btn.row = row
    env.castButtons[1] = btn
    local focus
    env.GetMouseFoci = function() return { focus } end
    assert(load(body, "=GPS.lua RaiseLikeAWindow", "t", env))()
    env.GPS.RaiseLikeAWindow(window)
    local catch
    for f, event in pairs(registered) do
        if event == "GLOBAL_MOUSE_DOWN" then catch = f end
    end
    H.assertTrue(catch ~= nil, "a shown window hears clicks")
    focus = bag
    catch.scripts.OnEvent(catch)
    H.assertEq(raised, 0, "a click on a bag over it leaves it under")
    focus = row
    catch.scripts.OnEvent(catch)
    H.assertEq(raised, 1, "a click in it raises it")
    H.assertEq(btn.level, row.level + 3, "its cast button back over its row")
    window.docked = true
    catch.scripts.OnEvent(catch)
    H.assertEq(raised, 1, "a docked section stays in the tracker")
end

local pass, fail, failures = H.runSuite("GPSWindowLayer", tests)
return { pass = pass, fail = fail, failures = failures }
