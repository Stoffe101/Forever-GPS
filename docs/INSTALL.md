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

## Updating and removing

To update, delete the folders above and unzip the new package. Settings live in `WTF` and survive that. To remove it, delete `ForeverGPS` and, if you do not want EasyFind either, the `EasyFind*` folders.

If you remove only Forever-GPS, two things it changed stay changed in EasyFind's own settings: EasyFind's search bar stays hidden, and EasyFind's arrow at the character may stay off. Both are in EasyFind's options.

## First run

Forever-GPS is meant to be the way in, so on a new install it skips EasyFind's tutorial and hides EasyFind's own search bar. Settings has a switch to bring the bar back.
