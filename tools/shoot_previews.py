"""Takes pictures of the rendered previews, for looking at several in one go.

    python tools/shoot_previews.py fullhd-default-home fullhd-worst-journey ...
    python tools/shoot_previews.py --all fullhd-worst

Needs a local Chromium browser (Edge or Chrome). Run tools/ui_preview.lua first.
Pictures land in build/shots/. These are renders of the addon's layout in a stand-in
client, not screenshots of the game.
"""
from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PREVIEW = ROOT / "build" / "preview"
SHOTS = ROOT / "build" / "shots"

CANDIDATES = [
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
]


def browser() -> str:
    for path in CANDIDATES:
        if os.path.exists(path):
            return path
    for name in ("chromium", "chromium-browser", "google-chrome", "msedge"):
        found = shutil.which(name)
        if found:
            return found
    raise SystemExit("No Chromium browser found.")


def size_of(page: Path) -> tuple[int, int]:
    text = page.read_text(encoding="utf-8", errors="replace")
    m = re.search(r'class="screen" style="width:(\d+)px;height:(\d+)px', text)
    return (int(m.group(1)), int(m.group(2))) if m else (1920, 1080)


def shoot(exe: str, name: str) -> None:
    page = PREVIEW / f"{name}.html"
    if not page.exists():
        print(f"{name}: no such render")
        return
    w, h = size_of(page)
    out = SHOTS / f"{name}.png"
    # A profile of its own: a browser that has just exited keeps its profile locked.
    profile = ROOT / "build" / "browser-profiles" / name
    subprocess.run(
        [exe, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--no-first-run",
         f"--user-data-dir={profile}", f"--screenshot={out}", f"--window-size={w},{h}",
         "--virtual-time-budget=6000", f"http://127.0.0.1:8931/{name}.html"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=60, check=False,
    )
    print(f"{name}: {'ok' if out.exists() else 'failed'}")
    shutil.rmtree(profile, ignore_errors=True)


def main() -> None:
    SHOTS.mkdir(parents=True, exist_ok=True)
    args = sys.argv[1:]
    if args and args[0] == "--all":
        prefix = args[1] if len(args) > 1 else ""
        args = sorted(p.stem for p in PREVIEW.glob(f"{prefix}*.html"))
    exe = browser()
    for name in args:
        shoot(exe, name)


if __name__ == "__main__":
    main()
