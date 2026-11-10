-- Travel costs: fares learned from the game, money weighed in the search itself, and the
-- limits that keep "cheapest" from meaning a long walk. Everything runs on the real engine
-- and data; the fares are set by hand, since the stand-in has no flight master to ask.
local T = require("support.t")
local Stack = require("support.stack")

local LAKESHIRE = { name = "Lakeshire", mapID = 1433, x = 0.26, y = 0.55 }
local KNOWN = { [2] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true, [12] = true }

local function Start(opts)
    opts = opts or {}
    opts.mapID, opts.x, opts.y = opts.mapID or 1453, opts.x or 0.70, opts.y or 0.72
    if opts.ui == nil then opts.ui = false end
    local c = Stack.new(opts)
    local Route = c.FG.Bridge.NS().GPSRoute
    Route.recordedKnown = opts.known or KNOWN
    if Route.ForgetKnown then Route.ForgetKnown() end
    return c
end

local function Fare(c, from, to, copper, age)
    local book = c.FG.char.fares or {}
    c.FG.char.fares = book
    book[from] = book[from] or {}
    book[from][to] = { c = copper, t = c.env.time() - (age or 0) }
    c.FG.Fares.rate = nil
end

local function Plan(c, dest)
    local P = c.FG.Planner
    P.Forget()
    P.Inspect({ data = dest, name = dest.name })
    T.ok(Stack.Until(c, function()
        local p = P.Current()
        return p and (p.status == "ready" or p.status == "unreachable" or p.status == "failed")
    end, 120), "planned")
    return P.Current()
end

local function Option(plan, key)
    for _, o in ipairs(plan.options) do
        if o.mode.key == key then return o end
    end
end

local function Flies(option)
    for _, s in ipairs(option.steps or {}) do
        if s.kind == "taxi" then return true end
    end
    return false
end

local tests = {}

-- ==== fares =================================================================

function tests.aFare_isReadFromTheMastersMap()
    local c = Start()
    c.env.GetTaxiMapID = function() return 1453 end
    rawset(c.env.Enum, "FlightPathState", { Current = 0, Reachable = 1, Unreachable = 2 })
    local S = c.env.Enum.FlightPathState
    c.env.C_TaxiMap.GetAllTaxiNodes = function()
        return { { nodeID = 2, slotIndex = 1, state = S.Current }, { nodeID = 5, slotIndex = 2, state = S.Reachable },
                 { nodeID = 6, slotIndex = 3, state = S.Reachable }, { nodeID = 99, slotIndex = 4, state = S.Unreachable } }
    end
    c.env.TaxiNodeCost = function(slot) return ({ [2] = 860, [3] = 1100 })[slot] end
    T.eq(c.FG.Fares.Learn(), 2, "two flights priced")
    local copper, sure = c.FG.Fares.Of(2, 5)
    T.eq(copper, 860)
    T.eq(sure, "fresh")
    T.eq(c.FG.Fares.Of(2, 99), c.FG.Fares.Of(2, 99), "an unreachable one is not stored")
    T.eq(c.FG.char.fares[2][99], nil)
end

function tests.aFareNeverSeen_isEstimatedFromThisCharactersOwn_andSaysSo()
    local c = Start()
    local _, sure = c.FG.Fares.Of(2, 5)
    T.eq(sure, "guess", "nothing seen yet: a rough figure, said to be one")
    Fare(c, 2, 6, 1000)
    local copper, sure2 = c.FG.Fares.Of(2, 5)
    T.eq(sure2, "estimate", "now from this character's own fares")
    T.ok(copper > 0)
end

function tests.anOldFare_isMarkedStale()
    local c = Start()
    Fare(c, 2, 5, 860, 40 * 86400)
    local _, sure = c.FG.Fares.Of(2, 5)
    T.eq(sure, "stale")
end

function tests.money_readsAsPlayersSeeIt()
    local M = Start().FG.Fares.Money
    T.eq(M(8), "8c")
    T.eq(M(800), "8s")
    T.eq(M(860), "8s 60c")
    T.eq(M(12500), "1g 25s")
    T.eq(M(30000), "3g")
end

-- ==== weighing ==============================================================

function tests.withoutMoneyWays_theRoutesAreAsBefore()
    local c = Start()
    local Route = c.FG.Bridge.NS().GPSRoute
    T.eq(Route.FarePenalty(2, 5, 3000, {}), 0, "no rate, nothing added")
    T.eq(Route.FarePenalty(2, 5, 3000, nil), 0)
end

function tests.bestValue_canChooseOtherThanFastest()
    local c = Start()
    Fare(c, 2, 5, 50000)        -- five gold for one flight
    c.FG.db.travel.preset = "money"
    local plan = Plan(c, LAKESHIRE)
    local fastest, value = Option(plan, "fastest"), Option(plan, "value")
    T.ok(Flies(fastest), "the fastest flies")
    T.no(Flies(value), "best value does not pay five gold for it")
    T.ok(value.total > fastest.total, "and takes longer")
    T.eq(value.cost.sure, "free")
end

function tests.bestValue_paysWhenTheTimeIsWorthIt()
    local c = Start()
    Fare(c, 2, 5, 10)
    c.FG.db.travel.preset = "balanced"
    local plan = Plan(c, LAKESHIRE)
    local value = Option(plan, "value")
    T.ok(value.same or Flies(value), "ten copper is worth the time saved")
end

function tests.cheapest_isNotALongWalkToSaveAFewCoins()
    local c = Start()
    Fare(c, 2, 5, 5)
    c.FG.db.travel.maxExtraMinutes = 2
    local plan = Plan(c, LAKESHIRE)
    local cheap = Option(plan, "cheap")
    T.ok(cheap.impractical or cheap.same or Flies(cheap), "a walk past the limit is not offered")
end

function tests.cheapest_isOfferedWithinTheLimits()
    local c = Start()
    Fare(c, 2, 5, 50000)
    c.FG.db.travel.maxExtraMinutes = 60
    c.FG.db.travel.maxExtraShare = 10
    local plan = Plan(c, LAKESHIRE)
    local cheap = Option(plan, "cheap")
    T.no(cheap.impractical, "allowed")
    T.no(Flies(cheap))
end

function tests.aRouteWithoutFlights_isConfirmedFree_andMoneyWaysAreSettledWithoutPlanning()
    local c = Start({ mapID = 1429, x = 0.42, y = 0.66 })
    local plan = Plan(c, { name = "Goldshire inn", mapID = 1429, x = 0.44, y = 0.66 })
    local fastest = Option(plan, "fastest")
    T.eq(fastest.cost.sure, "free")
    T.ok(Option(plan, "value").same, "nothing paid: nothing to weigh")
end

function tests.theComparison_saysWhatMoneyIsSaved()
    local c = Start()
    Fare(c, 2, 5, 50000)
    c.FG.db.travel.preset = "money"
    local plan = Plan(c, LAKESHIRE)
    local text = c.FG.Planner.Compare(Option(plan, "value"), Option(plan, "fastest"))
    T.ok(text and text:find("saves 5g", 1, true), tostring(text))
end

function tests.aGuessedFare_isShownAsAGuess()
    local c = Start()
    local plan = Plan(c, LAKESHIRE)
    local fastest = Option(plan, "fastest")
    T.ok(Flies(fastest))
    T.eq(fastest.cost.sure, "guess")
    T.ok(c.FG.Fares.Label(fastest.cost):sub(1, 1) == "~", "a guess reads as one")
    T.ok(c.FG.Fares.Note(fastest.cost))
end

function tests.thePreference_survivesAReroute()
    local c = Start()
    Fare(c, 2, 5, 50000)
    c.FG.db.travel.preset = "money"
    local plan = Plan(c, LAKESHIRE)
    c.FG.Planner.Select(Option(plan, "value"))
    c.FG.Planner.Start()
    c:Advance(1.5)
    local route = c.FG.Bridge.ActiveRoute()
    T.ok(route.wayAvoid and route.wayAvoid.money, "the route keeps what it was planned with")
    c:SetPlayer(1453, 0.30, 0.30)
    Stack.Until(c, function()
        local r = c.FG.Bridge.ActiveRoute()
        return r ~= route
    end, 60)
    local now = c.FG.Bridge.ActiveRoute()
    T.ok(now.wayAvoid and now.wayAvoid.money, "and a reroute plans with it too")
end

-- ==== the hearth ============================================================

function tests.aHearthMustSaveEnough_toBeWorthItsCooldown()
    local c = Start({ mapID = 1439, x = 0.37, y = 0.44, bags = { [6948] = 1 } })
    local Route = c.FG.Bridge.NS().GPSRoute
    c.FG.db.travel.hearthMinutes = 3
    T.eq(Route.HearthReserve(), 180)
    c.FG.db.travel.hearthMinutes = 0
    T.eq(Route.HearthReserve(), 0, "off when set to nothing")
end

function tests.theHearth_saysWhereAndWhen()
    local c = Start({ bags = { [6948] = 1 } })
    c.env.C_Container = c.env.C_Container or {}
    c.env.C_Container.GetItemCooldown = function() return c.env.GetTime() - 600, 3600 end
    local s = c.FG.Hearth.Status()
    T.eq(s.bind, "Lion's Pride Inn")
    T.no(s.ready)
    T.ok(s.cooldown > 2900 and s.cooldown <= 3000)
    T.ok(c.FG.Hearth.Line(s):find("ready in", 1, true))
    c.env.C_Container.GetItemCooldown = function() return 0, 0 end
    T.ok(c.FG.Hearth.Status().ready)
end

function tests.aRebind_dropsTheOldLanding()
    local c = Start({ bags = { [6948] = 1 } })
    c.env.EasyFindDB.gpsHearth = c.env.EasyFindDB.gpsHearth or {}
    local key = c.FG.Bridge.NS().CurrentCharacterKey()
    c.env.EasyFindDB.gpsHearth[key] = { bind = "Lion's Pride Inn", m = 1429, x = 0.44, y = 0.66 }
    T.ok(c.FG.Bridge.HearthSpot(), "known while bound there")
    T.eq(c.FG.Hearth.Status().sure, "learned")
    c.player.bind = "Thunderbrew Distillery"
    T.eq(c.FG.Bridge.HearthSpot(), nil, "not after binding elsewhere")
    T.eq(c.FG.Hearth.Status().sure, "town", "the new town's spot, said to be that")
end

return tests
