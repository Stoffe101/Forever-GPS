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

local only = arg and arg[1]
for i, screen in ipairs(SCREENS) do
    if not only or only == screen[1] then
        local c = NewClient(screen)
        Pages(c, screen)
        Overlays(c, screen)
        Journey(c, screen)
        if i <= 3 then Map(c, screen) end
        print(screen[1], #c.errors == 0 and "ok" or (#c.errors .. " errors"), c.errors[1] and c.errors[1]:sub(1, 300) or "")
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
