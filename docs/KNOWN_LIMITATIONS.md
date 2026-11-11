# Known limitations

## Not verified in the game

2.1 has run in the client. **2.2 has not**: everything new in it was tested in a stand-in client running the real addon code. These can only be judged in the game:

- **Whether the map taint error is gone.** See [TAINT.md](TAINT.md). The fix is real but unproven.
- The route map's art, which is drawn with the same calls as the game's map but has never been seen.
- The Quest Explorer against live Questie. Its data has been read offline, and everything else ran against a stand-in that follows Questie's rules.
- Fonts, texture quality, real frame times and memory, and how it sits beside EllesmereUI.

## 2.5

- **2.5 has not run in the game.** It fixes what 2.4 did there, as BugSack and the saved data showed. See [REALCLIENT.md](REALCLIENT.md).
- **Overlap:** the overlap the player saw is not confirmed to be the one fixed. The row heights now follow the game's own text measurements once drawn, and `/fgps report` counts any row that had to grow.
- **The automatic scan** relies on the server allowing `ReplicateItems` without a click. Auctionator does this in the same game, but Forever-GPS's own call has not been seen there yet.
- **Searches while you browse:** item searches can still run while you browse, but stop on your first search.
- **Known recipes:** which recipes a character knows is still read from the profession window. It is not guessed from the client's data.
- **The 2.2 taint** seen in session 35 (quest map pins, auras) is not explained yet. See REALCLIENT.md.

## 2.4

- **Nothing new has run in the game.** That covers the scan timing, searches, quantities, plans, trainers, alts, history, alerts, plans from elsewhere and the new navigation states. All were tested only in the stand-in client.
- **The trainer window's shape on Forever is not confirmed.** Both shapes are read. `/fgps report` says which one the client showed.
- **Recipe IDs:** the profession window's recipe IDs are taken to be the spell IDs in the client's data, as on other clients. If they differ, plans fall back to the ranges you have seen.
- **The game's ranges** come from the client's files via profit's export of build 1.60.1.70790. A later client may change some. What you see in your own window is believed over them.
- **A trainer's recipe price** is unknown until its window is read, so plans with recipes to learn leave it out and say so.
- **The long-climb search** is very close to the cheapest plan in tests, but not proven to be it. Short climbs are exact.
- **Commodities** are priced as bought unit by unit, as the auction house sells them. A non-stackable item's listings are whole auctions.
- **Alerts** speak in chat only, when new prices arrive. They never buy.

## 2.3

- **Nothing new has run in the game.** That covers continuous navigation, travel costs, professions, prices and trainers, all tested only in the stand-in client.
- **Fares** are only known once a flight master's map has been opened. Until then they are estimated and shown with `~`. Boats, trams and teleport reagents are not priced.
- **Recipe skill-up thresholds** are not given by the client. They are learned from colours seen and estimated until then. The chance rule is the long-standing one and is not confirmed on Forever.
- **The cheapest-way plan** uses learned recipes only. Gathering professions have none.
- **Trainers** are unknown until visited. No rank is assumed from an NPC's title.
- **Prices** come only from your own scans: one at a time, no sales history, no deposits, and no outside import.
- **A scan** reads the client's full listing, which the server limits to about one every 15 minutes. Its exact behaviour on Forever is unconfirmed.
- **Neutral houses** are told apart by the zone they are opened in: Booty Bay, Gadgetzan and Everlook.

## Data age

- Your client is build **70790**. EasyFind GPS's route data was generated from build **69977** and its instance list from 70532. Those are the same 1.60.1 patch, and the generator is not in the upstream repository, so it cannot be rebuilt here. A transport or flight added or moved since then will not be known until upstream updates. `/fgps diag` shows both numbers.
- Boat departure times are learned by riding, as EasyFind GPS has always done, so a countdown appears only after a route has been timed on that account.

## Routing and search

- **Flight advice appears after starting**, not while choosing. The engine works it out once a route is under way, and a second plan beside it got in the way of its other ways.
- **A spawn is a prediction.** NPC and object places come from static data. A creature may be dead, patrolling or elsewhere, and the panel says so.
- **A first search right after login** may lack dungeons for a moment while EasyFind builds that list. It is warmed in the background from six seconds after login.
- **Travel times in lists are estimates**: walks are straight lines with a detour factor. The journey panel's times use the walking grid and are better. Each is a planning figure, not a promise.
- **Flight knowledge** comes from flight masters' own maps, so a fresh install knows no flights until you open one on each character. That is upstream's rule for Forever, because the client's map listing marks every point discovered.
- **Questie's world search needs Questie**, and knows only what its database knows. Nothing is copied into this repository.
- **A trip's order is good, not best**: nearest-first with limited refinement. Its legs are straight-line estimates until the trip is planned.
- **A trip holds eight stops.**
- **Memory is reported as one figure now.** With one folder the game cannot separate navigation data from the search code around it. Saved memory from skipping the hidden bar's data can only be measured in the game.
- **Wrong-ride detection is by where you end up.** Boarding the wrong boat is noticed once you are somewhere neither end of the planned crossing, usually on landing. A ride between the same two continents as the planned one is not told apart until then.

## Safety

The risk label knows creatures, guards, enemy towns (by flight master), enemy transport, contested zones and drops. It knows nothing of enemy players. Town detection covers towns with a flight master only. Zone control is a fixed list of home territories, so a contested label is about the zone, not about what is happening there.

## Quests

- Objective locations need Questie. Without it there is one marker per quest at most.
- Quests not in the log need Questie too, and only what its database holds can be found.
- A status is Questie's reading of its data. Only the quest giver can confirm a quest is really on offer. See [QUEST_EXPLORER.md](QUEST_EXPLORER.md).
- An item's sources are what Questie records. A rare drop may have many, and only the first eight are offered.
- Rewards show reputation only: Questie's database holds no item rewards.
- Questie's objectives are matched to the log by position, as Questie itself does. A quest whose data disagrees with the log would show a mismatch.
- An objective spawning only inside an instance is reported as such; no route goes in.
- Objective text comes from the log, and does not explain what to do.
- After one objective finishes, the next is offered, not started. The route stops and you choose.
- Grouping and filtering by distance use a straight line, for speed. Open a quest for travel times.

## Interface

- English only. Other clients show English interface text, with route steps still localized by EasyFind GPS.
- CJK clients fall back to the game's font.
- On the default window the Saved chip wraps to a second row of its own. Cosmetic.
- **The game's map is the player's.** Forever-GPS no longer opens or turns it, so **Show on map** opens the route map instead, a window of its own. The route map shows a whole map at one size, with no zoom. Press M for the game's map: a preview draws on whatever map you turn it to.
- Where EasyFind's mark and the game's waypoint pin coincide, both now show. See [TAINT.md](TAINT.md).
- Escape closes Forever-GPS's windows out of combat only. In a fight it goes to the game, because key bindings cannot change then.
- The preview over the game's map was tested against a stand-in map. Its look over real art, and at every zoom, is for the game to confirm.
- The minimap button sits on a round minimap. A square or skinned minimap may need it hidden; the addon compartment and `/fgps` do the same job.

## Scope

- Forever only (interface 16001). The other clients EasyFind supports are out of scope for the Forever-GPS addon.
- RestedXP is not integrated, by design.
- Wowhead data is not used. See [ARCHITECTURE.md](ARCHITECTURE.md#why-not-wowhead-data).
- **EasyFind cannot be installed beside it.** The two would be the same addon twice. Forever-GPS offers to turn the old folders off if it finds them.
- `/ef` still answers, from the vendored code, and its options are gone with the companion apps. Use `/fgps`.
