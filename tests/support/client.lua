-- A fake WoW Forever client for tests. It loads the real addons through their
-- real TOC files, under the real load rules, into one environment, and answers
-- the game API they ask for. World geometry is exact: map-to-world transforms
-- come from the planes the NPC catalog ships. What stands in for the game is
-- only the player, their character sheet and the screen.
local UI = require("support.fakeui")

local Client = {}
Client.__index = Client

local ROOT = os.getenv("FGPS_ROOT") or "."
Client.ROOT = ROOT

local tunpack = table.unpack

-- WoW runs Lua 5.1, where %d and %x truncate a float; 5.4 raises instead.
do
    local format = string.format
    function string.format(fmt, ...)
        local args = { ... }
        local n = 0
        for spec in fmt:gmatch("%%[%-+ #0]*%d*%.?%d*([%a%%])") do
            if spec ~= "%" then
                n = n + 1
                if spec:match("[dixXouc]") and type(args[n]) == "number" then
                    local v = args[n]
                    args[n] = v >= 0 and math.floor(v) or math.ceil(v)
                end
            end
        end
        return format(fmt, tunpack(args, 1, select("#", ...)))
    end
end

-- ==== maps ==================================================================

local CONTINENT_KALIMDOR, CONTINENT_EK = 1414, 1415
local MAPS = {
    [947] = { "Azeroth", 1, nil },
    [CONTINENT_KALIMDOR] = { "Kalimdor", 2, 947 }, [CONTINENT_EK] = { "Eastern Kingdoms", 2, 947 },
    [1411] = { "Durotar", 3, 1414 }, [1412] = { "Mulgore", 3, 1414 }, [1413] = { "The Barrens", 3, 1414 },
    [1416] = { "Alterac Mountains", 3, 1415 }, [1417] = { "Arathi Highlands", 3, 1415 }, [1418] = { "Badlands", 3, 1415 },
    [1419] = { "Blasted Lands", 3, 1415 }, [1420] = { "Tirisfal Glades", 3, 1415 }, [1421] = { "Silverpine Forest", 3, 1415 },
    [1422] = { "Western Plaguelands", 3, 1415 }, [1423] = { "Eastern Plaguelands", 3, 1415 }, [1424] = { "Hillsbrad Foothills", 3, 1415 },
    [1425] = { "The Hinterlands", 3, 1415 }, [1426] = { "Dun Morogh", 3, 1415 }, [1427] = { "Searing Gorge", 3, 1415 },
    [1428] = { "Burning Steppes", 3, 1415 }, [1429] = { "Elwynn Forest", 3, 1415 }, [1430] = { "Deadwind Pass", 3, 1415 },
    [1431] = { "Duskwood", 3, 1415 }, [1432] = { "Loch Modan", 3, 1415 }, [1433] = { "Redridge Mountains", 3, 1415 },
    [1434] = { "Stranglethorn Vale", 3, 1415 }, [1435] = { "Swamp of Sorrows", 3, 1415 }, [1436] = { "Westfall", 3, 1415 },
    [1437] = { "Wetlands", 3, 1415 }, [1438] = { "Teldrassil", 3, 1414 }, [1439] = { "Darkshore", 3, 1414 },
    [1440] = { "Ashenvale", 3, 1414 }, [1441] = { "Thousand Needles", 3, 1414 }, [1442] = { "Stonetalon Mountains", 3, 1414 },
    [1443] = { "Desolace", 3, 1414 }, [1444] = { "Feralas", 3, 1414 }, [1445] = { "Dustwallow Marsh", 3, 1414 },
    [1446] = { "Tanaris", 3, 1414 }, [1447] = { "Azshara", 3, 1414 }, [1448] = { "Felwood", 3, 1414 },
    [1449] = { "Un'Goro Crater", 3, 1414 }, [1450] = { "Moonglade", 3, 1414 }, [1451] = { "Silithus", 3, 1414 },
    [1452] = { "Winterspring", 3, 1414 }, [1453] = { "Stormwind City", 3, 1429 }, [1454] = { "Orgrimmar", 3, 1411 },
    [1455] = { "Ironforge", 3, 1426 }, [1456] = { "Thunder Bluff", 3, 1412 }, [1457] = { "Darnassus", 3, 1438 },
    [1458] = { "Undercity", 3, 1420 }, [2482] = { "Mount Hyjal", 3, 1414 }, [2548] = { "Riverglades", 3, 1415 },
}
local AREAS = {
    [442] = "Auberdine", [17203] = "Stormwind Harbor", [150] = "Menethil Harbor", [271] = "Southshore", [702] = "Rut'theran Village",
    [1519] = "Stormwind City", [1537] = "Ironforge", [12] = "Elwynn Forest", [40] = "Westfall", [24] = "Northshire Abbey",
    [34] = "Lion's Pride Inn", [87] = "Goldshire", [2257] = "Deeprun Tram", [148] = "Darkshore",
}

local function vec(x, y)
    return { x = x, y = y, GetXY = function(self) return self.x, self.y end }
end

-- ==== the environment =======================================================

local function clone(t)
    if type(t) ~= "table" then return t end
    local o = {}
    for k, v in pairs(t) do o[clone(k)] = clone(v) end
    return o
end
Client.Clone = clone

function Client.new(opts)
    opts = opts or {}
    local self = setmetatable({}, Client)
    local screen = opts.screen or { 1920, 1080, 1 }
    self.frames, self.named = {}, {}
    UI.frames, UI.named, UI.unknown, UI.focus, UI.epoch, UI.conflicts = self.frames, self.named, {}, nil, 0, {}
    self.UI = UI
    self.root = UI.NewScreen(screen[1], screen[2], screen[3])
    self.now = opts.now or 1000
    self.timers = {}
    self.player = {
        mapID = opts.mapID or 1453, x = opts.x or 0.5, y = opts.y or 0.5,
        name = opts.name or "Tester", level = opts.level or 30, faction = opts.faction or "Alliance", class = opts.class or "WARRIOR", race = opts.race or "Human",
        bind = opts.bind or "Lion's Pride Inn", ghost = false, taxi = false, indoors = false, facing = 0, speed = 0, combat = opts.combat or false,
    }
    self.addons, self.bags = {}, opts.bags or {}
    self.quests = opts.quests or {}
    self.printed = {}
    self.errors = {}
    self.waypoint = nil
    self.superTrack = { waypoint = false }
    self.completed = opts.completed or {}
    self.bank, self.items = opts.bank or {}, opts.items or {}
    self.professions, self.recipes = opts.professions or {}, opts.recipes or {}
    self.auctions, self.merchant = opts.auctions or {}, opts.merchant or {}
    self.taint = Client.NewTaint(self)
    self.known = opts.knownFlights
    self.env = self:BuildEnv(opts)
    return self
end

local function InstallStrings(env)
    env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    env.tinsert, env.tremove, env.sort, env.tconcat = table.insert, table.remove, table.sort, table.concat
    env.unpack, env.select = tunpack, select
    env.loadstring = load
    env.strlower, env.strupper, env.strfind, env.strsub, env.strlen, env.strmatch, env.strrep, env.strbyte, env.strchar, env.strrev, env.gsub, env.format =
        string.lower, string.upper, string.find, string.sub, string.len, string.match, string.rep, string.byte, string.char, string.reverse, string.gsub, string.format
    env.gmatch = string.gmatch
    env.floor, env.ceil, env.abs, env.min, env.max, env.sqrt, env.random, env.mod, env.deg, env.rad =
        math.floor, math.ceil, math.abs, math.min, math.max, math.sqrt, math.random, math.fmod, math.deg, math.rad
    env.date, env.time = os.date, os.time
    env.strtrim = function(s) return (s or ""):gsub("^%s+", ""):gsub("%s+$", "") end
    env.strsplit = function(sep, s, limit)
        local out, pos = {}, 1
        s = s or ""
        while true do
            if limit and #out + 1 >= limit then break end
            local a, b = s:find(sep, pos, true)
            if not a then break end
            out[#out + 1] = s:sub(pos, a - 1)
            pos = b + 1
        end
        out[#out + 1] = s:sub(pos)
        return tunpack(out)
    end
    env.strjoin = function(sep, ...) return table.concat({ ... }, sep) end
    env.tostringall = function(...) return ... end
    env.tContains = function(t, v)
        for i = 1, #t do if t[i] == v then return true end end
        return false
    end
    env.CopyTable = clone
    env.Lerp = function(a, b, t) return a + (b - a) * t end
    env.Clamp = function(v, a, b) return math.min(math.max(v, a), b) end
    env.CreateFromMixins = function(...)
        local o = {}
        for _, m in ipairs({ ... }) do for k, v in pairs(m) do o[k] = v end end
        return o
    end
    env.Mixin = function(o, ...)
        for _, m in ipairs({ ... }) do for k, v in pairs(m) do o[k] = v end end
        return o
    end
    env.bit = {
        band = function(a, b) return a & b end, bor = function(a, b) return a | b end, bxor = function(a, b) return a ~ b end,
        bnot = function(a) return ~a end, lshift = function(a, n) return a << n end, rshift = function(a, n) return a >> n end,
    }
end

function Client:BuildEnv(opts)
    local client = self
    local env = setmetatable({}, { __index = _G })
    env._G = env
    InstallStrings(env)
    env.print = function(...)
        local parts = { ... }
        for i = 1, #parts do parts[i] = tostring(parts[i]) end
        client.printed[#client.printed + 1] = table.concat(parts, " ")
    end
    local function onError(err)
        client.errors[#client.errors + 1] = tostring(err)
        return err
    end
    env.geterrorhandler = function() return onError end
    env.seterrorhandler = function() end
    env.CallErrorHandler = onError
    env.debugstack = function() return "" end
    -- cpuStep: each look at the clock costs that many milliseconds, whatever the machine,
    -- so a test can stand in for a fast or a slow one and run the same way every time.
    env.debugprofilestop = function()
        if client.cpuStep then
            client.cpuClock = (client.cpuClock or 0) + client.cpuStep
            return client.cpuClock
        end
        return os.clock() * 1000
    end
    -- Time here is simulated and a plan's slices are real, so a test's deadline buys less
    -- on a slower machine. The largest budget keeps those deadlines far from the work.
    env.GetFramerate = function() return client.fps or 15 end
    env.UpdateAddOnMemoryUsage = function() end
    -- As strict as the metadata: only what is loaded has a figure.
    env.GetAddOnMemoryUsage = function(n)
        if not client.addons[n] then error("Invalid AddOn name " .. tostring(n), 2) end
        return 30000
    end
    env.GetTime = function() return client.now end
    env.GetServerTime = function() return math.floor(client.now) end
    env.time = function(t) return t and os.time(t) or math.floor(client.now) end
    env.GetBuildInfo = function() return "1.60.1", "70790", "Nov 4 2026", 16001 end
    env.GetLocale = function() return "enUS" end
    env.GetRealmName = function() return "Testrealm" end
    env.GetNormalizedRealmName = function() return "Testrealm" end
    env.WOW_PROJECT_ID, env.WOW_PROJECT_CAMELOT, env.WOW_PROJECT_MAINLINE = 16, 16, 1
    env.WOW_PROJECT_CLASSIC, env.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 2, 5
    env.LE_EXPANSION_LEVEL_CURRENT = 0
    env.GetExpansionLevel = function() return 0 end
    env.IsLoggedIn = function() return client.loggedIn == true end
    env.InCombatLockdown = function() return client.player.combat end
    env.UnitAffectingCombat = function() return client.player.combat end
    env.IsShiftKeyDown, env.IsControlKeyDown, env.IsAltKeyDown = function() return false end, function() return false end, function() return false end
    env.IsModifiedClick = function() return false end
    env.GetCursorPosition = function() return 0, 0 end
    env.GetMouseFoci = function() return {} end
    env.GetCurrentKeyBoardFocus = function() return UI.focus end
    env.GetBindingKey = function() return nil end
    env.GetBindingText = function(k) return k end
    env.GetBindingFromClick = function() return nil end
    env.SetBinding = function() return true end
    env.SaveBindings = function() end
    env.GetCurrentBindingSet = function() return 1 end
    env.hooksecurefunc = function(a, b, c)
        local t, name, fn = a, b, c
        if type(a) == "string" then t, name, fn = env, a, b end
        local prev = rawget(t, name) or t[name]
        rawset(t, name, function(...)
            local r = table.pack(prev(...))
            fn(...)
            return tunpack(r, 1, r.n)
        end)
    end
    env.securecall = function(fn, ...) if type(fn) == "string" then fn = env[fn] end return fn(...) end
    env.secureexecuterange = function() end
    env.issecurevariable = function() return true end
    env.issecretvalue = nil
    env.PlaySound = function() end
    env.PlaySoundFile = function() end
    env.StopSound = function() end
    env.SOUNDKIT = setmetatable({}, { __index = function() return 1 end })
    env.UISpecialFrames = {}
    env.UIParent = self.root
    local function fontObject(size)
        local f = { _size = size }
        function f:SetFont(_, s) self._size = s return true end
        function f:GetFont() return "Fonts/FRIZQT__.TTF", self._size, "" end
        function f:GetName() return "FakeFont" end
        function f:GetTextColor() return 1, 1, 1, 1 end
        function f:GetShadowColor() return 0, 0, 0, 1 end
        function f:GetShadowOffset() return 1, -1 end
        for _, m in ipairs({ "SetFontObject", "SetTextColor", "SetShadowColor", "SetShadowOffset", "SetJustifyH", "SetJustifyV", "CopyFontObject", "SetSpacing" }) do
            f[m] = function() end
        end
        return f
    end
    for name, size in pairs({ GameFontNormal = 12, GameFontNormalSmall = 10, GameFontHighlight = 12, GameFontHighlightSmall = 10,
        GameFontHighlightLarge = 16, GameFontDisable = 12, ChatFontNormal = 12, GameFontNormalLarge = 16, GameFontNormalHuge = 20,
        NumberFontNormal = 12, GameTooltipText = 12, GameTooltipHeaderText = 14, GameFontWhite = 12, GameFontNormalMed3 = 14,
        SystemFont_Shadow_Med1 = 12, SystemFont_Med1 = 12, GameFontHighlightMedium = 14, GameFontNormalMed2 = 14 }) do
        env[name] = fontObject(size)
    end
    env.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    env.UNIT_NAME_FONT, env.DAMAGE_TEXT_FONT, env.NAMEPLATE_FONT = "Fonts\\FRIZQT__.TTF", "Fonts\\FRIZQT__.TTF", "Fonts\\FRIZQT__.TTF"
    env.RED_FONT_COLOR = { r = 1, g = 0.13, b = 0.13 }
    env.NORMAL_FONT_COLOR = { r = 1, g = 0.82, b = 0 }
    env.HIGHLIGHT_FONT_COLOR = { r = 1, g = 1, b = 1 }
    env.GRAY_FONT_COLOR = { r = 0.5, g = 0.5, b = 0.5 }
    env.CreateFont = function(name)
        local f = fontObject(12)
        if name then env[name] = f end
        return f
    end
    env.CreateFrame = function(kind, name, parent, template)
        UI.frames, UI.named = client.frames, client.named
        local f = UI.CreateFrame(kind, name, parent)
        if name then env[name] = f end
        f._template = template
        return f
    end
    env.CreateFramePool = function() return setmetatable({}, { __index = function() return function() end end }) end
    env.CreateObjectPool = env.CreateFramePool
    env.CreateTexturePool = env.CreateFramePool
    env.CreateFontStringPool = env.CreateFramePool
    env.CreateVector2D = vec
    env.CreateColor = function(r, g, b, a)
        return { r = r, g = g, b = b, a = a, GetRGB = function() return r, g, b end, GetRGBA = function() return r, g, b, a end,
                 WrapTextInColorCode = function(_, t) return t end }
    end
    env.WrapTextInColorCode = function(t) return t end
    env.GameTooltip = setmetatable({}, { __index = function() return function() end end })
    env.GameTooltip_Hide = function() end
    env.ItemRefTooltip = env.GameTooltip
    env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, t) client.printed[#client.printed + 1] = t end }
    env.SlashCmdList = {}
    env.hash_SlashCmdList = {}
    env.UIErrorsFrame = { AddMessage = function() end }
    env.StaticPopupDialogs = {}
    env.StaticPopup_Show = function() end
    env.StaticPopup_Hide = function() end
    env.Settings = { RegisterCanvasLayoutCategory = function() return { GetID = function() return 1 end } end,
                     RegisterAddOnCategory = function() end, OpenToCategory = function() end }
    env.Enum = setmetatable({
        UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4, Micro = 5, Orphan = 6 },
        QuestWatchType = { Automatic = 0, Manual = 1 },
        GameRule = {},
    }, { __index = function() return {} end })

    -- The player
    env.UnitLevel = function() return client.player.level end
    env.UnitFactionGroup = function() return client.player.faction, client.player.faction end
    env.UnitClass = function() return "Warrior", client.player.class end
    env.UnitRace = function() return "Human", client.player.race end
    env.UnitName = function() return client.player.name, nil end
    env.UnitExists = function() return true end
    env.UnitIsGhost = function() return client.player.ghost end
    env.UnitIsDead = function() return false end
    env.UnitIsDeadOrGhost = function() return client.player.ghost end
    env.UnitOnTaxi = function() return client.player.taxi end
    env.UnitInVehicle = function() return false end
    env.UnitPosition = function() return nil end
    env.UnitBuff = function() return nil end
    env.UnitAura = function() return nil end
    env.IsMounted = function() return false end
    env.IsFlying = function() return false end
    env.IsSwimming = function() return false end
    env.IsIndoors = function() return client.player.indoors end
    env.IsOutdoors = function() return not client.player.indoors end
    env.IsInInstance = function() return false, "none" end
    env.IsPlayerMoving = function() return client.player.speed > 0 end
    env.GetUnitSpeed = function() return client.player.speed, 7, 7, 4.5 end
    env.GetPlayerFacing = function() return client.player.facing end
    env.GetBindLocation = function() return client.player.bind end
    env.GetSubZoneText = function() return "" end
    env.GetZoneText = function() return "" end
    env.GetRealZoneText = function() return "" end
    env.GetMinimapZoneText = function() return "" end
    env.GetNumSkillLines = function() return 0 end
    env.GetSkillLineInfo = function() return nil end
    env.IsPlayerSpell = function() return false end
    env.IsSpellKnown = function() return false end
    env.IsSpellKnownOrOverridesKnown = function() return false end
    env.GetSpellInfo = function() return nil end
    env.GetSpellCooldown = function() return 0, 0, 0 end
    -- Items, as WoW Forever 1.60.1 has them: through C_Item and C_Container only. The old
    -- globals GetItemInfo, GetItemCount, GetItemCooldown and GetMerchantItemInfo do not exist
    -- there (2.4 failed in the game on exactly that), so they do not exist here.
    -- client.uncached = { [itemID] = true }: not cached until asked for, then sent after
    -- client.itemDelay (0.2 s) with GET_ITEM_INFO_RECEIVED; client.itemNever: never sent.
    local function ItemCount(id, bank) return (client.bags[id] or 0) + (bank and client.bank[id] or 0) end
    local function ItemInfo(id)
        local item = client.items[id]
        if not item or (client.uncached and client.uncached[id]) then return nil end
        return item.name, nil, 1, 1, 1, "Trade Goods", "Parts", 20, "", 0, item.sell or 0
    end
    local function RequestLoad(id)
        client.itemRequests = (client.itemRequests or 0) + 1
        if not (client.uncached and client.uncached[id]) or (client.itemNever and client.itemNever[id]) then return end
        client:After(client.itemDelay or 0.2, function()
            client.uncached[id] = nil
            client:Fire("GET_ITEM_INFO_RECEIVED", id, true)
        end)
    end

    -- Professions, as GetProfessions and the profession window give them. client.professions:
    -- { { name, skill, max, line } }, client.recipes: { [id] = { name, line, learned, diff,
    -- out, qmin, qmax, reagents = { { id, n } } } }.
    env.GetProfessions = function()
        local p = client.professions
        return p[1] and 1 or nil, p[2] and 2 or nil, nil, nil, p[3] and 3 or nil
    end
    env.GetProfessionInfo = function(i)
        local p = client.professions[i]
        if not p then return nil end
        return p.name, 0, p.skill, p.max, 0, 0, p.line
    end
    -- The window's data may arrive late, as a real client's can: client.recipesAt (no
    -- recipes before that time) and client.schematicsAt (no reagents before it).
    -- client.noListUpdate: TRADE_SKILL_LIST_UPDATE never fires.
    env.C_TradeSkillUI = {
        GetBaseProfessionInfo = function()
            local p = client.openProfession
            return p and { professionID = p.line, skillLevel = p.skill, maxSkillLevel = p.max } or nil
        end,
        GetAllRecipeIDs = function()
            local out = {}
            if client.recipesAt and client.now < client.recipesAt then return out end
            for id, r in pairs(client.recipes) do
                if client.openProfession and r.line == client.openProfession.line then out[#out + 1] = id end
            end
            table.sort(out)
            return out
        end,
        GetRecipeInfo = function(id)
            local r = client.recipes[id]
            if not r then return nil end
            local diff = r.diff
            if r.at then
                local s = client.openProfession.skill
                diff = s >= r.at.x and 3 or s >= r.at.g and 2 or s >= r.at.y and 1 or 0
            end
            return { recipeID = id, name = r.name, learned = r.learned ~= false, relativeDifficulty = diff, icon = 0 }
        end,
        GetRecipeSchematic = function(id)
            local r = client.recipes[id]
            if not r then return nil end
            if client.schematicsAt and client.now < client.schematicsAt then
                return { recipeID = id, outputItemID = nil, quantityMin = 1, quantityMax = 1, reagentSlotSchematics = {} }
            end
            local slots = {}
            for i, g in ipairs(r.reagents or {}) do
                slots[i] = { reagentType = 1, quantityRequired = g.n, reagents = { { itemID = g.id } } }
            end
            return { recipeID = id, outputItemID = r.out, quantityMin = r.qmin or 1, quantityMax = r.qmax or r.qmin or 1,
                     reagentSlotSchematics = slots }
        end,
    }
    -- The auction house's full scan: client.auctions { { itemID, count, buyout } }.
    env.C_AuctionHouse = {
        -- replicateSpread: the answer arrives over that many seconds, an event each 0.1 s
        -- and the rows growing with them, as the real client does (hundreds of events).
        -- replicateSilent: no answer at all.
        ReplicateItems = function()
            client.replicated = (client.replicated or 0) + 1
            if client.replicateSilent then return end
            local spread = client.replicateSpread
            if not spread then
                client.replicateVisible = nil
                client:After(0.5, function() client:Fire("REPLICATE_ITEM_LIST_UPDATE") end)
                return
            end
            client.replicateVisible = 0
            local steps = math.max(1, math.floor(spread / 0.1))
            for k = 1, steps do
                client:After(0.5 + k * 0.1, function()
                    client.replicateVisible = math.floor(#client.auctions * k / steps)
                    client:Fire("REPLICATE_ITEM_LIST_UPDATE")
                end)
            end
        end,
        GetNumReplicateItems = function() return client.replicateVisible or #client.auctions end,
        GetReplicateItemInfo = function(i)
            local a = client.auctions[i + 1]
            if not a then return nil end
            return "Item", 0, a.count, 1, true, 1, 0, 0, 0, a.buyout, 0, false, nil, "Seller", nil, 0, a.itemID, true
        end,
        -- Targeted searches: answered from client.auctions after client.searchDelay (0.2 s),
        -- twice when client.searchTwice; never when client.searchSilent. client.throttled
        -- counts searches the throttle refuses before letting one through.
        MakeItemKey = function(id) return { itemID = id, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 } end,
        IsThrottledMessageSystemReady = function()
            if (client.throttled or 0) > 0 then
                client.throttled = client.throttled - 1
                return false
            end
            return true
        end,
        SendSearchQuery = function(key)
            client.searches = client.searches or {}
            client.searches[#client.searches + 1] = key.itemID
            if client.searchSilent then return end
            local id = key.itemID
            local gear = client.gear and client.gear[id]
            local function answer()
                if gear then client:Fire("ITEM_SEARCH_RESULTS_UPDATED", key) else client:Fire("COMMODITY_SEARCH_RESULTS_UPDATED", id) end
            end
            client:After(client.searchDelay or 0.2, answer)
            if client.searchTwice then client:After((client.searchDelay or 0.2) + 0.2, answer) end
        end,
        GetNumCommoditySearchResults = function(id)
            local n = 0
            for _, a in ipairs(client.auctions) do if a.itemID == id then n = n + 1 end end
            return n
        end,
        GetCommoditySearchResultInfo = function(id, i)
            local rows = {}
            for _, a in ipairs(client.auctions) do if a.itemID == id then rows[#rows + 1] = a end end
            table.sort(rows, function(x, y) return x.buyout / x.count < y.buyout / y.count end)
            local a = rows[i]
            return a and { itemID = id, quantity = a.count, unitPrice = math.floor(a.buyout / a.count) } or nil
        end,
        GetNumItemSearchResults = function(key)
            local n = 0
            for _, a in ipairs(client.auctions) do if a.itemID == key.itemID then n = n + 1 end end
            return n
        end,
        GetItemSearchResultInfo = function(key, i)
            local rows = {}
            for _, a in ipairs(client.auctions) do if a.itemID == key.itemID then rows[#rows + 1] = a end end
            table.sort(rows, function(x, y) return x.buyout < y.buyout end)
            local a = rows[i]
            return a and { itemKey = key, quantity = a.count, buyoutAmount = a.buyout } or nil
        end,
    }
    env.GetMerchantNumItems = function() return #client.merchant end
    -- The current shape: a table. Unlimited stock reads -1, as the game shows no count.
    env.C_MerchantFrame = { GetItemInfo = function(i)
        local m = client.merchant[i]
        if not m then return nil end
        return { name = "Item", texture = 0, price = m.price, stackCount = m.quantity or 1, numAvailable = m.available or -1,
                 isPurchasable = true, isUsable = true, hasExtendedCost = false }
    end }
    env.GetMerchantItemID = function(i) return client.merchant[i] and client.merchant[i].id end
    -- A trainer's window: client.trainer = { npcID, name, services = { { name, rank, category,
    -- skill, skillRank, level, cost } } }.
    env.UnitGUID = function(unit)
        if unit == "npc" and client.trainer then return ("Creature-0-1-1-1-%d-0000000001"):format(client.trainer.npcID) end
        return "Player-1-00000001"
    end
    env.UnitName = env.UnitName or function() return "Name" end
    env.GetNumTrainerServices = function() return client.trainer and #client.trainer.services or 0 end
    -- Two shapes, as the game has had: "classic" (name, rank, type) lists every rank;
    -- "current" (name, type, icon, level) shows the next rank as its own step service,
    -- with the player's skill and cap in that profession beside it.
    env.GetTrainerServiceInfo = function(i)
        local s = client.trainer.services[i]
        if client.trainer.shape == "current" then return s.name, s.category or "available", 136243, s.level or 1 end
        return s.name, s.rank, s.category or "available"
    end
    env.GetTrainerServiceSkillReq = function(i)
        local s = client.trainer.services[i]
        return s.skill, s.skillRank, true
    end
    env.IsTradeskillTrainer = function() return not (client.trainer and client.trainer.class) end
    env.GetTrainerServiceSkillLine = function(i)
        local s = client.trainer.services[i]
        return s.line or client.trainer.line
    end
    env.GetTrainerServiceStepIndex = function()
        return client.trainer and client.trainer.shape == "current" and client.trainer.step or nil
    end
    env.GetTrainerTradeskillRankValues = function()
        local v = client.trainer and client.trainer.rankValues
        if not v then return 0, 0, 0 end
        return v[1], v[2], 0
    end
    env.GetTrainerServiceLevelReq = function(i) return client.trainer.services[i].level end
    env.GetTrainerServiceCost = function(i) return client.trainer.services[i].cost end
    env.PlayerHasToy = function() return false end
    env.IsUsableItem = function() return true end
    env.C_Item = { GetItemCount = ItemCount, GetItemCooldown = function() return 0, 0, 0 end, GetItemInfo = ItemInfo,
                   RequestLoadItemDataByID = RequestLoad, GetItemNameByID = function(id) return (ItemInfo(id)) end, GetItemIconByID = function() return nil end, IsUsableItem = function() return true end,
                   GetItemSubClassInfo = function() return "Subclass" end, GetItemClassInfo = function() return "Class" end }
    env.GetItemSubClassInfo, env.GetItemClassInfo = env.C_Item.GetItemSubClassInfo, env.C_Item.GetItemClassInfo
    env.C_Spell = { GetSpellInfo = function() return nil end, GetSpellCooldown = function() return { startTime = 0, duration = 0 } end,
                    IsSpellUsable = function() return true end, GetSpellName = function() return nil end, GetSpellTexture = function() return nil end }
    env.C_ToyBox = { IsToyUsable = function() return false end }
    env.C_MountJournal = { GetMountIDs = function() return {} end, GetMountInfoByID = function() return nil end, GetNumMounts = function() return 0 end }
    env.C_UnitAuras = { GetPlayerAuraBySpellID = function() return nil end, GetAuraDataByIndex = function() return nil end }
    env.C_DeathInfo = { GetCorpseMapPosition = function() return client.player.corpse and vec(client.player.corpse.x, client.player.corpse.y) or nil end }
    env.C_PvP = { IsWarModeDesired = function() return false end, GetZonePVPInfo = function() return "contested" end }
    env.GetZonePVPInfo = function() return "contested" end
    env.C_GameRules = { IsGameRuleActive = function() return false end }
    env.C_Reputation = { GetNumFactions = function() return 0 end, GetFactionDataByIndex = function() return nil end }
    env.C_CurrencyInfo = { GetCurrencyInfo = function() return nil end, GetCurrencyListSize = function() return 0 end }
    env.C_Texture = { GetAtlasInfo = function() return nil end }
    env.C_XMLUtil = { GetTemplateInfo = function() return nil end }
    env.C_EncounterJournal = { GetDungeonEntranceMapInfo = function() return nil end }
    env.C_CVar = { GetCVar = function() return nil end, SetCVar = function() end, GetCVarBool = function() return false end, RegisterCVar = function() end }
    env.GetCVar, env.SetCVar, env.GetCVarBool = function() return nil end, function() end, function() return false end
    env.C_Timer = {
        After = function(delay, fn) client:After(delay, fn) end,
        NewTimer = function(delay, fn)
            local t = { Cancel = function(s) s.cancelled = true end, IsCancelled = function(s) return s.cancelled end }
            client:After(delay, function() if not t.cancelled then fn(t) end end)
            return t
        end,
        NewTicker = function(delay, fn)
            local t = { Cancel = function(s) s.cancelled = true end, IsCancelled = function(s) return s.cancelled end }
            local function again()
                if t.cancelled then return end
                fn(t)
                client:After(delay, again)
            end
            client:After(delay, again)
            return t
        end,
    }
    env.C_AddOns = {
        IsAddOnLoaded = function(n) return client.addons[n] == true end,
        IsAddOnLoadable = function(n) return client.addons[n] == true end,
        LoadAddOn = function(n) return client.addons[n] == true end,
        -- Strict on purpose: the real client need not answer for an addon it does not have.
        GetAddOnMetadata = function(n, key)
            if not (client.addons[n] or (client.meta and client.meta[n])) then error("Invalid AddOn name " .. tostring(n), 2) end
            return client.meta and client.meta[n] and client.meta[n][key]
        end,
        GetAddOnInfo = function(n) return n, n, "", client.addons[n] == true, client.addons[n] and "" or "MISSING" end,
        EnableAddOn = function() end, DisableAddOn = function() end, GetNumAddOns = function() return 0 end,
        DoesAddOnExist = function(n) return client.addons[n] == true end,
        GetAddOnEnableState = function(n) return client.addons[n] and 2 or 0 end,
    }
    env.GetAddOnMetadata = env.C_AddOns.GetAddOnMetadata
    env.IsAddOnLoaded = env.C_AddOns.IsAddOnLoaded

    -- Maps
    local function plane(m) return client.planes and client.planes[m] end
    local function mapPos(m, wx, wy)
        local p = plane(m)
        if not p then return nil end
        return (wy - p[4]) / p[5], (wx - p[2]) / p[3]
    end
    env.C_Map = {
        GetMapInfo = function(m)
            local i = MAPS[m]
            if not i then return nil end
            return { mapID = m, name = i[1], mapType = i[2], parentMapID = i[3] or 0 }
        end,
        GetMapChildrenInfo = function(m)
            local out = {}
            for id, i in pairs(MAPS) do
                if i[3] == m then out[#out + 1] = { mapID = id, name = i[1], mapType = i[2], parentMapID = m } end
            end
            return out
        end,
        GetBestMapForUnit = function() return client.player.mapID end,
        GetPlayerMapPosition = function(m)
            if m ~= client.player.mapID then return nil end
            return vec(client.player.x, client.player.y)
        end,
        GetWorldPosFromMapPos = function(m, v)
            local p = plane(m)
            if not p then return nil end
            return p[1], vec(p[2] + p[3] * v.y, p[4] + p[5] * v.x)
        end,
        GetMapPosFromWorldPos = function(ci, v, m)
            local x, y = mapPos(m, v.x, v.y)
            if not x then return nil end
            return m, vec(x, y)
        end,
        GetAreaInfo = function(a) return AREAS[a] end,
        GetMapLevels = function() return 1, 60 end,
        GetMapGroupID = function() return nil end,
        GetMapGroupMembersInfo = function() return nil end,
        GetMapRectOnMap = function() return nil end,
        GetMapArtID = function() return 1 end,
        GetMapArtLayers = function() return {} end,
        CanSetUserWaypointOnMap = function() return true end,
        GetUserWaypoint = function() return client.waypoint end,
        SetUserWaypoint = function(p)
            client.waypoint = p
            client.taint:Waypoint("SetUserWaypoint")
        end,
        ClearUserWaypoint = function()
            if client.waypoint == nil then return end
            client.waypoint = nil
            client.taint:Waypoint("ClearUserWaypoint")
            if client.superTrack.waypoint then
                client.superTrack.waypoint = false
                client.taint:SuperTrack("ClearUserWaypoint")
            end
        end,
        HasUserWaypoint = function() return client.waypoint ~= nil end,
        GetUserWaypointHyperlink = function() return nil end,
        GetUserWaypointPositionForMap = function() return nil end,
        GetMapBannersForMap = function() return {} end,
        GetAreaPOIForMap = function() return {} end,
        GetBountySetIDForMap = function() return nil end,
    }
    env.UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { uiMapID = m, position = vec(x, y) } end }
    env.C_AreaPoiInfo = { GetAreaPOIForMap = function() return {} end, GetAreaPOIInfo = function() return nil end }
    env.C_TaxiMap = { GetAllTaxiNodes = function() return {} end, GetTaxiNodesForMap = function() return {} end, ShouldMapShowTaxiNodes = function() return true end }
    -- One slot of state and a change to it fires SUPER_TRACKING_CHANGED inside the call,
    -- which is the path the taint error took: see Taint in this file.
    local track = client.superTrack
    env.C_SuperTrack = {
        SetSuperTrackedUserWaypoint = function(on)
            on = on and true or false
            client.taint:Called("SetSuperTrackedUserWaypoint")
            if track.waypoint ~= on then
                track.waypoint = on
                client.taint:SuperTrack("SetSuperTrackedUserWaypoint")
            end
        end,
        IsSuperTrackingUserWaypoint = function() return track.waypoint end,
        ClearAllSuperTracked = function()
            client.taint:Called("ClearAllSuperTracked")
            track.waypoint, track.quest = false, nil
            client.taint:SuperTrack("ClearAllSuperTracked")
        end,
        GetSuperTrackedQuestID = function() return track.quest end,
        IsSuperTrackingQuest = function() return track.quest ~= nil end,
        SetSuperTrackedQuestID = function(id)
            client.taint:Called("SetSuperTrackedQuestID")
            track.quest = id ~= 0 and id or nil
            if track.quest then track.waypoint = false end
            client.taint:SuperTrack("SetSuperTrackedQuestID")
        end,
        GetSuperTrackedVignette = function() return track.vignette end,
        SetSuperTrackedVignette = function(guid)
            client.taint:Called("SetSuperTrackedVignette")
            track.vignette = guid
            client.taint:SuperTrack("SetSuperTrackedVignette")
        end,
        ClearAllSuperTrackedVignettes = function()
            client.taint:Called("ClearAllSuperTrackedVignettes")
            track.vignette = nil
            client.taint:SuperTrack("ClearAllSuperTrackedVignettes")
        end,
        IsSuperTrackingAnything = function() return track.waypoint or track.quest ~= nil end,
        GetSuperTrackedContent = function() return nil end,
    }
    env.C_Navigation = { GetDistance = function() return 0 end, GetFrame = function() return nil end, GetTargetState = function() return 0 end }

    -- Quest log
    local QL = {}
    local function questEntry(id)
        for _, q in ipairs(client.quests) do
            if q.questID == id then return q end
        end
    end
    function QL.GetNumQuestLogEntries()
        local n = 0
        for _, q in ipairs(client.quests) do n = n + 1 + (q.header and 1 or 0) end
        return n, #client.quests
    end
    function QL.GetInfo(index)
        local i = 0
        for _, q in ipairs(client.quests) do
            if q.header then
                i = i + 1
                if i == index then return { title = q.header, isHeader = true, questID = 0 } end
            end
            i = i + 1
            if i == index then
                return { title = q.title, questID = q.questID, level = q.level, isHeader = false, isHidden = q.hidden or false,
                         suggestedGroup = 0, frequency = 0 }
            end
        end
    end
    function QL.GetQuestIDForLogIndex(index)
        local info = QL.GetInfo(index)
        return info and info.questID
    end
    function QL.GetLogIndexForQuestID(id)
        for i = 1, QL.GetNumQuestLogEntries() do
            local info = QL.GetInfo(i)
            if info and info.questID == id then return i end
        end
    end
    function QL.GetTitleForQuestID(id) local q = questEntry(id) return q and q.title end
    function QL.IsOnQuest(id) return questEntry(id) ~= nil end
    function QL.IsComplete(id) local q = questEntry(id) return q ~= nil and q.complete == true end
    function QL.IsFailed(id) local q = questEntry(id) return q ~= nil and q.failed == true end
    function QL.GetQuestObjectives(id) local q = questEntry(id) return q and q.objectives or {} end
    function QL.IsQuestFlaggedCompleted(id) return client.completed[id] == true end
    function QL.GetQuestsOnMap(m)
        local out = {}
        for _, q in ipairs(client.quests) do
            if q.poi and q.poi.mapID == m then out[#out + 1] = { questID = q.questID, x = q.poi.x, y = q.poi.y } end
        end
        return out
    end
    function QL.GetNextWaypoint(id)
        local q = questEntry(id)
        if q and q.waypoint then return q.waypoint.mapID, q.waypoint.x, q.waypoint.y end
    end
    function QL.GetQuestWatchType() return nil end
    function QL.AddQuestWatch() end
    function QL.RemoveQuestWatch() end
    function QL.SetSelectedQuest() end
    function QL.GetSelectedQuest() return 0 end
    env.C_QuestLog = QL
    env.GetQuestUiMapID = function(id)
        local q = questEntry(id)
        return q and q.poi and q.poi.mapID or 0
    end
    env.QuestMapFrame_OpenToQuestDetails = function(id) client.openedQuest = id end
    env.ToggleQuestLog = function() end
    env.Menu = { ModifyMenu = function() end }
    -- The client unpacks the walking grid and catalog itself; upstream's test
    -- inflater stands in.
    package.path = ROOT .. "/addons/EasyFind_GPS/tests/?.lua;" .. package.path
    local Inflate = require("Inflate")
    env.C_EncodingUtil = { DecodeBase64 = Inflate.DecodeBase64, DecompressString = function(z) return Inflate.Raw(z) end }
    for _, name in ipairs({ "ClearOverrideBindings", "SetOverrideBinding", "SetOverrideBindingClick", "SetOverrideBindingMacro",
        "ChatFrame_AddMessageEventFilter", "ChatFrame_RemoveMessageEventFilter", "ShowUIPanel",
        "HideUIPanel", "CloseDropDownMenus", "RegisterAddonMessagePrefix", "SetCursor", "ResetCursor", "UIFrameFadeIn", "UIFrameFadeOut",
        "Minimap_SetPing", "SetPortraitTexture", "SetPortraitTextureFromCreatureDisplayID", "UnitPopup_ShowMenu", "EventRegistry" }) do
        env[name] = function() end
    end
    env.EventRegistry = { RegisterCallback = function() end, TriggerEvent = function() end, RegisterFrameEventAndCallback = function() end }
    -- Everything running here is addon code, so a call from it stands for one the addon
    -- makes. The player's own hand on the map comes through Client:PlayerToggleMap.
    env.ToggleWorldMap = function()
        client.taint:MapWrite("ToggleWorldMap")
        client.taint.pinsTainted = true
        local map = env.WorldMapFrame
        if map:IsShown() then map:Hide() else map:Show() end
    end
    env.OpenWorldMap = function(mapID)
        client.taint:MapWrite("OpenWorldMap")
        client.taint.pinsTainted = true
        env.WorldMapFrame:Show()
        if mapID then client.viewedMap = mapID end
    end
    env.C_ChatInfo = { RegisterAddonMessagePrefix = function() return true end, SendAddonMessage = function() end }
    env.GetNumGroupMembers = function() return 0 end
    env.GetNumClasses = function() return 0 end
    env.RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1, colorStr = "ffffffff" } end })
    env.LOCALIZED_CLASS_NAMES_MALE = {}
    env.CLASS_SORT_ORDER = {}
    env.GetClassInfo = function() return nil end
    env.GetNumSpecializationsForClassID = function() return 0 end
    env.GetSpecializationInfoForClassID = function() return nil end
    env.IsInGroup, env.IsInRaid, env.IsInGuild = function() return false end, function() return false end, function() return false end
    -- The map frame: a canvas the map search and the route line hang on.
    local map = env.CreateFrame("Frame", "WorldMapFrame", self.root)
    map:Hide()
    map:SetSize(1000, 700)
    map:SetPoint("CENTER")
    local scroll = env.CreateFrame("Frame", nil, map)
    scroll:SetAllPoints(map)
    local canvas = env.CreateFrame("Frame", nil, scroll)
    canvas:SetAllPoints(scroll)
    scroll.Child = canvas
    function scroll:GetCanvas() return canvas end
    function scroll:GetCanvasScale() return 1 end
    function scroll:IsCanvasMouseFocus() return false end
    map.ScrollContainer = scroll
    map.BorderFrame = env.CreateFrame("Frame", nil, map)
    map.BorderFrame.TitleContainer = env.CreateFrame("Frame", nil, map.BorderFrame)
    map.QuestLog = env.CreateFrame("Frame", nil, map)
    map.pinPools = {}
    map.overlayFrames = {}
    function map:GetMapID() return client.viewedMap or client.player.mapID end
    function map:SetMapID(m)
        if client.viewedMap == m then return end
        client.taint:MapWrite("SetMapID")
        client.taint.mapIDTainted = true
        client.viewedMap = m
    end
    function map:GetCanvas() return canvas end
    function map:GetCanvasContainer() return scroll end
    function map:AddDataProvider() end
    function map:RemoveDataProvider() end
    function map:AddOverlayFrame() end
    function map:EnumeratePinsByTemplate() return function() end end
    function map:EnumerateAllPins() return function() end end
    function map:AcquirePin() return env.CreateFrame("Frame", nil, canvas) end
    function map:RemoveAllPinsByTemplate() end
    function map:RegisterCallback() end
    function map:SetPinPosition() end
    function map:GetNormalizedCursorPosition() return 0.5, 0.5 end
    -- The first show arms the quest pins' callback, which then outlives every hide.
    map:HookScript("OnShow", function() client.taint.armed = true end)
    function map:IsMaximized() return false end
    function map:Maximize() end
    function map:Minimize() end
    env.Minimap = env.CreateFrame("Frame", "Minimap", self.root)
    env.Minimap:SetSize(140, 140)
    env.Minimap:SetPoint("TOPRIGHT", -20, -20)
    function env.Minimap:GetZoom() return 0 end
    function env.Minimap:GetZoomLevels() return 6 end
    env.GetCVar = function() return nil end
    env.MinimapCluster = env.CreateFrame("Frame", "MinimapCluster", self.root)
    env.ObjectiveTrackerFrame = env.CreateFrame("Frame", "ObjectiveTrackerFrame", self.root)
    return env
end

-- ==== Blizzard's map and super-track chain ==================================

-- Modeled on the game's public UI source, whose lines match the reported stack exactly:
--
--   SUPER_TRACKING_CHANGED fires inside the call that changed it, so the handlers run in
--   the caller's taint. Blizzard_QuestSuperTracking.lua:59 fires Supertracking.OnChanged.
--   QuestDataProvider.lua:39 registers its refresh for that when the map shows, and its
--   UnregisterEvents leaves it registered, so the refresh runs with the map closed too.
--   RefreshAllData reaches AcquirePin, whose SetPassThroughButtons is refused to tainted
--   code in combat. That refusal is the error.
--
-- Two kinds of harm outlive the call, so a combat check alone would not be enough. The
-- map's id written by an addon stays tainted, and every later refresh reads it. A pin
-- built during a tainted refresh is tainted for the session.
local Taint = {}
Taint.__index = Taint

function Client.NewTaint(client)
    return setmetatable({ client = client, calls = {}, refreshes = {}, blocked = {}, mapWrites = {} }, Taint)
end

function Taint:Entry(what)
    return { what = what, combat = self.client.player.combat, mapShown = self.client.env.WorldMapFrame:IsShown() }
end

function Taint:Called(what)
    self.calls[#self.calls + 1] = self:Entry(what)
end

-- A refresh of the quest pins, from the caller's taint or the game's own clean event.
function Taint:Refresh(what, tainted)
    if not self.armed then return end
    if tainted then self.refreshes[#self.refreshes + 1] = self:Entry(what) end
    if self.client.player.combat and (tainted or self.mapIDTainted or self.pinsTainted) then
        self.blocked[#self.blocked + 1] = self:Entry(what)
    end
end

function Taint:SuperTrack(what)
    self:Refresh(what, true)
    self.client:Fire("SUPER_TRACKING_CHANGED")
end

-- Only the waypoint's own map pin listens, and only while the map is shown.
function Taint:Waypoint(what)
    self:Called(what)
    if self.client.env.WorldMapFrame:IsShown() then self:Refresh(what, true) end
    self.client:Fire("USER_WAYPOINT_UPDATED")
end

function Taint:MapWrite(what)
    self.mapWrites[#self.mapWrites + 1] = self:Entry(what)
    self:Refresh(what, true)
end

-- The player's own hand on the map: the game's code, clean. A map opened on another zone
-- writes a clean id over a tainted one.
function Client:PlayerToggleMap()
    local map, here = self.env.WorldMapFrame, self.player.mapID
    if map:IsShown() then return map:Hide() end
    if self.viewedMap ~= here then
        self.viewedMap = here
        self.taint.mapIDTainted = false
    end
    map:Show()
end

function Client:PlayerTurnsMap(mapID)
    if self.viewedMap == mapID then return end
    self.viewedMap = mapID
    self.taint.mapIDTainted = false
end

-- What the game does itself when a quest is accepted, turned in or finished: its own
-- super-track change, clean unless something it reads is not.
function Client:GameChangesSuperTrack(questID)
    self.superTrack.quest = questID
    if questID then self.superTrack.waypoint = false end
    self.taint:Refresh("the game", false)
    self:Fire("SUPER_TRACKING_CHANGED")
end

-- A reload keeps the game's map state and arms nothing new by itself: the callback the
-- map registered is gone with the old UI, until the player opens it again.
function Client:MapSeenForReload()
    self.taint.armed = true
end

function Client:After(delay, fn)
    self.timers[#self.timers + 1] = { at = self.now + (delay or 0), fn = fn }
end

-- Time passes in steps: timers that came due, then each frame's OnUpdate.
function Client:Advance(seconds, step)
    UI.frames, UI.named = self.frames, self.named
    step = step or 0.1
    local stop = self.now + seconds
    local guard = 0
    while self.now < stop and guard < 200000 do
        guard = guard + 1
        self.now = math.min(stop, self.now + step)
        local due = {}
        for i = #self.timers, 1, -1 do
            if self.timers[i].at <= self.now then
                due[#due + 1] = self.timers[i]
                table.remove(self.timers, i)
            end
        end
        for i = #due, 1, -1 do due[i].fn() end
        UI.RunUpdates(step)
    end
end

function Client:Fire(event, ...)
    UI.frames, UI.named = self.frames, self.named
    UI.Fire(event, ...)
end

function Client:SetPlayer(mapID, x, y)
    self.player.mapID, self.player.x, self.player.y = mapID, x, y
end

-- Where a world spot is on a map, for placing the player by the route's own numbers.
function Client:WorldToMap(mapID, wx, wy)
    local p = self.planes and self.planes[mapID]
    return (wy - p[4]) / p[5], (wx - p[2]) / p[3]
end

-- ==== loading through the TOC ===============================================

-- Whether a toc line's load rules let it load on this client.
local function Allowed(rules)
    for kind, value in rules:gmatch("%[(%w+)%s+([%w,%s]+)%]") do
        if kind == "AllowLoadGameType" and not value:find("camelot", 1, true) then return false end
        if kind == "AllowLoadTextLocale" and not value:find("enUS", 1, true) then return false end
    end
    return true
end

-- What ships: one folder, assembled by tools/assemble.py from the parts in addons/.
local PATHS = { ForeverGPS = "build/assembled/ForeverGPS" }
Client.PATHS = PATHS

function Client.TocLines(addon)
    local path = ROOT .. "/" .. PATHS[addon] .. "/" .. addon .. ".toc"
    local f = assert(io.open(path, "r"), "no toc: " .. path)
    local meta, files = {}, {}
    for line in f:lines() do
        line = line:gsub("\r$", "")
        local key, value = line:match("^##%s*([%w%-_]+):%s*(.-)%s*$")
        if key then meta[key] = value
        elseif line ~= "" and not line:find("^#") then
            local file, rules = line:match("^(.-)%s+(%[.*%])$")
            file, rules = file or line, rules or ""
            if Allowed(rules) then files[#files + 1] = file end
        end
    end
    f:close()
    return meta, files
end

-- skip(file) leaves a file out (the walking grids are slow to parse).
function Client:LoadAddon(addon, skip)
    self.loadFiles = self.loadFiles or {}
    local meta, files = Client.TocLines(addon)
    self.meta = self.meta or {}
    self.meta[addon] = meta
    self.addons[addon] = true
    self.loadOrder = self.loadOrder or {}
    self.loadOrder[#self.loadOrder + 1] = addon
    local own = {}
    self.addonTables = self.addonTables or {}
    self.addonTables[addon] = own
    if addon == "EasyFind" then
        -- The saved variables the client hands over before ADDON_LOADED.
        self.env.EasyFindDB = self.env.EasyFindDB
    end
    for _, file in ipairs(files) do
        if file:find("%.lua$") and not (skip and skip(file)) then
            local path = ROOT .. "/" .. PATHS[addon] .. "/" .. file:gsub("\\", "/")
            local chunk, err = loadfile(path, "t", self.env)
            if not chunk then error(addon .. "/" .. file .. ": " .. tostring(err), 2) end
            local ok, runErr = xpcall(chunk, debug.traceback, addon, own)
            if not ok then error(addon .. "/" .. file .. ": " .. tostring(runErr), 2) end
        end
    end
    local ns = self.env.EasyFind and self.env.EasyFind._ns
    local data = ns and ns.NPC_DATA
    if data and data.planes then
        self.planes = data.planes
        -- Continents: fitted from the instance table, which gives both.
        for _, m in ipairs({ CONTINENT_KALIMDOR, CONTINENT_EK }) do
            local list = {}
            for _, e in pairs(ns.FOREVER_INSTANCES or {}) do
                if type(e) == "table" and e.cm == m and e.cx and e.wx then list[#list + 1] = e end
            end
            if #list >= 2 then
                table.sort(list, function(a, b) return a.cx < b.cx end)
                local a, b = list[1], list[#list]
                local yScale = (b.wy - a.wy) / (b.cx - a.cx)
                table.sort(list, function(p, q) return p.cy < q.cy end)
                local c, d = list[1], list[#list]
                local xScale = (d.wx - c.wx) / (d.cy - c.cy)
                self.planes[m] = { a.ci, c.wx - xScale * c.cy, xScale, a.wy - yScale * a.cx, yScale }
            end
        end
    end
    return own
end

function Client:Login()
    for _, addon in ipairs(self.loadOrder) do UI.Fire("ADDON_LOADED", addon) end
    self.loggedIn = true
    UI.Fire("PLAYER_LOGIN")
    UI.Fire("PLAYER_ENTERING_WORLD", true, false)
    self:Advance(0.5)
end

return Client
