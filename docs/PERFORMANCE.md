# Performance

Two kinds of number appear here, and they are not comparable. **Real** figures come from `/fgps diag` in the game. **Simulated** figures come from the stand-in client on desktop Lua 5.4, on the development machine: read those as relative costs and as a baseline for catching regressions, not as what a player's frame spends.

## What the real numbers meant

From 2.0 in the game: search 2.4 ms, worst 25.9 ms. Map drawing 0.8 ms. Planning 1.73 s, worst 15.24 s.

**The planning figures were time across many frames, not freezes.** `plan` runs from asking to the last way being finished. The engine works in slices of 6 ms a frame, and four ways are planned in turn, so a long journey at a low frame rate takes many seconds while the game stays responsive. 2.1 reports `planFrame` beside it, the busiest single frame, which is the figure that decides whether anything stutters.

## 2.0 against 2.1

Package figures are exact. Planning figures are simulated, the time from asking to the last way being settled.

| Measure | 2.0 | 2.1 |
| --- | --- | --- |
| Folders to install | 14 | 1 |
| Files | 456 | 388 |
| Unpacked | 41.4 MB | 25.3 MB |
| Zipped | 12.9 MB | 9.6 MB |
| Planning: no route exists | 10,663 ms | 2,392 ms |
| Planning: Stormwind to Goldshire, a walk | 708 ms | 423 ms |
| Planning: Stormwind to Auberdine, by boat | 885 ms | 663 ms |
| Planning: Elwynn to Gadgetzan, a long journey with real alternatives | 3,440 ms | 2,895 ms |
| Plans for a walk | 4 | 1 to 3 |
| Share of a frame at 60 fps | 6 ms | 5 ms |
| Share of a frame at 20 fps | 6 ms | 12 ms, so twice the work per frame where frames are long |

The first answer is on screen after the fastest way alone, and quick navigation starts on it.

Real memory in 2.0 was 1.8 MB for Forever-GPS, 11.3 MB for EasyFind GPS and 18.1 MB for EasyFind. In 2.1 that is one figure. The companion apps are gone and EasyFind no longer loads its spells, toys, mounts and settings at login for a bar that stays hidden, so it should fall, but the stand-in client has almost none of that data, so how far can only be measured in the game.

Regenerate the simulated baselines with:

```bash
lua tools/perf.lua
```

| Measure (stand-in client, desktop Lua 5.4) | Value |
| --- | --- |
| Lua heap with everything loaded, UI not opened | 18.00 MB |
| Lua heap after opening the window and warming search | 20.44 MB |
| `Search.Run`: a place name | 0.82 ms |
| `Search.Run`: a kind of service | 0.70 ms |
| `Search.Run`: a misspelling | 0.92 ms |
| `Journey.View`, read five times a second | under 0.01 ms |
| `Journey.View` in the detailed HUD, looking for the next turn | 0.01 ms |
| `HUD.Render` | 0.41 ms |
| `Trip.Order`: eight stops, on a cost table | 0.10 ms |

The heap figure includes the stand-in client's own frames, so it says more about change over time than about the addon's real size.

## What keeps it cheap

- Nothing runs with the window closed and no route: no `OnUpdate`, no polling.
- The journey driver runs at 5 Hz, only with a route. The HUD arrow runs at about 30 Hz, only while on screen, and at 4 Hz with reduced motion. The map preview runs at 10 Hz, only while the map is open on a preview.
- Planning runs in the engine's coroutine slices, one way at a time, taking about 30% of a frame. Ways that cannot differ from the fastest are settled without a plan. A plan's result is kept 45 seconds, so going back and forth costs nothing.
- Every quest's places are worked out a few milliseconds a frame after login, so opening the window never does them all at once.
- Estimates run at most 4 ms a frame, only with the planner idle, and are cached for 60 seconds per 40-yard cell. A trip's matrix goes through the same queue, and a trip holds eight stops.
- Questie's names are indexed 3 ms a frame, once, starting after the window is first opened.
- The quest log is read only after it changes, at most once per 0.3 seconds. A quest's places are worked out again only when one of its objectives finishes, not at each kill, which a test holds to zero rebuilds.
- Ordering a trip is nearest-first plus six passes of 2-opt, bounded by eight stops.
- Lists build only the rows that fit.

## Budgets the tests hold

- Eight stops ordered in under 50 ms.
- Forty `QUEST_LOG_UPDATE` events make one read.
- A counter moving on an objective makes no quest's targets rebuild.
