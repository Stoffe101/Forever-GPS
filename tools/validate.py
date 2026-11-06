#!/usr/bin/env python3
"""Repository checks that need no game and no Lua runtime.

    python tools/validate.py

Fails on: an addon file the TOC lists that does not exist or a Lua file it forgets; a
texture the code names that is not in Art; an art file nothing can draw; a missing
license, notice or provenance document; a changelog that has not heard of the version;
or stray local paths and secrets in what would be published. Prints what it checked.
"""
from __future__ import annotations

import re
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ADDON = ROOT / "addons" / "ForeverGPS"

problems: list[str] = []


def check(ok: bool, message: str) -> None:
    if not ok:
        problems.append(message)


def toc_files() -> list[str]:
    out = []
    for line in (ADDON / "ForeverGPS.toc").read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            out.append(line.split()[0].replace("\\", "/"))
    return out


def version() -> str:
    text = (ADDON / "ForeverGPS.toc").read_text(encoding="utf-8")
    m = re.search(r"^## Version:\s*(\S+)", text, re.M)
    return m.group(1) if m else ""


def validate_toc() -> None:
    listed = toc_files()
    for name in listed:
        check((ADDON / name).exists(), f"TOC lists a missing file: {name}")
    lua = {p.relative_to(ADDON).as_posix() for p in ADDON.rglob("*.lua")}
    for name in sorted(lua - set(listed)):
        check(False, f"Lua file the TOC never loads: {name}")
    check(len(listed) == len(set(listed)), "TOC lists a file twice")


def validate_art() -> int:
    art = ADDON / "Art"
    names = {p.stem for p in art.glob("*.tga")}
    for path in art.glob("*.tga"):
        head = path.read_bytes()[:18]
        width, height = struct.unpack("<HH", head[12:16])
        check(width == height and width & (width - 1) == 0, f"{path.name}: the game needs a power of two: {width}x{height}")
        check(head[2] == 2 and head[16] == 32, f"{path.name}: expected uncompressed 32-bit TGA")
    # Names handed to an icon setter, or read from the kinds table.
    source = "\n".join(p.read_text(encoding="utf-8") for p in ADDON.rglob("*.lua"))
    used = set(re.findall(r'SetIcon\("([a-z][a-z-]*)"\)', source))
    used |= set(re.findall(r'icon = "([a-z][a-z-]*)"', source))
    used |= set(re.findall(r'IconButton\([\w.]+, "([a-z][a-z-]*)"', source))
    used |= set(re.findall(r'FG\.ART \.\. "([a-z][a-z-]*)"', source))
    for name in sorted(used):
        check(name in names, f"code names a texture that does not exist: {name}")
    return len(names)


def validate_notices() -> None:
    for name in ("NOTICE.md", "UPSTREAM.lock.json", "docs/UPSTREAM.md", "docs/ARCHITECTURE.md", "docs/INSTALL.md",
                 "docs/MANUAL_TESTING.md", "docs/KNOWN_LIMITATIONS.md", "CHANGELOG.md", "README.md"):
        check((ROOT / name).exists(), f"missing: {name}")
    for folder in ("EasyFind", "EasyFind_GPS", "EasyFind_Questie"):
        base = ROOT / "addons" / folder
        found = [p for p in base.iterdir() if p.name.upper().startswith(("LICENSE", "COPYING"))]
        check(bool(found), f"{folder} has lost its license file")


def validate_version() -> None:
    v = version()
    check(bool(v), "the TOC has no version")
    changelog = (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
    check(v in changelog, f"CHANGELOG.md does not mention {v}")


def validate_clean() -> None:
    # What ships must not carry this machine's paths or anything resembling a secret.
    pattern = re.compile(r"(C:\\\\Users\\\\|/home/\w+/|BEGIN (RSA|OPENSSH) PRIVATE KEY|ghp_[A-Za-z0-9]{20,})")
    for path in list(ADDON.rglob("*.lua")) + list((ROOT / "docs").rglob("*.md")):
        text = path.read_text(encoding="utf-8", errors="replace")
        match = pattern.search(text)
        check(match is None, f"{path.relative_to(ROOT)} contains {match.group(0) if match else ''}")


def main() -> int:
    validate_toc()
    textures = validate_art()
    validate_notices()
    validate_version()
    validate_clean()
    if problems:
        for problem in problems:
            print("FAIL:", problem)
        return 1
    print(f"OK: {len(toc_files())} TOC files, {textures} textures, notices, version {version()}, no stray paths or secrets")
    return 0


if __name__ == "__main__":
    sys.exit(main())
