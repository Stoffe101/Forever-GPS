-- Runs every tests/test_*.lua. From the repository root: lua tests/run.lua
-- Optionally a word: lua tests/run.lua quests runs the files with it in their name.
package.path = "tests/?.lua;" .. package.path

local filter = arg and arg[1]

local function ListFiles()
    local files = {}
    local isWindows = package.config:sub(1, 1) == "\\"
    local handle = io.popen(isWindows and 'cmd /c "dir /b tests\\test_*.lua"' or 'ls tests/test_*.lua')
    for line in handle:lines() do
        local name = line:match("([^/\\]+)$")
        if not filter or name:find(filter, 1, true) then files[#files + 1] = "tests/" .. name end
    end
    handle:close()
    table.sort(files)
    return files
end

-- Tests run against the folder that ships, so it is put together first.
local PYTHON = os.getenv("FGPS_PYTHON") or (package.config:sub(1, 1) == "\\" and "python" or "python3")
assert(os.execute(PYTHON .. " -I tools/assemble.py --quiet"), "tools/assemble.py failed")

local totalPass, totalFail, failures = 0, 0, {}
local T = require("support.t")

for _, file in ipairs(ListFiles()) do
    local chunk, err = loadfile(file)
    if not chunk then
        totalFail = totalFail + 1
        failures[#failures + 1] = file .. ": " .. tostring(err)
        print("LOAD ERROR " .. file .. ": " .. tostring(err))
    else
        local ok, suite = xpcall(chunk, debug.traceback)
        if not ok then
            totalFail = totalFail + 1
            failures[#failures + 1] = file .. ": " .. tostring(suite)
            print("RUN ERROR " .. file .. ": " .. tostring(suite))
        elseif type(suite) == "table" then
            local pass, fail, list = T.Run(file, suite)
            totalPass, totalFail = totalPass + pass, totalFail + fail
            for i = 1, #list do failures[#failures + 1] = list[i] end
        end
    end
end

print("")
print(string.format("== Results: %d passed, %d failed ==", totalPass, totalFail))
for i = 1, #failures do print("  FAIL " .. failures[i]) end
if totalFail > 0 then os.exit(1) end
