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

## Modules

`addons/ForeverGPS`, in load order:

| File | Job |
| --- | --- |
| `Core/Namespace.lua` | Topics, client events, safe calls |
| `Core/Format.lua` | Times and distances as text |
| `Core/Settings.lua` | Saved variables, first run |
| `Core/Bridge.lua` | **Every** touch of EasyFind's internals |
| `Core/Kinds.lua` | What each way of travel is called and drawn as |
| `Core/Eta.lua` | Travel-time estimates, sliced and cached |
| `Core/Risk.lua` | Known hazards on a route, as a label |
| `Core/Planner.lua` | Inspecting a journey before taking it |
| `Core/Saved.lua` | Favorites and recents |
| `Core/Quests.lua` | The quest log, read lazily |
| `Core/QuestTargets.lua` | Areas from spawns; quest targets |
| `Core/Search.lua` | One result list from all sources |
| `Core/Journey.lua` | The route as the HUD reads it; quests kept in step |
| `Core/TomTom.lua` | Optional mirror to TomTom |
| `Core/Diagnostics.lua` | `/fgps diag` |
| `UI/*` | Theme, widgets, list, panels, window, HUD |

Modules talk through topics (`FG.On`, `FG.Emit`): `plan:changed`, `quests:changed`, `journey:view`, `journey:step`, `route:started`, `route:cleared` and so on.

## How a journey is planned

1. `Planner.Inspect(target)` checks the destination can be routed to and that the client reports a position, and if not, says why.
2. For each mode it waits for the engine to be free, then runs `GPS:BuildRoute` inside `GPS:Plan`, the engine's coroutine planner, so nothing stalls a frame. The first answer shows at once, and the others fill in.
3. Modes that turn out to be the same route are merged, so the panel never offers a choice that is not one.
4. `Bridge.RestoreNav()` puts the walking grid's settings back. This matters: the active route's drawn walks are keyed under those settings, so comparing routes without restoring would lose them.
5. `Planner.Start` commits the selected steps, or plans again if the player has moved more than 120 yards or two minutes have passed.

Only one plan runs at a time and a newer one silently replaces the old, so Forever-GPS never starts a plan while `IsPlanning()` is true, and a watchdog moves on if one is displaced.

## Performance

- Nothing runs while the window is closed and no route exists: no `OnUpdate` scripts, no polling.
- The Journey driver runs at 5 Hz, only while a route exists. The HUD arrow runs at about 30 Hz, only while the arrow is on screen.
- Estimates run at most 4 ms a frame, only when the planner is idle, for at most ten results, and are cached for 60 seconds per 40-yard cell.
- The quest log is read only after it changes, at most once per 0.3 seconds, however many `QUEST_LOG_UPDATE`s fire. A test holds 40 events to one read.
- Lists create only the rows that fit.
- Forever-only data stays behind `AllowLoadGameType`, and the default package drops the rest.

## Combat

Only one secure frame exists: the HUD's cast button for teleport steps. It hangs from `UIParent`, not the HUD, because a frame a secure frame is anchored to becomes protected. It is hidden and unanchored at `PLAYER_REGEN_DISABLED`, and never touched in combat. Everything else is plain frames, so the window and HUD work during a fight.

## Testing

The test client (`tests/support/client.lua`) loads the real addons through their real TOC files, under the real load rules. Routing tests run the real engine on the real data and walking grid, and search tests run the real map search and NPC catalog. Only the player and the screen are pretended, plus a small stand-in Questie. Map geometry is exact, taken from the catalog's own map planes.

`tests/support/fakeui.lua` really solves anchors, so layout can be tested. It estimates font widths on the wide side and refuses over-constrained anchors. `tools/ui_preview.lua` renders the same thing to HTML for a person to look at.

The limits of this are in [MANUAL_TESTING.md](MANUAL_TESTING.md): none of it is the game.

## Updating upstream

See [UPSTREAM.md](UPSTREAM.md).
