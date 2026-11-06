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

## Patches

Every change to vendored code. All are additive except the bug fix.

### `EasyFind_GPS/Npcs.lua`: two read-only accessors

Adds `N.SpotsOf(npcID)` and `N.ReactionOf(npcID, horde)`, for offering a creature's several locations and marking hostile ones. The data was there, but only inside local functions.

### `EasyFind_GPS/Jumps.lua`: bug fix

`Jumps.ShopTip`, the parachute tip, ran a trial plan with an unlimited drop height as the last thing `PlanOtherWays` did, and left the walking grid that way. After nearly every route start on Forever:

- the route's own walks could no longer be found, because they are keyed under the grid's settings. `OffRoute` treats a missing walk as "nothing to be off", so **off-route detection silently stopped**.
- any walk drawn afterwards could cross drops that kill.

The fix restores the character's own limit after the trial. It is worth sending upstream.

### `EasyFind_Questie/Quests.lua`: public actions

Adds the `isReady` and `questSpots` actions through EasyFind's API, so all Questie reading stays in this one addon. `questSpots` returns each objective's spots by the log's index, as Questie itself indexes them, plus the turn-in. Guarded for an EasyFind without `RegisterAction`.

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
