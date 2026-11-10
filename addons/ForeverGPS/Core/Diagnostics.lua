-- `/fgps diag` and `/fgps report`: the facts needed to tell what a client really is,
-- what loaded, how it is performing and which game APIs answered. Everything
-- Forever-GPS depends on is probed here at runtime, so a client change shows up as a
-- line rather than a mystery. Reports hold no character or realm name, so they can
-- be posted as they are.
local FG = ForeverGPS
local Diagnostics = {}
FG.Diagnostics = Diagnostics

local Bridge = FG.Bridge

-- The game API Forever-GPS calls directly, by name. Kept in step with the code
-- by tests/test_static.lua.
Diagnostics.API = {
    "C_AddOns.GetAddOnMetadata", "C_Map.GetBestMapForUnit", "C_Map.GetMapArtLayers", "C_Map.GetMapArtLayerTextures",
    "C_Map.GetMapInfo", "C_Map.GetUserWaypoint",
    "C_AuctionHouse.ReplicateItems", "C_TradeSkillUI.GetRecipeSchematic", "GetProfessions", "TaxiNodeCost",
    "C_QuestLog.GetInfo", "C_QuestLog.GetNumQuestLogEntries", "C_QuestLog.GetQuestObjectives", "C_QuestLog.IsComplete",
    "C_QuestLog.IsFailed", "C_Timer.After", "CreateFrame", "GetCursorPosition", "GetPlayerFacing", "UnitClass",
    "UnitFactionGroup", "UnitLevel", "UnitOnTaxi", "debugprofilestop",
}

local function Lookup(path)
    local value = _G
    for part in path:gmatch("[^.]+") do
        if type(value) ~= "table" then return nil end
        value = value[part]
    end
    return value
end

local function AddonLine(name)
    local loaded = C_AddOns.IsAddOnLoaded(name)
    -- Asked only of what is loaded: the game need not answer for an addon it does not have.
    local version = loaded and C_AddOns.GetAddOnMetadata(name, "Version")
    return ("%s: %s%s"):format(name, loaded and "loaded" or "not loaded", version and (" (" .. version .. ")") or "")
end

-- What is inside the folder, by version.
local function VendorLine()
    local parts = {}
    for _, part in ipairs(FG.VENDOR or {}) do parts[#parts + 1] = ("%s %s"):format(part.name, part.version) end
    return "Built on: " .. table.concat(parts, ", ")
end

local function MissingApi()
    local absent = {}
    for _, name in ipairs(Diagnostics.API) do
        if Lookup(name) == nil then absent[#absent + 1] = name end
    end
    return absent
end

local function RouteData()
    local ns = Bridge.NS()
    return ns and ns.GPSData
end

-- What is right and wrong, worst first. Each: { "ok"|"note"|"limited"|"broken", text }.
-- "limited" works with less; "broken" means navigation cannot be trusted; "note" is
-- worth knowing and changes nothing.
function Diagnostics.Checks()
    local out = {}
    local function Add(state, text) out[#out + 1] = { state, text } end
    local missing, absent = Bridge.Missing(), MissingApi()
    if not Bridge.Ready() then
        Add("broken", "EasyFind GPS is not ready: no navigation")
    else
        Add("ok", "Route engine ready")
    end
    if #missing > 0 then Add("broken", "EasyFind internals missing: " .. table.concat(missing, ", ")) end
    if #absent > 0 then Add("broken", "Game API missing: " .. table.concat(absent, ", ")) end
    if FG.missingEvents then Add("limited", ("%d game events unknown to this client"):format(FG.missingEvents)) end
    local data = RouteData()
    local _, build = GetBuildInfo()
    if data and data.build and tostring(data.build) ~= tostring(build) then
        Add("note", ("Route data is from build %s, this client is %s"):format(tostring(data.build), tostring(build)))
    elseif data then
        Add("ok", "Route data matches this client")
    end
    Add(FG.QuestTargets.HasQuestie() and "ok" or "limited",
        FG.QuestTargets.HasQuestie() and "Questie data ready" or "No Questie data: objective places and world search are limited")
    if not Bridge.PlayerStart() then Add("limited", "No position available here") end
    local old = ForeverGPSPreflight.old
    if #old > 0 then Add("broken", "Old folders still enabled: " .. table.concat(old, ", ")) end
    table.sort(out, function(a, b)
        local rank = { broken = 1, limited = 2, note = 3, ok = 4 }
        if a[1] ~= b[1] then return rank[a[1]] < rank[b[1]] end
        return a[2] < b[2]
    end)
    return out
end

-- One word for the whole of it: "ready", "limited" or "broken".
function Diagnostics.Status()
    local worst = "ready"
    for _, check in ipairs(Diagnostics.Checks()) do
        if check[1] == "broken" then return "broken" end
        if check[1] == "limited" then worst = "limited" end
    end
    return worst
end

local function CacheLine()
    return ("Caches: %d travel estimates, %d plans kept"):format(FG.Eta.Size(), FG.Planner.KeptCount())
end

-- The figures that are easy to misread, said in words. Elapsed time spans many frames and
-- costs nothing by itself: the worst frame is what a player can feel.
function Diagnostics.Timing()
    local M, out = FG.Metrics, {}
    local function ms(name, of) return ("%.1f"):format((of or M.Last)(name) or 0) end
    if M.Runs("plan") > 0 then
        out[#out + 1] = ("Planning, last: %s ms from asking to the answer, of which %s ms of work"):format(ms("plan"), ms("planWork"))
    end
    if M.Runs("planFrame") > 0 then
        out[#out + 1] = ("Planning, busiest frame: engine %s ms (unpacking up to %s), then collector up to %s, then finishing up to %s, over %d frames"):format(
            ms("planFrame", M.Worst), ms("planUnpack", M.Worst), ms("planCollect", M.Worst), ms("planFinish", M.Worst), M.Runs("planFrame"))
    end
    if M.Runs("search") > 0 then
        out[#out + 1] = ("Search, slowest: %s ms (places %s, creatures and objects %s, quests %s)"):format(
            ms("search", M.Worst), ms("searchPlaces", M.Worst), ms("searchWorld", M.Worst), ms("searchQuests", M.Worst))
    end
    if M.Runs("mapDraw") > 0 then out[#out + 1] = ("Map drawing, slowest: %s ms"):format(ms("mapDraw", M.Worst)) end
    if M.Runs("questIndex") > 0 then
        out[#out + 1] = ("Quest index: %d quests, slowest slice %s ms"):format(FG.QuestIndex.Count(), ms("questIndex", M.Worst))
    end
    return out
end

-- What has been asked of the game's waypoint and map, for a real session to be read.
function Diagnostics.GameLines()
    local c = Bridge.GameChanges()
    return {
        ("Game waypoint: %d changes made, %d held for a fight, %d held for the map, %d skipped as already so"):format(c.ran, c.heldInCombat, c.heldUnderMap, c.skipped),
        ("Game map turned by a click in its own panel: %d, refused in a fight: %d"):format(c.mapTurns, c.mapRefused),
        ("Game beacon: %s. Taint log: %s"):format(FG.db.map.beacon ~= false and "on" or "off", tostring(GetCVar("taintLog") or "off")),
    }
end

function Diagnostics.Lines()
    local out = {}
    local version, build, _, interface = GetBuildInfo()
    out[#out + 1] = ("Forever-GPS %s: %s"):format(tostring(FG.VERSION), Diagnostics.Status())
    out[#out + 1] = ("Client %s build %s, interface %s, project %s, locale %s"):format(
        tostring(version), tostring(build), tostring(interface), tostring(WOW_PROJECT_ID), tostring(GetLocale()))
    local data = RouteData()
    out[#out + 1] = ("Route data built from client build %s"):format(tostring(data and data.build))
    out[#out + 1] = VendorLine()
    for _, name in ipairs({ "Questie", "TomTom" }) do
        out[#out + 1] = AddonLine(name)
    end
    out[#out + 1] = "Questie data: " .. (FG.QuestTargets.HasQuestie() and "ready" or "not available")
    local missing = Bridge.Missing()
    out[#out + 1] = #missing == 0 and "EasyFind internals: all present" or ("EasyFind internals MISSING: " .. table.concat(missing, ", "))
    local absent = MissingApi()
    out[#out + 1] = #absent == 0 and ("Game API: all %d present"):format(#Diagnostics.API) or ("Game API MISSING: " .. table.concat(absent, ", "))
    local mapID = C_Map.GetBestMapForUnit("player")
    local start = Bridge.PlayerStart()
    out[#out + 1] = ("Position: map %s (%s), world %s"):format(tostring(mapID), tostring(Bridge.MapName(mapID)),
        start and ("continent %d at %.0f, %.0f"):format(start.ci, start.wx, start.wy) or "unknown here")
    local route = Bridge.Route()
    if route then
        out[#out + 1] = ("Route to %s: step %d of %d%s"):format(route.dest and route.dest.name or "?", route.active or 1, #route.steps,
            route.arrived and ", arrived" or "")
    else
        out[#out + 1] = "No route"
    end
    out[#out + 1] = ("Arrow: %s. Planning: %s"):format(FG.Journey.ArrowMode(), tostring(Bridge.IsPlanning()))
    out[#out + 1] = CacheLine()
    for _, line in ipairs(Diagnostics.GameLines()) do out[#out + 1] = line end
    for _, line in ipairs(Diagnostics.Timing()) do out[#out + 1] = line end
    for _, line in ipairs(FG.Metrics.Lines()) do out[#out + 1] = line end
    if UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
        UpdateAddOnMemoryUsage()
        out[#out + 1] = ("Memory: %.1f MB"):format(GetAddOnMemoryUsage(FG.ADDON) / 1024)
    end
    return out
end

function Diagnostics.Print()
    FG.Print("diagnostics")
    for _, line in ipairs(Diagnostics.Lines()) do print("  " .. line) end
end

-- All of it as text to paste into a report.
function Diagnostics.Report()
    local out = { "Forever-GPS report" }
    for _, check in ipairs(Diagnostics.Checks()) do
        out[#out + 1] = ("[%s] %s"):format(check[1], check[2])
    end
    out[#out + 1] = ""
    for _, line in ipairs(Diagnostics.Lines()) do out[#out + 1] = line end
    local notes = FG.Metrics.Notes()
    if #notes > 0 then
        out[#out + 1] = ""
        out[#out + 1] = "Recent:"
        for _, note in ipairs(notes) do out[#out + 1] = "  " .. tostring(note) end
    end
    return table.concat(out, "\n")
end
