# Known limitations

## Not verified in the game

2.0 has run in the client. **2.1 has not**: the one-folder build and everything new in it were tested against a stand-in client running the real addon code. These can only be judged in the game: the single folder loading, fonts and text metrics, texture quality, secure button behaviour, real frame rate and memory, and how it sits beside EllesmereUI. See [FIRST_RUN.md](FIRST_RUN.md).

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
- Questie's objectives are matched to the log by position, as Questie itself does. A quest whose data disagrees with the log would show a mismatch.
- An objective spawning only inside an instance is reported as such; no route goes in.
- Objective text comes from the log, and does not explain what to do.
- After one objective finishes, the next is offered, not started. The route stops and you choose.
- Grouping and filtering by distance use a straight line, for speed. Open a quest for travel times.

## Interface

- English only. Other clients show English interface text, with route steps still localized by EasyFind GPS.
- CJK clients fall back to the game's font.
- On the default window the Saved chip wraps to a second row of its own. Cosmetic.
- The world map preview was tested against a stand-in map. Its look over real map art, and at every zoom, is for the game to confirm.
- The minimap button sits on a round minimap. A square or skinned minimap may need it hidden; the addon compartment and `/fgps` do the same job.

## Scope

- Forever only (interface 16001). The other clients EasyFind supports are out of scope for the Forever-GPS addon.
- RestedXP is not integrated, by design.
- Wowhead data is not used. See [ARCHITECTURE.md](ARCHITECTURE.md#why-not-wowhead-data).
- **EasyFind cannot be installed beside it.** The two would be the same addon twice. Forever-GPS offers to turn the old folders off if it finds them.
- `/ef` still answers, from the vendored code, and its options are gone with the companion apps. Use `/fgps`.
