-- What buying a quantity costs: the cheapest listings first, then a merchant's unlimited
-- stock where that is cheaper, and what is left over or cannot be bought at all.
--
-- From ForeverNet's Market.Quote (https://github.com/thewoolfi/ForeverNet, commit 10a81d9,
-- MIT License, Copyright (c) 2026 Andrew Woolfi, Licenses/ForeverNet-LICENSE.txt): a
-- commodity is bought cheapest first along its price tiers; whole auctions are chosen by a
-- bounded 0/1 covering knapsack (the cheapest set of auctions holding at least the quantity),
-- and past that bound cheapest first, marked approximate. Changed here: it reads Forever-GPS's
-- price ladders, a merchant's stock is one more tier, and a missing price is "unknown",
-- never zero.
local FG = ForeverGPS
local Quote = {}
FG.Quote = Quote

local KNAPSACK_WORK = 200000

-- The cheapest set of whole auctions holding at least `want` units. offers: { {unit, count} }.
-- Returns cost and units bought, or nil past the bound.
local function Covering(offers, want)
    local total = 0
    for _, o in ipairs(offers) do total = total + o[2] end
    local target = math.min(want, total)
    if target * #offers > KNAPSACK_WORK then return nil end
    local cost, bought = { [0] = 0 }, { [0] = 0 }
    for _, o in ipairs(offers) do
        local price = o[1] * o[2]
        for have = target - 1, 0, -1 do
            if cost[have] then
                local reach = math.min(target, have + o[2])
                local paid = cost[have] + price
                if not cost[reach] or paid < cost[reach] then
                    cost[reach], bought[reach] = paid, bought[have] + o[2]
                end
            end
        end
    end
    return cost[target] or 0, bought[target] or 0
end

-- Buying `quantity` of an item. opts.whole: listings are whole auctions (gear); opts.price:
-- a price record to use instead of the market's; opts.noVendor: auction only.
-- Returns { status = "known" | "unknown" | "empty", cost, bought, covered, remaining,
--           surplus, fromAuction, fromVendor, minimum, stale, partial, approximate, sure }.
-- remaining > 0: that many cannot be bought from what is known.
function Quote.Buy(itemID, quantity, opts)
    opts = opts or {}
    quantity = math.max(0, math.floor(quantity or 0))
    local q = { status = "unknown", cost = 0, bought = 0, covered = 0, remaining = quantity, surplus = 0,
                fromAuction = 0, fromVendor = 0 }
    if quantity == 0 then
        q.status = "known"
        return q
    end
    local price = opts.price or FG.Market.Price(itemID)
    local vendor = not opts.noVendor and FG.Market.VendorBuy(itemID) or nil
    if not price and not vendor then return q end
    q.status = "known"
    if price then
        q.minimum, q.stale, q.partial, q.sure = price.buy, price.sure == "stale", price.partial, price.sure
    else
        q.sure = "vendor"
    end
    local ladder = price and price.ladder or {}
    if opts.whole and #ladder > 0 then
        -- Whole auctions, unless a merchant sells it for less than the cheapest of them.
        if not (vendor and vendor <= ladder[1][1]) then
            local cost, bought = Covering(ladder, quantity)
            if cost then
                q.cost, q.bought = cost, bought
            else
                q.approximate = true
                for _, o in ipairs(ladder) do
                    if q.bought >= quantity then break end
                    q.cost, q.bought = q.cost + o[1] * o[2], q.bought + o[2]
                end
            end
            q.fromAuction = q.bought
        end
    else
        -- Cheapest first along the tiers, the merchant's price as a tier without end.
        local need = quantity
        for _, o in ipairs(ladder) do
            if need == 0 or (vendor and vendor <= o[1]) then break end
            local take = math.min(need, o[2])
            q.cost, q.bought, need = q.cost + take * o[1], q.bought + take, need - take
            q.fromAuction = q.fromAuction + take
        end
    end
    if vendor and q.bought < quantity then
        local take = quantity - q.bought
        q.cost, q.bought, q.fromVendor = q.cost + take * vendor, q.bought + take, take
    end
    q.covered = math.min(quantity, q.bought)
    q.remaining = math.max(0, quantity - q.bought)
    q.surplus = math.max(0, q.bought - quantity)
    -- Listings known only in part (the cheapest tiers of a scan) may hold more.
    if q.remaining > 0 and price and price.units and price.units > q.fromAuction and not opts.whole then
        q.beyondLadder = true
    end
    if q.bought == 0 and q.remaining > 0 then q.status = price and #ladder == 0 and "empty" or q.status end
    return q
end

-- Buying several items: { [itemID] = quantity }. Sums what is known, and says what is not.
function Quote.Budget(want)
    local r = { cost = 0, unknown = 0, uncovered = 0, stale = 0, partial = 0, approximate = false, items = {} }
    for id, n in pairs(want) do
        local q = Quote.Buy(id, n)
        r.items[id] = q
        r.cost = r.cost + q.cost
        if q.status ~= "known" then r.unknown = r.unknown + 1 end
        if q.remaining > 0 then r.uncovered = r.uncovered + 1 end
        if q.stale then r.stale = r.stale + 1 end
        if q.partial then r.partial = r.partial + 1 end
        r.approximate = r.approximate or q.approximate or false
    end
    return r
end
