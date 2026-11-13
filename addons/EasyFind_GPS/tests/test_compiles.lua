-- Every file the toc lists compiles: past 200 locals in one function the
-- client refuses the whole file ("main function has more than 200 local
-- variables"), and nothing else runs it whole (GPS.lua, 2026-11-06).
local H = require("Harness")

local tests = {}

function tests.everyTocFileCompiles()
    local files, ok = H.TocFiles("EasyFind_GPS.toc")
    H.assertTrue(ok, "EasyFind_GPS.toc readable")
    H.assertTrue(#files > 0, "the toc lists files")
    for _, file in ipairs(files) do
        local f = assert(io.open(H.Path(file), "rb"), file .. " missing")
        local src = f:read("a")
        f:close()
        local chunk, err = load(src, "=" .. file, "t", {})
        H.assertTrue(chunk ~= nil, tostring(err))
    end
end

local pass, fail, failures = H.runSuite("Compiles", tests)
return { pass = pass, fail = fail, failures = failures }
