# Architecture

## The decision

Forever-GPS is a **separate addon on top of the three EasyFind addons**, not a merge of them.

```
ForeverGPS            window, HUD, search, quests, journey planning
   |  Bridge.lua      the only file that knows EasyFind's insides
EasyFind_GPS          route engine, walking grid, step tracking, map lines
EasyFind_Questie      reads Questie's database                   (optional)
EasyFind              search, map data, extension API
Questie, TomTom       separately installed                       (optional)
```

Why not merge everything into one addon, or rewrite the router? Because the existing engine is much better than the brief's description of it, and everything valuable in it depends on names that a merge would break:

| Merge into one addon | Layer on top (chosen) |
| --- | --- |
| One folder to install | 14 folders, in one zip |
| Must rename `EasyFind._ns`, saved variables, texture paths, `Interface\AddOns\EasyFind\...` | Nothing renamed |
| Every upstream update is a manual port | Upstream updates apply with a small diff |
| 1,600 upstream tests need rewriting | They run unchanged |

The cost is real: upstream internals are not a stable API, and EasyFind's search bar and companions come along. The first is contained by `Bridge.lua`, and the second is hidden on first run.

## What was reused, and what was not rebuilt

There is **no second routing engine**. Every time on screen comes from `Route:Build`.

- **Travel times in lists** are `Route:Build` called with `canFly = true` and a speed of `ground / 1.2`. That is the engine's own straight-line mode with its own 1.2 ground detour: the same graph, flights, boats, faction rules and hearth, without searching the walking grid. It costs about a millisecond, and on Stormwind to Auberdine it reads 374 seconds against 375 for the full route.
- **Route alternatives** are `GPS:BuildRoute` with different `avoid` sets, using the engine's `danger` and `offroad` options.
- **Starting a route** hands the steps already planned to `GPS.Navigated`, so what you inspected is exactly what you follow, with no second plan.
- **Following** is untouched: EasyFind GPS's ticker advances steps, reroutes, handles death and restores after a reload. Forever-GPS only reads that state.
- **The HUD's arrow** uses the character arrow's own `_Aim` and `_Bearing`, so it follows bends in the walk.

## One folder

The package is one addon. `tools/assemble.py` builds it from the pinned vendored addons and Forever-GPS's own files, into `build/assembled/ForeverGPS`:

```
ForeverGPS/
  ForeverGPS.toc     generated: Preflight, then the vendored files in their own order, then Forever-GPS
  Bindings.xml
  Core/  UI/  Art/  Locales/  Commands.lua    Forever-GPS
  Vendor/
    EasyFind/  EasyFind_GPS/  EasyFind_Questie/    the routing engine, map search and data, with their licenses
```

Keeping the parts apart in `addons/` is what keeps updates manageable: their suites run there, unchanged, and the Forever-GPS suite runs on the assembled folder, which is what ships. [UPSTREAM.md](UPSTREAM.md) lists every change assembly makes.

All files of one addon share one private table. EasyFind's code owns it, and EasyFind GPS already shared it. Forever-GPS moved to its own global, `ForeverGPS`, and the Questie extension keeps a table inside the shared one.

`Core/Preflight.lua` loads first. EasyFind calls `ForeverGPSPreflight.Settle` the moment it has its saved variables, so its search bar stays hidden and old data arrives before anything reads it, whichever frame hears `ADDON_LOADED` first.

WoW hands an addon only what is saved under its own name, so what EasyFind GPS saved cannot follow by itself. `tools/migrate_saved.py` reads it and writes `Core/Imported.lua` into the installed folder, which is why going back to 2.0 stays exact: `WTF` is never written.

## Modules

`addons/ForeverGPS`, in load order:

| File | Job |
| --- | --- |
| `Core/Namespace.lua` | Topics, client events, safe calls |
| `Core/Format.lua` | Times and distances as text |
| `Core/Metrics.lua` | Timings of its own work, for `/fgps diag` |
| `Core/Settings.lua` | Saved variables, migrations, first run |
| `Core/Bridge.lua` | **Every** touch of EasyFind's internals |
| `Core/Kinds.lua` | What each way of travel is called and drawn as |
| `Core/Eta.lua` | Travel-time estimates, sliced and cached |
| `Core/Risk.lua` | Known hazards on a route, as a label |
| `Core/Planner.lua` | Inspecting a journey before taking it |
| `Core/Saved.lua` | Favorites, recents, regular places, the journey log, resuming |
| `Core/Quests.lua` | The quest log, read lazily |
| `Core/QuestDB.lua` | **Every** read of Questie's modules, for quests not in the log |
| `Core/QuestTargets.lua` | Areas from spawns; quest targets; where a quest starts |
| `Core/QuestStatus.lua` | Questie's answer in a player's words |
| `Core/QuestIndex.lua` | Every quest, findable, built a slice at a time |
| `Core/QuestChain.lua` | Prerequisites, chains and the way to a quest, all bounded |
| `Core/Search.lua` | One result list from all sources |
| `Core/Journey.lua` | The route as the HUD reads it; ride states; quests kept in step |
| `Core/Trip.lua` | Several stops, the order to visit them in, saved trips, circuits |
| `Core/QuestBrowse.lua` | Finding quests: lists, filters, near the player, one quest's details |
| `Core/Continuity.lua` | Keeps a destination when the player travels another way |
| `Core/Fares.lua`, `Core/Hearth.lua` | Fares, money ways and the hearth's status |
| `Core/Professions.lua`, `Core/Market.lua`, `Core/Crafting.lua`, `Core/Trainers.lua` | Professions, prices, crafting maths and lists, trainers by what they teach |
| `Core/Suggest.lua` | What might be useful now, for the home view |
| `Core/TomTom.lua` | Optional mirror to TomTom |
| `Core/Diagnostics.lua` | `/fgps diag` and the copyable report |
| `UI/Theme.lua`, `UI/Kit.lua`, `UI/List.lua` | Tokens, widgets, a list that builds only what fits |
| `UI/RouteMap.lua` | A map of our own, so nothing here has to open or turn the game's |
| `UI/MapPreview.lua` | The journey or a quest's places, on our map or over one the player opened |
| `UI/RoutePanel.lua`, `UI/SearchView.lua`, `UI/QuestsView.lua`, `UI/TripView.lua` | The window's pages |
| `UI/ExplorerView.lua`, `UI/QuestDetail.lua` | Find quests, and one quest in full |
| `UI/ProfessionsView.lua` | The Professions tab |
| `UI/CopyBox.lua`, `UI/Settings.lua`, `UI/MainWindow.lua` | Text to copy, settings, the window |
| `UI/HUD.lua`, `UI/Quick.lua`, `UI/MinimapButton.lua` | What stays out of the window |

Modules talk through topics (`FG.On`, `FG.Emit`): `plan:changed`, `quests:changed`, `journey:view`, `journey:step`, `route:started`, `route:cleared` and so on.

## How a journey is planned

1. `Planner.Inspect(target)` checks the destination can be routed to and that the client reports a position, and if not, says why.
2. For each mode it waits for the engine to be free, then runs `GPS:BuildRoute` inside `GPS:Plan`, the engine's coroutine planner, so nothing stalls a frame. The first answer shows at once, and the others fill in.
3. Modes that turn out to be the same route are merged, so the panel never offers a choice that is not one.
4. `Bridge.RestoreNav()` puts the walking grid's settings back. This matters: the active route's drawn walks are keyed under those settings, so comparing routes without restoring would lose them.
5. `Planner.Start` commits the selected steps, or plans again if the player has moved more than 120 yards or two minutes have passed.

Only one plan runs at a time and a newer one silently replaces the old, so Forever-GPS waits out the engine's own plans, replaces only its own, and has a watchdog move on if one is displaced. Each plan owns the walks it found, so the map can draw any option at any time. Every stage is laid out in [LIFECYCLE.md](LIFECYCLE.md).

The fastest way is planned first, and every other way is that with something added or left out. So `Planner.Settled` can often answer from it without a plan: nothing reaches the place, or the fastest uses no transport for Overland to leave out, or no dangerous ground for Safer to go around, or the walk is too short to compare. Roads is the one that always needs its own plan. Starting drops whatever is left.

## How search ranks

In stages, so a list appears at once and improves:

1. `Search.Run` understands the query (`nearest`, `any`, what players call things, a misspelling), gathers from EasyFind's map search, the NPC catalog, travel and Questie's world index, and orders by match.
2. `Search.Price` puts a coarse travel time on the first results, from the route graph with straight-line walks, in small slices.
3. For a kind of thing, the list reorders by that time, and a row for many places moves onto the quickest, passing over enemy towns.
4. The selected result gets a full plan on the walking grid.

## Why not Wowhead data

Addons cannot reach the network, so Wowhead could only ever be static data shipped in the package. No official API was found, the terms could not be read, and the fetch was blocked, so whether scraping is allowed is unknown. It is not used. Questie's installed database has Forever's data, far more than the catalog, and is read at run time through `EasyFind_Questie`. Coverage is limited to what Questie knows, and it needs Questie installed.

## Performance

- Nothing runs while the window is closed and no route exists: no `OnUpdate` scripts, no polling.
- A plan takes about 30% of each frame, between 4 and 12 ms, so a slow machine is not left waiting. Its busiest frame is reported as `planFrame`.
- The Journey driver runs at 5 Hz, only while a route exists. The HUD arrow runs at about 30 Hz, only while the arrow is on screen. Baselines are in [PERFORMANCE.md](PERFORMANCE.md).
- Estimates run at most 4 ms a frame, only when the planner is idle, for at most ten results, and are cached for 60 seconds per 40-yard cell.
- The quest log is read only after it changes, at most once per 0.3 seconds, however many `QUEST_LOG_UPDATE`s fire. A test holds 40 events to one read.
- Lists create only the rows that fit.
- Forever-only data stays behind `AllowLoadGameType`, and the default package drops the rest.

## Combat

Nothing here opens, closes or turns the game's map, and every change to its waypoint and tracking waits out a fight and an open map: [TAINT.md](TAINT.md) says why, and a static test holds it.

Only one secure frame exists: the HUD's cast button for teleport steps. It hangs from `UIParent`, not the HUD, because a frame a secure frame is anchored to becomes protected. It is hidden and unanchored at `PLAYER_REGEN_DISABLED`, and never touched in combat. Everything else is plain frames, so the window and HUD work during a fight.

## Testing

The test client (`tests/support/client.lua`) loads the real addons through their real TOC files, under the real load rules. Routing tests run the real engine on the real data and walking grid, and search tests run the real map search and NPC catalog. Only the player and the screen are pretended, plus a small stand-in Questie. Map geometry is exact, taken from the catalog's own map planes.

`tests/support/fakeui.lua` really solves anchors, so layout can be tested. It estimates font widths on the wide side and refuses over-constrained anchors. `tools/ui_preview.lua` renders the same thing to HTML for a person to look at, and [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md) sets out what they should see.

`tests/test_golden.lua` takes six journeys from typing to arriving. `tests/test_invariants.lua` holds what must be true for any input, with a fixed seed so a failure repeats.

The limits of this are in [MANUAL_TESTING.md](MANUAL_TESTING.md): none of it is the game.

## Updating upstream

See [UPSTREAM.md](UPSTREAM.md).
