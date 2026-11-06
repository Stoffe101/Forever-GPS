-- How numbers read. Pure functions: no client state.
local FG = ForeverGPS
local Format = {}
FG.Format = Format

local L = FG.L
local mfloor = math.floor

-- A travel time for planning: "<1 min", "12 min", "1 hr 5 min".
function Format.Duration(sec)
    if not sec then return nil end
    if sec < 60 then return L["TIME_LESS_MIN"] end
    local minutes = mfloor(sec / 60 + 0.5)
    if minutes < 60 then return L["TIME_MIN"]:format(minutes) end
    local hours, rest = mfloor(minutes / 60), minutes % 60
    if rest == 0 then return L["TIME_HR"]:format(hours) end
    return L["TIME_HR_MIN"]:format(hours, rest)
end

-- An estimate for a list: "~12 min", or "<1 min", which needs no tilde.
function Format.About(sec)
    if not sec then return nil end
    if sec < 60 then return L["TIME_LESS_MIN"] end
    return L["ETA_SHORT_FMT"]:format(Format.Duration(sec))
end

-- A countdown for what is happening now: "0:45", "12:05".
function Format.Clock(sec)
    if not sec then return nil end
    sec = mfloor(math.max(0, sec) + 0.5)
    return ("%d:%02d"):format(mfloor(sec / 60), sec % 60)
end

-- A distance. Rounded so it does not flicker as the player moves.
function Format.Yards(yards)
    if not yards then return nil end
    if yards < 20 then return L["YARDS"]:format(mfloor(yards + 0.5)) end
    if yards < 1000 then return L["YARDS"]:format(mfloor(yards / 10 + 0.5) * 10) end
    return L["KILOYARDS"]:format(yards / 1000)
end

-- Map fractions as the numbers players type: 45.2, 60.1.
function Format.Coords(x, y)
    return ("%.1f, %.1f"):format(x * 100, y * 100)
end
