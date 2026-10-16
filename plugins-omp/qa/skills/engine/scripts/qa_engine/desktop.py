"""Run DESKTOP scripts headless through the Ebitengine ``exp/vmhost`` host driver.

``run_desktop`` holds the run lock only to validate the config, trust, the
dispatch and the app. Script expansion, both builds and the app run outside
it. Every build and host process runs in its own process group with ``QA_*``
and ``STORE_*`` variables removed, and is killed with its group on every exit
path, interruptions included. The guest's raw output is masked into
``guest.log`` and deleted before the call returns.
"""
from __future__ import annotations

from collections.abc import Iterator
from collections.abc import Mapping
from contextlib import contextmanager
from contextlib import suppress
import fcntl
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import signal
import subprocess
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
from qa_engine.config import DESKTOP_MAX_ARG_LENGTH
from qa_engine.config import DESKTOP_MAX_ARGS
from qa_engine.models import StateStop
from qa_engine.runs import check_drift
from qa_engine.runs import open_run
from qa_engine.secrets import SecretSet
from qa_engine.services import require_trust

HOST_DIR = ".av-qa-ebitengine-host"
HOST_SOURCE = Path(__file__).resolve().parents[2] / "drivers" / "ebitengine" / "main.go"
BUILD_TIMEOUT = 300
HOST_TIMEOUT = 120
HOST_DEADLINE_GRACE = 15
KILL_GRACE = 5
EBITENGINE_MODULE = "github.com/hajimehoshi/ebiten/v2"
EBITENGINE_MINIMUM = (2, 10, 5)
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
RESULTS = frozenset({
    "completed", "guest-exited", "build-failed", "host-build-failed", "handshake-failed", "host-failed",
    "invalid-script", "timeout", "tool-missing", "unsupported",
})

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
        raise _script_error(index, f"{action}: expected an ebiten.Key name")
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


def _go_mod_entries(text: str) -> Iterator[tuple[str, list[str]]]:
    """Yield ``(verb, fields)`` for every directive line, inside or outside ``verb (…)`` blocks."""
    block: str | None = None
    for raw in text.splitlines():
        line = raw.split("//", 1)[0].strip()
        if not line:
            continue
        if block is not None:
            if line == ")":
                block = None
            else:
                yield block, line.split()
            continue
        verb, *rest = line.split(None, 1)
        if rest == ["("]:
            block = verb
        elif rest:
            yield verb, rest[0].split()


def ebitengine_requirement(repo: Path) -> str | None:
    """``None`` when the root module may run under ``exp/vmhost``, else the ``unsupported`` detail.

    Reads ``go.mod`` as text only: no ``go`` command, module cache or network.
    """
    try:
        text = (repo / "go.mod").read_text()
    except FileNotFoundError:
        return "no go.mod at the repository root"
    except (OSError, UnicodeError):
        return "go.mod is not readable"
    version: str | None = None
    replaced = False
    for verb, fields in _go_mod_entries(text):
        if not fields or fields[0].strip('"') != EBITENGINE_MODULE:
            continue
        if verb == "replace":
            replaced = True
        elif verb == "require" and len(fields) >= 2:
            version = fields[1]
    if version is None:
        return f"go.mod does not require {EBITENGINE_MODULE}"
    if replaced:
        return None
    parsed = re.match(r"v(\d+)\.(\d+)\.(\d+)", version)
    if parsed and tuple(int(part) for part in parsed.groups()) >= EBITENGINE_MINIMUM:
        return None
    minimum = ".".join(str(part) for part in EBITENGINE_MINIMUM)
    return f"go.mod requires {EBITENGINE_MODULE} {version}; the QA desktop driver supports v{minimum} or later"


def ebitengine_vmhost_available(repo: Path) -> bool:
    return shutil.which("go") is not None and ebitengine_requirement(repo) is None


def desktop_script(run_id: str, repo: Path) -> str:
    """The run helper ``desktop.sh <dispatch> <app> <script-file>``, bound to this run and repository."""
    engine = shlex.quote(str(Path(__file__).resolve().parents[1] / "qa.py"))
    return f'''# Run one DESKTOP script through the engine's Ebitengine driver.
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
    """The one build or host process group currently running, killed with its group on cleanup."""

    def __init__(self, environment: Mapping[str, str]) -> None:
        self.environment = dict(environment)
        self.current: subprocess.Popen[bytes] | None = None

    def run(self, argv: list[str], cwd: Path, log: Path, timeout: float) -> int | None:
        """Run ``argv`` in its own session; ``None`` when it outlived ``timeout`` and was killed."""
        with log.open("wb") as output:
            log.chmod(0o600)
            # Go trusts an inherited PWD naming the same directory, so a symlinked path (macOS /tmp) would
            # not match the overlay's resolved repository path.
            self.current = subprocess.Popen(
                argv, cwd=cwd, env={**self.environment, "PWD": str(cwd)}, stdin=subprocess.DEVNULL, stdout=output,
                stderr=subprocess.STDOUT, start_new_session=True,
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


def _host_result(artifacts: Path) -> JSON | None:
    """The current attempt's ``result.json`` when it is well formed, else ``None``."""
    try:
        data = json.loads((artifacts / "result.json").read_text())
    except (OSError, UnicodeError, ValueError):
        return None
    if not isinstance(data, dict) or data.get("result") not in RESULTS:
        return None
    shots = data.get("shots", [])
    if not isinstance(shots, list) or not all(
            isinstance(shot, dict) and isinstance(shot.get("name"), str) and SHOT_NAME.fullmatch(shot["name"])
            and shot.get("file") == f"{shot['name']}.png" and type(shot.get("tick")) is int for shot in shots):
        return None
    return data


def _clear_attempt(artifacts: Path) -> None:
    for name in ("result.json", "guest.raw.log"):
        (artifacts / name).unlink(missing_ok=True)
    for shot in artifacts.glob("*.png"):
        shot.unlink(missing_ok=True)


def run_desktop(
    repo: Path, run_id: str, dispatch: str, target: str, script_path: Path, *,
    host_timeout: float = HOST_TIMEOUT, build_timeout: float = BUILD_TIMEOUT,
) -> dict[str, object]:
    """Build the app's guest and the cached host, run the script and return the driver result."""
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

    if shutil.which("go") is None:
        return finish("tool-missing", "go")
    unsupported = ebitengine_requirement(repo)
    if unsupported is not None:
        return finish("unsupported", unsupported)

    artifacts = _artifacts_directory(directory / "results" / dispatch, target)
    output["artifacts"] = str(artifacts)
    atomic_write(artifacts / "script.json", original, 0o600)
    steps_path = artifacts / "steps.json"
    write_json(steps_path, {"steps": steps}, 0o600)

    children = _Children(_child_environment())
    with _Interrupts() as interrupts:
        try:
            host, failure = _host(repo, directory / "desktop", children, build_timeout, secrets)
            if host is None:
                return finish("host-build-failed", failure)
            guest = artifacts / "guest"
            build_log = artifacts / "build.log"
            code = children.run(["go", "build", "-tags", "ebitenginevmguest", "-o", str(guest), str(app["package"])], repo, build_log, build_timeout)
            if code != 0:
                output["build_log"] = str(build_log)
                reason = f"guest build timed out after {build_timeout:g}s" if code is None else _first_line(_read_log(build_log), secrets)
                return finish("build-failed", reason or f"guest build exited {code}")
            output["build_log"] = str(build_log)
            argv = [
                str(host), "-guest", str(guest), "-script", str(steps_path), "-out", str(artifacts),
                "-w", str(screen[0]), "-h", str(screen[1]), "-deadline", f"{host_timeout + HOST_DEADLINE_GRACE:g}s",
                "--", *[str(arg) for arg in app["args"]], *script["args"],
            ]
            result: JSON | None = None
            for attempt in (1, 2):
                _clear_attempt(artifacts)
                output["attempts"] = attempt
                code = children.run(argv, repo, artifacts / "host.log", host_timeout)
                if code is None:
                    return finish("timeout", f"host did not finish within {host_timeout:g}s")
                result = _host_result(artifacts)
                if result is None:
                    return finish("host-failed", f"host exited {code} without result.json")
                if result["result"] != "handshake-failed":
                    break
            assert result is not None
            for key in ("step", "exit_code", "scale"):
                output[key] = result.get(key)
            output["ticks"] = result.get("ticks", 0)
            output["tps"] = result.get("tps", 0)
            output["shots"] = [
                {"name": shot["name"], "path": str(artifacts / shot["file"]), "tick": shot["tick"], "sensitive": shot["name"] in sensitive}
                for shot in result.get("shots", [])
            ]
            detail = result.get("detail")
            return finish(str(result["result"]), detail if isinstance(detail, str) else None)
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


def _host(repo: Path, cache: Path, children: _Children, timeout: float, secrets: SecretSet) -> tuple[Path | None, str | None]:
    """The run's cached host binary, built once under the build lock; ``(None, detail)`` on failure."""
    host = cache / "host"
    with _locked(cache / "build.lock"):
        if host.is_file() and os.access(host, os.X_OK):
            return host, None
        if (repo / HOST_DIR).exists():
            return None, f"reserved directory {HOST_DIR} exists"
        overlay = cache / "overlay.json"
        write_json(overlay, {"Replace": {str(repo / HOST_DIR / "main.go"): str(HOST_SOURCE)}}, 0o600)
        building = cache / "host.partial"
        building.unlink(missing_ok=True)
        log = cache / "host-build.log"
        code = children.run(["go", "build", "-overlay", str(overlay), "-o", str(building), f"./{HOST_DIR}"], repo, log, timeout)
        if code is None:
            building.unlink(missing_ok=True)
            return None, f"host build timed out after {timeout:g}s"
        if code != 0 or not building.is_file():
            building.unlink(missing_ok=True)
            return None, _first_line(_read_log(log), secrets) or f"host build exited {code}"
        os.replace(building, host)
        return host, None


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
        (artifacts / "guest").unlink(missing_ok=True)
