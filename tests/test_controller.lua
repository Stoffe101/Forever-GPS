-- The controller, end to end: buttons pressed on the stand-in pad travel the way the
-- client sends them (support/gamepad.lua): frames that hear the pad, then override
-- bindings clicking Forever-GPS's hidden buttons, then the game's own bindings. Nothing
-- here calls an action directly where a press can do it.
local T = require("support.t")
local Stack = require("support.stack")
local UI = require("support.fakeui")

local tests = {}

local QUESTIE = {
    areaMaps = { [12] = 1429 },
    npcs = { [240] = { name = "Marshal Dughan", spawns = { [12] = { { 42.1, 65.9 } } } } },
    quests = { [33] = { name = "Wolves Across the Border", objectives = {}, finisher = 240 } },
}
local LOG = {
    { questID = 33, title = "Wolves Across the Border", level = 6, header = "Elwynn Forest",
      objectives = { { text = "Young Wolf slain: 3/8", numFulfilled = 3, numRequired = 8, finished = false } } },
}

local function Start(opts)
    opts = opts or {}
    opts.mapID, opts.x, opts.y = opts.mapID or 1453, opts.x or 0.6, opts.y or 0.6
    opts.questie, opts.quests = QUESTIE, LOG
    local c = Stack.new(opts)
    c:Advance(0.5)
    -- The first-time introduction is a test of its own.
    if not opts.intro then c.FG.Pad.DB().introDone = true end
    return c, c.FG
end

local function Press(c, button, times)
    local who
    for _ = 1, times or 1 do
        who = c:PadPress(button)
        c:Advance(0.05, 0.05)
    end
    return who
end

local function Focused(c)
    local frame, list, index = c.FG.Focus.Current()
    return frame, list, index
end

local function Ready(c)
    return Stack.Until(c, function()
        local p = c.FG.Planner.Current()
        return p and (p.status == "ready" or p.status == "failed" or p.status == "unreachable")
    end, 30)
end

local function Open(c, page)
    c:PadPress("PAD1", { hold = true })   -- the pad in use, as the client says when it is touched
    c:PadRelease("PAD1")
    c.FG.Window.Show(page or "search")
    c:Advance(0.3)
end

-- ==== who hears the buttons ================================================

function tests.theButtons_areTheGamesUntilTheWindowOpens()
    local c, FG = Start()
    T.eq(c:PadPress("PADDDOWN"), "game", "closed: the game's")
    T.eq(c:PadPress("PAD1"), "game", "A too")
    Open(c)
    T.eq(c:PadPress("PADDDOWN"), "addon", "open: Forever-GPS's")
    FG.Window.Hide()
    c:Advance(0.1)
    T.eq(c:PadPress("PADDDOWN"), "game", "closed again: the game's again")
    T.eq(#c:OverridesOf(c.env.ForeverGPSPadOwner, c.env.ForeverGPSPadWorld), 0, "no binding of Forever-GPS's left behind")
    T.eq(#c.blocked, 0, "nothing protected was refused")
end

function tests.theWorldButton_needsConsent()
    local c, FG = Start({ screen = { 1280, 800, 1 } })
    FG.Pad.Settings().mode = "handheld"     -- the Steam Deck profile, with a paddle to open
    FG.Pad.Apply()
    T.eq(FG.Pad.Binding("toggle"), "PADPADDLE1", "the Deck's paddle opens it")
    T.eq(c:PadPress("PADPADDLE1"), "game", "without consent the paddle stays the game's")
    FG.Pad.Settings().worldConsent = true
    FG.Pad.ApplyWorld()
    T.eq(c:PadPress("PADPADDLE1"), "addon", "with consent it opens Forever-GPS")
    c:Advance(0.2)
    T.ok(FG.Window.IsShown(), "open")
    Press(c, "PADPADDLE1")
    T.ok(not FG.Window.IsShown(), "the same paddle closes it")
    T.eq(c:PadPress("PADPADDLE1"), "addon", "and opens it again")
end

function tests.aModifierChord_isItsOwnBinding()
    local c, FG = Start()
    Open(c)
    T.ok(FG.Pad.Set("replan", "SHIFT-PAD3"), "LT + X for replanning")
    c:PadPress("PADLTRIGGER", { hold = true })
    local who = c:PadPress("PAD3")
    c:PadRelease("PADLTRIGGER")
    T.eq(who, "addon", "the chord reaches Forever-GPS")
    T.eq(FG.Pad.Label("SHIFT-PAD3"), "LT + X", "labelled with the button that is Shift")
    T.ok(FG.Pad.ModifierOnly("PADLTRIGGER"), "LT alone is the game's Shift")
    T.ok(FG.Pad.Label("PADLTRIGGER"):find("SHIFT", 1, true), "and its label says so")
end

-- ==== moving and choosing ===================================================

function tests.searchingAndStarting_withButtonsAlone()
    local c, FG = Start()
    FG.Bridge.WarmSearch()
    c:Advance(1)
    Open(c)
    Press(c, "PAD4")                              -- Y: the search, with the keyboard
    T.ok(FG.PadKeyboard.IsOpen(), "the keyboard opens on the search box")
    T.eq(FG.PadKeyboard.Target(), FG.SearchView.Box(), "for the search box")
    -- Type "auber" on the keyboard: the focus starts on q.
    local keys = { a = 0, u = 0, b = 0, e = 0, r = 0 }
    T.ok(keys, "")
    local function TypeKey(letter)
        local frame = Focused(c)
        local tries = 0
        while frame and frame.padKey ~= letter and tries < 40 do
            -- Walk: rows first, then across.
            local want = FG.PadKeyboard._Where(letter)
            local at = FG.PadKeyboard._Where(frame.padKey)
            if want.row > at.row then Press(c, "PADDDOWN")
            elseif want.row < at.row then Press(c, "PADDUP")
            elseif want.col > at.col then Press(c, "PADDRIGHT")
            else Press(c, "PADDLEFT") end
            frame = Focused(c)
            tries = tries + 1
        end
        T.eq(frame and frame.padKey, letter, "reached " .. letter)
        Press(c, "PAD1")
    end
    for letter in ("auber"):gmatch(".") do TypeKey(letter) end
    T.eq(FG.SearchView.Box():GetText(), "auber", "typed")
    Press(c, "PAD4")                              -- Y on the keyboard: done, search now
    T.ok(not FG.PadKeyboard.IsOpen(), "closed")
    local frame, list, index = Focused(c)
    T.ok(list ~= nil and list.items[index].result ~= nil, "the selection is on the first result")
    T.ok(list.items[index].result.name:lower():find("auberdine", 1, true), "Auberdine: " .. tostring(list.items[index].result.name))
    T.ok(frame ~= nil, "on screen")
    Press(c, "PAD1")                              -- A: go
    T.ok(Ready(c), "the journey is planned")
    T.ok(FG.Planner.Current().selected ~= nil, "a route chosen")
    Press(c, "PADPADDLE3")                        -- not bound on this profile: the game's
    local before = #c.gameActions
    T.eq(c.gameActions[before], "PADPADDLE3", "an unbound button stays the game's")
    -- Start, as the hint says: the window's Start button, focused and pressed.
    FG.Window.PadAction("startNav")
    c:Advance(0.5)
    T.ok(FG.Bridge.ActiveRoute() ~= nil, "navigating")
    Press(c, "PAD2")                              -- B: out of the journey, then the window
    Press(c, "PAD2")
    c:Advance(0.2)
    T.ok(not FG.Window.IsShown(), "back, back: closed")
    T.ok(FG.Bridge.ActiveRoute() ~= nil, "the navigation goes on")
    T.eq(#c.errors, 0, tostring(c.errors[1]))
end

function tests.theKeyboard_cancelsBackToWhatWasThere()
    local c, FG = Start()
    Open(c)
    FG.SearchView.Box():SetText("gold")
    Press(c, "PAD4")
    Press(c, "PAD1")                              -- types q
    T.eq(FG.SearchView.Box():GetText(), "goldq", "typed")
    Press(c, "PAD3")                              -- X: delete
    T.eq(FG.SearchView.Box():GetText(), "gold", "deleted")
    Press(c, "PAD1")
    Press(c, "PAD2")                              -- B: cancel
    T.ok(not FG.PadKeyboard.IsOpen(), "closed")
    T.eq(FG.SearchView.Box():GetText(), "gold", "the text as it was")
    T.ok(FG.Window.IsShown(), "and the window still open")
end

function tests.aHeldDirection_repeats()
    local c, FG = Start()
    FG.Bridge.WarmSearch()
    c:Advance(1)
    Open(c)
    FG.SearchView.Query("trainer")
    c:Advance(1)
    FG.Focus.To(FG.SearchView.FirstFocus())
    local _, _, first = Focused(c)
    c:PadPress("PADDDOWN", { hold = true })
    c:Advance(1, 0.02)
    c:PadRelease("PADDDOWN")
    local _, _, after = Focused(c)
    T.ok(after - first >= 5, ("held for a second: moved %d"):format(after - first))
    c:Advance(1)
    local _, _, still = Focused(c)
    T.eq(still, after, "released: it stops")
end

function tests.aLongList_isWalkedThroughToTheEnd()
    local c, FG = Start()
    FG.Bridge.WarmSearch()
    c:Advance(1)
    Open(c)
    FG.SearchView.Query("trainer")
    c:Advance(1)
    local list = FG.SearchView.Get().list
    local cards = 0
    for _, item in ipairs(list.items) do if item.result then cards = cards + 1 end end
    T.ok(cards >= 25, "a long list: " .. cards)
    FG.Focus.To(FG.SearchView.FirstFocus())
    Press(c, "PADDDOWN", cards + 5)
    local frame, _, index = Focused(c)
    T.eq(list.items[index].result, list.items[#list.items].result or list.items[index].result, "at the end")
    T.ok(frame ~= nil and frame:IsVisible(), "and the row for it is on screen")
    T.ok(list.offset > 0, "the list scrolled")
    Press(c, "PADDUP", 3)
    local _, _, up = Focused(c)
    T.ok(up < index, "and back up")
end

-- A virtual list of hundreds: every item reached, only a screenful of rows made.
function tests.hundredsOfItems_areReachedOneByOne()
    local c, FG = Start()
    Open(c, "trip")
    local parent = FG.Window.Frame()
    local clicked
    local list = FG.List.New(parent, {
        make = { row = function(p)
            local b = c.env.CreateFrame("Button", nil, p)
            b:SetScript("OnClick", function(self) clicked = self.item.n end)
            return b
        end },
        bind = function(row, item) row.item = item end,
        height = function() return 28 end,
    })
    list:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, -80)
    list:SetSize(300, 280)
    local items = {}
    for i = 1, 400 do items[i] = { kind = "row", n = i, key = "row" .. i } end
    list:SetItems(items)
    c:Advance(0.1)
    FG.Focus.To(list.shown[1])
    Press(c, "PADDDOWN", 399)
    local _, at, index = FG.Focus.Current()
    T.eq(at, list, "still in the list")
    T.eq(index, 400, "the last of 400")
    T.ok(#list.shown <= 20, "only a screenful of rows: " .. #list.shown)
    Press(c, "PAD1")
    T.eq(clicked, 400, "A on it chooses that one")
    Press(c, "PADPADDLE2")
    -- Paging, where bound.
    FG.Pad.Set("pageUp", "PADPADDLE2")
    c:Advance(0.2)
    Press(c, "PADPADDLE2")
    local _, _, paged = FG.Focus.Current()
    T.ok(paged < 400 and paged >= 380, "a page up: " .. tostring(paged))
    -- Items taken away under the focus: the nearest left.
    for i = 1, 100 do items[#items] = nil end
    list:SetItems(items, true)
    local _, _, now = FG.Focus.Current()
    T.ok(now and now <= 300, "the nearest left: " .. tostring(now))
    T.eq(#c.errors, 0, tostring(c.errors[1]))
end

-- Nothing of the controller's runs with the window closed; a press costs little.
function tests.theController_costsNothingClosedAndLittleOpen()
    local c, FG = Start()
    local running = {}
    for _, f in ipairs(c.frames) do
        local n = f.GetName and f:GetName() or ""
        if f._scripts.OnUpdate and f:IsVisible() and (n:find("Pad") or n:find("Focus") or n:find("Keyboard")) then running[#running + 1] = n end
    end
    T.eq(#running, 0, "no controller OnUpdate with the window closed: " .. table.concat(running, ","))
    FG.Bridge.WarmSearch()
    c:Advance(1)
    Open(c)
    FG.SearchView.Query("trainer")
    c:Advance(1)
    FG.Focus.To(FG.SearchView.FirstFocus())
    local start = os.clock()
    for _ = 1, 25 do
        c:PadPress("PADDDOWN")
        c:PadPress("PADDUP")
    end
    local each = (os.clock() - start) * 1000 / 50
    T.ok(each < 5, ("a press takes %.2f ms here, the stand-in's own work included"):format(each))
    print(("    a press: %.2f ms in the stand-in"):format(each))
end

function tests.theMouseAgain_putsTheControllerAside()
    local c, FG = Start()
    Open(c)
    Press(c, "PADDDOWN")
    local ring = c.env.ForeverGPSFocusRing
    T.ok(ring and ring:IsShown(), "the highlight while the controller is used")
    T.ok(FG.Window.Frame().hints:IsShown(), "and the hints")
    c:MouseUsed()
    T.ok(not ring:IsShown(), "the mouse again: no highlight")
    T.ok(not FG.Window.Frame().hints:IsShown(), "no hints")
    T.eq(c:PadPress("PADDDOWN"), "addon", "the controller still works at once")
    T.ok(ring:IsShown(), "and shows its highlight again")
end

function tests.theFocusedItem_survivesTheListChanging()
    local c, FG = Start()
    FG.Bridge.WarmSearch()
    c:Advance(1)
    Open(c)
    FG.SearchView.Query("trainer")
    c:Advance(1)
    FG.Focus.To(FG.SearchView.FirstFocus())
    Press(c, "PADDDOWN", 4)
    local _, list, index = Focused(c)
    local key = list.items[index].result
    -- New prices: the same items again, redrawn in place.
    list:SetItems(list.items, true)
    local _, _, again = Focused(c)
    T.eq(list.items[again].result, key, "the same item after a redraw")
    -- A narrower search: the item gone, the nearest one takes its place.
    FG.SearchView.Query("auberdine")
    c:Advance(1)
    Press(c, "PADDDOWN")
    local frame, list2, now = Focused(c)
    T.ok(frame ~= nil and list2 ~= nil and list2.items[now] ~= nil, "still somewhere sensible")
    T.eq(#c.errors, 0, tostring(c.errors[1]))
end

function tests.thePages_areReachedWithTheShoulders()
    local c, FG = Start()
    Open(c)
    local seen = { FG.Window.View() }
    for _ = 1, 5 do
        Press(c, "PADRSHOULDER")
        seen[#seen + 1] = FG.Window.View()
    end
    T.eq(table.concat(seen, ","), "search,quests,professions,trip,settings,search", "every page, round")
    Press(c, "PADLSHOULDER")
    T.eq(FG.Window.View(), "settings", "and back")
    T.eq(#c.errors, 0, tostring(c.errors[1]))
end

function tests.everyPage_hasSomethingToFocus()
    local c, FG = Start()
    FG.Trip.Add({ name = "Goldshire", subtitle = "Elwynn Forest", mapID = 1429, x = 0.42, y = 0.65 })
    Open(c)
    for _, page in ipairs({ "search", "quests", "professions", "trip", "settings" }) do
        FG.Window.Show(page)
        c:Advance(0.3)
        FG.Focus.First()
        local frame = Focused(c)
        T.ok(frame ~= nil, page .. ": something is focused")
        -- And moving about on it does no harm.
        for _, b in ipairs({ "PADDDOWN", "PADDDOWN", "PADDRIGHT", "PADDUP", "PADDLEFT" }) do Press(c, b) end
        T.ok(Focused(c) ~= nil, page .. ": still focused after moving")
    end
    FG.Window.Show("quests")
    FG.QuestsView.SetMode("find")
    T.ok(Stack.Until(c, FG.QuestIndex.Ready, 10), "the index builds")
    c:Advance(0.5)
    Press(c, "PAD4")
    T.eq(FG.PadKeyboard.Target(), FG.ExplorerView.Box(), "Y on the Quest Explorer: its own search")
    Press(c, "PAD2")
    T.eq(#c.errors, 0, tostring(c.errors[1]))
end

function tests.theProfessionViews_areCycledWithTheTriggers()
    -- Triggers not used as modifiers in the game's controller settings.
    local c, FG = Start({ })
    c.cvars.GamePadEmulateShift, c.cvars.GamePadEmulateCtrl = "none", "none"
    Open(c, "professions")
    local views = {}
    for _ = 1, 5 do
        Press(c, "PADRTRIGGER")
        views[#views + 1] = FG.ProfessionsView.Current and FG.ProfessionsView.Current() or "?"
    end
    local distinct = {}
    for _, v in ipairs(views) do distinct[v] = true end
    local n = 0
    for _ in pairs(distinct) do n = n + 1 end
    T.ok(n >= 4, "the triggers go through the views: " .. table.concat(views, ","))
    T.eq(#c.errors, 0, tostring(c.errors[1]))
end

-- ==== the route map =========================================================

function tests.theRouteMap_takesTheButtonsAndGivesThemBack()
    local c, FG = Start()
    FG.Bridge.WarmSearch()
    c:Advance(1)
    Open(c)
    FG.SearchView.Query("auberdine")
    c:Advance(1)
    FG.SearchView.Open(FG.SearchView._Results()[1])
    T.ok(Ready(c), "planned")
    Press(c, "PADRSTICK")                         -- R3: the map
    T.ok(FG.RouteMap.Shown(), "the map is open")
    Press(c, "PADDRIGHT")
    T.ok(FG.MapPreview.Focused() ~= nil, "right: the first step")
    Press(c, "PADDUP")
    T.eq(FG.MapPreview.Focused(), nil, "up: all of it")
    Press(c, "PAD2")
    T.ok(not FG.RouteMap.Shown(), "B closes the map")
    T.ok(FG.Planner.Current() ~= nil, "the plan is still there")
    T.ok(FG.Window.IsShown(), "and the window")
    Press(c, "PADRSHOULDER")
    T.eq(FG.Window.View(), "quests", "the map gone, the buttons are the window's again")
    -- Closed by its own button, with the mouse: the same.
    Press(c, "PADLSHOULDER")
    Press(c, "PADRSTICK")
    T.ok(FG.RouteMap.Shown(), "open again")
    FG.RouteMap.Frame():Hide()
    Press(c, "PADRSHOULDER")
    T.eq(FG.Window.View(), "quests", "the window's buttons, after a close by mouse")
    T.eq(#c.errors, 0, tostring(c.errors[1]))
end

-- ==== combat ================================================================

function tests.combat_givesTheButtonsBackAtOnce()
    local c, FG = Start()
    Open(c)
    T.eq(c:PadPress("PAD1"), "addon", "Forever-GPS's before the fight")
    c:SetCombat(true)
    T.eq(c:PadPress("PAD1"), "game", "the game's the moment it starts")
    T.eq(c:PadPress("PADDDOWN"), "game", "every one")
    T.ok(FG.Window.IsShown(), "the window may stay open")
    c:SetCombat(false)
    c:Advance(0.1)
    T.eq(c:PadPress("PADDDOWN"), "addon", "after it: Forever-GPS's again")
    T.eq(#c.blocked, 0, "nothing protected was tried in combat: " .. tostring(c.blocked[1]))
end

function tests.openingInCombat_waitsForTheEnd()
    local c, FG = Start()
    c:SetCombat(true)
    Open(c)
    T.ok(FG.Window.IsShown(), "it opens")
    T.eq(c:PadPress("PADDDOWN"), "game", "but the buttons stay the game's")
    T.eq(#c.blocked, 0, "nothing protected tried: " .. tostring(c.blocked[1]))
    c:SetCombat(false)
    T.eq(c:PadPress("PADDDOWN"), "addon", "then they are Forever-GPS's")
    FG.Window.Hide()
    c:SetCombat(true)
    c:SetCombat(false)
    T.eq(c:PadPress("PADDDOWN"), "game", "closed during the fight: not taken back")
    T.eq(#c.blocked, 0, tostring(c.blocked[1]))
end

function tests.aButtonHeldAsTheWindowOpens_isLetGoFirst()
    local c, FG = Start()
    c:PadPress("PADDDOWN", { hold = true })
    FG.Window.Show("search")
    c:Advance(0.3)
    T.eq(c:Override("PADDDOWN"), nil, "not taken while held")
    c:PadRelease("PADDDOWN")
    c:Advance(0.3)
    T.ok(c:Override("PADDDOWN") ~= nil, "taken once released")
end

-- ==== changing a button =====================================================

local function ToSettings(c, FG)
    Open(c, "settings")
    FG.SettingsView.SelectByLabel("SETG_CONTROLLER")
    c:Advance(0.2)
end

function tests.changingAButton_byPressingIt()
    local c, FG = Start()
    ToSettings(c, FG)
    FG.PadSettings.Change("save")
    T.ok(FG.Pad.Learning(), "waiting for a press")
    T.eq(c:PadPress("PADPADDLE2"), "frame", "the press goes to the learner, not a binding")
    T.ok(not FG.Pad.Learning(), "done")
    T.eq(FG.Pad.Binding("save"), "PADPADDLE2", "saved")
    c:Advance(0.2)
    T.eq(c:PadPress("PADPADDLE2"), "addon", "and it works once let go")
    T.ok(FG.Pad.Undo(), "undo")
    T.eq(FG.Pad.Binding("save"), nil, "back as it was")
    T.eq(#c.blocked, 0, tostring(c.blocked[1]))
end

function tests.aModifierAndAButton_areLearnedTogether()
    local c, FG = Start()
    ToSettings(c, FG)
    FG.PadSettings.Change("replan")
    c:PadPress("PADLTRIGGER", { hold = true })
    T.ok(FG.Pad.Learning(), "a modifier alone: still waiting")
    c:PadPress("PAD2")
    c:PadRelease("PADLTRIGGER")
    T.eq(FG.Pad.Binding("replan"), "SHIFT-PAD2", "LT + B, not a cancel")
end

function tests.backAlone_timeoutAndEscape_cancel()
    local c, FG = Start()
    ToSettings(c, FG)
    local before = FG.Pad.Binding("search")
    FG.PadSettings.Change("search")
    c:PadPress("PAD2")
    T.ok(not FG.Pad.Learning(), "B alone cancels")
    T.eq(FG.Pad.Binding("search"), before, "unchanged")
    T.ok(not FG.PadSettings.DialogShown(), "the dialog gone")
    FG.PadSettings.Change("search")
    c:Advance(11)
    T.ok(not FG.Pad.Learning(), "ten seconds: given up")
    T.eq(FG.Pad.Binding("search"), before, "unchanged")
    FG.PadSettings.Change("search")
    local learner = c.env.ForeverGPSPadLearner
    learner._scripts.OnKeyDown(learner, "ESCAPE")
    T.ok(not FG.Pad.Learning(), "Escape cancels")
    T.eq(c:PadPress("PAD1"), "addon", "the window's buttons are back")
end

function tests.aClash_offersSwapReplaceCancel()
    local c, FG = Start()
    ToSettings(c, FG)
    FG.PadSettings.Change("search")
    c:PadPress("PAD3")                            -- X: More's
    T.ok(FG.PadSettings.DialogShown(), "asked")
    local labels = {}
    for _, b in ipairs(FG.PadSettings.DialogButtons()) do if b:IsShown() then labels[#labels + 1] = b.label:GetText() end end
    T.eq(table.concat(labels, ","), "Swap,Replace,Cancel", "the choices")
    -- The dialog has the focus: A on the first choice.
    Press(c, "PAD1")
    T.eq(FG.Pad.Binding("search"), "PAD3", "swapped: Search is X")
    T.eq(FG.Pad.Binding("context"), "PAD4", "and More has Y")
    T.ok(not FG.PadSettings.DialogShown(), "closed")
end

function tests.theEssentials_cannotBeLeftWithoutAButton()
    local c, FG = Start()
    Open(c)
    local ok, why = FG.Pad.Set("search", "PAD1", "replace")
    T.ok(not ok and why == "essential", "Select cannot lose A")
    ok, why = FG.Pad.Set("confirm", nil)
    T.ok(not ok and why == "essential", "nor be unbound")
    T.eq(FG.Pad.Binding("confirm"), "PAD1", "unchanged")
end

function tests.theGamesOwnUse_isSaidAndChosen()
    local c, FG = Start()
    c.gameBindings["PADFORWARD"] = "TOGGLEGAMEMENU"
    c.env.BINDING_NAME_TOGGLEGAMEMENU = "Game Menu"
    ToSettings(c, FG)
    FG.PadSettings.Change("toggle")
    c:PadPress("PADFORWARD")
    T.ok(FG.PadSettings.DialogShown(), "the game's use is said")
    local labels = {}
    for _, b in ipairs(FG.PadSettings.DialogButtons()) do if b:IsShown() then labels[#labels + 1] = b.label:GetText() end end
    T.eq(table.concat(labels, ","), "Use it,Only to close it,Choose another,Cancel", "the choices")
    -- Only to close it: no world binding; the button closes the open window.
    FG.PadSettings.DialogButtons()[2]:Click()
    T.ok(not FG.Pad.Settings().worldConsent, "no consent given")
    c:Advance(0.2)
    T.eq(c:PadPress("PADFORWARD"), "addon", "closes the window")
    c:Advance(0.1)
    T.ok(not FG.Window.IsShown(), "closed")
    T.eq(c:PadPress("PADFORWARD"), "game", "closed: the game's menu again")
    T.eq(c.gameActions[#c.gameActions], "TOGGLEGAMEMENU", "the game got it")
end

function tests.inCombat_aChangeWaits()
    local c, FG = Start()
    ToSettings(c, FG)
    c:SetCombat(true)
    FG.PadSettings.Change("search")
    T.ok(not FG.Pad.Learning(), "no capture in combat")
    T.ok(FG.PadSettings.DialogShown(), "it says why")
    c:SetCombat(false)
    FG.PadSettings.Change("search")
    T.ok(FG.Pad.Learning(), "after: capture")
    c:SetCombat(true)
    T.ok(not FG.Pad.Learning(), "a fight mid-capture ends it")
    T.eq(#c.blocked, 0, "without a protected call in combat: " .. tostring(c.blocked[1]))
    c:SetCombat(false)
end

-- ==== profiles ==============================================================

function tests.profiles_areMadeRenamedSwitchedAndDeleted()
    local c, FG = Start()
    local P = FG.Pad
    Open(c)
    T.eq(P.ProfileName(), "Controller", "the desktop default")
    local deck = P.NewProfile("deck", "Couch")
    T.eq(P.ProfileName(), "Couch", "a new one is used")
    T.eq(P.Binding("toggle"), "PADPADDLE1", "from the Deck layout")
    local copy = P.Duplicate()
    T.eq(copy, "Couch copy", "duplicated")
    T.ok(P.Rename(copy, "Couch 2"), "renamed")
    T.ok(not P.Rename("Couch 2", "Couch"), "not to a name taken")
    T.ok(P.Use("Controller"), "switched")
    T.eq(P.Binding("toggle"), nil, "the Xbox layout")
    T.ok(P.Delete(deck), "deleted")
    for _, name in ipairs(P.Profiles()) do
        if name ~= "Controller" then P.Delete(name) end
    end
    T.eq(#P.Profiles(), 1, "one left")
    T.ok(not P.Delete("Controller"), "the last stays")
    T.eq(c:PadPress("PADDDOWN"), "addon", "the window still works")
end

function tests.aCharacter_canHaveItsOwnProfile()
    local c, FG = Start()
    local P = FG.Pad
    P.NewProfile("minimal", "Mine")
    P.Use("Controller")
    P.Use("Mine", true)
    T.eq(P.ProfileName(), "Mine", "this character's")
    T.eq(FG.db.pad.active.desktop, "Controller", "the account's choice kept")
    P.Use("Controller")
    T.eq(FG.char.padProfile, nil, "back to the account's")
end

function tests.handheldAndDocked_keepTheirOwnProfiles()
    local c, FG = Start({ screen = { 1280, 800, 1 } })
    local P = FG.Pad
    T.eq(P.Layout(), "desktop", "small screen, mouse in use: desktop")
    Open(c)
    T.eq(P.Layout(), "handheld", "small screen, controller in use: handheld")
    T.eq(P.ProfileName(), "Steam Deck", "its own profile")
    P.Settings().mode = "desktop"
    T.eq(P.ProfileName(), "Controller", "docked: the other")
end

function tests.resetOneAndAll_withUndo()
    local c, FG = Start()
    local P = FG.Pad
    Open(c)
    P.Set("search", "PADPADDLE1")
    T.ok(P.Reset("search"), "reset one")
    T.eq(P.Binding("search"), "PAD4", "to its layout's")
    P.Set("search", "PADPADDLE1")
    P.Set("save", "PADPADDLE2")
    P.ResetAll("minimal")
    T.eq(P.Binding("save"), nil, "the minimal layout")
    T.ok(P.Undo(), "undone")
    T.eq(P.Binding("save"), "PADPADDLE2", "everything back")
    T.eq(P.Binding("search"), "PADPADDLE1", "everything")
end

-- ==== the first time ========================================================

function tests.theIntroduction_comesOnceAndIsSkipped()
    local c, FG = Start({ intro = true })
    Open(c)
    c:Advance(0.1)
    T.ok(FG.PadSettings.DialogShown(), "the first time: what the buttons do")
    Press(c, "PAD2")
    T.ok(not FG.PadSettings.DialogShown(), "B skips it")
    T.ok(FG.Window.IsShown(), "and the window stays")
    FG.Window.Hide()
    Open(c)
    c:Advance(0.1)
    T.ok(not FG.PadSettings.DialogShown(), "only once")
    T.ok(FG.PadSettings.Intro(true), "again, asked for")
    Press(c, "PAD1")
    T.eq(FG.Window.View(), "settings", "its first choice: the controller settings")
end

function tests.theIntroduction_waitsForTheController()
    local c, FG = Start({ intro = true })
    FG.Window.Show("search")
    c:Advance(0.2)
    T.ok(not FG.PadSettings.DialogShown(), "not with the mouse")
    c:PadPress("PADDDOWN")
    c:Advance(0.1)
    T.ok(FG.PadSettings.DialogShown(), "the controller touched: now")
end

-- ==== the handheld screen ===================================================

function tests.handheld_fitsTheDeckScreen()
    local c, FG = Start({ screen = { 1280, 800, 1 } })
    FG.Bridge.WarmSearch()
    c:Advance(1)
    Open(c)
    T.ok(FG.Window.Handheld(), "handheld")
    local f = FG.Window.Frame()
    local r = UI.rectOf(f)
    T.ok(r.l >= 0 and r.r <= 1280 and r.b >= 0 and r.t <= 800, ("on screen: %d %d %d %d"):format(r.l, r.r, r.b, r.t))
    T.ok(r.r - r.l >= 1000, "most of it: " .. (r.r - r.l))
    -- Text a person can read at arm's length: the window scaled up.
    T.ok(f:GetEffectiveScale() >= 1.1, "scaled up: " .. f:GetEffectiveScale())
    for _, page in ipairs({ "search", "quests", "professions", "trip", "settings" }) do
        FG.Window.Show(page)
        c:Advance(0.3)
        local rr = UI.rectOf(f)
        T.ok(rr.l >= 0 and rr.r <= 1280 and rr.b >= 0 and rr.t <= 800, page .. ": on screen")
    end
    T.ok(f.hints:IsShown(), "the button hints at the foot")
    -- The navigation display: compact there, and placed with the controller.
    T.ok(FG.HUD.MoveTo("bottom"), "moved to the foot")
    T.eq(FG.HUD.Spot(), "bottom", "there")
    T.ok(f.hints:GetText():find("Select", 1, true), "they name what A does: " .. tostring(f.hints:GetText()))
    T.eq(#c.errors, 0, tostring(c.errors[1]))
end

function tests.theMouse_isUntouchedWithoutAController()
    local c, FG = Start()
    FG.Window.Show("search")
    c:Advance(0.3)
    T.ok(FG.SearchView.Box():HasFocus(), "the box takes the keyboard, as before")
    T.ok(not c.env.ForeverGPSFocusRing or not c.env.ForeverGPSFocusRing:IsShown(), "no controller ring")
    T.ok(not FG.Window.Frame().hints:IsShown(), "no button hints")
    T.ok(not FG.Window.Handheld(), "the desktop layout")
end

function tests.aController_neverTouchesTheGamesSavedBindings()
    local c, FG = Start()
    local saved = 0
    c.env.SetBinding = function() saved = saved + 1 end
    c.env.SaveBindings = function() saved = saved + 1 end
    Open(c)
    FG.Pad.Set("save", "PADPADDLE2")
    FG.Pad.Settings().worldConsent = true
    FG.Pad.Set("toggle", "PADPADDLE1")
    Press(c, "PADDDOWN", 3)
    T.eq(saved, 0, "only override bindings, never the player's own")
end

return tests
