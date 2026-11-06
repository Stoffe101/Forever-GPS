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

-- ==== understanding what was typed ==========================================

function tests.theExamplesFromTheBrief_allFindSomething()
    local c = Start({ mapID = 1429, x = 0.45, y = 0.6 })
    for _, q in ipairs({ "auberdine", "blacksmith trainer", "weapon trainer", "repair", "nearest mailbox", "bank stormwind",
                         "any inn", "flight master darkshore", "deadmines", "Westfall 56 47" }) do
        T.ok(#c.FG.Search.Run(q) > 0, "nothing for: " .. q)
    end
end

function tests.nearest_meansAKindOfThing()
    local _, info = C().FG.Search.Run("nearest mailbox")
    T.ok(info.kind, "ordered by travel time")
    T.eq(info.query, "mailbox", "and read as what is wanted")
end

function tests.aPhraseTypedInFull_isNotDoubled()
    local N = C().FG.Search._Normalize
    T.eq((N("auction house")), "auction house")
    T.eq((N("stable master")), "stable master")
    T.eq((N("ah stormwind")), "auction house stormwind", "a short word still expands")
    T.eq((N("hearthstone")), "innkeeper")
    T.eq((N("stable")), "stable master")
end

function tests.myTrainer_meansThisCharacters()
    local c = C()
    local query, nearest = c.FG.Search._Normalize("my trainer")
    T.has(query, "trainer")
    T.ok(nearest, "and any of them will do")
    T.lacks(query, "my", "as a question, not a word")
end

function tests.coordinates_readTheWayPeopleWriteThem()
    local P = C().FG.Search._ParseCoords
    local function Reads(text, zone, x, y)
        local name, a, b = P(text)
        T.eq(name, zone, text .. " zone")
        T.near(a, x, 0.0001, text .. " x")
        T.near(b, y, 0.0001, text .. " y")
    end
    Reads("56 47", nil, 0.56, 0.47)
    Reads("56.1, 47.2", nil, 0.561, 0.472)
    Reads("56.1/47.2", nil, 0.561, 0.472)
    Reads("Westfall 56 47", "Westfall", 0.56, 0.47)
    Reads("Westfall: 56 47", "Westfall", 0.56, 0.47)
    Reads("56 47 Westfall", "Westfall", 0.56, 0.47)
    Reads("/way 56 47", nil, 0.56, 0.47)
    Reads("way Westfall 56 47", "Westfall", 0.56, 0.47)
    T.no(P("Westfall"), "no numbers, no coordinates")
    T.no(P("150 47"), "off the map")
end

function tests.flightPathsToLearn_canBeAskedFor()
    local c = C()
    local results, info = c.FG.Search.Run("flights to learn", "all")
    T.ok(#results > 0, "a list")
    T.ok(info.kind, "in order of travel time")
    T.ok(info.unknown, "and with no master seen yet, it says so")
    c.ns.GPSRoute.recordedKnown = { [2] = true }
    local before = #results
    results, info = c.FG.Search.Run("flights to learn", "all")
    T.no(info.unknown, "one seen, it knows")
    T.eq(#results, before - 1, "and what is known leaves the list")
    for _, r in ipairs(results) do T.lacks(r.subtitle or "", "Horde") end
end

function tests.whatPlayersCallThings_isUnderstood()
    local N = C().FG.Search._Normalize
    T.eq((N("ah")), "auction house")
    T.eq((N("fp")), "flight master")
    T.eq((N("where is the bank")), "bank")
    T.eq((N("closest inn")), "inn")
    T.ok(select(2, N("any inn")), "any means nearest")
end

function tests.aMisspelling_stillFindsThePlace()
    for _, q in ipairs({ "stormwnid", "darkshroe", "ironfoge", "innkeper" }) do
        T.ok(#C().FG.Search.Run(q) > 0, "nothing for: " .. q)
    end
end

function tests.spelling_correctsWhatEasyFindCannot()
    local Search = C().FG.Search
    T.eq(Search._Corrected("westfal"), "westfall", "a word it knows")
    T.eq(Search._Corrected("flght mastr"), "flight master", "several at once")
    local results, info = Search.Run("flght mastr")
    T.ok(#results > 0, "found")
    T.eq(info.corrected, "flight master", "and it says what it read")
end

function tests.aRealWord_isNeverCorrected()
    local _, info = C().FG.Search.Run("stormwind")
    T.no(info.corrected, "spelling only steps in when nothing was found")
end

function tests.spelling_isBounded()
    local Search = C().FG.Search
    T.eq(Search._Distance("kitten", "sitting", 5), 3)
    T.ok(Search._Distance("short", "averyverylongword", 2) > 2, "gives up at once")
    T.no(Search._Corrected("zzzzzzzz"), "nothing close: no guess")
end

function tests.longAndOddInput_isHarmless()
    local Search = C().FG.Search
    for _, q in ipairs({ string.rep("a", 500), "%%%%", "(((", "[a-z]+", "ÅÄÖ", "日本語", "   ", "a", "\\", "' OR 1" }) do
        Search.Run(q)
    end
    T.eq(#C().errors, 0, tostring(C().errors[1]))
end

-- ==== the transport network ==================================================

function tests.boatsAndDocks_canBeSearched()
    local results = C().FG.Search.Run("boat")
    local found = Find(results, "Boat to Auberdine")
    T.ok(found, "the Stormwind boat: " .. Names(results))
    T.eq(found.group, "travel")
    T.has(found.subtitle, "Boat", "says what it is")
    T.ok(C().FG.Bridge.CanNavigate(found.data), "and the dock can be routed to")
end

function tests.theTravelFilter_listsRidesWithNothingTyped()
    local results = C().FG.Search.Run("", "travel")
    T.ok(#results >= 5, "rides are listed: " .. #results)
    for _, r in ipairs(results) do T.eq(r.group, "travel", r.name) end
end

function tests.aTram_isFound()
    T.ok(#C().FG.Search.Run("tram") > 0, "the Deeprun Tram")
end

function tests.enemyRides_areNotOffered()
    local c = Start({ faction = "Horde", race = "Orc", mapID = 1454, x = 0.5, y = 0.5 })
    T.no(Find(c.FG.Search.Run("boat", "travel"), "Boat to Auberdine"), "an Alliance boat for a Horde character")
    T.ok(#c.FG.Search.Run("zeppelin", "travel") > 0, "its own zeppelins are")
end

-- ==== places with many instances ==============================================

function tests.aManyPlaceRow_goesToTheQuickestNotTheNearest()
    local c = Start({ mapID = 1429, x = 0.45, y = 0.6 })
    local results, info = c.FG.Search.Run("innkeeper")
    local row = Find(results, "Innkeeper")
    T.ok(row and row.instances, "the row knows its places: " .. tostring(row and row.data.spotCount))
    c.FG.Search.Price(results, info, function() end)
    T.ok(Stack.Until(c, function() return row.priced end, 10), "priced")
    T.ok(row.eta and row.eta.sec < 300, "a nearby inn: " .. tostring(row.eta and row.eta.sec))
    T.eq(row.basis, "travel", "chosen by the route engine's time")
    T.ok(row.areas, "and the others stay on offer")
end

function tests.aManyPlaceRow_skipsEnemyTowns()
    local c = Start({ mapID = 1454, x = 0.445, y = 0.04 })   -- Alliance, in Orgrimmar
    -- One inn on the doorstep, in the enemy's city; one a world away, at home.
    local row = { name = "Innkeeper", data = { name = "Innkeeper", mapID = 1454, x = 0.445, y = 0.04 },
                  instances = { { mapID = 1454, x = 0.445, y = 0.04 }, { mapID = 1429, x = 0.44, y = 0.66 } } }
    c.FG.Search.Price({ row }, { kind = true }, function() end)
    T.ok(Stack.Until(c, function() return row.priced end, 10), "priced")
    T.no(row.area.enemy, "the nearest friendly inn, not the enemy's next door")
    T.eq(row.area.zone, "Elwynn Forest")
end

function tests.aServiceInAnEnemyTown_saysSoAndComesLast()
    local c = Start({ mapID = 1454, x = 0.5, y = 0.5 })   -- Alliance, in Orgrimmar
    local results = c.FG.Search.Run("bank")
    local last = results[#results]
    T.ok(last and last.hostile, "the local bank is the enemy's")
    T.ok(last.note, "and marked: " .. tostring(last.note))
    T.eq(last.noteTone, "danger")
end

function tests.enemyGround_isToldFromFlightMasters()
    local c = C()
    local Risk = c.FG.Risk
    T.ok(Risk.EnemyGround(1, 1678, -4316), "Orgrimmar's master, to an Alliance character")
    T.no(Risk.EnemyGround(0, -8841, 490), "Stormwind's is not")
    T.no(Risk.EnemyGround(0, 100, 100), "open country is nobody's")
end

function tests.zones_haveAnOwner()
    local Risk = C().FG.Risk
    T.eq(Risk.ZoneControl(1429, "Alliance"), "home")
    T.eq(Risk.ZoneControl(1429, "Horde"), "enemy")
    T.eq(Risk.ZoneControl(1431, "Alliance"), "contested", "Duskwood")
end

function tests.choosingABusyRow_plansTheChosenPlace()
    local c = Start({ mapID = 1429, x = 0.45, y = 0.6 })
    local row = Find(c.FG.Search.Run("innkeeper"), "Innkeeper")
    c.FG.Search.Inspect(row)
    T.ok(Stack.Until(c, function()
        local p = c.FG.Planner.Current()
        return p and (p.status == "ready" or p.status == "failed")
    end, 30), "planned")
    local plan = c.FG.Planner.Current()
    T.eq(plan.status, "ready")
    T.ok(plan.target.areas and #plan.target.areas > 1, "with its other places to choose from")
end

-- ==== Questie's world ==========================================================

local WORLD = {
    areaMaps = { [12] = 1429, [40] = 1436 },
    npcs = {
        [299] = { name = "Young Wolf", spawns = { [12] = { { 43, 72 }, { 44, 73 } }, [40] = { { 58, 22 } } }, zoneID = 12 },
        [240] = { name = "Marshal Dughan", spawns = { [12] = { { 42.1, 65.9 } } }, zoneID = 12 },
    },
    objects = {
        [1731] = { name = "Copper Vein", spawns = { [12] = { { 60, 50 } }, [40] = { { 40, 40 } } }, zoneID = 12 },
    },
}

local function WithWorld()
    local c = Start({ questie = WORLD, mapID = 1429, x = 0.45, y = 0.6 })
    T.ok(Stack.Until(c, function() return c.FG.Bridge.WarmWorld(50) end, 5), "indexed")
    return c
end

function tests.questiesWorld_findsWhatTheCatalogLacks()
    local c = WithWorld()
    local r = Find(c.FG.Search.Run("copper vein"), "Copper Vein")
    T.ok(r, "an object no NPC list has")
    T.ok(r.world, "from Questie")
    T.has(r.subtitle, "known spawns", "and it says these are known spawns")
end

function tests.questiesWorld_doesNotRepeatTheCatalog()
    local c = WithWorld()
    local n = 0
    for _, r in ipairs(c.FG.Search.Run("marshal dughan")) do
        if r.name == "Marshal Dughan" then n = n + 1 end
    end
    T.eq(n, 1, "one row, the catalog's")
end

function tests.questiesWorld_offersEveryArea()
    local c = WithWorld()
    local r = Find(c.FG.Search.Run("young wolf"), "Young Wolf")
    T.ok(r, "found")
    local target = c.FG.Search.Target(r)
    T.ok(target.areas and #target.areas == 2, "both zones")
    T.ok(target.predicted, "and marked as prediction, not a live position")
end

function tests.withoutQuestie_noWorldRowsAndNoErrors()
    local c = C()
    T.eq(#c.FG.Search.Run("copper vein"), 0, "nothing")
    T.eq(#c.errors, 0)
end

function tests.aMissingDestination_cannotBeNavigated()
    local B = C().FG.Bridge
    T.no(B.CanNavigate({ name = "No spot" }), "no map at all")
    T.no(B.CanNavigate({ name = "No such map", mapID = 123456, x = 0.5, y = 0.5 }), "a map the client does not know")
    T.no(B.CanNavigate(nil), "nothing")
end

return tests
