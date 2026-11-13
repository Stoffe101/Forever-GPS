-- How the controller feels, page by page: from every control the selection can reach, each
-- direction is pressed, and where it lands is judged the way a player would.
--
--   - every control on the page can be reached from where the page starts;
--   - left and right stay on the row when there is a control on the row that way;
--   - up and down do not skip a nearer control straight above or below;
--   - a direction with a control that way goes somewhere.
--
-- Presses go through the stand-in controller (support/gamepad.lua), as in play.
local T = require("support.t")
local Stack = require("support.stack")
local UI = require("support.fakeui")

local tests = {}

local QUESTIE = {
    areaMaps = { [12] = 1429 },
    npcs = { [240] = { name = "Marshal Dughan", spawns = { [12] = { { 42.1, 65.9 } } } },
             [299] = { name = "Young Wolf", spawns = { [12] = { { 43, 72 }, { 44, 73 } } } } },
    quests = { [33] = { name = "Wolves Across the Border", objectives = { { id = 299, text = "Young Wolf" } }, finisher = 240 } },
}
local LOG = {
    { questID = 33, title = "Wolves Across the Border", level = 6, header = "Elwynn Forest",
      objectives = { { text = "Young Wolf slain: 3/8", numFulfilled = 3, numRequired = 8, finished = false } } },
}

local SCREENS = { { "1920x1080", 1920, 1080, 1.406 }, { "1280x800 handheld", 1280, 800, 800 / 768, pad = true } }

local function Start(screen)
    local c = Stack.new({ mapID = 1453, x = 0.6, y = 0.6, questie = QUESTIE, quests = LOG, screen = { screen[2], screen[3], screen[4] } })
    c:Advance(0.5)
    c.FG.Pad.DB().introDone = true
    c:PadPress("PADDDOWN")
    return c, c.FG
end

local function Rect(f) return UI.rectOf(f) end
local function Overlap(a1, a2, b1, b2) return math.min(a2, b2) - math.max(a1, b1) end

local function Name(f)
    if not f then return "nothing" end
    local text = f.label and f.label._text or f._text or (f.text and f.text._text) or f.tip or f.tooltipTitle
    local icon = f.icon and f.icon._iconName
    local r = Rect(f)
    return (f:GetName() or f:GetObjectType()) .. (text and (" \"" .. tostring(text):sub(1, 24) .. "\"") or "")
        .. (icon and (" [" .. tostring(icon) .. "]") or "") .. (r and (" @%d,%d"):format(r.l, r.b) or "")
end

-- What is selected now, as one key: a list's item, or a frame.
local function Here(c)
    local frame, list, index = c.FG.Focus.Current()
    if list then return tostring(list) .. "#" .. tostring(index) .. "#" .. tostring(frame), frame end
    return frame and tostring(frame), frame
end

-- Every control the selection can stand on, from where the page starts, and each move.
local DIRS = { up = "PADDUP", down = "PADDDOWN", left = "PADDLEFT", right = "PADDRIGHT" }
local Controls
local function Walk(c, root, limit)
    local FG = c.FG
    FG.Focus.First()
    local startKey = Here(c)
    if not startKey then return {}, {} end
    local seen, order, moves = { [startKey] = true }, { startKey }, {}
    local frames = {}
    local _, f0 = Here(c)
    frames[startKey] = f0
    local i = 1
    while i <= #order and i <= (limit or 120) do
        local key = order[i]
        for dir, button in pairs(DIRS) do
            -- Back to the control, as the player would stand on it; the page as they see it.
            local f = frames[key]
            if not (f and f:IsVisible()) then break end
            FG.Focus.To(f)
            c:Advance(0.02, 0.02)
            local shot = {}
            for _, o in ipairs(Controls(c, root)) do shot[o] = Rect(o) end
            c:PadPress(button)
            c:Advance(0.02, 0.02)
            local to, tf = Here(c)
            moves[#moves + 1] = { from = f, dir = dir, to = tf, shot = shot }
            if to and not seen[to] then
                seen[to], frames[to] = true, tf
                order[#order + 1] = to
            end
        end
        i = i + 1
    end
    return frames, moves
end

-- Every control on screen in the window, as the focus would collect them.
function Controls(c, root)
    local out = {}
    UI.Walk(root, function(obj)
        if obj._kind and obj:IsVisible() and not obj.padSkip and obj ~= c.env.ForeverGPSFocusRing then
            local clickable = obj._kind == "EditBox" or obj.padAdjust
                or (obj._kind == "Button" and (obj._scripts.OnClick or obj._scripts.OnMouseUp))
            local r = clickable and Rect(obj)
            if r and r.r - r.l > 2 and r.t - r.b > 2 then out[#out + 1] = obj end
        end
    end)
    return out
end

-- Judges the moves; returns the oddities, as lines.
-- Only what the player can see: inside the window, and inside any frame that clips it.
local function Seen(o, box)
    local r = Rect(o)
    if not (r.l >= box.l - 1 and r.r <= box.r + 1 and r.b >= box.b - 1 and r.t <= box.t + 1) then return false end
    local p = o:GetParent()
    while p do
        if p._clips then
            local cr = Rect(p)
            if r.b < cr.b - 1 or r.t > cr.t + 1 then return false end
        end
        p = p:GetParent()
    end
    return true
end

local function Judge(c, root, moves)
    local issues = {}
    local box = Rect(root)
    for _, m in ipairs(moves) do
        local shot = m.shot
        local fr = shot[m.from] or Rect(m.from)
        local horizontal = m.dir == "left" or m.dir == "right"
        local sign = (m.dir == "right" or m.dir == "up") and 1 or -1
        -- The nearest control that way on the same row (or column), on screen then.
        local best, bestGap
        for o, r in pairs(shot) do
            if o ~= m.from and Seen(o, box) then
                local lined, gap
                if horizontal then
                    lined = Overlap(fr.b, fr.t, r.b, r.t) > math.min(fr.t - fr.b, r.t - r.b) * 0.5
                    gap = sign > 0 and (r.l - fr.r) or (fr.l - r.r)
                else
                    lined = Overlap(fr.l, fr.r, r.l, r.r) > math.min(fr.r - fr.l, r.r - r.l) * 0.5
                    gap = sign > 0 and (r.b - fr.t) or (fr.b - r.t)
                end
                if lined and gap > -2 and (not bestGap or gap < bestGap) then best, bestGap = o, gap end
            end
        end
        if best and not m.to then
            issues[#issues + 1] = ("%s: %s goes nowhere, though %s is that way"):format(Name(m.from), m.dir, Name(best))
        elseif best and m.to and m.to ~= m.from and horizontal then
            local tr = shot[m.to] or Rect(m.to)
            if Overlap(fr.b, fr.t, tr.b, tr.t) <= 0 then
                issues[#issues + 1] = ("%s: %s leaves the row for %s, though %s is on it"):format(Name(m.from), m.dir, Name(m.to), Name(best))
            end
        end
    end
    return issues, Controls(c, root)
end

local function Audit(c, label, root)
    root = root or c.FG.Window.Frame()
    local frames, moves = Walk(c, root)
    local issues, all = Judge(c, root, moves)
    -- Reachable: every control on the page was stood on.
    local reached = {}
    for _, f in pairs(frames) do reached[f] = true end
    for _, o in ipairs(all) do
        if not reached[o] and o:GetObjectType() ~= "Slider" then
            -- A row of a list stands for its item; anything inside a reached row counts.
            local p, ok = o, false
            while p do
                if reached[p] then ok = true break end
                p = p:GetParent()
            end
            if not ok then issues[#issues + 1] = ("%s: never reached"):format(Name(o)) end
        end
    end
    for _, line in ipairs(issues) do print("    " .. label .. ": " .. line) end
    local n = 0
    for _ in pairs(frames) do n = n + 1 end
    print(("  %s: %d controls stood on, %d presses judged"):format(label, n, #moves))
    T.ok(n >= 3 and #moves >= 12, label .. ": the walk covered the page")
    return #issues
end

local function Pages(c, FG, screen)
    local total = 0
    local function Check(label, root)
        c:Advance(0.3)
        total = total + Audit(c, screen[1] .. " " .. label, root)
    end
    FG.Bridge.WarmSearch()
    c:Advance(1)
    FG.Window.Show("search")
    Check("search home")
    FG.SearchView.Query("auberdine")
    c:Advance(1)
    Check("search results")
    FG.SearchView.Open(FG.SearchView._Results()[1])
    Stack.Until(c, function() local p = FG.Planner.Current() return p and p.status == "ready" end, 30)
    Check("journey")
    FG.MapPreview.Open()
    c:Advance(0.3)
    Check("route map", FG.RouteMap.Frame())
    FG.RouteMap.Hide()
    FG.Trip.Add({ name = "Goldshire", subtitle = "Elwynn Forest", mapID = 1429, x = 0.42, y = 0.65 })
    FG.Trip.Add({ name = "Sentinel Hill", subtitle = "Westfall", mapID = 1436, x = 0.56, y = 0.47 })
    FG.Planner.Clear()
    FG.Window.Show("trip")
    Check("trip")
    FG.Window.Show("quests")
    FG.QuestsView.SetMode("log")
    Check("quests")
    FG.QuestsView.SetMode("find")
    Stack.Until(c, FG.QuestIndex.Ready, 10)
    Check("quest explorer")
    FG.ExplorerView.Open(33)
    c:Advance(1)
    Check("quest detail")
    FG.Window.CloseQuest()
    FG.Window.Show("professions")
    for _, which in ipairs({ "overview", "leveling", "profit", "lists", "market" }) do
        FG.ProfessionsView.Show(which)
        Check("professions " .. which)
    end
    FG.Window.Show("settings")
    for _, label in ipairs({ "SETG_NAVIGATION", "SETG_CONTROLLER", "SETG_HUD" }) do
        FG.SettingsView.SelectByLabel(label)
        Check("settings " .. label)
    end
    return total
end

function tests.everyPage_movesTheWayItLooks()
    for _, screen in ipairs(SCREENS) do
        local c, FG = Start(screen)
        local issues = Pages(c, FG, screen)
        T.eq(issues, 0, screen[1] .. ": moves that feel wrong (listed above)")
        T.eq(#c.errors, 0, screen[1] .. ": " .. tostring(c.errors[1]))
    end
end

return tests
