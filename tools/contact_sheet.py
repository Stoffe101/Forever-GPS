#!/usr/bin/env python3
"""One picture of many renders, to look them over side by side.

    python -I tools/contact_sheet.py <name> <shot-prefix>...

Lays out build/shots/<prefix>*.png in a labelled grid, as build/shots/contact-<name>.html,
then takes its picture as build/shots/contact-<name>.png with the browser that
tools/shoot_previews.py uses. Serve build/shots first:
`python -I -m http.server 8932 --bind 127.0.0.1 --directory build/shots`. These are renders of the addon's layout in a stand-in client, not game screenshots.
Standard library only.
"""
from __future__ import annotations

import html
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHOTS = ROOT / "build" / "shots"
sys.path.insert(0, str(ROOT / "tools"))
import shoot_previews  # noqa: E402  (a sibling tool)

COLUMNS, THUMB = 4, 560


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(__doc__)
        return 2
    name, prefixes = argv[1], argv[2:]
    shots = sorted({p for prefix in prefixes for p in SHOTS.glob(f"{prefix}*.png") if not p.name.startswith("contact-")})
    if not shots:
        print("contact_sheet: no shots match")
        return 1
    cells = "".join(
        f'<figure><img src="{html.escape(p.name)}"><figcaption>{html.escape(p.stem)}</figcaption></figure>' for p in shots)
    rows = (len(shots) + COLUMNS - 1) // COLUMNS
    width, height = COLUMNS * (THUMB + 16) + 32, rows * (THUMB * 9 // 16 + 48) + 96
    page = SHOTS / f"contact-{name}.html"
    page.write_text(
        "<!doctype html><meta charset=utf-8><title>Forever-GPS contact sheet</title><style>"
        "body{margin:16px;background:#14181e;color:#e8ecf1;font:13px system-ui}"
        f"main{{display:grid;grid-template-columns:repeat({COLUMNS},{THUMB}px);gap:16px}}"
        f"img{{width:{THUMB}px;height:{THUMB * 9 // 16}px;object-fit:contain;background:#000;display:block}}"
        "figure{margin:0}figcaption{padding-top:4px;color:#9aa6b2}</style>"
        f"<h1 style='font-size:16px'>{html.escape(name)}: renders in a stand-in client, not game screenshots</h1>"
        f"<main>{cells}</main>", encoding="utf-8")
    exe = shoot_previews.browser()
    out = SHOTS / f"contact-{name}.png"
    profile = ROOT / "build" / "browser-profiles" / f"contact-{name}"
    subprocess.run(
        [exe, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--no-first-run", f"--user-data-dir={profile}",
         f"--screenshot={out}", f"--window-size={width},{height}", "--virtual-time-budget=8000",
         f"http://127.0.0.1:8932/{page.name}"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=90, check=False)
    shutil.rmtree(profile, ignore_errors=True)
    print(f"contact_sheet: {len(shots)} shots in {out.relative_to(ROOT).as_posix()}" if out.exists() else "contact_sheet: failed")
    return 0 if out.exists() else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
