"""DESKTOP runs: script validation, builds, the host contract, cleanup and secrets.

A fake ``go`` first on PATH builds a fake host and guest, so these tests need
neither Go nor a display.

Run: uv run python -m unittest discover -s plugins/qa/tests -p test_engine_desktop.py
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import signal
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

SCRIPTS = Path(__file__).resolve().parents[1] / "skills/engine/scripts"
sys.path.insert(0, str(SCRIPTS))

from av_config.errors import InvalidConfig
from qa_engine.desktop import ebitengine_requirement
from qa_engine.desktop import run_desktop
from qa_engine.desktop import validate_script

SENTINEL = "qa-sentinel-7319"
CONFIG = f'''version = 1
[env.targets]
ui = "http://localhost:5173"
[env.values]
sentinel = "literal:{SENTINEL}"
[qa]
[qa.desktop.app]
driver = "ebitengine"
args = ["-debug"]
'''
GO_MOD = "module example.com/game\n\ngo 1.25\n\nrequire github.com/hajimehoshi/ebiten/v2 v2.10.5\n"
PLAN = '''# Test Plan
## FE Test Scenarios
### FE-01: Display items
- **Writes:** no
- **URL:** /items
- **Expected:** Items are displayed. (src/app.py:1)
## DESKTOP Test Scenarios
### DESKTOP-01: Console echoes typed text
- **Writes:** no
- **Steps:** Wait 2 ticks, type $QA_TAG and $QA_SENTINEL, shot `after`
- **Expected:** Shot `after` shows the typed text. (src/app.py:1)
'''
FAKE_GO = '''#!{python}
import json, os, shutil, subprocess, sys, time
state = os.environ["FAKE_GO_DIR"]
args = sys.argv[1:]
with open(os.path.join(state, "go.log"), "a") as log:
    log.write(json.dumps({{"argv": args, "cwd": os.getcwd()}}) + "\\n")
guest = "-tags" in args
mode_file = os.path.join(state, "guest-build" if guest else "host-build")
mode = open(mode_file).read().strip() if os.path.exists(mode_file) else "ok"
if mode == "fail":
    print("main.go:1:1: undefined: brokenSymbol", file=sys.stderr)
    sys.exit(1)
if mode == "hang":
    child = subprocess.Popen(["sleep", "600"])
    with open(os.path.join(state, "build.pids"), "w") as pids:
        pids.write(f"{{os.getpid()}} {{child.pid}}")
    time.sleep(600)
out = args[args.index("-o") + 1]
shutil.copy(os.path.join(state, "guest.sh" if guest else "host.py"), out)
os.chmod(out, 0o755)
'''
FAKE_HOST = '''#!{python}
import json, os, subprocess, sys, time
state = os.environ["FAKE_GO_DIR"]
argv = sys.argv[1:]
with open(os.path.join(state, "host.log"), "a") as log:
    log.write(json.dumps(argv) + "\\n")
with open(os.path.join(state, "host.pid"), "w") as pid:
    pid.write(str(os.getpid()))
options, index = {{}}, 0
while argv[index] != "--":
    options[argv[index]] = argv[index + 1]
    index += 2
out = options["-out"]
calls_path = os.path.join(state, "host.calls")
calls = int(open(calls_path).read()) + 1 if os.path.exists(calls_path) else 1
open(calls_path, "w").write(str(calls))
mode_path = os.path.join(state, "host-mode")
modes = open(mode_path).read().split() if os.path.exists(mode_path) else ["completed"]
mode = modes[min(calls, len(modes)) - 1]
steps = json.load(open(options["-script"]))["steps"]
with open(os.path.join(out, "guest.raw.log"), "w") as log:
    log.write("typed " + "".join(step.get("type", "") for step in steps) + "\\n")
if mode == "exit1":
    sys.exit(1)
if mode == "sleep":
    time.sleep(600)
if mode == "pidfile":
    child = subprocess.Popen(["sleep", "600"])
    with open(os.path.join(state, "host.pids"), "w") as pids:
        pids.write(f"{{os.getpid()}} {{child.pid}}")
    time.sleep(600)
shots, tick = [], 0
for step in steps:
    tick += step.get("wait", 0) + len(step.get("type", ""))
    if "shot" in step:
        name = step["shot"]
        open(os.path.join(out, name + ".png"), "wb").write(b"\\x89PNG\\r\\n\\x1a\\n")
        shots.append({{"name": name, "file": name + ".png", "tick": tick}})
result = {{"result": mode, "detail": None if mode == "completed" else "fake " + mode, "step": None, "exit_code": 0,
          "ticks": tick, "tps": 60, "scale": 2.0, "screen": [int(options["-w"]), int(options["-h"])],
          "shots": shots if mode == "completed" else []}}
json.dump(result, open(os.path.join(out, "result.json"), "w"))
'''
REFERENCE = {"args": ["-seed", "42"], "steps": [
    {"wait": 10}, {"key": "Backquote", "ticks": 3}, {"hold": "ShiftLeft"}, {"type": "seed"}, {"release": "ShiftLeft"},
    {"type_env": "QA_TAG"}, {"move": [10, 20.5]}, {"click": [480, 270], "button": "right"}, {"scroll": [0, -1]},
    {"shot": "console"},
]}


class ScriptValidationTests(unittest.TestCase):
    def test_reference_script_and_a_shot_after_any_advancing_step_pass(self) -> None:
        self.assertEqual(validate_script(REFERENCE, (960, 540))["args"], ["-seed", "42"])
        validate_script({"steps": [{"wait": 1}, {"hold": "A"}, {"shot": "x"}]}, (960, 540))

    def test_every_rule_fails_with_a_script_error_naming_its_step(self) -> None:
        cases: list[tuple[object, int | None]] = [
            ([], None), ({"steps": []}, None), ({"steps": [{"wait": 1}], "extra": 1}, None),
            ({"args": "-seed", "steps": [{"wait": 1}]}, None), ({"args": [1], "steps": [{"wait": 1}]}, None),
            ({"args": ["-v"] * 33, "steps": [{"wait": 1}]}, None), ({"args": ["x" * 257], "steps": [{"wait": 1}]}, None),
            ({"args": ["a\0b"], "steps": [{"wait": 1}]}, None), ({"steps": [{"wait": 1}] * 501}, None),
            ({"steps": [{"wait": 0}]}, 0), ({"steps": [{"wait": 36001}]}, 0), ({"steps": [{"wait": True}]}, 0),
            ({"steps": [{"wait": 1.5}]}, 0), ({"steps": [{"wait": 1}, {"key": "A", "ticks": 601}]}, 1),
            ({"steps": [{"key": "Back quote"}]}, 0), ({"steps": [{"key": "A", "button": "left"}]}, 0),
            ({"steps": [{"wait": 1, "shot": "x"}]}, 0), ({"steps": [{"type": ""}]}, 0), ({"steps": [{"type": "x" * 201}]}, 0),
            ({"steps": [{"type_env": "SENTINEL"}]}, 0), ({"steps": [{"move": [961, 0]}]}, 0), ({"steps": [{"move": [0]}]}, 0),
            ({"steps": [{"click": [True, 1]}]}, 0), ({"steps": [{"click": [1, 1], "button": "side"}]}, 0),
            ({"steps": [{"scroll": [0, 101]}]}, 0), ({"steps": [{"wait": 1}, {"shot": "bad name"}]}, 1),
            ({"steps": [{"shot": "x"}]}, 0), ({"steps": [{"hold": "A"}, {"move": [1, 1]}, {"shot": "x"}]}, 2),
            ({"steps": [{"wait": 1}, {"shot": "x"}, {"shot": "x"}]}, 2),
            ({"steps": [{"wait": 1}, *({"shot": f"s{index}"} for index in range(51))]}, 51),
            ({"steps": [{"wait": 36000}, {"key": "A"}]}, 1), ({"steps": ["wait"]}, 0),
        ]
        for data, index in cases:
            with self.subTest(data=json.dumps(data)[:80]):
                with self.assertRaises(InvalidConfig) as caught:
                    validate_script(data, (960, 540))
                message = str(caught.exception)
                self.assertTrue(message.startswith("script: "), message)
                if index is not None:
                    self.assertIn(f"step {index}:", message)


class EligibilityTests(unittest.TestCase):
    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.repo = Path(tmp.name)

    def requirement(self, text: str | None) -> str | None:
        if text is not None:
            (self.repo / "go.mod").write_text(text)
        return ebitengine_requirement(self.repo)

    def test_supported_modules_need_no_module_cache_or_vendor_state(self) -> None:
        with mock.patch.dict(os.environ, {"GOMODCACHE": str(self.repo / "empty-cache")}):
            self.assertIsNone(self.requirement(GO_MOD))
        (self.repo / "vendor/github.com/hajimehoshi/ebiten/v2").mkdir(parents=True)
        self.assertIsNone(self.requirement(GO_MOD))
        self.assertIsNone(self.requirement("module m\n\nrequire (\n\tgithub.com/hajimehoshi/ebiten/v2 v2.11.0-alpha.1 // indirect\n)\n"))
        self.assertIsNone(self.requirement("module m\nrequire github.com/hajimehoshi/ebiten/v2 v2.9.0\nreplace github.com/hajimehoshi/ebiten/v2 => ../ebiten\n"))

    def test_unsupported_modules_name_the_reason(self) -> None:
        self.assertEqual(self.requirement(None), "no go.mod at the repository root")
        self.assertEqual(self.requirement("module m\n\nrequire github.com/hajimehoshi/ebiten v1.12.12\n"),
                         "go.mod does not require github.com/hajimehoshi/ebiten/v2")
        self.assertEqual(self.requirement("module m\n\nrequire github.com/hajimehoshi/ebiten/v2 v2.9.0\n"),
                         "go.mod requires github.com/hajimehoshi/ebiten/v2 v2.9.0; the QA desktop driver supports v2.10.5 or later")


class DesktopRunTests(unittest.TestCase):
    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name).resolve()
        self.repo = self.root / "repo"
        self.fake = self.root / "fake"
        self.bin = self.root / "bin"
        for directory in (self.repo, self.fake, self.bin):
            directory.mkdir()
        self.executable(self.bin / "go", FAKE_GO.format(python=sys.executable))
        (self.bin / "python3").symlink_to(sys.executable)
        (self.fake / "host.py").write_text(FAKE_HOST.format(python=sys.executable))
        (self.fake / "guest.sh").write_text("#!/bin/sh\nexit 0\n")
        self.env = {**os.environ, "PATH": f"{self.bin}{os.pathsep}{os.environ['PATH']}", "TMPDIR": str(self.root),
                    "XDG_STATE_HOME": str(self.root / "state"), "FAKE_GO_DIR": str(self.fake)}
        for args in (("init", "-q"), ("config", "user.name", "QA"), ("config", "user.email", "qa@test.local")):
            subprocess.run(["git", *args], cwd=self.repo, check=True)
        self.put(".av/local.toml\n", ".git/info/exclude")
        self.put("name = 'game'\n", "src/app.py")
        subprocess.run(["git", "add", "src"], cwd=self.repo, check=True)
        subprocess.run(["git", "commit", "-qm", "initial"], cwd=self.repo, check=True)
        self.put(CONFIG, ".av/config.toml")
        self.put(GO_MOD, "go.mod")
        plan = self.put(PLAN, "docs/testing/plans/2026-10-16-desktop-test-plan.md")
        self.cli("trust", "accept", self.cli("config")["trust_hash"])
        self.run_id = self.cli("run", "start", str(plan))["run"]
        self.addCleanup(lambda: self.cli("run", "end", "--run", self.run_id))
        self.cli("users", "provision", "--run", self.run_id)
        self.dispatch = self.new_dispatch()

    def executable(self, path: Path, text: str) -> None:
        path.write_text(text)
        path.chmod(0o755)

    def put(self, content: str, name: str) -> Path:
        path = self.repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        return path

    def invoke(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run([sys.executable, str(SCRIPTS / "qa.py"), *args, "--repo", str(self.repo)],
                              env=self.env, capture_output=True, text=True, check=False)

    def cli(self, *args: str, code: int = 0) -> dict[str, object]:
        result = self.invoke(*args)
        self.assertEqual(result.returncode, code, result.stdout + result.stderr)
        return json.loads(result.stdout)

    def new_dispatch(self, section: str = "DESKTOP") -> dict[str, object]:
        return self.cli("dispatch", "--run", self.run_id, "tester", "--section", section, "--phase", "baseline")

    def script(self, data: object) -> Path:
        path = self.root / f"script-{time.monotonic_ns()}.json"
        path.write_text(json.dumps(data))
        return path

    def desktop_args(self, data: object, dispatch: dict[str, object] | None = None, target: str = "app") -> list[str]:
        return ["desktop", "run", "--run", self.run_id, "--dispatch", str((dispatch or self.dispatch)["dispatch"]),
                "--target", target, "--script", str(self.script(data))]

    def desktop(self, data: object, dispatch: dict[str, object] | None = None, target: str = "app", code: int = 0) -> dict[str, object]:
        return self.cli(*self.desktop_args(data, dispatch, target), code=code)

    def in_process(self, data: object, **limits: float) -> dict[str, object]:
        with mock.patch.dict(os.environ, self.env, clear=True):
            return run_desktop(self.repo, self.run_id, str(self.dispatch["dispatch"]), "app", self.script(data), **limits)

    def mode(self, name: str, value: str) -> None:
        (self.fake / name).write_text(value)
        (self.fake / "host.calls").unlink(missing_ok=True)

    def go_builds(self) -> tuple[int, int]:
        calls = [json.loads(line)["argv"] for line in (self.fake / "go.log").read_text().splitlines()]
        return sum("-tags" not in argv for argv in calls), sum("-tags" in argv for argv in calls)

    def host_argv(self) -> list[str]:
        return json.loads((self.fake / "host.log").read_text().splitlines()[-1])

    def pids(self, name: str) -> list[int]:
        path = self.fake / name
        deadline = time.monotonic() + 30
        while not path.exists() or not path.read_text().strip():
            if time.monotonic() > deadline:
                self.fail(f"{name} never appeared")
            time.sleep(0.05)
        return [int(pid) for pid in path.read_text().split()]

    def assertGone(self, *pids: int) -> None:
        deadline = time.monotonic() + 5
        for pid in pids:
            while True:
                try:
                    os.kill(pid, 0)
                except ProcessLookupError:
                    break
                if time.monotonic() > deadline:
                    self.fail(f"process {pid} survived")
                time.sleep(0.05)

    def test_completed_run_returns_shots_and_removes_private_output(self) -> None:
        result = self.desktop({"args": ["-seed", "42"], "steps": [{"wait": 2}, {"shot": "start"}, {"type": "seed"}, {"shot": "console"}]})
        self.assertEqual((result["result"], result["attempts"], result["tps"]), ("completed", 1, 60))
        self.assertEqual([shot["name"] for shot in result["shots"]], ["start", "console"])
        for shot in result["shots"]:
            self.assertTrue(Path(shot["path"]).is_absolute())
            self.assertTrue(Path(shot["path"]).is_file())
            self.assertFalse(shot["sensitive"])
        artifacts = Path(result["artifacts"])
        self.assertEqual(stat.S_IMODE(artifacts.stat().st_mode), 0o700)
        for name in ("steps.json", "guest.log"):
            self.assertEqual(stat.S_IMODE((artifacts / name).stat().st_mode), 0o600)
        self.assertEqual(result["log"], str(artifacts / "guest.log"))
        self.assertFalse((artifacts / "guest").exists())
        self.assertFalse((artifacts / "guest.raw.log").exists())
        argv = self.host_argv()
        self.assertEqual(argv[argv.index("--") + 1:], ["-debug", "-seed", "42"])

    def test_host_is_built_once_per_run_and_the_guest_per_call(self) -> None:
        for _ in range(2):
            self.assertEqual(self.desktop({"steps": [{"wait": 1}]})["result"], "completed")
        self.assertEqual(self.go_builds(), (1, 2))

    def test_only_a_handshake_failure_is_retried(self) -> None:
        self.mode("host-mode", "handshake-failed completed")
        result = self.desktop({"steps": [{"wait": 1}]})
        self.assertEqual((result["result"], result["attempts"]), ("completed", 2))
        self.mode("host-mode", "guest-exited completed")
        result = self.desktop({"steps": [{"wait": 1}]})
        self.assertEqual((result["result"], result["attempts"], result["detail"]), ("guest-exited", 1, "fake guest-exited"))

    def test_a_retry_never_reads_the_first_attempt_result(self) -> None:
        self.mode("host-mode", "handshake-failed exit1")
        result = self.desktop({"steps": [{"wait": 1}]})
        self.assertEqual((result["result"], result["attempts"], result["detail"]),
                         ("host-failed", 2, "host exited 1 without result.json"))

    def test_guest_build_failure_reports_its_log_and_never_runs_the_host(self) -> None:
        self.mode("guest-build", "fail")
        result = self.desktop({"steps": [{"wait": 1}]})
        self.assertEqual(result["result"], "build-failed")
        self.assertTrue(Path(result["build_log"]).is_file())
        self.assertEqual(result["detail"], "main.go:1:1: undefined: brokenSymbol")
        self.assertFalse((self.fake / "host.log").exists())

    def test_host_timeout_kills_the_host_process_group(self) -> None:
        self.mode("host-mode", "sleep")
        result = self.in_process({"steps": [{"wait": 1}]}, host_timeout=1)
        self.assertEqual((result["result"], result["detail"]), ("timeout", "host did not finish within 1s"))
        self.assertGone(*self.pids("host.pid"))

    def test_build_timeouts_kill_go_and_its_children(self) -> None:
        self.mode("host-build", "hang")
        result = self.in_process({"steps": [{"wait": 1}]}, build_timeout=1)
        self.assertEqual((result["result"], result["detail"]), ("host-build-failed", "host build timed out after 1s"))
        self.assertGone(*self.pids("build.pids"))
        (self.fake / "build.pids").unlink()
        self.mode("host-build", "ok")
        self.mode("guest-build", "hang")
        result = self.in_process({"steps": [{"wait": 1}]}, build_timeout=1)
        self.assertEqual((result["result"], result["detail"]), ("build-failed", "guest build timed out after 1s"))
        self.assertGone(*self.pids("build.pids"))

    def test_sigterm_during_a_build_interrupts_and_kills_it(self) -> None:
        self.mode("guest-build", "hang")
        process = subprocess.Popen([sys.executable, str(SCRIPTS / "qa.py"), *self.desktop_args({"steps": [{"wait": 1}]}), "--repo", str(self.repo)],
                                   env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        pids = self.pids("build.pids")
        process.send_signal(signal.SIGTERM)
        stdout, stderr = process.communicate(timeout=30)
        self.assertEqual(process.returncode, 1, stdout + stderr)
        self.assertEqual(json.loads(stdout), {"error": "desktop run interrupted"})
        self.assertGone(*pids)

    def test_sigterm_while_the_host_runs_cleans_up_and_masks(self) -> None:
        self.mode("host-mode", "pidfile")
        args = self.desktop_args({"steps": [{"wait": 1}, {"type_env": "QA_SENTINEL"}]})
        process = subprocess.Popen([sys.executable, str(SCRIPTS / "qa.py"), *args, "--repo", str(self.repo)],
                                   env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        pids = self.pids("host.pids")
        process.send_signal(signal.SIGTERM)
        stdout, stderr = process.communicate(timeout=30)
        self.assertEqual(process.returncode, 1, stdout + stderr)
        self.assertEqual(json.loads(stdout), {"error": "desktop run interrupted"})
        self.assertGone(*pids)
        artifacts = next((self.root / f"qa-run-{self.run_id}/results/{self.dispatch['dispatch']}/desktop").iterdir())
        self.assertFalse((artifacts / "guest.raw.log").exists())
        self.assertFalse((artifacts / "guest").exists())
        self.assertNotIn(SENTINEL, (artifacts / "guest.log").read_text())
        argv = self.host_argv()
        self.assertEqual(argv[argv.index("-deadline") + 1], "135s")

    def test_type_env_types_each_dispatch_tag_and_private_values_masked(self) -> None:
        tagged = {"steps": [{"wait": 1}, {"type_env": "QA_TAG"}, {"shot": "tag"}]}
        second = self.new_dispatch()
        for dispatch in (self.dispatch, second):
            result = self.desktop(tagged, dispatch)
            self.assertIn(f"typed {dispatch['tag']}", Path(result["log"]).read_text())
            self.assertEqual([shot["sensitive"] for shot in result["shots"]], [False])
        self.assertNotEqual(self.dispatch["tag"], second["tag"])
        process = self.invoke(*self.desktop_args({"steps": [{"wait": 1}, {"shot": "before"}, {"type_env": "QA_SENTINEL"}, {"shot": "after"}]}))
        self.assertEqual(process.returncode, 0, process.stdout + process.stderr)
        self.assertNotIn(SENTINEL, process.stdout)
        result = json.loads(process.stdout)
        self.assertEqual([(shot["name"], shot["sensitive"]) for shot in result["shots"]], [("before", False), ("after", True)])
        artifacts = Path(result["artifacts"])
        self.assertNotIn(SENTINEL, (artifacts / "script.json").read_text())
        self.assertIn(SENTINEL, (artifacts / "steps.json").read_text())
        log = Path(result["log"]).read_text()
        self.assertNotIn(SENTINEL, log)
        self.assertIn("***", log)

    def test_unexposed_or_empty_type_env_names_are_script_errors(self) -> None:
        secrets = self.root / f"qa-run-{self.run_id}/secrets.json"
        secrets.write_text(json.dumps({**json.loads(secrets.read_text()), "QA_EMPTY": ""}))
        for name in ("QA_MISSING", "QA_EMPTY"):
            with self.subTest(name=name):
                result = self.desktop({"steps": [{"type_env": name}]}, code=2)
                self.assertEqual(result, {"error": f"script: type_env {name} is not exposed"})

    def test_missing_go_and_unsupported_modules_are_reported_without_building(self) -> None:
        empty = self.root / "empty-bin"
        empty.mkdir()
        with mock.patch.dict(self.env, {"PATH": str(empty)}):
            result = self.in_process({"steps": [{"wait": 1}]})
        self.assertEqual((result["result"], result["detail"]), ("tool-missing", "go"))
        self.put(GO_MOD.replace("v2.10.5", "v2.9.0"), "go.mod")
        result = self.desktop({"steps": [{"wait": 1}]})
        self.assertEqual((result["result"], result["detail"]), (
            "unsupported", "go.mod requires github.com/hajimehoshi/ebiten/v2 v2.9.0; the QA desktop driver supports v2.10.5 or later"))
        self.assertFalse((self.fake / "go.log").exists())

    def test_wrong_dispatch_unknown_app_and_config_drift_stop_with_exit_one(self) -> None:
        frontend = self.new_dispatch("FE")
        self.assertEqual(self.desktop({"steps": [{"wait": 1}]}, frontend, code=1), {"error": "dispatch is not a DESKTOP tester dispatch"})
        self.assertEqual(self.desktop({"steps": [{"wait": 1}]}, target="tools", code=1), {"error": "unknown desktop app: tools"})
        self.put(CONFIG.replace('args = ["-debug"]', 'args = ["-debug", "-v"]'), ".av/config.toml")
        self.assertEqual(self.desktop({"steps": [{"wait": 1}]}, code=1), {"error": "config changed during run"})

    def test_provision_writes_the_desktop_helper(self) -> None:
        helper = self.root / f"qa-run-{self.run_id}/desktop.sh"
        self.assertEqual(stat.S_IMODE(helper.stat().st_mode), 0o600)
        script = str(self.script({"steps": [{"wait": 1}]}))
        dispatch = str(self.dispatch["dispatch"])
        for args in ((dispatch, "app"), ("X001", "app", script), (dispatch, "bad-app", script), (dispatch, "1app", script)):
            with self.subTest(args=args):
                self.assertEqual(subprocess.run(["sh", str(helper), *args], env=self.env, capture_output=True, check=False).returncode, 2)
        result = subprocess.run(["sh", str(helper), dispatch, "app", script], env=self.env, capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(json.loads(result.stdout)["result"], "completed")


if __name__ == "__main__":
    unittest.main()
