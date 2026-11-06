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

function tests.theAddon_targetsThisClient()
    local meta = Client.TocLines("ForeverGPS")
    T.eq(meta.Interface, "16001", "this client alone")
    T.has(meta.Title, "Forever-GPS")
end

function tests.foreverGps_dependsOnNothing()
    local meta = Client.TocLines("ForeverGPS")
    T.no(meta.Dependencies, "one folder stands alone")
    T.no(meta.RequiredDeps, "one folder stands alone")
    T.has(meta.OptionalDeps, "Questie", "Questie only if there")
    T.has(meta.OptionalDeps, "TomTom", "TomTom only if there")
    T.lacks((meta.OptionalDeps or ""):lower(), "rested", "RestedXP has no place here")
    T.lacks((meta.OptionalDeps or ""):lower(), "rxp", "nor RXP")
    T.lacks(meta.OptionalDeps, "EasyFind", "nothing else of ours to wait for")
end

function tests.everySavedVariable_isDeclared()
    local meta = Client.TocLines("ForeverGPS")
    for _, name in ipairs({ "ForeverGPSDB", "EasyFindDB", "EasyFindQuestieDB" }) do T.has(meta.SavedVariables, name) end
    for _, name in ipairs({ "ForeverGPSCharDB", "EasyFindCharDB" }) do T.has(meta.SavedVariablesPerCharacter, name) end
end

function tests.preflightComesFirst_andForeverGpsLast()
    local _, files = Client.TocLines("ForeverGPS")
    T.eq(files[1], "Core/Preflight.lua", "it must hear the saved variables first")
    local at = {}
    for i, f in ipairs(files) do at[f] = i end
    T.ok(at["Vendor/EasyFind/Core/Main.lua"] < at["Vendor/EasyFind_GPS/GPS.lua"], "EasyFind before its GPS")
    T.ok(at["Vendor/EasyFind_GPS/GPS.lua"] < at["Vendor/EasyFind_Questie/Quests.lua"], "as the old load order had it")
    T.ok(at["Vendor/EasyFind_Questie/Namespace.lua"] < at["Vendor/EasyFind_Questie/Locales/enUS.lua"], "its table before its files")
    T.ok(at["Vendor/EasyFind_Questie/Quests.lua"] < at["Core/Namespace.lua"], "and Forever-GPS on top")
end

function tests.theFolder_isOneAddon()
    local isWindows = package.config:sub(1, 1) == "\\"
    local cmd = isWindows and 'cmd /c "dir /s /b build\\assembled\\ForeverGPS\\*.toc"' or 'find build/assembled/ForeverGPS -name "*.toc"'
    local p = io.popen(cmd)
    local tocs = {}
    for line in p:lines() do tocs[#tocs + 1] = line:gsub("\\", "/") end
    p:close()
    T.eq(#tocs, 1, "one TOC, not addons nested in a folder: " .. table.concat(tocs, ", "))
    T.has(tocs[1], "ForeverGPS/ForeverGPS.toc")
end

function tests.noFile_pointsAtTheOldFolders()
    local _, files = Client.TocLines("ForeverGPS")
    for _, file in ipairs(files) do
        local src = Read("build/assembled/ForeverGPS/" .. file) or ""
        T.no(src:find("AddOns\\\\EasyFind", 1, true), file .. " still names an old folder")
        T.no(src:find("AddOns/EasyFind", 1, true), file .. " still names an old folder")
    end
end

function tests.everyVendoredPart_keepsItsLicense()
    for _, addon in ipairs({ "EasyFind", "EasyFind_GPS", "EasyFind_Questie" }) do
        local here = Read("build/assembled/ForeverGPS/Vendor/" .. addon .. "/LICENSE")
        T.ok(here and #here > 100, addon .. " carries its license")
        T.eq(here, Read("addons/" .. addon .. "/LICENSE"), "unchanged")
    end
end

function tests.vendoredTextures_exist()
    local _, files = Client.TocLines("ForeverGPS")
    local missing = {}
    for _, file in ipairs(files) do
        local src = Read("build/assembled/ForeverGPS/" .. file) or ""
        for path in src:gmatch('"Interface\\\\AddOns\\\\ForeverGPS\\\\Vendor\\\\([%w_\\%-%.]+)"') do
            local rel = path:gsub("\\\\", "/")
            -- A literal naming a whole file, with or without its extension.
            -- ForeverBand is the start of five names, which Utils.lua finishes.
            if not rel:find("/$") and not rel:find("ForeverBand$") and not (Read("build/assembled/ForeverGPS/Vendor/" .. rel) or Read("build/assembled/ForeverGPS/Vendor/" .. rel .. ".tga")
                or Read("build/assembled/ForeverGPS/Vendor/" .. rel .. ".blp")) then
                missing[rel] = file
            end
        end
    end
    local list = {}
    for rel, file in pairs(missing) do list[#list + 1] = rel .. " (" .. file .. ")" end
    table.sort(list)
    T.eq(#list, 0, "named but not shipped: " .. table.concat(list, "; "))
end

function tests.aLogin_saysNothingAboutWhatIsGone()
    local c = Stack.new({})
    c:Advance(12)
    local said = table.concat(c.printed, "\n")
    T.lacks(said:lower(), "easyfind", "no talk of the old addons: " .. said)
    T.lacks(said:lower(), "disabled", "or of parts switched off")
    T.eq(#c.errors, 0, tostring(c.errors[1]))
end

function tests.noPartOfTheFolder_asksAfterAnAddonThatIsGone()
    -- The client's answer for a missing addon is not to be relied on. A vendored file that
    -- asks at load would stop there in the real game.
    local c = Stack.new({})
    c:Advance(2)
    T.eq(#c.errors, 0, tostring(c.errors[1]))
    local report = c.FG.Diagnostics.Report()
    T.has(report, "Built on: EasyFind 5.2.0", "the parts, from the build")
    T.has(report, "Memory:", "and the one addon's memory")
end

function tests.nothingListensForUpdatesThatAreNotOurs()
    local _, files = Client.TocLines("ForeverGPS")
    local joined = table.concat(files, " ")
    T.lacks(joined, "VersionCheck", "EasyFind's update notices stay out")
    T.lacks(joined, "EasyFind_GPS/Guard.lua", "and its version guard")
end

function tests.oldFoldersLeftBehind_areCaught()
    local c = Client.new({})
    c.addons.EasyFind = true
    c.addons.EasyFind_GPS = true
    c:LoadAddon("ForeverGPS", function(file) return file:find("^UI/") end)
    local old = c.env.ForeverGPSPreflight.old
    T.eq(#old, 2, "both seen")
end

function tests.withANewSavedVariablesFile_theSearchBarStaysAway()
    local c = Stack.new({})
    local ef = c.env.EasyFind.db
    T.eq(ef.visible, false, "EasyFind's own bar stays hidden")
    T.ok(ef.tutorialDone, "and its welcome stays away")
    T.eq(#c.errors, 0)
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
    T.ok(at["Core/Namespace.lua"] < at["Locales/enUS.lua"], "the namespace, then what goes in it")
    T.ok(at["Core/Bridge.lua"] < at["Core/Eta.lua"])
    T.ok(at["Core/Eta.lua"] < at["Core/QuestTargets.lua"])
    T.ok(at["Core/Quests.lua"] < at["Core/QuestTargets.lua"])
    T.ok(at["UI/Theme.lua"] < at["UI/Kit.lua"])
    T.ok(at["UI/Kit.lua"] < at["UI/List.lua"])
    T.ok(at["UI/List.lua"] < at["UI/RoutePanel.lua"])
    T.ok(at["UI/RoutePanel.lua"] < at["UI/MainWindow.lua"])
end

function tests.foreverLoads_onlyForeversData()
    local _, files = Client.TocLines("ForeverGPS")
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
    local c = Stack.new({})
    T.eq(#c.errors, 0, tostring(c.errors[1]))
    T.no(c.FG.QuestTargets.HasQuestie())
end

function tests.withoutEasyFindGps_itSaysSoAndStaysUp()
    local c = Client.new({})
    c:LoadAddon("ForeverGPS", function(file) return file:find("^Vendor/EasyFind_GPS/") end)
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
        T.ok(Read("build/assembled/ForeverGPS/Vendor/EasyFind/Fonts/" .. file), file)
    end
end

return tests
