#!/usr/bin/env python3
"""Build the private, installable Forever-GPS package.

    python tools/package.py        # dist/ForeverGPS-<version>-forever.zip

The zip holds one folder, ForeverGPS, as tools/assemble.py puts it together, and it goes
in Interface/AddOns as it is. Questie and TomTom stay separate, optional installs.

This makes a local file. It never publishes anything.
"""
from __future__ import annotations

import re
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DIST = ROOT / "dist"
FOLDER = ROOT / "build" / "assembled" / "ForeverGPS"

# Patterns of what must never ship.
DEVELOPMENT = re.compile(r"(^|/)(tests?|\.github|__pycache__)/|\.py$|(^|/)\.[^/]+$|\.md\.bak$")
# Parts that must be there for it to be Forever-GPS at all.
REQUIRED = ("ForeverGPS.toc", "Bindings.xml", "Core/Preflight.lua", "Core/Namespace.lua", "Core/Bridge.lua", "Core/Imported.lua", "UI/HUD.lua",
            "Vendor/EasyFind/Core/Main.lua", "Vendor/EasyFind_GPS/GPS.lua", "Vendor/EasyFind_GPS/Data_Forever.lua",
            "Vendor/EasyFind_GPS/Walk_Kalimdor.lua", "Vendor/EasyFind_GPS/Walk_EasternKingdoms.lua",
            "Vendor/EasyFind_Questie/Quests.lua", "Vendor/EasyFind/LICENSE", "Vendor/EasyFind_GPS/LICENSE", "Vendor/EasyFind_Questie/LICENSE")
# Left out on purpose. Their presence would mean the assembly went wrong.
OTHER_CLIENTS = ("Data_Era", "Data_TBC", "Data_Mists", "Walk_Outland", "Walk_Northrend", "Npcs_Retail", "Walk_Kalimdor_Era")


def collect() -> dict[str, bytes]:
    return {p.relative_to(FOLDER).as_posix(): p.read_bytes() for p in sorted(FOLDER.rglob("*")) if p.is_file()}


def toc_files(text: str) -> list[str]:
    out = []
    for line in text.split("\n"):
        line = line.strip()
        if line and not line.startswith("#"):
            out.append(re.sub(r"\s+\[.*$", "", line).replace("\\", "/"))
    return out


def verify(files: dict[str, bytes]) -> list[str]:
    problems = []
    for name in REQUIRED:
        if name not in files:
            problems.append(f"missing {name}")
    tocs = [k for k in files if k.endswith(".toc")]
    if tocs != ["ForeverGPS.toc"]:
        problems.append(f"expected one TOC, found {tocs}")
    toc = files.get("ForeverGPS.toc", b"").decode("utf-8")
    if "\r" in toc:
        problems.append("carriage return in the TOC")
    if toc.split("\n", 1)[0].strip() != "## Interface: 16001":
        problems.append("the TOC's first line must name interface 16001")
    for file in toc_files(toc):
        if file not in files:
            problems.append(f"the TOC lists missing {file}")
    for key in files:
        if DEVELOPMENT.search(key):
            problems.append(f"{key}: development file in the package")
        if any(mark in key for mark in OTHER_CLIENTS):
            problems.append(f"{key}: another client's data")
    if len(files.get("Core/Imported.lua", b"")) > 400:
        problems.append("Core/Imported.lua must ship empty")
    return problems


def version() -> str:
    return re.search(r"^## Version:\s*(\S+)", (FOLDER / "ForeverGPS.toc").read_text(encoding="utf-8"), re.M).group(1)


def main() -> int:
    subprocess.run([sys.executable, "-I", str(ROOT / "tools" / "assemble.py"), "--quiet"], check=True)
    files = collect()
    problems = verify(files)
    for line in problems:
        print("FAIL", line)
    if problems:
        return 1
    DIST.mkdir(exist_ok=True)
    target = DIST / f"ForeverGPS-{version()}-forever.zip"
    with zipfile.ZipFile(target, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for key in sorted(files):
            info = zipfile.ZipInfo(f"ForeverGPS/{key}", date_time=(2026, 11, 6, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            z.writestr(info, files[key])
    size = sum(len(v) for v in files.values())
    print(f"{target.name}: {len(files)} files, {size / 1e6:.1f} MB unpacked, {target.stat().st_size / 1e6:.1f} MB zipped")
    print("Top-level folders: ForeverGPS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
