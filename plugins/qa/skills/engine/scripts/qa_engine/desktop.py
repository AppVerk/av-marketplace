"""Run DESKTOP scripts headless through the app's registered desktop driver plugin.

Desktop driver contract 1. A driver plugin ships the skill
``qa-desktop-driver-<driver>`` whose directory holds the manifest
``qa-desktop-driver.json`` (exactly ``{"contract": 1, "driver", "version",
"entry"}``; ``driver`` matches ``[a-z][a-z0-9-]{0,39}``, ``version``
``[0-9A-Za-z.+-]{1,40}``, ``entry`` is a relative path to a Python 3.11+ stdlib
script inside that directory), its guide ``SKILL.md`` and its code.
``desktop register`` records a manifest from outside the repository for one
run in ``<run-dir>/desktop/drivers.json``; an app whose driver is not
registered gets ``tool-missing`` with detail ``desktop-driver:<driver>``.

The engine runs ``[sys.executable, <entry>, <phase>, …]`` with cwd and ``PWD``
set to the repository root, without ``QA_*`` and ``STORE_*`` variables, stdin
``/dev/null`` and its own session; a timeout or interruption kills the phase's
process group (SIGTERM, then SIGKILL after 5 s). Phases:

- ``check --repo R`` (60 s): exit 0 and print one JSON object,
  ``{"result": null}``, ``{"result": "tool-missing", "detail": …}`` or
  ``{"result": "unsupported", "detail": …}``; anything else is ``host-failed``.
- ``prepare --repo R --cache C`` (300 s): once per run and driver, under
  ``C/.lock``; success writes ``C/.prepared``, failure is ``host-build-failed``.
- ``build --repo R --cache C --package P --out G`` (300 s): builds the app at
  ``G``; failure is ``build-failed``.
- ``run --repo R --cache C --guest G --steps S --out A --width W --height H
  --deadline N -- <args…>`` (120 s, ``N`` = 135): executes the steps and writes
  ``A/result.json``, one PNG per shot and ``A/guest.raw.log``.
  ``handshake-failed`` is retried once; a missing or schema-breaking
  ``result.json`` is ``host-failed``.

``result.json`` holds at least ``result`` (``completed``, ``guest-exited``,
``handshake-failed``, ``host-failed``, ``invalid-script`` or ``timeout``),
``detail`` (string or null), ``step`` (non-negative integer or null),
``exit_code`` (integer or null), ``ticks`` (non-negative integer), ``tps``
(integer of at least -1; -1 ties ticks to rendered frames), ``scale`` (positive
number or null), ``screen`` (two positive integers) and ``shots`` (``{"name",
"file": "<name>.png", "tick"}``, each file present). An intentional quit is
reported only as ``guest-exited`` with ``exit_code`` 0 and detail
``guest terminated itself``.

``run_desktop`` holds the run lock only to validate the config, trust, the
dispatch, the app and its driver. Script expansion and every driver phase run
outside it. The guest's raw output is masked into ``guest.log`` and deleted
before the call returns.
"""
from __future__ import annotations

from collections.abc import Iterator
from collections.abc import Mapping
from contextlib import contextmanager
from contextlib import suppress
import fcntl
import json
import math
import os
from pathlib import Path
import re
import shlex
import shutil
import signal
import subprocess
import sys
import threading
import time
from types import FrameType
from types import TracebackType
from typing import Any

from av_config.errors import ConfigError
from av_config.errors import InvalidConfig
from av_config.files import atomic_write
from qa_engine.common import read_object
from qa_engine.common import write_json
from qa_engine.config import Config
from qa_engine.config import DESKTOP_APP_NAME
from qa_engine.config import DESKTOP_DRIVER_NAME
from qa_engine.config import DESKTOP_MAX_ARG_LENGTH
from qa_engine.config import DESKTOP_MAX_ARGS
from qa_engine.models import Run
from qa_engine.models import StateStop
from qa_engine.runs import check_drift
from qa_engine.runs import open_run
from qa_engine.secrets import SecretSet
from qa_engine.services import require_trust

CONTRACT = 1
CHECK_TIMEOUT = 60
BUILD_TIMEOUT = 300
HOST_TIMEOUT = 120
HOST_DEADLINE_GRACE = 15
KILL_GRACE = 5
DRIVERS_FILE = "drivers.json"
MANIFEST_KEYS = frozenset({"contract", "driver", "version", "entry"})
DRIVER_VERSION = re.compile(r"[0-9A-Za-z.+-]{1,40}\Z")
MAX_STEPS = 500
MAX_TOTAL_TICKS = 36000
MAX_WAIT_TICKS = 36000
MAX_KEY_TICKS = 600
DEFAULT_KEY_TICKS = 2
MAX_TYPE = 200
MAX_SHOTS = 50
MAX_SCROLL = 100
MAX_DETAIL = 300
ACTIONS = ("wait", "key", "hold", "release", "type", "type_env", "move", "click", "scroll", "shot")
MODIFIERS = {"key": {"ticks"}, "click": {"button"}}
BUTTONS = ("left", "right", "middle")
ADVANCING = frozenset({"wait", "key", "type", "type_env", "click", "scroll"})
SHOT_NAME = re.compile(r"[A-Za-z0-9_-]{1,40}\Z")
KEY_NAME = re.compile(r"[A-Za-z][A-Za-z0-9]{0,31}\Z")
ENV_NAME = re.compile(r"QA_[A-Z0-9_]+\Z")
RUN_RESULTS = frozenset({"completed", "guest-exited", "handshake-failed", "host-failed", "invalid-script", "timeout"})
CHECK_RESULTS = ("tool-missing", "unsupported")

JSON = dict[str, Any]


def _script_error(index: int | None, message: str) -> InvalidConfig:
    return InvalidConfig(f"script: step {index}: {message}" if index is not None else f"script: {message}")


def _integer(value: object, low: int, high: int) -> bool:
    return type(value) is int and low <= value <= high


def _pair(value: object) -> tuple[float, float] | None:
    if not isinstance(value, list) or len(value) != 2 or not all(type(item) in (int, float) for item in value):
        return None
    return float(value[0]), float(value[1])


def _step_ticks(step: Mapping[str, object]) -> int:
    """Ticks a validated step advances; ``type_env`` counts its resolved length later."""
    if "wait" in step:
        return int(step["wait"])  # type: ignore[call-overload]
    if "key" in step:
        return int(step.get("ticks", DEFAULT_KEY_TICKS)) + 1  # type: ignore[call-overload]
    if "type" in step:
        return len(str(step["type"]))
    if "type_env" in step or "scroll" in step:
        return 1
    if "click" in step:
        return 2
    return 0


def _validate_step(index: int, step: object, screen: tuple[int, int]) -> str:
    if not isinstance(step, dict):
        raise _script_error(index, "expected an object with one action key")
    actions = [name for name in ACTIONS if name in step]
    if len(actions) != 1:
        raise _script_error(index, f"expected exactly one action key ({', '.join(ACTIONS)})")
    action = actions[0]
    unexpected = sorted(set(step) - {action} - MODIFIERS.get(action, set()))
    if unexpected:
        raise _script_error(index, f"unexpected field {unexpected[0]!r} in a {action} step")
    value = step[action]
    width, height = screen
    if action == "wait" and not _integer(value, 1, MAX_WAIT_TICKS):
        raise _script_error(index, f"wait: expected an integer from 1 to {MAX_WAIT_TICKS}")
    if action in {"key", "hold", "release"} and not (isinstance(value, str) and KEY_NAME.fullmatch(value)):
        raise _script_error(index, f"{action}: expected a KeyboardEvent.code key name")
    if action == "key" and "ticks" in step and not _integer(step["ticks"], 1, MAX_KEY_TICKS):
        raise _script_error(index, f"ticks: expected an integer from 1 to {MAX_KEY_TICKS}")
    if action == "type" and not (isinstance(value, str) and 1 <= len(value) <= MAX_TYPE):
        raise _script_error(index, f"type: expected 1 to {MAX_TYPE} characters")
    if action == "type_env" and not (isinstance(value, str) and ENV_NAME.fullmatch(value)):
        raise _script_error(index, "type_env: expected a QA_<NAME> token name")
    if action in {"move", "click"}:
        point = _pair(value)
        if point is None:
            raise _script_error(index, f"{action}: expected [x, y]")
        if not (0 <= point[0] <= width and 0 <= point[1] <= height):
            raise _script_error(index, f"{action}: point is outside the {width}x{height} screen")
    if action == "click" and "button" in step and step["button"] not in BUTTONS:
        raise _script_error(index, "button: expected left, right or middle")
    if action == "scroll":
        delta = _pair(value)
        if delta is None or not all(-MAX_SCROLL <= item <= MAX_SCROLL for item in delta):
            raise _script_error(index, f"scroll: expected [dx, dy] within -{MAX_SCROLL}..{MAX_SCROLL}")
    if action == "shot" and not (isinstance(value, str) and SHOT_NAME.fullmatch(value)):
        raise _script_error(index, "shot: expected a name matching [A-Za-z0-9_-]{1,40}")
    return action


def validate_script(data: object, screen: tuple[int, int]) -> dict[str, object]:
    """Check a tester's script against the format and limits; raise ``InvalidConfig('script: …')``."""
    if not isinstance(data, dict):
        raise _script_error(None, "expected a JSON object with steps")
    unexpected = sorted(set(data) - {"args", "steps"})
    if unexpected:
        raise _script_error(None, f"unexpected field {unexpected[0]!r}")
    args = data.get("args", [])
    if not isinstance(args, list) or len(args) > DESKTOP_MAX_ARGS or not all(
            isinstance(arg, str) and len(arg) <= DESKTOP_MAX_ARG_LENGTH and "\0" not in arg for arg in args):
        raise _script_error(None, f"args: expected at most {DESKTOP_MAX_ARGS} strings of at most {DESKTOP_MAX_ARG_LENGTH} characters without NUL")
    steps = data.get("steps")
    if not isinstance(steps, list) or not steps:
        raise _script_error(None, "steps: expected a non-empty list")
    if len(steps) > MAX_STEPS:
        raise _script_error(None, f"steps: at most {MAX_STEPS} steps")
    total = 0
    advanced = False
    shots: set[str] = set()
    for index, step in enumerate(steps):
        action = _validate_step(index, step, screen)
        if action == "shot":
            name = step["shot"]
            if not advanced:
                raise _script_error(index, f"shot {name!r} needs an earlier step that advances ticks ({', '.join(sorted(ADVANCING))})")
            if name in shots:
                raise _script_error(index, f"shot name {name!r} is used twice")
            shots.add(name)
            if len(shots) > MAX_SHOTS:
                raise _script_error(index, f"more than {MAX_SHOTS} shots")
        advanced = advanced or action in ADVANCING
        total += _step_ticks(step)
        if total > MAX_TOTAL_TICKS:
            raise _script_error(index, f"the script advances more than {MAX_TOTAL_TICKS} ticks in total")
    return {"args": list(args), "steps": steps}


def desktop_script(run_id: str, repo: Path) -> str:
    """The run helper ``desktop.sh <dispatch> <app> <script-file>``, bound to this run and repository."""
    engine = shlex.quote(str(Path(__file__).resolve().parents[1] / "qa.py"))
    return f'''# Run one DESKTOP script through the engine and the app's registered desktop driver.
[ "$#" -eq 3 ] || exit 2
case "$1" in D[0-9][0-9][0-9]*) ;; *) exit 2 ;; esac
case "$1" in *[!D0-9]*) exit 2 ;; esac
case "$2" in ''|[!A-Za-z_]*|*[!A-Za-z0-9_]*) exit 2 ;; esac
exec python3 {engine} desktop run --run {shlex.quote(run_id)} --dispatch "$1" --target "$2" --script "$3" --repo {shlex.quote(str(repo))}
'''


class _Interrupts:
    """Turn SIGTERM/SIGINT into ``StateStop`` while armed; defer them during cleanup."""

    def __init__(self) -> None:
        self.armed = False
        self.pending = False
        self.previous: dict[int, Any] = {}

    def __enter__(self) -> _Interrupts:
        if threading.current_thread() is threading.main_thread():
            for number in (signal.SIGTERM, signal.SIGINT):
                self.previous[number] = signal.signal(number, self._handle)
            self.armed = True
        return self

    def _handle(self, number: int, frame: FrameType | None) -> None:
        self.pending = True
        if self.armed:
            self.armed = False
            raise StateStop("desktop run interrupted")

    def hold(self) -> None:
        self.armed = False

    def __exit__(self, kind: type[BaseException] | None, error: BaseException | None, trace: TracebackType | None) -> None:
        for number, handler in self.previous.items():
            signal.signal(number, handler)
        if self.pending and error is None:
            raise StateStop("desktop run interrupted")


class _Children:
    """The one driver phase process group currently running, killed with its group on cleanup."""

    def __init__(self, environment: Mapping[str, str]) -> None:
        self.environment = dict(environment)
        self.current: subprocess.Popen[bytes] | None = None

    def run(self, argv: list[str], cwd: Path, log: Path, timeout: float, *, stdout: Path | None = None) -> int | None:
        """Run ``argv`` in its own session; ``None`` when it outlived ``timeout`` and was killed.

        Output goes to ``log``; with ``stdout``, standard output goes to that file and only stderr to ``log``.
        """
        # PWD names cwd: tools that trust an inherited PWD (go does) must not see the caller's directory or a
        # symlinked spelling of the repository (macOS /tmp).
        environment = {**self.environment, "PWD": str(cwd)}
        with log.open("wb") as errors:
            log.chmod(0o600)
            if stdout is None:
                self.current = subprocess.Popen(
                    argv, cwd=cwd, env=environment, stdin=subprocess.DEVNULL, stdout=errors, stderr=subprocess.STDOUT,
                    start_new_session=True,
                )
            else:
                with stdout.open("wb") as output:
                    stdout.chmod(0o600)
                    self.current = subprocess.Popen(
                        argv, cwd=cwd, env=environment, stdin=subprocess.DEVNULL, stdout=output, stderr=errors,
                        start_new_session=True,
                    )
        try:
            return self.current.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            self.stop()
            return None
        finally:
            self.stop()

    def stop(self) -> None:
        process = self.current
        if process is None:
            return
        group = process.pid
        try:
            os.killpg(group, signal.SIGTERM)
        except (ProcessLookupError, PermissionError):
            process.wait()
            self.current = None
            return
        deadline = time.monotonic() + KILL_GRACE
        while time.monotonic() < deadline:
            process.poll()
            try:
                os.killpg(group, 0)
            except (ProcessLookupError, PermissionError):
                break
            time.sleep(0.05)
        else:
            with suppress(ProcessLookupError, PermissionError):
                os.killpg(group, signal.SIGKILL)
        process.wait()
        self.current = None


def _child_environment() -> dict[str, str]:
    return {name: value for name, value in os.environ.items() if not name.startswith(("QA_", "STORE_"))}


def _first_line(text: str, secrets: SecretSet) -> str | None:
    for line in secrets.mask(text).splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            return line[:MAX_DETAIL]
    return None


def _read_log(path: Path) -> str:
    try:
        return path.read_bytes().decode(errors="replace")
    except FileNotFoundError:
        return ""


@contextmanager
def _locked(path: Path) -> Iterator[None]:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    with path.open("a") as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        yield


def _artifacts_directory(results: Path, target: str) -> Path:
    parent = results / "desktop"
    parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    numbers = [int(match.group(1)) for item in parent.iterdir() if (match := re.match(r"(\d{3})-", item.name))]
    number = max(numbers, default=0) + 1
    while True:
        directory = parent / f"{number:03d}-{target}"
        try:
            directory.mkdir(mode=0o700)
        except FileExistsError:
            number += 1
            continue
        directory.chmod(0o700)
        return directory


def _count(value: object, low: int = 0) -> bool:
    return type(value) is int and value >= low


def _valid_shot(shot: object, artifacts: Path) -> bool:
    if not isinstance(shot, dict):
        return False
    name = shot.get("name")
    if not isinstance(name, str) or not SHOT_NAME.fullmatch(name):
        return False
    return shot.get("file") == f"{name}.png" and _count(shot.get("tick")) and (artifacts / f"{name}.png").is_file()


def _host_result(artifacts: Path) -> JSON | None:
    """The current attempt's ``result.json`` when it matches contract 1's schema, else ``None``; never raises."""
    try:
        data = json.loads((artifacts / "result.json").read_text())
    except (OSError, UnicodeError, ValueError, RecursionError):
        return None
    if not isinstance(data, dict):
        return None
    result = data.get("result")
    if not isinstance(result, str) or result not in RUN_RESULTS:
        return None
    if not all(key in data for key in ("detail", "step", "exit_code", "ticks", "tps", "scale", "screen", "shots")):
        return None
    scale = data["scale"]
    screen = data["screen"]
    shots = data["shots"]
    valid = (
        (data["detail"] is None or isinstance(data["detail"], str))
        and (data["step"] is None or _count(data["step"]))
        and (data["exit_code"] is None or type(data["exit_code"]) is int)
        and _count(data["ticks"]) and _count(data["tps"], -1)
        and (scale is None or _positive_number(scale))
        and isinstance(screen, list) and len(screen) == 2 and all(_count(item, 1) for item in screen)
        and isinstance(shots, list) and all(_valid_shot(shot, artifacts) for shot in shots)
    )
    return data if valid else None


def _positive_number(value: object) -> bool:
    if isinstance(value, bool):
        return False
    if isinstance(value, int):
        return value > 0
    return isinstance(value, float) and math.isfinite(value) and value > 0


def _check_result(path: Path) -> tuple[str | None, str | None] | None:
    """``(result, detail)`` from a ``check`` phase's stdout when it follows the contract, else ``None``."""
    try:
        data = json.loads(path.read_text())
    except (OSError, UnicodeError, ValueError, RecursionError):
        return None
    if not isinstance(data, dict) or "result" not in data or not set(data) <= {"result", "detail"}:
        return None
    result = data["result"]
    if result is None:
        return None, None
    detail = data.get("detail")
    if not isinstance(result, str) or result not in CHECK_RESULTS or not isinstance(detail, str):
        return None
    return result, detail


def register_driver(run: Run, manifest: Path) -> dict[str, object]:
    """Record a desktop driver manifest from outside the repository for this run."""
    path = manifest.expanduser().resolve()
    if path.is_relative_to(run.repo):
        raise InvalidConfig("desktop driver manifest must be outside the repository")
    try:
        data = json.loads(path.read_text())
    except (OSError, UnicodeError, ValueError, RecursionError) as error:
        raise InvalidConfig("desktop driver manifest is not a readable JSON object") from error
    if not isinstance(data, dict):
        raise InvalidConfig("desktop driver manifest is not a readable JSON object")
    if set(data) != MANIFEST_KEYS:
        raise InvalidConfig("desktop driver manifest needs exactly the keys contract, driver, version and entry")
    contract = data["contract"]
    if not (type(contract) is int and contract == CONTRACT):
        raise InvalidConfig(f"desktop driver contract {contract!r} is not supported; this qa engine supports contract {CONTRACT}")
    name = data["driver"]
    if not isinstance(name, str) or not DESKTOP_DRIVER_NAME.fullmatch(name):
        raise InvalidConfig("desktop driver manifest has an invalid driver name")
    version = data["version"]
    if not isinstance(version, str) or not DRIVER_VERSION.fullmatch(version):
        raise InvalidConfig("desktop driver manifest has an invalid version")
    entry = data["entry"]
    base = path.parent
    target: Path | None = None
    if isinstance(entry, str) and entry and "\0" not in entry and not Path(entry).is_absolute() and ".." not in Path(entry).parts:
        target = (base / entry).resolve()
    if target is None or not target.is_relative_to(base) or not target.is_file():
        raise InvalidConfig("desktop driver entry must be a relative path to a file inside the manifest directory")
    directory = run.directory / "desktop"
    directory.mkdir(mode=0o700, exist_ok=True)
    registry = directory / DRIVERS_FILE
    drivers = read_object(registry)
    current = drivers.get(name)
    if isinstance(current, dict) and current.get("manifest") != str(path):
        raise StateStop(f"desktop driver {name} is already registered from another manifest")
    drivers[name] = {"manifest": str(path), "entry": str(target), "version": version}
    write_json(registry, drivers, 0o600)
    return {"driver": name, "version": version, "contract": CONTRACT, "manifest": str(path)}


def _clear_attempt(artifacts: Path) -> None:
    for name in ("result.json", "guest.raw.log"):
        (artifacts / name).unlink(missing_ok=True)
    for shot in artifacts.glob("*.png"):
        shot.unlink(missing_ok=True)


def run_desktop(
    repo: Path, run_id: str, dispatch: str, target: str, script_path: Path, *,
    host_timeout: float = HOST_TIMEOUT, build_timeout: float = BUILD_TIMEOUT,
) -> dict[str, object]:
    """Run the script through the app's registered driver: check, prepare once, build, then run."""
    started = time.monotonic()
    repo = repo.resolve()
    with open_run(repo, run_id) as run:
        config = Config(repo)
        check_drift(run, config)
        require_trust(config)
        record = run.state["dispatches"].get(dispatch)
        if record is None or record["kind"] != "tester":
            raise StateStop("unknown tester dispatch")
        if record["ingested"]:
            raise StateStop("dispatch already ingested")
        if record["section"] != "DESKTOP":
            raise StateStop("dispatch is not a DESKTOP tester dispatch")
        if target not in config.desktop:
            raise StateStop(f"unknown desktop app: {target}" if DESKTOP_APP_NAME.fullmatch(target) else "unknown desktop app")
        app = config.desktop[target]
        tag = str(record["tag"])
        directory = run.directory
        secrets = SecretSet(directory, run.record["config"], config.data)
        driver_name = str(app["driver"])
        driver = read_object(directory / "desktop" / DRIVERS_FILE).get(driver_name)

    screen_value = app["screen"]
    assert isinstance(screen_value, list)
    screen = (int(screen_value[0]), int(screen_value[1]))
    try:
        original = script_path.read_bytes()
        data = json.loads(original)
    except FileNotFoundError as error:
        raise _script_error(None, "script file not found") from error
    except (OSError, UnicodeError, ValueError) as error:
        raise _script_error(None, "not a readable JSON file") from error
    script = validate_script(data, screen)
    steps, sensitive = _expand(script["steps"], tag, directory)

    output: JSON = {
        "result": None, "detail": None, "step": None, "exit_code": None, "ticks": 0, "tps": 0, "scale": None,
        "screen": list(screen), "shots": [], "log": None, "build_log": None, "artifacts": None, "attempts": 0,
        "duration_ms": 0,
    }

    def finish(result: str, detail: str | None = None) -> JSON:
        output["result"] = result
        output["detail"] = None if detail is None else _first_line(detail, secrets)
        output["duration_ms"] = int((time.monotonic() - started) * 1000)
        return output

    if not isinstance(driver, dict) or not isinstance(driver.get("entry"), str):
        return finish("tool-missing", f"desktop-driver:{driver_name}")

    artifacts = _artifacts_directory(directory / "results" / dispatch, target)
    output["artifacts"] = str(artifacts)
    atomic_write(artifacts / "script.json", original, 0o600)
    steps_path = artifacts / "steps.json"
    write_json(steps_path, {"steps": steps}, 0o600)
    cache = directory / "desktop" / driver_name
    cache.mkdir(mode=0o700, parents=True, exist_ok=True)
    entry = [sys.executable, str(driver["entry"])]
    common = ["--repo", str(repo), "--cache", str(cache)]

    children = _Children(_child_environment())
    with _Interrupts() as interrupts:
        try:
            check_output = artifacts / "check.json"
            code = children.run([*entry, "check", "--repo", str(repo)], repo, artifacts / "check.log", CHECK_TIMEOUT, stdout=check_output)
            verdict = _check_result(check_output) if code == 0 else None
            if verdict is None:
                return finish("host-failed", "desktop driver check failed")
            if verdict[0] is not None:
                return finish(verdict[0], verdict[1])
            failure = _prepare(entry, common, repo, cache, children, build_timeout, secrets)
            if failure is not None:
                output["build_log"] = str(cache / "prepare.log")
                return finish("host-build-failed", failure)
            guest = artifacts / "guest"
            build_log = artifacts / "build.log"
            code = children.run([*entry, "build", *common, "--package", str(app["package"]), "--out", str(guest)], repo, build_log, build_timeout)
            output["build_log"] = str(build_log)
            if code != 0:
                reason = f"guest build timed out after {build_timeout:g}s" if code is None else _first_line(_read_log(build_log), secrets)
                return finish("build-failed", reason or f"guest build exited {code}")
            argv = [
                *entry, "run", *common, "--guest", str(guest), "--steps", str(steps_path), "--out", str(artifacts),
                "--width", str(screen[0]), "--height", str(screen[1]),
                "--deadline", str(math.ceil(host_timeout + HOST_DEADLINE_GRACE)),
                "--", *[str(arg) for arg in app["args"]], *script["args"],
            ]
            result: JSON | None = None
            for attempt in (1, 2):
                _clear_attempt(artifacts)
                output["attempts"] = attempt
                code = children.run(argv, repo, artifacts / "host.log", host_timeout)
                if code is None:
                    return finish("timeout", f"host did not finish within {host_timeout:g}s")
                if not (artifacts / "result.json").exists():
                    return finish("host-failed", f"host exited {code} without result.json")
                result = _host_result(artifacts)
                if result is None:
                    return finish("host-failed", f"host exited {code} with an invalid result.json")
                if result["result"] != "handshake-failed":
                    break
            assert result is not None
            for key in ("step", "exit_code", "scale", "ticks", "tps"):
                output[key] = result[key]
            output["shots"] = [
                {"name": shot["name"], "path": str(artifacts / shot["file"]), "tick": shot["tick"], "sensitive": shot["name"] in sensitive}
                for shot in result["shots"]
            ]
            return finish(str(result["result"]), result["detail"])
        finally:
            interrupts.hold()
            children.stop()
            _mask_guest_output(artifacts, secrets, output)


def _expand(steps: list[Any], tag: str, directory: Path) -> tuple[list[JSON], set[str]]:
    """Resolve ``type_env`` steps for the host's private copy and name the shots taken after a secret."""
    exposed: dict[str, Any] | None = None
    expanded: list[JSON] = []
    sensitive: set[str] = set()
    secret_typed = False
    total = 0
    for index, step in enumerate(steps):
        if "type_env" in step:
            name = step["type_env"]
            if name == "QA_TAG":
                value = tag
            else:
                exposed = read_object(directory / "secrets.json") if exposed is None else exposed
                value = exposed.get(name)
                if not isinstance(value, str) or not value:
                    raise _script_error(None, f"type_env {name} is not exposed")
                secret_typed = True
            if len(value) > MAX_TYPE:
                raise _script_error(index, f"type_env {name} is longer than {MAX_TYPE} characters")
            step = {"type": value}
        elif "shot" in step and secret_typed:
            sensitive.add(step["shot"])
        total += _step_ticks(step)
        if total > MAX_TOTAL_TICKS:
            raise _script_error(index, f"the script advances more than {MAX_TOTAL_TICKS} ticks in total")
        expanded.append(step)
    return expanded, sensitive


def _prepare(
    entry: list[str], common: list[str], repo: Path, cache: Path, children: _Children, timeout: float, secrets: SecretSet,
) -> str | None:
    """Run the driver's ``prepare`` once per run under the cache lock; the failure detail, or ``None``."""
    marker = cache / ".prepared"
    log = cache / "prepare.log"
    with _locked(cache / ".lock"):
        if marker.is_file():
            return None
        code = children.run([*entry, "prepare", *common], repo, log, timeout)
        if code is None:
            return f"driver prepare timed out after {timeout:g}s"
        if code != 0:
            return _first_line(_read_log(log), secrets) or f"driver prepare exited {code}"
        atomic_write(marker, b"", 0o600)
        return None


def _mask_guest_output(artifacts: Path, secrets: SecretSet, output: JSON) -> None:
    raw = artifacts / "guest.raw.log"
    try:
        if raw.exists():
            atomic_write(artifacts / "guest.log", secrets.mask(_read_log(raw)).encode(), 0o600)
            output["log"] = str(artifacts / "guest.log")
    except (OSError, ConfigError):
        output["log"] = None
    finally:
        raw.unlink(missing_ok=True)
        guest = artifacts / "guest"
        if guest.is_dir() and not guest.is_symlink():
            shutil.rmtree(guest, ignore_errors=True)
        else:
            guest.unlink(missing_ok=True)
