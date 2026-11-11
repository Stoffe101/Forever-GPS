-- Draws the real interface for a person to look at, from the real addon code on
-- the real engine and data, at each target screen.
--
--     lua tools/ui_preview.lua [screen name]    (from the repository root)
--     python tools/art_png.py                   (once, for the icons)
--
-- Writes build/preview/*.html, and build/preview/index.html to walk through them.
-- These are renders of the addon's layout in a stand-in client, in a browser. They
-- are not screenshots of the game.
--
-- A screen here is pixels wide, tall, and pixels per UI unit. In the game that last
-- number is (height / 768) * uiScale, so a default 1080p screen is about 1.4 and
-- UIParent is 1365 by 768. A UI scale addon can bring it down to 1: the 3440x1440
-- setup this was built for runs UIParent at 3440 by 1440.
package.path = "tests/?.lua;" .. package.path
local Stack = require("support.stack")
local Preview = require("support.preview")

local QUESTIE = {
    areaMaps = { [12] = 1429, [40] = 1436 },
    npcs = {
        [299] = { name = "Young Wolf", spawns = { [12] = { { 43, 72 }, { 44, 73 }, { 45, 71 }, { 52, 80 } }, [40] = { { 58, 22 } } } },
        [38] = { name = "Defias Thug", spawns = { [12] = { { 52, 60 }, { 53, 62 } } } },
        [197] = { name = "Marshal McBride", spawns = { [12] = { { 48.2, 42.1 } } } },
        [240] = { name = "Marshal Dughan", spawns = { [12] = { { 42.1, 65.9 } } } },
    },
    quests = {
        [33] = { name = "Wolves Across the Border", objectives = { { id = 299, text = "Young Wolf" } }, finisher = 240 },
        [18] = { name = "Brotherhood of Thieves", objectives = { { id = 38, text = "Defias Thug" } }, finisher = 197 },
        [99] = { name = "Whispers in the Dark", objectives = { { id = 9999, text = "Whisper" } }, finisher = 9998 },
    },
}

-- Quests for the explorer, shaped as Questie's are. A stand-in, for looking at the layout.
local function Explorer(world)
    world.npcs[241] = { name = "Remy \"Two Times\"", zoneID = 12, spawns = { [12] = { { 42.1, 67.2 } } } }
    world.objects = { [500] = { name = "Wanted Poster", zoneID = 12, spawns = { [12] = { { 42, 66 } } } } }
    world.items = { [600] = { name = "A Bloodstained Letter", npcDrops = { 299 } } }
    local function Q(id, name, level, fields)
        fields = fields or {}
        fields.name, fields.questLevel, fields.requiredLevel = name, level, fields.requiredLevel or math.max(1, level - 3)
        fields.starter = fields.starter or 240
        fields.finisher = fields.finisher or 240
        fields.zoneOrSort = 12
        world.quests[id] = fields
    end
    Q(100, "A Threat Within", 2, { nextQuestInChain = 101, objectivesText = { "Speak with Deputy Willem at Northshire Abbey." } })
    Q(101, "Kobold Camp Cleanup", 3, { preQuestSingle = { 100 }, nextQuestInChain = 102, reputationReward = { { 72, 75 } } })
    Q(102, "Investigate Echo Ridge", 4, { preQuestSingle = { 101 }, nextQuestInChain = 103 })
    Q(103, "Skirmish at Echo Ridge", 5, { preQuestSingle = { 102 }, nextQuestInChain = 104 })
    Q(104, "Report to Goldshire", 5, { preQuestSingle = { 103 }, nextQuestInChain = 105 })
    Q(105, "The Fargodeep Mine", 7, { preQuestSingle = { 104 }, nextQuestInChain = 106, starter = 241 })
    Q(106, "The Jasperlode Mine", 8, { preQuestSingle = { 105 }, objectivesText = { "Scout through the Jasperlode Mine and report back." } })
    Q(110, "The Left Road", 6)
    Q(111, "The Right Road", 6, { starter = 241 })
    Q(112, "Where The Roads Meet", 7, { preQuestSingle = { 110, 111 }, nextQuestInChain = 113 })
    Q(113, "One Last Errand", 8, { preQuestSingle = { 112 } })
    Q(120, "Both Hands Needed", 7, { preQuestGroup = { 110, 101 } })
    Q(121, "The Light's Choice", 8, { exclusiveTo = { 122 } })
    Q(122, "The Dark Choice", 8, { exclusiveTo = { 121 } })
    Q(130, "A Note Pinned Up", 6, { startedBy = { nil, { 500 } } })
    Q(131, "A Letter In The Mud", 6, { startedBy = { nil, nil, { 600 } } })
    Q(132, "Nobody Remembers", 6, { startedBy = {}, finisher = 240 })
    Q(133, "Far Too Soon", 40, { requiredLevel = 38 })
    Q(134, "Only For Friends", 20, { requiredLevel = 8, requiredMinRep = { 72, 3000 }, stop = "MISSING_REPUTATION" })
    Q(135, "Tailors Wanted", 20, { requiredLevel = 8, requiredSkill = { 197, 100 }, stop = "PROFESSION_SKILL" })
    Q(136, "For The Horde", 10, { requiredRaces = 178, stop = "WRONG_RACE" })
    Q(137, "A Link To Nowhere", 6, { preQuestSingle = { 99999 } })
    Q(138, "Deep In The Mines", 15, { dungeon = true, requiredLevel = 8 })
    Q(139, "Again And Again", 8, { repeatable = true })
    return world
end
Explorer(QUESTIE)

local QUEST_LOG = {
    { questID = 33, title = "Wolves Across the Border", level = 6, header = "Elwynn Forest",
      objectives = { { text = "Young Wolf slain: 3/8", numFulfilled = 3, numRequired = 8, finished = false } } },
    { questID = 18, title = "Brotherhood of Thieves", level = 4,
      objectives = { { text = "Red Burlap Bandana: 12/12", numFulfilled = 12, numRequired = 12, finished = true },
                     { text = "Defias Thug slain: 4/8", numFulfilled = 4, numRequired = 8, finished = false } } },
    { questID = 99, title = "Whispers in the Dark", level = 7, header = "Westfall",
      objectives = { { text = "Whisper heard: 0/1", numFulfilled = 0, numRequired = 1, finished = false } } },
}

local SCREENS = {
    { "ultrawide-1px", 3440, 1440, 1, "3440x1440, one UI unit per pixel (a UI scale addon)" },
    { "ultrawide-default", 3440, 1440, 1.875, "3440x1440, default UI scale: UIParent 1835x768" },
    { "fullhd-default", 1920, 1080, 1.406, "1920x1080, default UI scale: UIParent 1365x768" },
    { "fullhd-large", 1920, 1080, 1.617, "1920x1080, largest UI scale: UIParent 1187x668" },
    { "fullhd-small", 1920, 1080, 0.9, "1920x1080, smallest UI scale: UIParent 2133x1200" },
    { "fullhd-worst", 1920, 1080, 3, "1920x1080 at three pixels per unit, tighter than the game goes: 640x360" },
}

local BACKDROPS = {
    { "snow", 0.86, 0.90, 0.93 }, { "sand", 0.78, 0.68, 0.48 }, { "forest", 0.25, 0.37, 0.23 }, { "dark", 0.11, 0.13, 0.19 },
}

local AUBERDINE = { name = "Auberdine", mapID = 1439, x = 0.37, y = 0.44 }
local DARKSHIRE = { name = "Darkshire", mapID = 1431, x = 0.75, y = 0.45 }

os.execute(package.config:sub(1, 1) == "\\" and "mkdir build\\preview 2>nul" or "mkdir -p build/preview")

local pages = {}

local function Shot(c, screen, state, extra)
    local frames = {}
    -- In the order the game's frame strata would stack them.
    for _, name in ipairs({ "ForeverGPSHUD", "ForeverGPSToast", "WorldMapFrame", "ForeverGPSWindow", "ForeverGPSRouteMap", "ForeverGPSQuick",
                            "ForeverGPSCopyBox", "ForeverGPSMenu" }) do
        local f = c.env[name]
        if f and f._shown then frames[#frames + 1] = f end
    end
    for _, f in ipairs(extra or {}) do frames[#frames + 1] = f end
    local name = screen[1] .. "-" .. state
    Preview.Write("build/preview/" .. name .. ".html", state .. ": " .. screen[5], c.root, frames)
    pages[#pages + 1] = { name = name, title = screen[5] }
end

local function Settle(c, seconds)
    Stack.Until(c, function() return false end, seconds or 0.6)
end

local function Planned(c)
    Stack.Until(c, function()
        local p = c.FG.Planner.Current()
        return p and (p.status == "ready" or p.status == "failed" or p.status == "unreachable")
    end, 30)
    Settle(c, 0.3)
end

local function NewClient(screen, opts)
    opts = opts or {}
    opts.screen = { screen[2], screen[3], screen[4] }
    opts.mapID, opts.x, opts.y = opts.mapID or 1453, opts.x or 0.6, opts.y or 0.6
    opts.questie, opts.quests, opts.level = QUESTIE, QUEST_LOG, 8
    local c = Stack.new(opts)
    c.FG.Bridge.WarmSearch()
    Settle(c)
    return c
end

local function Pages(c, screen)
    local FG = c.FG
    FG.Window.Show("search")
    Settle(c)
    Shot(c, screen, "home")
    -- A character some way into playing: quests warmed, a hearth set, places visited.
    FG.QuestTargets.Warm()
    c.env.EasyFind.db.gpsHearth = { [c.ns.CurrentCharacterKey()] = { bind = "Goldshire", m = 1429, x = 0.43, y = 0.65 } }
    for i = 1, 4 do
        FG.Saved.AddRecent({ data = { name = "Stormwind Bank", mapID = 1453, x = 0.6, y = 0.7 }, name = "Stormwind Bank", subtitle = "Stormwind City" })
        FG.Saved.AddRecent({ data = { name = "Goldshire", mapID = 1429, x = 0.42, y = 0.65 }, name = "Goldshire", subtitle = "Elwynn Forest" })
        if i == 1 then FG.Saved.AddRecent({ data = { name = "Sentinel Hill", mapID = 1436, x = 0.56, y = 0.47 }, name = "Sentinel Hill", subtitle = "Westfall" }) end
    end
    Settle(c)
    FG.Window.Show("search")
    Settle(c)
    Shot(c, screen, "home-used")
    FG.SearchView.Query("repair")
    Settle(c)
    Shot(c, screen, "search")
    FG.SearchView.Query("auberdin")
    Settle(c)
    Shot(c, screen, "search-spelling")
    local results = FG.SearchView._Results()
    if results[1] then FG.SearchView.Open(results[1]) end
    Planned(c)
    Shot(c, screen, "journey")
    FG.Planner.Inspect({ data = DARKSHIRE, name = "Darkshire", subtitle = "Duskwood" })
    Planned(c)
    Shot(c, screen, "journey-contested")
    FG.Planner.Clear()
    FG.Window.Show("quests")
    Settle(c)
    FG.QuestsView.Toggle(33)
    FG.QuestsView.Toggle(18)
    FG.QuestsView.Toggle(99)
    Settle(c, 1)
    Shot(c, screen, "quests")
    FG.QuestsView.SetFilter("missing")
    FG.QuestsView.NextGrouping()
    Settle(c)
    Shot(c, screen, "quests-filtered")
    FG.QuestsView.SetFilter("all")
    FG.Trip.Add({ name = "Marshal Dughan", subtitle = "Elwynn Forest", mapID = 1429, x = 0.421, y = 0.659 })
    FG.Trip.Add({ name = "Sentinel Hill", subtitle = "Westfall", mapID = 1436, x = 0.56, y = 0.47 })
    FG.Trip.Add({ name = "A very long stop name that has to fit in the row somehow", subtitle = "Westfall", mapID = 1436, x = 0.4, y = 0.6 })
    FG.Trip.Save()
    FG.Window.Show("trip")
    Settle(c)
    Shot(c, screen, "trip")
    FG.Trip.Clear()
    FG.Window.Show("settings")
    for index, group in ipairs(FG.SettingsView.Groups()) do
        FG.SettingsView.Select(index)
        Settle(c, 0.1)
        Shot(c, screen, "settings-" .. group.label:sub(6):lower())
    end
    FG.Window.Show("search")
end

-- The explorer: every state that has its own look.
local function Quests(c, screen)
    local FG = c.FG
    c.completed[100], c.completed[101] = true, true
    FG.QuestStatus.Forget()
    FG.Window.Show("quests")
    FG.QuestsView.SetMode("find")
    Stack.Until(c, function() return FG.QuestIndex.Ready() end, 10)
    FG.QuestBrowse.Scan()
    Stack.Until(c, FG.QuestBrowse.Scanned, 10)
    Settle(c, 0.3)
    FG.ExplorerView.SetFilter("available")
    Shot(c, screen, "explore-results")
    FG.ExplorerView.SetFilter("all")
    Shot(c, screen, "explore-large-list")
    FG.ExplorerView.Search("zzzzzz")
    Settle(c, 0.2)
    Shot(c, screen, "explore-empty")
    FG.ExplorerView.Search("")
    FG.ExplorerView.ToggleZones()
    if FG.ExplorerView.Mode() ~= "zones" then FG.ExplorerView.ToggleZones() end
    Settle(c, 0.2)
    Shot(c, screen, "explore-zones")
    FG.ExplorerView.PickZone("Elwynn Forest")
    for _, entry in ipairs({ { "details-available", 102 }, { "details-locked", 106 }, { "details-alternatives", 112 },
                             { "details-branching", 113 }, { "details-multiple-prereq", 120 }, { "details-object", 130 },
                             { "details-item", 131 }, { "details-missing", 132 }, { "details-level", 133 },
                             { "details-rep", 134 }, { "details-wrong-side", 136 }, { "details-broken-link", 137 },
                             { "details-exclusive", 121 } }) do
        FG.ExplorerView.Open(entry[2])
        Settle(c, 1.5)
        Shot(c, screen, entry[1])
    end
    c.completed[102], c.completed[103], c.completed[104], c.completed[105], c.completed[106] = true, true, true, true, true
    FG.QuestStatus.Forget()
    FG.ExplorerView.Open(106)
    Settle(c, 1)
    Shot(c, screen, "details-completed-chain")
    FG.QuestDetail.ShowOnMap()
    Settle(c, 0.5)
    Shot(c, screen, "explore-map")
    FG.RouteMap.Hide()
    FG.Window.CloseQuest()
    FG.QuestsView.SetMode("log")
end

-- Professions, travel costs and a journey gone another way. Stand-in data, for the layout.
local TRADE = {
    professions = { { name = "Alchemy", skill = 132, max = 150, line = 171 }, { name = "Herbalism", skill = 140, max = 150, line = 182 } },
    recipes = {
        [1001] = { name = "Lesser Healing Potion", line = 171, out = 858, reagents = { { id = 900, n = 1 }, { id = 902, n = 1 } },
                   at = { y = 140, g = 155, x = 170 } },
        [1002] = { name = "Elixir of Minor Fortitude", line = 171, out = 2458, qmin = 2, qmax = 4,
                   reagents = { { id = 901, n = 2 }, { id = 902, n = 1 } }, at = { y = 135, g = 145, x = 155 } },
        [1003] = { name = "Swiftness Potion", line = 171, out = 2459, reagents = { { id = 904, n = 1 }, { id = 902, n = 1 } },
                   at = { y = 140, g = 150, x = 160 } },
        [1004] = { name = "Elixir of Wisdom", line = 171, out = 3383, reagents = { { id = 905, n = 2 }, { id = 902, n = 1 } },
                   at = { y = 150, g = 165, x = 180 } },
    },
    auctions = { { itemID = 900, count = 10, buyout = 1000 }, { itemID = 901, count = 20, buyout = 800 }, { itemID = 904, count = 5, buyout = 2500 },
                 { itemID = 858, count = 4, buyout = 12000 }, { itemID = 2458, count = 6, buyout = 3600 }, { itemID = 2459, count = 2, buyout = 900 } },
    merchant = { { id = 902, price = 20 } },
    items = { [900] = { name = "Briarthorn" }, [901] = { name = "Earthroot" }, [902] = { name = "Empty Vial" }, [904] = { name = "Swiftthistle" },
              [905] = { name = "Bruiseweed" }, [858] = { name = "Lesser Healing Potion", sell = 100 }, [2458] = { name = "Elixir", sell = 40 } },
}

local function Trade(screen)
    local opts = { screen = { screen[2], screen[3], screen[4] }, mapID = 1453, x = 0.70, y = 0.72, level = 22,
                   questie = QUESTIE, quests = QUEST_LOG }
    -- A copy each screen: the long-list shot adds reagents, which must not leak into the next.
    for k, v in pairs(TRADE) do opts[k] = require("support.client").Clone(v) end
    local c = Stack.new(opts)
    local FG = c.FG
    Settle(c, 4)
    c:Fire("MERCHANT_SHOW")
    -- Before any auction house: recipes read, nothing priced. Every recipe is still shown.
    c.openProfession = c.professions[1]
    c:Fire("TRADE_SKILL_SHOW")
    Settle(c, 1)
    FG.Window.Show("professions")
    FG.ProfessionsView.Show("profit")
    Settle(c, 0.5)
    Shot(c, screen, "prof-profit-unpriced")
    -- At the auction house: it scans by itself.
    c:Fire("AUCTION_HOUSE_SHOW")
    Settle(c, 3.6)
    FG.ProfessionsView.Show("market")
    Settle(c, 0.2)
    Shot(c, screen, "prof-market-auto")
    Settle(c, 4)
    for _, which in ipairs({ "overview", "leveling", "profit", "market" }) do
        FG.ProfessionsView.Show(which)
        Settle(c, 0.6)
        Shot(c, screen, "prof-" .. which)
    end
    -- Recipes still to learn, from the client's data, and the profit list filtered.
    FG.ProfessionsView.Show("leveling")
    FG.ProfessionsView._Set({ coverage = "obtainable" })
    Settle(c, 1.5)
    Shot(c, screen, "prof-leveling-obtainable")
    FG.ProfessionsView._Set({ coverage = "known" })
    FG.ProfessionsView.Show("profit")
    FG.ProfessionsView._Set({ only = { complete = true }, sort = "recovery" })
    Settle(c, 0.3)
    Shot(c, screen, "prof-profit-filtered")
    FG.ProfessionsView._Set({ only = {}, sort = "profit" })
    local project = FG.Crafting.NewProject("Potions to sell")
    FG.Crafting.AddToProject(project, 1001, 10)
    FG.Crafting.AddToProject(project, 1002, 6)
    FG.Crafting.Mark(project, 901, "bought")
    FG.ProfessionsView.Show("lists")
    Settle(c, 0.3)
    Shot(c, screen, "prof-lists")
    -- A long list with long names: it scrolls, and nothing runs off the edge.
    local big = FG.Crafting.NewProject("A list with a name long enough to test how the chips wrap at small sizes")
    for id = 1001, 1004 do FG.Crafting.AddToProject(big, id, 40) end
    for i = 1, 30 do
        c.items[5000 + i] = { name = "An extraordinarily long reagent name, number " .. i .. ", that keeps going" }
        c.recipes[1001].reagents[#c.recipes[1001].reagents + 1] = { id = 5000 + i, n = 1 }
    end
    FG.ProfessionsView.Show("lists")
    Settle(c, 0.3)
    Shot(c, screen, "prof-lists-long")
    -- A scan arriving: the page says how far it has got.
    c.FG.db.market.houses[FG.Market.Key()].askedAt = c.env.time() - 3600
    c.replicateSpread = 6
    FG.Market.Scan()
    Settle(c, 1.2)
    FG.ProfessionsView.Show("market")
    Settle(c, 0.2)
    Shot(c, screen, "prof-market-scanning")
    Settle(c, 10)
    c.replicateSpread = nil
    c:Fire("AUCTION_HOUSE_CLOSED")
    c.FG.db.market.houses[FG.Market.Key()].scannedAt = c.env.time() - 5 * 86400
    FG.ProfessionsView.Show("profit")
    Settle(c, 0.3)
    Shot(c, screen, "prof-stale")

    -- Travel costs: a flight that costs five gold against a free way round.
    local Route = FG.Bridge.NS().GPSRoute
    Route.recordedKnown = { [2] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true, [12] = true }
    Route.ForgetKnown()
    FG.char.fares = { [2] = { [5] = { c = 50000, t = c.env.time() } } }
    FG.db.travel.preset = "money"
    FG.Planner.Inspect({ data = { name = "Lakeshire", mapID = 1433, x = 0.26, y = 0.55 }, name = "Lakeshire", subtitle = "Redridge Mountains" })
    Planned(c)
    FG.Window.ShowRoute()
    Settle(c, 0.5)
    Shot(c, screen, "route-value")
    for _, o in ipairs(FG.Planner.Current().options) do
        if o.mode.key == "value" then FG.Planner.Select(o) end
    end
    Settle(c, 0.3)
    Shot(c, screen, "route-value-chosen")

    -- Gone another way: flying while the route waits for something else. The window is
    -- closed, as while travelling, so the HUD is what shows.
    FG.Planner.Start()
    FG.Window.Hide()
    Settle(c, 1.5)
    c.player.taxi = true
    Settle(c, 2)
    Shot(c, screen, "nav-flying-elsewhere")
    c:SetPlayer(1455, 0.55, 0.48)
    c.player.taxi = false
    Settle(c, 1)
    Shot(c, screen, "nav-rerouting")
    -- No way found from the landing: said, and tried again later.
    local ns = FG.Bridge.NS()
    Stack.Until(c, function() return not FG.Bridge.IsPlanning() end, 60)
    local build = ns.GPS.BuildStops
    ns.GPS.BuildStops = function() return nil end
    c.player.taxi = true
    Settle(c, 2)
    c:SetPlayer(1437, 0.06, 0.62)
    c.player.taxi = false
    Settle(c, 1.5)
    Shot(c, screen, "nav-unavailable")
    ns.GPS.BuildStops = build
    Settle(c, 15)
    -- The report a player pastes.
    FG.Window.Show("search")
    FG.CopyBox.Show(FG.Diagnostics.Report())
    Settle(c, 0.3)
    Shot(c, screen, "nav-report")
    if c.env.ForeverGPSCopyBox then c.env.ForeverGPSCopyBox:Hide() end
    -- A journey looked at from somewhere else.
    FG.Bridge.Stop()
    Settle(c, 0.5)
    FG.Planner.Inspect({ data = { name = "Lakeshire", mapID = 1433, x = 0.26, y = 0.55 }, name = "Lakeshire", subtitle = "Redridge Mountains",
                         from = { name = "Ironforge", mapID = 1455, x = 0.55, y = 0.48 } })
    Planned(c)
    FG.Window.ShowRoute()
    Settle(c, 0.5)
    Shot(c, screen, "route-from-elsewhere")
    return c
end

local function Journey(c, screen)
    local FG = c.FG
    FG.db.autoClose = false
    FG.Planner.Inspect({ data = AUBERDINE, name = "Auberdine", subtitle = "Darkshore" })
    Planned(c)
    FG.Window.Show("search")
    FG.RoutePanel.Go()
    Settle(c)
    FG.Window.Show("search")
    Settle(c)
    Shot(c, screen, "navigating")
    FG.Window.Hide()
    Settle(c, 0.2)
    for _, mode in ipairs({ "compact", "standard", "detailed" }) do
        FG.db.hud.mode = mode
        FG.Emit("settings:changed")
        Settle(c, 0.3)
        Shot(c, screen, "hud-" .. mode)
    end
    FG.db.hud.mode = "standard"
    FG.Emit("settings:changed")
    local route = FG.Bridge.ActiveRoute()
    local dock = route.steps[1].go
    c.ns.GPSBoats.Aboard = function() return false end
    c:SetPlayer(dock.m, dock.x, dock.y)
    Settle(c, 1)
    Shot(c, screen, "hud-waiting")
    FG.Emit("toast", "Objective done: Young Wolf slain: 8/8", 33, "Next: Turn in to Marshal Dughan", true)
    Settle(c, 0.3)
    Shot(c, screen, "hud-toast")
    FG.Bridge.Stop()
    Settle(c)
    FG.Window.Show("search")
    Settle(c)
    Shot(c, screen, "home-resume")
    FG.Window.Hide()
    FG.Saved.SetResume(nil)
    c.env.ForeverGPSToast:Hide()
    c:SetPlayer(1453, 0.6, 0.6)
    c:Advance(0.2)
    c.ns.GPSBoats.Aboard = nil
end

local function Overlays(c, screen)
    local FG = c.FG
    FG.Quick.Open("repair")
    Settle(c, 0.5)
    Shot(c, screen, "quick")
    c.env.ForeverGPSQuick:Hide()
    FG.CopyBox.Show(FG.Diagnostics.Report())
    Settle(c)
    Shot(c, screen, "report")
    c.env.ForeverGPSCopyBox:Hide()
end

-- The journey on the map, over each kind of ground it has to read on. The grounds
-- are flat colors: the line and the marks are what is being looked at.
local function Map(c, screen)
    local FG = c.FG
    local map = c.env.WorldMapFrame
    local ground = map:CreateTexture(nil, "BACKGROUND")
    ground:SetAllPoints(map)
    map:Show()
    FG.Planner.Inspect({ data = { name = "Gadgetzan", mapID = 1446, x = 0.52, y = 0.28 }, name = "Gadgetzan", subtitle = "Tanaris" })
    Planned(c)
    FG.MapPreview.Open()
    Settle(c, 0.3)
    ground:SetColorTexture(0.25, 0.37, 0.23, 1)
    Shot(c, screen, "map-alternatives")
    FG.MapPreview.NextLeg()
    Settle(c, 0.3)
    Shot(c, screen, "map-next-leg")
    FG.Planner.Inspect({ data = AUBERDINE, name = "Auberdine", subtitle = "Darkshore" })
    Planned(c)
    FG.MapPreview.Open()
    Settle(c, 0.3)
    for _, b in ipairs(BACKDROPS) do
        ground:SetColorTexture(b[2], b[3], b[4], 1)
        Shot(c, screen, "map-" .. b[1])
    end
    FG.MapPreview.Focus(2)
    Settle(c, 0.3)
    ground:SetColorTexture(0.25, 0.37, 0.23, 1)
    Shot(c, screen, "map-focused")
    FG.Planner.Clear()
    map:Hide()
    Settle(c, 0.2)
end

-- A Steam Deck's screen, 1280x800 at the default scale, driven by the controller alone.
local DECK = { "deck", 1280, 800, 800 / 768, "1280x800 (Steam Deck), handheld layout, controller" }

local function PadExtras(c)
    local out = {}
    for _, name in ipairs({ "ForeverGPSKeyboard", "ForeverGPSPadDialog", "ForeverGPSFocusRing" }) do
        local f = c.env[name]
        if f and f._shown then out[#out + 1] = f end
    end
    return out
end

local function Controller(screen)
    local c = NewClient(screen)
    local FG = c.FG
    local function Press(button, times)
        for _ = 1, times or 1 do
            c:PadPress(button)
            Settle(c, 0.05)
        end
    end
    local function PadShot(state) Shot(c, screen, state, PadExtras(c)) end
    c:PadPress("PADDDOWN")
    FG.Window.Show("search")
    Settle(c, 0.3)
    PadShot("pad-intro")
    Press("PAD2")
    Press("PADDDOWN", 2)
    PadShot("pad-home")
    FG.SearchView.Box():SetText("auberdin")
    Press("PAD4")
    for _, key in ipairs({ "PADDRIGHT", "PADDRIGHT" }) do Press(key) end
    PadShot("pad-keyboard")
    Press("PAD4")
    Settle(c, 1)
    PadShot("pad-results")
    Press("PAD1")
    Planned(c)
    PadShot("pad-journey")
    Press("PADRSTICK")
    Settle(c, 0.5)
    Press("PADDRIGHT")
    Settle(c, 0.3)
    Shot(c, screen, "pad-map", PadExtras(c))
    Press("PAD2")
    FG.Planner.Clear()
    Press("PADRSHOULDER")
    Settle(c, 0.5)
    Press("PADDDOWN", 2)
    PadShot("pad-quests")
    Press("PADRSHOULDER")
    Settle(c, 0.3)
    PadShot("pad-professions")
    FG.Window.Show("settings")
    FG.SettingsView.SelectByLabel("SETG_CONTROLLER")
    Settle(c, 0.3)
    FG.Focus.First()
    PadShot("pad-settings")
    FG.PadSettings.Change("search")
    PadShot("pad-press")
    c:PadPress("PAD3")
    Settle(c, 0.1)
    PadShot("pad-clash")
    Press("PAD2")
    print(screen[1], "controller", #c.errors == 0 and "ok" or (#c.errors .. " errors"), c.errors[1] and c.errors[1]:sub(1, 300) or "")
end

local only = arg and arg[1]
if not only or only == "deck" then Controller(DECK) end
for i, screen in ipairs(SCREENS) do
    if not only or only == screen[1] then
        local c = NewClient(screen)
        Pages(c, screen)
        Overlays(c, screen)
        Journey(c, screen)
        if i <= 3 then Map(c, screen) end
        print(screen[1], #c.errors == 0 and "ok" or (#c.errors .. " errors"), c.errors[1] and c.errors[1]:sub(1, 300) or "")
        local t = Trade(screen)
        print(screen[1], "trade", #t.errors == 0 and "ok" or (#t.errors .. " errors"), t.errors[1] and t.errors[1]:sub(1, 300) or "")
        local q = NewClient(screen)
        Quests(q, screen)
        print(screen[1], "quests", #q.errors == 0 and "ok" or (#q.errors .. " errors"), q.errors[1] and q.errors[1]:sub(1, 300) or "")
    end
end

local index = assert(io.open("build/preview/index.html", "w"))
index:write("<!doctype html><meta charset=utf-8><title>Forever-GPS renders</title>",
    "<style>body{font:14px system-ui;margin:24px;background:#14181e;color:#e8ecf1}a{color:#6db6ff}</style>",
    "<h1>Forever-GPS renders</h1><p>Drawn from the addon's real layout code in a stand-in client. Not screenshots of the game.</p><ul>")
for _, page in ipairs(pages) do
    index:write(('<li><a href="%s.html">%s</a> <small>%s</small></li>'):format(page.name, page.name, page.title))
end
index:write("</ul>")
index:close()
print(#pages .. " renders")
