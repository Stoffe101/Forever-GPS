-- Static checks on Forever-GPS's own source. WoW runs Lua 5.1 and these tests run
-- on 5.4, so what the runtime cannot catch is caught by reading the code: globals
-- touched, game API used, widget methods called, text keys, syntax.
local T = require("support.t")
local UI = require("support.fakeui")

local function Read(path)
    local f = assert(io.open(path, "rb"), path)
    local s = f:read("a")
    f:close()
    return s
end

local function Sources()
    local isWindows = package.config:sub(1, 1) == "\\"
    local p = io.popen(isWindows and 'cmd /c "dir /s /b addons\\ForeverGPS\\*.lua"' or 'find addons/ForeverGPS -name "*.lua"')
    local out = {}
    for line in p:lines() do
        local rel = line:gsub("\\", "/"):match("(addons/ForeverGPS/.+)$")
        out[#out + 1] = { path = rel, src = Read(rel) }
    end
    p:close()
    table.sort(out, function(a, b) return a.path < b.path end)
    return out
end

-- Source with strings and comments blanked, for looking at the code itself.
local function CodeOnly(src)
    local out, i, n = {}, 1, #src
    while i <= n do
        local c = src:sub(i, i)
        if src:sub(i, i + 3) == "--[[" then
            local _, e = src:find("]]", i, true)
            i = (e or n) + 1
        elseif src:sub(i, i + 1) == "--" then
            local e = src:find("\n", i, true) or n
            i = e
        elseif c == '"' or c == "'" then
            local j = i + 1
            while j <= n do
                local ch = src:sub(j, j)
                if ch == "\\" then j = j + 2
                elseif ch == c then break
                else j = j + 1 end
            end
            out[#out + 1] = '""'
            i = j + 1
        else
            out[#out + 1] = c
            i = i + 1
        end
    end
    return table.concat(out)
end

-- Every global a file reads and writes, from the compiler's own listing.
local LUAC = os.getenv("LUAC") or "luac"
local function Globals(path)
    local p = io.popen(('%s -l -l -p "%s" 2>&1'):format(LUAC, path))
    local reads, writes = {}, {}
    for line in p:lines() do
        local op, name = line:match("(%u+TABUP).-_ENV%s+\"([%w_]+)\"")
        if op == "GETTABUP" then reads[name] = true
        elseif op == "SETTABUP" then writes[name] = true end
    end
    p:close()
    return reads, writes
end

-- Lua's own, and what WoW adds to the language.
local LANGUAGE = {}
for name in ("assert error ipairs math next pairs pcall print select string table tonumber tostring type unpack xpcall "
    .. "getmetatable setmetatable rawget rawset wipe strtrim tinsert"):gmatch("%S+") do LANGUAGE[name] = true end

-- The game API Forever-GPS reaches for. Each one is used by EasyFind, EasyFind GPS
-- or an addon verified on interface 16001; tests below hold this list to that.
local GAME = {}
for name in ("C_AddOns C_Item C_Map C_QuestLog C_Spell C_Timer CreateFrame EasyFind GameTooltip GetAddOnMemoryUsage GetBuildInfo GetTime "
    .. "GetAddOnMetadata GetLocale GetPlayerFacing InCombatLockdown STANDARD_TEXT_FONT SlashCmdList UIParent "
    .. "UnitClass UnitFactionGroup UnitLevel UnitOnTaxi UpdateAddOnMemoryUsage WOW_PROJECT_ID debugprofilestop geterrorhandler "
    .. "issecretvalue WorldMapFrame GetCursorPosition GetCVar GetClassInfo GetItemCount GetItemInfo GetProfessions GetProfessionInfo GetTaxiMapID TaxiNodeCost GetRealmName GetMinimapZoneText GetMerchantNumItems GetMerchantItemInfo GetMerchantItemID UnitGUID UnitName strsplit GetNumTrainerServices GetTrainerServiceInfo GetTrainerServiceSkillReq GetTrainerServiceLevelReq GetTrainerServiceCost GetTrainerServiceStepIndex GetTrainerServiceSkillLine GetTrainerTradeskillRankValues C_AuctionHouse C_TradeSkillUI C_TaxiMap C_Container GetItemCooldown Enum IsShiftKeyDown Minimap CANCEL ReloadUI StaticPopupDialogs GetFramerate UnitName GetBindLocation time PlaySound SOUNDKIT "
    .. "StaticPopup_Show ForeverGPSPreflight ForeverGPSImported EasyFindDB _G coroutine"):gmatch("%S+") do GAME[name] = true end

local OWN_GLOBALS = {}
for name in ("ForeverGPS ForeverGPSDB ForeverGPSCharDB ForeverGPS_OnCompartmentClick SLASH_FOREVERGPS1 SLASH_FOREVERGPS2 "
    .. "BINDING_HEADER_FOREVERGPS BINDING_NAME_FOREVERGPS_TOGGLE BINDING_NAME_FOREVERGPS_QUESTS BINDING_NAME_FOREVERGPS_STOP BINDING_NAME_FOREVERGPS_QUICK BINDING_NAME_FOREVERGPS_TARGET ForeverGPSPreflight EasyFindDB "
    .. "ForeverGPSImported"):gmatch("%S+") do
    OWN_GLOBALS[name] = true
end

local tests = {}

function tests.noGlobalLeaks()
    for _, file in ipairs(Sources()) do
        local _, writes = Globals(file.path)
        for name in pairs(writes) do
            T.ok(OWN_GLOBALS[name], file.path .. " writes the global " .. name)
        end
    end
end

function tests.onlyKnownGlobalsAreRead()
    local reads = 0
    for _, file in ipairs(Sources()) do
        local names = Globals(file.path)
        for name in pairs(names) do
            reads = reads + 1
            T.ok(LANGUAGE[name] or GAME[name] or OWN_GLOBALS[name], file.path .. " reads an unlisted global (a typo?): " .. name)
        end
    end
    T.ok(reads > 50, "the listing was read: " .. reads)
end

-- docs/TAINT.md. What Forever-GPS's own code must never do, whatever a green run says.
function tests.ourOwnCode_keepsOffTheGamesMapAndTracking()
    local FORBIDDEN = { "SetMapID", "ToggleWorldMap", "OpenWorldMap", "ShowUIPanel", "HideUIPanel", "UISpecialFrames",
        "C_SuperTrack", "SetUserWaypoint", "ClearUserWaypoint", "AddDataProvider", "RemoveDataProvider", "AcquirePin",
        "SetPassThroughButtons", "SetPropagateMouseClicks", "QuestMapFrame_OpenToQuestDetails" }
    for _, file in ipairs(Sources()) do
        local code = CodeOnly(file.src)
        for _, name in ipairs(FORBIDDEN) do
            T.no(code:find(name, 1, true), file.path .. " reaches for " .. name)
        end
    end
end

-- The vendored code changes the game's waypoint and tracking in one place only.
function tests.theGamesWaypoint_hasOneDoorInTheFolderThatShips()
    local DOOR = {
        ["C_SuperTrack.SetSuperTrackedUserWaypoint(on)"] = true,
        ["SetUserWaypoint(point)"] = true,
        ["ClearUserWaypoint()"] = true,
    }
    local function Scan(rel)
        local isWindows = package.config:sub(1, 1) == "\\"
        local p = io.popen(isWindows and ('cmd /c "dir /b /s build\\assembled\\ForeverGPS\\' .. rel:gsub("/", "\\") .. '\\*.lua"')
            or ("find build/assembled/ForeverGPS/" .. rel .. " -name '*.lua'"))
        local seen = 0
        for path in p:lines() do
            seen = seen + 1
            local code = CodeOnly(Read(path))
            for line in code:gmatch("[^\n]+") do
                local call = line:match("C_SuperTrack%.Set[%w_]+%b()") or line:match("C_SuperTrack%.Clear[%w_]+%b()")
                    or line:match("%f[%w_]SetUserWaypoint%b()") or line:match("%f[%w_]ClearUserWaypoint%b()")
                if call and not line:find("local ", 1, true) then
                    local inFunnel = DOOR[call] or line:find("WaypointChange(", 1, true) or line:find("GamePinChange(", 1, true)
                    T.ok(inFunnel, path .. " changes the game's waypoint outside the door: " .. line)
                end
            end
        end
        p:close()
        return seen
    end
    T.ok(Scan("Vendor") > 20, "the scan saw the vendored files")
end

function tests.everyGameApi_isOneUpstreamAlreadyUses()
    -- Upstream runs on this client. A name it uses is one the client has.
    local haystack = {}
    local isWindows = package.config:sub(1, 1) == "\\"
    local p = io.popen(isWindows and 'cmd /c "dir /b addons\\EasyFind_GPS\\*.lua"' or 'ls addons/EasyFind_GPS/')
    for line in p:lines() do
        local name = line:match("([^/\\]+%.lua)$")
        if name and not name:find("^Walk_") and not name:find("^Npcs_") and not name:find("^Data") then
            haystack[#haystack + 1] = Read("addons/EasyFind_GPS/" .. name)
        end
    end
    p:close()
    haystack[#haystack + 1] = Read("addons/EasyFind/Shared/Utils.lua")
    haystack[#haystack + 1] = Read("addons/EasyFind/Core/Main.lua")
    haystack[#haystack + 1] = Read("addons/EasyFind/Search/Modules.lua")
    haystack[#haystack + 1] = Read("addons/EasyFind_Questie/Quests.lua")
    -- Not something EasyFind has reason to call, and guarded by a pcall where it is used.
    haystack[#haystack + 1] = "C_AddOns.DisableAddOn"
    -- What the game's own map draws its art with, read in its public source. Absent, the
    -- route map draws on plain ground, and `/fgps diag` says so.
    haystack[#haystack + 1] = "C_Map.GetMapArtLayers C_Map.GetMapArtLayerTextures"
    -- Professions, prices and fares: the modern APIs this client has, as addons verified on
    -- interface 16001 use them (Auctionator, NaowhForever). Probed by /fgps diag.
    haystack[#haystack + 1] = "C_AuctionHouse.ReplicateItems C_AuctionHouse.GetNumReplicateItems C_AuctionHouse.GetReplicateItemInfo "
        .. "C_TradeSkillUI.GetBaseProfessionInfo C_TradeSkillUI.GetAllRecipeIDs C_TradeSkillUI.GetRecipeInfo C_TradeSkillUI.GetRecipeSchematic "
        .. "C_TaxiMap.GetAllTaxiNodes C_Container.GetItemCooldown "
    -- Targeted auction searches, as CraftProfit measured them in this client
    -- (third_party/CraftProfit/docs/probe-findings.md F1 and F13).
        .. "C_AuctionHouse.SendSearchQuery C_AuctionHouse.MakeItemKey C_AuctionHouse.IsThrottledMessageSystemReady "
        .. "C_AuctionHouse.GetNumCommoditySearchResults C_AuctionHouse.GetCommoditySearchResultInfo "
        .. "C_AuctionHouse.GetNumItemSearchResults C_AuctionHouse.GetItemSearchResultInfo"
    local all = table.concat(haystack, "\n")
    local checked = 0
    for _, file in ipairs(Sources()) do
        for call in CodeOnly(file.src):gmatch("%f[%w_](C_%w+%.[%w_]+)") do
            checked = checked + 1
            T.ok(all:find(call, 1, true), file.path .. " calls " .. call .. ", which upstream never does")
        end
    end
    T.ok(checked > 10, "the scan saw calls: " .. checked)
end

function tests.everyEventListened_isOneTheClientFires()
    local KNOWN = {}
    for name in ("ADDON_LOADED PLAYER_LOGIN QUEST_LOG_UPDATE QUEST_ACCEPTED QUEST_REMOVED QUEST_TURNED_IN UNIT_QUEST_LOG_CHANGED "
        .. "TAXIMAP_OPENED HEARTHSTONE_BOUND UI_SCALE_CHANGED DISPLAY_SIZE_CHANGED PLAYER_REGEN_DISABLED PLAYER_REGEN_ENABLED "
        .. "GLOBAL_MOUSE_DOWN PLAYER_LEVEL_UP SKILL_LINES_CHANGED PLAYER_ENTERING_WORLD UPDATE_FACTION "
        .. "AUCTION_HOUSE_SHOW AUCTION_HOUSE_CLOSED REPLICATE_ITEM_LIST_UPDATE COMMODITY_SEARCH_RESULTS_UPDATED ITEM_SEARCH_RESULTS_UPDATED MERCHANT_SHOW TRAINER_SHOW TRADE_SKILL_SHOW "
        .. "TRADE_SKILL_LIST_UPDATE"):gmatch("%S+") do KNOWN[name] = true end
    for _, file in ipairs(Sources()) do
        for event in file.src:gmatch('FG%.OnEvent%("([%u_]+)"') do
            T.ok(KNOWN[event], file.path .. " listens for " .. event)
        end
    end
end

-- The widget methods Forever-GPS may call, all present in the fake (so anything
-- else fails here, not in the game) and all real API.
local OWN_METHODS = {}
for name in ("Paint Place SetLabel SetVariant SetSelected SetColor SetColorKey SetIcon SetActiveColor Sync Layout SetValue "
    .. "Width Measure Render Clamp SetItems Refresh Reveal "
    -- EasyFind and EasyFind GPS objects, reached through the Bridge.
    .. "IsPlanning Plan BuildRoute Clear Build Guiding HasGlobalInstanceCache SetStart "
    .. "Line Begin Finish GetMapID GetXY "
    -- Questie's loader, reached only from Core/QuestDB.lua.
    .. "ImportModule GetUiMapIdByAreaId "
    -- GameTooltip.
    .. "SetOwner AddLine"):gmatch("%S+") do OWN_METHODS[name] = true end
local STRING_METHODS = { upper = true, find = true, match = true, gmatch = true, gsub = true, sub = true, lower = true, format = true, byte = true }

function tests.everyWidgetMethod_isReal()
    for _, file in ipairs(Sources()) do
        for method in CodeOnly(file.src):gmatch(":([%a_][%w_]*)%(") do
            if method:match("^%u") and not OWN_METHODS[method] then
                local known = false
                for _, class in pairs(UI.classes) do known = known or class[method] ~= nil end
                T.ok(known or file.src:find("function %w+:" .. method) or file.src:find("function [%w%.]+:" .. method),
                    file.path .. " calls :" .. method .. "(), unknown to the fake and not defined here")
            elseif method:match("^%l") then
                T.ok(STRING_METHODS[method], file.path .. " calls :" .. method)
            end
        end
    end
end

function tests.everyTextKey_isDefinedAndUsed()
    local defined = {}
    for key in Read("addons/ForeverGPS/Locales/enUS.lua"):gmatch('L%["([%w_]+)"%]%s*=') do defined[key] = true end
    local used = {}
    local all = {}
    for _, file in ipairs(Sources()) do
        if not file.path:find("Locales", 1, true) then
            all[#all + 1] = file.src
            for key in file.src:gmatch('L%["([%w_]+)"%]') do
                T.ok(defined[key], file.path .. " uses the undefined text " .. key)
                used[key] = true
            end
        end
    end
    local joined = table.concat(all, "\n")
    local unused = {}
    for key in pairs(defined) do
        if not used[key] and not joined:find('"' .. key .. '"', 1, true) then unused[#unused + 1] = key end
    end
    table.sort(unused)
    T.eq(#unused, 0, "text no code uses: " .. table.concat(unused, ", "))
end

function tests.noSyntaxThatLua51Lacks()
    for _, file in ipairs(Sources()) do
        local code = CodeOnly(file.src)
        T.no(code:find("//", 1, true), file.path .. " uses integer division")
        T.no(code:find("<<", 1, true) or code:find(">>", 1, true), file.path .. " uses a bit shift")
        T.no(code:find("[%w%)]%s*&%s*[%w%(]"), file.path .. " uses a bit operator")
        T.no(code:find("%f[%w]goto%f[%W]"), file.path .. " uses goto")
        T.no(code:find("<const>", 1, true) or code:find("<close>", 1, true), file.path .. " uses an attribute")
        T.no(code:find("table%.unpack") or code:find("table%.pack"), file.path .. " uses 5.2's table.pack")
        T.no(code:find("utf8%."), file.path .. " uses 5.3's utf8")
    end
end

function tests.noMultiReturnLostToAndOr()
    -- `x and f() or nil` keeps one value of f's: a bug this code has had.
    local src = Read("addons/ForeverGPS/Core/Bridge.lua")
    T.no(src:find("Arrow%._Aim%(%)%s+or"), "ArrowAim must hand back every value")
end

function tests.diagnostics_knowsEveryDirectCall()
    local src = Read("addons/ForeverGPS/Core/Diagnostics.lua")
    for _, name in ipairs({ "C_QuestLog.GetInfo", "C_QuestLog.GetQuestObjectives", "C_Map.GetBestMapForUnit" }) do
        T.has(src, name, "/fgps diag probes it")
    end
end

function tests.noLineEndingsButLf()
    for _, file in ipairs(Sources()) do
        T.no(file.src:find("\r", 1, true), file.path .. " has a carriage return")
    end
    for _, path in ipairs({ "addons/ForeverGPS/ForeverGPS.toc", "addons/ForeverGPS/Bindings.xml" }) do
        T.no(Read(path):find("\r", 1, true), path)
    end
end

function tests.noRestedXp()
    for _, file in ipairs(Sources()) do
        local low = file.src:lower()
        T.no(low:find("restedxp", 1, true) or low:find("rxpguides", 1, true), file.path)
    end
end

function tests.bindingsMatchTheirNames()
    local xml = Read("addons/ForeverGPS/Bindings.xml")
    local text = Read("addons/ForeverGPS/Locales/enUS.lua")
    for name in xml:gmatch('name="(FOREVERGPS_[%u_]+)"') do
        T.has(text, "BINDING_NAME_" .. name, "a label for " .. name)
    end
end

return tests
