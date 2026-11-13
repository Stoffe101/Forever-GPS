-- A journey looked at from somewhere else ("from Ironforge to Goldshire"), why a way was
-- chosen, a fare never seen, and the report a player can paste.
local T = require("support.t")
local Stack = require("support.stack")

local GOLDSHIRE = { name = "Goldshire", mapID = 1429, x = 0.42, y = 0.65 }
local IRONFORGE = { name = "Ironforge", mapID = 1455, x = 0.55, y = 0.48 }

local function Start(opts)
    opts = opts or {}
    opts.mapID, opts.x, opts.y = opts.mapID or 1453, opts.x or 0.6, opts.y or 0.6
    if opts.ui == nil then opts.ui = false end
    return Stack.new(opts)
end

local function Ready(c)
    return Stack.Until(c, function() return c.FG.Planner.Current() and c.FG.Planner.Current().status == "ready" end, 60)
end

local function Near(here, place, c, yards)
    local ci, wx, wy = c.FG.Bridge.WorldPos(place.mapID, place.x, place.y)
    return here and here.ci == ci and ((here.wx - wx) ^ 2 + (here.wy - wy) ^ 2) ^ 0.5 <= (yards or 300)
end

local tests = {}

function tests.aJourneyFromElsewhere_isPlannedFromThere()
    local c = Start()
    local P = c.FG.Planner
    P.Inspect({ data = GOLDSHIRE, name = "Goldshire", from = IRONFORGE })
    T.ok(Ready(c), "planned")
    local option = P.Current().selected
    T.ok(Near(option.from, IRONFORGE, c), "from Ironforge, not from where the player stands")
    T.ok(c.FG.Bridge.CustomStart(), "the engine plans from there")
    P.Clear()
    T.eq(c.FG.Bridge.CustomStart(), nil, "and forgets it when the preview goes")
end

function tests.startingIt_waitsAtItsStart_andPlansFromThePlayerAfter()
    local c = Start()
    local P = c.FG.Planner
    P.Inspect({ data = GOLDSHIRE, name = "Goldshire", from = IRONFORGE })
    T.ok(Ready(c))
    T.ok(P.Start())
    T.ok(Stack.Until(c, function() return c.FG.Bridge.ActiveRoute() ~= nil end, 60), "started")
    local route = c.FG.Bridge.ActiveRoute()
    T.ok(route.origin, "the route knows it starts elsewhere")
    T.eq(c.FG.Bridge.CustomStart(), nil, "the start went with the route")
    local ns = c.FG.Bridge.NS()
    local rerouted = 0
    local real = ns.GPS.Rerouted
    ns.GPS.Rerouted = function(...) rerouted = rerouted + 1 return real(...) end
    for _ = 1, 15 do c:Advance(1) end
    T.eq(rerouted, 0, "far from its start, it waits rather than replanning")
    ns.GPS.Rerouted = real
end

function tests.aSearch_canAskFromSomewhere()
    local c = Start()
    c:Advance(1)
    c.FG.Bridge.WarmSearch()
    c:Advance(2)
    local results, info = c.FG.Search.Run("from Ironforge to Goldshire", "all")
    T.ok(info.from, "a start was found")
    T.ok(info.from.name:find("Ironforge", 1, true), info.from.name)
    T.ok(#results > 0, "and places to go")
    T.ok(results[1].from == info.from, "each result carries it")
    local target = c.FG.Search.Target(results[1])
    T.eq(target.from, info.from, "and so does the plan")
    local _, missing = c.FG.Search.Run("from Nowhereville Qqq to Goldshire", "all")
    T.ok(missing.fromMissing, "an unknown start is said, not ignored")
    local _, plain = c.FG.Search.Run("Goldshire", "all")
    T.eq(plain.from, nil)
end

function tests.aWay_saysWhyItWasChosen()
    local c = Start()
    local P = c.FG.Planner
    P.Inspect({ data = GOLDSHIRE, name = "Goldshire" })
    T.ok(Ready(c))
    local plan = P.Current()
    local why = P.Explain(plan, plan.selected)
    T.ok(why and (why:find("quickest", 1, true) or why:find("only way", 1, true)), tostring(why))
    for _, option in ipairs(plan.options) do
        if option.steps and option.mode.key == "overland" then
            T.eq(P.Explain(plan, option), c.FG.L["WHY_OVERLAND"])
        end
    end
end

function tests.aFareNeverSeen_isUnknown_notFree()
    local c = Start()
    local F = c.FG.Fares
    local cost = F.RouteCost({ { kind = "taxi" } })
    T.eq(cost.unknown, 1)
    T.eq(F.Label(cost), c.FG.L["COST_UNKNOWN"], "not free, not ~0")
    T.eq(F.Note(cost), c.FG.L["COST_UNKNOWN_NOTE"])
    T.eq(F.Label(F.RouteCost({ { kind = "travel" } })), c.FG.L["COST_FREE"], "walking is free")
end

function tests.theReport_saysWhereNavigationStands()
    local c = Start()
    local P = c.FG.Planner
    P.Inspect({ data = GOLDSHIRE, name = "Goldshire" })
    T.ok(Ready(c))
    P.Start()
    Stack.Until(c, function() return c.FG.Bridge.ActiveRoute() ~= nil end, 60)
    local text = c.FG.Diagnostics.Report()
    T.ok(text:find("Navigation: on plan", 1, true), "the continuity state")
    T.ok(text:find("HUD: ", 1, true), "what the HUD says")
    T.ok(text:find("Prices: scan idle", 1, true), "the price scan")
    T.ok(text:find("Trainer window: not opened yet", 1, true))
    c:SetPlayer(1455, 0.55, 0.48)
    c:Advance(1.2)
    text = c.FG.Diagnostics.Report()
    T.ok(text:find("Navigation: recalculating (jump)", 1, true) or text:find("Navigation: on plan", 1, true), "after a jump")
end

return tests
