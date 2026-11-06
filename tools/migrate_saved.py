#!/usr/bin/env python3
"""Carry what the separate EasyFind folders saved into the one ForeverGPS folder.

    python tools/migrate_saved.py <_forever_ folder> [--into <ForeverGPS folder>]

WoW hands an addon only the saved variables filed under its own name. Forever-GPS's
favorites, recents, positions and settings are under ForeverGPS and carry straight
over. What EasyFind GPS kept is under EasyFind: known flight paths, the route under
way, your hearth, boat timings, the transport you avoid. Without this they would be
stranded, and each character would need every flight master visited again.

This reads WTF and never writes to it, so going back to 2.0 stays exact. It writes
Core/Imported.lua in the installed addon, which applies once at the next login and
never overwrites anything newer. Run it with the game closed: the game writes saved
variables when it exits.

Standard library only.
"""
from __future__ import annotations

import re
import sys
import time
from pathlib import Path

HEADER = """-- Written by tools/migrate_saved.py from what the separate EasyFind folders saved, so
-- nothing has to be learned again. Applied once, and only where nothing newer exists.
"""
BLOCK = """local function Saved{index}()
    local EasyFindDB
{text}
    return EasyFindDB
end
"""
# The saved-variables file is plain assignments, so it can be read in place: inside a
# function that holds EasyFindDB as a local, its assignment lands there.
ASSIGNMENT = re.compile(r"^EasyFindDB\s*=", re.M)


def sources(forever: Path) -> list[Path]:
    found = []
    for account in sorted((forever / "WTF" / "Account").glob("*")):
        path = account / "SavedVariables" / "EasyFind.lua"
        if path.is_file():
            found.append(path)
    return found


def render(paths: list[Path], stamp: str) -> str:
    out = [HEADER]
    calls = []
    for index, path in enumerate(paths, 1):
        text = path.read_text(encoding="utf-8", errors="replace")
        if not ASSIGNMENT.search(text):
            continue
        out.append(BLOCK.format(index=index, text=text))
        calls.append(f"Saved{index}()")
    out.append(f'ForeverGPSImported = {{ id = "{stamp}", accounts = {{ {", ".join(calls)} }} }}\n')
    return "\n".join(out)


def main(argv: list[str]) -> int:
    args = [a for a in argv[1:] if not a.startswith("--")]
    if not args:
        print(__doc__)
        return 2
    forever = Path(args[0])
    into = Path(argv[argv.index("--into") + 1]) if "--into" in argv else forever / "Interface" / "AddOns" / "ForeverGPS"
    if not (into / "ForeverGPS.toc").is_file():
        print(f"No ForeverGPS addon at {into}")
        return 1
    paths = sources(forever)
    if not paths:
        print("No EasyFind saved variables found: nothing to carry over.")
        return 0
    target = into / "Core" / "Imported.lua"
    target.write_text(render(paths, time.strftime("%Y%m%d%H%M%S")), encoding="utf-8", newline="\n")
    print(f"Carried over {len(paths)} account file(s) into {target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
