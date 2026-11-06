#!/usr/bin/env python3
"""Install the built package into a local WoW Forever client.

    python tools/install_local.py "<...>/World of Warcraft/_forever_"            # shows what it would do
    python tools/install_local.py "<...>/World of Warcraft/_forever_" --apply
    python tools/install_local.py "<...>/World of Warcraft/_forever_" --apply --wait      # as soon as the game closes

Moves the old separate folders out of Interface/AddOns into a backup beside it, so going
back is moving them home. It touches only the folders named in OURS, refuses to run while
the game is open, deletes nothing, and never writes to WTF. Then it unpacks the package
and carries over what the old folders saved.

Standard library only.
"""
from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import time
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CHECK_SECONDS, SETTLE_SECONDS = 15, 10
OURS = ("EasyFind", "EasyFind_Calc", "EasyFind_Clipboard", "EasyFind_GPS", "EasyFind_Guide", "EasyFind_Icons", "EasyFind_Items",
        "EasyFind_Onboarding", "EasyFind_Options", "EasyFind_Questie", "EasyFind_Quicklists", "EasyFind_Settings", "EasyFind_Snippets",
        "ForeverGPS")


def game_running() -> bool:
    if os.environ.get("FGPS_SKIP_GAME_CHECK"):      # tests, on a pretend install
        return False
    try:
        out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq Wow.exe"], capture_output=True, text=True, check=False).stdout
    except FileNotFoundError:
        return False
    return "Wow.exe" in out


def package() -> Path:
    toc = (ROOT / "addons" / "ForeverGPS" / "ForeverGPS.toc").read_text(encoding="utf-8")
    version = re.search(r"^## Version:\s*(\S+)", toc, re.M).group(1)
    return ROOT / "dist" / f"ForeverGPS-{version}-forever.zip"


def main(argv: list[str]) -> int:
    args = [a for a in argv[1:] if not a.startswith("--")]
    if not args:
        print(__doc__)
        return 2
    apply = "--apply" in argv
    forever = Path(args[0])
    addons = forever / "Interface" / "AddOns"
    zip_path = package()
    if not addons.is_dir():
        print(f"No AddOns folder at {addons}")
        return 1
    if not zip_path.is_file():
        print(f"No package at {zip_path}: run python tools/package.py")
        return 1
    if apply and "--wait" in argv:
        print("Waiting for the game to close.", flush=True)
        while game_running():
            time.sleep(CHECK_SECONDS)
        time.sleep(SETTLE_SECONDS)      # saved variables are written as it exits
    if game_running():
        print("The game is running. Close it first: it writes saved variables as it exits.")
        return 1
    with zipfile.ZipFile(zip_path) as z:
        tops = {name.split("/")[0] for name in z.namelist()}
    if tops != {"ForeverGPS"}:
        print(f"Refusing a package with these folders: {sorted(tops)}")
        return 1
    present = [name for name in OURS if (addons / name).is_dir()]
    backup = forever / f"ForeverGPS-backup-{time.strftime('%Y%m%d-%H%M%S')}"
    print(f"Package:  {zip_path.name}")
    print(f"Move out: {len(present)} folders, to {backup}")
    for name in present:
        print(f"  {name}")
    others = sorted(p.name for p in addons.iterdir() if p.is_dir() and p.name not in OURS)
    print(f"Left alone: {len(others)} other addons")
    if not apply:
        print("Nothing changed. Add --apply to do it.")
        return 0
    backup.mkdir()
    for name in present:
        shutil.move(str(addons / name), str(backup / name))
    with zipfile.ZipFile(zip_path) as z:
        z.extractall(addons)
    after = sorted(p.name for p in addons.iterdir() if p.is_dir() and p.name not in OURS)
    if after != others:
        print("Another addon changed. Stopping so you can look.")
        return 1
    done = subprocess.run([sys.executable, "-I", str(ROOT / "tools" / "migrate_saved.py"), str(forever)], check=False)
    print(f"Installed. Going back: move the folders in {backup.name} home, replacing ForeverGPS.")
    return done.returncode


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
