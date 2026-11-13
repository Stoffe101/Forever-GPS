-- Small assertions and a suite runner.
local T = {}

local function Fail(message, level) error(message, (level or 1) + 2) end

function T.eq(actual, expected, label)
    if actual ~= expected then
        Fail(("%s: expected %s, got %s"):format(label or "eq", tostring(expected), tostring(actual)))
    end
end

function T.ok(value, label)
    if not value then Fail(label or "expected a true value") end
end

function T.no(value, label)
    if value then Fail((label or "expected a false value") .. ": got " .. tostring(value)) end
end

function T.near(actual, expected, tolerance, label)
    if not (actual and math.abs(actual - expected) <= tolerance) then
        Fail(("%s: expected %s within %s, got %s"):format(label or "near", tostring(expected), tostring(tolerance), tostring(actual)))
    end
end

function T.has(text, part, label)
    if not tostring(text):find(part, 1, true) then
        Fail(("%s: %q not in %q"):format(label or "has", tostring(part), tostring(text)))
    end
end

function T.lacks(text, part, label)
    if tostring(text):find(part, 1, true) then
        Fail(("%s: %q should not be in %q"):format(label or "lacks", tostring(part), tostring(text)))
    end
end

-- suite: { name = function, ... }, run in name order so results read the same.
function T.Run(file, suite)
    local names = {}
    for name in pairs(suite) do names[#names + 1] = name end
    table.sort(names)
    print("== " .. file .. " ==")
    local pass, fail, failures = 0, 0, {}
    for _, name in ipairs(names) do
        local ok, err = xpcall(suite[name], debug.traceback)
        if ok then
            pass = pass + 1
            print("  ok   " .. name)
        else
            fail = fail + 1
            failures[#failures + 1] = file .. " " .. name .. ": " .. tostring(err):match("^[^\n]*")
            print("  FAIL " .. name)
            print("       " .. tostring(err):gsub("\n", "\n       "))
        end
    end
    return pass, fail, failures
end

return T
