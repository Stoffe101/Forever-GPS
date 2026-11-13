# Upstream code

## Pins

| Addon | Version | Commit |
| --- | --- | --- |
| EasyFind | 5.3.0 | `a029fac24bf0fb8004f63406a9397dc7a60c910a` |
| EasyFind GPS | 1.6.0 | `ec713f984d080b7b52cf30de18ffd903c730fdae` |
| EasyFind Questie | 1.3.0 | `41f71ebe28d3ae65493b6b7234f057a84255f073` |

All three are their release tags of 2026-11-11, the newest on 2026-11-13. Before them, Forever-GPS 2.0–2.6 were on EasyFind 5.2.0 (`b593508`), GPS 1.4.0 (`570600a`) and the Questie extension 1.2.1 (`d86ddc3`). They are imported byte-exact from each commit's object store, without their `.github` folders, which mean nothing in a subfolder.

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
- `CONTINUITY_EDITS` asks Forever-GPS's `Core/Continuity.lua`, each second, whether the step under way has been left by another way of travelling. It also names the engine's reroute as `GPS.Reroute`, so a reroute can start the moment the planner is free.
- `LAUNCHER_EDITS` turns off EasyFind's minimap button, broker launcher and compartment entries. Forever-GPS has the one launcher.
- `ECONOMY_EDITS` adds a flight's fare, at the player's rate, to its weight for the money ways, and a hearth's minimum saving to its weight. With neither set, routes are unchanged.
- `LEFT_OUT` lists the two TOC entries with no place here: the GPS's guard, which asks the game about an addon called EasyFind, and EasyFind's update notices.
- The Questie extension had a private table, as every addon does. In one addon all files share one, so it gets a table of its own inside it.

Each LICENSE ships with its code under `Vendor/`.

To take a new version: update as in [Taking a new upstream version](#taking-a-new-upstream-version), then run `python tools/assemble.py`. A failed edit names the file and the text it expected.

## Patches

Every change to vendored code, as declared in `tools/upstream.py`. All are additive except the two bug fixes.

### `EasyFind/MapSearch/Npcs.lua`: two read-only accessors

Adds `N.SpotsOf(npcID)` and `N.ReactionOf(npcID, horde)`, for offering a creature's several locations and marking hostile ones. The data was there, but only inside local functions. Up to GPS 1.5 the creature catalog was the GPS's own (`EasyFind_GPS/Npcs.lua`, `ns.GPSNpcs`); from EasyFind 5.3.0 it is EasyFind's (`ns.Npcs`), and the two accessors moved with it unchanged. `Core/Bridge.lua` reads whichever is there.

### `EasyFind_GPS/Jumps.lua`: bug fix

`Jumps.ShopTip`, the parachute tip, ran a trial plan with an unlimited drop height as the last thing `PlanOtherWays` did, and left the walking grid that way. After nearly every route start on Forever:

- the route's own walks could no longer be found, because they are keyed under the grid's settings. `OffRoute` treats a missing walk as "nothing to be off", so **off-route detection silently stopped**.
- any walk drawn afterwards could cross drops that kill.

The fix restores the character's own limit after the trial. It is worth sending upstream.

### `EasyFind_GPS/GPS.lua`: trips survive a reroute

`GPS.Rerouted` built a new route table without `stops` or `skipLearn`, so one wrong turn on a trip turned it into a route to the last stop. GPS 1.6.0 keeps both itself now. `GPS.StopsAhead(route)` works out which stops are still ahead, by what they are, since saved routes come back as copies, and `Reroute` goes on from those instead of back round the ones already reached. Worth sending upstream.

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

The tools do it; a person reads the result. If something then fails in `Bridge.lua`, that is the seam working: internals moved, and that one file adapts. `Bridge.Missing()` and `/fgps diag` name what is gone. A patch upstream has taken must be removed from `PATCHES` in `tools/upstream.py`: the lock expects patched files to differ from upstream.

```bash
python tools/upstream.py update EasyFind v5.3.0 --version 5.3.0
python tools/assemble.py
python tools/run_tests.py
```

`update` replaces every unpatched file with upstream's at the new tag, and merges each declared patch three ways (the old upstream, the new upstream, ours) with `git merge-file`. A patch that does not merge is left with conflict markers, reported, and the command fails: nothing of ours is dropped silently, and nothing of upstream's either. Then `assemble.py` checks every assembly edit still matches as often as it says: an upstream rewrite of a spot we change fails the build and names it. The lock is rewritten for the new revision, and `verify` holds the result to it.

What the 5.3.0 / 1.6.0 / 1.3.0 update met, as an example of what to expect:

- **Merged cleanly:** the result row's instances, the parachute fix, the Questie extension's actions.
- **Conflicts, resolved by keeping both:** `GPS.lua`, where upstream added `StepPassed`, `StepReached` and `Replanned` beside our `StopsAhead`, and now keeps a trip's stops on a reroute itself; and the Questie extension's test, where both sides added a zone.
- **Moved:** the creature catalog, from the GPS to EasyFind; our two accessors moved with it.
- **Taken over by upstream:** our map door. EasyFind 5.3.0 has its own `MapSearch.TurnMap`, which opens the map through the client (`C_Map.OpenWorldMap`) and holds a turn asked for in a fight until it ends, so our version went. Ours lives on as counters for `/fgps diag` and the Gamepad UI guard. Upstream's waypoint door (`WaypointChange`, `GPS.GamePinChange`) now waits for the map; our edits add the wait for a fight, the check that a cleared waypoint is still the one asked about, and skip changes that change nothing.

## Watching upstream

`tools/upstream_watch.py` checks everything Forever-GPS is built on. `.github/workflows/upstream-watch.yml` runs it twice a day once it is on `main`, and by hand from the Actions tab:

| Dependency | How it is watched | When it moves |
| --- | --- | --- |
| EasyFind, EasyFind GPS, EasyFind Questie | Releases newer than the pins; their LICENSE compared (they are used by written permission: any change stops it) | An update is prepared on `upstream/<names>-<versions>`, merged as above, assembled, tested and packaged, and offered as a draft pull request against the development branch, marked failing when anything failed. One branch per set of versions. |
| Questie | Its newest release has every module and function Forever-GPS reads (`QUESTIE_CONTRACT`) | Reported. Questie is the player's own install: it is never bundled, installed or replaced. |
| CraftProfit, ForeverNet, profit, Easy Controller | Commits since the pins in `third_party/THIRD_PARTY.lock.json` | Reported for a person to read: their code was adapted, not copied. |
| WoW Forever client | The live build (Blizzard's version server) and the client's own UI code (Gethe/wow-ui-source, branch `forever`) | Every `C_` API Forever-GPS calls is looked up in the client's API documentation, missing and newly restricted ones flagged. A new build is never called compatible until played. |

Known versions live in `upstream/WATCH.json`: Questie 12.6.2 is the oldest known to work (a real install), 12.8.0 the newest checked; client build 70938 the newest checked, 70790 the newest actually played.

`python -I tools/tests/test_automation.py` tests the watch and the artifact rules against a pretend GitHub: no update, a patch, minor and major release, a malformed release, drafts, a deleted tag, a network failure, a rate limit, a license change, Questie's contract kept and broken, a branch already prepared.

What the workflow needs: GitHub runs schedules from the default branch only, so the workflow files have to be on `main` (a separate pull request carries them). For it to open pull requests, the repository setting "Allow GitHub Actions to create and approve pull requests" must be on. Pull requests opened with the workflow's token do not start CI on their own branch: the watch runs the suites itself, and the report is in the pull request.
