-- What 2.4 got wrong in the real game, and what the stand-in client was too kind about.
--
-- Found in the user's game (2.4, BugSack and saved data, 2026-11-11):
--   - GetItemInfo, GetItemCount, GetItemCooldown and GetMerchantItemInfo do not exist there.
--     Every profit figure, plan and list called one of them and failed, so Profit and
--     Skill up never showed anything, and merchants' prices were never learned. The
--     stand-in had them; it no longer does.
--   - The recipe window was read correctly (15 learned recipes, their IDs in the client's
--     data), so recipe reading was not the cause; it is made sturdier here anyway, since
--     whether its update event always comes is not known.
--   - Rows were measured at one width and drawn at another, at fixed heights.
-- And what the user asked for: prices that update by themselves at the auction house.
local T = require("support.t")
local Stack = require("support.stack")
local UI = require("support.fakeui")

local ALCHEMY = 171
local HERB, VIAL = 900, 902
local POTION, ELIXIR = 1001, 1002

local function Recipes()
    return {
        [POTION] = { name = "Lesser Healing Potion", line = ALCHEMY, out = 858, reagents = { { id = HERB, n = 1 }, { id = VIAL, n = 1 } },
                     at = { y = 140, g = 155, x = 170 } },
        [ELIXIR] = { name = "Elixir of Minor Fortitude", line = ALCHEMY, out = 2458, reagents = { { id = 901, n = 2 }, { id = VIAL, n = 1 } },
                     at = { y = 135, g = 145, x = 155 } },
    }
end

local function Start(opts)
    opts = opts or {}
    opts.mapID, opts.x, opts.y = opts.mapID or 1453, opts.x or 0.6, opts.y or 0.6
    if opts.ui == nil then opts.ui = false end
    opts.professions = opts.professions or { { name = "Alchemy", skill = 132, max = 150, line = ALCHEMY } }
    opts.recipes = opts.recipes or Recipes()
    opts.auctions = opts.auctions or {}
    opts.merchant = opts.merchant or {}
    opts.items = opts.items or { [HERB] = { name = "Peacebloom" }, [VIAL] = { name = "Empty Vial" }, [858] = { name = "Lesser Healing Potion", sell = 100 } }
    local c = Stack.new(opts)
    c:Advance(4)
    return c
end

-- The profession window opening, as the game does it: the show event, then (unless the
-- stand-in is told otherwise) the list update.
local function OpenWindow(c)
    c.openProfession = c.professions[1]
    c:Fire("TRADE_SKILL_SHOW")
    if not c.noListUpdate then c:After(0.1, function() c:Fire("TRADE_SKILL_LIST_UPDATE") end) end
end

local tests = {}

-- ==== the missing globals ===================================================

function tests.theOldItemGlobals_areGone_andNothingNeedsThem()
    local c = Start({ ui = true, auctions = { { itemID = HERB, count = 20, buyout = 2000 }, { itemID = 858, count = 2, buyout = 6000 } },
                      merchant = { { id = VIAL, price = 20 } } })
    T.eq(c.env.GetItemInfo, nil, "as in the game")
    T.eq(c.env.GetItemCount, nil)
    T.eq(c.env.GetMerchantItemInfo, nil)
    c:Fire("MERCHANT_SHOW")
    c:Advance(0.5)
    T.eq(c.FG.Market.VendorBuy(VIAL), 20, "a merchant's price is learned through C_MerchantFrame")
    OpenWindow(c)
    c:Advance(1)
    c:Fire("AUCTION_HOUSE_SHOW")
    Stack.Until(c, function() return c.FG.Market.Scanning().state == "done" end, 20)
    local ranking = c.FG.Crafting.Ranking(ALCHEMY, "profit")
    T.eq(#ranking, 2, "both recipes ranked")
    T.ok(ranking[1].complete, "the potion priced")
    c.FG.Window.Show("professions")
    for _, which in ipairs({ "overview", "leveling", "profit", "lists", "market" }) do
        c.FG.ProfessionsView.Show(which)
        if which == "profit" then c.FG.ProfessionsView.AddToList(POTION) end
        c:Advance(0.5)
    end
    c.FG.ProfessionsView.Show("leveling")
    Stack.Until(c, function() return c.FG.ProfessionsView.PlanState().status ~= "planning" end, 20)
    T.eq(c.FG.ProfessionsView.PlanState().status, "done", "the plan finishes")
    T.eq(#c.errors, 0, tostring(c.errors[1]))
    T.eq(c.FG.ProfessionsView.state.errors, 0, tostring(c.FG.ProfessionsView.state.lastError))
end

-- ==== reading the profession window =========================================

function tests.noListUpdate_theWindowOpeningStillReads()
    local c = Start()
    c.noListUpdate = true
    OpenWindow(c)
    c:Advance(1)
    T.eq(#c.FG.Professions.Recipes(ALCHEMY), 2)
    T.eq(c.FG.Professions.status.lastWhy, "ok")
    T.eq(c.FG.Professions.status.events.TRADE_SKILL_LIST_UPDATE, nil)
end

function tests.recipesArrivingLate_areReadWhenTheyCome()
    local c = Start()
    c.recipesAt = c.now + 2.5
    c.noListUpdate = true
    OpenWindow(c)
    c:Advance(1)
    T.eq(#c.FG.Professions.Recipes(ALCHEMY), 0, "nothing there yet")
    T.eq(c.FG.Professions.status.lastWhy, "empty")
    c:Advance(3)
    T.eq(#c.FG.Professions.Recipes(ALCHEMY), 2, "read once they are")
end

function tests.reagentsArrivingLate_areFilledIn()
    local c = Start()
    c.schematicsAt = c.now + 2.5
    c.noListUpdate = true
    OpenWindow(c)
    c:Advance(1)
    T.eq(c.FG.Professions.status.lastWhy, "partial", "learned recipes without reagents: not done")
    c:Advance(3)
    T.eq(c.FG.Professions.status.lastWhy, "ok")
    T.ok(c.FG.Professions.Recipe(POTION).reagents[1], "reagents read")
end

function tests.anEmptyWindow_isRetriedAFewTimes_thenLeft()
    local c = Start({ recipes = {} })
    c.noListUpdate = true
    OpenWindow(c)
    c:Advance(30)
    local reads = c.FG.Professions.status.lastWhy
    T.eq(reads, "empty")
    T.ok(#c.errors == 0)
    -- Bounded: no read after the tries run out.
    local calls = 0
    local get = c.env.C_TradeSkillUI.GetAllRecipeIDs
    c.env.C_TradeSkillUI.GetAllRecipeIDs = function() calls = calls + 1 return get() end
    c:Advance(30)
    T.eq(calls, 0, "no polling once the tries are spent")
end

function tests.noProfessionApi_isSaid_notAnError()
    local c = Start()
    c.env.C_TradeSkillUI = nil
    OpenWindow(c)
    c:Advance(2)
    T.eq(c.FG.Professions.status.path, "missing")
    T.eq(#c.errors, 0)
end

function tests.aRecipeTheClientsDataKnows_getsItsReagentsBeforeTheWindowGivesThem()
    local c = Start({ professions = { { name = "Leatherworking", skill = 10, max = 75, line = 165 } },
                      recipes = { [2149] = { name = "Handstitched Leather Boots", line = 165 } } })
    c.schematicsAt = c.now + 100
    c.noListUpdate = true
    OpenWindow(c)
    c:Advance(1)
    local r = c.FG.Professions.Recipe(2149)
    T.ok(r.reagents and r.reagents[1], "the client's data stands in")
    T.ok(r.fromData)
    T.eq(c.FG.Professions.status.matched, 1)
end

-- ==== items not cached yet ==================================================

function tests.anItemNotCachedYet_showsAPlaceholder_thenItsName()
    local c = Start()
    c.uncached = { [HERB] = true }
    T.eq(c.FG.Item.Label(HERB), c.FG.L["ITEM_LOADING_FMT"]:format(HERB))
    local loaded = 0
    c.FG.On("items:loaded", function() loaded = loaded + 1 end)
    c:Advance(1)
    T.eq(c.FG.Item.Label(HERB), "Peacebloom")
    T.eq(loaded, 1, "one redraw for the burst")
    T.eq(c.FG.Item.Pending(), 0)
end

function tests.anItemThatNeverComes_isAskedForOnceAMinute_atMost()
    local c = Start()
    c.uncached, c.itemNever = { [HERB] = true }, { [HERB] = true }
    for _ = 1, 50 do c.FG.Item.Label(HERB) end
    T.eq(c.itemRequests, 1, "asked once")
    c:Advance(61)
    c.FG.Item.Label(HERB)
    T.ok(c.itemRequests <= 2, "at most again after a minute")
end

-- ==== profit that never hides ===============================================

function tests.recipesWithoutPrices_areShown_withWhy()
    local c = Start({ ui = true })
    OpenWindow(c)
    c:Advance(1)
    c.FG.Window.Show("professions")
    c.FG.ProfessionsView.Show("profit")
    c:Advance(0.5)
    local lines, summary = 0, nil
    for _, item in ipairs(c.FG.ProfessionsView.ItemsNow()) do
        if item.kind == "line" then
            lines = lines + 1
            T.eq(item.right, "?", "no figure, not zero")
            T.ok(item.sub:find("no price", 1, true) or item.sub:find("nothing to sell", 1, true), item.sub)
        end
        if item.kind == "card" and item.title == c.FG.L["PV_PROFIT_TITLE"] then summary = item end
    end
    T.eq(lines, 2, "both recipes listed")
    T.ok(summary.body:find("2 recipes, 0 of them priced", 1, true), summary.body)
end

function tests.aFilterThatHidesEverything_offersToClearIt()
    local c = Start({ ui = true })
    OpenWindow(c)
    c:Advance(1)
    c.FG.Window.Show("professions")
    c.FG.ProfessionsView.Show("profit")
    c.FG.ProfessionsView._Set({ only = { complete = true } })
    c:Advance(0.3)
    local clear
    for _, item in ipairs(c.FG.ProfessionsView.ItemsNow()) do
        if item.action == c.FG.L["PV_CLEAR_FILTERS"] then clear = item end
    end
    T.ok(clear, "a way out")
    clear.run()
    c:Advance(0.3)
    local lines = 0
    for _, item in ipairs(c.FG.ProfessionsView.ItemsNow()) do if item.kind == "line" then lines = lines + 1 end end
    T.eq(lines, 2)
end

function tests.makingFive_pricesFive()
    local c = Start({ auctions = { { itemID = HERB, count = 3, buyout = 300 }, { itemID = HERB, count = 10, buyout = 2000 } },
                      merchant = { { id = VIAL, price = 20 } } })
    c:Fire("MERCHANT_SHOW")
    c:Advance(0.5)
    c:Fire("AUCTION_HOUSE_SHOW")
    Stack.Until(c, function() return c.FG.Market.Scanning().state == "done" end, 20)
    OpenWindow(c)
    c:Advance(1)
    local one = c.FG.Crafting.Profit(c.FG.Professions.Recipe(POTION), 1)
    local five = c.FG.Crafting.Profit(c.FG.Professions.Recipe(POTION), 5)
    T.eq(one.cost, 100 + 20)
    T.eq(five.cost, 3 * 100 + 2 * 200 + 5 * 20, "three at 1s, two at 2s: the tiers")
end

-- ==== the skill-up plan never hangs =========================================

local function Leveling(c)
    OpenWindow(c)
    c:Advance(1)
    c.FG.Window.Show("professions")
    c.FG.ProfessionsView.Show("leveling")
end

function tests.aPlanThatFails_saysWhy_andCanBeTriedAgain()
    local c = Start({ ui = true, auctions = { { itemID = HERB, count = 500, buyout = 50000 } }, merchant = { { id = VIAL, price = 20 } } })
    c:Fire("MERCHANT_SHOW")
    local plan = c.FG.Crafting.Plan
    c.FG.Crafting.Plan = function() error("a test failure") end
    Leveling(c)
    Stack.Until(c, function() return c.FG.ProfessionsView.PlanState().status ~= "planning" end, 10)
    T.eq(c.FG.ProfessionsView.PlanState().status, "failed")
    local card
    for _, item in ipairs(c.FG.ProfessionsView.ItemsNow()) do if item.action == c.FG.L["PV_TRY_AGAIN"] then card = item end end
    T.ok(card and card.body:find("a test failure", 1, true), "the reason is shown")
    c.FG.Crafting.Plan = plan
    card.run()
    Stack.Until(c, function() return c.FG.ProfessionsView.PlanState().status ~= "planning" end, 10)
    T.eq(c.FG.ProfessionsView.PlanState().status, "done", "and the retry works")
end

function tests.aPlanThatNeverAnswers_isGivenUp_notAnEndlessSpinner()
    local c = Start({ ui = true })
    c.FG.Crafting.PlanAsync = function() end
    Leveling(c)
    c:Advance(1)
    T.eq(c.FG.ProfessionsView.PlanState().status, "planning")
    c:Advance(12)
    c.FG.ProfessionsView.Refresh()
    T.eq(c.FG.ProfessionsView.PlanState().status, "stalled")
    local retry
    for _, item in ipairs(c.FG.ProfessionsView.ItemsNow()) do if item.action == c.FG.L["PV_TRY_AGAIN"] then retry = item end end
    T.ok(retry, "a way to try again")
end

function tests.aPlanThatStopsHalfway_saysHowFarAndWhy()
    local c = Start({ ui = true, auctions = { { itemID = HERB, count = 500, buyout = 50000 } }, merchant = { { id = VIAL, price = 20 } } })
    c:Fire("MERCHANT_SHOW")
    c:Fire("AUCTION_HOUSE_SHOW")
    Stack.Until(c, function() return c.FG.Market.Scanning().state == "done" end, 20)
    Leveling(c)
    -- To 225: the potion goes grey at 170, and the elixir has no herb price.
    c.FG.ProfessionsView._Set({ target = 225 })
    Stack.Until(c, function()
        local st = c.FG.ProfessionsView.PlanState()
        return st.status == "done" and st.key and st.key:find(":225:", 1, true)
    end, 20)
    c.FG.ProfessionsView.Refresh()
    local plan = c.FG.ProfessionsView.PlanState().plan
    -- Grey at 170 by the recipe, earlier by the estimate the colours seen so far allow.
    T.ok(plan.stuck and plan.stuck > 132 and plan.stuck <= 170, "stops partway: " .. tostring(plan.stuck))
    local card = c.FG.ProfessionsView.ItemsNow()
    local found = false
    for _, item in ipairs(card) do
        if item.kind == "card" and item.body and item.body:find(("through skill %d"):format(plan.stuck), 1, true) then found = true end
    end
    T.ok(found, "says how far it got")
end

function tests.newPrices_makeTheShownPlanStale()
    local c = Start({ ui = true, auctions = { { itemID = HERB, count = 500, buyout = 50000 } }, merchant = { { id = VIAL, price = 20 } } })
    c:Fire("MERCHANT_SHOW")
    Leveling(c)
    Stack.Until(c, function() return c.FG.ProfessionsView.PlanState().status == "done" end, 20)
    local key = c.FG.ProfessionsView.PlanState().key
    c.FG.Emit("market:prices", c.FG.Market.Key())
    c:Advance(0.5)
    T.ok(c.FG.ProfessionsView.PlanState().key ~= key, "planned again for the new prices")
end

-- ==== prices that update by themselves ======================================

local function OpenAH(c) c:Fire("AUCTION_HOUSE_SHOW") end

function tests.openingTheAuctionHouse_scansByItself()
    local c = Start({ auctions = { { itemID = HERB, count = 5, buyout = 500 } } })
    OpenAH(c)
    c:Advance(2)
    T.eq(c.replicated, nil, "not at once: other addons first")
    c:Advance(2)
    T.eq(c.replicated, 1, "asked by itself")
    T.ok(Stack.Until(c, function() return c.FG.Market.Scanning().state == "done" end, 20))
    T.eq(c.FG.Market.Price(HERB).buy, 100)
    T.ok(c.FG.Market.Scanning().auto)
end

function tests.freshPrices_areNotScannedAgain_butNeededItemsAreSearched()
    local c = Start({ auctions = { { itemID = HERB, count = 5, buyout = 500 } } })
    OpenAH(c)
    Stack.Until(c, function() return c.FG.Market.Scanning().state == "done" end, 20)
    c:Fire("AUCTION_HOUSE_CLOSED")
    OpenWindow(c)
    c:Advance(1)
    c.searches = {}
    OpenAH(c)
    c:Advance(4)
    T.eq(c.replicated, 1, "no second full scan")
    T.ok(#c.searches > 0, "the items still unpriced were searched")
    T.eq(c.FG.AutoPrices.status.last, "searches")
end

function tests.theServersWait_isKept_andAutomaticScansNeverRepeat()
    local c = Start({ auctions = { { itemID = HERB, count = 5, buyout = 500 } } })
    for _ = 1, 5 do
        OpenAH(c)
        c:Advance(5)
        Stack.Until(c, function() local s = c.FG.Market.Scanning().state return s == "done" or s == "failed" or s == "idle" end, 20)
        c:Fire("AUCTION_HOUSE_CLOSED")
        c:Advance(60)
    end
    T.eq(c.replicated, 1, "one full scan in fifteen minutes, however often it is opened")
end

function tests.anotherAddonsScan_isReadInstead()
    local c = Start({ auctions = { { itemID = HERB, count = 5, buyout = 500 } } })
    OpenAH(c)
    c:Advance(1)
    c.env.C_AuctionHouse.ReplicateItems()   -- another addon, before our wait is over
    c:Advance(5)
    T.eq(c.replicated, 1, "no second request")
    T.ok(Stack.Until(c, function() return c.FG.Market.Scanning().state == "done" end, 20))
    T.eq(c.FG.Market.Scanning().by, "other")
end

function tests.auctionatorsRecentScan_counts()
    local c = Start({ auctions = { { itemID = HERB, count = 5, buyout = 500 } } })
    c.env.Auctionator = { SavedState = { TimeOfLastReplicateScan = c.env.time() - 60 } }
    OpenAH(c)
    c:Advance(5)
    T.eq(c.replicated, nil, "Auctionator scanned a minute ago")
end

function tests.closingBeforeTheWait_asksNothing()
    local c = Start()
    OpenAH(c)
    c:Advance(1)
    c:Fire("AUCTION_HOUSE_CLOSED")
    OpenAH(c)
    c:Advance(1)
    c:Fire("AUCTION_HOUSE_CLOSED")
    c:Advance(10)
    T.eq(c.replicated, nil)
end

function tests.turnedOff_scansOnlyWhenAsked()
    local c = Start()
    c.FG.AutoPrices.Settings().auto = "off"
    OpenAH(c)
    c:Advance(5)
    T.eq(c.replicated, nil)
    T.eq(c.FG.AutoPrices.status.last, "off")
end

function tests.searchingYourself_stopsTheAutomaticSearches()
    local c = Start({ auctions = { { itemID = HERB, count = 5, buyout = 500 } } })
    c.searchDelay = 2
    OpenAH(c)
    Stack.Until(c, function() return c.FG.Market.Scanning().state == "done" end, 20)
    c:Fire("AUCTION_HOUSE_CLOSED")
    OpenWindow(c)
    c:Advance(1)
    c.searches = {}
    OpenAH(c)
    c:Advance(3.5)
    T.ok(c.FG.MarketSearch.Status().waiting > 0 or c.FG.MarketSearch.Status().current, "searching")
    c:Fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
    T.eq(c.FG.MarketSearch.Status().waiting, 0, "the rest dropped")
    T.eq(c.FG.AutoPrices.status.last, "searches stopped")
end

-- ==== nothing overlaps ======================================================

local function Rect(obj) return UI.rectOf(obj) end

local function Overlaps(a, b) return a.l < b.r - 0.5 and b.l < a.r - 0.5 and a.b < b.t - 0.5 and b.b < a.t - 0.5 end

-- Every row on screen: its texts inside it, and no two rows over each other.
local function CheckRows(c, label)
    local list = c.FG.ProfessionsView.Get().list
    local rows = {}
    for _, row in ipairs(list.shown) do
        local r = Rect(row)
        if r then
            rows[#rows + 1] = r
            for _, key in ipairs({ "name", "sub", "title", "body", "right" }) do
                local fs = row[key]
                if fs and fs._shown ~= false and (fs._text or "") ~= "" then
                    local t = Rect(fs)
                    T.ok(t and t.b >= r.b - 1 and t.t <= r.t + 1, ("%s: %q stays in its row"):format(label, fs._text))
                end
            end
            -- A card's button never sits over its text.
            if row.action and row.action._shown and row.body and (row.body._text or "") ~= "" then
                local btn, body = Rect(row.action), Rect(row.body)
                T.ok(not (btn and body and Overlaps(btn, body)), ("%s: a button over %q"):format(label, row.body._text:sub(1, 40)))
            end
        end
    end
    for i = 1, #rows do
        for j = i + 1, #rows do T.ok(not Overlaps(rows[i], rows[j]), label .. ": rows apart") end
    end
    return #rows
end

function tests.aLongList_inANarrowWindow_hasNoOverlap()
    local items = { [HERB] = { name = "Peacebloom" }, [VIAL] = { name = "Empty Vial" } }
    local recipes = Recipes()
    for i = 1, 25 do
        local id = 5000 + i
        items[id] = { name = ("A reagent with an extraordinarily long name, number %d, that keeps on going"):format(i) }
        recipes[POTION].reagents[#recipes[POTION].reagents + 1] = { id = id, n = i }
    end
    for _, screen in ipairs({ { 1920, 1080, 3 }, { 1920, 1080, 1.406 }, { 3440, 1440, 1.875 } }) do
        local c = Start({ ui = true, screen = screen, items = items, recipes = recipes, bags = { [HERB] = 3 }, bank = { [VIAL] = 2 },
                          merchant = { { id = VIAL, price = 20 } } })
        c:Fire("MERCHANT_SHOW")
        OpenWindow(c)
        c:Advance(1)
        c.FG.Window.Show("professions")
        local project = c.FG.Crafting.NewProject("A list with a long name")
        c.FG.Crafting.AddToProject(project, POTION, 40)
        for _, which in ipairs({ "lists", "profit", "leveling", "overview", "market" }) do
            c.FG.ProfessionsView.Show(which)
            c:Advance(1)
            local n = CheckRows(c, ("%dx%d@%.2f %s"):format(screen[1], screen[2], screen[3], which))
            T.ok(n > 0, which .. " shows rows")
            -- Scrolled down, the rows still sit apart.
            local list = c.FG.ProfessionsView.Get().list
            list.offset = math.max(0, list.total - list:GetHeight())
            list:Render()
            CheckRows(c, which .. " scrolled")
        end
        T.eq(#c.errors, 0, tostring(c.errors[1]))
    end
end

function tests.textThatTurnsOutTaller_growsItsRow()
    local c = Start({ ui = true })
    OpenWindow(c)
    c:Advance(1)
    c.FG.Window.Show("professions")
    c.FG.ProfessionsView.Show("overview")
    c:Advance(0.5)
    -- The game's font measuring taller than the estimate: the drawn row notices.
    local before = c.FG.ProfessionsView.overflows
    local measure = c.FG.ProfessionsView._TextHeight
    local list = c.FG.ProfessionsView.Get().list
    local item = list.items[1]
    item._minH = nil
    list.heights[1] = 10
    list:Render()
    c:Advance(0.1)
    T.ok(c.FG.ProfessionsView.overflows > before, "noticed")
    T.ok(list.heights[1] > 10, "and given room")
    T.ok(measure ~= nil)
end


-- ==== the report ============================================================

function tests.theReport_saysWhatTheProfessionsPageRestsOn_withoutNames()
    local c = Start({ ui = true })
    OpenWindow(c)
    c:Advance(1)
    c.FG.Window.Show("professions")
    c.FG.ProfessionsView.Show("profit")
    c:Advance(0.5)
    local text = c.FG.Diagnostics.Report()
    for _, want in ipairs({ "Professions: 171 132/150 (2 learned, 2 with reagents)", "Recipe reading: api C_TradeSkillUI",
                            "TRADE_SKILL_SHOW=1", "Items: info C_Item.GetItemInfo", "merchant C_MerchantFrame.GetItemInfo",
                            "Professions page: 2 ranked", "Market: Alliance house (told by map)", "Automatic prices: permitted" }) do
        T.ok(text:find(want, 1, true), "the report says: " .. want)
    end
    T.no(text:find("Testrealm", 1, true), "no realm name")
    T.no(text:find("Tester", 1, true), "no character name")
end

return tests
