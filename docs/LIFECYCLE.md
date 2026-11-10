# Navigation lifecycle

What happens from typing a search to arriving, who owns each piece of state, and what each stage must leave untouched. This is the audit the 2.0 work started from. Each row marked *fixed* had a failing test first.

## The stages

| Stage | Owner | What changes | What must not change |
| --- | --- | --- | --- |
| Search | `Search.Run`, `Search.Price` | Results, in memory | Route, grid, saved settings |
| Select a result | `Search.Inspect` | `Planner.current` | The active route |
| Compare ways | `Planner.RunNext` | Grid settings, for the length of each plan | The active route's walks, once the plan ends |
| Preview on the map | `MapPreview` | Its own overlay, nothing else | EasyFind's map line, the map's zoom unless asked |
| Start | `Bridge.Commit` | `CharDB.route`, `wayAvoid`, the quest binding | |
| Walk | EasyFind GPS's ticker, `Follow` | `route.active`, `route.eta` | |
| Wait at a stop | `Journey.RideState` | The HUD's view only | The route. No countdown unless a ride has timed that loop |
| Ride | `Boats`, `UnitOnTaxi` | `route.stepEta` | |
| Arrive | `GPS.Arrive` | `route.arrived`, then cleared after 8 seconds | |
| Leave the route | `Reroute` | A new route table to the same place, keeping `stops` and `wayAvoid` | |
| Teleport away | `OffRoute` | As above | |
| Die | `GPS.LeadToCorpse` | A corpse step ahead of the current one | The rest of the route |
| Reload | `CharDB.route` | Route restored by EasyFind GPS | Settings the route uses, restored at login by `Bridge` |
| Objective finished | `Journey`, `Trip` | The route stops, or the stop drops out of a trip | Any route not bound to that quest |
| Cancel | `Bridge.Stop` | Route cleared, binding cleared, TomTom waypoint removed, the journey kept to resume | |

## Going another way (2.3)

The destination is kept until you arrive or stop. The route to it is not.

The engine only noticed two things: a walk gone astray, and a crossing taken to the wrong continent. So while it waited for a boat, a flight or a hearth, you could fly, ride or teleport anywhere on the same continent and it stayed on that step. Tests reproduced this before it was fixed.

`Core/Continuity.lua` is now asked each second, before the engine's own check:

| What happens | What it does |
| --- | --- |
| A flight that is not the planned step | Holds the route. Plans nothing in the air. The HUD says the route picks up where you land |
| Landing, from such a flight or somewhere other than the planned field | Plans once from where you are |
| A jump within a step (hearth, portal, teleport) that lands away from the step's end | Plans once from there |
| Walking more than 400 yards from both ends of a boat or tram you were waiting for | Plans once from there |
| Walking with a hearth ahead | Nothing. A hearth can be used from anywhere |
| A plan that fails | Keeps the destination and tries again 6 seconds later |
| Position unknown, or a reload mid-flight | Holds, then carries on as above |

The destination, a trip's stops ahead and the way you chose all carry through. A portal that completes its own step is not counted as a jump.

## Who owns what

- **The route under way** belongs to EasyFind GPS, in `CharDB.route`. Forever-GPS reads it and replaces it only through `GPS.Navigated`.
- **The walking grid's settings** are global, and walks are keyed under them. Anything that plans changes them. Every plan of ours passes through `Bridge.PlanOurs`, which puts them back when it ends, including when whoever asked has moved on.
- **A plan** owns its walks, read while its settings were live. That is what lets the map show any option at any time without touching the grid.
- **The quest binding** lives in `FG.char`, so it survives a reload with the route it belongs to.

## What the audit found

| Finding | Effect | Now |
| --- | --- | --- |
| A Safer route lost its settings on start | The arrow lost its walk, and off-route detection stopped | *Fixed.* `Commit` sets `wayAvoid` and restores the grid |
| The same after a reload | As above, after every `/reload` | *Fixed.* The login handler restores them |
| Trips lost their stops on reroute | A wrong turn on a trip became a one-stop route | *Fixed.* `GPS.Rerouted` keeps `stops`, a declared patch |
| A rerouted trip went back round stops already reached | Doubled back | *Fixed.* `GPS.StopsAhead` |
| 1.0.0 wrote EasyFind's arrow setting | Uninstalling left EasyFind's arrow off | *Fixed.* Held at run time, and the old write is undone by migration |
| First run overrode an existing EasyFind user's bar | EasyFind's bar vanished for someone who used it | *Fixed.* Existing users are left alone, and what is changed is kept so it can be put back |
| Starting while the other ways were still planning left the grid on that plan's settings | Same symptom as the first row | *Fixed.* `PlanOurs` always restores |
| A news line went with the HUD when the route ended | "Objective done" flashed and vanished | *Fixed.* The toast is its own frame |
| A slider's thumb was left to the client | A setting with nothing to grab | *Fixed.* Sliders are drawn in full here |
| `Jumps.ShopTip` left the grid at any drop height | Off-route detection stopped after nearly every start | *Fixed in 1.0.0*, a declared patch |
| Reports asked the game about addons that may not exist | One folder removed them, and the client need not answer | *Fixed.* The test client now raises, as the real one may |
| Reopening the window showed the old search | The journey under way was a click away | *Fixed.* Starting clears it |

## Client compatibility

`Diagnostics.API` lists every game function Forever-GPS calls directly. A static test keeps that list in step with the code, and `/fgps diag` and `/fgps report` probe each one at run time. An event the client does not know is counted and never heard, not raised.
