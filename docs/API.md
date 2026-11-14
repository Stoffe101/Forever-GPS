# ForeverGPS.API (version 1)

A small public surface for other addons (first user: HarvestMate Enhanced). Defined in `addons/ForeverGPS/Core/API.lua`; tested on the real route engine in `tests/test_api.lua`. Additive only: later versions add functions, never change these.

```lua
local api = ForeverGPS and ForeverGPS.API
if api and (api.VERSION or 0) >= 1 then
    local token, why = api.NavigateTo({ mapID = 1436, x = 0.56, y = 0.47, label = "Sentinel Hill farm",
                                        source = "MyAddon", start = true })
    api.On("arrived", function(t) if t == token then --[[ take over locally ]] end end)
end
```

| Function | Returns |
|---|---|
| `NavigateTo(spec)` — `{ mapID, x, y (0-1), label?, source?, start? }` | token, or nil and a reason. Plans and shows the journey; `start = true` begins it once planned (use only right after the player asked for directions). |
| `Status(token)` | `pending`, `active`, `arrived`, `cancelled`, `superseded`, `released`, `stale` or `unknown` |
| `IsActive(token)` | true while that journey is the route being followed |
| `Current()` | `{ token?, mapID, x, y, name }` of the route followed now; `token` only if it is an API journey |
| `Release(token)` | stops the route only if it is still that token's journey; true if it did |
| `EstimateSeconds(mapID, x, y)` | travel estimate in seconds from the player, or nil |
| `On(event, fn)` | `started(token|nil, dest)`, `arrived(token, dest)`, `cancelled(token)`, `superseded(token)`, `released(token)` |

## Ownership rules
- A request becomes a token's journey only when a route starts whose destination matches it (same map, within 80 yards).
- A route to another destination supersedes the request: that journey is the player's, and `Release` refuses to stop it.
- The clear that follows an arrival is not a cancellation.
- Duplicate events change nothing.
- After `/reload`, an active journey whose route no longer exists becomes `stale`.

Nothing in the API calls protected functions, opens the map in combat or changes bindings.

## Version 2 (additive)

`ForeverGPS.API.VERSION` is 2. Everything in version 1 is unchanged.

### Holding the arrow

For an addon that guides the player itself for a while (HarvestMate Enhanced round a farming loop) while a Forever-GPS journey is running. The journey is not stopped or changed; only Forever-GPS's arrows stand down, so there is never more than one arrow.

| Function | Returns |
|---|---|
| `HoldArrow(source, reason?)` | a hold id, or nil and a reason. While any hold stands, `Journey.ArrowMode()` is `"held"`: no HUD arrow, EasyFind's character arrow hidden, the TomTom mirror removed and the beacon's edge arrow suppressed. The HUD keeps its steps. |
| `ReleaseArrow(holdID)` | true if that hold stood; the arrows come back as the player set them |
| `ArrowHeld()` | true while any hold stands, then `{ { id, source, reason } }` |

Rules: holds are not kept over `/reload`. A journey the player starts afterwards releases every hold (the player's newest choice leads); the same journey reported twice does not. Events: `hold(holdID, held, why)` and, for every journey, `ended(token|nil, how)` with `how` = `"arrived"` or `"cleared"`.

### Walks on the walking grid

Read-only use of EasyFind GPS's walking grid for an addon's own local routes (a farming loop's legs). Nothing here changes the grid's settings (roads, danger, drop limit) or the route being followed: walks are searched under the settings the grid holds at that moment, and `result.settings` says which.

| Function | Returns |
|---|---|
| `HasTerrain(mapID)` | whether the grid covers that map's continent |
| `LocalPath(spec)` — `{ mapID, ax, ay, bx, by (0-1), maxPoints? (2-200, 64), detour? (1.2-6, 4) }` | one walk, searched at once (up to about a tenth of a second for a long one). `status`: `straight` (the line is walkable), `path` (`points` = `{ x1, y1, ... }` on `mapID`, ends included), `detour` (no walk within `detour` x the line), `none` (no walk on foot), `nodata`, `far` (ends more than `LOCAL_MAX_YARDS` = 1500 apart), `invalid` (`reason`). Also `yards`, `straight`, `drops` (falls above the safe height) and `settings`. |
| `LocalPaths(spec, done)` — `{ mapID, legs = { {ax, ay, bx, by}, ... } (1-64), maxPoints?, detour?, budgetMs? (1-12) }` | a handle (`Cancel()`, `Status()`, `Progress()`), or nil and a reason. Walks the legs a few milliseconds a frame inside a coroutine that yields within searches; waits while Forever-GPS plans a route of its own and starts a search again if a plan ran across it (the grid's planning scratch is shared). `done(results, handle)` once all are walked; a cancelled batch never calls it. |
| `LocalBound(mapID, ax, ay, bx, by)` | the least a walk can cost, from the grid's landmarks, without a search; nil off the grid |

Points are pulled straight (Douglas-Peucker) to `maxPoints`, keeping the turns that matter. Measured on the real grid (desktop Lua 5.4, `tools/terrain_fixture.lua` in HarvestMate Enhanced): real 99- and 100-leg gathering loops took about 40-60 ms per leg, the slowest leg about 0.13 s, which is why `LocalPaths` exists.

### The nearest service

| Function | Returns |
|---|---|
| `NavigateToService(kind, spec?)` — `kind` = `mailbox`, `vendor`, `repair`, `inn`, `bank`, `auction` or `trainer` (`spec.profession` = "Skinning" ...) | true and the place's name, or false and a reason. Searches "nearest <kind>" with Forever-GPS's own search (enemy ground passed over) and opens that journey for the player to start with Go. A one-off trip: no token, and the caller's own guidance simply steps aside for it. |
