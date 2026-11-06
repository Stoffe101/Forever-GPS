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

## Updating from 1.0.0

1. Close the game. An addon cannot be replaced safely while the client is running.
2. Keep a copy of `_forever_/WTF` if you want a way back.
3. Delete the old `ForeverGPS` and `EasyFind*` folders from `Interface/AddOns`.
4. Unzip the new package into `Interface/AddOns`.

**Check the folders are not nested.** The result must be `Interface/AddOns/ForeverGPS/ForeverGPS.toc`, not `Interface/AddOns/ForeverGPS-2.0.0-forever/ForeverGPS/...`. If the game does not list the addon, this is the usual reason.

Your preferences live in `WTF`, so they survive this. Favorites, recent places, positions, theme and arrow choice all carry over. On first load 2.0.0 undoes the one thing 1.0.0 should not have done, which was to write EasyFind's arrow setting, and sizes you never changed become sizes that suit your screen.

## Rolling back

Delete the folders and unzip the previous package. 1.0.0 ignores settings it does not know, so `WTF` need not change. If you kept a copy of `WTF`, restoring it puts everything back exactly.

## Removing it

Delete `ForeverGPS` and, if you do not want EasyFind either, the `EasyFind*` folders. If you are keeping EasyFind, first use Settings, Integrations, Restore EasyFind's settings, which puts back the search bar and welcome that first run changed.

## First run

Forever-GPS is meant to be the way in, so on a new install it skips EasyFind's tutorial and hides EasyFind's own search bar. If you already use EasyFind, it leaves all of that alone. Settings has a switch to bring the bar back.

Then run the five-minute [first-run check](FIRST_RUN.md).
