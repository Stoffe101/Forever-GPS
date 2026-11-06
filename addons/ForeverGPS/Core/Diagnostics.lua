-- `/fgps diag`: the facts needed to tell what a client really is, what loaded,
-- and which game APIs answered. Everything Forever-GPS depends on is probed
-- here at runtime, so a client change shows up as a line rather than a mystery.
local _, FG = ...
local Diagnostics = {}
FG.Diagnostics = Diagnostics

local Bridge = FG.Bridge

-- The game API Forever-GPS calls directly, by name. Kept in step with the code
-- by tests/test_static.lua.
Diagnostics.API = {
    "C_AddOns.GetAddOnMetadata", "C_Map.GetBestMapForUnit", "C_Map.GetMapInfo", "C_Map.GetUserWaypoint",
    "C_QuestLog.GetInfo", "C_QuestLog.GetNumQuestLogEntries", "C_QuestLog.GetQuestObjectives", "C_QuestLog.IsComplete",
    "C_QuestLog.IsFailed", "C_Timer.After", "CreateFrame", "GetPlayerFacing", "UnitClass", "UnitFactionGroup",
    "UnitLevel", "UnitOnTaxi", "debugprofilestop",
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
    local Meta = C_AddOns.GetAddOnMetadata
    local loaded = C_AddOns.IsAddOnLoaded(name)
    local version = Meta(name, "Version")
    return ("%s: %s%s"):format(name, loaded and "loaded" or "not loaded", version and (" (" .. version .. ")") or "")
end

function Diagnostics.Lines()
    local out = {}
    local version, build, _, interface = GetBuildInfo()
    out[#out + 1] = ("Client %s build %s, interface %s, project %s, locale %s"):format(
        tostring(version), tostring(build), tostring(interface), tostring(WOW_PROJECT_ID), tostring(GetLocale()))
    local ns = Bridge.NS()
    local data = ns and ns.GPSData
    out[#out + 1] = ("Route data built from client build %s"):format(tostring(data and data.build))
    for _, name in ipairs({ "EasyFind", "EasyFind_GPS", "EasyFind_Questie", "Questie", "TomTom" }) do
        out[#out + 1] = AddonLine(name)
    end
    out[#out + 1] = "Questie data: " .. (FG.QuestTargets.HasQuestie() and "ready" or "not available")
    local missing = Bridge.Missing()
    out[#out + 1] = #missing == 0 and "EasyFind internals: all present" or ("EasyFind internals MISSING: " .. table.concat(missing, ", "))
    local absent = {}
    for _, name in ipairs(Diagnostics.API) do
        if Lookup(name) == nil then absent[#absent + 1] = name end
    end
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
    if UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
        UpdateAddOnMemoryUsage()
        out[#out + 1] = ("Memory: Forever-GPS %.1f MB, GPS %.1f MB, EasyFind %.1f MB"):format(
            GetAddOnMemoryUsage("ForeverGPS") / 1024, GetAddOnMemoryUsage("EasyFind_GPS") / 1024, GetAddOnMemoryUsage("EasyFind") / 1024)
    end
    return out
end

function Diagnostics.Print()
    FG.Print("diagnostics")
    for _, line in ipairs(Diagnostics.Lines()) do print("  " .. line) end
end
