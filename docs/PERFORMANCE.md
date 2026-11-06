# Performance

**Every number here is from a simulation:** the stand-in client on desktop Lua 5.4, on the development machine. The game's Lua, frame timing and memory reporting all differ. Read these as relative costs and as a baseline for catching regressions, not as what a player's frame spends. Real figures come from `/fgps diag` in the game, which reports timings for its own plans, searches and map drawing, plus addon memory.

Regenerate with:

```bash
lua tools/perf.lua
```

| Measure (stand-in client, desktop Lua 5.4) | Value |
| --- | --- |
| Lua heap with EasyFind, GPS and Forever-GPS loaded, UI not opened | 17.66 MB |
| Lua heap after opening the window and warming search | 20.09 MB |
| `Search.Run`: a place name | 0.86 ms |
| `Search.Run`: a kind of service | 0.70 ms |
| `Search.Run`: a misspelling | 0.90 ms |
| Planner: every way to a place across a sea, in slices | 924 ms total |
| `Journey.View`, as the HUD reads it five times a second | under 0.01 ms |
| `Journey.View` in the detailed HUD, looking for the next turn | 0.01 ms |
| `HUD.Render` | 0.43 ms |
| `Trip.Order`: eight stops, on a cost table | 0.09 ms |

The heap figure includes the fake client's own frames and EasyFind's data, so it says more about change over time than about the addon's real size.

## What keeps it cheap

- Nothing runs with the window closed and no route: no `OnUpdate`, no polling.
- The journey driver runs at 5 Hz, only with a route. The HUD arrow runs at about 30 Hz, only while on screen, and at 4 Hz with reduced motion. The map preview runs at 10 Hz, only while the map is open on a preview.
- Planning runs in the engine's coroutine slices, one way at a time. A plan's result is kept 45 seconds, so going back and forth costs nothing.
- Estimates run at most 4 ms a frame, only with the planner idle, and are cached for 60 seconds per 40-yard cell. A trip's matrix goes through the same queue, and a trip holds eight stops.
- Questie's names are indexed 3 ms a frame, once, starting after the window is first opened.
- The quest log is read only after it changes, at most once per 0.3 seconds. A quest's places are worked out again only when one of its objectives finishes, not at each kill, which a test holds to zero rebuilds.
- Ordering a trip is nearest-first plus six passes of 2-opt, bounded by eight stops.
- Lists build only the rows that fit.

## Budgets the tests hold

- Eight stops ordered in under 50 ms.
- Forty `QUEST_LOG_UPDATE` events make one read.
- A counter moving on an objective makes no quest's targets rebuild.
