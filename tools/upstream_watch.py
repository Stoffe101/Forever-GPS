#!/usr/bin/env python3
"""Watch what Forever-GPS is built on, and prepare updates when it moves.

    python -I tools/upstream_watch.py check   [--only NAME] [--state FILE] [--report FILE] [--json FILE]
    python -I tools/upstream_watch.py prepare [--only NAME] [--state FILE] [--report FILE] [--push]

`check` asks GitHub (and Blizzard's version server, for the client) what is new since the
pins, and checks it as far as can be done without the game:

  vendored   EasyFind, EasyFind GPS, EasyFind Questie: newer releases than UPSTREAM.lock.json
             pins, and whether their LICENSE changed (they are used by written permission:
             any change to it stops everything for a person to read).
  runtime    Questie: its newest release still has every module and function Forever-GPS
             and the Questie extension read (QUESTIE_CONTRACT). Never installed or bundled.
  reused     CraftProfit, ForeverNet, profit, Easy Controller: new commits after the pins in
             third_party/THIRD_PARTY.lock.json, for a person to read. Their code was adapted,
             not copied, so nothing is merged automatically.
  client     WoW Forever's live build, and whether every C_ API Forever-GPS calls is still in
             the client's own API documentation (Gethe/wow-ui-source, branch forever), and
             still unrestricted.

`prepare` takes every vendored update together (GPS releases need the matching EasyFind),
with tools/upstream.py update (three-way merge of our patches; conflicts stop it), then
tools/assemble.py (every assembly edit must still match), the test suites and the package.
With --push it commits to a branch upstream/<names>-<versions> and opens a draft pull
request against the development branch: marked ready when everything passed, failing
otherwise, with the report. One branch per set of versions: a second run finds it and
does nothing. Nothing is merged, released or installed.

State (what was last checked and last prepared) lives in --state, a JSON file the workflow
keeps on the upstream-status branch. GitHub requests are a handful per component; a rate
limit or a network failure is reported for that component and the rest go on.
Standard library only.
"""
from __future__ import annotations

import argparse
import datetime as dt
import io
import json
import os
import re
import subprocess
import sys
import tarfile
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOCK = ROOT / "UPSTREAM.lock.json"
THIRD = ROOT / "third_party" / "THIRD_PARTY.lock.json"
WATCH = ROOT / "upstream" / "WATCH.json"
API = "https://api.github.com"
RIBBIT = "https://us.version.battle.net/v2/products/wowf/versions"

VENDORED = {
    "EasyFind": "fallenguards/EasyFind",
    "EasyFind_GPS": "fallenguards/EasyFind_GPS",
    "EasyFind_Questie": "fallenguards/EasyFind_Questie",
}
REUSED = {
    "CraftProfit": "Renaud-Sto/CraftProfit",
    "ForeverNet": "thewoolfi/ForeverNet",
    "profit": "ExcEssIv3/profit",
    "EasyController": "moust4ki/EasyControllerWowForever",
}
QUESTIE_REPO = "Questie/Questie"
# What Forever-GPS (Core/QuestDB.lua) and the Questie extension read of Questie: each must
# appear in its source. Checked against Questie 12.8.0 when written.
QUESTIE_CONTRACT = [
    'CreateModule("QuestieDB")', 'CreateModule("ZoneDB")', 'CreateModule("QuestieProfessions")',
    'CreateModule("QuestieReputation")', 'CreateModule("TrackerMenu")',
    "QuestieDB.QueryQuestSingle", "QuestieDB.QueryNPCSingle", "QuestieDB.QueryObjectSingle",
    "QuestieDB.QueryItemSingle", "function QuestieDB.IsDoable", "function ZoneDB:GetUiMapIdByAreaId",
    "RegisterOnReady",
]
VERSION = re.compile(r"(\d+)\.(\d+)\.(\d+)")


class Net:
    """GitHub and the version server, with failures reported, never raised."""

    def __init__(self, token: str | None, opener=urllib.request.urlopen):
        self.token, self.open = token, opener
        self.requests = 0
        self.rate_limited = False

    def get(self, url: str, accept: str = "application/vnd.github+json", raw: bool = False):
        if self.rate_limited and url.startswith(API):
            return None, "rate limited"
        headers = {"Accept": accept, "User-Agent": "forever-gps-upstream-watch"}
        if self.token and url.startswith(API):
            headers["Authorization"] = f"Bearer {self.token}"
        self.requests += 1
        try:
            with self.open(urllib.request.Request(url, headers=headers), timeout=30) as resp:
                body = resp.read()
                return (body if raw else json.loads(body or b"null")), None
        except urllib.error.HTTPError as err:
            if err.code in (403, 429) and err.headers.get("X-RateLimit-Remaining") == "0":
                self.rate_limited = True
                return None, "rate limited"
            return None, f"HTTP {err.code}"
        except (urllib.error.URLError, TimeoutError, OSError, ValueError) as err:
            return None, f"unreachable ({err.__class__.__name__})"


def version_of(text: str | None) -> tuple | None:
    m = VERSION.search(text or "")
    return tuple(int(x) for x in m.groups()) if m else None


def bump(old: tuple | None, new: tuple | None) -> str:
    if not (old and new) or new <= old:
        return "none"
    return "major" if new[0] != old[0] else "minor" if new[1] != old[1] else "patch"


def latest_release(net: Net, repo: str) -> dict:
    """The newest stable release with a version in its tag, or the newest version tag."""
    out = {"repo": repo}
    rels, err = net.get(f"{API}/repos/{repo}/releases?per_page=10")
    if err:
        out["error"] = err
        return out
    malformed = []
    for rel in rels or []:
        if rel.get("draft") or rel.get("prerelease"):
            continue
        v = version_of(rel.get("tag_name"))
        if not v:
            malformed.append(rel.get("tag_name"))
            continue
        out.update(tag=rel["tag_name"], version=".".join(map(str, v)), published=rel.get("published_at"))
        break
    if malformed:
        out["malformed"] = malformed
    if "tag" not in out:
        tags, err = net.get(f"{API}/repos/{repo}/tags?per_page=20")
        for tag in tags or []:
            v = version_of(tag.get("name"))
            if v:
                out.update(tag=tag["name"], version=".".join(map(str, v)))
                break
    return out


def tag_exists(net: Net, repo: str, tag: str) -> bool | None:
    data, err = net.get(f"{API}/repos/{repo}/git/ref/tags/{tag}")
    if err and err.startswith("HTTP 404"):
        return False
    return None if err else True


def license_changed(net: Net, repo: str, old_rev: str, new_tag: str) -> bool | None:
    texts = []
    for ref in (old_rev, new_tag):
        body, err = net.get(f"{API}/repos/{repo}/contents/LICENSE?ref={ref}", accept="application/vnd.github.raw", raw=True)
        if err:
            return None
        texts.append(body.replace(b"\r\n", b"\n").strip())
    return texts[0] != texts[1]


def check_vendored(net: Net, lock: dict, state: dict) -> list[dict]:
    rows = []
    for name, repo in VENDORED.items():
        pinned = lock.get(name, {})
        row = {"name": name, "kind": "vendored", "repo": repo, "pinned": pinned.get("version"),
               "pinned_rev": (pinned.get("rev") or "")[:10]}
        rel = latest_release(net, repo)
        row.update({k: rel[k] for k in ("tag", "version", "published", "malformed", "error") if k in rel})
        kind = bump(version_of(row["pinned"]), version_of(row.get("version")))
        row["update"] = kind
        if kind != "none" and row.get("tag"):
            changed = license_changed(net, repo, pinned.get("rev", ""), row["tag"])
            row["license"] = {True: "CHANGED: stop, read it", False: "unchanged", None: "could not compare"}[changed]
            if changed:
                row["blocked"] = "license changed"
        pinned_tag = f"v{row['pinned']}" if row.get("pinned") else None
        if pinned_tag and tag_exists(net, repo, pinned_tag) is False:
            row["warning"] = f"the pinned tag {pinned_tag} is gone upstream; the pinned commit still identifies it"
        prepared = state.get("prepared", {}).get(name)
        row["prepared"] = prepared
        rows.append(row)
    return rows


def check_reused(net: Net, third: dict) -> list[dict]:
    rows = []
    for name, repo in REUSED.items():
        pinned = (third.get(name) or {}).get("commit", "")
        row = {"name": name, "kind": "reused", "repo": repo, "pinned_rev": pinned[:7]}
        data, err = net.get(f"{API}/repos/{repo}/compare/{pinned}...HEAD") if pinned else (None, "not pinned")
        if err:
            row["error"] = err
        else:
            row["ahead"] = data.get("ahead_by", 0)
            row["update"] = "review" if row["ahead"] else "none"
            row["files"] = [f["filename"] for f in (data.get("files") or [])][:20]
        rows.append(row)
    return rows


def check_questie(net: Net, watch: dict) -> dict:
    tested = (watch.get("questie") or {}).get("tested")
    row = {"name": "Questie", "kind": "runtime", "repo": QUESTIE_REPO, "pinned": tested,
           "minimum": (watch.get("questie") or {}).get("minimum")}
    rel = latest_release(net, QUESTIE_REPO)
    row.update({k: rel[k] for k in ("tag", "version", "published", "error") if k in rel})
    row["update"] = bump(version_of(tested), version_of(row.get("version")))
    if row["update"] != "none" and row.get("tag"):
        body, err = net.get(f"https://codeload.github.com/{QUESTIE_REPO}/tar.gz/refs/tags/{row['tag']}", raw=True)
        if err:
            row["contract"] = f"not checked: {err}"
        else:
            row["contract"], row["missing"] = questie_contract(body)
    return row


def questie_contract(tgz: bytes) -> tuple[str, list[str]]:
    seen = {item: False for item in QUESTIE_CONTRACT}
    with tarfile.open(fileobj=io.BytesIO(tgz), mode="r:gz") as tar:
        for member in tar:
            if member.isfile() and member.name.endswith(".lua"):
                text = tar.extractfile(member).read().decode("utf-8", "replace")
                for item in seen:
                    if not seen[item] and item in text:
                        seen[item] = True
    missing = [k for k, v in seen.items() if not v]
    return ("passes" if not missing else "BROKEN"), missing


def own_c_apis() -> set[str]:
    calls = set()
    for path in (ROOT / "addons" / "ForeverGPS").rglob("*.lua"):
        for m in re.finditer(r"\b(C_\w+)\.(\w+)", path.read_text(encoding="utf-8", errors="replace")):
            calls.add(f"{m.group(1)}.{m.group(2)}")
    return calls


def check_client(net: Net, watch: dict) -> dict:
    known = (watch.get("client") or {})
    row = {"name": "WoW Forever client", "kind": "client", "pinned": known.get("verified"), "known": known.get("build")}
    body, err = net.get(RIBBIT, raw=True)
    if err:
        row["error"] = err
        return row
    for line in body.decode("utf-8", "replace").splitlines():
        if line.startswith("us|"):
            row["version"] = line.split("|")[5]
    build = (row.get("version") or "").rsplit(".", 1)[-1]
    row["update"] = "new build" if build and build != known.get("build") else "none"
    if row["update"] == "none":
        return row
    tgz, err = net.get("https://codeload.github.com/Gethe/wow-ui-source/tar.gz/refs/heads/forever", raw=True)
    if err:
        row["api"] = f"not checked: {err}"
        return row
    docs = {}
    ui_version = None
    with tarfile.open(fileobj=io.BytesIO(tgz), mode="r:gz") as tar:
        for member in tar:
            if member.name.endswith("version.txt"):
                ui_version = tar.extractfile(member).read().decode().strip()
            if "Blizzard_APIDocumentationGenerated/" in member.name and member.name.endswith(".lua") and member.isfile():
                text = tar.extractfile(member).read().decode("utf-8", "replace")
                ns = re.search(r'Namespace = "(C_\w+)"', text)
                if not ns:
                    continue
                for fn in re.finditer(r'Name = "(\w+)",\s*Type = "Function",(.*?)Arguments|Name = "(\w+)",\s*Type = "Function",', text, re.S):
                    name = fn.group(1) or fn.group(3)
                    restricted = bool(fn.group(2) and "HasRestrictions = true" in fn.group(2))
                    docs[f"{ns.group(1)}.{name}"] = restricted
    row["ui_source"] = ui_version
    calls = own_c_apis()
    namespaces = {k.split(".")[0] for k in docs}
    row["missing"] = sorted(c for c in calls if c.split(".")[0] in namespaces and c not in docs)
    row["restricted"] = sorted(c for c in calls if docs.get(c))
    row["api"] = "ok" if not (row["missing"] or row["restricted"]) else "REVIEW"
    return row


# ==== preparing an update ===================================================

def run(cmd: list[str], log: list[str]) -> int:
    proc = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
    log.append(f"$ {' '.join(cmd)}  (exit {proc.returncode})")
    tail = (proc.stdout + proc.stderr).strip().splitlines()[-25:]
    log.extend("    " + line for line in tail)
    return proc.returncode


def prepare(rows: list[dict], push: bool, base: str, net: Net) -> dict:
    todo = [r for r in rows if r["kind"] == "vendored" and r["update"] not in ("none",) and r.get("tag")
            and not r.get("blocked")]
    if not todo:
        return {"prepared": False, "why": "nothing to prepare"}
    label = "-".join(f"{r['name']}-{r['version']}" for r in todo)
    branch = f"upstream/{label}"
    if push and subprocess.run(["git", "ls-remote", "--exit-code", "--heads", "origin", branch], cwd=ROOT,
                               capture_output=True).returncode == 0:
        return {"prepared": False, "why": f"{branch} already exists: prepared before", "branch": branch}
    log: list[str] = []
    steps = {}
    if push:
        run(["git", "checkout", "-B", branch], log)
    ok = True
    for r in todo:
        code = run([sys.executable, "-I", "tools/upstream.py", "update", r["name"], r["tag"], "--version", r["version"]], log)
        steps[f"update {r['name']}"] = "merged" if code == 0 else "CONFLICT"
        ok = ok and code == 0
    steps["assemble (every edit still matches)"] = "passed" if run([sys.executable, "-I", "tools/assemble.py"], log) == 0 else "FAILED"
    steps["pins"] = "passed" if run([sys.executable, "-I", "tools/upstream.py", "verify"], log) == 0 else "FAILED"
    steps["tests"] = "passed" if run([sys.executable, "-I", "tools/run_tests.py"], log) == 0 else "FAILED"
    steps["package"] = "passed" if run([sys.executable, "-I", "tools/package.py"], log) == 0 else "FAILED"
    ok = ok and all(v in ("passed", "merged") for v in steps.values())
    result = {"prepared": True, "branch": branch, "ok": ok, "steps": steps, "log": log,
              "versions": {r["name"]: r["version"] for r in todo}}
    if push:
        run(["git", "add", "-A"], log)
        title = ("" if ok else "[failing] ") + "Upstream: " + ", ".join(f"{r['name']} {r['version']}" for r in todo)
        run(["git", "commit", "-m", title + "\n\nPrepared by tools/upstream_watch.py. Not merged: for review.\n\n"
             "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"], log)
        run(["git", "push", "origin", branch], log)
        body = report_pr(result)
        run(["gh", "pr", "create", "--draft", "--base", base, "--head", branch, "--title", title, "--body", body], log)
    return result


def report_pr(result: dict) -> str:
    lines = ["Prepared automatically. Nothing is merged, released or installed without approval.", ""]
    lines.append("| Step | Result |")
    lines.append("| --- | --- |")
    lines.extend(f"| {k} | {v} |" for k, v in result["steps"].items())
    lines += ["", "<details><summary>Log</summary>", "", "```", *result["log"][-200:], "```", "</details>", "",
              "🤖 Generated with [Claude Code](https://claude.com/claude-code)"]
    return "\n".join(lines)


# ==== the report ============================================================

def report(rows: list[dict], prepared: dict | None, net: Net, now: str) -> str:
    out = [f"# Upstream status, {now}", ""]
    out.append("| Dependency | Kind | Pinned | Latest upstream | Update | Checks | Pull request |")
    out.append("| --- | --- | --- | --- | --- | --- | --- |")
    for r in rows:
        latest = r.get("version") or r.get("ahead") and f"{r['ahead']} commits ahead" or "same"
        checks = []
        for key in ("license", "contract", "api", "warning", "blocked", "error"):
            if r.get(key):
                checks.append(f"{key}: {r[key]}")
        if r.get("missing"):
            checks.append("missing: " + ", ".join(r["missing"][:6]))
        if r.get("restricted"):
            checks.append("restricted: " + ", ".join(r["restricted"][:6]))
        if r.get("malformed"):
            checks.append("ignored releases: " + ", ".join(map(str, r["malformed"][:3])))
        pinned = r.get("pinned") or r.get("pinned_rev") or "?"
        pr = prepared.get("branch") if prepared and r["name"] in (prepared.get("versions") or {}) else ""
        out.append(f"| {r['name']} | {r['kind']} | {pinned} | {latest} | {r.get('update', '?')} | {'; '.join(checks) or 'ok'} | {pr} |")
    if prepared:
        out += ["", f"Prepare: {prepared.get('why') or ('ready for review' if prepared.get('ok') else 'FAILED, kept as a report')}"
                + (f" ({prepared['branch']})" if prepared.get("branch") else "")]
    out += ["", f"Requests: {net.requests}." + (" GitHub rate limit reached: later components unchecked." if net.rate_limited else "")]
    return "\n".join(out) + "\n"


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("command", choices=("check", "prepare"))
    ap.add_argument("--only")
    ap.add_argument("--state")
    ap.add_argument("--report")
    ap.add_argument("--json")
    ap.add_argument("--push", action="store_true")
    ap.add_argument("--base", default=os.environ.get("FGPS_DEV_BRANCH", "feature/forever-gps-v1"))
    args = ap.parse_args(argv[1:])
    net = Net(os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN"))
    lock = json.loads(LOCK.read_text(encoding="utf-8"))
    third = json.loads(THIRD.read_text(encoding="utf-8")) if THIRD.exists() else {}
    watch = json.loads(WATCH.read_text(encoding="utf-8")) if WATCH.exists() else {}
    state = json.loads(Path(args.state).read_text(encoding="utf-8")) if args.state and Path(args.state).exists() else {}
    now = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    rows = check_vendored(net, lock, state) + [check_questie(net, watch)] + check_reused(net, third) + [check_client(net, watch)]
    if args.only:
        rows = [r for r in rows if r["name"].lower() == args.only.lower()]
    prepared = None
    if args.command == "prepare":
        prepared = prepare(rows, args.push, args.base, net)
        if prepared.get("prepared"):
            state.setdefault("prepared", {}).update({n: v for n, v in prepared["versions"].items()})
    state["checked"] = now
    state["latest"] = {r["name"]: r.get("version") or r.get("ahead") for r in rows}
    text = report(rows, prepared, net, now)
    if args.report:
        Path(args.report).write_text(text, encoding="utf-8")
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as fh:
            fh.write(text)
    if args.json:
        Path(args.json).write_text(json.dumps({"rows": rows, "prepared": prepared}, indent=1, default=str), encoding="utf-8")
    if args.state:
        Path(args.state).write_text(json.dumps(state, indent=1, sort_keys=True), encoding="utf-8")
    print(text)
    broken = any(r.get("contract") == "BROKEN" or r.get("blocked") for r in rows)
    return 1 if (prepared and prepared.get("prepared") and not prepared.get("ok")) or broken else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
