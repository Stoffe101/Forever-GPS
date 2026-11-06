# Known limitations

## Not verified in the game

Nothing has been run in the WoW client. All testing is against a fake client running the real addon code. In particular, these can only be judged in the game: fonts and text metrics, texture quality, secure button behaviour, real frame rate, and how it sits beside EllesmereUI. See [MANUAL_TESTING.md](MANUAL_TESTING.md).

## Data age

- Your client is build **70790**. EasyFind GPS's route data was generated from build **69977** and its instance list from 70532. Those are the same 1.60.1 patch, and the generator is not in the upstream repository, so it cannot be rebuilt here. A transport or flight added or moved since then will not be known until upstream updates. `/fgps diag` shows both numbers.
- Boat departure times are learned by riding, as EasyFind GPS has always done, so a countdown appears only after a route has been timed on that account.

## Routing and search

- **The map line appears when navigation starts**, not during inspection. The journey panel lists the steps; EasyFind GPS's preview is tied to the active route.
- **"Any inn" results** are ordered by travel time, but the single "Innkeeper · 45 locations" row goes to the nearest by straight line, as EasyFind chooses it. Named NPCs and quest objectives use the travel-time choice.
- **A first search right after login** may lack dungeons for a moment while EasyFind builds that list. It is warmed in the background from six seconds after login.
- **Travel times in lists are estimates**: walks are straight lines with a detour factor. The journey panel's times use the walking grid and are better. Each is a planning figure, not a promise.
- **Flight knowledge** comes from flight masters' own maps, so a fresh install knows no flights until you open one on each character. That is upstream's rule for Forever, because the client's map listing marks every point discovered.
- Multi-stop trips work through EasyFind GPS's own window, not the Forever-GPS panel.

## Safety

The risk label knows creatures, guards, enemy towns (by flight master) and enemy transport. It knows nothing of enemy players. Town detection covers towns with a flight master only.

## Quests

- Objective locations need Questie. Without it there is one marker per quest at most.
- Questie's objectives are matched to the log by position, as Questie itself does. A quest whose data disagrees with the log would show a mismatch.
- An objective spawning only inside an instance is reported as such; no route goes in.
- Objective text comes from the log, and does not explain what to do.
- After one objective finishes, the next is not started automatically. The route stops and you choose.

## Interface

- English only. Other clients show English interface text, with route steps still localized by EasyFind GPS.
- CJK clients fall back to the game's font.
- Disabling Forever-GPS leaves EasyFind's bar hidden and its character arrow off until you change those in EasyFind's options.

## Scope

- Forever only (interface 16001). The other clients EasyFind supports are out of scope for the Forever-GPS addon.
- RestedXP is not integrated, by design.
