-- The real interface in the layout-solving fake, at every screen the brief names.
-- The third number is pixels per UI unit. In the game that is (height / 768) times
-- the UI scale, which runs from 0.64 to 1.15, and an addon can set less: the 3440x1440
-- install this was built for keeps UIParent at 3440 by 1440. So the real range is
-- covered, and the reading of "GUI scale 3" as three pixels per unit is kept as a
-- worst case tighter than the game goes. Text widths are estimates on the wide side:
-- a pass means the layout has room, not that it matches the game to the pixel.
local T = require("support.t")
local Stack = require("support.stack")

local UI = require("support.fakeui")

local SCREENS = {
    { "3440x1440 at 2 px per unit", 3440, 1440, 2 }, { "3440x1440 at 3 px per unit", 3440, 1440, 3 },
    { "1920x1080 at 2 px per unit", 1920, 1080, 2 }, { "1920x1080 at 3 px per unit", 1920, 1080, 3 },
    { "1920x1080 at 1 px per unit", 1920, 1080, 1 }, { "2560x1440 at 1 px per unit", 2560, 1440, 1 },
    { "3440x1440 at 1 px per unit", 3440, 1440, 1 },
    { "3440x1440 default", 3440, 1440, 1.875 }, { "1920x1080 default", 1920, 1080, 1.406 },
    { "1920x1080 largest", 1920, 1080, 1.617 }, { "1920x1080 smallest", 1920, 1080, 0.9 },
}

local QUESTIE = {
    areaMaps = { [12] = 1429 },
    npcs = {
        [299] = { name = "Young Wolf", spawns = { [12] = { { 43, 72 }, { 44, 73 } } } },
        [240] = { name = "Marshal Dughan", spawns = { [12] = { { 42.1, 65.9 } } } },
    },
    quests = { [33] = { name = "Wolves Across the Border", objectives = { { id = 299, text = "Young Wolf" } }, finisher = 240 } },
}

local LOG = {
    { questID = 33, title = "Wolves Across the Border", level = 6, header = "Elwynn Forest",
      objectives = { { text = "Young Wolf slain: 3/8", numFulfilled = 3, numRequired = 8, finished = false } } },
    { questID = 99, title = "A Quest With Quite a Long Title That Has to Fit Somewhere", level = 60, header = "Westfall",
      objectives = { { text = "An objective that also runs on for rather a long way before it finally ends: 0/1", numFulfilled = 0, numRequired = 1, finished = false } } },
}

local function Start(screen, opts)
    opts = opts or {}
    opts.screen = { screen[2], screen[3], screen[4] }
    opts.mapID, opts.x, opts.y = 1453, 0.6, 0.6
    opts.questie, opts.quests = QUESTIE, LOG
    local c = Stack.new(opts)
    c.UI.conflicts = {}
    return c
end

local function Rect(obj) return UI.rectOf(obj) end

-- Whether a is inside b, a pixel's grace.
local function Inside(a, b)
    return a.l >= b.l - 1 and a.r <= b.r + 1 and a.b >= b.b - 1 and a.t <= b.t + 1
end

-- Everything shown under frame, outside a clipping frame's own scroll.
local function Visible(frame, visit, clipped)
    for _, region in ipairs(frame._regions) do
        if region._shown then visit(region, clipped) end
    end
    for _, child in ipairs(frame._children) do
        if child._shown then
            -- Inside a clipping frame, a row past its edge is simply not seen.
            visit(child, clipped or frame._clips)
            Visible(child, visit, clipped or frame._clips)
        end
    end
end

local function Check(c, name, frame)
    local window = frame or c.env.ForeverGPSWindow
    local screen = c.root._rect
    local box = Rect(window)
    T.ok(box, name .. ": the window resolves")
    T.ok(Inside(box, screen), ("%s: window inside the screen (%d by %d of %d by %d)"):format(name, box.r - box.l, box.t - box.b, screen.r, screen.t))
    local buttons = {}
    Visible(window, function(obj, clipped)
        local r = Rect(obj)
        if r and not clipped then
            local text = obj._kind == "FontString" and (obj._text or "") ~= ""
            if text or obj._kind == "Button" then
                T.ok(Inside(r, box), ("%s: %s %q leaves the window"):format(name, obj._kind, tostring(obj._text or "")))
            end
            if obj._kind == "Button" and r.r - r.l > 1 then buttons[#buttons + 1] = { obj = obj, r = r } end
        end
    end)
    for i = 1, #buttons do
        for j = i + 1, #buttons do
            local a, b = buttons[i], buttons[j]
            if a.obj._parent == b.obj._parent then
                local apart = a.r.r <= b.r.l + 1 or b.r.r <= a.r.l + 1 or a.r.t <= b.r.b + 1 or b.r.t <= a.r.b + 1
                T.ok(apart, ("%s: controls overlap: %q and %q"):format(name, tostring(a.obj._text or (a.obj.label and a.obj.label._text)),
                    tostring(b.obj._text or (b.obj.label and b.obj.label._text))))
            end
        end
    end
    local bad = {}
    for key in pairs(c.UI.conflicts) do bad[#bad + 1] = key end
    T.eq(#bad, 0, name .. ": over-constrained anchors: " .. table.concat(bad, "; "))
end

local function Ready(c)
    local FG = c.FG
    return Stack.Until(c, function()
        local p = FG.Planner.Current()
        return p and (p.status == "ready" or p.status == "failed" or p.status == "unreachable")
    end, 30)
end

local tests = {}

function tests.everyView_fitsEveryScreen()
    for _, screen in ipairs(SCREENS) do
        local c = Start(screen)
        local FG = c.FG
        FG.Bridge.WarmSearch()
        c:Advance(1)
        FG.Window.Show("search")
        c:Advance(0.5)
        Check(c, screen[1] .. " home")
        FG.SearchView.Query("repair")
        c:Advance(1)
        Check(c, screen[1] .. " results")
        FG.Window.Show("search")
        FG.SearchView.Query("auberdine")
        c:Advance(1)
        FG.SearchView.Open(FG.SearchView._Results()[1])
        T.ok(Ready(c), "planned")
        c:Advance(0.3)
        Check(c, screen[1] .. " journey")
        FG.Window.Show("quests")
        FG.QuestsView.Toggle(33)
        FG.QuestsView.Toggle(99)
        c:Advance(1)
        Check(c, screen[1] .. " quests")
        FG.Window.Show("settings")
        c:Advance(0.3)
        Check(c, screen[1] .. " settings")
        T.eq(#c.errors, 0, screen[1] .. ": " .. tostring(c.errors[1]))
    end
end

function tests.aSmallScreen_usesOneColumnAndNothingIsLost()
    local c = Start(SCREENS[4])
    local FG = c.FG
    FG.Window.Show("search")
    c:Advance(0.5)
    T.ok(FG.Window.IsCompact(), "640 units wide: one column")
    local W = FG.Window.Frame()
    T.ok(W.left:IsShown(), "the list first")
    T.no(W.right:IsShown(), "the journey waits")
    FG.SearchView.Query("auberdine")
    c:Advance(1)
    FG.SearchView.Open(FG.SearchView._Results()[1])
    T.ok(Ready(c), "planned")
    c:Advance(0.3)
    T.ok(W.right:IsShown(), "the journey takes the window")
    T.no(W.left:IsShown(), "from the list")
    T.ok(W.route.backButton:IsShown(), "with a way back")
    W.route.backButton:Click()
    c:Advance(0.3)
    T.ok(W.left:IsShown(), "back to the list")
end

function tests.aSmallScreen_stillShowsSeveralSteps()
    local c = Start(SCREENS[4])
    local FG = c.FG
    FG.Window.Show("search")
    FG.Planner.Inspect({ data = { name = "Auberdine", mapID = 1439, x = 0.37, y = 0.44 }, name = "Auberdine" })
    FG.Window.ShowRoute()
    T.ok(Ready(c), "planned")
    c:Advance(0.3)
    local W = FG.Window.Frame()
    local shown = 0
    Visible(W.route, function(obj)
        if obj._kind == "FontString" and tostring(obj._text):find("Board the boat", 1, true) then shown = shown + 1 end
    end)
    T.ok(shown > 0, "the boat step is on screen at 640 by 360")
end

function tests.aSmallScreen_reopensOnTheJourneyUnderWay()
    local c = Start(SCREENS[4])
    local FG = c.FG
    FG.Planner.Inspect({ data = { name = "Auberdine", mapID = 1439, x = 0.37, y = 0.44 }, name = "Auberdine" })
    T.ok(Ready(c), "planned")
    FG.Planner.Start()
    c:Advance(0.5)
    FG.Planner.Clear()
    FG.Toggle()
    c:Advance(0.3)
    local W = FG.Window.Frame()
    T.ok(W.right:IsShown(), "the journey, not the list")
    T.has(W.route.title:GetText(), "Auberdine", "and its destination")
end

function tests.easyFindsBar_comesBackWhenAskedFor()
    local c = Start(SCREENS[3])
    local B = c.FG.Bridge
    T.no(B.EasyFindBar(), "off by default")
    B.SetEasyFindBar(true)
    T.ok(B.EasyFindBar(), "on")
    B.SetEasyFindBar(false)
    T.no(B.EasyFindBar(), "off again")
    T.eq(#c.errors, 0, tostring(c.errors[1]))
end

function tests.aLargeScreen_usesTwoColumns()
    local c = Start(SCREENS[1])
    c.FG.Window.Show("search")
    c:Advance(0.5)
    T.no(c.FG.Window.IsCompact(), "side by side")
    local W = c.FG.Window.Frame()
    T.ok(W.left:IsShown() and W.right:IsShown(), "both")
end

function tests.theHud_fitsEveryScreenAndStaysUnderTheScreenTop()
    for _, screen in ipairs(SCREENS) do
        local c = Start(screen)
        local FG = c.FG
        FG.Planner.Inspect({ data = { name = "Auberdine", mapID = 1439, x = 0.37, y = 0.44 }, name = "Auberdine" })
        T.ok(Ready(c), "planned")
        FG.Planner.Start()
        c:Advance(0.5)
        local hud = c.env.ForeverGPSHUD
        T.ok(hud:IsShown(), "shown")
        local box, s = Rect(hud), c.root._rect
        T.ok(Inside(box, s), screen[1] .. ": HUD inside the screen")
        Visible(hud, function(obj, clipped)
            local r = Rect(obj)
            if r and obj._kind == "FontString" and (obj._text or "") ~= "" and not clipped then
                T.ok(r.b >= box.b - 1 and r.t <= box.t + 1, screen[1] .. ": HUD text inside the card: " .. obj._text)
            end
        end)
        T.eq(#c.errors, 0, screen[1])
    end
end

function tests.theWindow_doesNotNeedToStayOpen()
    local c = Start(SCREENS[3])
    local FG = c.FG
    FG.Window.Show("search")
    FG.Planner.Inspect({ data = { name = "Auberdine", mapID = 1439, x = 0.37, y = 0.44 }, name = "Auberdine" })
    T.ok(Ready(c), "planned")
    FG.RoutePanel.Go()
    c:Advance(0.5)
    T.no(FG.Window.IsShown(), "it closes on starting")
    T.ok(c.env.ForeverGPSHUD:IsShown(), "and the HUD takes over")
end

function tests.searchFromTheBox_runsAfterTyping()
    local c = Start(SCREENS[3])
    local FG = c.FG
    FG.Window.Show("search")
    local box = c.env.ForeverGPSSearchBox
    box._text = "auberdine"
    box._scripts.OnTextChanged(box, true)
    T.eq(#FG.SearchView._Results(), 0, "not on every keystroke")
    c:Advance(0.3)
    T.ok(#FG.SearchView._Results() > 0, "just after typing stops")
end

function tests.theKeyboard_movesAndChooses()
    local c = Start(SCREENS[3])
    local FG = c.FG
    FG.Window.Show("search")
    FG.SearchView.Query("auberdine")
    c:Advance(1)
    local box = c.env.ForeverGPSSearchBox
    box._scripts.OnArrowPressed(box, "DOWN")
    box._scripts.OnEnterPressed(box)
    T.ok(FG.Planner.Current(), "Enter opens the journey")
end

function tests.escape_clearsThenLetsGo()
    local c = Start(SCREENS[3])
    local FG = c.FG
    FG.Window.Show("search")
    local box = c.env.ForeverGPSSearchBox
    box:SetText("auberdine")
    box._scripts.OnEscapePressed(box)
    T.eq(box:GetText(), "", "first it clears")
    T.ok(box:HasFocus(), "keeping focus")
    box._scripts.OnEscapePressed(box)
    T.no(box:HasFocus(), "then it lets go")
    local found = false
    for _, name in ipairs(c.env.UISpecialFrames) do found = found or name == "ForeverGPSWindow" end
    T.ok(found, "and Escape closes the window")
end

function tests.quests_openIntoTheirTargets()
    local c = Start(SCREENS[3])
    local FG = c.FG
    FG.Window.Show("quests")
    FG.QuestsView.Toggle(33)
    c:Advance(1)
    local list = FG.Window.Frame().questsPage.list
    local objective, turnIn
    for _, item in ipairs(list.items) do
        if item.kind == "target" and item.objective then objective = item end
        if item.kind == "target" and item.target.kind == "turnin" then turnIn = item end
    end
    T.ok(objective and objective.target.best, "the objective has a place")
    T.ok(turnIn and turnIn.target.best, "and so does the turn-in")
    FG.QuestsView.Go(objective)
    T.ok(Ready(c), "directions plan a journey")
    T.has(FG.Planner.Current().target.name, "Wolves Across the Border", "named for the quest")
end

function tests.aQuestsQuickButton_goesToWhatIsNext()
    local c = Start(SCREENS[3])
    local FG = c.FG
    FG.Window.Show("quests")
    c:Advance(0.3)
    FG.QuestsView.GoNext(FG.Quests.Get(33))
    T.ok(Ready(c), "plans the journey")
    T.eq(FG.Planner.Current().target.binding.kind, "objective", "to the open objective")
end

function tests.aQuestsQuickButton_opensAQuestWithNowhereToGo()
    local c = Start(SCREENS[3])
    local FG = c.FG
    FG.Window.Show("quests")
    c:Advance(0.3)
    FG.QuestsView.GoNext(FG.Quests.Get(99))
    c:Advance(0.5)
    T.no(FG.Planner.Current(), "no journey is invented")
    local shown = false
    for _, item in ipairs(FG.Window.Frame().questsPage.list.items) do
        if item.kind == "target" and item.quest.questID == 99 then shown = true end
    end
    T.ok(shown, "it opens to say why")
end

function tests.aQuestWithNoPlace_offersNoDirections()
    local c = Start(SCREENS[3])
    local FG = c.FG
    FG.Window.Show("quests")
    FG.QuestsView.Toggle(99)
    c:Advance(1)
    local found
    for _, item in ipairs(FG.Window.Frame().questsPage.list.items) do
        if item.kind == "target" and item.quest.questID == 99 and item.objective then found = item end
    end
    T.ok(found, "the objective is listed")
    T.no(found.target.best, "with nowhere to go")
    T.has(found.target.reason, "No reliable location", "and it says so")
end

-- Every control the page lists is a real size, on the page and clear of the rest.
function tests.settings_everyControlIsThereToUse()
    for _, screen in ipairs(SCREENS) do
        local c = Start(screen)
        local FG = c.FG
        FG.Window.Show("settings")
        c:Advance(0.3)
        local page = FG.Window.Frame().settingsPage
        local box = Rect(page)
        local seen = 0
        for index, group in ipairs(FG.SettingsView.Groups()) do
            FG.SettingsView.Select(index)
            for _, item in ipairs(group.items) do
                FG.SettingsView.Reveal(item)
                local r = Rect(item.widget)
                T.ok(r, screen[1] .. ": a settings row resolves")
                if item.sizing ~= "own" then
                    T.ok(r.r - r.l >= 100, ("%s: a settings row is %d wide"):format(screen[1], r.r - r.l))
                end
                T.ok(r.t - r.b >= 8, screen[1] .. ": and has height")
                T.ok(Inside(r, box), ("%s: %s on the page"):format(screen[1], group.label))
                seen = seen + 1
            end
        end
        T.ok(seen >= 25, "the page has its controls: " .. seen)
        T.eq(#c.errors, 0, "and none of them raised")
    end
end

function tests.settings_switchesDoWhatTheySay()
    local c = Start(SCREENS[3])
    local FG = c.FG
    FG.Window.Show("settings")
    c:Advance(0.3)
    local hud
    for index, group in ipairs(FG.SettingsView.Groups()) do
        FG.SettingsView.Select(index)
        for _, item in ipairs(group.items) do
            if item.widget.label and item.widget.label._text == FG.L["SET_HUD"] then hud = item.widget end
        end
        if hud then break end
    end
    T.ok(hud, "the HUD switch is on the page")
    hud:Click()
    T.no(FG.db.hud.enabled, "off")
    hud:Click()
    T.ok(FG.db.hud.enabled, "and on")
end

-- Finds a slider by the heading above it.
local function SliderUnder(FG, headingKey)
    for index, group in ipairs(FG.SettingsView.Groups()) do
        FG.SettingsView.Select(index)
        for i, item in ipairs(group.items) do
            if item.widget._text == FG.L[headingKey] then return group.items[i + 1], index end
        end
    end
end

function tests.sliders_haveAKnobAndAValueAndWork()
    for _, screen in ipairs(SCREENS) do
        local c = Start(screen)
        local FG = c.FG
        FG.Window.Show("settings")
        c:Advance(0.3)
        local item = SliderUnder(FG, "SET_HUD_SCALE")
        T.ok(item, "the slider is there")
        FG.SettingsView.Reveal(item)
        local s = item.widget
        local knob, track = Rect(s.knob), Rect(s.track)
        T.ok(knob and knob.r - knob.l >= 8, screen[1] .. ": the knob can be seen")
        T.ok(track and track.r - track.l >= 60, screen[1] .. ": the track has room")
        T.ok(knob.l >= track.l - 8 and knob.r <= track.r + 8, screen[1] .. ": the knob sits on the track")
        local start = FG.Settings.HudScale()
        T.eq(s.value._text, ("%d%%"):format(start * 100 + 0.5), "the value is written beside it")
        s._scripts.OnMouseWheel(s, 1)
        T.near(FG.db.hud.scale, start + 0.05, 0.001, "the wheel moves it")
        local moved = Rect(s.knob)
        T.ok(moved.l > knob.l, "and the knob with it")
        T.eq(s.value._text, ("%d%%"):format(start * 100 + 5.5))
        -- A press at the far end of the track.
        local scale = s:GetEffectiveScale()
        c.env.GetCursorPosition = function() return (track.r + 50) * 1, 0 end
        s._scripts.OnMouseDown(s, "LeftButton")
        s._scripts.OnMouseUp(s, "LeftButton")
        T.near(FG.db.hud.scale, 1.6, 0.001, "a press past the end stops at the end (scale " .. scale .. ")")
        T.eq(#c.errors, 0)
    end
end

function tests.settings_reachWhatTheySay()
    local c = Start(SCREENS[3])
    local FG = c.FG
    FG.Window.Show("settings")
    c:Advance(0.3)
    -- The rail changes the page, and what was on it leaves.
    FG.SettingsView.Select(6)
    local first = FG.SettingsView.Groups()[6].items[1].widget
    T.ok(first:IsVisible(), "the group shows")
    FG.SettingsView.Select(1)
    T.no(first:IsVisible(), "and goes when another is chosen")
    FG.Saved.AddRecent({ data = { name = "Somewhere", mapID = 1429, x = 0.5, y = 0.5 }, name = "Somewhere" })
    T.eq(#FG.Saved.Recents(), 1)
    FG.Saved.ClearRecents()
    T.eq(#FG.Saved.Recents(), 0, "clearing recents clears them")
end

function tests.theHud_fitsInEveryMode()
    for _, screen in ipairs(SCREENS) do
        for _, mode in ipairs({ "compact", "standard", "detailed" }) do
            local c = Start(screen)
            local FG = c.FG
            FG.db.hud.mode = mode
            FG.Planner.Inspect({ data = { name = "Auberdine", mapID = 1439, x = 0.37, y = 0.44 }, name = "Auberdine" })
            Ready(c)
            FG.Planner.Start()
            c:Advance(0.5)
            local hud = c.env.ForeverGPSHUD
            T.ok(hud:IsVisible(), screen[1] .. " " .. mode .. ": shown")
            Check(c, screen[1] .. " " .. mode, hud)
            local r, s = Rect(hud), c.env.UIParent
            T.ok(r.r - r.l <= s:GetWidth() * s:GetEffectiveScale() + 1, "no wider than the screen")
            local text = 0
            Visible(hud, function(obj)
                if obj._kind == "FontString" and (obj._text or "") ~= "" then text = text + 1 end
            end)
            T.ok(text >= 2, mode .. " says something")
        end
    end
end

function tests.theHud_showsLessWhenCompactAndMoreWhenDetailed()
    local c = Start(SCREENS[3])
    local FG = c.FG
    FG.Planner.Inspect({ data = { name = "Auberdine", mapID = 1439, x = 0.37, y = 0.44 }, name = "Auberdine" })
    Ready(c)
    FG.Planner.Start()
    c:Advance(0.5)
    local hud = c.env.ForeverGPSHUD
    local function Set(mode)
        FG.db.hud.mode = mode
        FG.Emit("settings:changed")
        return Rect(hud)
    end
    local compact = Set("compact")
    T.no(hud.nextLine:IsShown(), "compact has no next step")
    local detailed = Set("detailed")
    T.ok(hud.nextLine:IsShown(), "detailed does")
    T.ok(detailed.r - detailed.l > compact.r - compact.l, "and it is wider")
    FG.db.hud.showEta = false
    FG.Emit("settings:changed")
    T.lacks(hud.meta._text, "left", "the time left can be turned off")
end

function tests.theHudArrow_turnsWithoutTwitching()
    local c = Start(SCREENS[3])
    c.FG.HUD.Render({ state = "moving", title = "x", icon = c.FG.ART .. "walk" })
    local Eased = c.FG.HUD._Eased
    T.near(Eased(1, 0.03), 1, 0.001, "starts on its aim")
end

function tests.news_outlivesTheRouteItSpeaksOf()
    local c = Start(SCREENS[3])
    local FG = c.FG
    FG.Emit("toast", "Something happened", nil, nil, true)
    c:Advance(0.5)
    local toast = FG.HUD.ToastFrame()
    T.ok(toast:IsVisible(), "seen with no route and no HUD")
    T.has(toast.text._text, "Something happened")
    Check(c, "toast", toast)
    c:Advance(7)
    T.no(toast:IsVisible(), "and goes by itself")
end

function tests.quickNavigation_typesAndGoes()
    local c = Start(SCREENS[3])
    local FG = c.FG
    FG.Quick.Open("auberdine")
    c:Advance(0.5)
    local quick = c.env.ForeverGPSQuick
    T.ok(quick:IsVisible(), "the box opens")
    T.ok(#FG.Quick._Results() > 0, "and finds it")
    Check(c, "quick", quick)
    FG.Quick.Choose()
    T.no(quick:IsVisible(), "goes away once chosen")
    T.ok(Stack.Until(c, function() return FG.Bridge.ActiveRoute() ~= nil end, 30), "and navigation starts")
    T.no(FG.Window.IsShown(), "without the window")
end

function tests.quickNavigation_canLookFirst()
    local c = Start(SCREENS[3])
    local FG = c.FG
    FG.Quick.Open("auberdine")
    c:Advance(0.5)
    FG.Quick.Choose(1, true)
    c:Advance(1)
    T.ok(FG.Window.IsShown(), "the journey to look over")
    Ready(c)
    T.no(FG.Bridge.ActiveRoute(), "and nothing has started")
end

function tests.theMinimapButton_doesWhatItSays()
    local c = Start(SCREENS[3])
    local FG = c.FG
    c:Advance(0.2)
    local b = c.env.ForeverGPSMinimapButton
    T.ok(b and b:IsVisible(), "there by default")
    b._scripts.OnClick(b, "LeftButton")
    T.ok(FG.Window.IsShown(), "left click opens")
    b._scripts.OnClick(b, "RightButton")
    T.ok(c.env.ForeverGPSQuick:IsVisible(), "right click goes quick")
    FG.db.minimap.shown = false
    FG.Emit("settings:changed")
    T.no(b:IsVisible(), "and it can go")
end

function tests.theCopyBox_fitsAndHoldsNothingPersonal()
    for _, screen in ipairs(SCREENS) do
        local c = Start(screen)
        local FG = c.FG
        local text = FG.Diagnostics.Report()
        FG.CopyBox.Show(text)
        c:Advance(0.2)
        Check(c, "copy box", c.env.ForeverGPSCopyBox)
        T.has(text, "Forever-GPS report")
        T.has(text, "Route engine ready")
        T.lacks(text, c.env.UnitName("player"), "no character name")
        T.lacks(text, c.env.GetRealmName(), "no realm name")
    end
end

function tests.aTallInterface_getsLargerWindowsUntilTheyAreChosen()
    local c = Start({ "1px", 3440, 1440, 1 })
    local FG = c.FG
    T.eq(FG.Settings.WindowScale(), 1.25, "a window for 768 units would read small at 1440")
    FG.db.window.scale = 1
    T.eq(FG.Settings.WindowScale(), 1, "and a chosen size is kept")
    local normal = Start({ "default", 1920, 1080, 1.406 })
    T.eq(normal.FG.Settings.WindowScale(), 1, "a default interface stays as it is")
end

function tests.homeTiles_fitTheirLabels()
    local c = Start(SCREENS[3])
    local FG = c.FG
    FG.Window.Show("search")
    c:Advance(0.3)
    Visible(FG.Window.Frame().searchPage, function(obj)
        if obj._kind == "FontString" and (obj._text or "") ~= "" and obj.IsTruncated then
            T.no(obj:IsTruncated(), "a home label is cut off: " .. obj._text)
        end
    end)
end

function tests.themes_repaintEverything()
    local c = Start(SCREENS[3])
    local FG = c.FG
    FG.Window.Show("search")
    c:Advance(0.3)
    for _, name in ipairs({ "glacier", "parchment", "obsidian" }) do
        FG.Theme.Apply(name)
        c:Advance(0.1)
    end
    T.eq(#c.errors, 0, tostring(c.errors[1]))
end

function tests.savedPlaces_comeBack()
    local c = Start(SCREENS[3])
    local FG = c.FG
    FG.Window.Show("search")
    local W = FG.Window.Frame()
    W:SetSize(500, 300)
    FG.db.window.point = { "TOPLEFT", "TOPLEFT", 20, -20 }
    FG.db.hud.point = { "TOP", "TOP", 40, -40 }
    FG.Settings.ResetPlaces()
    T.no(FG.db.window.point, "reset forgets them")
    T.no(FG.db.hud.point)
end

function tests.aWindowSavedLargerThanTheScreen_isBroughtIn()
    local saved = { ForeverGPSDB = { window = { width = 3000, height = 2000, scale = 1 }, firstRunDone = true } }
    local c = Start(SCREENS[4], { saved = saved })
    c.FG.Window.Show("search")
    c:Advance(0.3)
    Check(c, "a saved size from a larger screen")
end

function tests.firstRun_startsWithoutEasyFindsWelcome()
    local c = Start(SCREENS[3])
    local db = c.env.EasyFind.db
    T.ok(db.tutorialDone, "no tutorial")
    T.eq(db.visible, false, "and no second search bar, until asked for")
    T.ok(c.FG.db.firstRunDone)
end

function tests.commands_work()
    local c = Start(SCREENS[3])
    local run = c.env.SlashCmdList["FOREVERGPS"]
    run("")
    T.ok(c.FG.Window.IsShown(), "/fgps opens")
    run("")
    T.no(c.FG.Window.IsShown(), "and closes")
    run("quests")
    T.ok(c.FG.Window.IsShown(), "/fgps quests")
    run("way 45 60")
    T.ok(Ready(c), "/fgps way")
    T.eq(c.FG.Planner.Current().target.data.mapID, 1453, "on the current map")
    run("way nowhere-at-all 45 60")
    T.has(table.concat(c.printed, "\n"), "No zone matches", "says so")
    run("way banana")
    T.has(table.concat(c.printed, "\n"), "/fgps way", "shows how")
    run("diag")
    T.has(table.concat(c.printed, "\n"), "build 70790", "/fgps diag reports the client")
    run("nonsense")
    T.has(table.concat(c.printed, "\n"), "/fgps stop", "and anything else shows the commands")
    T.eq(#c.errors, 0, tostring(c.errors[1]))
end

function tests.keyBindings_reachTheirFunctions()
    local c = Start(SCREENS[3])
    local FG = c.env.ForeverGPS
    T.eq(type(FG.Toggle), "function")
    T.eq(type(FG.OpenQuests), "function")
    T.eq(type(FG.StopNavigation), "function")
    T.eq(type(c.env.ForeverGPS_OnCompartmentClick), "function", "the addon compartment's")
end

return tests
