-- The tools that touch a real install, run on a pretend one. What they may never do
-- matters more here than what they do.
local T = require("support.t")

local WINDOWS = package.config:sub(1, 1) == "\\"
local PYTHON = os.getenv("FGPS_PYTHON") or (WINDOWS and "python" or "python3")
local BASE = "build/tooltest"

local function Win(path) return WINDOWS and path:gsub("/", "\\") or path end

local function Mkdir(path)
    os.execute(WINDOWS and ('mkdir "%s" 2>nul'):format(Win(path)) or ('mkdir -p "%s"'):format(path))
end

local function Write(path, text)
    local f = assert(io.open(path, "wb"), path)
    f:write(text)
    f:close()
end

local function Read(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("a")
    f:close()
    return s
end

local function Fresh()
    os.execute(WINDOWS and ('rmdir /s /q "%s" 2>nul'):format(Win(BASE)) or ('rm -rf "%s"'):format(BASE))
    Mkdir(BASE .. "/forever/Interface/AddOns")
    Mkdir(BASE .. "/forever/WTF/Account/1234#1/SavedVariables")
    return BASE .. "/forever"
end

local function Addon(forever, name)
    Mkdir(forever .. "/Interface/AddOns/" .. name)
    Write(forever .. "/Interface/AddOns/" .. name .. "/" .. name .. ".toc", "## Title: " .. name .. "\n")
end

local NULL = WINDOWS and "nul" or "/dev/null"

local function Run(script, args)
    return os.execute(('%s -I tools/%s %s > %s 2>&1'):format(PYTHON, script, args, NULL))
end

local SAVED = [[
EasyFindDB = {
	["gpsChar"] = {
		["Name-Realm"] = {
			["flights"] = {
				[6] = true,
			},
			["route"] = {
				["active"] = 2,
			},
		},
	},
	["gpsAvoid"] = {
		["boat"] = true,
	},
	["visible"] = true,
}
]]

local tests = {}

function tests.migrating_readsOldSavedDataWithoutWritingToWtf()
    local forever = Fresh()
    local wtf = forever .. "/WTF/Account/1234#1/SavedVariables/EasyFind.lua"
    Write(wtf, SAVED)
    Addon(forever, "ForeverGPS")
    Mkdir(forever .. "/Interface/AddOns/ForeverGPS/Core")
    T.ok(Run("migrate_saved.py", ('"%s"'):format(forever)), "it runs")
    local imported = forever .. "/Interface/AddOns/ForeverGPS/Core/Imported.lua"
    local env = {}
    local chunk = assert(loadfile(imported, "t", env))
    chunk()
    local data = env.ForeverGPSImported
    T.ok(data and data.id, "a stamp for applying once")
    T.ok(data.accounts[1].gpsChar["Name-Realm"].flights[6], "flight paths come across")
    T.eq(data.accounts[1].gpsChar["Name-Realm"].route.active, 2, "and the route")
    T.eq(Read(wtf), SAVED, "WTF is exactly as it was")
end

-- The real client writes no indenting, array comments, and over a megabyte of search
-- data that is not ours to keep loading.
function tests.migrating_takesOnlyWhatTheGpsKept_whateverTheFilesLayout()
    local forever = Fresh()
    local saved = table.concat({
        "", "EasyFindDB = {", '["aliases"] = {', "},", '["note"] = "a } and a \\" and a , inside",',
        '["gpsFlown"] = {', '["1"] = {', "7, -- [1]", "9, -- [2]", "},", "},",
        '["searchHistory"] = {', '["big"] = "' .. ("x"):rep(5000) .. '",', "},",
        '["gpsChar"] = {', '["Name-Realm"] = {', '["flights"] = {', "[6] = true,", "},", "},", "},",
        "}", "" }, "\r\n")
    Write(forever .. "/WTF/Account/1234#1/SavedVariables/EasyFind.lua", saved)
    Addon(forever, "ForeverGPS")
    Mkdir(forever .. "/Interface/AddOns/ForeverGPS/Core")
    T.ok(Run("migrate_saved.py", ('"%s"'):format(forever)), "it runs")
    local imported = forever .. "/Interface/AddOns/ForeverGPS/Core/Imported.lua"
    T.ok(#Read(imported) < 1000, "the rest stays behind")
    local env = {}
    assert(loadfile(imported, "t", env))()
    local data = env.ForeverGPSImported.accounts[1]
    T.eq(data.gpsFlown["1"][2], 9)
    T.ok(data.gpsChar["Name-Realm"].flights[6])
    T.eq(data.searchHistory, nil)
    T.eq(data.note, nil)
end

function tests.migrating_withNothingToCarry_writesNothing()
    local forever = Fresh()
    Addon(forever, "ForeverGPS")
    T.ok(Run("migrate_saved.py", ('"%s"'):format(forever)), "it says so and stops")
    T.no(Read(forever .. "/Interface/AddOns/ForeverGPS/Core/Imported.lua"))
end

function tests.installing_movesOurFoldersAndNoOthers()
    assert(os.execute(PYTHON .. " -I tools/package.py > " .. NULL))
    local forever = Fresh()
    for _, name in ipairs({ "EasyFind", "EasyFind_GPS", "EasyFind_Calc", "EasyFind_Snippets", "ForeverGPS", "Questie", "TomTom", "EasyFishing", "EasyFindMore" }) do
        Addon(forever, name)
    end
    Write(forever .. "/WTF/Account/1234#1/SavedVariables/EasyFind.lua", SAVED)
    local prefix = WINDOWS and "set FGPS_SKIP_GAME_CHECK=1&& " or "FGPS_SKIP_GAME_CHECK=1 "
    T.ok(os.execute(prefix .. ('%s -I tools/install_local.py "%s" > %s 2>&1'):format(PYTHON, forever, NULL)), "a look first")
    T.ok(Read(forever .. "/Interface/AddOns/EasyFind/EasyFind.toc"), "and looking moves nothing")
    T.ok(os.execute(prefix .. ('%s -I tools/install_local.py "%s" --apply > %s 2>&1'):format(PYTHON, forever, NULL)), "then for real")
    local addons = forever .. "/Interface/AddOns/"
    for _, name in ipairs({ "EasyFind", "EasyFind_GPS", "EasyFind_Calc", "EasyFind_Snippets" }) do
        T.no(Read(addons .. name .. "/" .. name .. ".toc"), name .. " has left AddOns")
    end
    for _, name in ipairs({ "Questie", "TomTom", "EasyFishing", "EasyFindMore" }) do
        T.ok(Read(addons .. name .. "/" .. name .. ".toc"), name .. " is untouched")
    end
    local toc = Read(addons .. "ForeverGPS/ForeverGPS.toc")
    T.has(toc, "Vendor/EasyFind/Core/Main.lua", "the new folder is in")
    T.ok(Read(addons .. "ForeverGPS/Vendor/EasyFind_GPS/GPS.lua"), "with its parts")
    local p = io.popen(WINDOWS and ('cmd /c "dir /b %s\\ForeverGPS-backup-*"'):format(Win(forever)) or ('ls -d %s/ForeverGPS-backup-*'):format(forever))
    local backup = p:read("l")
    p:close()
    T.ok(backup, "the old folders are kept beside it")
    local name = backup:match("([^/\\]+)$")
    T.ok(Read(forever .. "/" .. name .. "/EasyFind/EasyFind.toc"), "whole")
    T.ok(Read(forever .. "/" .. name .. "/ForeverGPS/ForeverGPS.toc"), "the old ForeverGPS among them")
    T.has(Read(addons .. "ForeverGPS/Core/Imported.lua"), "gpsChar", "and what they saved is carried over")
end

return tests
