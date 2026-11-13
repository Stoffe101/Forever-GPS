-- Performance baselines in the stand-in client. These run on desktop Lua 5.4 on the
-- developer's machine, not in the game: read them as relative costs and as a guard
-- against regressions, not as what a player's frame will spend.
--
--     lua tools/perf.lua          (from the repository root)
package.path = "tests/?.lua;" .. package.path
local Stack = require("support.stack")

local function Time(n, fn)
    local started = os.clock()
    for i = 1, n do fn(i) end
    return (os.clock() - started) * 1000 / n
end

local function MB()
    collectgarbage("collect")
    collectgarbage("collect")
    return collectgarbage("count") / 1024
end

local rows = {}
local function Row(name, value, unit) rows[#rows + 1] = ("| %s | %.2f %s |"):format(name, value, unit) end

local bare = MB()
local c = Stack.new({ screen = { 1920, 1080, 1.406 }, mapID = 1453, x = 0.6, y = 0.6 })
local FG = c.FG
Row("Lua heap with EasyFind, GPS and Forever-GPS loaded, UI not opened", MB() - bare, "MB")

FG.Bridge.WarmSearch()
c:Advance(2)
FG.Window.Show("search")
c:Advance(0.5)
Row("Lua heap after opening the window and warming search", MB() - bare, "MB")

Row("Search.Run: a place name", Time(50, function() FG.Search.Run("auberdine", "all") end), "ms")
Row("Search.Run: a kind of service", Time(50, function() FG.Search.Run("nearest mailbox", "all") end), "ms")
Row("Search.Run: a misspelling", Time(50, function() FG.Search.Run("auberdene", "all") end), "ms")

local clock = os.clock()
FG.Planner.Inspect({ data = { name = "Auberdine", mapID = 1439, x = 0.37, y = 0.44 }, name = "Auberdine" })
Stack.Until(c, function()
    local p = FG.Planner.Current()
    return p and p.status == "ready"
end, 40)
Row("Planner: every way to a place across a sea, in slices", (os.clock() - clock) * 1000, "ms")

FG.Planner.Start()
c:Advance(1.5)
Row("Journey.View, as the HUD reads it five times a second", Time(1000, function() FG.Journey.View() end), "ms")
FG.db.hud.mode = "detailed"
Row("Journey.View in the detailed HUD, which looks for the next turn", Time(1000, function() FG.Journey.View() end), "ms")
FG.db.hud.mode = "standard"
local view = FG.Journey.View()
Row("HUD.Render", Time(1000, function() FG.HUD.Render(view) end), "ms")

Row("Trip.Order: eight stops, on a cost table", Time(200, function()
    FG.Trip.Order(8, function(a, b) return ((a * 7 + b * 13) % 17) + 1 end)
end), "ms")

local path = "build/perf.md"
local file = assert(io.open(path, "w"))
file:write("| Measure (stand-in client, desktop Lua 5.4) | Value |\n|---|---|\n", table.concat(rows, "\n"), "\n")
file:close()
print(table.concat(rows, "\n"))
print(#c.errors == 0 and "no errors" or c.errors[1])
