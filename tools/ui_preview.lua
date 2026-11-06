-- Draws the real interface for a person to look at, from the real addon code on
-- the real engine and data, at each target screen.
--
--     lua tools/ui_preview.lua            (from the repository root)
--     python tools/art_png.py             (once, for the icons)
--
-- Writes build/preview/*.html. Screens are pixels wide, tall, and UI scale.
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
    { "3440x1440-s2", 3440, 1440, 2 }, { "3440x1440-s3", 3440, 1440, 3 },
    { "1920x1080-s2", 1920, 1080, 2 }, { "1920x1080-s3", 1920, 1080, 3 },
    { "1920x1080-s1", 1920, 1080, 1 },
}

os.execute(package.config:sub(1, 1) == "\\" and "mkdir build\\preview 2>nul" or "mkdir -p build/preview")

local function Shot(c, name, title)
    local frames = {}
    for _, f in ipairs({ c.env.ForeverGPSWindow, c.env.ForeverGPSHUD, c.env.ForeverGPSMenu }) do
        if f and f._shown then frames[#frames + 1] = f end
    end
    Preview.Write("build/preview/" .. name .. ".html", title, c.root, frames)
end

local function Settle(c)
    Stack.Until(c, function() return false end, 0.6)
end

for _, s in ipairs(SCREENS) do
    local name, w, h, scale = s[1], s[2], s[3], s[4]
    local c = Stack.new({ screen = { w, h, scale }, mapID = 1453, x = 0.6, y = 0.6, questie = QUESTIE, quests = QUEST_LOG, level = 8 })
    local FG = c.FG
    FG.Bridge.WarmSearch()
    Settle(c)
    FG.Window.Show("search")
    Settle(c)
    Shot(c, name .. "-home", "Home " .. name)
    FG.SearchView.Query("repair")
    Settle(c)
    Shot(c, name .. "-search", "Search " .. name)
    FG.Window.Show("search")
    FG.SearchView.Query("auberdine")
    Settle(c)
    local results = FG.SearchView._Results()
    if results[1] then FG.SearchView.Open(results[1]) end
    Stack.Until(c, function()
        local p = FG.Planner.Current()
        return p and (p.status == "ready" or p.status == "failed" or p.status == "unreachable")
    end, 15)
    Settle(c)
    Shot(c, name .. "-route", "Route " .. name)
    FG.Window.Show("quests")
    Settle(c)
    FG.QuestsView.Toggle(33)
    FG.QuestsView.Toggle(18)
    FG.QuestsView.Toggle(99)
    Settle(c)
    Shot(c, name .. "-quests", "Quests " .. name)
    FG.Window.Show("settings")
    Settle(c)
    Shot(c, name .. "-settings", "Settings " .. name)
    FG.Window.Show("search")
    FG.SearchView.Query("auberdine")
    Settle(c)
    results = FG.SearchView._Results()
    if results[1] then FG.SearchView.Open(results[1]) end
    Stack.Until(c, function()
        local p = FG.Planner.Current()
        return p and p.status == "ready"
    end, 15)
    FG.db.autoClose = false
    FG.RoutePanel.Go()
    Settle(c)
    FG.Window.Hide()
    Settle(c)
    Shot(c, name .. "-hud", "HUD " .. name)
    print(name, #c.errors == 0 and "ok" or (#c.errors .. " errors"), c.errors[1] and c.errors[1]:sub(1, 300) or "")
end
