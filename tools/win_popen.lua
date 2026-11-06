-- Windows only, for running the test suites locally. Upstream tests shell out
-- with POSIX commands (ls globs, find, git), which cmd.exe does not expand.
-- This hands each one to Git Bash instead. CI on Linux never loads this file.
local bash, tmp = os.getenv("FGPS_BASH"), os.getenv("FGPS_TMP")
if not (bash and tmp) then return end
local real, n = io.popen, 0
io.popen = function(cmd, mode)
    if cmd:find("^cmd /c") then return real(cmd, mode) end
    n = n + 1
    local path = string.format("%s/popen-%d.sh", tmp, n)
    local f = assert(io.open(path, "wb"))
    f:write(cmd, "\n")
    f:close()
    return real(string.format('""%s" "%s""', bash, path), mode)
end
