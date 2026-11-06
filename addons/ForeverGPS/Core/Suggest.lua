-- What might be useful right now, worked out from what is already known: quests ready to
-- hand in, things to do close by, flight paths not yet learned, the way back to the
-- hearth. Offered on the home view and never acted on by itself. Each line reads tables
-- that already exist, so asking costs nothing worth measuring.
local FG = ForeverGPS
local Suggest = {}
FG.Suggest = Suggest

local Bridge, Quests, Targets, Trip = FG.Bridge, FG.Quests, FG.QuestTargets, FG.Trip
local L = FG.L

local FLIGHT_NEAR_YARDS = 2500   -- a flight path this close is worth a detour

local function ReadyQuests()
    local n = 0
    for _, q in ipairs(Quests.All()) do
        if q.complete and not q.failed then n = n + 1 end
    end
    return n
end

-- Flight paths to learn on this continent, near enough to matter.
function Suggest.NearbyFlights()
    local start = Bridge.PlayerStart()
    if not (start and Bridge.KnownFlights()) then return {} end
    local out = {}
    for _, node in ipairs(Bridge.UnlearnedFlights()) do
        if node.ci == start.ci then
            local yards = ((node.wx - start.wx) ^ 2 + (node.wy - start.wy) ^ 2) ^ 0.5
            if yards <= FLIGHT_NEAR_YARDS then out[#out + 1] = node end
        end
    end
    return out
end

-- The lines to show, most useful first. Each: { icon, text, sub, run }.
function Suggest.List()
    local out = {}
    local ready = ReadyQuests()
    if ready > 0 then
        out[#out + 1] = { icon = "turnin", text = L[ready == 1 and "SUGGEST_READY_ONE" or "SUGGEST_READY_FMT"]:format(ready), run = function()
            FG.Window.Show("quests")
            FG.QuestsView.SetFilter("ready")
        end }
    end
    local near = #Trip.NearbyStops()
    if near >= 2 then
        out[#out + 1] = { icon = "quest", text = L["SUGGEST_CIRCUIT_FMT"]:format(near), sub = L["SUGGEST_CIRCUIT_SUB"], run = Trip.PlanNearby }
    end
    local flights = Suggest.NearbyFlights()
    if #flights > 0 then
        out[#out + 1] = { icon = "flight", text = L[#flights == 1 and "SUGGEST_FLIGHT_ONE" or "SUGGEST_FLIGHT_FMT"]:format(#flights), run = function()
            FG.Window.Show("search")
            FG.SearchView.Query("flights to learn")
        end }
    end
    local hearth = Bridge.HearthSpot()
    if hearth then
        out[#out + 1] = { icon = "hearth", text = L["SUGGEST_HEARTH_FMT"]:format(hearth.name), run = function()
            FG.Planner.Inspect({ data = hearth, name = hearth.name, subtitle = L["SUGGEST_HEARTH_SUB"], icon = "hearth" })
            FG.Window.ShowRoute()
        end }
    end
    return out
end
