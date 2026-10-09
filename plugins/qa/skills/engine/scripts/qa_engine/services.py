"""Trusted source resolution, masked process logs and run-bound services."""
from __future__ import annotations

from collections.abc import Mapping
from contextlib import ExitStack
import os
import re
import signal
import subprocess
from tempfile import TemporaryFile
from typing import TYPE_CHECKING
from typing import Any
from typing import cast
from urllib.request import Request

from av_config.errors import ConfigError
from av_config.files import atomic_write
from qa_engine.common import write_json
from qa_engine.config import Config
from qa_engine.config import mapping
from qa_engine.recipes import PLACEHOLDER
from qa_engine.recipes import http_request
from qa_engine.secrets import SecretSet

if TYPE_CHECKING:
    from qa_engine.models import Run


def require_trust(config: Config) -> None:
    if config.errors or config.state != "ok" or config.trust not in {"trusted", "not-required"}:
        raise ConfigError("trust required")


class Runtime:
    """Resolve only used sources and delay logs until outputs can be masked."""

    def __init__(self, run: Run, config: Config, *, cleanup: bool = False) -> None:
        if not cleanup:
            require_trust(config)
        self.run = run
        self.config = config
        self.cache: dict[str, str] = {}
        self.secrets = SecretSet(run.directory, mapping(run.record.get("config")), config.data, minimum_length=4)
        self.logs: list[tuple[str, str]] = []

    def __enter__(self) -> Runtime:
        return self

    def __exit__(self, exc_type: object, exc: object, traceback: object) -> None:
        if not self.logs:
            return
        path = self.run.directory / "engine.log"
        previous = path.read_text() if path.exists() else ""
        entries: list[str] = []
        for label, output in self.logs:
            output = self.secrets.mask(output)
            entries.append(f"{label}: {output[-2048:]}\n")
        text = "".join(entries)
        atomic_write(path, (previous + text).encode(), 0o600)

    def log_command(self, label: str, code: int, stdout: str, stderr: str) -> None:
        """Keep successful output out of logs; mask failures before truncation."""
        self.logs.append((label, stdout + stderr if code else f"exit 0, {len(stdout.splitlines())} lines"))

    def resolve(self, source: str, key: str) -> str:
        if key in self.cache:
            return self.cache[key]
        require_trust(self.config)
        value = self.config.shared.resolve(source, key, trusted=True, execute=self._run_source)
        self.cache[key] = value
        self.secrets.remember(value)
        return value

    def _run_source(self, command: str, key: str) -> str:
        """Execute a source with inherited inputs and masked engine-log capture."""
        environ = dict(os.environ)
        code, stdout, stderr = self.shell(command, environ, key, timeout=30)
        if code:
            self.logs.append((key, "***"))
            raise ConfigError(f"{key}: command source failed")
        self.log_command(key, code, stdout, stderr)
        return stdout

    def named(self, kind: str, name: str) -> str:
        table = self.config.values if kind == "value" else mapping(self.config.env.get("secrets"))
        key = f"env.{'values' if kind == 'value' else 'secrets'}.{name}"
        source = table.get(name)
        if not isinstance(source, str):
            raise ConfigError(f"{key}: source unavailable")
        return self.resolve(source, key)

    def substitute(self, value: object, identity: Mapping[str, object]) -> Any:
        if isinstance(value, str):
            def replacement(match: re.Match[str]) -> str:
                name = match.group(1)
                if name.startswith("secret."):
                    return self.named("secret", name[7:])
                if name.startswith("value."):
                    return self.named("value", name[6:])
                result = identity.get(name)
                if result is None or result == "":
                    raise ConfigError(f"recipe placeholder {name}: required output missing")
                return str(result)
            return PLACEHOLDER.sub(replacement, value)
        if isinstance(value, dict):
            return {key: self.substitute(item, identity) for key, item in value.items()}
        if isinstance(value, list):
            return [self.substitute(item, identity) for item in value]
        return value

    def shell(self, command: str, environ: Mapping[str, str], label: str, *,
              timeout: float, file_output: bool = False) -> tuple[int, str, str]:
        """Bound source calls separately; service children must not hold pipes open."""
        with ExitStack() as stack:
            output = stack.enter_context(TemporaryFile(dir=self.run.directory)) if file_output else None
            try:
                process = subprocess.Popen(["/bin/sh", "-c", command], cwd=self.run.repo, env=dict(environ),
                                           stdout=output if output is not None else subprocess.PIPE,
                                           stderr=subprocess.STDOUT if output is not None else subprocess.PIPE,
                                           start_new_session=True)
            except OSError as error:
                raise ConfigError(f"{label}: command unavailable") from error
            try:
                stdout, stderr = process.communicate(timeout=timeout)
            except subprocess.TimeoutExpired as error:
                os.killpg(process.pid, signal.SIGKILL)
                process.communicate()
                self.logs.append((label, "***"))
                raise ConfigError(f"{label}: command timed out") from error
            if output is not None:
                output.seek(0)
                # Mask complete values in __exit__ before taking the log's tail.
                stdout, stderr = output.read(), b""
            try:
                return process.returncode, (stdout or b"").decode(), (stderr or b"").decode()
            except UnicodeError as error:
                raise ConfigError(f"{label}: invalid command output") from error


def services(run: Run, config: Config, operation: str) -> dict[str, object]:
    """Run checks/bring-up against the pinned config; down ignores current drift."""
    if operation != "down":
        require_trust(config)
    recorded = run.record["config"]["env"]
    settings = mapping(recorded.get("services"))
    if operation == "check":
        probes: list[dict[str, object]] = []
        for probe in cast(list[str], settings.get("health", [])):
            target, path = probe.split(":", 1)
            try:
                status = http_request(Request(recorded["targets"][target] + path))
            except ConfigError:
                status = None
            probes.append({"target": target, "path": path, "status": status})
        return {"up": all(isinstance(p["status"], int) and p["status"] < 500 for p in probes), "probes": probes}
    if operation == "down" and not run.record.get("services_up"):
        return {"ran": False, "exit": None}
    configured = settings.get(operation, [])
    commands = cast(list[str], configured) if isinstance(configured, list) else [cast(str, configured)]
    if not commands:
        return {"ran": False, "exit": None}
    with Runtime(run, config, cleanup=operation == "down") as runtime:
        code = 0
        for command in commands:
            # Teardown runs the already-trusted command even after config repair.
            environ = dict(os.environ)
            if operation == "up":
                run.record["services_up"] = True
                write_json(run.directory / "run.json", run.record, 0o600)
            code, stdout, stderr = runtime.shell(command, environ, f"services {operation}",
                                                 timeout=float(run.budget["minutes"]) * 60, file_output=True)
            runtime.log_command(f"services {operation}", code, stdout, stderr)
            if code:
                raise ConfigError(f"services {operation}: command failed (exit {code})")
        return {"ran": True, "exit": code}
