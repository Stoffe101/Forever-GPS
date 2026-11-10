# Upstream code

## Pins

| Addon | Version | Commit |
| --- | --- | --- |
| EasyFind | 5.2.0 | `b593508a6cc2e9ac93dc6fbae8d37a7ea323843b` |
| EasyFind GPS | 1.4.0 | `570600ac99e2ae746efe2e0cae3059ce6365a804` |
| EasyFind Questie | 1.2.1 | `d86ddc31846a009bd081f3fcf1079056de088b50` |

All three were the latest commits on their default branches on 2026-11-06. They are imported byte-exact from each commit's object store, without their `.github` folders, which mean nothing in a subfolder.

`UPSTREAM.lock.json` holds each file's git blob hash at its pin. This command, which CI also runs, fails on any vendored file that differs and is not declared below:

```bash
python tools/upstream.py verify
```

## Line endings

Addon Lua files carry binary blobs inside strings, and upstream's tests match exact source text. A CRLF conversion corrupts both, so `.gitattributes` turns all conversion off. Do not remove that line. On this machine `core.autocrlf` is on, and it broke 13 upstream tests until the checkout was made byte-exact.

## One folder

The vendored addons stay here as their authors wrote them, because this is where their test suites run and where an update lands. What ships is built from them by `tools/assemble.py`:

- Their TOCs are read and merged in order, EasyFind first, then GPS, the Questie extension and Forever-GPS, with only what Forever's client can load.
- Their files go under `Vendor/`, and `Interface\\AddOns\\EasyFind\\` paths are rewritten to match.
- Companion apps, tutorial art, tests and other clients' data stay behind.
- `EDITS` lists every exact change one folder needs. Each must match as many times as it says, so an upstream change that moves one of them fails the build rather than slipping past.
- `TAINT_EDITS` puts every change to the game's waypoint and tracking through one door, and stops writing to native pins. [TAINT.md](TAINT.md) says why. A test fails if any vendored file changes them outside that door.
- `PLANNING_EDITS` measures what a planning frame holds and starts unpacking in a fresh slice. The engine's answers do not change, and the golden tests hold it to that. It also narrows a creature search as a word is typed.
- `CONTINUITY_EDITS` asks Forever-GPS's `Core/Continuity.lua`, each second, whether the step under way has been left by another way of travelling.
- `LAUNCHER_EDITS` turns off EasyFind's minimap button, broker launcher and compartment entries. Forever-GPS has the one launcher.
- `ECONOMY_EDITS` adds a flight's fare, at the player's rate, to its weight for the money ways, and a hearth's minimum saving to its weight. With neither set, routes are unchanged.
- `LEFT_OUT` lists the two TOC entries with no place here: the GPS's guard, which asks the game about an addon called EasyFind, and EasyFind's update notices.
- The Questie extension had a private table, as every addon does. In one addon all files share one, so it gets a table of its own inside it.

Each LICENSE ships with its code under `Vendor/`.

To take a new version: update as in [Taking a new upstream version](#taking-a-new-upstream-version), then run `python tools/assemble.py`. A failed edit names the file and the text it expected.

## Patches

Every change to vendored code, as declared in `tools/upstream.py`. All are additive except the two bug fixes.

### `EasyFind_GPS/Npcs.lua`: two read-only accessors

Adds `N.SpotsOf(npcID)` and `N.ReactionOf(npcID, horde)`, for offering a creature's several locations and marking hostile ones. The data was there, but only inside local functions.

### `EasyFind_GPS/Jumps.lua`: bug fix

`Jumps.ShopTip`, the parachute tip, ran a trial plan with an unlimited drop height as the last thing `PlanOtherWays` did, and left the walking grid that way. After nearly every route start on Forever:

- the route's own walks could no longer be found, because they are keyed under the grid's settings. `OffRoute` treats a missing walk as "nothing to be off", so **off-route detection silently stopped**.
- any walk drawn afterwards could cross drops that kill.

The fix restores the character's own limit after the trial. It is worth sending upstream.

### `EasyFind_GPS/GPS.lua`: trips survive a reroute

`GPS.Rerouted` built a new route table without `stops` or `skipLearn`, so one wrong turn on a trip turned it into a route to the last stop. It now keeps both. `GPS.StopsAhead(route)` works out which stops are still ahead, by what they are, since saved routes come back as copies, and `Reroute` goes on from those instead of back round the ones already reached. Worth sending upstream.

`PlanStep` also takes its budget from `GPS.PlanBudget` when one is set, so it can follow the frame rate, and reports each slice's real cost to `GPS.OnPlanSlice`.

### `EasyFind/MapSearch/Search/Results.lua`: every instance on the row

The row for a service with many locations kept only the nearest. It now carries `allInstances` too, so Forever-GPS can choose the quickest by travel time and pass over enemy towns. Additive: one field.

### `EasyFind_Questie/Quests.lua`: public actions

Adds actions through EasyFind's API, so all Questie reading stays in this one addon. Guarded for an EasyFind without `RegisterAction`.

- `isReady` and `questSpots`: each objective's spots by the log's index, as Questie itself indexes them, plus the turn-in.
- `warmWorld`, `findWorld` and `worldSpots`: a name index over Questie's creatures and objects, built in slices at run time from the installed addon. Nothing from Questie's database enters this repository.

### `EasyFind_Questie/tools/tests/smoke_test.lua`

Covers those actions.

## Questie

Checked by reading Questie 12.6.2 as installed on this machine: every function `EasyFind_Questie` binds exists, `Questie.API.RegisterOnReady` and `RegisterForQuestUpdates` exist, and `QuestPointers` is a hashmap. No Questie code or data is in this repository.

## Taking a new upstream version

1. Clone the upstream repositories side by side, with `core.autocrlf=false`.
2. Change the versions and commits in `tools/upstream.py`.
3. Run `python tools/upstream.py vendor <folder>` then `python tools/upstream.py lock <folder>`. This overwrites the patches above.
4. Reapply each patch, and drop any upstream has since taken.
5. Run `python tools/upstream.py verify` and `python tools/run_tests.py`.
6. If something fails in `Bridge.lua`, that is the seam working: internals moved, and that one file adapts. `Bridge.Missing()` and `/fgps diag` name what is gone.

Note that the lock's patch list expects patched files to differ from upstream. A patch upstream has taken must be removed from `PATCHES` in `tools/upstream.py`.
