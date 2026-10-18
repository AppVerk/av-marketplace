"""DESKTOP runs: script validation, driver registration, the driver contract, cleanup and secrets.

A fake desktop driver plugin outside the test repository implements the four
contract phases, so these tests need neither a toolkit nor a display.

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
driver = "fake"
args = ["-debug"]
'''
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
MANIFEST = {"contract": 1, "driver": "fake", "version": "0.0.1", "entry": "driver.py"}
FAKE_DRIVER = '''import json, os, subprocess, sys, time
state = os.environ["FAKE_DRIVER_DIR"]
phase, rest = sys.argv[1], sys.argv[2:]
split = rest.index("--") if "--" in rest else len(rest)
options = dict(zip(rest[:split:2], rest[1:split:2]))
with open(os.path.join(state, "calls.jsonl"), "a") as log:
    log.write(json.dumps({"phase": phase, "argv": sys.argv[1:], "cwd": os.getcwd(), "pwd": os.environ.get("PWD"),
                          "leaked": sorted(name for name in os.environ if name.startswith(("QA_", "STORE_")))}) + "\\n")


def mode(name, default="ok"):
    path = os.path.join(state, name)
    return open(path).read().strip() if os.path.exists(path) else default


def hang(name):
    child = subprocess.Popen(["sleep", "600"])
    with open(os.path.join(state, name), "w") as pids:
        pids.write(f"{os.getpid()} {child.pid}")
    time.sleep(600)


if phase == "check":
    value = mode("check-mode")
    if value == "exit1":
        sys.exit(1)
    print({"ok": json.dumps({"result": None}), "tool-missing": json.dumps({"result": "tool-missing", "detail": "go"}),
           "unsupported": json.dumps({"result": "unsupported", "detail": "fake unsupported"})}.get(value, "not json"))
    sys.exit(0)
if phase in ("prepare", "build"):
    value = mode(phase + "-mode")
    if value == "fail":
        print("fake prepare failed" if phase == "prepare" else "main.go:1:1: undefined: brokenSymbol", file=sys.stderr)
        sys.exit(1)
    if value == "hang":
        hang(phase + ".pids")
    if phase == "build":
        open(options["--out"], "w").write("guest")
    sys.exit(0)
calls_path = os.path.join(state, "run.calls")
calls = int(open(calls_path).read()) + 1 if os.path.exists(calls_path) else 1
open(calls_path, "w").write(str(calls))
modes = mode("run-mode", "completed").split()
value = modes[min(calls, len(modes)) - 1]
out = options["--out"]
steps = json.load(open(options["--steps"]))["steps"]
with open(os.path.join(out, "guest.raw.log"), "w") as log:
    log.write("typed " + "".join(step.get("type", "") for step in steps) + "\\n")
if value == "exit1":
    sys.exit(1)
if value == "sleep":
    open(os.path.join(state, "run.pid"), "w").write(str(os.getpid()))
    time.sleep(600)
if value == "pidfile":
    hang("run.pids")
if value in ("bad-type", "partial"):
    json.dump({"result": []} if value == "bad-type" else {"result": "completed"}, open(os.path.join(out, "result.json"), "w"))
    sys.exit(0)
shots, tick = [], 0
for step in steps:
    tick += step.get("wait", 0) + len(step.get("type", ""))
    if "shot" in step:
        name = step["shot"]
        if value != "bad-shot":
            open(os.path.join(out, name + ".png"), "wb").write(b"\\x89PNG\\r\\n\\x1a\\n")
        shots.append({"name": name, "file": name + ".png", "tick": tick})
result, detail, step, completed = {
    "completed": ("completed", None, None, True), "sync-fps": ("completed", None, None, True),
    "bad-shot": ("completed", None, None, True), "quit": ("guest-exited", "guest terminated itself", 0, False),
}.get(value, (value, "fake " + value, None, False))
json.dump({"result": result, "detail": detail, "step": step, "exit_code": 0, "ticks": tick,
           "tps": -1 if value == "sync-fps" else 60, "scale": 2.0,
           "screen": [int(options["--width"]), int(options["--height"])], "shots": shots if completed else []},
          open(os.path.join(out, "result.json"), "w"))
'''
REFERENCE = {"args": ["-seed", "42"], "steps": [
    {"wait": 10}, {"key": "Backquote", "ticks": 3}, {"hold": "ShiftLeft"}, {"type": "seed"}, {"release": "ShiftLeft"},
    {"type_env": "QA_TAG"}, {"move": [10, 20.5]}, {"click": [480, 270], "button": "right"}, {"scroll": [0, -1]},
    {"shot": "console"},
]}
WAIT = {"steps": [{"wait": 1}]}
SHOT = {"steps": [{"wait": 1}, {"shot": "x"}]}


class ScriptValidationTests(unittest.TestCase):
    def test_reference_script_and_a_shot_after_any_advancing_step_pass(self) -> None:
        self.assertEqual(validate_script(REFERENCE, (960, 540))["args"], ["-seed", "42"])
        validate_script({"steps": [{"wait": 1}, {"hold": "KeyA"}, {"shot": "x"}]}, (960, 540))

    def test_every_rule_fails_with_a_script_error_naming_its_step(self) -> None:
        cases: list[tuple[object, int | None]] = [
            ([], None), ({"steps": []}, None), ({"steps": [{"wait": 1}], "extra": 1}, None),
            ({"args": "-seed", "steps": [{"wait": 1}]}, None), ({"args": [1], "steps": [{"wait": 1}]}, None),
            ({"args": ["-v"] * 33, "steps": [{"wait": 1}]}, None), ({"args": ["x" * 257], "steps": [{"wait": 1}]}, None),
            ({"args": ["a\0b"], "steps": [{"wait": 1}]}, None), ({"steps": [{"wait": 1}] * 501}, None),
            ({"steps": [{"wait": 0}]}, 0), ({"steps": [{"wait": 36001}]}, 0), ({"steps": [{"wait": True}]}, 0),
            ({"steps": [{"wait": 1.5}]}, 0), ({"steps": [{"wait": 1}, {"key": "KeyA", "ticks": 601}]}, 1),
            ({"steps": [{"key": "Back quote"}]}, 0), ({"steps": [{"key": "KeyA", "button": "left"}]}, 0),
            ({"steps": [{"wait": 1, "shot": "x"}]}, 0), ({"steps": [{"type": ""}]}, 0), ({"steps": [{"type": "x" * 201}]}, 0),
            ({"steps": [{"type_env": "SENTINEL"}]}, 0), ({"steps": [{"move": [961, 0]}]}, 0), ({"steps": [{"move": [0]}]}, 0),
            ({"steps": [{"click": [True, 1]}]}, 0), ({"steps": [{"click": [1, 1], "button": "side"}]}, 0),
            ({"steps": [{"scroll": [0, 101]}]}, 0), ({"steps": [{"wait": 1}, {"shot": "bad name"}]}, 1),
            ({"steps": [{"shot": "x"}]}, 0), ({"steps": [{"hold": "KeyA"}, {"move": [1, 1]}, {"shot": "x"}]}, 2),
            ({"steps": [{"wait": 1}, {"shot": "x"}, {"shot": "x"}]}, 2),
            ({"steps": [{"wait": 1}, *({"shot": f"s{index}"} for index in range(51))]}, 51),
            ({"steps": [{"wait": 36000}, {"key": "KeyA"}]}, 1), ({"steps": ["wait"]}, 0),
        ]
        for data, index in cases:
            with self.subTest(data=json.dumps(data)[:80]):
                with self.assertRaises(InvalidConfig) as caught:
                    validate_script(data, (960, 540))
                message = str(caught.exception)
                self.assertTrue(message.startswith("script: "), message)
                if index is not None:
                    self.assertIn(f"step {index}:", message)


class DesktopRunTests(unittest.TestCase):
    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name).resolve()
        self.repo = self.root / "repo"
        self.driver = self.root / "fake-driver"
        self.bin = self.root / "bin"
        for directory in (self.repo, self.driver, self.bin):
            directory.mkdir()
        self.manifest = self.write_driver(self.driver)
        (self.bin / "python3").symlink_to(sys.executable)
        self.env = {**os.environ, "PATH": f"{self.bin}{os.pathsep}{os.environ['PATH']}", "TMPDIR": str(self.root),
                    "XDG_STATE_HOME": str(self.root / "state"), "FAKE_DRIVER_DIR": str(self.driver)}
        for args in (("init", "-q"), ("config", "user.name", "QA"), ("config", "user.email", "qa@test.local")):
            subprocess.run(["git", *args], cwd=self.repo, check=True)
        self.put(".av/local.toml\n", ".git/info/exclude")
        self.put("name = 'game'\n", "src/app.py")
        subprocess.run(["git", "add", "src"], cwd=self.repo, check=True)
        subprocess.run(["git", "commit", "-qm", "initial"], cwd=self.repo, check=True)
        self.put(CONFIG, ".av/config.toml")
        plan = self.put(PLAN, "docs/testing/plans/2026-10-16-desktop-test-plan.md")
        self.cli("trust", "accept", self.cli("config")["trust_hash"])
        self.run_id = self.cli("run", "start", str(plan))["run"]
        self.addCleanup(lambda: self.cli("run", "end", "--run", self.run_id))
        self.run_dir = self.root / f"qa-run-{self.run_id}"
        self.cli("users", "provision", "--run", self.run_id)
        self.register()
        self.dispatch = self.new_dispatch()

    def write_driver(self, directory: Path, **overrides: object) -> Path:
        directory.mkdir(parents=True, exist_ok=True)
        (directory / "driver.py").write_text(FAKE_DRIVER)
        manifest = directory / "qa-desktop-driver.json"
        manifest.write_text(json.dumps({**MANIFEST, **overrides}))
        return manifest

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

    def register(self, manifest: Path | None = None, code: int = 0) -> dict[str, object]:
        return self.cli("desktop", "register", "--run", self.run_id, "--manifest", str(manifest or self.manifest), code=code)

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
        (self.driver / name).write_text(value)
        (self.driver / "run.calls").unlink(missing_ok=True)

    def calls(self) -> list[dict[str, object]]:
        path = self.driver / "calls.jsonl"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def phases(self) -> list[str]:
        return [str(call["phase"]) for call in self.calls()]

    def pids(self, name: str) -> list[int]:
        path = self.driver / name
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

    def assertPrivateOutputRemoved(self, result: dict[str, object]) -> None:
        artifacts = Path(str(result["artifacts"]))
        self.assertFalse((artifacts / "guest").exists())
        self.assertFalse((artifacts / "guest.raw.log").exists())

    def test_register_records_the_manifest_for_this_run_only(self) -> None:
        for _ in range(2):
            self.assertEqual(self.register(), {"driver": "fake", "version": "0.0.1", "contract": 1, "manifest": str(self.manifest)})
        registry = self.run_dir / "desktop/drivers.json"
        self.assertEqual(stat.S_IMODE(registry.stat().st_mode), 0o600)
        self.assertEqual(json.loads(registry.read_text())["fake"]["manifest"], str(self.manifest))
        cases = [
            (self.repo / "driver", {}, "desktop driver manifest must be outside the repository"),
            (self.root / "contract", {"contract": 2}, "desktop driver contract 2 is not supported; this qa engine supports contract 1"),
            (self.root / "extra", {"extra": 1}, "desktop driver manifest needs exactly the keys contract, driver, version and entry"),
            (self.root / "name", {"driver": "Bad_Name"}, "desktop driver manifest has an invalid driver name"),
            (self.root / "entry", {"entry": "../x.py"}, "desktop driver entry must be a relative path to a file inside the manifest directory"),
        ]
        for directory, overrides, message in cases:
            with self.subTest(message=message):
                self.assertEqual(self.register(self.write_driver(directory, **overrides), code=2), {"error": message})
        self.assertEqual(self.register(self.write_driver(self.root / "copy"), code=1),
                         {"error": "desktop driver fake is already registered from another manifest"})

    def test_an_unregistered_driver_is_a_missing_tool_without_running_anything(self) -> None:
        (self.run_dir / "desktop/drivers.json").unlink()
        result = self.desktop(WAIT)
        self.assertEqual((result["result"], result["detail"], result["attempts"], result["artifacts"]),
                         ("tool-missing", "desktop-driver:fake", 0, None))
        self.assertFalse((self.driver / "calls.jsonl").exists())

    def test_completed_run_returns_shots_and_runs_every_phase_in_the_repository_without_secrets(self) -> None:
        with mock.patch.dict(self.env, {"QA_LEAK_PROBE": "1", "STORE_PROBE_PGPASSWORD": "x"}):
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
        self.assertPrivateOutputRemoved(result)
        calls = self.calls()
        self.assertEqual([call["phase"] for call in calls], ["check", "prepare", "build", "run"])
        for call in calls:
            self.assertEqual((call["cwd"], call["pwd"], call["leaked"]), (str(self.repo), str(self.repo), []))
        argv = calls[-1]["argv"]
        self.assertEqual(argv[argv.index("--") + 1:], ["-debug", "-seed", "42"])
        self.assertEqual(argv[argv.index("--deadline") + 1], "135")

    def test_prepare_runs_once_per_run_and_driver(self) -> None:
        for _ in range(2):
            self.assertEqual(self.desktop(WAIT)["result"], "completed")
        self.assertEqual(self.phases(), ["check", "prepare", "build", "run", "check", "build", "run"])

    def test_check_answers_end_the_call_before_any_other_phase(self) -> None:
        cases = {"tool-missing": ("tool-missing", "go"), "unsupported": ("unsupported", "fake unsupported"),
                 "garbage": ("host-failed", "desktop driver check failed"), "exit1": ("host-failed", "desktop driver check failed")}
        for check, expected in cases.items():
            with self.subTest(check=check):
                self.mode("check-mode", check)
                result = self.desktop(WAIT)
                self.assertEqual((result["result"], result["detail"]), expected)
        self.assertEqual(set(self.phases()), {"check"})

    def test_prepare_failure_is_a_host_build_failure_and_is_retried_next_call(self) -> None:
        self.mode("prepare-mode", "fail")
        result = self.desktop(WAIT)
        self.assertEqual((result["result"], result["detail"]), ("host-build-failed", "fake prepare failed"))
        self.assertFalse((self.run_dir / "desktop/fake/.prepared").exists())
        self.mode("prepare-mode", "ok")
        self.assertEqual(self.desktop(WAIT)["result"], "completed")
        self.assertEqual(self.phases(), ["check", "prepare", "check", "prepare", "build", "run"])

    def test_build_failure_reports_its_log_and_never_runs_the_app(self) -> None:
        self.mode("build-mode", "fail")
        result = self.desktop(WAIT)
        self.assertEqual(result["result"], "build-failed")
        self.assertTrue(Path(result["build_log"]).is_file())
        self.assertEqual(result["detail"], "main.go:1:1: undefined: brokenSymbol")
        self.assertNotIn("run", self.phases())

    def test_only_a_handshake_failure_is_retried(self) -> None:
        self.mode("run-mode", "handshake-failed completed")
        result = self.desktop(WAIT)
        self.assertEqual((result["result"], result["attempts"]), ("completed", 2))
        self.mode("run-mode", "guest-exited completed")
        result = self.desktop(WAIT)
        self.assertEqual((result["result"], result["attempts"], result["detail"]), ("guest-exited", 1, "fake guest-exited"))

    def test_a_retry_never_reads_the_first_attempt_result(self) -> None:
        self.mode("run-mode", "handshake-failed exit1")
        result = self.desktop(WAIT)
        self.assertEqual((result["result"], result["attempts"], result["detail"]),
                         ("host-failed", 2, "host exited 1 without result.json"))

    def test_a_result_that_breaks_the_schema_is_a_host_failure(self) -> None:
        for value in ("bad-type", "partial", "bad-shot"):
            with self.subTest(mode=value):
                self.mode("run-mode", value)
                result = self.in_process(SHOT)
                self.assertEqual((result["result"], result["detail"], result["attempts"], result["shots"]),
                                 ("host-failed", "host exited 0 with an invalid result.json", 1, []))
                self.assertPrivateOutputRemoved(result)

    def test_an_intentional_quit_and_frame_synced_ticks_pass_through(self) -> None:
        self.mode("run-mode", "quit")
        result = self.desktop(WAIT)
        self.assertEqual((result["result"], result["exit_code"], result["detail"], result["attempts"]),
                         ("guest-exited", 0, "guest terminated itself", 1))
        self.mode("run-mode", "sync-fps")
        result = self.desktop(WAIT)
        self.assertEqual((result["result"], result["tps"]), ("completed", -1))

    def test_run_timeout_kills_the_driver_process_group(self) -> None:
        self.mode("run-mode", "sleep")
        result = self.in_process(WAIT, host_timeout=1)
        self.assertEqual((result["result"], result["detail"]), ("timeout", "host did not finish within 1s"))
        self.assertGone(*self.pids("run.pid"))

    def test_prepare_and_build_timeouts_kill_the_driver_and_its_children(self) -> None:
        self.mode("prepare-mode", "hang")
        result = self.in_process(WAIT, build_timeout=1)
        self.assertEqual((result["result"], result["detail"]), ("host-build-failed", "driver prepare timed out after 1s"))
        self.assertGone(*self.pids("prepare.pids"))
        self.mode("prepare-mode", "ok")
        self.mode("build-mode", "hang")
        result = self.in_process(WAIT, build_timeout=1)
        self.assertEqual((result["result"], result["detail"]), ("build-failed", "guest build timed out after 1s"))
        self.assertGone(*self.pids("build.pids"))

    def test_sigterm_during_a_build_interrupts_and_kills_it(self) -> None:
        self.mode("build-mode", "hang")
        process = subprocess.Popen([sys.executable, str(SCRIPTS / "qa.py"), *self.desktop_args(WAIT), "--repo", str(self.repo)],
                                   env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        pids = self.pids("build.pids")
        process.send_signal(signal.SIGTERM)
        stdout, stderr = process.communicate(timeout=30)
        self.assertEqual(process.returncode, 1, stdout + stderr)
        self.assertEqual(json.loads(stdout), {"error": "desktop run interrupted"})
        self.assertGone(*pids)

    def test_sigterm_while_the_app_runs_cleans_up_and_masks(self) -> None:
        self.mode("run-mode", "pidfile")
        args = self.desktop_args({"steps": [{"wait": 1}, {"type_env": "QA_SENTINEL"}]})
        process = subprocess.Popen([sys.executable, str(SCRIPTS / "qa.py"), *args, "--repo", str(self.repo)],
                                   env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        pids = self.pids("run.pids")
        process.send_signal(signal.SIGTERM)
        stdout, stderr = process.communicate(timeout=30)
        self.assertEqual(process.returncode, 1, stdout + stderr)
        self.assertEqual(json.loads(stdout), {"error": "desktop run interrupted"})
        self.assertGone(*pids)
        artifacts = next((self.run_dir / f"results/{self.dispatch['dispatch']}/desktop").iterdir())
        self.assertFalse((artifacts / "guest.raw.log").exists())
        self.assertFalse((artifacts / "guest").exists())
        self.assertNotIn(SENTINEL, (artifacts / "guest.log").read_text())

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
        secrets = self.run_dir / "secrets.json"
        secrets.write_text(json.dumps({**json.loads(secrets.read_text()), "QA_EMPTY": ""}))
        for name in ("QA_MISSING", "QA_EMPTY"):
            with self.subTest(name=name):
                result = self.desktop({"steps": [{"type_env": name}]}, code=2)
                self.assertEqual(result, {"error": f"script: type_env {name} is not exposed"})

    def test_wrong_dispatch_unknown_app_and_config_drift_stop_with_exit_one(self) -> None:
        frontend = self.new_dispatch("FE")
        self.assertEqual(self.desktop(WAIT, frontend, code=1), {"error": "dispatch is not a DESKTOP tester dispatch"})
        self.assertEqual(self.desktop(WAIT, target="tools", code=1), {"error": "unknown desktop app: tools"})
        self.put(CONFIG.replace('args = ["-debug"]', 'args = ["-debug", "-v"]'), ".av/config.toml")
        self.assertEqual(self.desktop(WAIT, code=1), {"error": "config changed during run"})

    def test_provision_writes_the_desktop_helper(self) -> None:
        helper = self.run_dir / "desktop.sh"
        self.assertEqual(stat.S_IMODE(helper.stat().st_mode), 0o600)
        script = str(self.script(WAIT))
        dispatch = str(self.dispatch["dispatch"])
        for args in ((dispatch, "app"), ("X001", "app", script), (dispatch, "bad-app", script), (dispatch, "1app", script)):
            with self.subTest(args=args):
                self.assertEqual(subprocess.run(["sh", str(helper), *args], env=self.env, capture_output=True, check=False).returncode, 2)
        result = subprocess.run(["sh", str(helper), dispatch, "app", script], env=self.env, capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(json.loads(result.stdout)["result"], "completed")


if __name__ == "__main__":
    unittest.main()
