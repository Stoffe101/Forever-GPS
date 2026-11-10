-- What crafting costs and earns, the cheapest way up a profession, and lists of what to make.
-- Prices come from FG.Market; recipes, colours and chances from FG.Professions. Every figure
-- says what it rests on, and a figure missing a price is shown as incomplete, never as a
-- smaller number. docs/PROFESSIONS.md.
local FG = ForeverGPS
local Craft = {}
FG.Crafting = Craft

local Prof, Market = FG.Professions, FG.Market

local AUCTION_CUT = 0.05     -- the house's share of a sale
local MAX_DEPTH = 4          -- intermediate crafts this deep at most

-- ==== one recipe ============================================================

local function Yield(r) return ((r.qmin or 1) + (r.qmax or r.qmin or 1)) / 2 end

-- What one craft's reagents cost, the cheapest way for each. copper, and missing: the
-- reagents with no price at all. owned: subtract what is in the bags, at no cash cost.
function Craft.MaterialCost(r, opts)
    opts = opts or {}
    local copper, missing, parts = 0, {}, {}
    for _, g in ipairs(r.reagents or {}) do
        local unit, from = Market.Cost(g.id)
        local need = g.n * (opts.times or 1)
        local have = opts.owned and math.min(need, GetItemCount(g.id) or 0) or 0
        local buy = need - have
        if unit then
            copper = copper + unit * buy
        elseif buy > 0 then
            missing[#missing + 1] = g.id
        end
        parts[#parts + 1] = { id = g.id, need = need, have = have, unit = unit, from = from }
    end
    return copper, missing, parts
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

-- Everything the profit page shows for a recipe.
function Craft.Profit(r)
    local cost, missing = Craft.MaterialCost(r)
    local sale, where, price = Craft.SaleValue(r)
    local p = { recipe = r, cost = cost, missingPrices = #missing, sale = sale, where = where, price = price }
    p.complete = #missing == 0 and sale ~= nil
    if p.complete then
        p.profit = math.floor(sale - cost)
        p.share = cost > 0 and p.profit / cost or nil
    end
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
        local k = math.floor((GetItemCount(g.id) or 0) / g.n)
        n = n and math.min(n, k) or k
    end
    return n or 0
end

local SORTS = {
    profit = function(a, b) return (a.profit or -math.huge) > (b.profit or -math.huge) end,
    share = function(a, b) return (a.share or -math.huge) > (b.share or -math.huge) end,
    cheap = function(a, b) return (a.cost or math.huge) < (b.cost or math.huge) end,
    -- Confidence first: priced from a fresh scan, with others selling it too.
    safe = function(a, b)
        local x = (a.sure == "fresh" and 2 or a.sure == "recent" and 1 or 0) + (a.listed > 0 and 1 or 0)
        local y = (b.sure == "fresh" and 2 or b.sure == "recent" and 1 or 0) + (b.listed > 0 and 1 or 0)
        if x ~= y then return x > y end
        return (a.profit or -math.huge) > (b.profit or -math.huge)
    end,
}
Craft.SORTS = { "profit", "share", "cheap", "safe" }

-- Every learned recipe that makes something, by sort. Incomplete ones go last.
function Craft.Ranking(line, sort)
    local out = {}
    for _, r in ipairs(Prof.Recipes(line)) do
        if r.learned and r.out then out[#out + 1] = Craft.Profit(r) end
    end
    local by = SORTS[sort or "profit"] or SORTS.profit
    table.sort(out, function(a, b)
        if a.complete ~= b.complete then return a.complete end
        if by(a, b) ~= by(b, a) then return by(a, b) end
        return (a.recipe.name or "") < (b.recipe.name or "")
    end)
    return out
end

-- ==== the way up ============================================================

Craft.MODES = { "upfront", "net", "mine" }

-- What a craft costs towards a point, by mode: cash spent, cash less what the output sells
-- for, or cash with what is already in the bags counted free.
local function CraftCost(r, mode)
    local cost, missing = Craft.MaterialCost(r, { owned = mode == "mine" })
    if #missing > 0 then return nil end
    if mode == "net" then
        local sale = Craft.SaleValue(r)
        cost = cost - (sale or 0)
    end
    return cost
end

-- The cheapest expected way from skill a to b. Each point costs a craft's price over its
-- chance, and every point stands alone, so the cheapest recipe at each skill makes the
-- cheapest plan: the plan is exact for its inputs, and as good as the chances behind it.
-- { segments = { from, to, recipe, crafts, cost, sure }, total, train = { at, cap },
--   stuck = skill with no way on, unsure }
function Craft.Plan(line, a, b, mode)
    mode = mode or "upfront"
    local p = Prof.Get(line)
    local recipes = {}
    for _, r in ipairs(Prof.Recipes(line)) do
        if r.learned then recipes[#recipes + 1] = { r = r, cost = CraftCost(r, mode) } end
    end
    local out = { segments = {}, total = 0, train = {} }
    local cap = p and p.max or b
    local s = a
    while s < b do
        if s >= cap then
            local next = Prof.NextRank({ skill = s, max = cap })
            if not next then
                out.stuck = s
                break
            end
            out.train[#out.train + 1] = { at = s, cap = next.cap, name = next.name }
            cap = next.cap
        end
        local best, bestCost, bestChance, bestSure
        for _, c in ipairs(recipes) do
            if c.cost then
                local chance, sure = Prof.Chance(c.r, s)
                if chance and chance > 0 then
                    local per = c.cost / chance
                    if not bestCost or per < bestCost or (per == bestCost and c.r.id < best.id) then
                        best, bestCost, bestChance, bestSure = c.r, per, chance, sure
                    end
                end
            end
        end
        if not best then
            out.stuck = s
            break
        end
        local last = out.segments[#out.segments]
        if last and last.recipe == best then
            last.to, last.crafts, last.cost = s + 1, last.crafts + 1 / bestChance, last.cost + bestCost
            last.sure = last.sure and bestSure
        else
            out.segments[#out.segments + 1] = { from = s, to = s + 1, recipe = best, crafts = 1 / bestChance, cost = bestCost, sure = bestSure }
        end
        out.total = out.total + bestCost
        if not bestSure then out.unsure = true end
        s = s + 1
    end
    for _, seg in ipairs(out.segments) do
        seg.crafts = math.ceil(seg.crafts - 0.001)
        seg.cost = math.floor(seg.cost + 0.5)
    end
    out.total = math.floor(out.total + 0.5)
    return out
end

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
    local project = { name = name, items = {}, marks = {} }
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

-- Cheapest unit price of an item, buying it or making it, through at most MAX_DEPTH
-- crafts, never round a cycle. Returns copper (nil if unknown) and "buy" or "craft".
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
    return buy, buy and "buy" or nil
end
Craft._UnitCost = function(itemID) return UnitCost(itemID, 0, {}) end

-- Every reagent a project needs, merged across its recipes, with what is in the bags (and
-- the bank, when the game says), what is left to get, and its price. With craft = true, a
-- reagent this character can make more cheaply is broken into its own reagents instead.
function Craft.Shopping(project, craft)
    local need, order = {}, {}
    local function Add(itemID, n, depth, seen)
        local maker = craft and depth < MAX_DEPTH and not seen[itemID] and MakerOf(itemID)
        if maker then
            local _, how = UnitCost(itemID, depth, {})
            if how == "craft" then
                seen[itemID] = true
                local runs = math.ceil(n / Yield(maker))
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
    local rows, total, unknown = {}, 0, 0
    for _, itemID in ipairs(order) do
        local bags = GetItemCount(itemID) or 0
        local all = GetItemCount(itemID, true) or bags
        local left = math.max(0, need[itemID] - bags)
        local unit, from = Market.Cost(itemID)
        local mark = project.marks[itemID]
        if mark == "bought" or mark == "have" then left = 0 end
        rows[#rows + 1] = { id = itemID, need = need[itemID], bags = bags, bank = all - bags, left = left,
                            unit = unit, from = from, mark = mark }
        if left > 0 then
            if unit then total = total + unit * left else unknown = unknown + 1 end
        end
    end
    return { rows = rows, total = total, unknown = unknown }
end

-- A material's state on the list, set by hand and never overwritten: nil, "bought", "have".
function Craft.Mark(project, itemID, mark)
    project.marks[itemID] = mark
    FG.Emit("projects:changed")
end
