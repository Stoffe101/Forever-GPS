#!/usr/bin/env python3
"""Build the private, installable Forever-GPS package.

    python tools/package.py                      # dist/ForeverGPS-<version>-forever.zip
    python tools/package.py --full               # keep every client's data
    python tools/package.py --compare <zip>      # also diff EasyFind against an official zip

The zip's top level is what goes in Interface/AddOns, laid out as EasyFind's own
releases are: each Apps/<Name> companion becomes a top-level EasyFind_<Name>.

The default build keeps only what the Forever client can load: a file a TOC line
restricts to another game type goes, and so does that line. Nothing is rewritten
otherwise. Line endings and data blobs pass through byte for byte.

This makes a local file. It never publishes anything.
"""
from __future__ import annotations

import re
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ADDONS = ROOT / "addons"
DIST = ROOT / "dist"

# Development files, in any addon.
SKIP_PARTS = {"tests", "dev", ".github", "__pycache__"}
SKIP_NAMES = {".gitattributes", ".gitignore", ".luacheckrc", ".luarc.json"}
# A tool folder that only holds tests.
SKIP_PREFIX = {"EasyFind_Questie": ("tools/",), "EasyFind": ("API/",)}

RULE = re.compile(r"\[(\w+)\s+([^\]]+)\]")


def allowed_on_forever(rules: str) -> bool:
    for kind, value in RULE.findall(rules):
        if kind == "AllowLoadGameType" and "camelot" not in value:
            return False
    return True


def toc_entries(text: str) -> list[tuple[str, str, str]]:
    """(raw line, file, rules) for each file line."""
    out = []
    for line in text.split("\n"):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        match = re.match(r"^(.*?)\s+(\[.*\])$", stripped)
        file, rules = (match.group(1), match.group(2)) if match else (stripped, "")
        out.append((line, file.replace("\\", "/"), rules))
    return out


def strip_toc(text: str) -> tuple[str, set[str]]:
    """The TOC with other clients' lines gone, and the files those lines named."""
    dropped: set[str] = set()
    keep = text
    for line, file, rules in toc_entries(text):
        if not allowed_on_forever(rules):
            dropped.add(file)
            keep = keep.replace(line + "\n", "", 1)
    still = {file for _, file, _ in toc_entries(keep)}
    return keep, dropped - still


def addon_files(name: str, base: Path) -> list[tuple[str, Path]]:
    prefixes = SKIP_PREFIX.get(name, ())
    out = []
    for path in sorted(base.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(base).as_posix()
        parts = rel.split("/")
        if SKIP_PARTS.intersection(parts) or parts[-1] in SKIP_NAMES:
            continue
        if rel.startswith(prefixes) if prefixes else False:
            continue
        out.append((rel, path))
    return out


def collect(full: bool) -> dict[str, bytes]:
    files: dict[str, bytes] = {}

    def add(addon: str, base: Path, skip_apps: bool = False) -> None:
        tocs = {}
        for rel, path in addon_files(addon, base):
            if skip_apps and rel.startswith("Apps/"):
                continue
            tocs[rel] = path
        dropped: set[str] = set()
        toc_text = {}
        for rel, path in tocs.items():
            if rel.endswith(".toc") and "/" not in rel:
                text = path.read_bytes().decode("utf-8")
                if not full:
                    text, gone = strip_toc(text)
                    dropped |= gone
                toc_text[rel] = text
        for rel, path in tocs.items():
            if rel in dropped:
                continue
            key = f"{addon}/{rel}"
            files[key] = toc_text[rel].encode("utf-8") if rel in toc_text else path.read_bytes()

    add("EasyFind", ADDONS / "EasyFind", skip_apps=True)
    for app in sorted((ADDONS / "EasyFind" / "Apps").iterdir()):
        toc = next(app.glob("EasyFind_*.toc"), None)
        if toc:
            add(toc.stem, app)
    add("EasyFind_GPS", ADDONS / "EasyFind_GPS")
    add("EasyFind_Questie", ADDONS / "EasyFind_Questie")
    add("ForeverGPS", ADDONS / "ForeverGPS")
    return files


def verify(files: dict[str, bytes]) -> list[str]:
    problems = []
    tocs = [k for k in files if k.endswith(".toc") and k.count("/") == 1]
    for key in tocs:
        folder, name = key.split("/")
        if name != folder + ".toc":
            problems.append(f"{key}: a toc must be named after its folder")
        text = files[key].decode("utf-8")
        if "\r" in text:
            problems.append(f"{key}: carriage return")
        if "16001" not in text.split("\n", 1)[0]:
            problems.append(f"{key}: no 16001 on its Interface line")
        for _, file, _ in toc_entries(text):
            if f"{folder}/{file}" not in files:
                problems.append(f"{key}: lists missing {file}")
    want = {"EasyFind", "EasyFind_GPS", "EasyFind_Questie", "ForeverGPS"}
    have = {k.split("/")[0] for k in files}
    for name in sorted(want - have):
        problems.append(f"missing addon folder {name}")
    for key in files:
        if "/tests/" in key or key.endswith(".py"):
            problems.append(f"{key}: development file in the package")
    return problems


def compare(files: dict[str, bytes], zip_path: Path) -> None:
    official = zipfile.ZipFile(zip_path)
    theirs = {n for n in official.namelist() if not n.endswith("/")}
    ours = {k for k in files if k.split("/")[0].startswith("EasyFind") and not k.startswith(("EasyFind_GPS/", "EasyFind_Questie/"))}
    print(f"official: {len(theirs)} files, ours: {len(ours)}")
    for name in sorted(theirs - ours)[:20]:
        print("  only official:", name)
    for name in sorted(ours - theirs)[:20]:
        print("  only ours:", name)
    differ = [n for n in sorted(theirs & ours) if official.read(n) != files[n]]
    print(f"  same path, different bytes: {len(differ)}")
    for name in differ[:10]:
        print("   ", name)


def version() -> str:
    toc = (ADDONS / "ForeverGPS" / "ForeverGPS.toc").read_text(encoding="utf-8")
    return re.search(r"^## Version:\s*(\S+)", toc, re.M).group(1)


def main(argv: list[str]) -> int:
    full = "--full" in argv
    files = collect(full)
    problems = verify(files)
    for line in problems:
        print("FAIL", line)
    if problems:
        return 1
    DIST.mkdir(exist_ok=True)
    flavor = "all-clients" if full else "forever"
    target = DIST / f"ForeverGPS-{version()}-{flavor}.zip"
    with zipfile.ZipFile(target, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for key in sorted(files):
            info = zipfile.ZipInfo(key, date_time=(2026, 11, 6, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            z.writestr(info, files[key])
    size = sum(len(v) for v in files.values())
    print(f"{target.name}: {len(files)} files, {size / 1e6:.1f} MB unpacked, {target.stat().st_size / 1e6:.1f} MB zipped")
    print("Top-level folders:", " ".join(sorted({k.split('/')[0] for k in files})))
    if "--compare" in argv:
        compare(files, Path(argv[argv.index("--compare") + 1]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
