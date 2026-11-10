-- Prices for a few items, asked of the auction house one at a time: the reagents of a list,
-- fresher than the last full scan, and every listing on offer rather than the cheapest
-- tiers. Only ever started by the player's click, with the auction house open.
--
-- From CraftProfit's AHAdapter.lua (https://github.com/Renaud-Sto/CraftProfit, commit
-- 79e8eda, MIT License, Copyright (c) 2026 Sto, Licenses/CraftProfit-LICENSE.txt): a
-- price-sorted SendSearchQuery, sent only when IsThrottledMessageSystemReady says so; a
-- reagent answers on COMMODITY_SEARCH_RESULTS_UPDATED and gear on ITEM_SEARCH_RESULTS_UPDATED
-- (F1); the first answer holds every row and a second, identical one may follow (F13), so
-- an answer for an item no longer asked about is ignored; at most 100 rows are read, and
-- fewer than 100 means the list was complete. Rewritten here as a queue, with a time limit
-- per item: CraftProfit measured answers in 0.15 to 0.27 s and allows 6.
local FG = ForeverGPS
local Search = {}
FG.MarketSearch = Search

local TIMEOUT, MAX_RESULTS, NOT_READY_WAIT = 6, 100, 0.4
Search.TIMEOUT, Search.MAX_RESULTS = TIMEOUT, MAX_RESULTS

local queue, queued, current = {}, {}, nil
local results = { asked = 0, answered = 0, missed = 0, empty = 0 }
local open = false

local function Secret(v) return issecretvalue ~= nil and issecretvalue(v) == true end

local function Available()
    local api = C_AuctionHouse
    return api and api.SendSearchQuery and api.MakeItemKey and true or false
end

function Search.Available() return Available() end

-- Where the queue stands: items waiting, the one asked now, and what came back.
function Search.Status()
    return { waiting = #queue, current = current and current.id or nil, asked = results.asked,
             answered = results.answered, missed = results.missed, empty = results.empty }
end

local Next

local function Done(id)
    if not (current and current.id == id) then return end
    current = nil
    FG.Emit("market:changed")
    FG.After(0, Next)
end

function Next()
    if current or not open then return end
    local id = table.remove(queue, 1)
    if not id then return FG.Emit("market:changed") end
    queued[id] = nil
    local api = C_AuctionHouse
    if api.IsThrottledMessageSystemReady and not api.IsThrottledMessageSystemReady() then
        table.insert(queue, 1, id)
        queued[id] = true
        return FG.After(NOT_READY_WAIT, Next)
    end
    local sorts = {}
    local price = Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price
    if price ~= nil then sorts = { { sortOrder = price, reverseSort = false } } end
    local ok = pcall(function() api.SendSearchQuery(api.MakeItemKey(id), sorts, true) end)
    results.asked = results.asked + 1
    if not ok then
        results.missed = results.missed + 1
        return FG.After(0, Next)
    end
    local mine = { id = id, at = GetTime() }
    current = mine
    FG.After(TIMEOUT, function()
        if current == mine then
            results.missed = results.missed + 1
            Done(id)
        end
    end)
end

-- Asks for these items' prices. Returns how many were added to the queue.
function Search.Ask(ids)
    if not (open and Available()) then return 0 end
    local n = 0
    for _, id in ipairs(ids) do
        if type(id) == "number" and not queued[id] and not (current and current.id == id) then
            queue[#queue + 1] = id
            queued[id] = true
            n = n + 1
        end
    end
    if n > 0 then
        FG.Emit("market:changed")
        Next()
    end
    return n
end

function Search.Cancel()
    queue, queued, current = {}, {}, nil
    FG.Emit("market:changed")
end

-- Every row the answer holds, as unit price and count pairs. full: every unit on offer.
local function Commodity(itemID)
    local api = C_AuctionHouse
    local list, full = {}, false
    local n = api.GetNumCommoditySearchResults(itemID)
    if Secret(n) or type(n) ~= "number" then return list, false end
    full = n < MAX_RESULTS
    for i = 1, math.min(n, MAX_RESULTS) do
        local info = api.GetCommoditySearchResultInfo(itemID, i)
        if info and not Secret(info.unitPrice) and not Secret(info.quantity)
            and type(info.unitPrice) == "number" and type(info.quantity) == "number" and info.quantity > 0 then
            list[#list + 1] = info.unitPrice
            list[#list + 1] = info.quantity
        else
            full = false
        end
    end
    return list, full
end

local function Item(itemKey)
    local api = C_AuctionHouse
    local list, full = {}, false
    local n = api.GetNumItemSearchResults(itemKey)
    if Secret(n) or type(n) ~= "number" then return list, false end
    full = n < MAX_RESULTS
    for i = 1, math.min(n, MAX_RESULTS) do
        local info = api.GetItemSearchResultInfo(itemKey, i)
        if info and not Secret(info.buyoutAmount) and not Secret(info.quantity) then
            local qty = type(info.quantity) == "number" and info.quantity > 0 and info.quantity or 1
            -- A bid-only auction cannot be bought out: not on offer, and not a gap.
            if type(info.buyoutAmount) == "number" and info.buyoutAmount > 0 then
                list[#list + 1] = math.floor(info.buyoutAmount / qty)
                list[#list + 1] = qty
            end
        else
            full = false
        end
    end
    return list, full
end

-- An answer: into the market store, as this item's freshest price.
local function Answer(id, list, full)
    if not (current and current.id == id) then return end
    local house = FG.Market.House(FG.Market.Key())
    house.fresh = house.fresh or {}
    house.cut = house.cut or {}
    if #list > 0 then
        house.items[id] = FG.Market.Pack(list)
        house.fresh[id] = time()
        house.cut[id] = not full or nil
        results.answered = results.answered + 1
    else
        -- Nobody selling now. The old price stays, and its age says how old it is.
        results.empty = results.empty + 1
        house.none = house.none or {}
        house.none[id] = time()
    end
    FG.Emit("market:prices", FG.Market.Key())
    Done(id)
end

FG.OnEvent("AUCTION_HOUSE_SHOW", function() open = true end)
FG.OnEvent("AUCTION_HOUSE_CLOSED", function()
    open = false
    Search.Cancel()
end)
FG.OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED", function(itemID)
    if Secret(itemID) or type(itemID) ~= "number" then return end
    if current and current.id == itemID then
        local ok, list, full = pcall(Commodity, itemID)
        Answer(itemID, ok and list or {}, ok and full)
    end
end)
FG.OnEvent("ITEM_SEARCH_RESULTS_UPDATED", function(itemKey)
    local id = type(itemKey) == "table" and itemKey.itemID
    if Secret(id) or type(id) ~= "number" then return end
    if current and current.id == id then
        local ok, list, full = pcall(Item, itemKey)
        Answer(id, ok and list or {}, ok and full)
    end
end)
