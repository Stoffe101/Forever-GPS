# Installing Forever-GPS

## 1. Build the package

You need Python 3. From the repository root:

```bash
python tools/package.py
```

That writes `dist/ForeverGPS-1.0.0-forever.zip`: about 13 MB, 41 MB unpacked, with only the data the Forever client can load. To keep every client's data, add `--full`.

## 2. Put it in place

Close the game, or expect to `/reload` afterwards. Unzip the package into your Forever AddOns folder, so that each top-level folder in the zip lands directly inside it:

```
<World of Warcraft>/_forever_/Interface/AddOns/
    EasyFind/
    EasyFind_Calc/
    EasyFind_Clipboard/
    EasyFind_GPS/
    EasyFind_Guide/
    EasyFind_Icons/
    EasyFind_Items/
    EasyFind_Onboarding/
    EasyFind_Options/
    EasyFind_Questie/
    EasyFind_Quicklists/
    EasyFind_Settings/
    EasyFind_Snippets/
    ForeverGPS/
```

On this machine that folder is `D:\Battle.net games\World of Warcraft\_forever_\Interface\AddOns`.

## 3. Check it in game

1. On the character screen, open AddOns and confirm **Forever-GPS** and the **EasyFind** entries are enabled. If the list says *Out of date*, your client's interface number has moved past 16001.
2. Log in and type `/fgps`. The window should open.
3. Type `/fgps diag`. It reports the client build, what loaded, and whether anything the addon depends on is missing.

## Optional addons

- **Questie**: objective locations for From Your Quests. Install it as usual; Forever-GPS finds it on its own. Questie 12.6.2 was checked against this build.
- **TomTom**: choose it under Settings, Direction arrow, if you prefer its arrow. Not required.

## Updating from 2.0

2.1 is one folder. The fourteen old folders must go: two copies of one addon cannot share a session.

The easy way, with the game closed:

```bash
python tools/package.py
```

```bash
python tools/install_local.py "D:/Battle.net games/World of Warcraft/_forever_"
```

That shows what it would do. Add `--apply` to do it, or `--apply --wait` to have it wait for the game to close. It moves only the old Forever-GPS folders into a dated `ForeverGPS-backup-...` folder beside `Interface`, unpacks the new one, and carries over what the old folders saved. It refuses to run while the game is open, and it leaves every other addon and all of `WTF` alone.

By hand:

1. Close the game.
2. Keep a copy of `_forever_/WTF`.
3. Move these out of `Interface/AddOns`: `EasyFind`, `EasyFind_Calc`, `EasyFind_Clipboard`, `EasyFind_GPS`, `EasyFind_Guide`, `EasyFind_Icons`, `EasyFind_Items`, `EasyFind_Onboarding`, `EasyFind_Options`, `EasyFind_Questie`, `EasyFind_Quicklists`, `EasyFind_Settings`, `EasyFind_Snippets`, `ForeverGPS`.
4. Unzip the package into `Interface/AddOns`.
5. Run `python tools/migrate_saved.py "<...>/_forever_"`, so known flight paths and the rest carry over.

**Check the folder is not nested.** The result must be `Interface/AddOns/ForeverGPS/ForeverGPS.toc`, not `Interface/AddOns/ForeverGPS-2.1.0-forever/ForeverGPS/...`. If the game does not list the addon, this is the usual reason.

### What carries over

| What | How |
| --- | --- |
| Favorites, recents, positions, theme, arrow, HUD and map choices, the way you pick first | Saved under `ForeverGPS`, so they stay where they are |
| Known flight paths, the route under way, your hearth, boat timings, what you avoid | Saved under `EasyFind`, which one folder cannot read, so `migrate_saved.py` writes them into `Core/Imported.lua`. Applied once at the next login, and never over anything newer |

Without that step Forever-GPS still works, and each character relearns its flight paths from the first flight master it opens.

Installed while the game was open? Saved data only reaches the disk as it exits, so run `python tools/migrate_saved.py "<...>/_forever_" --wait` to carry it over the moment it closes. Avoid `/reload` until the game has been restarted: the running client still holds the old addon list.

If the old folders are still enabled at login, Forever-GPS offers to turn them off and reload.

## Checking it loaded

```
/fgps report
```

Expect `[ok] Route engine ready` and a `Built on:` line naming EasyFind, EasyFind_GPS and EasyFind_Questie. `[broken] Old folders still enabled` means something was left behind.

## Rolling back

Move the folders in `ForeverGPS-backup-...` back into `Interface/AddOns`, replacing `ForeverGPS`. Nothing in `WTF` was changed, so 2.0 finds what it left, and ignores the settings it does not know. `dist/ForeverGPS-2.0.0-forever.zip` is the same thing as a package.

## Removing it

Delete `ForeverGPS` from `Interface/AddOns`. Questie and TomTom are separate and stay.

## First run

Run the five-minute [first-run check](FIRST_RUN.md).
