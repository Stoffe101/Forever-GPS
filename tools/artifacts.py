#!/usr/bin/env python3
"""GitHub Actions artifacts: what they hold, and pruning the ones nothing needs.

    python -I tools/artifacts.py inventory [--owner NAME] [--repo NAME ...] [--json FILE]
    python -I tools/artifacts.py prune [--owner NAME] [--repo NAME ...] [--apply] [--keep-days 7] [--report FILE]

Without --apply, prune deletes nothing: it lists what it would delete, and why. Artifacts
are the only thing it ever deletes: never releases, tags, branches, runs, code or issues.

What is kept:
  - the newest artifact of each name, per workflow and branch, for every branch that exists
    or has an open pull request (the latest build of a branch), whatever its age;
  - anything whose name says release, rollback, keep or retain;
  - artifacts of failed runs, for --failed-days (14): they are the diagnosis;
  - older copies for --superseded-days (2), and those of deleted branches for --keep-days (7);
  - anything already expired (it holds no storage).
What is pruned: older copies an artifact of the same name, workflow and branch replaced, and
artifacts of branches that no longer exist, once past those windows.

The token comes from GITHUB_TOKEN or GH_TOKEN, else from `gh auth token`. Requests are
paged and few; a rate limit stops the run cleanly, with what was done so far reported.
Standard library only.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.github.com"
KEEP_WORDS = ("release", "rollback", "keep", "retain")


class RateLimited(Exception):
    pass


def token() -> str:
    for name in ("GITHUB_TOKEN", "GH_TOKEN"):
        if os.environ.get(name):
            return os.environ[name]
    try:
        return subprocess.run(["gh", "auth", "token"], capture_output=True, text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        sys.exit("artifacts: no token (set GITHUB_TOKEN, or sign in with gh)")


class GitHub:
    def __init__(self, tok: str, opener=urllib.request.urlopen):
        self.tok, self.open, self.calls = tok, opener, 0

    def request(self, method: str, path: str) -> tuple[int, object, dict]:
        url = path if path.startswith("http") else API + path
        req = urllib.request.Request(url, method=method, headers={
            "Authorization": f"Bearer {self.tok}", "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28", "User-Agent": "forever-gps-artifacts"})
        self.calls += 1
        try:
            with self.open(req, timeout=30) as resp:
                body = resp.read()
                return resp.status, (json.loads(body) if body else None), dict(resp.headers)
        except urllib.error.HTTPError as err:
            if err.code in (403, 429) and err.headers.get("X-RateLimit-Remaining") == "0":
                raise RateLimited(err.headers.get("X-RateLimit-Reset", "?")) from err
            body = err.read()
            try:
                data = json.loads(body) if body else None
            except ValueError:
                data = None
            return err.code, data, dict(err.headers)

    def pages(self, path: str, key: str) -> list:
        out, url = [], path + ("&" if "?" in path else "?") + "per_page=100"
        while url:
            status, data, headers = self.request("GET", url)
            if status != 200 or not isinstance(data, dict):
                raise RuntimeError(f"{path}: HTTP {status}")
            out.extend(data.get(key, []))
            url = None
            for part in (headers.get("Link") or "").split(","):
                if 'rel="next"' in part:
                    url = part[part.index("<") + 1:part.index(">")]
        return out


def parse_time(text: str) -> dt.datetime:
    return dt.datetime.fromisoformat(text.replace("Z", "+00:00"))


def repos(gh: GitHub, owner: str, only: list[str]) -> list[str]:
    if only:
        return only
    status, data, _ = gh.request("GET", "/user")
    me = data.get("login") if status == 200 and isinstance(data, dict) else None
    # One's own private repositories are listed only under /user/repos.
    path = "/user/repos?affiliation=owner" if me == owner else f"/users/{owner}/repos"
    return sorted(r["name"] for r in _list(gh, path) if r["owner"]["login"] == owner)


def artifacts_of(gh: GitHub, owner: str, repo: str) -> list[dict]:
    rows = gh.pages(f"/repos/{owner}/{repo}/actions/artifacts", "artifacts")
    out = []
    for a in rows:
        run = a.get("workflow_run") or {}
        out.append({
            "repo": repo, "id": a["id"], "name": a["name"], "bytes": a.get("size_in_bytes", 0),
            "created": a.get("created_at"), "expired": a.get("expired", False),
            "run": run.get("id"), "branch": run.get("head_branch"), "sha": (run.get("head_sha") or "")[:7],
        })
    return out


def run_workflows(gh: GitHub, owner: str, repo: str, run_ids: set) -> dict:
    """The workflow and outcome of each run the artifacts came from."""
    runs = {}
    for rid in run_ids:
        if rid is None:
            continue
        status, data, _ = gh.request("GET", f"/repos/{owner}/{repo}/actions/runs/{rid}")
        if status == 200 and isinstance(data, dict):
            runs[rid] = {"name": data.get("name") or data.get("path") or "?", "conclusion": data.get("conclusion")}
        else:
            runs[rid] = {"name": "deleted run", "conclusion": None}
    return runs


def branches_of(gh: GitHub, owner: str, repo: str) -> set:
    try:
        return {b["name"] for b in _list(gh, f"/repos/{owner}/{repo}/branches")}
    except RuntimeError:
        return set()


def _list(gh: GitHub, path: str) -> list:
    out, page = [], 1
    sep = "&" if "?" in path else "?"
    while True:
        status, data, _ = gh.request("GET", f"{path}{sep}per_page=100&page={page}")
        if status != 200 or not isinstance(data, list):
            if page == 1:
                raise RuntimeError(f"{path}: HTTP {status}")
            break
        out.extend(data)
        if len(data) < 100:
            break
        page += 1
    return out


def open_pr_heads(gh: GitHub, owner: str, repo: str) -> set:
    try:
        return {p["head"]["ref"] for p in _list(gh, f"/repos/{owner}/{repo}/pulls")}
    except RuntimeError:
        return set()


def decide(arts: list[dict], runs: dict, branches: set, pr_heads: set, keep_days: int, now: dt.datetime,
           superseded_days: int = 2, failed_days: int = 14) -> list[dict]:
    """Each artifact with keep (True/False) and why."""
    def workflow(a):
        return runs.get(a["run"], {}).get("name", "?")
    newest = {}
    for a in arts:
        key = (workflow(a), a["branch"], a["name"])
        if a["expired"]:
            continue
        if key not in newest or parse_time(a["created"]) > parse_time(newest[key]["created"]):
            newest[key] = a
    out = []
    for a in arts:
        a = dict(a)
        a["workflow"] = workflow(a)
        a["conclusion"] = runs.get(a["run"], {}).get("conclusion")
        age = (now - parse_time(a["created"])).days
        key = (a["workflow"], a["branch"], a["name"])
        lowered = a["name"].lower()
        if a["expired"]:
            a["keep"], a["why"] = True, "already expired: holds no storage"
        elif any(w in lowered for w in KEEP_WORDS):
            a["keep"], a["why"] = True, "named for keeping (release, rollback, keep)"
        elif newest.get(key, {}).get("id") == a["id"] and (a["branch"] in branches or a["branch"] in pr_heads):
            a["keep"], a["why"] = True, ("newest of an open pull request" if a["branch"] in pr_heads
                                         else "newest of its name on a live branch")
        elif a["conclusion"] in ("failure", "timed_out") and age < failed_days:
            a["keep"], a["why"] = True, f"from a failed run, kept {failed_days} d for diagnosis ({age} d)"
        elif a["branch"] not in branches and a["branch"] not in pr_heads:
            if age < keep_days:
                a["keep"], a["why"] = True, f"branch gone, but recent ({age} d)"
            else:
                a["keep"], a["why"] = False, f"branch {a['branch']!r} no longer exists, {age} d old"
        elif age < superseded_days:
            a["keep"], a["why"] = True, f"superseded, but under {superseded_days} d old"
        else:
            a["keep"], a["why"] = False, f"superseded by a newer {a['name']!r} on {a['branch']}, {age} d old"
        out.append(a)
    return out


def human(n: int) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024 or unit == "GB":
            return f"{n:.1f} {unit}" if unit != "B" else f"{n} B"
        n /= 1024
    return f"{n:.1f} GB"


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("command", choices=("inventory", "prune"))
    ap.add_argument("--owner", default=os.environ.get("GITHUB_REPOSITORY_OWNER", ""))
    ap.add_argument("--repo", action="append", default=[])
    ap.add_argument("--keep-days", type=int, default=7, help="artifacts of deleted branches are kept this long")
    ap.add_argument("--superseded-days", type=int, default=2, help="older copies are kept this long")
    ap.add_argument("--failed-days", type=int, default=14, help="artifacts of failed runs are kept this long")
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--json")
    ap.add_argument("--report")
    args = ap.parse_args(argv[1:])
    gh = GitHub(token())
    if not args.owner:
        status, data, _ = gh.request("GET", "/user")
        args.owner = data["login"] if status == 200 else sys.exit("artifacts: give --owner")
    now = dt.datetime.now(dt.timezone.utc)
    rows, problems, deleted, freed = [], [], [], 0
    try:
        for repo in repos(gh, args.owner, args.repo):
            try:
                arts = artifacts_of(gh, args.owner, repo)
            except RuntimeError as err:
                problems.append(f"{repo}: {err}")
                continue
            if not arts:
                continue
            runs = run_workflows(gh, args.owner, repo, {a["run"] for a in arts})
            decided = decide(arts, runs, branches_of(gh, args.owner, repo), open_pr_heads(gh, args.owner, repo),
                             args.keep_days, now, args.superseded_days, args.failed_days)
            rows.extend(decided)
            if args.command == "prune" and args.apply:
                for a in decided:
                    if a["keep"]:
                        continue
                    status, _, _ = gh.request("DELETE", f"/repos/{args.owner}/{repo}/actions/artifacts/{a['id']}")
                    if status in (204, 404):         # 404: already gone, which is the goal
                        deleted.append(a)
                        freed += a["bytes"] if status == 204 else 0
                    else:
                        problems.append(f"{repo}/{a['name']} ({a['id']}): delete refused, HTTP {status}")
    except RateLimited as err:
        problems.append(f"rate limited, resets at {err}; stopped here")
    lines = []
    total = sum(a["bytes"] for a in rows if not a["expired"])
    by_repo = {}
    for a in rows:
        if not a["expired"]:
            by_repo[a["repo"]] = by_repo.get(a["repo"], 0) + a["bytes"]
    lines.append(f"# Actions artifacts of {args.owner}, {now:%Y-%m-%d %H:%M} UTC")
    lines.append("")
    lines.append(f"{len(rows)} artifacts, {human(total)} unexpired, in {len(by_repo)} repositories. API requests: {gh.calls}.")
    lines.append("")
    lines.append("| Repository | Unexpired |")
    lines.append("| --- | --- |")
    for repo, size in sorted(by_repo.items(), key=lambda kv: -kv[1]):
        lines.append(f"| {repo} | {human(size)} |")
    lines.append("")
    verb = "Deleted" if args.command == "prune" and args.apply else "Would delete"
    gone = [a for a in rows if not a["keep"]]
    lines.append(f"## {verb}: {len(gone)}, {human(sum(a['bytes'] for a in gone))}")
    lines.append("")
    lines.append("| Repository | Artifact | Size | Created | Workflow | Branch @ commit | Why |")
    lines.append("| --- | --- | --- | --- | --- | --- | --- |")
    for a in sorted(gone, key=lambda a: (a["repo"], a["created"])):
        lines.append(f"| {a['repo']} | {a['name']} | {human(a['bytes'])} | {a['created'][:10]} | {a['workflow']} | "
                     f"{a['branch']} @ {a['sha']} | {a['why']} |")
    lines.append("")
    kept = [a for a in rows if a["keep"] and not a["expired"]]
    lines.append(f"## Kept: {len(kept)}, {human(sum(a['bytes'] for a in kept))}")
    lines.append("")
    lines.append("| Repository | Artifact | Size | Created | Workflow | Branch | Why kept |")
    lines.append("| --- | --- | --- | --- | --- | --- | --- |")
    for a in sorted(kept, key=lambda a: (a["repo"], a["created"])):
        lines.append(f"| {a['repo']} | {a['name']} | {human(a['bytes'])} | {a['created'][:10]} | {a['workflow']} | {a['branch']} | {a['why']} |")
    if args.command == "prune" and args.apply:
        lines.append("")
        lines.append(f"Deleted {len(deleted)}, {human(freed)}. GitHub's storage figure can take hours to follow.")
    if problems:
        lines.append("")
        lines.append("## Problems")
        lines.extend(f"- {p}" for p in problems)
    text = "\n".join(lines) + "\n"
    if args.report:
        with open(args.report, "w", encoding="utf-8") as fh:
            fh.write(text)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as fh:
            fh.write(text)
    if args.json:
        with open(args.json, "w", encoding="utf-8") as fh:
            json.dump(rows, fh, indent=1)
    print(text if len(text) < 20000 else text[:20000] + "\n... (see --report)")
    return 1 if problems and not rows else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
