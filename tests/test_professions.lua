-- Professions: what the game says the character has, prices from its own auction house and
-- merchants, what crafting earns, the cheapest way up, lists, and trainers by what they
-- teach. Small cases with answers that can be worked out by hand.
local T = require("support.t")
local Stack = require("support.stack")

local ALCHEMY = 171
local HERB_A, HERB_B, VIAL, PEACEBLOOM = 900, 901, 902, 903
local LESSER, ELIXIR, MINOR, UNLEARNED, OIL = 1001, 1002, 1003, 1004, 1005

local function Recipes()
    return {
        [LESSER] = { name = "Lesser Healing Potion", line = ALCHEMY, out = 858, reagents = { { id = HERB_A, n = 1 }, { id = VIAL, n = 1 } },
                     at = { y = 140, g = 155, x = 170 } },
        [ELIXIR] = { name = "Elixir of Minor Fortitude", line = ALCHEMY, out = 2458, qmin = 2, qmax = 4,
                     reagents = { { id = HERB_B, n = 2 }, { id = VIAL, n = 1 } }, at = { y = 135, g = 145, x = 155 } },
        [MINOR] = { name = "Minor Healing Potion", line = ALCHEMY, out = 118, reagents = { { id = PEACEBLOOM, n = 1 }, { id = VIAL, n = 1 } },
                    at = { y = 55, g = 75, x = 95 } },
        [UNLEARNED] = { name = "Swiftness Potion", line = ALCHEMY, out = 2459, learned = false, reagents = { { id = HERB_A, n = 1 } },
                        at = { y = 200, g = 210, x = 220 } },
        -- Made from what another recipe makes: a craft inside a craft.
        [OIL] = { name = "Strong Oil", line = ALCHEMY, out = 3000, reagents = { { id = 2458, n = 1 }, { id = VIAL, n = 1 } },
                  at = { y = 160, g = 170, x = 180 } },
    }
end

local function Auctions()
    return {
        { itemID = HERB_A, count = 10, buyout = 1000 },   -- 1s each
        { itemID = HERB_A, count = 5, buyout = 750 },     -- 1s 50c? no: 150c each
        { itemID = HERB_B, count = 20, buyout = 4000 },   -- 2s each
        { itemID = 858, count = 1, buyout = 2500 },
        { itemID = 858, count = 4, buyout = 12000 },
        { itemID = 2458, count = 1, buyout = 500 },
        { itemID = 3000, count = 1, buyout = 9000 },
    }
end

local function Start(opts)
    opts = opts or {}
    opts.mapID, opts.x, opts.y = opts.mapID or 1453, opts.x or 0.6, opts.y or 0.6
    if opts.ui == nil then opts.ui = false end
    opts.professions = opts.professions or { { name = "Alchemy", skill = 132, max = 150, line = ALCHEMY },
                                             { name = "Herbalism", skill = 140, max = 150, line = 182 } }
    opts.recipes = opts.recipes or Recipes()
    opts.auctions = opts.auctions or Auctions()
    opts.merchant = opts.merchant or { { id = VIAL, price = 20 } }
    opts.items = opts.items or { [858] = { name = "Lesser Healing Potion", sell = 100 }, [2458] = { name = "Elixir", sell = 50 } }
    local c = Stack.new(opts)
    c:Advance(4)
    return c
end

local function OpenWindow(c, skill)
    local p = c.professions[1]
    if skill then p.skill = skill end
    c.openProfession = p
    c.FG.Professions.Refresh()
    return c.FG.Professions.ReadRecipes()
end

local function Scan(c)
    c:Fire("AUCTION_HOUSE_SHOW")
    T.ok(c.FG.Market.Scan())
    T.ok(Stack.Until(c, function() return c.FG.Market.Scanning().state == "done" end, 10), "the scan is read")
end

local tests = {}

-- ==== what the character has ================================================

function tests.professions_areReadWithSkillAndCap()
    local c = Start()
    local list = c.FG.Professions.List()
    T.eq(#list, 2)
    local a = c.FG.Professions.Get(ALCHEMY)
    T.eq(a.skill, 132)
    T.eq(a.max, 150, "132 of 150: the cap is the game's, not a guess from the skill")
    T.no(a.gathering)
    T.ok(c.FG.Professions.Get(182).gathering, "herbalism makes nothing")
    local next = c.FG.Professions.NextRank(a)
    T.eq(next.cap, 225)
    T.eq(next.name, "Expert")
    T.no(next.ready)
    T.ok(next.close, "within 25 of the cap")
end

function tests.noProfessions_isAnEmptyList()
    local c = Start({ professions = {} })
    T.eq(#c.FG.Professions.List(), 0)
end

function tests.learningOrLosingOne_isNoticed()
    local c = Start()
    table.remove(c.professions, 2)
    c:Fire("SKILL_LINES_CHANGED")
    T.eq(#c.FG.Professions.List(), 1)
    c.professions[1].skill, c.professions[1].max = 150, 225
    c:Fire("SKILL_LINES_CHANGED")
    T.eq(c.FG.Professions.Get(ALCHEMY).max, 225, "a new rank")
end

function tests.recipes_areReadFromTheWindow_withReagentsAndOutput()
    local c = Start()
    T.eq(OpenWindow(c), 5)
    local r = c.FG.Professions.Recipe(ELIXIR)
    T.eq(r.out, 2458)
    T.eq(r.qmin, 2)
    T.eq(r.qmax, 4)
    T.eq(#r.reagents, 2)
    T.no(c.FG.Professions.Recipe(UNLEARNED).learned)
end

function tests.colours_closeInOnTheSkillsTheyTurnAt()
    local c = Start()
    OpenWindow(c, 132)
    local th = c.FG.Professions.Recipe(LESSER).th
    T.eq(th.ylo, 133, "orange at 132: yellow comes later")
    OpenWindow(c, 141)
    th = c.FG.Professions.Recipe(LESSER).th
    T.eq(th.yhi, 141, "yellow by 141")
    T.eq(th.glo, 142)
    OpenWindow(c, 160)
    th = c.FG.Professions.Recipe(LESSER).th
    T.eq(th.ghi, 160)
    T.eq(th.xlo, 161)
end

function tests.theChance_followsTheLongStandingRule()
    local c = Start()
    local P = c.FG.Professions
    local r = { th = { ylo = 140, yhi = 140, xlo = 170, xhi = 170 } }
    T.eq(P.Chance(r, 130), 1, "orange")
    T.near(P.Chance(r, 155), 0.5, 0.001, "half way from yellow to grey")
    T.eq(P.Chance(r, 170), 0, "grey")
    local sure = select(2, P.Chance(r, 150))
    T.ok(sure, "pinned down by what was seen")
    local _, guess = P.Chance({ th = { ylo = 133 } }, 140)
    T.no(guess, "only bounded on one side: an estimate")
end

-- ==== prices ================================================================

function tests.aScan_needsTheAuctionHouseOpen_andAClick()
    local c = Start()
    local ok, why = c.FG.Market.Scan()
    T.no(ok)
    T.ok(why)
    T.eq(c.replicated, nil, "nothing asked of the server")
end

function tests.aScan_keepsTheLowestATypicalPriceAndHowManyAreListed()
    local c = Start()
    Scan(c)
    local p = c.FG.Market.Price(HERB_A)
    T.eq(p.buy, 100, "1s each is the lowest unit buyout")
    T.eq(p.units, 15)
    T.eq(p.sure, "fresh")
    T.eq(c.FG.Market.Price(858).buy, 2500)
    T.eq(c.FG.Market.Price(858).typical, 3000, "a quarter of five units reaches into the dearer listing")
end

function tests.theServersCooldown_isRespected()
    local c = Start()
    Scan(c)
    local ok, why, wait = c.FG.Market.CanScan()
    T.no(ok)
    T.ok(wait and wait > 800, why)
    T.eq(c.replicated, 1)
end

function tests.closingMidScan_keepsTheOldPrices()
    local c = Start()
    Scan(c)
    local house = c.FG.db.market.houses[c.FG.Market.Key()]
    house.scannedAt = house.scannedAt - 3600
    local before = c.FG.Market.Price(HERB_A).buy
    c.auctions = {}
    for i = 1, 5000 do c.auctions[i] = { itemID = HERB_A, count = 1, buyout = 1 } end
    T.ok(c.FG.Market.Scan())
    c:Advance(0.2)
    c:Fire("AUCTION_HOUSE_CLOSED")
    c:Advance(1)
    T.eq(c.FG.Market.Scanning().state, "failed")
    T.eq(c.FG.Market.Price(HERB_A).buy, before, "nothing half-read replaces them")
end

function tests.eachHouse_isItsOwnMarket()
    local c = Start()
    Scan(c)
    local home = c.FG.Market.Key()
    c.env.GetMinimapZoneText = function() return "Gadgetzan" end
    local key, side = c.FG.Market.Key()
    T.eq(side, "Neutral")
    T.ok(key ~= home)
    T.eq(c.FG.Market.Price(HERB_A, key), nil, "no prices carried across")
end

function tests.oldPrices_sayTheyAreOld()
    local c = Start()
    Scan(c)
    c.FG.db.market.houses[c.FG.Market.Key()].scannedAt = c.env.time() - 5 * 86400
    T.eq(c.FG.Market.Price(HERB_A).sure, "stale")
end

function tests.merchantPrices_areLearned_andTheCheaperSourceIsUsed()
    local c = Start({ merchant = { { id = VIAL, price = 20 }, { id = HERB_A, price = 500, available = 3 } } })
    c:Fire("MERCHANT_SHOW")
    c:Advance(0.5)
    T.eq(c.FG.Market.VendorBuy(VIAL), 20)
    T.eq(c.FG.Market.VendorBuy(HERB_A), nil, "limited stock is not a price to plan on")
    Scan(c)
    local unit, from = c.FG.Market.Cost(VIAL)
    T.eq(unit, 20)
    T.eq(from, "vendor")
end

-- ==== profit ================================================================

local function Ready(c)
    c:Fire("MERCHANT_SHOW")
    c:Advance(0.5)
    Scan(c)
    OpenWindow(c)
end

function tests.profit_countsTheHousesCut_andTheCheapestMaterials()
    local c = Start()
    Ready(c)
    local p = c.FG.Crafting.Profit(c.FG.Professions.Recipe(LESSER))
    T.eq(p.cost, 100 + 20, "a herb at 1s and a vial from a merchant")
    T.eq(p.sale, math.floor(2500 * 0.95), "the lowest listing less the 5% cut")
    T.eq(p.profit, math.floor(2500 * 0.95) - 120)
    T.ok(p.complete)
end

function tests.severalOutputs_areCountedOnAverage()
    local c = Start()
    Ready(c)
    local p = c.FG.Crafting.Profit(c.FG.Professions.Recipe(ELIXIR))
    T.eq(p.sale, math.floor(500 * 0.95) * 3, "two to four: three on average")
end

function tests.aMissingPrice_makesItIncomplete_notCheaper()
    local c = Start()
    Ready(c)
    local p = c.FG.Crafting.Profit(c.FG.Professions.Recipe(MINOR))
    T.no(p.complete, "no price for peacebloom")
    T.eq(p.profit, nil)
end

function tests.aMerchantsPrice_isTheFloor()
    local c = Start({ auctions = { { itemID = HERB_A, count = 1, buyout = 100 }, { itemID = 858, count = 1, buyout = 50 } } })
    Ready(c)
    local sale, where = c.FG.Crafting.SaleValue(c.FG.Professions.Recipe(LESSER))
    T.eq(where, "vendor", "a merchant pays more than the house nets")
    T.eq(sale, 100)
end

function tests.aLoss_isShownAsOne_andRankedLast()
    local c = Start({ auctions = { { itemID = HERB_A, count = 1, buyout = 5000 }, { itemID = HERB_B, count = 1, buyout = 10 },
                                   { itemID = 858, count = 1, buyout = 1000 }, { itemID = 2458, count = 1, buyout = 500 } } })
    Ready(c)
    local list = c.FG.Crafting.Ranking(ALCHEMY, "profit")
    local first, lesser = list[1], nil
    for _, p in ipairs(list) do if p.recipe.id == LESSER then lesser = p end end
    T.ok(lesser.profit < 0, "a loss")
    T.eq(first.recipe.id, ELIXIR, "the best first")
    T.no(list[#list].complete, "the ones missing a price last")
end

-- ==== the way up ============================================================

-- The expected cost of each point is a craft's cost over its chance; the cheapest recipe
-- at each skill is the answer, and this works it out by brute force to compare.
function tests.thePlan_isTheCheapestByBruteForce()
    local c = Start()
    Ready(c)
    -- Every turning point seen, so nothing is guessed.
    for _, id in ipairs({ LESSER, ELIXIR }) do
        local r = c.FG.Professions.Recipe(id)
        local at = c.recipes[id].at
        r.th = { ylo = at.y, yhi = at.y, glo = at.g, ghi = at.g, xlo = at.x, xhi = at.x }
    end
    local plan = c.FG.Crafting.Plan(ALCHEMY, 132, 150)
    T.no(plan.stuck)
    local expect = 0
    for s = 132, 149 do
        local best
        for _, id in ipairs({ LESSER, ELIXIR }) do
            local r = c.FG.Professions.Recipe(id)
            local chance = c.FG.Professions.Chance(r, s)
            local cost = c.FG.Crafting.MaterialCost(r)
            if chance > 0 then
                local per = cost / chance
                best = best and math.min(best, per) or per
            end
        end
        expect = expect + best
    end
    T.eq(plan.total, math.floor(expect + 0.5))
    T.no(plan.unsure)
    T.ok(#plan.segments >= 1)
end

function tests.thePlan_changesRecipeAsColoursChange()
    local c = Start({ auctions = { { itemID = HERB_A, count = 1, buyout = 100 }, { itemID = HERB_B, count = 50, buyout = 50 } } })
    Ready(c)
    for _, id in ipairs({ LESSER, ELIXIR }) do
        local r = c.FG.Professions.Recipe(id)
        local at = c.recipes[id].at
        r.th = { ylo = at.y, yhi = at.y, xlo = at.x, xhi = at.x }
    end
    local plan = c.FG.Crafting.Plan(ALCHEMY, 132, 160)
    local used = {}
    for _, seg in ipairs(plan.segments) do used[seg.recipe.id] = true end
    T.ok(used[ELIXIR] and used[LESSER], "the elixir goes grey at 155 and is cheap early; the potion carries on")
end

function tests.thePlan_trainsTheNextRankOnTheWay()
    local c = Start()
    Ready(c)
    local plan = c.FG.Crafting.Plan(ALCHEMY, 145, 160)
    T.eq(plan.train[1] and plan.train[1].cap, 225, "Expert at 150: " .. tostring(plan.stuck))
    T.eq(plan.train[1].at, 150)
end

function tests.aSkillNothingCanRaise_isSaidToBeTheEnd()
    local c = Start()
    Ready(c)
    local plan = c.FG.Crafting.Plan(ALCHEMY, 132, 300)
    T.ok(plan.stuck, "every learned recipe is grey long before 300")
end

function tests.ownMaterials_countAsFree_inThatMode()
    local c = Start({ bags = { [HERB_A] = 100, [VIAL] = 100 } })
    Ready(c)
    local mine = c.FG.Crafting.Plan(ALCHEMY, 132, 140, "mine")
    local upfront = c.FG.Crafting.Plan(ALCHEMY, 132, 140, "upfront")
    T.eq(mine.total, 0)
    T.ok(upfront.total > 0)
end

function tests.aGuessedColour_isSaidToBeOne()
    local c = Start()
    Ready(c)
    local plan = c.FG.Crafting.Plan(ALCHEMY, 132, 140)
    T.ok(plan.unsure, "only one skill seen: the bands are assumed")
end

-- ==== lists =================================================================

function tests.aList_mergesReagents_andCountsTheBagsAndBank()
    local c = Start({ bags = { [VIAL] = 2 }, bank = { [VIAL] = 5 } })
    Ready(c)
    local C = c.FG.Crafting
    local project = C.NewProject("Potions to sell")
    C.AddToProject(project, LESSER, 4)
    C.AddToProject(project, ELIXIR, 3)
    local list = C.Shopping(project)
    local vials, herbs
    for _, row in ipairs(list.rows) do
        if row.id == VIAL then vials = row end
        if row.id == HERB_B then herbs = row end
    end
    T.eq(vials.need, 4 + 1, "four potions and one run of elixirs: one vial each")
    T.eq(vials.bags, 2)
    T.eq(vials.bank, 5)
    T.eq(vials.left, 3, "the bank is shown, not counted as in hand")
    T.eq(herbs.need, 2)
end

function tests.aMark_isNeverOverwritten()
    local c = Start()
    Ready(c)
    local C = c.FG.Crafting
    local project = C.NewProject("Mine")
    C.AddToProject(project, LESSER, 2)
    C.Mark(project, HERB_A, "bought")
    local row
    for _, r in ipairs(C.Shopping(project).rows) do if r.id == HERB_A then row = r end end
    T.eq(row.mark, "bought")
    T.eq(row.left, 0)
end

function tests.anIntermediate_isMadeWhenThatIsCheaper()
    local c = Start({ auctions = { { itemID = HERB_A, count = 1, buyout = 100 }, { itemID = HERB_B, count = 10, buyout = 100 },
                                   { itemID = 2458, count = 1, buyout = 90000 } } })
    Ready(c)
    local C = c.FG.Crafting
    local unit, how = C._UnitCost(2458)
    T.eq(how, "craft", "buying the elixir costs 9g; making it costs copper")
    local project = C.NewProject("Oil")
    C.AddToProject(project, OIL, 1)
    local bought = C.Shopping(project, false)
    local made = C.Shopping(project, true)
    local elixirBought, herbMade = false, false
    for _, r in ipairs(bought.rows) do elixirBought = elixirBought or r.id == 2458 end
    for _, r in ipairs(made.rows) do herbMade = herbMade or r.id == HERB_B end
    T.ok(elixirBought)
    T.ok(herbMade, "broken into its own reagents")
    T.ok(unit)
end

function tests.listsSurviveAReload()
    local c = Start()
    Ready(c)
    local project = c.FG.Crafting.NewProject("Keep me")
    c.FG.Crafting.AddToProject(project, LESSER, 3)
    local d = Start({ saved = Stack.Saved(c) })
    local kept = d.FG.Crafting.Projects()
    T.eq(#kept, 1)
    T.eq(kept[1].items[1].qty, 3)
end

-- ==== trainers ==============================================================

function tests.aTrainersWindow_saysWhatItTeaches()
    local c = Start()
    c.trainer = { npcID = 1386, services = {
        { name = "Expert Alchemist", rank = "Expert", skill = "Alchemy", skillRank = 125, level = 20, cost = 10000 },
        { name = "Elixir of Wisdom", category = "unavailable" },
    } }
    c:Fire("TRAINER_SHOW")
    c:Advance(0.5)
    local a = c.FG.Professions.Get(ALCHEMY)
    local state, rank = c.FG.Trainers.ForNext(1386, a)
    T.eq(state, "teaches")
    T.eq(rank.skill, 125)
    T.eq(rank.cost, 10000)
    T.eq(c.FG.Trainers.ForNext(9999, a), "unknown", "not visited: unknown, not assumed")
    c.trainer = { npcID = 5177, services = { { name = "Journeyman Alchemist", rank = "Journeyman", skill = "Alchemy", skillRank = 50 } } }
    c:Fire("TRAINER_SHOW")
    c:Advance(0.5)
    T.eq(c.FG.Trainers.ForNext(5177, a), "no", "a nearer one that cannot teach Expert")
    T.ok(c.FG.Trainers.ORDER.teaches < c.FG.Trainers.ORDER.unknown)
    T.ok(c.FG.Trainers.ORDER.unknown < c.FG.Trainers.ORDER.no)
end

function tests.aSearchForATrainer_putsTheOneThatTeachesFirst()
    local c = Start()
    c:Advance(1)
    c.FG.Bridge.WarmSearch()
    c:Advance(2)
    local results = c.FG.Search.Run("alchemy trainer", "all")
    local trainers = {}
    for _, r in ipairs(results) do
        if r.data and r.data.npcID then trainers[#trainers + 1] = r end
    end
    if #trainers < 2 then return T.ok(true, "the stand-in's data has too few alchemy trainers to order") end
    local last = trainers[#trainers]
    c.trainer = { npcID = last.data.npcID, services = { { name = "Expert Alchemist", rank = "Expert", skill = "Alchemy", skillRank = 125 } } }
    c:Fire("TRAINER_SHOW")
    c:Advance(0.5)
    local again = c.FG.Search.Run("alchemy trainer", "all")
    local first
    for _, r in ipairs(again) do
        if r.data and r.data.npcID then first = first or r end
    end
    T.eq(first.data.npcID, last.data.npcID, "the one known to teach Expert leads")
    T.eq(first.trainer, "teaches")
end

return tests
