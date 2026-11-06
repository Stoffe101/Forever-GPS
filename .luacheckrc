-- Forever-GPS's own code. Upstream's addons keep their own .luacheckrc and are
-- checked against their pins by tools/upstream.py instead.
std = "lua51"
max_line_length = false
codes = true
exclude_files = { "addons/EasyFind/**", "addons/EasyFind_GPS/**", "addons/EasyFind_Questie/**", "tests/**", "tools/**", "build/**", "dist/**" }

ignore = {
    "212/self",     -- methods need not use self
    "212/_.*",      -- deliberately unused arguments
    "213/_.*",
}

globals = {
    "ForeverGPS", "ForeverGPSDB", "ForeverGPSCharDB", "ForeverGPS_OnCompartmentClick", "ForeverGPSPreflight", "ForeverGPSImported",
    "EasyFindDB", "StaticPopupDialogs",
    "EasyFind",     -- its saved settings are written through the Bridge; never the global itself
    "SLASH_FOREVERGPS1", "SLASH_FOREVERGPS2", "SlashCmdList", "UISpecialFrames",
    "BINDING_HEADER_FOREVERGPS", "BINDING_NAME_FOREVERGPS_TOGGLE", "BINDING_NAME_FOREVERGPS_QUESTS", "BINDING_NAME_FOREVERGPS_STOP", "BINDING_NAME_FOREVERGPS_QUICK",
}

read_globals = {
    "C_AddOns", "C_Item", "C_Map", "C_QuestLog", "C_Spell", "C_Timer", "CreateFrame", "GameTooltip",
    "GetAddOnMemoryUsage", "GetAddOnMetadata", "GetBuildInfo", "GetLocale", "GetPlayerFacing", "GetTime", "InCombatLockdown",
    "STANDARD_TEXT_FONT", "UIParent", "UnitClass", "UnitFactionGroup", "UnitLevel", "UnitOnTaxi", "UpdateAddOnMemoryUsage",
    "WOW_PROJECT_ID", "debugprofilestop", "geterrorhandler", "issecretvalue", "strtrim", "tinsert", "wipe",
    "ToggleWorldMap", "WorldMapFrame", "GetCursorPosition", "IsShiftKeyDown", "Minimap", "CANCEL", "ReloadUI", "StaticPopup_Show", "GetFramerate",
}
