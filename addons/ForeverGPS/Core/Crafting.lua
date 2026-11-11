-- What crafting costs and earns, the cheapest way up a profession, and lists of what to make.
-- Prices come from FG.Market and FG.Quote; recipes, colours and chances from FG.Professions.
-- Every figure says what it rests on, and a figure missing a price is shown as incomplete,
-- never as a smaller number. docs/PROFESSIONS.md.
--
-- Quantities matter: buying forty of a herb walks up its price tiers, and a merchant's stock
-- is a tier without end. What is in the bags is used once, across a whole plan or list, not
-- once per craft.
local FG = ForeverGPS
local Craft = {}
FG.Crafting = Craft

local Prof, Market = FG.Professions, FG.Market

local AUCTION_CUT = 0.05     -- the house's share of a sale (CraftProfit measured it: F5)
local MAX_DEPTH = 4          -- intermediate crafts this deep at most
local SAFE_Z = 1.645         -- a shopping quantity enough 19 times in 20
Craft.AUCTION_CUT, Craft.SAFE_Z = AUCTION_CUT, SAFE_Z

local function Yield(r) return ((r.qmin or 1) + (r.qmax or r.qmin or 1)) / 2 end
Craft.Yield = Yield

-- ==== buying, unit by unit ==================================================

-- An item's tiers to buy along: the cheapest listings, then a merchant's price for ever.
-- nil when nothing is known.
local function Tiers(itemID)
    local price = Market.Price(itemID)
    local vendor = Market.VendorBuy(itemID)
    if not price and not vendor then return nil end
    local tiers = {}
    for _, t in ipairs(price and price.ladder or {}) do
        if vendor and vendor <= t[1] then break end
        tiers[#tiers + 1] = { t[1], t[2] }
    end
    if vendor then tiers[#tiers + 1] = { vendor, math.huge } end
    return tiers, price
end

-- What units x0 to x1 of an item cost (x may be fractional: an expected quantity), and how
-- many of them cannot be bought from what is known.
local function CostBetween(tiers, x0, x1)
    if x1 <= x0 then return 0, 0 end
    local cost, at = 0, 0
    for _, t in ipairs(tiers) do
        local top = at + t[2]
        local lo, hi = math.max(at, x0), math.min(top, x1)
        if hi > lo then cost = cost + (hi - lo) * t[1] end
        at = top
        if at >= x1 then return cost, 0 end
    end
    return cost, x1 - math.max(at, x0)
end

-- A book of what a plan or list has used: free units in hand, and units bought so far, so
-- the next unit is priced where the last left off.
local function NewBook(owned)
    return { stock = {}, used = {}, bought = {}, tiers = {}, owned = owned }
end

local function BookTiers(book, id)
    local t = book.tiers[id]
    if t == nil then
        t = Tiers(id) or false
        book.tiers[id] = t
    end
    return t or nil
end

local function Free(book, id)
    if not book.owned then return 0 end
    if book.stock[id] == nil then book.stock[id] = FG.Item.Count(id) end
    return math.max(0, book.stock[id] - (book.used[id] or 0))
end

-- Takes q units of an item (fractional allowed): from hand first, then bought. Returns cost,
-- units short (cannot be bought), and nil when nothing about it is known.
local function Take(book, id, q, dry)
    local free = math.min(q, Free(book, id))
    local buy = q - free
    local cost, short = 0, 0
    if buy > 0 then
        local tiers = BookTiers(book, id)
        if not tiers then
            if not dry then book.used[id] = (book.used[id] or 0) + free end
            return nil, buy
        end
        local before = book.bought[id] or 0
        cost, short = CostBetween(tiers, before, before + buy)
        if not dry then book.bought[id] = before + buy end
    end
    if not dry then book.used[id] = (book.used[id] or 0) + free end
    return cost, short
end

-- ==== one recipe ============================================================

-- What `times` crafts' reagents cost, bought the cheapest way for the whole quantity.
-- copper, missing (reagents with no price), parts, short (units that cannot be bought).
-- opts.owned: what is in the bags is used first, at no cash cost. opts.book: share a book.
function Craft.MaterialCost(r, opts)
    opts = opts or {}
    local book = opts.book or NewBook(opts.owned)
    local times = opts.times or 1
    local copper, missing, parts, short = 0, {}, {}, 0
    for _, g in ipairs(r.reagents or {}) do
        local need = g.n * times
        local have = math.min(need, Free(book, g.id))
        local cost, lack = Take(book, g.id, need, opts.dry)
        if cost == nil then
            missing[#missing + 1] = g.id
        else
            copper = copper + cost
            short = short + lack
            if lack > 0 then missing[#missing + 1] = g.id end
        end
        local tiers = BookTiers(book, g.id)
        parts[#parts + 1] = { id = g.id, need = need, have = have, cost = cost, short = lack,
                              unit = tiers and tiers[1][1] or nil,
                              from = tiers and (tiers[1][2] == math.huge and "vendor" or "auction") or nil }
    end
    return math.floor(copper + 0.5), missing, parts, short
end

-- What selling one craft's output brings, and where: the current lowest buyout less the
-- house's cut, if it sold at that, or what a merchant pays, whichever is more. Posted is not
-- sold: the figure says "if it sells at the lowest price listed now".
function Craft.SaleValue(r)
    if not r.out then return nil end
    local yield = Yield(r)
    local price = Market.Price(r.out)
    local auction = price and math.floor(price.buy * (1 - AUCTION_CUT)) or nil
    local vendor = Market.VendorSell(r.out)
    if auction and (not vendor or auction >= vendor) then return auction * yield, "auction", price end
    if vendor then return vendor * yield, "vendor", price end
    return nil, nil, price
end

-- Everything the profit page shows for a recipe, kept apart:
--   cost      the reagents at today's prices, one craft
--   upfront   what buying them costs now, after what is in the bags
--   sale      the output at today's lowest listing, less the cut ("if it sells")
--   recovery  what a merchant pays for the output: the floor, sold or not
--   profit    sale - cost: a hypothetical margin, not a sale
function Craft.Profit(r, times)
    times = math.max(1, times or 1)
    local cost, missing = Craft.MaterialCost(r, { times = times })
    local upfront = Craft.MaterialCost(r, { owned = true, times = times })
    local sale, where, price = Craft.SaleValue(r)
    if sale then sale = sale * times end
    local recovery = r.out and Market.VendorSell(r.out)
    local p = { recipe = r, times = times, cost = cost, upfront = upfront, missingPrices = #missing, missing = missing,
                sale = sale, where = where, price = price, recovery = recovery and recovery * Yield(r) * times or nil }
    p.complete = #missing == 0 and sale ~= nil
    if p.complete then
        p.profit = math.floor(sale - cost)
        p.share = cost > 0 and p.profit / cost or nil
    end
    if #missing == 0 and p.recovery then p.recoveryShare = cost > 0 and p.recovery / cost or nil end
    -- How sure: the oldest price used, and whether anyone else is selling it at all.
    p.sure = price and price.sure or (where == "vendor" and "vendor" or nil)
    p.listed = price and price.units or 0
    p.canMake = Craft.CanMake(r)
    return p
end

-- How many can be made from what is in the bags now.
function Craft.CanMake(r)
    local n
    for _, g in ipairs(r.reagents or {}) do
        local k = math.floor(FG.Item.Count(g.id) / g.n)
        n = n and math.min(n, k) or k
    end
    return n or 0
end

local SORTS = {
    profit = function(a, b) return (a.profit or -math.huge) > (b.profit or -math.huge) end,
    share = function(a, b) return (a.share or -math.huge) > (b.share or -math.huge) end,
    cheap = function(a, b) return (a.upfront or math.huge) < (b.upfront or math.huge) end,
    -- Confidence first: priced from a fresh scan, with others selling it too.
    safe = function(a, b)
        local x = (a.sure == "fresh" and 2 or a.sure == "recent" and 1 or 0) + (a.listed > 0 and 1 or 0)
        local y = (b.sure == "fresh" and 2 or b.sure == "recent" and 1 or 0) + (b.listed > 0 and 1 or 0)
        if x ~= y then return x > y end
        return (a.profit or -math.huge) > (b.profit or -math.huge)
    end,
    -- What a merchant gives back for the reagents' cost: the least that can be lost.
    recovery = function(a, b) return (a.recoveryShare or -math.huge) > (b.recoveryShare or -math.huge) end,
}
Craft.SORTS = { "profit", "share", "cheap", "safe", "recovery" }

local FILTERS = {
    complete = function(p) return p.complete end,
    makeable = function(p) return p.canMake > 0 end,
    sellers = function(p) return p.listed > 0 end,
    gain = function(p) return p.complete and p.profit > 0 end,
}
Craft.FILTERS = { "complete", "makeable", "sellers", "gain" }

-- Every learned recipe that makes something, by sort, kept by every filter in `only`.
-- Incomplete ones go last.
function Craft.Ranking(line, sort, only, times)
    local out = {}
    for _, r in ipairs(Prof.Recipes(line)) do
        if r.learned and r.out then
            local p = Craft.Profit(r, times)
            local keep = true
            for key in pairs(only or {}) do
                if FILTERS[key] and not FILTERS[key](p) then keep = false end
            end
            if keep then out[#out + 1] = p end
        end
    end
    local by = SORTS[sort or "profit"] or SORTS.profit
    table.sort(out, function(a, b)
        if a.complete ~= b.complete then return a.complete end
        if by(a, b) ~= by(b, a) then return by(a, b) end
        return (a.recipe.name or "") < (b.recipe.name or "")
    end)
    return out
end

-- Items a profession's learned recipes need priced: reagents with no price, and outputs
-- with neither a listing nor a merchant's figure. For a targeted refresh, at most `most`.
function Craft.MissingPrices(line, most)
    local out, seen = {}, {}
    most = most or 30
    local function Add(id)
        if id and not seen[id] and #out < most then
            seen[id] = true
            out[#out + 1] = id
        end
    end
    for _, r in ipairs(Prof.Recipes(line)) do
        if r.learned then
            for _, g in ipairs(r.reagents or {}) do
                if not Market.Cost(g.id) then Add(g.id) end
            end
            if r.out and not Market.Price(r.out) then Add(r.out) end
        end
    end
    return out
end

-- ==== the way up ============================================================

Craft.MODES = { "upfront", "net", "mine" }
Craft.COVERAGE = { "known", "obtainable" }

-- What learning a recipe costs once: its recipe item's price, or unknown (a trainer's
-- recipe cost is not known until its window is read). nil, how: no figure.
local function LearnCost(r)
    if r.learned then return 0, nil end
    local d = r.data or Prof.Data(r.id)
    if d and d.items[1] then
        local unit = Market.Cost(d.items[1].id)
        return unit, "item"
    end
    return nil, "trainer"
end

-- The recipes a plan may use, each with what it rests on.
local function Candidates(line, coverage)
    local out = {}
    for _, r in ipairs(Prof.Recipes(line)) do
        if r.learned and r.reagents then out[#out + 1] = r end
    end
    if coverage == "obtainable" then
        for _, r in ipairs(Prof.Obtainable(line)) do out[#out + 1] = r end
    end
    return out
end

-- Everything a whole assignment of recipes to skill points costs: reagents bought in their
-- total quantities, what is in hand used first, each new recipe learned once. Returns the
-- total (nil when something is not priced or cannot be bought) and its book.
local function Total(assign, chances, mode, opts)
    local book = NewBook(mode == "mine")
    local runs = {}
    for k, r in ipairs(assign) do runs[r] = (runs[r] or 0) + 1 / chances[k] end
    local total = 0
    local qty = {}
    for r, n in pairs(runs) do
        for _, g in ipairs(r.reagents or {}) do qty[g.id] = (qty[g.id] or 0) + g.n * n end
        if not r.learned then
            local learn = LearnCost(r)
            if learn == nil and not opts.learnUnknownFree then return nil end
            total = total + (learn or 0)
        end
        if mode == "net" then
            local sale = Craft.SaleValue(r)
            total = total - (sale or 0) * n
        end
    end
    for id, q in pairs(qty) do
        local cost, short = Take(book, id, q)
        if cost == nil or short > 1e-9 then return nil end
        total = total + cost
    end
    return total, book, runs
end
Craft._Total = Total

local EXACT_PLANS = 4096     -- a climb with at most this many plans is solved by trying them all
local PAIRS_UP_TO = 40       -- points: past this, pairs of changes are not tried
local KEEP_OPTIONS = 4       -- choices per point the long-climb search weighs
local MOST_TOTALS = 30000    -- whole-plan totals the search may work out
Craft.KEEP_OPTIONS, Craft.MOST_TOTALS = KEEP_OPTIONS, MOST_TOTALS

-- The cheapest assignment found, written into points/chances/sources; returns its total.
-- A short climb tries every plan: exact. A longer one improves the greedy plan by changing
-- one point, then two points at once, while the whole total falls: very close, not proven.
function Craft._Improve(points, chances, sources, options, total, mode, opts)
    local n = #points
    local plans = 1
    for k = 1, n do
        plans = plans * math.max(1, #options[k])
        if plans > EXACT_PLANS then break end
    end
    Craft._lastExact = false
    if plans <= EXACT_PLANS and not opts.noExact then
        local best, bestPick = total, nil
        local pick = {}
        local function Try(k)
            if k > n then
                local t = Total(points, chances, mode, opts)
                if t and (not best or t < best - 1e-9) then
                    best = t
                    bestPick = {}
                    for i = 1, n do bestPick[i] = pick[i] end
                end
                return
            end
            for i, o in ipairs(options[k]) do
                points[k], chances[k], pick[k] = o.r, o.chance, i
                Try(k + 1)
            end
        end
        local keep = {}
        for k = 1, n do keep[k] = sources[k] end
        Try(1)
        for k = 1, n do
            local o = bestPick and options[k][bestPick[k]] or keep[k]
            points[k], chances[k], sources[k] = o.r, o.chance, o
        end
        Craft._lastExact = true
        return best
    end
    if not total then return nil end
    -- The few cheapest choices at each point, as the greedy pass priced them.
    for k = 1, n do
        local list = options[k]
        if #list > KEEP_OPTIONS then
            table.sort(list, function(x, y) return (x.cost or math.huge) < (y.cost or math.huge) end)
            local kept = {}
            for i = 1, KEEP_OPTIONS do kept[i] = list[i] end
            local present = false
            for _, o in ipairs(kept) do if o.r == points[k] then present = true end end
            if not present then kept[#kept + 1] = sources[k] end
            options[k] = kept
        end
    end
    local function Set(k, o) points[k], chances[k], sources[k] = o.r, o.chance, o end
    local spent = 0
    local function Within()
        spent = spent + 1
        return spent <= MOST_TOTALS
    end
    local improved, rounds = true, 0
    while improved and rounds < 8 do
        improved, rounds = false, rounds + 1
        for k = 1, n do
            if opts.yield then opts.yield() end
            for _, o in ipairs(options[k]) do
                if o.r ~= points[k] and Within() then
                    local was = sources[k]
                    Set(k, o)
                    local t = Total(points, chances, mode, opts)
                    if t and t < total - 1e-6 then
                        total, improved = t, true
                    else
                        Set(k, was)
                    end
                end
            end
        end
        if not improved and n <= PAIRS_UP_TO then
            for k1 = 1, n - 1 do
                if opts.yield then opts.yield() end
                for k2 = k1 + 1, n do
                    for _, o1 in ipairs(options[k1]) do
                        for _, o2 in ipairs(options[k2]) do
                            if (o1.r ~= points[k1] or o2.r ~= points[k2]) and Within() then
                                local was1, was2 = sources[k1], sources[k2]
                                Set(k1, o1)
                                Set(k2, o2)
                                local t = Total(points, chances, mode, opts)
                                if t and t < total - 1e-6 then
                                    total, improved = t, true
                                else
                                    Set(k1, was1)
                                    Set(k2, was2)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return total
end

-- The cheapest expected way from skill a to b.
--   Greedy first: at each point, the recipe whose next crafts cost least given what has
--   been used so far. Then the whole plan is improved: each point tries every other recipe,
--   and a change is kept when the whole plan's total falls, until none does. With prices
--   flat and nothing in hand, the greedy plan is already the cheapest; with tiers, bags and
--   recipes to learn it may not be. Small cases are checked against every plan in the tests.
-- opts.coverage: "known" (default) or "obtainable"; opts.learnUnknownFree: count a
-- trainer's unknown recipe cost as nothing (the plan says so).
-- { segments = { from, to, recipe, crafts, safe, cost, sure, source }, total, train,
--   learn = { at, recipe, how, cost }, stuck, stuckWhy, unsure, shopping }
function Craft.Plan(line, a, b, mode, opts)
    mode, opts = mode or "upfront", opts or {}
    local p = Prof.Get(line)
    local recipes = Candidates(line, opts.coverage)
    local out = { segments = {}, total = 0, train = {}, learn = {}, shopping = {}, coverage = opts.coverage or "known" }
    local cap = p and p.max or b
    local points, chances, sources, options = {}, {}, {}, {}
    local book = NewBook(mode == "mine")
    local chosen = {}
    local s = a
    while s < b do
        if s >= cap then
            local next = Prof.NextRank({ skill = s, max = cap })
            if not next then
                out.stuck, out.stuckWhy = s, "rank"
                break
            end
            out.train[#out.train + 1] = { at = s, cap = next.cap, name = next.name }
            cap = next.cap
        end
        -- The choices at this point, and the greedy pick among them.
        local here, best, bestCost = {}, nil, nil
        if opts.yield then opts.yield() end
        if opts.progress then opts.progress(s - a, b - a) end
        for _, r in ipairs(recipes) do
            local learnAt = r.learned and 0 or (r.learnAt or 0)
            local chance, sure, source = Prof.Chance(r, s)
            if chance and chance > 0 and learnAt <= s then
                local o = { r = r, chance = chance, sure = sure, source = source }
                here[#here + 1] = o
                local cost = 0
                for _, g in ipairs(r.reagents or {}) do
                    local c, short = Take(book, g.id, g.n / chance, true)
                    if c == nil or short > 1e-9 then
                        cost = nil
                        break
                    end
                    cost = cost + c
                end
                if cost and not r.learned and not chosen[r] then
                    -- A recipe still to learn pays for it once, on the first point that uses it.
                    local learn = LearnCost(r)
                    if learn == nil and not opts.learnUnknownFree then cost = nil end
                    if cost then cost = cost + (learn or 0) end
                end
                if cost and mode == "net" then cost = cost - (Craft.SaleValue(r) or 0) / chance end
                o.cost = cost
                if cost and (not bestCost or cost < bestCost or (cost == bestCost and r.id < best.r.id)) then
                    best, bestCost = o, cost
                end
            end
        end
        if not best then
            out.stuck, out.stuckWhy = s, #here == 0 and "recipes" or "prices"
            break
        end
        for _, g in ipairs(best.r.reagents or {}) do Take(book, g.id, g.n / best.chance) end
        chosen[best.r] = true
        points[#points + 1], chances[#chances + 1], sources[#sources + 1] = best.r, best.chance, best
        options[#options + 1] = here
        s = s + 1
    end
    local total = #points > 0 and Total(points, chances, mode, opts) or 0
    if #points > 0 then
        total = Craft._Improve(points, chances, sources, options, total, mode, opts)
        out.exact = Craft._lastExact
    end
    out.total = total and math.floor(total + 0.5) or nil
    if not total and #points > 0 then out.incomplete = true end
    -- Segments, with each point's cost as the final plan's own book prices it, in order.
    local seq = NewBook(mode == "mine")
    local learnedSeen = {}
    for k, r in ipairs(points) do
        local o = sources[k]
        local cost = 0
        for _, g in ipairs(r.reagents or {}) do cost = cost + (Take(seq, g.id, g.n / o.chance) or 0) end
        if not r.learned and not learnedSeen[r] then
            learnedSeen[r] = true
            local learn, how = LearnCost(r)
            out.learn[#out.learn + 1] = { at = a + k - 1, recipe = r, how = how, cost = learn }
            if learn == nil then out.learnUnknown = true end
            cost = cost + (learn or 0)
        end
        if mode == "net" then cost = cost - (Craft.SaleValue(r) or 0) / o.chance end
        local last = out.segments[#out.segments]
        local var = (1 - o.chance) / (o.chance * o.chance)
        if last and last.recipe == r then
            last.to, last.crafts, last.cost, last.var = a + k, last.crafts + 1 / o.chance, last.cost + cost, last.var + var
            last.sure = last.sure and o.sure
            if o.source ~= "client" then last.source = o.source end
        else
            out.segments[#out.segments + 1] = { from = a + k - 1, to = a + k, recipe = r, crafts = 1 / o.chance, cost = cost,
                                                sure = o.sure, source = o.source, var = var }
        end
        if not o.sure then out.unsure = true end
    end
    -- Expected crafts, and enough to be safe 19 times in 20; what to buy for each.
    local buy = {}
    for _, seg in ipairs(out.segments) do
        seg.expected = seg.crafts
        seg.crafts = math.ceil(seg.crafts - 0.001)
        seg.safe = math.max(seg.crafts, math.ceil(seg.expected + SAFE_Z * math.sqrt(seg.var) - 0.001))
        seg.cost = math.floor(seg.cost + 0.5)
        for _, g in ipairs(seg.recipe.reagents or {}) do
            local row = buy[g.id] or { id = g.id, expected = 0, safe = 0 }
            buy[g.id] = row
            row.expected = row.expected + g.n * seg.expected
            row.safe = row.safe + g.n * seg.safe
        end
    end
    for id, row in pairs(buy) do
        row.expected = math.ceil(row.expected - 0.001)
        row.have = mode == "mine" and math.min(row.safe, FG.Item.Count(id)) or 0
        local q = FG.Quote.Buy(id, math.max(0, row.safe - row.have))
        row.cost, row.short, row.status = q.cost, q.remaining, q.status
        out.shopping[#out.shopping + 1] = row
    end
    table.sort(out.shopping, function(x, y) return x.id < y.id end)
    -- Training: who is known to teach it, and what it asks.
    for _, t in ipairs(out.train) do
        for npc, entry in pairs(FG.db.trainers or {}) do
            local yes, rank = FG.Trainers.Teaches(npc, line, t.cap)
            if yes then
                t.known = (t.known or 0) + 1
                t.level = t.level and rank.level and math.min(t.level, rank.level) or t.level or rank.level
                t.cost = t.cost and rank.cost and math.min(t.cost, rank.cost) or t.cost or rank.cost
                t.trainer = t.trainer or entry.name
            end
        end
    end
    return out
end

-- A plan worked out a few milliseconds a frame, as the route planner does: a whole climb
-- over hundreds of recipes would otherwise hold the game for a moment. done(plan) once it
-- is there. A newer request replaces an older one, whose done is never called.
local planFrame = CreateFrame("Frame")
local SLICE_MS = 6
local running

function Craft.PlanAsync(line, a, b, mode, opts, done)
    opts = opts or {}
    local sliceEnd = 0
    opts.yield = function()
        if debugprofilestop() > sliceEnd then coroutine.yield() end
    end
    local co = coroutine.create(function() return Craft.Plan(line, a, b, mode, opts) end)
    running = co
    planFrame:SetScript("OnUpdate", function()
        if running ~= co then return end
        sliceEnd = debugprofilestop() + SLICE_MS
        FG.Metrics.Begin("craftPlan")
        local ok, plan = coroutine.resume(co)
        FG.Metrics.End("craftPlan")
        if not ok then
            -- Said, not swallowed: the page shows the message and offers to try again.
            running = nil
            planFrame:SetScript("OnUpdate", nil)
            Craft.lastError = tostring(plan)
            FG.Metrics.Note("plan failed: " .. tostring(plan))
            return done(nil, plan)
        end
        if coroutine.status(co) == "dead" then
            running = nil
            planFrame:SetScript("OnUpdate", nil)
            Craft.lastPlan = { total = plan and plan.total, stuck = plan and plan.stuck, why = plan and plan.stuckWhy,
                               segments = plan and #plan.segments or 0, at = time() }
            done(plan)
        end
    end)
end

function Craft.Planning() return running ~= nil end

-- ==== lists =================================================================

local function Projects()
    local c = FG.char
    if not c then return {} end
    c.projects = c.projects or {}
    return c.projects
end

function Craft.Projects() return Projects() end

function Craft.NewProject(name)
    local list = Projects()
    local project = { name = name, items = {}, marks = {}, choose = {} }
    list[#list + 1] = project
    FG.Emit("projects:changed")
    return project
end

function Craft.AddToProject(project, recipeID, qty)
    for _, item in ipairs(project.items) do
        if item.recipe == recipeID then
            item.qty = item.qty + (qty or 1)
            FG.Emit("projects:changed")
            return item
        end
    end
    local item = { recipe = recipeID, qty = qty or 1 }
    project.items[#project.items + 1] = item
    FG.Emit("projects:changed")
    return item
end

function Craft.Remove(project, index)
    table.remove(project.items, index)
    FG.Emit("projects:changed")
end

-- The recipe that makes an item, if this character knows one.
local function MakerOf(itemID)
    for _, r in ipairs(Prof.Recipes()) do
        if r.learned and r.out == itemID then return r end
    end
end
Craft.MakerOf = MakerOf

-- Cheapest unit price of an item, buying it or making it, through at most MAX_DEPTH
-- crafts, never round a cycle. Returns copper (nil if unknown), "buy" or "craft", the maker.
local function UnitCost(itemID, depth, seen)
    local buy = Market.Cost(itemID)
    local maker = depth < MAX_DEPTH and not seen[itemID] and MakerOf(itemID)
    if not maker then return buy, buy and "buy" or nil end
    seen[itemID] = true
    local total = 0
    for _, g in ipairs(maker.reagents or {}) do
        local unit = UnitCost(g.id, depth + 1, seen)
        if not unit then
            total = nil
            break
        end
        total = total + unit * g.n
    end
    seen[itemID] = nil
    local made = total and total / Yield(maker)
    if made and (not buy or made < buy) then return made, "craft", maker end
    return buy, buy and "buy" or nil, maker
end
Craft._UnitCost = function(itemID) return UnitCost(itemID, 0, {}) end

-- Make or buy a reagent on a list: the player's choice when set, else the cheaper.
-- project.choose[itemID] = "craft" | "buy" | nil.
function Craft.Choose(project, itemID, how)
    project.choose = project.choose or {}
    project.choose[itemID] = how
    FG.Emit("projects:changed")
end

-- Every reagent a project needs, merged across its recipes, with what is in the bags (and
-- the bank, when the game says), what is left to get, and what buying that quantity costs.
-- With craft = true, a reagent this character can make (more cheaply, or because the player
-- chose to) is broken into its own reagents, and the batches' surplus is said.
-- rows: { id, need, bags, bank, left, cost, unit, from, short, status, mark, makes = recipe,
--         choice, alts = { "Name-Realm", ... } }; crafts: { id, recipe, runs, surplus }.
function Craft.Shopping(project, craft)
    local need, order, crafts = {}, {}, {}
    local makeable = {}
    project.choose = project.choose or {}
    local function Add(itemID, n, depth, seen)
        local maker = craft and depth < MAX_DEPTH and not seen[itemID] and MakerOf(itemID)
        local choice = project.choose[itemID]
        if maker then
            makeable[itemID] = maker
            local _, how = UnitCost(itemID, depth, {})
            if choice == "craft" or (choice == nil and how == "craft") then
                seen[itemID] = true
                local runs = math.ceil(n / Yield(maker))
                local c = crafts[itemID] or { id = itemID, recipe = maker, runs = 0, made = 0, wanted = 0 }
                crafts[itemID] = c
                c.runs, c.made, c.wanted = c.runs + runs, c.made + runs * Yield(maker), c.wanted + n
                for _, g in ipairs(maker.reagents or {}) do Add(g.id, g.n * runs, depth + 1, seen) end
                seen[itemID] = nil
                return
            end
        end
        if not need[itemID] then
            need[itemID] = 0
            order[#order + 1] = itemID
        end
        need[itemID] = need[itemID] + n
    end
    for _, item in ipairs(project.items) do
        local r = Prof.Recipe(item.recipe)
        local runs = r and math.ceil(item.qty / Yield(r)) or 0
        for _, g in ipairs(r and r.reagents or {}) do Add(g.id, g.n * runs, 0, {}) end
    end
    local rows, total, unknown, short = {}, 0, 0, 0
    for _, itemID in ipairs(order) do
        local bags = FG.Item.Count(itemID)
        local all = math.max(bags, FG.Item.Count(itemID, true))
        local left = math.max(0, need[itemID] - bags)
        local mark = project.marks[itemID]
        if mark == "bought" or mark == "have" then left = 0 end
        local q = FG.Quote.Buy(itemID, left)
        local unit, from = Market.Cost(itemID)
        rows[#rows + 1] = { id = itemID, need = need[itemID], bags = bags, bank = all - bags, left = left,
                            cost = q.status == "known" and q.cost or nil, short = q.remaining, status = q.status,
                            fromVendor = q.fromVendor, unit = unit, from = from, mark = mark,
                            makes = makeable[itemID], choice = project.choose[itemID],
                            alts = FG.Alts and FG.Alts.WhoMakes(itemID) or nil }
        if left > 0 then
            if q.status ~= "known" then
                unknown = unknown + 1
            else
                total = total + q.cost
                if q.remaining > 0 then short = short + 1 end
            end
        end
    end
    local made = {}
    for _, c in pairs(crafts) do
        c.surplus = math.max(0, math.floor(c.made - c.wanted + 0.5))
        made[#made + 1] = c
    end
    table.sort(made, function(x, y) return x.id < y.id end)
    return { rows = rows, total = total, unknown = unknown, short = short, crafts = made }
end

-- A list as plain text, to copy out of the game: one line per item still to get.
function Craft.ShoppingText(project, craft)
    local shop = Craft.Shopping(project, craft)
    local lines = { project.name }
    for _, row in ipairs(shop.rows) do
        if row.left > 0 then
            local name = FG.Item.Label(row.id)
            lines[#lines + 1] = ("%s x%d"):format(name, row.left)
        end
    end
    return table.concat(lines, "\n"), shop
end

-- A material's state on the list, set by hand and never overwritten: nil, "bought", "have".
function Craft.Mark(project, itemID, mark)
    project.marks[itemID] = mark
    FG.Emit("projects:changed")
end
