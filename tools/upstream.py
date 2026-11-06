#!/usr/bin/env python3
"""Vendor the upstream addons and verify they stay byte-exact.

    python tools/upstream.py vendor <checkout-root>   # copy pinned trees in
    python tools/upstream.py lock   <checkout-root>   # (re)write UPSTREAM.lock.json
    python tools/upstream.py verify                   # check addons/ against the lock

The lock records, per addon, the upstream repository, version and commit, and
each file's git blob hash at that commit. `verify` fails when a vendored file
changed without being declared in PATCHES below, or when a declared patch no
longer differs from upstream. CI runs it, so an unrecorded edit to third-party
code cannot land, and a CRLF conversion of a data blob is caught immediately.

Standard library only. Any path handed in is treated as data.
"""
from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ADDONS = ROOT / "addons"
LOCK = ROOT / "UPSTREAM.lock.json"

UPSTREAMS = {
    "EasyFind": {
        "repo": "https://github.com/fallenguards/EasyFind",
        "version": "5.2.0",
        "rev": "b593508a6cc2e9ac93dc6fbae8d37a7ea323843b",
    },
    "EasyFind_GPS": {
        "repo": "https://github.com/fallenguards/EasyFind_GPS",
        "version": "1.4.0",
        "rev": "570600ac99e2ae746efe2e0cae3059ce6365a804",
    },
    "EasyFind_Questie": {
        "repo": "https://github.com/fallenguards/EasyFind_Questie",
        "version": "1.2.1",
        "rev": "d86ddc31846a009bd081f3fcf1079056de088b50",
    },
}

# Upstream's own CI lives in .github, which has no meaning in a subfolder.
SKIP_PREFIXES = (".github/",)

# Every intentional change to vendored code, with why. docs/UPSTREAM.md explains
# each one; `verify` insists this list matches what is on disk.
PATCHES = {
    "EasyFind": {
        "MapSearch/Search/Results.lua": "Keeps a folded row's instances on the row, so one can be chosen by travel time.",
    },
    "EasyFind_GPS": {
        "GPS.lua": "Fixes trips losing their stops on a reroute, and returning to stops already reached. Lets the plan budget follow the frame rate.",
        "Npcs.lua": "Adds N.SpotsOf and N.ReactionOf: read-only access to a creature's spawns and its reaction.",
        "Jumps.lua": "Fixes ShopTip leaving the walking grid at an unlimited drop height, which lost the route's walks.",
    },
    "EasyFind_Questie": {
        "Quests.lua": "Exports quest spots, and a name index over Questie's creatures and objects, as public EasyFind actions.",
        "tools/tests/smoke_test.lua": "Covers the new actions.",
    },
}


def git_blob_hash(data: bytes) -> str:
    h = hashlib.sha1()
    h.update(b"blob %d\0" % len(data))
    h.update(data)
    return h.hexdigest()


def tracked(checkout: Path, rev: str) -> list[str]:
    out = subprocess.run(
        ["git", "-C", str(checkout), "ls-tree", "-r", "--name-only", rev],
        check=True, capture_output=True, text=True, encoding="utf-8",
    ).stdout
    return [p for p in out.splitlines() if p and not p.startswith(SKIP_PREFIXES)]


def blob(checkout: Path, rev: str, path: str) -> bytes:
    return subprocess.run(
        ["git", "-C", str(checkout), "cat-file", "blob", f"{rev}:{path}"],
        check=True, capture_output=True,
    ).stdout


def vendor(source: Path) -> None:
    for name, up in UPSTREAMS.items():
        checkout = source / name
        dest = ADDONS / name
        if dest.exists():
            shutil.rmtree(dest)
        files = tracked(checkout, up["rev"])
        for rel in files:
            target = dest / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            # Taken from the object store, so the checkout's autocrlf cannot touch it.
            target.write_bytes(blob(checkout, up["rev"], rel))
        print(f"{name}: {len(files)} files at {up['rev'][:10]}")


def lock(source: Path) -> None:
    out = {}
    for name, up in UPSTREAMS.items():
        checkout = source / name
        files = {}
        for rel in tracked(checkout, up["rev"]):
            files[rel] = git_blob_hash(blob(checkout, up["rev"], rel))
        out[name] = {**up, "files": files}
    LOCK.write_text(json.dumps(out, indent=1, sort_keys=True) + "\n", encoding="utf-8", newline="\n")
    print(f"wrote {LOCK.name}")


def verify() -> int:
    data = json.loads(LOCK.read_text(encoding="utf-8"))
    problems: list[str] = []
    for name, up in data.items():
        patched = PATCHES.get(name, {})
        base = ADDONS / name
        seen = set()
        for rel, want in up["files"].items():
            path = base / rel
            seen.add(rel)
            if not path.is_file():
                problems.append(f"{name}/{rel}: missing")
                continue
            got = git_blob_hash(path.read_bytes())
            if rel in patched:
                if got == want:
                    problems.append(f"{name}/{rel}: declared patched but equals upstream")
            elif got != want:
                problems.append(f"{name}/{rel}: differs from upstream {up['rev'][:10]} and is not declared")
        for path in base.rglob("*"):
            if path.is_file():
                rel = path.relative_to(base).as_posix()
                if rel not in seen and rel not in patched and "__pycache__" not in rel:
                    problems.append(f"{name}/{rel}: not in upstream and not declared")
        for rel in patched:
            if rel not in up["files"] and not (base / rel).is_file():
                problems.append(f"{name}/{rel}: declared patch is missing")
    for line in problems:
        print("FAIL", line)
    total = sum(len(u["files"]) for u in data.values())
    if problems:
        print(f"{len(problems)} problem(s) across {total} vendored files")
        return 1
    print(f"OK: {total} vendored files match their pins; "
          f"{sum(len(p) for p in PATCHES.values())} declared patches")
    return 0


def main(argv: list[str]) -> int:
    if len(argv) >= 3 and argv[1] == "vendor":
        vendor(Path(argv[2]))
        return 0
    if len(argv) >= 3 and argv[1] == "lock":
        lock(Path(argv[2]))
        return 0
    if len(argv) == 2 and argv[1] == "verify":
        return verify()
    print(__doc__)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
