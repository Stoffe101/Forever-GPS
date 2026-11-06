-- What each way of travel is called and drawn as, and the one-line shape of a
-- route. The step kinds are the route engine's own.
local _, FG = ...
local Kinds = {}
FG.Kinds = Kinds

local L = FG.L

-- icon: a file in Art/. ride: the player is carried once aboard.
local INFO = {
    travel = { icon = "walk", label = "KIND_WALK" },
    taxi = { icon = "flight", label = "KIND_FLIGHT", ride = true },
    boat = { icon = "boat", label = "KIND_BOAT", ride = true },
    ferry = { icon = "boat", label = "KIND_BOAT", ride = true },
    zeppelin = { icon = "zeppelin", label = "KIND_ZEPPELIN", ride = true },
    skyship = { icon = "zeppelin", label = "KIND_SKYSHIP", ride = true },
    tram = { icon = "tram", label = "KIND_TRAM", ride = true },
    portal = { icon = "portal", label = "KIND_PORTAL" },
    teleport = { icon = "hearth", label = "KIND_TELEPORT" },
    elevator = { icon = "lift", label = "KIND_LIFT" },
    enter = { icon = "door", label = "KIND_BUILDING" },
    leave = { icon = "door", label = "KIND_BUILDING" },
    learn = { icon = "flight", label = "KIND_LEARN" },
    seam = { icon = "walk", label = "KIND_WALK" },
}

function Kinds.Info(step)
    local info = INFO[step and step.kind] or INFO.travel
    if step and step.corpse then return { icon = "corpse", label = "KIND_CORPSE" } end
    return info
end

function Kinds.Icon(step) return FG.ART .. Kinds.Info(step).icon end
function Kinds.Label(step) return L[Kinds.Info(step).label] end
function Kinds.IsRide(step) return Kinds.Info(step).ride == true end

-- A route's shape: adjacent walks fold into one segment, each with its time.
-- { { kind, icon, sec }, ... }
function Kinds.Segments(steps)
    local out = {}
    for i = 1, steps and #steps or 0 do
        local step = steps[i]
        local info = Kinds.Info(step)
        local last = out[#out]
        if last and last.icon == info.icon then
            last.sec = last.sec + (step.sec or 0)
        else
            out[#out + 1] = { kind = step.kind, icon = info.icon, sec = step.sec or 0 }
        end
    end
    return out
end

-- The transports a route takes, for one line: "Boat, Flight".
function Kinds.Summary(steps)
    local seen, out = {}, {}
    for i = 1, steps and #steps or 0 do
        local step = steps[i]
        if step.kind ~= "travel" and step.kind ~= "seam" and step.kind ~= "enter" and step.kind ~= "leave" then
            local label = Kinds.Label(step)
            if not seen[label] then
                seen[label] = true
                out[#out + 1] = label
            end
        end
    end
    if #out == 0 then return L["KIND_WALK"] end
    return table.concat(out, ", ")
end
