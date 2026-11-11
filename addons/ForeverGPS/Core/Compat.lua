-- Items and merchants, the way this client asks for them.
--
-- Found in the real game (2.4, BugSack): the old globals GetItemInfo, GetItemCount,
-- GetItemCooldown and GetMerchantItemInfo do not exist in WoW Forever 1.60.1. They moved
-- to C_Item, C_Container and C_MerchantFrame, as in the game's own UI code of the same
-- build line (12.1.5). Every profit figure, plan and list called them and failed, and
-- merchants' prices were never learned. Everything here asks the current API first and
-- the old name only where a client still has it.
--
-- Item names may not be cached yet. A missing name is asked for (C_Item.
-- RequestLoadItemDataByID) and shown as a placeholder meanwhile; when the game answers
-- (GET_ITEM_INFO_RECEIVED), "items:loaded" tells the pages to draw again, once per burst.
-- The waiting list is bounded, and nothing is asked twice in a minute.
local FG = ForeverGPS
local Item = {}
FG.Item = Item
local Merchant = {}
FG.Merchant = Merchant

local L = FG.L

local MOST_PENDING, ASK_AGAIN = 200, 60
local pending, pendingCount, asked = {}, 0, {}
Item.stats = { asked = 0, received = 0, dropped = 0 }

local function Api(namespace, name, legacy)
    local ns = _G[namespace]
    local fn = ns and ns[name]
    if type(fn) == "function" then return fn end
    fn = legacy and _G[legacy]
    return type(fn) == "function" and fn or nil
end

-- Which way each was found, for /fgps report.
function Item.Paths()
    local function Which(namespace, name, legacy)
        local ns = _G[namespace]
        if ns and type(ns[name]) == "function" then return namespace .. "." .. name end
        if legacy and type(_G[legacy]) == "function" then return legacy end
        return "missing"
    end
    return {
        info = Which("C_Item", "GetItemInfo", "GetItemInfo"),
        count = Which("C_Item", "GetItemCount", "GetItemCount"),
        cooldown = Which("C_Container", "GetItemCooldown", "GetItemCooldown"),
        merchant = Which("C_MerchantFrame", "GetItemInfo", "GetMerchantItemInfo"),
        load = Which("C_Item", "RequestLoadItemDataByID"),
    }
end

-- Everything GetItemInfo gives, or nothing while the item is not cached.
function Item.Info(id)
    local fn = Api("C_Item", "GetItemInfo", "GetItemInfo")
    if not (fn and id) then return nil end
    return fn(id)
end

local function Request(id)
    if not id or pending[id] then return end
    local now = GetTime()
    if asked[id] and now - asked[id] < ASK_AGAIN then return end
    if pendingCount >= MOST_PENDING then
        Item.stats.dropped = Item.stats.dropped + 1
        return
    end
    asked[id] = now
    local load = Api("C_Item", "RequestLoadItemDataByID")
    if not load then return end
    pending[id], pendingCount = true, pendingCount + 1
    Item.stats.asked = Item.stats.asked + 1
    pcall(load, id)
end

-- An item's name, or nil while the game has not sent it (it is asked for).
function Item.Name(id)
    local name = Item.Info(id)
    if type(name) == "string" and name ~= "" then return name end
    local byID = Api("C_Item", "GetItemNameByID")
    name = byID and byID(id)
    if type(name) == "string" and name ~= "" then return name end
    Request(id)
    return nil
end

-- A name to show: the item's, or a placeholder until it arrives.
function Item.Label(id)
    return Item.Name(id) or L["ITEM_LOADING_FMT"]:format(id or 0)
end

-- How many the player has: bags, or bags and bank.
function Item.Count(id, bank)
    local fn = Api("C_Item", "GetItemCount", "GetItemCount")
    if not (fn and id) then return 0 end
    local ok, n = pcall(fn, id, bank and true or false)
    return ok and type(n) == "number" and n or 0
end

-- What a merchant pays for one.
function Item.SellPrice(id)
    local sell = select(11, Item.Info(id))
    return type(sell) == "number" and sell > 0 and sell or nil
end

function Item.Cooldown(id)
    local fn = Api("C_Container", "GetItemCooldown", "GetItemCooldown") or Api("C_Item", "GetItemCooldown")
    if not fn then return nil end
    return fn(id)
end

function Item.Pending() return pendingCount end

local burst = false
FG.OnEvent("GET_ITEM_INFO_RECEIVED", function(itemID)
    if not (itemID and pending[itemID]) then return end
    pending[itemID], pendingCount = nil, pendingCount - 1
    Item.stats.received = Item.stats.received + 1
    if burst then return end
    burst = true
    FG.After(0.3, function()
        burst = false
        FG.Emit("items:loaded")
    end)
end)

-- A merchant's item i: price for one, units in a stack, units left (-1: no limit), item ID.
function Merchant.Item(i)
    local current = C_MerchantFrame and C_MerchantFrame.GetItemInfo
    local id = GetMerchantItemID and GetMerchantItemID(i)
    if type(current) == "function" then
        local info = current(i)
        if type(info) ~= "table" then return nil end
        return info.price, info.stackCount, info.numAvailable, id
    end
    local legacy = _G["GetMerchantItemInfo"]
    if type(legacy) == "function" then
        local _, _, price, quantity, available = legacy(i)
        return price, quantity, available, id
    end
    return nil
end

function Merchant.Count()
    return GetMerchantNumItems and GetMerchantNumItems() or 0
end
