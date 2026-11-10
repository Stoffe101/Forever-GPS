-- Auction house adapter: the only file that talks to C_AuctionHouse.
-- It turns the game's results into plain { unit, qty } listings. A search's listings also
-- carry `full`: true when they hold every unit on offer (fewer rows than
-- MAX_SEARCH_RESULTS and none skipped as unreadable), false when the list was cut, so
-- their total volume is only part of the market.
local _, ns = ...
local Util, Prices = ns.Util, ns.Prices

local AH = {}
ns.AH = AH

AH.isOpen = false
-- docs/probe-findings.md F2 (measured 2026-10-08): GetReplicateItemInfo's buyout
-- is the price of the whole stack, not of one unit.
AH.PER_UNIT_REPLICATE = false
AH.CHUNK = 1500             -- scan rows read per frame
AH.REPLICATE_COOLDOWN = 15 * 60
AH.MAX_SEARCH_RESULTS = 100 -- results come sorted by price; the cheapest are enough
-- The client fires REPLICATE_ITEM_LIST_UPDATE hundreds of times for one scan
-- (measured in the beta). One read is scheduled after DEBOUNCE seconds; events
-- during that wait, during the read, or within REREAD_QUIET seconds of its end
-- are the same scan and are ignored.
AH.DEBOUNCE = 1
AH.REREAD_QUIET = 10

local EVENTS = {
    "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED",
    "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED",
    "REPLICATE_ITEM_LIST_UPDATE",
}

local handlers = {}
local snapshotToken = 0
local lastReplicate
local replicatePending, reading, lastRead = false, false, nil

function AH.setHandlers(h)
    handlers = h or {}
end

local isSecret = Util.isSecret

-- Seconds before another full scan is allowed (Blizzard limits it account-wide).
function AH.cooldownLeft(now)
    if not lastReplicate or not Util.isFinite(now) then return 0 end
    local left = AH.REPLICATE_COOLDOWN - (now - lastReplicate)
    if left > 0 then return left end
    return 0
end

function AH.requestSnapshot(now)
    if not AH.isOpen then return false, "closed" end
    local api = C_AuctionHouse
    if not api or not api.ReplicateItems then return false, "unavailable" end
    local left = AH.cooldownLeft(now)
    if left > 0 then return false, "cooldown", left end
    if not pcall(api.ReplicateItems) then return false, "unavailable" end
    lastReplicate = now
    return true
end

-- Quality of life, never a purchase: types the item's name in the AH's own search box
-- and starts the search, then presets the quantity when the item's buy view opens.
-- Every Blizzard frame is reached defensively: a missing piece skips that step.
local pendingQuantity
local quantityHooked = false

local function applyPendingQuantity(buyFrame)
    local pending = pendingQuantity
    if not pending or GetTime() > pending.expires then
        pendingQuantity = nil
        return
    end
    local ok, shownID = pcall(function() return buyFrame.GetItemID and buyFrame:GetItemID() end)
    if ok and type(shownID) == "number" and shownID ~= pending.itemID then return end
    -- Let the buy view receive its search results first, then set the quantity the way
    -- typing it would: setting the number alone leaves the quote on one unit (measured
    -- in the beta: quantity 20, price of 1, "item no longer available" on Buy).
    C_Timer.After(0.3, function()
        local display = buyFrame.BuyDisplay
        local input = display and display.QuantityInput
        if not (input and type(input.SetQuantity) == "function") then return end
        pcall(input.SetQuantity, input, pending.qty)
        local box = input.InputBox
        local typed = type(box) == "table" and type(box.GetScript) == "function"
            and select(2, pcall(box.GetScript, box, "OnTextChanged"))
        if type(typed) == "function" then pcall(typed, box, true) end
    end)
    pendingQuantity = nil
end

local function hookBuyFrame(frame)
    local buy = frame.CommoditiesBuyFrame
    if quantityHooked or type(buy) ~= "table" or type(buy.HookScript) ~= "function" then return end
    if pcall(buy.HookScript, buy, "OnShow", function() applyPendingQuantity(buy) end) then
        quantityHooked = true
    end
end

-- Returns true when the search was started, else false and a reason.
function AH.browse(name, itemID, quantity)
    if not AH.isOpen then return false, "closed" end
    local frame = AuctionHouseFrame
    local bar = type(frame) == "table" and frame.SearchBar
    local box = type(bar) == "table" and bar.SearchBox
    if type(box) ~= "table" or type(box.SetText) ~= "function" or type(bar.StartSearch) ~= "function" then
        return false, "unavailable"
    end
    local modes = AuctionHouseFrameDisplayMode
    if type(frame.SetDisplayMode) == "function" and type(modes) == "table" and modes.Buy ~= nil then
        pcall(frame.SetDisplayMode, frame, modes.Buy)
    end
    if not pcall(box.SetText, box, name) then return false, "unavailable" end
    if not pcall(bar.StartSearch, bar) then return false, "unavailable" end
    pendingQuantity = Util.count(quantity)
        and { itemID = itemID, qty = quantity, expires = GetTime() + 60 } or nil
    hookBuyFrame(frame)
    return true
end

-- Sends a price-sorted search. The answer arrives through handlers.onSearch.
function AH.search(itemID)
    local api = C_AuctionHouse
    if not AH.isOpen or not api or not api.SendSearchQuery or not api.MakeItemKey then return false end
    if api.IsThrottledMessageSystemReady and not api.IsThrottledMessageSystemReady() then return false end
    local sorts = {}
    local price = Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price
    if price ~= nil then sorts = { { sortOrder = price, reverseSort = false } } end
    return pcall(function()
        api.SendSearchQuery(api.MakeItemKey(itemID), sorts, true)
    end)
end

local function readCommodity(itemID)
    local api = C_AuctionHouse
    local listings = { full = false }
    local n = api.GetNumCommoditySearchResults(itemID)
    if isSecret(n) or not Util.isFinite(n) then return listings end
    listings.full = n < AH.MAX_SEARCH_RESULTS
    for i = 1, math.min(n, AH.MAX_SEARCH_RESULTS) do
        local info = api.GetCommoditySearchResultInfo(itemID, i)
        if info and not isSecret(info.unitPrice) and not isSecret(info.quantity) then
            listings[#listings + 1] = { unit = info.unitPrice, qty = info.quantity }
        else
            listings.full = false
        end
    end
    return listings
end

local function readItem(itemKey)
    local api = C_AuctionHouse
    local listings = { full = false }
    local n = api.GetNumItemSearchResults(itemKey)
    if isSecret(n) or not Util.isFinite(n) then return listings end
    listings.full = n < AH.MAX_SEARCH_RESULTS
    for i = 1, math.min(n, AH.MAX_SEARCH_RESULTS) do
        local info = api.GetItemSearchResultInfo(itemKey, i)
        if info and not isSecret(info.buyoutAmount) and not isSecret(info.quantity) then
            local qty = Util.count(info.quantity or 1)
            -- A bid-only auction cannot be bought out: it is not on offer, not a gap.
            if qty and Util.isCopper(info.buyoutAmount) and info.buyoutAmount > 0 then
                listings[#listings + 1] = { unit = info.buyoutAmount / qty, qty = qty }
            elseif type(info.buyoutAmount) == "number" and info.buyoutAmount > 0 then
                -- A buyout that could not be read (bad quantity, absurd amount) is a gap.
                listings.full = false
            end
        else
            listings.full = false
        end
    end
    return listings
end

-- Reads the full scan in chunks of AH.CHUNK rows per frame so the client never
-- freezes. A newer scan, or closing the AH, abandons the one in progress.
local function readSnapshot()
    local api = C_AuctionHouse
    if not api or not api.GetNumReplicateItems or not api.GetReplicateItemInfo then return end
    local ok, total = pcall(api.GetNumReplicateItems)
    if not ok or isSecret(total) or not Util.count(total) then return end
    snapshotToken = snapshotToken + 1
    local token = snapshotToken
    reading = true
    local agg = Prices.newAggregator()
    local index = 0
    local function readRows(first, last)
        for i = first, last do
            local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = api.GetReplicateItemInfo(i)
            if not (isSecret(count) or isSecret(buyout) or isSecret(itemID)) then
                local qty = Util.count(count)
                if qty and Util.isCopper(buyout) and buyout > 0 then
                    agg.add(itemID, AH.PER_UNIT_REPLICATE and buyout or buyout / qty, qty)
                end
            end
        end
    end
    local function step()
        if token ~= snapshotToken then return end
        local last = math.min(index + AH.CHUNK, total)
        -- A read that raises ends this scan; `reading` must never stay true, or every later
        -- scan of this AH session would be ignored.
        if not pcall(readRows, index + 1, last) then
            reading = false
            lastRead = GetTime()
            return
        end
        index = last
        if index < total then
            C_Timer.After(0, step)
        else
            reading = false
            lastRead = GetTime()
            if handlers.onSnapshot then handlers.onSnapshot(agg, total) end
        end
    end
    step()
end

function AH.onEvent(event, arg1)
    if event == "AUCTION_HOUSE_SHOW" then
        AH.isOpen = true
        if handlers.onOpen then handlers.onOpen(true) end
    elseif event == "AUCTION_HOUSE_CLOSED" then
        AH.isOpen = false
        snapshotToken = snapshotToken + 1
        replicatePending, reading = false, false
        -- A preset asked for in this session must not apply in the next one.
        pendingQuantity = nil
        if handlers.onOpen then handlers.onOpen(false) end
    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
        local itemID = Util.id(arg1)
        if itemID and handlers.onSearch then handlers.onSearch(itemID, readCommodity(itemID)) end
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
        local itemID = type(arg1) == "table" and Util.id(arg1.itemID)
        if itemID and handlers.onSearch then handlers.onSearch(itemID, readItem(arg1)) end
    elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
        -- Also fires for scans other addons started; they use the same cooldown.
        local now = GetTime()
        lastReplicate = now
        AH.lastEventTime = now
        if replicatePending or reading then return end
        if lastRead and now - lastRead < AH.REREAD_QUIET then return end
        replicatePending = true
        local token = snapshotToken
        C_Timer.After(AH.DEBOUNCE, function()
            if token ~= snapshotToken then return end
            replicatePending = false
            readSnapshot()
        end)
    end
end

local frame = CreateFrame("Frame")
for _, event in ipairs(EVENTS) do
    pcall(frame.RegisterEvent, frame, event)
end
frame:SetScript("OnEvent", function(_, event, arg1) AH.onEvent(event, arg1) end)
