-- GPS's settings rows in EasyFind's search bar come from its declaration
-- (OptionsPage.Rows), never from the built settings page: the five the
-- window gave stay (fixture from /efd optrows), and every row reads and
-- writes with no window.
local H = require("Harness")

local function source(path)
    local f = assert(io.open(H.Path(path), "rb"))
    local src = f:read("*a")
    f:close()
    return src
end

local function slice(src, from, to)
    local s = assert(src:find(from, 1, true), from .. " not found")
    local e = assert(src:find(to, s + #from, true), to .. " not found")
    return src:sub(s, e - 1)
end

-- EasyFind's words, then GPS's own over them.
local function Rows()
    local env = H.newEnv()
    local ns = H.newNs(env)
    ns.L = {}
    assert(loadfile(H.EASYFIND_ROOT .. "/Locales/enUS.lua", "t", env))("EasyFind", ns)
    env.EasyFind = { _ns = ns, db = {}, API = {} }
    assert(loadfile(H.Path("Locales/enUS.lua"), "t", env))("EasyFind_GPS", {})
    setmetatable(ns.L, { __index = function(_, k) return k end })
    local L, Utils = ns.L, ns.Utils
    Utils.OffOrNil = function(on) if on then return nil end return false end
    ns.SettingsRows = { Under = function(heading, name) return (heading:gsub(":%s*$", "")) .. ": " .. name end }
    ns.GPSWorldPin = { Style = function() return "flame" end, DefaultStyle = function() return "calm" end }
    ns.GOLD_COLOR = { 1, 0.82, 0 }
    local db = {}
    local gpsSrc = source("GPS.lua")
    local gpsEnv = setmetatable({ L = L, Utils = Utils, ns = ns, DB = function() return db end, Refresh = function() end,
        Route = function() end, Reroute = function() end,
        GPS = { CogMode = function() return "hover" end, ApplyCogs = function() end } }, { __index = env })
    local rows = assert(load(slice(gpsSrc, "local TEXT_SIZES = ", "\n") .. "\n"
        .. slice(gpsSrc, "-- The ways of travel a route may avoid", "-- The menu row hiding the steps already done")
        .. slice(gpsSrc, "local OptionsPage = {}", "\n-- The extension: its tile opens")
        .. "\nreturn OptionsPage.Rows", "=GPS rows", "t", gpsEnv))()()
    return rows, db
end

local function LabelMatches(label, name)
    if label == name then return true end
    local cut = label:match("^(.-)%.%.%.$")
    return cut ~= nil and cut ~= "" and name:sub(1, #cut) == cut
end

local tests = {}

function tests.theWindowsRowsAllStay()
    local rows = Rows()
    local baseline = dofile(H.Path("tests/fixtures/options_rows_baseline.lua"))
    local missing, wanted = {}, 0
    for _, b in ipairs(baseline) do
        if b[2] == "GPS" then
            wanted = wanted + 1
            local found = false
            for _, row in ipairs(rows) do
                if row.control.kind == b[4] and LabelMatches(b[3], row.name) then found = true end
            end
            if not found then missing[#missing + 1] = table.concat(b, " | ") end
        end
    end
    H.assertTrue(wanted > 0, "the baseline lists GPS's rows")
    H.assertEq(table.concat(missing, "; "), "", "rows the window had and the declarations lack")
end

function tests.everyRowWorksWithNoWindow()
    local rows, db = Rows()
    H.assertTrue(#rows > 0, "GPS declares rows")
    local seen = {}
    for _, row in ipairs(rows) do
        local c = row.control
        H.assertFalse(seen[row.name] == true, row.name .. " twice")
        seen[row.name] = true
        if c.kind == "button" then
            H.assertEq(type(c.press), "function", row.name .. " press")
        else
            H.assertNotNil(c.get(), row.name .. " get")
            if c.kind == "choice" then H.assertTrue(#c.choices > 0, row.name .. " choices") end
        end
    end
    for _, row in ipairs(rows) do
        if row.name == "Beacon style" then
            H.assertEq(row.control.get(), "flame", "the beacon row reads the beacon's style")
            row.control.set("off")
            H.assertEq(db.gpsWorldPin, false, "a choice row writes the saved setting")
        end
    end
end

local pass, fail, failures = H.runSuite("GPSSettingsRows", tests)
return { pass = pass, fail = fail, failures = failures }
