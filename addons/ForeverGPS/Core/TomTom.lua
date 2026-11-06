-- Optional: when chosen as the arrow, TomTom points at the current step's end.
-- One waypoint at a time, never left behind, and nothing at all without TomTom.
local _, FG = ...
local Mirror = {}
FG.TomTom = Mirror

local uid, shownKey

function Mirror.Available()
    local T = _G.TomTom
    return type(T) == "table" and type(T.AddWaypoint) == "function" and type(T.RemoveWaypoint) == "function"
end

local function Remove()
    if uid and Mirror.Available() then pcall(_G.TomTom.RemoveWaypoint, _G.TomTom, uid) end
    uid, shownKey = nil, nil
end
Mirror.Remove = Remove

-- The current step's end, as a map spot; nil on a ride, where a straight line
-- to the far dock means nothing.
local function StepSpot(view)
    local step = view and view.step
    if not (step and view.pointing and view.state == "moving") then return nil end
    return step.mapID, step.x, step.y
end

local function Sync(view)
    if not (Mirror.Available() and FG.Journey.ArrowMode() == "tomtom") then
        return Remove()
    end
    local mapID, x, y = StepSpot(view)
    if not (mapID and x and y) then return Remove() end
    local key = ("%d:%.4f:%.4f"):format(mapID, x, y)
    if key == shownKey then return end
    Remove()
    local ok, id = pcall(_G.TomTom.AddWaypoint, _G.TomTom, mapID, x, y, {
        title = view.title, from = "Forever-GPS", persistent = false, silent = true, crazy = true,
        minimap = false, world = false,
    })
    if ok then uid, shownKey = id, key end
end

FG.On("journey:step", Sync)
FG.On("arrow:changed", function()
    Sync(FG.Journey.View())
end)
FG.On("route:cleared", Remove)
FG.On("route:arrived", Remove)
