"""Pinned run lifecycle and locked mutations of the durable sidecar."""
from __future__ import annotations

from collections.abc import Iterator
from contextlib import contextmanager
from dataclasses import dataclass
import fcntl
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import stat
import time
from typing import cast

from av_config.errors import ConfigError
from av_config.errors import InvalidConfig
from av_config.origins import parse_origin
from av_config.sources import mask
from av_config.trust import canonical_hash
from qa_engine.common import format_origin
from qa_engine.common import write_json
from qa_engine.config import Config
from qa_engine.config import VALUE_SOURCE_KEYS
from qa_engine.files import _load_json
from qa_engine.files import _plan_hash
from qa_engine.git import _dirty
from qa_engine.git import _fingerprint
from qa_engine.iterations import iteration_close
from qa_engine.locks import LOCK_GRACE_MINUTES
from qa_engine.locks import OriginLocks
from qa_engine.locks import default_lock_directory
from qa_engine.models import LIMITS
from qa_engine.models import Run
from qa_engine.models import StateStop
from qa_engine.plan import Plan
from qa_engine.plan import parse_plan
from qa_engine.schema import Fingerprints
from qa_engine.schema import JSON
from qa_engine.schema import LoopEnd
from qa_engine.schema import RunRecord
from qa_engine.schema import SidecarState
from qa_engine.schema import _conforms
from qa_engine.secrets import SecretSet
from qa_engine.sidecar import SidecarContext
from qa_engine.sidecar import _prepare_sidecar
from qa_engine.sidecar import _topic
from qa_engine.stores import store_lock_key

RUN_ID = re.compile(r"[0-9a-f]{8}\Z")
RUN_DIRECTORY = re.compile(r"qa-run-[0-9a-f]{8}\Z")
STOP_REASONS = frozenset({"user-abort", "config-drift", "plan-changed", "cleanup-error", "other"})
STALE_SECONDS = 24 * 3600


@dataclass(frozen=True)
class RunStartOptions:
    """Optional takeover, provenance and dirty-baseline choices for run start."""

    takeover: str | None = None
    generated: bool = False
    baseline_run: str | None = None
    baseline_file: Path | None = None


def effective_config(config: Config) -> JSON:
    """Pin only QA's environment tables and QA config, with defaults applied."""
    env = {name: config.env[name] for name in ("targets", "services", "secrets", "values", "stores") if name in config.env}
    return {"env": env, "qa": {**config.qa, **config.policy}}


def check_drift(run: Run, config: Config) -> None:
    """Refuse to act on a config other than the one ``run start`` recorded."""
    if config.errors or canonical_hash(effective_config(config)) != run.record["config_hash"]:
        raise StateStop("config changed during run")


def run_directory(run_id: str) -> Path:
    if not RUN_ID.fullmatch(run_id):
        raise InvalidConfig("invalid run id")
    return _tmp_root() / f"qa-run-{run_id}"


def start_run(config: Config, plan_path: Path, options: RunStartOptions) -> JSON:
    """Create a run and its sidecar, rolling back locks and directory on failure."""
    if config.errors:
        raise InvalidConfig("invalid configuration; run the config subcommand for its errors")
    if config.state != "ok":
        raise StateStop("no QA configuration in .av/config.toml")
    if config.trust not in {"trusted", "not-required"}:
        raise StateStop("trust required")
    if options.takeover is not None and not RUN_ID.fullmatch(options.takeover):
        raise InvalidConfig("invalid run id")

    repo = config.repo
    plan_path = plan_path.resolve()
    plan_hash = _plan_hash(plan_path)
    if plan_hash is None:
        raise ConfigError("plan is not readable")
    plan = parse_plan(plan_path)
    effective = effective_config(config)
    pre_loop = _restart_baseline(repo, plan, options.baseline_run) if options.baseline_run is not None else None
    if options.baseline_file is not None:
        names = _load_json(options.baseline_file)
        if not isinstance(names, list) or any(
            not isinstance(name, str) or not name or Path(name).is_absolute() or ".." in Path(name).parts
            for name in names
        ):
            raise InvalidConfig("baseline file must contain a JSON array of repository-relative paths")
        pre_loop = {name: _fingerprint(repo / name) for name in names}
    origins = sorted({format_origin(parse_origin(url, origin_only=True)) for url in config.targets.values()}
                     | {store_lock_key(name, cast(dict[str, object], store), repo) for name, store in config.stores.items()})
    now = time.time()
    tmp = _tmp_root()
    _remove_stale(tmp, repo, now)
    locks = OriginLocks(config.store.path.parent / "qa-locks")
    run_id, directory = _create_run_directory(tmp)
    started = False

    try:
        holder = {
            "run_id": run_id, "started": now, "repo": str(repo), "dir": str(directory),
            "limit_minutes": LIMITS["minutes"] + LOCK_GRACE_MINUTES,
        }
        for displaced in locks.acquire(origins, holder, now, options.takeover):
            _remove_run_directory(displaced)
        start_dirty = _dirty(repo)
        if pre_loop is None:
            pre_loop = start_dirty
        sidecar_context = SidecarContext(
            plan_sha256=plan_hash, run_id=run_id, pre_loop=pre_loop, generated=options.generated,
        )
        idempotency, sidecar, report, state = _prepare_sidecar(repo, plan, sidecar_context)
        record: RunRecord = {
            "run_id": run_id, "repo": str(repo), "plan": str(plan_path), "plan_sha256": plan_hash,
            "started": now, "sidecar": str(sidecar), "report": str(report),
            "config": cast(JSON, mask(effective, VALUE_SOURCE_KEYS)),
            "config_hash": canonical_hash(effective), "trust_hash": config.trust_hash, "origins": origins,
            "locks": str(locks.directory), "pre_loop": pre_loop,
            "bootstrap_dirty": sorted((set(start_dirty) - set(pre_loop)) & {".av/config.toml", ".gitignore"}),
        }
        write_json(directory / "run.json", record, 0o600)
        (directory / "results").mkdir(mode=0o700)
        write_json(sidecar, state)
        started = True
    finally:
        if not started:
            try:
                locks.release(run_id)
            finally:
                shutil.rmtree(directory, ignore_errors=True)

    return {"run": run_id, "dir": str(directory), "sidecar": str(sidecar), "report": str(report), "idempotency": idempotency}


def end_run(repo: Path, run_id: str) -> JSON:
    """Release this run's locks and delete its directory; never compares the config."""
    directory = run_directory(run_id)
    record = _load_json(directory / "run.json") if _owned_directory(directory) else None
    if isinstance(record, dict) and record.get("repo") != str(repo):
        raise StateStop("run belongs to another repository")
    recorded = record.get("locks") if isinstance(record, dict) else None
    locks = OriginLocks(Path(recorded) if isinstance(recorded, str) else default_lock_directory())
    released = locks.release(run_id)
    _remove_run_directory(directory)

    return {"released": released}


def _restart_baseline(repo: Path, plan: Plan, run_id: str) -> Fingerprints:
    """Read the ended pass's fingerprints from its durable sidecar, not its deleted directory."""
    if not RUN_ID.fullmatch(run_id):
        raise InvalidConfig("invalid baseline run id")
    path = repo / "docs/testing/reports" / f"{_topic(plan.path)}-loop-state.json"
    stored = _load_json(path)
    if not isinstance(stored, dict) or stored.get("run_id") != run_id:
        raise StateStop("baseline run is unavailable for this plan")
    baseline = stored.get("pre_loop")
    if not _conforms(baseline, Fingerprints):
        raise StateStop("baseline run has no recorded dirty fingerprints")

    return baseline


def stop_run(run: Run, reason: str, detail: str | None = None) -> LoopEnd:
    """Close pending fix work and record a sanitized explicit stop, without config drift checks."""
    if reason not in STOP_REASONS:
        raise InvalidConfig("invalid stop reason")
    if run.state["open_iteration"] is not None:
        iteration_close(run, decide=False)
    end = run.state["loop_end"]
    if end is not None and end["decision"] == "stop":
        return end
    sanitized = detail or ""
    if sanitized:
        sanitized = SecretSet(run.directory, run.record["config"], Config(run.repo).data).mask(sanitized)
        sanitized = " ".join(sanitized.split())
    stopped: LoopEnd = {"decision": "stop", "reason": reason, "detail": sanitized}
    run.state["loop_end"] = stopped

    return stopped


@contextmanager
def open_run(repo: Path, run_id: str, *, close_iteration: bool = False) -> Iterator[Run]:
    """Load locked state; exit closure persists even if the subsequent operation fails."""
    directory = run_directory(run_id)
    if not _owned_directory(directory):
        raise StateStop("unknown run; start one with run start")
    with (directory / "state.lock").open("a") as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        record = _load_json(directory / "run.json")
        if not isinstance(record, dict) or record.get("repo") != str(repo) or record.get("run_id") != run_id:
            raise StateStop("run belongs to another repository")
        if not _conforms(record, RunRecord):
            raise StateStop("the run record is invalid")
        sidecar = Path(record["sidecar"])
        state = _load_json(sidecar)
        if not _conforms(state, SidecarState):
            raise StateStop("the sidecar is missing or invalid")
        if state["run_id"] != run_id:
            raise StateStop("the sidecar belongs to another run")
        run = Run(repo, run_id, directory, record, state)
        if close_iteration and state["open_iteration"] is not None:
            iteration_close(run, decide=False)
            write_json(sidecar, state)
        before = json.dumps(state, sort_keys=True)
        yield run
        if json.dumps(state, sort_keys=True) != before:
            write_json(sidecar, state)


def _tmp_root() -> Path:
    return Path(os.environ.get("TMPDIR") or "/tmp")


def _create_run_directory(tmp: Path) -> tuple[str, Path]:
    for _ in range(8):
        run_id = secrets.token_hex(4)
        directory = tmp / f"qa-run-{run_id}"
        try:
            directory.mkdir(mode=0o700)
        except FileExistsError:
            continue
        directory.chmod(0o700)
        return run_id, directory
    raise ConfigError("cannot create a run directory")


def _owned_directory(directory: Path) -> bool:
    try:
        info = directory.lstat()
    except FileNotFoundError:
        return False
    return stat.S_ISDIR(info.st_mode) and info.st_uid == os.getuid()


def _remove_run_directory(directory: Path) -> None:
    if RUN_DIRECTORY.fullmatch(directory.name) and _owned_directory(directory):
        shutil.rmtree(directory)


def _remove_stale(tmp: Path, repo: Path, now: float) -> None:
    """Best-effort removal of this repository's run directories older than 24 h."""
    for directory in tmp.glob("qa-run-*"):
        if not RUN_DIRECTORY.fullmatch(directory.name) or not _owned_directory(directory):
            continue
        try:
            record = json.loads((directory / "run.json").read_text())
        except (OSError, ValueError, UnicodeError):
            continue
        if not isinstance(record, dict) or record.get("repo") != str(repo):
            continue
        started = record.get("started")
        if isinstance(started, (int, float)) and now - started > STALE_SECONDS:
            shutil.rmtree(directory, ignore_errors=True)


