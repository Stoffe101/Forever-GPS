-- Measures the professions and price work in the stand-in client, on desktop Lua.
--
--     lua tools/bench_professions.lua
--
-- Assembles nothing: run `python -I tools/assemble.py --quiet` first. Figures are CPU time
-- on this machine and memory as Lua counts it; the game's Lua 5.1 is slower, and the work
-- is spread over frames there. docs/PERFORMANCE.md keeps the results.
package.path = "tests/?.lua;tests/support/?.lua;" .. package.path
local Stack = require("support.stack")

local function Clock(fn)
    collectgarbage("collect")
    local t0 = os.clock()
    local r = fn()
    return (os.clock() - t0) * 1000, r
end

local function Rows(n)
    local list = {}
    for i = 1, n do list[i] = { itemID = 10000 + i % 6000, count = 1 + i % 20, buyout = 100 * (1 + i % 37) * (1 + i % 20) } end
    return list
end

local out = {}
local function Say(fmt, ...)
    local line = fmt:format(...)
    out[#out + 1] = line
    print(line)
end

-- Data/Recipes.lua: memory once loaded.
do
    collectgarbage("collect")
    local before = collectgarbage("count")
    _G.ForeverGPS = {}
    dofile("addons/ForeverGPS/Data/Recipes.lua")
    collectgarbage("collect")
    Say("Recipe data loaded: %.0f KB", collectgarbage("count") - before)
    _G.ForeverGPS = nil
end

for _, n in ipairs({ 20000, 80000 }) do
    local c = Stack.new({ mapID = 1453, x = 0.6, y = 0.6, ui = false, auctions = Rows(n), recipes = {}, merchant = {},
                          professions = { { name = "Alchemy", skill = 1, max = 75, line = 171 } } })
    c:Advance(4)
    c:Fire("AUCTION_HOUSE_SHOW")
    c.FG.Market.Scan()
    local ms = Clock(function()
        Stack.Until(c, function() return c.FG.Market.Scanning().state == "done" end, 600)
    end)
    local kept = 0
    for _, v in pairs(c.FG.db.market.houses[c.FG.Market.Key()].items) do kept = kept + #v + 8 end
    Say("Full scan of %d listings: %.0f ms CPU in all (read 4 ms a frame), %d items, about %.0f KB saved", n, ms,
        c.FG.Market.Summary().count, kept / 1024)
end

do
    local c = Stack.new({ mapID = 1453, x = 0.6, y = 0.6, ui = false, recipes = {}, merchant = {}, auctions = {},
                          professions = { { name = "Leatherworking", skill = 1, max = 300, line = 165 } } })
    c:Advance(4)
    c.openProfession = c.professions[1]
    c.FG.Professions.Refresh()
    c.FG.db.market = c.FG.db.market or { houses = {}, vendor = {} }
    local ms, list = Clock(function() return c.FG.Professions.Obtainable(165) end)
    Say("Recipes to learn for leatherworking: %d, %.0f ms the first time (parsing)", #list, ms)
    for id in pairs(c.FG.RecipeData.recipes) do
        local d = c.FG.Professions.Data(id)
        if d.line == 165 then for _, g in ipairs(d.reagents) do c.FG.db.market.vendor[g.id] = 10 + g.id % 90 end end
    end
    local planMs, plan = Clock(function()
        return c.FG.Crafting.Plan(165, 1, 300, "upfront", { coverage = "obtainable", learnUnknownFree = true })
    end)
    Say("Plan 1 to 300 over every leatherworking recipe: %.0f ms CPU (spread over frames, 6 ms each), %d segments", planMs, #plan.segments)
    local shortMs, short = Clock(function()
        return c.FG.Crafting.Plan(165, 40, 46, "upfront", { coverage = "obtainable", learnUnknownFree = true })
    end)
    Say("Plan 40 to 46 (solved exactly: %s): %.0f ms", tostring(short.exact), shortMs)
end

do
    local c = Stack.new({ mapID = 1453, x = 0.6, y = 0.6, ui = false, recipes = {}, merchant = {}, auctions = {} })
    c:Advance(4)
    local ladder = {}
    for i = 1, 10 do ladder[i] = { 100 + i * 7, 3 + i } end
    local price = { buy = 107, units = 200, ladder = ladder, sure = "fresh" }
    local ms = Clock(function()
        for _ = 1, 10000 do c.FG.Quote.Buy(900, 40, { price = price }) end
    end)
    Say("Pricing 40 units along 10 tiers: %.1f microseconds each", ms * 1000 / 10000)
    local offers = {}
    for i = 1, 30 do offers[i] = { 50 + i, 1 + i % 5 } end
    local whole = { buy = 51, units = 90, ladder = offers, sure = "fresh" }
    ms = Clock(function()
        for _ = 1, 100 do c.FG.Quote.Buy(900, 40, { price = whole, whole = true, noVendor = true }) end
    end)
    Say("40 units from 30 whole auctions (covering knapsack): %.2f ms each", ms / 100)
end

local f = io.open("build/bench_professions.txt", "w")
if f then
    f:write(table.concat(out, "\n"), "\n")
    f:close()
end
