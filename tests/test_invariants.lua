-- What must hold whatever the input. Seeded, so a failure repeats. The routes are real
-- ones between places taken from the addon's own data, and the rest is random input
-- thrown at the pure parts.
local T = require("support.t")
local Stack = require("support.stack")

local SEED = 20261106

local function Start(opts)
    opts = opts or {}
    opts.mapID, opts.x, opts.y = opts.mapID or 1453, opts.x or 0.6, opts.y or 0.6
    return Stack.new(opts)
end

local function Random()
    local state = SEED
    return function(n)
        state = (state * 1103515245 + 12345) % 2147483648
        return state % n + 1
    end
end

local tests = {}

function tests.anyOrder_visitsEveryStopOnceAndKeepsItsPromises()
    local c = Start({ ui = false })
    local rnd = Random()
    for _ = 1, 200 do
        local n = rnd(8)
        local grid = {}
        for a = 0, n do
            grid[a] = {}
            for b = 0, n do grid[a][b] = rnd(1000) end
        end
        local before = {}
        if n >= 2 then
            local a, b = rnd(n), rnd(n)
            if a ~= b then before[a] = b end
        end
        local order = c.FG.Trip.Order(n, function(a, b) return grid[a][b] end, before)
        T.eq(#order, n, "every stop")
        local seen, at = {}, {}
        for pos, stop in ipairs(order) do
            T.no(seen[stop], "once")
            seen[stop], at[stop] = true, pos
        end
        for a, b in pairs(before) do T.ok(at[a] < at[b], "what comes first, does") end
    end
end

function tests.refining_neverMakesAnOrderWorse()
    local c = Start({ ui = false })
    local rnd = Random()
    for _ = 1, 100 do
        local n = 3 + rnd(5)
        local x, y = {}, {}
        for i = 0, n do x[i], y[i] = rnd(1000), rnd(1000) end
        local function Cost(a, b) return ((x[a] - x[b]) ^ 2 + (y[a] - y[b]) ^ 2) ^ 0.5 end
        local order = c.FG.Trip.Order(n, Cost)
        -- Against nearest-first done by hand.
        local used, from, plain = {}, 0, 0
        for _ = 1, n do
            local best, bestCost
            for stop = 1, n do
                if not used[stop] and (not best or Cost(from, stop) < bestCost) then best, bestCost = stop, Cost(from, stop) end
            end
            used[best], from, plain = true, best, plain + bestCost
        end
        local total, at = 0, 0
        for _, stop in ipairs(order) do
            total = total + Cost(at, stop)
            at = stop
        end
        T.ok(total <= plain + 0.001, "as good as nearest-first or better")
    end
end

function tests.searchText_neverRaisesWhateverIsTyped()
    local c = Start({ ui = false })
    local rnd = Random()
    local bits = { "", " ", "the", "%", "[", "(", "^", "$", ".*", "|c", "\\", "nearest", "any", "56", "47.2", ",", "aubérdine", "ü", "\t", "'", "\"",
                   "bank stormwind", "Westfall 56 47", "9999 9999", "-1", "0" }
    for _ = 1, 400 do
        local parts = {}
        for i = 1, rnd(4) do parts[i] = bits[rnd(#bits)] end
        local text = table.concat(parts, rnd(2) == 1 and " " or "")
        local ok, err = pcall(c.FG.Search.Run, text, "all")
        T.ok(ok, ("%q raised: %s"):format(text, tostring(err)))
    end
    T.eq(#c.errors, 0)
end

function tests.spellingDistance_behaves()
    local c = Start({ ui = false })
    local Distance = c.FG.Search._Distance
    local rnd = Random()
    local letters = "abcdefghij"
    local function Word()
        local out = {}
        for i = 1, rnd(9) do
            local at = rnd(#letters)
            out[i] = letters:sub(at, at)
        end
        return table.concat(out)
    end
    for _ = 1, 300 do
        local a, b = Word(), Word()
        T.eq(Distance(a, a, 99), 0, "nothing from itself")
        T.eq(Distance(a, b, 99), Distance(b, a, 99), "the same both ways")
        T.ok(Distance(a, b, 99) <= math.max(#a, #b), "never more than rewriting it")
    end
end

function tests.everyTime_readsAsText()
    local c = Start({ ui = false })
    local Format = c.FG.Format
    for _, sec in ipairs({ 0, 0.4, 1, 59, 59.9, 60, 61, 90, 3599, 3600, 3661, 86400, 1e6 }) do
        T.ok(type(Format.Duration(sec)) == "string", "duration")
        T.ok(type(Format.About(sec)) == "string", "about")
        T.ok(type(Format.Clock(sec)) == "string", "clock")
    end
    T.no(Format.Duration(nil))
    T.no(Format.About(nil))
    T.no(Format.About(30):find("~", 1, true), "under a minute needs no tilde")
    for _, yards in ipairs({ 0, 1, 19, 20, 999, 1000, 123456 }) do
        T.ok(type(Format.Yards(yards)) == "string", "yards")
    end
end

function tests.aSharedLine_neverCarriesMarkup()
    local c = Start({ ui = false })
    local rnd = Random()
    local bits = { "|c", "|H", "|r", "|T", "[", "]", "{", "}", "<", ">", "\n", "\r", "\t", "name", "Stormwind", "|", string.rep("x", 60) }
    for _ = 1, 300 do
        local parts = {}
        for i = 1, rnd(6) do parts[i] = bits[rnd(#bits)] end
        local line = c.FG.Saved.ShareLine(table.concat(parts), table.concat(parts), 0.5, 0.5)
        T.no(line:find("|", 1, true), "no escape codes")
        T.no(line:find("[%[%]{}<>%c]"), "no brackets or control characters")
        T.ok(#line < 140, "and it stays short")
    end
end

-- Real journeys between places the addon knows, each checked the same way.
function tests.anyPlan_isCompleteAndLeavesTheGridAlone()
    local PLACES = {
        { "Stormwind", 1453, 0.6, 0.6 }, { "Goldshire", 1429, 0.42, 0.65 }, { "Sentinel Hill", 1436, 0.56, 0.47 },
        { "Ironforge", 1455, 0.55, 0.48 }, { "Menethil", 1437, 0.1, 0.6 }, { "Auberdine", 1439, 0.37, 0.44 },
        { "Orgrimmar", 1454, 0.5, 0.5 }, { "Thunder Bluff", 1456, 0.45, 0.55 }, { "Darkshire", 1431, 0.75, 0.45 },
    }
    local rnd = Random()
    for _ = 1, 12 do
        local from, to = PLACES[rnd(#PLACES)], PLACES[rnd(#PLACES)]
        if from ~= to then
            local c = Start({ ui = false, mapID = from[2], x = from[3], y = from[4] })
            local P = c.FG.Planner
            P.Inspect({ data = { name = to[1], mapID = to[2], x = to[3], y = to[4] }, name = to[1] })
            T.ok(Stack.Until(c, function()
                local plan = P.Current()
                return plan.status ~= "planning" and plan.status ~= "partial"
            end, 40), from[1] .. " to " .. to[1] .. " finishes")
            local plan = P.Current()
            if plan.status == "ready" then
                local option = plan.selected
                T.ok(option.total and option.total >= 0, "a time")
                T.ok(#option.steps > 0, "steps")
                for i, step in ipairs(option.steps) do
                    T.ok(step.text and step.text ~= "", ("%s to %s step %d has words"):format(from[1], to[1], i))
                    T.ok(step.kind ~= nil, "and a kind")
                end
                T.ok(option.quality, "and says how sure it is")
                local names = {}
                for _, o in ipairs(plan.options) do
                    T.no(o.same == o, "a way is not the same as itself")
                    names[o.mode.key] = (names[o.mode.key] or 0) + 1
                end
                for key, n in pairs(names) do T.eq(n, 1, key .. " offered once") end
            end
            local left = c.ns.GPSNav.epoch
            c.FG.Bridge.RestoreNav()
            T.eq(left, c.ns.GPSNav.epoch, "the grid is put back")
            T.eq(#c.errors, 0, from[1] .. " to " .. to[1] .. ": " .. tostring(c.errors[1]))
        end
    end
end

-- A journey across continents never draws a line through the world.
function tests.acrossContinents_noLineCrossesTheSea()
    local c = Start()
    c.env.WorldMapFrame:Show()
    local P = c.FG.Planner
    P.Inspect({ data = { name = "Auberdine", mapID = 1439, x = 0.37, y = 0.44 }, name = "Auberdine" })
    T.ok(Stack.Until(c, function() return P.Current().status == "ready" end, 30), "planned")
    c.FG.MapPreview.Open()
    c:Advance(0.3)
    local drawn = c.FG.MapPreview._Lines().n
    -- On the continent map, where both ends of the crossing could be shown if it were
    -- drawn across: only the walks on this side appear.
    c.env.WorldMapFrame:SetMapID(1415)
    c.FG.MapPreview._Redraw()
    c:Advance(0.3)
    local option = P.Current().selected
    local boat
    for i, step in ipairs(option.steps) do
        if step.kind == "boat" then boat = i end
    end
    T.ok(boat, "a crossing")
    T.ok(option.steps[boat].go.ci ~= option.steps[boat].arrive.ci, "between two continents")
    T.ok(drawn > 0, "the walks are drawn")
    T.no(option.walks[boat], "the crossing has no walk to draw")
end

return tests
