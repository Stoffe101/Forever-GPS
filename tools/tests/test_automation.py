"""The automation's decisions, against a pretend GitHub: no network.

    python -I tools/tests/test_automation.py

upstream_watch: no update, a patch, minor and major release, a malformed release, a deleted
tag, a network failure, a rate limit, a license change, Questie's contract kept and broken,
a branch already prepared. artifacts: nothing to prune, superseded copies, recent ones,
failed runs, deleted branches, names kept on purpose, expired ones, a rate limit, a refused
or already-gone delete. The merge of our patches onto a new upstream is exercised for real
by tools/upstream.py update (docs/UPSTREAM.md).
"""
from __future__ import annotations

import datetime as dt
import io
import json
import sys
import tarfile
import unittest
import urllib.error
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import artifacts  # noqa: E402
import upstream_watch as watch  # noqa: E402


class FakeResponse(io.BytesIO):
    def __init__(self, body: bytes, status: int = 200, headers: dict | None = None):
        super().__init__(body)
        self.status, self.headers = status, headers or {}

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


def fake_opener(routes: dict, calls: list | None = None):
    """routes: url fragment -> body (bytes, or JSON-able), or an exception to raise."""
    def opener(req, timeout=30):
        url = req.full_url
        if calls is not None:
            calls.append((req.get_method(), url))
        for fragment, answer in routes.items():
            if fragment in url:
                if isinstance(answer, Exception):
                    raise answer
                body = answer if isinstance(answer, bytes) else json.dumps(answer).encode()
                return FakeResponse(body)
        raise urllib.error.HTTPError(url, 404, "Not Found", {}, io.BytesIO(b"{}"))
    return opener


def rate_limit(url="x"):
    return urllib.error.HTTPError(url, 403, "rate limited", {"X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "1"},
                                  io.BytesIO(b"{}"))


def tgz(files: dict) -> bytes:
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as tar:
        for name, text in files.items():
            data = text.encode()
            info = tarfile.TarInfo(name)
            info.size = len(data)
            tar.addfile(info, io.BytesIO(data))
    return buf.getvalue()


LOCK = {"EasyFind": {"version": "5.3.0", "rev": "a" * 40}, "EasyFind_GPS": {"version": "1.6.0", "rev": "b" * 40},
        "EasyFind_Questie": {"version": "1.3.0", "rev": "c" * 40}}


def releases(tag, **extra):
    return [{"tag_name": tag, "published_at": "2026-11-12T00:00:00Z", "draft": False, "prerelease": False, **extra}]


class Versions(unittest.TestCase):
    def test_bumps(self):
        v = watch.version_of
        self.assertEqual(watch.bump(v("5.3.0"), v("5.3.0")), "none")
        self.assertEqual(watch.bump(v("5.3.0"), v("5.3.1")), "patch")
        self.assertEqual(watch.bump(v("5.3.0"), v("5.4.0")), "minor")
        self.assertEqual(watch.bump(v("5.3.0"), v("6.0.0")), "major")
        self.assertEqual(watch.bump(v("5.3.0"), v("5.2.9")), "none", "an older release is no update")
        self.assertEqual(watch.version_of("bundle/v12.8.0+v1.0.16"), (12, 8, 0))


class Watch(unittest.TestCase):
    def net(self, routes, calls=None):
        return watch.Net("token", opener=fake_opener(routes, calls))

    def vendored(self, routes):
        rows = watch.check_vendored(self.net(routes), LOCK, {})
        return {r["name"]: r for r in rows}

    def test_noUpdate(self):
        rows = self.vendored({"EasyFind/releases": releases("v5.3.0"), "EasyFind_GPS/releases": releases("v1.6.0"),
                              "EasyFind_Questie/releases": releases("v1.3.0"), "/git/ref/tags/": {"ref": "x"}})
        self.assertTrue(all(r["update"] == "none" for r in rows.values()))
        self.assertTrue(all("warning" not in r for r in rows.values()))

    def test_patchRelease_withTheLicenseUnchanged(self):
        rows = self.vendored({"EasyFind/releases": releases("v5.3.1"), "/git/ref/tags/": {"ref": "x"},
                              "EasyFind/contents/LICENSE": b"All rights reserved."})
        self.assertEqual(rows["EasyFind"]["update"], "patch")
        self.assertEqual(rows["EasyFind"]["license"], "unchanged")
        self.assertNotIn("blocked", rows["EasyFind"])

    def test_aLicenseChange_blocksTheUpdate(self):
        answers = iter([b"All rights reserved.", b"MIT License"])

        def opener(req, timeout=30):
            if "contents/LICENSE" in req.full_url:
                return FakeResponse(next(answers))
            return fake_opener({"EasyFind/releases": releases("v6.0.0"), "/git/ref/tags/": {"ref": "x"}})(req)
        rows = {r["name"]: r for r in watch.check_vendored(watch.Net("t", opener=opener), LOCK, {})}
        self.assertEqual(rows["EasyFind"]["update"], "major")
        self.assertEqual(rows["EasyFind"]["blocked"], "license changed")

    def test_aMalformedRelease_isSkipped_forAVersionTag(self):
        rel = releases("nightly-build") + releases("v5.4.0")
        rows = self.vendored({"EasyFind/releases": rel, "/git/ref/tags/": {"ref": "x"}, "contents/LICENSE": b"same"})
        self.assertEqual(rows["EasyFind"]["version"], "5.4.0")
        self.assertIn("nightly-build", rows["EasyFind"]["malformed"])

    def test_draftsAndPrereleases_areNoUpdate(self):
        rel = [{"tag_name": "v9.0.0", "draft": True, "prerelease": False}, {"tag_name": "v8.0.0", "draft": False, "prerelease": True}]
        rows = self.vendored({"EasyFind/releases": rel, "EasyFind/tags": [{"name": "v5.3.0"}], "/git/ref/tags/": {"ref": "x"}})
        self.assertEqual(rows["EasyFind"]["update"], "none")

    def test_aDeletedPinnedTag_isAWarning_notAFailure(self):
        rows = self.vendored({"EasyFind/releases": releases("v5.3.0")})       # every tag lookup: 404
        self.assertIn("pinned tag v5.3.0 is gone", rows["EasyFind"]["warning"])
        self.assertEqual(rows["EasyFind"]["update"], "none")

    def test_aNetworkFailure_isReported_andTheRestGoOn(self):
        rows = self.vendored({"EasyFind/releases": urllib.error.URLError("down"), "EasyFind_GPS/releases": releases("v1.6.0"),
                              "EasyFind_Questie/releases": releases("v1.3.0"), "/git/ref/tags/": {"ref": "x"}})
        self.assertIn("unreachable", rows["EasyFind"]["error"])
        self.assertEqual(rows["EasyFind_GPS"]["update"], "none")

    def test_aRateLimit_stopsFurtherRequests(self):
        calls = []
        net = self.net({"/releases": rate_limit()}, calls)
        rows = watch.check_vendored(net, LOCK, {})
        self.assertTrue(net.rate_limited)
        self.assertEqual(len(calls), 1, "nothing more is asked once limited")
        self.assertTrue(all(r.get("error") == "rate limited" for r in rows))

    def test_questie_contractKept(self):
        source = "\n".join(watch.QUESTIE_CONTRACT)
        net = self.net({"Questie/Questie/releases": releases("bundle/v12.9.0+v1.0.17"),
                        "codeload.github.com/Questie": tgz({"Questie/Modules/Db.lua": source})})
        row = watch.check_questie(net, {"questie": {"tested": "12.8.0"}})
        self.assertEqual(row["update"], "minor")
        self.assertEqual(row["contract"], "passes")

    def test_questie_contractBroken_namesWhatIsGone(self):
        source = "\n".join(c for c in watch.QUESTIE_CONTRACT if "ZoneDB" not in c)
        net = self.net({"Questie/Questie/releases": releases("bundle/v13.0.0+v2.0.0"),
                        "codeload.github.com/Questie": tgz({"Questie/Modules/Db.lua": source})})
        row = watch.check_questie(net, {"questie": {"tested": "12.8.0"}})
        self.assertEqual(row["contract"], "BROKEN")
        self.assertTrue(any("ZoneDB" in m for m in row["missing"]))

    def test_reusedSources_areForReview(self):
        net = self.net({"/compare/": {"ahead_by": 2, "files": [{"filename": "Market.lua"}]}})
        rows = watch.check_reused(net, {"ForeverNet": {"commit": "10a81d9"}})
        row = {r["name"]: r for r in rows}["ForeverNet"]
        self.assertEqual(row["update"], "review")
        self.assertEqual(row["files"], ["Market.lua"])

    def test_aBranchAlreadyPrepared_isNotPreparedAgain(self):
        rows = [{"name": "EasyFind", "kind": "vendored", "update": "patch", "tag": "v5.3.1", "version": "5.3.1"}]
        import subprocess as sp
        real = sp.run

        def fake_run(cmd, *a, **k):
            if cmd[:2] == ["git", "ls-remote"]:
                return sp.CompletedProcess(cmd, 0, "", "")
            return real(cmd, *a, **k)
        sp.run, watch.subprocess.run = fake_run, fake_run
        try:
            result = watch.prepare(rows, push=True, base="dev", net=self.net({}))
        finally:
            sp.run = watch.subprocess.run = real
        self.assertFalse(result["prepared"])
        self.assertIn("already exists", result["why"])

    def test_nothingToPrepare_whenBlocked(self):
        rows = [{"name": "EasyFind", "kind": "vendored", "update": "major", "tag": "v6.0.0", "version": "6.0.0",
                 "blocked": "license changed"}]
        self.assertFalse(watch.prepare(rows, push=False, base="dev", net=self.net({}))["prepared"])


NOW = dt.datetime(2026, 11, 13, tzinfo=dt.timezone.utc)


def art(i, name, days, branch="main", run=1, expired=False):
    return {"repo": "r", "id": i, "name": name, "bytes": 100, "created": (NOW - dt.timedelta(days=days)).isoformat(),
            "expired": expired, "run": run, "branch": branch, "sha": "abc"}


class Artifacts(unittest.TestCase):
    def decide(self, arts, runs=None, branches=("main",), prs=()):
        runs = runs or {a["run"]: {"name": "CI", "conclusion": "success"} for a in arts}
        return {a["id"]: a for a in artifacts.decide(arts, runs, set(branches), set(prs), 7, NOW)}

    def test_nothingToPrune(self):
        self.assertEqual(artifacts.decide([], {}, set(), set(), 7, NOW), [])

    def test_theNewestIsKept_olderCopiesGo(self):
        d = self.decide([art(1, "build", 30), art(2, "build", 10), art(3, "build", 3)])
        self.assertTrue(d[3]["keep"])
        self.assertFalse(d[1]["keep"])
        self.assertFalse(d[2]["keep"])
        self.assertIn("superseded", d[1]["why"])

    def test_aVeryRecentOlderCopy_waits(self):
        d = self.decide([art(1, "build", 1), art(2, "build", 0)])
        self.assertTrue(d[1]["keep"], "superseded, but under 2 days old")

    def test_theNewest_isKeptHoweverOld(self):
        d = self.decide([art(1, "release-like-build", 200)])
        self.assertTrue(d[1]["keep"])

    def test_failedRuns_keptForDiagnosis(self):
        arts = [art(1, "logs", 5, run=1), art(2, "logs", 1, run=2)]
        runs = {1: {"name": "CI", "conclusion": "failure"}, 2: {"name": "CI", "conclusion": "success"}}
        d = self.decide(arts, runs)
        self.assertTrue(d[1]["keep"])
        self.assertIn("failed run", d[1]["why"])

    def test_deletedBranches_goAfterAWeek(self):
        d = self.decide([art(1, "build", 10, branch="gone"), art(2, "build", 3, branch="gone")])
        self.assertFalse(d[1]["keep"])
        self.assertTrue(d[2]["keep"])

    def test_openPullRequests_keepTheirNewest(self):
        d = self.decide([art(1, "build", 30, branch="pr-branch")], branches=("main",), prs=("pr-branch",))
        self.assertTrue(d[1]["keep"])

    def test_namesForKeeping_areKept(self):
        d = self.decide([art(1, "rollback-package", 60), art(2, "rollback-package", 1)])
        self.assertTrue(d[1]["keep"])

    def test_expired_areLeftAlone(self):
        d = self.decide([art(1, "build", 100, expired=True), art(2, "build", 1)])
        self.assertTrue(d[1]["keep"])
        self.assertIn("expired", d[1]["why"])

    def test_aRateLimit_isReported(self):
        gh = artifacts.GitHub("t", opener=fake_opener({"/": rate_limit()}))
        with self.assertRaises(artifacts.RateLimited):
            gh.request("GET", "/user")

    def test_aRefusedDelete_isAnAnswer_notACrash(self):
        def opener(req, timeout=30):
            raise urllib.error.HTTPError(req.full_url, 403, "forbidden", {}, io.BytesIO(b'{"message": "no"}'))
        status, _, _ = artifacts.GitHub("t", opener=opener).request("DELETE", "/repos/o/r/actions/artifacts/1")
        self.assertEqual(status, 403)


if __name__ == "__main__":
    unittest.main()
