-- The addons as the client loads them: real TOCs, real load rules, in order.
local T = require("support.t")
local Client = require("support.client")
local Stack = require("support.stack")

local function Read(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("a")
    f:close()
    return s
end

local ROOT = "addons/"
local tests = {}

function tests.everyTocFile_exists()
    for addon, path in pairs(Client.PATHS) do
        local meta, files = Client.TocLines(addon)
        T.ok(meta.Interface, addon .. " has an interface line")
        for _, file in ipairs(files) do
            T.ok(Read(path .. "/" .. file:gsub("\\", "/")), addon .. " lists a missing file: " .. file)
        end
    end
end

function tests.everyAddon_targetsThisClient()
    for _, addon in ipairs({ "EasyFind", "EasyFind_GPS", "EasyFind_Questie", "ForeverGPS" }) do
        local meta = Client.TocLines(addon)
        T.has(meta.Interface, "16001", addon)
    end
end

function tests.foreverGps_dependsOnWhatItNeeds()
    local meta = Client.TocLines("ForeverGPS")
    T.has(meta.Dependencies, "EasyFind", "needs EasyFind")
    T.has(meta.Dependencies, "EasyFind_GPS", "and GPS")
    T.has(meta.OptionalDeps, "Questie", "Questie only if there")
    T.has(meta.OptionalDeps, "TomTom", "TomTom only if there")
    T.lacks(meta.Dependencies, "Questie", "never required")
    T.lacks(meta.Dependencies, "TomTom", "never required")
    T.lacks((meta.Dependencies .. (meta.OptionalDeps or "")):lower(), "rested", "RestedXP has no place here")
    T.lacks((meta.OptionalDeps or ""):lower(), "rxp", "nor RXP")
    T.eq(meta.SavedVariables, "ForeverGPSDB")
    T.eq(meta.SavedVariablesPerCharacter, "ForeverGPSCharDB")
end

function tests.everyLuaFile_isInTheToc()
    local _, files = Client.TocLines("ForeverGPS")
    local listed = {}
    for _, f in ipairs(files) do listed[f:gsub("\\", "/")] = true end
    local isWindows = package.config:sub(1, 1) == "\\"
    local p = io.popen(isWindows and 'cmd /c "dir /s /b addons\\ForeverGPS\\*.lua"' or 'find addons/ForeverGPS -name "*.lua"')
    for line in p:lines() do
        local rel = line:gsub("\\", "/"):match("addons/ForeverGPS/(.+)$")
        T.ok(listed[rel], "not in the toc: " .. tostring(rel))
    end
    p:close()
end

function tests.filesLoadInAnOrderTheirNeedsAllow()
    local _, files = Client.TocLines("ForeverGPS")
    local at = {}
    for i, f in ipairs(files) do at[f] = i end
    T.ok(at["Locales/enUS.lua"] < at["Core/Namespace.lua"], "text first: Namespace reads FG.L at call time only")
    T.ok(at["Core/Bridge.lua"] < at["Core/Eta.lua"])
    T.ok(at["Core/Eta.lua"] < at["Core/QuestTargets.lua"])
    T.ok(at["Core/Quests.lua"] < at["Core/QuestTargets.lua"])
    T.ok(at["UI/Theme.lua"] < at["UI/Kit.lua"])
    T.ok(at["UI/Kit.lua"] < at["UI/List.lua"])
    T.ok(at["UI/List.lua"] < at["UI/RoutePanel.lua"])
    T.ok(at["UI/RoutePanel.lua"] < at["UI/MainWindow.lua"])
end

function tests.foreverLoads_onlyForeversData()
    local _, files = Client.TocLines("EasyFind_GPS")
    local joined = table.concat(files, " ")
    T.has(joined, "Data_Forever.lua", "Forever's routes")
    T.has(joined, "Walk_Kalimdor.lua", "Forever's grid")
    T.lacks(joined, "Data_Era.lua", "not Era's")
    T.lacks(joined, "Walk_Kalimdor_TBC.lua", "not TBC's")
    T.lacks(joined, "Npcs_Retail.lua", "not retail's")
end

function tests.theWholeStack_loadsWithoutAnError()
    local c = Stack.new({})
    T.eq(#c.errors, 0, tostring(c.errors[1]))
    T.ok(c.FG.Bridge.Ready(), "and finds everything it needs: " .. table.concat(c.FG.Bridge.Missing(), ", "))
end

function tests.withoutQuestie_nothingComplains()
    local c = Stack.new({ withQuestieAddon = true })
    T.eq(#c.errors, 0, tostring(c.errors[1]))
    T.no(c.FG.QuestTargets.HasQuestie())
end

function tests.withoutEasyFindGps_itSaysSoAndStaysUp()
    local c = Client.new({})
    c:LoadAddon("EasyFind")
    c:LoadAddon("ForeverGPS")
    c:Login()
    local FG = c.env.ForeverGPS
    T.ok(#FG.Bridge.Missing() > 0, "knows what is missing")
    T.no(FG.Bridge.Ready())
    FG.Planner.Inspect({ data = { name = "x", mapID = 1453, x = 0.5, y = 0.5 }, name = "x" })
    T.eq(FG.Planner.Current().status, "failed", "a plan fails plainly")
    T.has(table.concat(c.printed, "\n"), "not ready", "and the player is told")
end

function tests.allArtUsed_exists()
    local isWindows = package.config:sub(1, 1) == "\\"
    local cmd = isWindows and 'cmd /c "dir /s /b addons\\ForeverGPS\\*.lua"' or 'find addons/ForeverGPS -name "*.lua"'
    local p = io.popen(cmd)
    local used = {}
    for line in p:lines() do
        local src = Read(line) or ""
        for name in src:gmatch('SetIcon%("([%w%-]+)"%)') do used[name] = true end
        for name in src:gmatch('icon%s*=%s*"([%w%-]+)"') do used[name] = true end
        for name in src:gmatch('iconArt%s*=%s*"([%w%-]+)"') do used[name] = true end
        for name in src:gmatch('FG%.ART%s*%.%.%s*"([%w%-]+)"') do used[name] = true end
    end
    p:close()
    local count = 0
    for name in pairs(used) do
        count = count + 1
        T.ok(Read(ROOT .. "ForeverGPS/Art/" .. name .. ".tga"), "missing art: " .. name)
    end
    T.ok(count > 15, "the scan found the art: " .. count)
end

function tests.textures_areWhatTheClientTakes()
    local isWindows = package.config:sub(1, 1) == "\\"
    local p = io.popen(isWindows and 'cmd /c "dir /b addons\\ForeverGPS\\Art\\*.tga"' or 'ls addons/ForeverGPS/Art/')
    local n = 0
    for line in p:lines() do
        local data = Read(ROOT .. "ForeverGPS/Art/" .. line:match("([^/\\]+)$"))
        T.ok(data and #data > 18, line)
        local w, h = data:byte(13) + data:byte(14) * 256, data:byte(15) + data:byte(16) * 256
        T.eq(data:byte(3), 2, line .. " is uncompressed true color")
        T.eq(data:byte(17), 32, line .. " has alpha")
        T.eq(w, h, line .. " is square")
        T.eq(w & (w - 1), 0, line .. " is a power of two")
        n = n + 1
    end
    p:close()
    T.ok(n >= 30, "textures found: " .. n)
end

function tests.fontsItAsksFor_ship()
    for _, file in ipairs({ "Inter-Regular.ttf", "Inter-SemiBold.ttf", "Inter-Bold.ttf" }) do
        T.ok(Read(ROOT .. "EasyFind/Fonts/" .. file), file)
    end
end

return tests
