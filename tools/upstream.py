#!/usr/bin/env python3
"""Vendor the upstream addons and verify they stay byte-exact.

    python tools/upstream.py vendor <checkout-root>   # copy pinned trees in
    python tools/upstream.py lock   <checkout-root>   # (re)write UPSTREAM.lock.json
    python tools/upstream.py verify                   # check addons/ against the lock
    python tools/upstream.py update <addon> <rev-or-tag> [--source DIR] [--version X.Y.Z]
                                                      # take a newer upstream, keeping our patches

`update` replaces the addon's unpatched files with upstream's at the new revision, and
merges each declared patch three ways (the old upstream, the new upstream, ours) with
`git merge-file`. A patch that does not merge cleanly is left with conflict markers and
reported, and the command fails: nothing of ours is ever dropped silently. The lock is
rewritten for the new revision. Then tools/assemble.py checks every assembly edit still
matches, and the test suites run (tools/upstream_watch.py prepare does all of it).

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

# Where each vendored addon comes from, and the revision it is pinned at: the lock is the
# one record of that, so an update changes it in one place.
def upstreams() -> dict:
    data = json.loads(LOCK.read_text(encoding="utf-8"))
    return {name: {k: v for k, v in entry.items() if k != "files"} for name, entry in data.items()}


UPSTREAMS = upstreams()

# Upstream's own CI lives in .github, which has no meaning in a subfolder.
SKIP_PREFIXES = (".github/",)

# Every intentional change to vendored code, with why. docs/UPSTREAM.md explains
# each one; `verify` insists this list matches what is on disk.
PATCHES = {
    "EasyFind": {
        "MapSearch/Search/Results.lua": "Keeps a folded row's instances on the row, so one can be chosen by travel time.",
        "MapSearch/Npcs.lua": "Adds N.SpotsOf and N.ReactionOf: read-only access to a creature's spawns and its reaction.",
    },
    "EasyFind_GPS": {
        "GPS.lua": "Fixes trips losing their stops on a reroute, and returning to stops already reached. Lets the plan budget follow the frame rate.",
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


def clone(repo: str, into: Path) -> Path:
    """A blobless clone: history and trees at once, file contents as they are read."""
    if not (into / ".git").exists():
        subprocess.run(["git", "clone", "--quiet", "--filter=blob:none", "--no-checkout", repo, str(into)], check=True)
    else:
        subprocess.run(["git", "-C", str(into), "fetch", "--quiet", "--tags", "origin"], check=True)
    return into


def resolve(checkout: Path, ref: str) -> str:
    return subprocess.run(["git", "-C", str(checkout), "rev-parse", f"{ref}^{{commit}}"],
                          check=True, capture_output=True, text=True).stdout.strip()


def update(name: str, ref: str, source: Path | None, version: str | None) -> int:
    """The addon at a newer upstream revision, with our patches merged onto it."""
    data = json.loads(LOCK.read_text(encoding="utf-8"))
    if name not in data:
        print(f"update: no vendored addon called {name}")
        return 2
    old = data[name]
    checkout = clone(old["repo"], source or (ROOT / "build" / "upstream" / name))
    new_rev = resolve(checkout, ref)
    if new_rev == old["rev"]:
        print(f"{name}: already at {new_rev[:10]}")
        return 0
    dest = ADDONS / name
    patched = PATCHES.get(name, {})
    new_files = tracked(checkout, new_rev)
    conflicts, merged, removed_patches = [], [], []
    # Ours, kept aside before anything is replaced.
    ours = {rel: (dest / rel).read_bytes() for rel in patched if (dest / rel).is_file()}
    for rel in old["files"]:
        if rel not in new_files and rel not in patched and (dest / rel).is_file():
            (dest / rel).unlink()
    for rel in new_files:
        target = dest / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        theirs = blob(checkout, new_rev, rel)
        if rel in patched and rel in ours:
            base = blob(checkout, old["rev"], rel) if rel in old["files"] else b""
            work = ROOT / "build" / "upstream" / "merge"
            work.mkdir(parents=True, exist_ok=True)
            (work / "ours").write_bytes(ours[rel])
            (work / "base").write_bytes(base)
            (work / "theirs").write_bytes(theirs)
            result = subprocess.run(["git", "merge-file", "-L", "forever-gps", "-L", f"{name} {old['version']}",
                                     "-L", f"{name} {version or new_rev[:10]}",
                                     str(work / "ours"), str(work / "base"), str(work / "theirs")])
            target.write_bytes((work / "ours").read_bytes())
            if result.returncode != 0:
                conflicts.append(rel)
            else:
                merged.append(rel)
        else:
            target.write_bytes(theirs)
    for rel in patched:
        if rel not in new_files:
            removed_patches.append(rel)
    data[name] = {"repo": old["repo"], "version": version or old["version"], "rev": new_rev,
                  "files": {rel: git_blob_hash(blob(checkout, new_rev, rel)) for rel in new_files}}
    LOCK.write_text(json.dumps(data, indent=1, sort_keys=True) + "\n", encoding="utf-8", newline="\n")
    print(f"{name}: {old['version']} ({old['rev'][:10]}) -> {version or '?'} ({new_rev[:10]}), {len(new_files)} files")
    for rel in merged:
        print(f"  patch merged cleanly: {rel}")
    for rel in removed_patches:
        print(f"  REVIEW: upstream removed {rel}, which we patch; ours is kept")
    for rel in conflicts:
        print(f"  CONFLICT: {rel} has conflict markers; resolve by hand, keeping both intents")
    return 1 if conflicts else 0


def main(argv: list[str]) -> int:
    if len(argv) >= 4 and argv[1] == "update":
        source = version = None
        rest = argv[4:]
        if "--source" in rest:
            source = Path(rest[rest.index("--source") + 1])
        if "--version" in rest:
            version = rest[rest.index("--version") + 1]
        return update(argv[2], argv[3], source, version)
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
