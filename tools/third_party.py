#!/usr/bin/env python3
"""Check the MIT-licensed upstream files Forever-GPS reuses.

    python tools/third_party.py verify

- Every file in third_party/ matches the hash pinned in third_party/THIRD_PARTY.lock.json,
  and nothing unlisted sits there.
- Each upstream LICENSE ships, unchanged, in addons/ForeverGPS/Licenses/.
- Each module adapted from upstream code names its source at the top.
- The packed recipe data is what tools/recipes_import.py makes from the pinned files.

docs/REUSE.md says what was taken and why; THIRD_PARTY.md is the provenance record.
Standard library only.
"""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BASE = ROOT / "third_party"
LOCK = BASE / "THIRD_PARTY.lock.json"
SHIPPED = ROOT / "addons" / "ForeverGPS" / "Licenses"

# Adapted module -> what its header must name.
ADAPTED = {
    "addons/ForeverGPS/Core/Market.lua": ("CraftProfit", "79e8eda"),
    "addons/ForeverGPS/Core/MarketSearch.lua": ("CraftProfit", "79e8eda"),
    "addons/ForeverGPS/Core/Quote.lua": ("ForeverNet", "10a81d9"),
    "addons/ForeverGPS/Data/Recipes.lua": ("profit", "823413b"),
    "addons/ForeverGPS/Core/Pad.lua": ("Easy Controller", "cf2ad94"),
}


def problems() -> list[str]:
    found: list[str] = []
    lock = json.loads(LOCK.read_text(encoding="utf-8"))
    listed = {LOCK.resolve()}
    for name, entry in lock.items():
        for local, meta in entry["files"].items():
            path = BASE / name / local
            listed.add(path.resolve())
            if not path.is_file():
                found.append(f"{name}/{local}: missing")
                continue
            if hashlib.sha256(path.read_bytes()).hexdigest() != meta["sha256"]:
                found.append(f"{name}/{local}: differs from the pinned upstream file")
        lic = BASE / name / "LICENSE"
        shipped = SHIPPED / f"{name}-LICENSE.txt"
        if not shipped.is_file():
            found.append(f"{name}: its license is not shipped as Licenses/{shipped.name}")
        elif lic.is_file() and shipped.read_bytes() != lic.read_bytes():
            found.append(f"{name}: the shipped license differs from upstream's")
    for path in BASE.rglob("*"):
        if path.is_file() and path.resolve() not in listed:
            found.append(f"{path.relative_to(ROOT).as_posix()}: not in the lock")
    for rel, (name, commit) in ADAPTED.items():
        path = ROOT / rel
        if not path.is_file():
            found.append(f"{rel}: missing")
            continue
        head = path.read_text(encoding="utf-8")[:1500]
        if name not in head or commit not in head or "MIT" not in head:
            found.append(f"{rel}: its header must name {name}, commit {commit} and the MIT license")
    sys.path.insert(0, str(ROOT / "tools"))
    import recipes_import  # noqa: E402  (a sibling tool, standard library only)
    data = ROOT / "addons" / "ForeverGPS" / "Data" / "Recipes.lua"
    if data.is_file() and data.read_bytes() != recipes_import.render().encode("utf-8"):
        found.append("Data/Recipes.lua: out of date, run tools/recipes_import.py")
    return found


def main(argv: list[str]) -> int:
    if argv[1:] != ["verify"]:
        print(__doc__)
        return 2
    found = problems()
    for line in found:
        print("third_party:", line)
    if not found:
        print("third_party: every reused file matches its pin, licenses ship, sources are named")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
