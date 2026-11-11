-- Crafting with quantities: price tiers, merchants as a tier without end, what is in the
-- bags used once across a whole plan, the client's own skill-up ranges, recipes still to
-- learn, and a whole-plan search checked against every plan on small cases.
local T = require("support.t")
local Stack = require("support.stack")

local ALCHEMY, LEATHER = 171, 165
local HERB_A, HERB_B, VIAL = 900, 901, 902
local LESSER, ELIXIR = 1001, 1002

local function Recipes()
    return {
        [LESSER] = { name = "Lesser Healing Potion", line = ALCHEMY, out = 858, reagents = { { id = HERB_A, n = 1 }, { id = VIAL, n = 1 } },
                     at = { y = 140, g = 155, x = 170 } },
        [ELIXIR] = { name = "Elixir of Minor Fortitude", line = ALCHEMY, out = 2458, qmin = 2, qmax = 4,
                     reagents = { { id = HERB_B, n = 2 }, { id = VIAL, n = 1 } }, at = { y = 135, g = 145, x = 155 } },
    }
end

local function Start(opts)
    opts = opts or {}
    opts.mapID, opts.x, opts.y = opts.mapID or 1453, opts.x or 0.6, opts.y or 0.6
    if opts.ui == nil then opts.ui = false end
    opts.professions = opts.professions or { { name = "Alchemy", skill = 132, max = 150, line = ALCHEMY } }
    opts.recipes = opts.recipes or Recipes()
    opts.auctions = opts.auctions or {}
    opts.merchant = opts.merchant or { { id = VIAL, price = 20 } }
    opts.items = opts.items or { [858] = { name = "Lesser Healing Potion", sell = 100 }, [2458] = { name = "Elixir", sell = 50 } }
    local c = Stack.new(opts)
    c:Advance(4)
    c:Fire("MERCHANT_SHOW")
    c:Advance(0.5)
    if #c.auctions > 0 then
        c:Fire("AUCTION_HOUSE_SHOW")
        c.FG.Market.Scan()
        Stack.Until(c, function() return c.FG.Market.Scanning().state == "done" end, 20)
    end
    c.openProfession = c.professions[1]
    c.FG.Professions.Refresh()
    c.FG.Professions.ReadRecipes()
    return c
end

-- Pins every turning point, so nothing is estimated.
local function Pin(c, ids)
    for _, id in ipairs(ids) do
        local r = c.FG.Professions.Recipe(id)
        local at = c.recipes[id].at
        r.th = { ylo = at.y, yhi = at.y, glo = at.g, ghi = at.g, xlo = at.x, xhi = at.x }
    end
end

local tests = {}

-- ==== quantities ============================================================

function tests.manyCrafts_walkUpThePriceTiers()
    local c = Start({ auctions = { { itemID = HERB_A, count = 10, buyout = 1000 }, { itemID = HERB_A, count = 5, buyout = 750 } } })
    local r = c.FG.Professions.Recipe(LESSER)
    local cost, missing = c.FG.Crafting.MaterialCost(r, { times = 12 })
    T.eq(#missing, 0)
    T.eq(cost, 10 * 100 + 2 * 150 + 12 * 20, "ten at 1s, two at 1s 50c, and the vials")
    local _, missing2, _, short = c.FG.Crafting.MaterialCost(r, { times = 20 })
    T.eq(short, 5, "five more than are listed")
    T.eq(missing2[1], HERB_A, "so incomplete, not cheaper")
end

-- 2.3 counted bag reagents free for every craft. Now they are used once.
function tests.whatIsInTheBags_isUsedOnce_acrossThePlan()
    local c = Start({ auctions = { { itemID = HERB_A, count = 1000, buyout = 100000 } }, bags = { [HERB_A] = 10, [VIAL] = 0 } })
    Pin(c, { LESSER })
    local plan = c.FG.Crafting.Plan(ALCHEMY, 132, 140, "mine")
    -- All orange: one craft a point, eight crafts, eight herbs and eight vials.
    T.eq(plan.total, 8 * 20, "the herbs in the bags cover eight; only vials are bought")
    plan = c.FG.Crafting.Plan(ALCHEMY, 132, 148, "mine")
    local herbsBought = 0
    for _, row in ipairs(plan.shopping) do
        if row.id == HERB_A then herbsBought = row.safe - row.have end
    end
    T.ok(herbsBought > 0, "past ten herbs, the rest are bought")
    local spent = c.FG.Crafting.Plan(ALCHEMY, 132, 148, "upfront").total
    T.ok(plan.total < spent, "less than buying everything")
    T.eq(spent - plan.total, 10 * 100, "exactly the ten herbs in hand")
end

function tests.aMerchantStock_neverRunsOut_andCapsTheAuctionPrice()
    local c = Start({ auctions = { { itemID = VIAL, count = 2, buyout = 20 }, { itemID = VIAL, count = 50, buyout = 5000 } } })
    local q = c.FG.Quote.Buy(VIAL, 10)
    T.eq(q.cost, 2 * 10 + 8 * 20, "two cheap ones, then the merchant, not the dear listing")
    T.eq(q.fromVendor, 8)
end

-- ==== the client's ranges ===================================================

function tests.aRecipeInTheClientsData_usesItsRanges()
    local c = Start()
    local P = c.FG.Professions
    local d = P.Data(2149)
    T.ok(d, "Handstitched Leather Boots are in the data")
    T.eq(d.line, LEATHER)
    T.eq(d.yellow, 40)
    T.eq(d.grey, 70)
    local chance, sure, source = P.Chance({ id = 2149 }, 55)
    T.near(chance, 0.5, 0.0001, "half way from yellow to grey")
    T.ok(sure)
    T.eq(source, "client")
    T.eq(P.Chance({ id = 2149 }, 39), 1, "orange")
    T.eq(P.Chance({ id = 2149 }, 70), 0, "grey")
end

function tests.whatTheCharacterSaw_winsOverDataThatDisagrees()
    local c = Start()
    local r = { id = 2149, th = { xlo = 61, xhi = 61, ylo = 35, yhi = 35 } }
    local _, _, source = c.FG.Professions.Chance(r, 50)
    T.eq(source, "seen")
    T.ok(r.conflict, "the disagreement is noted")
end

-- One recipe of two professions (Synthetic Gordok Ogre Suit is leatherworking and
-- tailoring) is offered to both, not to whichever came last in the data.
function tests.aRecipeOfTwoProfessions_belongsToBoth()
    local c = Start()
    local d = c.FG.Professions.Data(461692)
    T.ok(d.lines[165] and d.lines[197], "both lines")
    local function Has(line)
        for _, r in ipairs(c.FG.Professions.Obtainable(line)) do if r.id == 461692 then return true end end
        return false
    end
    T.ok(Has(165), "a leatherworker can learn it")
    T.ok(Has(197), "and a tailor")
end

function tests.everyDataRecipe_parses()
    local c = Start()
    local n, lines = 0, {}
    for id in pairs(c.FG.RecipeData.recipes) do
        local d = c.FG.Professions.Data(id)
        T.ok(d and d.line, "parsed " .. id)
        lines[d.line] = true
        if d.yellow and d.grey then T.ok(d.grey >= d.yellow, "grey after yellow: " .. id) end
        n = n + 1
    end
    T.ok(n > 2400, "every recipe: " .. n)
    for _, line in ipairs({ 164, 165, 171, 185, 197, 202, 333 }) do T.ok(lines[line], "profession " .. line) end
end

-- ==== recipes still to learn ================================================

local function Leatherworker(opts)
    opts = opts or {}
    opts.professions = { { name = "Leatherworking", skill = 1, max = 75, line = LEATHER } }
    opts.recipes = {}
    opts.auctions = opts.auctions or { { itemID = 2318, count = 500, buyout = 500 * 15 } }
    opts.merchant = { { id = 2320, price = 10 } }
    return Start(opts)
end

function tests.knownOnly_isStuck_withoutRecipes()
    local c = Leatherworker()
    local plan = c.FG.Crafting.Plan(LEATHER, 1, 20, "upfront")
    T.eq(plan.stuck, 1)
    T.eq(plan.stuckWhy, "recipes")
end

function tests.includeObtainable_plansWithRecipesToLearn()
    local c = Leatherworker()
    local list = c.FG.Professions.Obtainable(LEATHER)
    T.ok(#list > 20, "leatherworking has many: " .. #list)
    local plan = c.FG.Crafting.Plan(LEATHER, 1, 20, "upfront", { coverage = "obtainable" })
    T.eq(plan.stuck, 1, "a trainer's recipe price is unknown: not counted as free")
    plan = c.FG.Crafting.Plan(LEATHER, 1, 20, "upfront", { coverage = "obtainable", learnUnknownFree = true })
    T.no(plan.stuck, "with unknown costs left out of the total, a way is found")
    T.ok(#plan.learn >= 1, "and it says what to learn")
    T.ok(plan.learnUnknown, "and that the cost to learn is unknown")
    for _, seg in ipairs(plan.segments) do T.eq(seg.source, "client", "on the client's ranges") end
end

-- ==== the whole plan against every plan =====================================

-- Small worlds: two or three recipes, short climbs, tiered prices, some herbs in the bags.
-- Every assignment of recipes to points is tried and compared. A climb this short is solved
-- exactly; with noExact the search a long climb uses is measured against the same answers.
local function Worlds(noExact)
    local seed = 11
    local function rand(n)
        seed = (seed * 1103515245 + 12345) % 2147483648
        return seed % n
    end
    local worse, cases, gap = 0, 0, 0
    for case = 1, 24 do
        local herbs = { 910, 911, 912 }
        local recipes, auctions, bags = {}, {}, {}
        local nr = 2 + rand(2)
        for i = 1, nr do
            local y = 100 + rand(10)
            recipes[2000 + i] = { name = "R" .. i, line = ALCHEMY, out = 3000 + i,
                                  reagents = { { id = herbs[1 + rand(3)], n = 1 + rand(2) } },
                                  at = { y = y, g = y + 5, x = y + 10 + rand(6) } }
        end
        for _, h in ipairs(herbs) do
            for _ = 1, 1 + rand(3) do
                local count = 1 + rand(4)
                auctions[#auctions + 1] = { itemID = h, count = count, buyout = count * (10 + rand(40)) }
            end
            auctions[#auctions + 1] = { itemID = h, count = 500, buyout = 500 * 200 }
            if rand(2) == 0 then bags[h] = rand(4) end
        end
        local c = Start({ recipes = recipes, auctions = auctions, bags = bags,
                          professions = { { name = "Alchemy", skill = 104, max = 150, line = ALCHEMY } } })
        local ids = {}
        for id in pairs(recipes) do ids[#ids + 1] = id end
        table.sort(ids)
        Pin(c, ids)
        local a, b = 104, 104 + 3 + rand(3)
        local mode = rand(2) == 0 and "mine" or "upfront"
        local plan = c.FG.Crafting.Plan(ALCHEMY, a, b, mode, { noExact = noExact })
        if not plan.stuck and plan.total then
            cases = cases + 1
            -- Every assignment.
            local P = c.FG.Professions
            local options = {}
            for s = a, b - 1 do
                local here = {}
                for _, id in ipairs(ids) do
                    local r = P.Recipe(id)
                    local chance = P.Chance(r, s)
                    if chance and chance > 0 then here[#here + 1] = { r = r, chance = chance } end
                end
                options[#options + 1] = here
            end
            local best
            local assign, chances = {}, {}
            local function Try(k)
                if k > #options then
                    local t = c.FG.Crafting._Total(assign, chances, mode, {})
                    if t and (not best or t < best) then best = t end
                    return
                end
                for _, o in ipairs(options[k]) do
                    assign[k], chances[k] = o.r, o.chance
                    Try(k + 1)
                end
                assign[k], chances[k] = nil, nil
            end
            Try(1)
            if math.abs(plan.total - math.floor(best + 0.5)) > 1 then worse = worse + 1 end
            gap = math.max(gap, (plan.total - best) / math.max(1, best))
            if not noExact then
                T.ok(plan.exact, "solved exactly")
                T.ok(plan.total <= math.floor(best + 0.5) + 1, ("case %d: plan %d, cheapest %.1f"):format(case, plan.total, best))
            end
        end
    end
    return cases, worse, gap
end

function tests.aShortClimb_isTheCheapestOfEveryPlan()
    local cases, worse = Worlds(false)
    T.ok(cases >= 10, "enough cases were plannable: " .. cases)
    T.eq(worse, 0)
end

-- The search for long climbs, on the same worlds: never far from the cheapest, and the
-- numbers are reported (docs/PROFESSIONS.md).
function tests.theLongClimbSearch_staysCloseToTheCheapest()
    local cases, worse, gap = Worlds(true)
    print(("    search vs every plan: %d cases, %d not the cheapest, worst %.2f%% dearer"):format(cases, worse, gap * 100))
    T.ok(cases >= 10)
    T.ok(gap <= 0.02, ("within 2%%: worst %.2f%%"):format(gap * 100))
end

-- ==== how many to buy =======================================================

function tests.aSaferQuantity_coversBadLuck()
    local c = Start({ auctions = { { itemID = HERB_A, count = 1000, buyout = 100000 } } })
    Pin(c, { LESSER })
    local plan = c.FG.Crafting.Plan(ALCHEMY, 150, 165, "upfront")
    local seg = plan.segments[#plan.segments]
    T.ok(seg.expected > seg.to - seg.from, "yellow and green need more crafts than points")
    T.ok(seg.safe > seg.crafts, "and the safe count is more again: " .. seg.crafts .. " / " .. seg.safe)
    local herb
    for _, row in ipairs(plan.shopping) do if row.id == HERB_A then herb = row end end
    T.ok(herb.safe >= herb.expected)
    T.eq(herb.status, "known")
end

-- ==== lists =================================================================

local function ListWith(c, recipe, qty)
    local project = c.FG.Crafting.NewProject("Test")
    c.FG.Crafting.AddToProject(project, recipe, qty)
    return project
end

function tests.aList_pricesTheWholeQuantity()
    local c = Start({ auctions = { { itemID = HERB_A, count = 10, buyout = 1000 }, { itemID = HERB_A, count = 5, buyout = 750 } } })
    local project = ListWith(c, LESSER, 12)
    local shop = c.FG.Crafting.Shopping(project, true)
    local herb
    for _, row in ipairs(shop.rows) do if row.id == HERB_A then herb = row end end
    T.eq(herb.cost, 1300)
    T.eq(herb.short, 0)
    project.items[1].qty = 20
    shop = c.FG.Crafting.Shopping(project, true)
    for _, row in ipairs(shop.rows) do if row.id == HERB_A then herb = row end end
    T.eq(herb.short, 5, "five more than are listed")
    T.eq(shop.short, 1)
end

function tests.makeOrBuy_isThePlayersToChoose_andBatchesSaySurplus()
    local recipes = Recipes()
    recipes[1003] = { name = "Strong Oil", line = ALCHEMY, out = 3000, reagents = { { id = 2458, n = 4 }, { id = VIAL, n = 1 } },
                      at = { y = 160, g = 170, x = 180 } }
    local c = Start({ recipes = recipes, auctions = { { itemID = HERB_B, count = 100, buyout = 1000 }, { itemID = 2458, count = 100, buyout = 100000 } } })
    local project = ListWith(c, 1003, 1)
    local shop = c.FG.Crafting.Shopping(project, true)
    T.eq(#shop.crafts, 1, "the elixir is cheaper to make")
    T.eq(shop.crafts[1].runs, 2, "four needed, three a craft: two crafts")
    T.eq(shop.crafts[1].surplus, 2, "two left over")
    c.FG.Crafting.Choose(project, 2458, "buy")
    shop = c.FG.Crafting.Shopping(project, true)
    T.eq(#shop.crafts, 0, "bought, as chosen")
    local elixir
    for _, row in ipairs(shop.rows) do if row.id == 2458 then elixir = row end end
    T.ok(elixir and elixir.makes, "and the row says it could be made")
    T.eq(elixir.choice, "buy")
end

function tests.aList_copiesAsText()
    local c = Start({ auctions = { { itemID = HERB_A, count = 50, buyout = 5000 } }, items = { [HERB_A] = { name = "Peacebloom" } } })
    local project = ListWith(c, LESSER, 3)
    local text = c.FG.Crafting.ShoppingText(project, true)
    T.ok(text:find("Test", 1, true))
    T.ok(text:find("Peacebloom x3", 1, true), text)
end

-- ==== profit, apart =========================================================

function tests.profit_keepsItsFiguresApart()
    local c = Start({ auctions = { { itemID = HERB_A, count = 50, buyout = 5000 }, { itemID = 858, count = 1, buyout = 3000 } },
                      bags = { [HERB_A] = 1 } })
    local p = c.FG.Crafting.Profit(c.FG.Professions.Recipe(LESSER))
    T.eq(p.cost, 100 + 20, "reagents at today's prices")
    T.eq(p.upfront, 20, "the herb in the bags is not bought")
    T.eq(p.sale, math.floor(3000 * 0.95), "if it sells, less the cut")
    T.eq(p.recovery, 100, "what a merchant pays")
    T.eq(p.profit, math.floor(3000 * 0.95) - 120)
end

-- ==== other characters ======================================================

function tests.anotherCharacter_seesWhatThisOneCanMake_asACopy()
    local c = Start({ auctions = { { itemID = HERB_A, count = 50, buyout = 5000 } } })
    -- Another character: the account's saved data, not this one's own.
    local saved = Stack.Saved(c)
    saved.ForeverGPSCharDB = nil
    local d = Start({ saved = saved, recipes = {}, name = "Second",
                      professions = { { name = "Tailoring", skill = 10, max = 75, line = 197 } } })
    local alts = d.FG.Alts.List()
    T.eq(#alts, 1, "the first character")
    T.eq(alts[1].name, "Tester")
    T.eq(alts[1].professions[1].line, ALCHEMY)
    T.ok(alts[1].at, "with when it was seen")
    local who = d.FG.Alts.WhoMakes(858)
    T.ok(who and who[1].name == "Tester", "Tester can make the potion")
    T.eq(d.FG.Alts.WhoMakes(999999), nil)
    T.eq(#d.FG.Professions.Recipes(ALCHEMY), 0, "never mixed into this character's own recipes")
end

-- ==== price history and alerts ==============================================

local function Rescan(c)
    local house = c.FG.db.market.houses[c.FG.Market.Key()]
    house.askedAt = house.askedAt - 3600
    c.FG.Market.Scan()
    Stack.Until(c, function() return c.FG.Market.Scanning().state == "done" end, 20)
end

function tests.history_keepsADayAPoint_forTwoWeeks_andSaysItIsListings()
    local c = Start({ auctions = { { itemID = HERB_A, count = 50, buyout = 5000 } } })
    local H = c.FG.PriceHistory
    local now = c.env.time
    c.env.time = function() return 1800000000 + now() end   -- a date in this century
    Rescan(c)   -- the recipes are known now: their herbs are worth a history
    local points = H.Of(HERB_A)
    T.eq(#points, 1, "today's point")
    T.eq(points[1].low, 100)
    Rescan(c)
    T.eq(#H.Of(HERB_A), 1, "still one a day")
    local house = c.FG.db.market.houses[c.FG.Market.Key()]
    local today = math.floor(c.env.time() / 86400)
    local old = {}
    for d = 20, 1, -1 do old[#old + 1] = (today - d) .. ":200:10" end
    house.history[HERB_A] = table.concat(old, ";")
    Rescan(c)
    points = H.Of(HERB_A)
    T.eq(#points, H.DAYS, "two weeks at most")
    local _, trend = H.Of(HERB_A)
    T.eq(trend, "down", "100 against 200 before")
    T.eq(house.history[999], nil, "nothing for items that do not matter here")
end

function tests.anAlert_speaksOnce_whenNewPricesFallUnderIt()
    local c = Start({ auctions = { { itemID = HERB_A, count = 50, buyout = 5000 } } })
    c.FG.PriceHistory.SetAlert(HERB_A, 120)
    local before = #c.printed
    Rescan(c)
    T.eq(#c.printed, before + 1, "said once")
    T.ok(c.printed[#c.printed]:find("under your", 1, true))
    Rescan(c)
    T.eq(#c.printed, before + 1, "the same price is not said again")
    c.auctions[1].buyout = 50 * 150
    Rescan(c)
    c.auctions[1].buyout = 50 * 90
    Rescan(c)
    T.eq(#c.printed, before + 2, "back under it: said again")
    c:Advance(600)
    T.eq(#c.printed, before + 2, "never on a timer")
end

function tests.alerts_areSetAndClearedByCommand()
    local c = Start()
    local run = c.env.SlashCmdList.FOREVERGPS
    run("alert 900 1s20c")
    T.eq(c.FG.db.alerts[900].below, 120)
    run("alert |cffffffff|Hitem:901::::::::|h[Herb]|h|r 2g")
    T.eq(c.FG.db.alerts[901].below, 20000, "from a link")
    run("alert 900 off")
    T.eq(c.FG.db.alerts[900], nil)
    T.eq(c.FG.Commands._ParseMoney("35s"), 3500)
    T.eq(c.FG.Commands._ParseMoney("nonsense"), nil)
end

function tests.profit_filters()
    local c = Start({ auctions = { { itemID = HERB_A, count = 50, buyout = 5000 }, { itemID = 858, count = 1, buyout = 3000 } } })
    local all = c.FG.Crafting.Ranking(ALCHEMY, "profit")
    local complete = c.FG.Crafting.Ranking(ALCHEMY, "profit", { complete = true })
    T.ok(#complete < #all, "the elixir has no herb price")
    for _, p in ipairs(complete) do T.ok(p.complete) end
    T.eq(#c.FG.Crafting.Ranking(ALCHEMY, "profit", { makeable = true }), 0, "nothing in the bags")
end

return tests
