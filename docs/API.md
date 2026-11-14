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
