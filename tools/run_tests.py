#!/usr/bin/env python3
"""Run every Lua test suite in the repository and report one summary.

    python tools/run_tests.py            # everything
    python tools/run_tests.py forever    # only the named suites
    (suites: easyfind, gps, questie, forever)

Upstream suites run from their own addon folder, as their CI does. On Windows
the POSIX shell-outs in those tests go through tools/win_popen.lua.
"""
from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LUA = os.environ.get("LUA") or shutil.which("lua") or shutil.which("lua5.4") or "lua"
QUESTIE_MODES = ("normal", "noapi", "oldapi", "questie", "data", "old")


def lua_cmd(script_args: list[str], env: dict) -> list[str]:
    if os.name == "nt" and env.get("FGPS_BASH"):
        shim = (ROOT / "tools" / "win_popen.lua").as_posix()
        return [LUA, "-e", f"dofile('{shim}')", *script_args]
    return [LUA, *script_args]


def run(cmd: list[str], cwd: Path, env: dict) -> tuple[int, str]:
    p = subprocess.run(cmd, cwd=cwd, env=env, capture_output=True, text=True, encoding="utf-8", errors="replace")
    return p.returncode, (p.stdout or "") + (p.stderr or "")


def results(out: str) -> tuple[int, int]:
    m = re.findall(r"== Results: (\d+) passed, (\d+) failed ==", out)
    return (int(m[-1][0]), int(m[-1][1])) if m else (0, 0)


def suite_lua(name: str, folder: Path, entry: str, env: dict) -> dict:
    code, out = run(lua_cmd([entry], env), folder, env)
    passed, failed = results(out)
    return {"name": name, "ok": code == 0 and passed > 0, "passed": passed, "failed": failed, "out": out}


def suite_questie(env: dict) -> dict:
    folder = ROOT / "addons" / "EasyFind_Questie"
    passed, failed, logs = 0, 0, []
    for mode in QUESTIE_MODES:
        code, out = run(lua_cmd(["tools/tests/smoke_test.lua", ".", "EasyFind_Questie.toc", "EasyFind_Questie", mode], env), folder, env)
        logs.append(f"== {mode}\n{out}")
        if code == 0:
            passed += 1
        else:
            failed += 1
    return {"name": "questie", "ok": failed == 0, "passed": passed, "failed": failed, "out": "\n".join(logs)}


def main(argv: list[str]) -> int:
    want = set(argv[1:]) or {"easyfind", "gps", "questie", "forever"}
    env = dict(os.environ)
    tmp = None
    if os.name == "nt":
        tmp = tempfile.mkdtemp(prefix="fgps-popen-")
        env["FGPS_TMP"] = Path(tmp).as_posix()
        bash = shutil.which("bash")
        # Git's bash, never the WSL launcher in System32.
        if bash and "system32" not in bash.lower():
            env["FGPS_BASH"] = bash
    env.setdefault("EASYFIND_ROOT", (ROOT / "addons" / "EasyFind").as_posix())
    jobs = []
    if "easyfind" in want:
        jobs.append(lambda: suite_lua("easyfind", ROOT / "addons" / "EasyFind", "tests/Run.lua", env))
    if "gps" in want:
        jobs.append(lambda: suite_lua("gps", ROOT / "addons" / "EasyFind_GPS", "tests/Run.lua", env))
    if "questie" in want:
        jobs.append(lambda: suite_questie(env))
    if "forever" in want:
        jobs.append(lambda: suite_lua("forever", ROOT, "tests/run.lua", env))
    all_ok, summary = True, []
    for job in jobs:
        start = time.time()
        res = job()
        took = time.time() - start
        all_ok = all_ok and res["ok"]
        summary.append(f"{res['name']:<10} {'PASS' if res['ok'] else 'FAIL'}  {res['passed']} passed, {res['failed']} failed  ({took:.0f}s)")
        if not res["ok"]:
            print(res["out"][-6000:])
    if tmp:
        shutil.rmtree(tmp, ignore_errors=True)
    print("\n".join(summary))
    return 0 if all_ok else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
