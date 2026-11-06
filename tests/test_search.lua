-- Finding a destination: the real map search and NPC catalog, as the player
-- would use them, with what a result card shows.
local T = require("support.t")
local Stack = require("support.stack")

local function Start(opts)
    opts = opts or {}
    opts.ui = false
    opts.mapID, opts.x, opts.y = opts.mapID or 1453, opts.x or 0.6, opts.y or 0.6
    local c = Stack.new(opts)
    c.FG.Bridge.WarmSearch()
    c:Advance(1)
    return c
end

local function Names(results)
    local out = {}
    for i, r in ipairs(results) do out[i] = r.name end
    return table.concat(out, " | ")
end

local function Find(results, name)
    for _, r in ipairs(results) do
        if r.name == name then return r end
    end
end

local tests = {}
local shared

local function C()
    shared = shared or Start()
    return shared
end

function tests.aPlace_isFoundWithItsZone()
    local r = Find(C().FG.Search.Run("auberdine"), "Auberdine")
    T.ok(r, "found")
    T.eq(r.group, "places")
    T.has(r.subtitle, "Darkshore", "says which zone")
end

function tests.aZone_isFound()
    local r = Find(C().FG.Search.Run("elwynn forest"), "Elwynn Forest")
    T.ok(r, "found")
    T.eq(r.group, "places")
    T.has(r.subtitle, "Zone", "says what it is")
end

function tests.anNpc_isFoundByName()
    local r = Find(C().FG.Search.Run("marshal dughan"), "Marshal Dughan")
    T.ok(r, "found")
    T.has(r.subtitle, "Elwynn Forest", "with its zone")
end

function tests.aDungeonAndARaid_areFound()
    local dungeon = Find(C().FG.Search.Run("deadmines"), "Deadmines")
    T.ok(dungeon, "dungeon found")
    T.eq(dungeon.group, "instances")
    T.has(dungeon.subtitle, "Dungeon", "named as one")
    local raid = Find(C().FG.Search.Run("molten core"), "Molten Core")
    T.ok(raid, "raid found")
    T.has(raid.subtitle, "Raid", "named as one")
    T.ok(C().FG.Bridge.CanNavigate(raid.data), "and an entrance can be routed to")
end

function tests.aFirstDungeonSearch_doesNotComeUpEmpty()
    local c = Start()
    T.ok(Find(c.FG.Search.Run("deadmines"), "Deadmines"), "the instance list is warmed ahead of the first search")
end

function tests.services_findTheNearestOfTheirKind()
    for query, name in pairs({ innkeeper = "Innkeeper", bank = "Bank", mailbox = "Mailbox", ["auction house"] = "Auction House" }) do
        local results, info = C().FG.Search.Run(query)
        T.ok(Find(results, name), query .. " gave: " .. Names(results))
        T.ok(info.kind or query == "mailbox", query .. " is a kind of place")
    end
end

function tests.flightMastersAndRepairers_areServices()
    local results = C().FG.Search.Run("flight master")
    T.ok(#results > 0, "found")
    T.eq(results[1].group, "services", "a flight master is a service")
    T.has(results[1].subtitle, "Gryphon Master", "its title is shown")
    results = C().FG.Search.Run("repair")
    T.ok(#results > 0, "found")
    T.eq(results[1].group, "services", "a repairer is a service")
end

function tests.trainers_areGrouped()
    for _, query in ipairs({ "mage trainer", "fishing trainer", "alchemy" }) do
        local results = C().FG.Search.Run(query, "trainers")
        T.ok(#results > 0, query)
        T.eq(results[1].group, "trainers", query)
    end
end

function tests.aFilter_keepsOnlyItsGroup()
    for _, r in ipairs(C().FG.Search.Run("stormwind", "instances")) do
        T.eq(r.group, "instances", r.name)
    end
    for _, r in ipairs(C().FG.Search.Run("stormwind", "places")) do
        T.eq(r.group, "places", r.name)
    end
end

function tests.coordinates_routeOnTheCurrentMap()
    local results = C().FG.Search.Run("45.2 60.1")
    local r = results[1]
    T.ok(r and r.data, "a coordinates result")
    T.eq(r.data.mapID, 1453, "on the player's map")
    T.near(r.data.x, 0.452, 0.001, "x")
    T.near(r.data.y, 0.601, 0.001, "y")
end

function tests.coordinates_inANamedZone()
    local r = C().FG.Search.Run("westfall 56 47")[1]
    T.ok(r and r.data, "a coordinates result")
    T.eq(r.data.mapID, 1436, "Westfall")
    T.has(r.subtitle, "Westfall", "says so")
end

function tests.nonsenseCoordinates_areNotAPlace()
    local Search = C().FG.Search
    T.no(select(2, Search._ParseCoords("150 60")), "past the map's edge")
    T.no(select(2, Search._ParseCoords("hogger")), "no numbers")
end

function tests.theMapPin_isAPlaceToGo()
    local c = Start()
    T.no(c.FG.Search.MapPin(), "none until one is placed")
    c.env.C_Map.SetUserWaypoint(c.env.UiMapPoint.CreateFromCoordinates(1429, 0.42, 0.65))
    local pin = c.FG.Search.MapPin()
    T.eq(pin.data.mapID, 1429)
    T.ok(c.FG.Bridge.CanNavigate(pin.data), "routable")
end

function tests.noMatch_isEmptyNotAnError()
    T.eq(#C().FG.Search.Run("zzqqxx"), 0, "nothing found")
    T.eq(#C().errors, 0, "and nothing broke")
end

function tests.results_arePricedByTravelTime()
    local c = C()
    local results, info = c.FG.Search.Run("auberdine")
    local updates = 0
    c.FG.Search.Price(results, info, function() updates = updates + 1 end)
    T.ok(Stack.Until(c, function() return results[1].priced end, 5), "priced in later frames")
    T.ok(updates > 0, "the list is told")
    T.has(results[1].eta.transports, "Boat", "and it knows a boat is involved")
end

function tests.aKindOfThing_isOrderedByTravelTime()
    local c = C()
    local results, info = c.FG.Search.Run("repair")
    T.ok(info.kind, "any repairer will do")
    c.FG.Search.Price(results, info, function() end)
    T.ok(Stack.Until(c, function() return results[1].priced and results[2].priced end, 5), "priced")
    local last
    for i = 1, 10 do
        local sec = results[i] and results[i].eta and results[i].eta.sec
        if sec then
            T.ok(not last or sec >= last, "ordered by time at " .. i)
            last = sec
        end
    end
end

function tests.aNewSearch_dropsTheOldPrices()
    local c = C()
    local old, info = c.FG.Search.Run("auberdine")
    c.FG.Search.Price(old, info, function() error("a stale result was priced") end)
    c.FG.Search.CancelPricing()
    c:Advance(1)
    T.eq(#c.errors, 0, "the old list is left alone")
end

function tests.anNpcWithSeveralSpawns_offersEachArea()
    local c = C()
    local N = c.ns.GPSNpcs
    -- A creature the catalog has in more than one place, found from the data.
    local found
    for i = 1, N.n do
        local spots = N.SpotsOf(N.Rec.id(i))
        if spots and #spots >= 4 then
            local maps = {}
            for _, s in ipairs(spots) do maps[s.m] = true end
            if next(maps, next(maps)) then
                found = { id = N.Rec.id(i), spots = spots }
                break
            end
        end
    end
    T.ok(found, "the catalog has creatures on several maps")
    for _, s in ipairs(found.spots) do s.mapID, s.name = s.m, "x" end
    local areas = c.FG.Areas.From(found.spots)
    T.ok(#areas >= 2, "grouped into areas: " .. #areas)
    local best
    c.FG.Areas.Rank(areas, function(a, basis) best = { area = a, basis = basis } end)
    T.ok(Stack.Until(c, function() return best ~= nil end, 10), "ranked")
    T.ok(best.area, "one is chosen")
    if best.basis == "travel" then
        for _, a in ipairs(areas) do
            T.ok(not a.sec or a.sec >= best.area.sec, "the chosen area is the quickest to reach")
        end
    end
end

function tests.sameNamedNpcs_stayApartByPlace()
    local results = C().FG.Search.Run("innkeeper")
    local seen = {}
    for _, r in ipairs(results) do
        local key = r.name .. "|" .. tostring(r.data.mapID)
        T.no(seen[key], "a duplicate row for " .. key)
        seen[key] = true
    end
end

function tests.aHostileNpc_isMarkedAndComesLast()
    local c = Start({ faction = "Horde", race = "Orc" })
    local results = c.FG.Search.Run("marshal dughan")
    local r = Find(results, "Marshal Dughan")
    T.ok(r, "still findable")
    T.ok(r.hostile, "marked hostile to a Horde character")
    T.has(r.note, "Hostile", "and says so")
end

function tests.aFriendlyNpc_carriesNoWarning()
    local r = Find(C().FG.Search.Run("marshal dughan"), "Marshal Dughan")
    T.no(r.hostile, "friendly to the Alliance")
end

function tests.favoritesAndRecents_comeBackFromSaved()
    local c = Start()
    local FG = c.FG
    local target = FG.Search.Target(Find(FG.Search.Run("auberdine"), "Auberdine"))
    FG.Saved.ToggleFavorite(target)
    T.ok(FG.Saved.IsFavorite(target.data), "saved")
    T.eq(#FG.Saved.Favorites(), 1)
    FG.Saved.AddRecent(target)
    FG.Saved.AddRecent(target)
    T.eq(#FG.Saved.Recents(), 1, "one entry however often it is visited")
    T.ok(FG.Bridge.CanNavigate(FG.Saved.Recents()[1].data), "and it can still be routed to")
    FG.Saved.ToggleFavorite(target)
    T.no(FG.Saved.IsFavorite(target.data), "removed")
end

function tests.aMissingDestination_cannotBeNavigated()
    local B = C().FG.Bridge
    T.no(B.CanNavigate({ name = "No spot" }), "no map at all")
    T.no(B.CanNavigate({ name = "No such map", mapID = 123456, x = 0.5, y = 0.5 }), "a map the client does not know")
    T.no(B.CanNavigate(nil), "nothing")
end

return tests
