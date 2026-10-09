"""Marketplace file loading, provenance and shared environment validation."""
from __future__ import annotations

from collections.abc import Callable
from collections.abc import Mapping
from dataclasses import asdict
import os
from pathlib import Path
import subprocess
import tempfile
import tomllib
from typing import cast

from av_config.errors import ConfigError
from av_config.origins import is_loopback
from av_config.origins import parse_origin
from av_config.origins import require_secure_transport
from av_config.sources import NAME
from av_config.sources import SOURCE_KINDS
from av_config.sources import SourceRule
from av_config.sources import ValueSources
from av_config.sources import source_subset

Diagnostic = dict[str, str]


def default_state_home() -> Path:
    """Use XDG's state root, falling back to the standard home directory location."""
    return Path(os.environ.get("XDG_STATE_HOME") or str(Path.home() / ".local/state"))


def read_bytes(path: Path) -> bytes | None:
    try:
        return path.read_bytes()
    except FileNotFoundError:
        return None
    except OSError as error:
        raise ConfigError("configuration file is not readable") from error


def atomic_write(path: Path, content: bytes, mode: int | None = None) -> None:
    """Replace a file atomically, preserving permissions unless specified."""
    path.parent.mkdir(parents=True, exist_ok=True)
    permissions = mode if mode is not None else (path.stat().st_mode & 0o777 if path.exists() else 0o644)
    descriptor, name = tempfile.mkstemp(prefix=f".{path.name}-", dir=path.parent)
    temporary = Path(name)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        temporary.chmod(permissions)
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


class Configuration:
    """Load the marketplace files; plugin presence belongs to the shared file."""

    def __init__(self, repo: Path, *, plugin_prefix: str, config_text: str | None = None, gitignore_text: str | None = None) -> None:
        self.repo = repo.resolve()
        self.data: dict[str, object] = {}
        self._shared_tables: set[str] = set()
        self.provenance: dict[str, str] = {}
        self.rules: dict[str, SourceRule] = {}
        self.errors: list[Diagnostic] = []
        self.warnings: list[Diagnostic] = []
        self.exists = False
        self.sources = ValueSources(self.repo, plugin_prefix=plugin_prefix, gitignore_text=gitignore_text)
        for name in (".av/config.toml", ".av/local.toml"):
            if name == ".av/config.toml" and config_text is not None:
                raw = config_text
                self.exists = True
            else:
                content = read_bytes(self.repo / name)
                if content is None:
                    continue
                if name == ".av/local.toml":
                    tracked = subprocess.run(["git", "ls-files", "--error-unmatch", "--", name], cwd=self.repo, capture_output=True, check=False)
                    if tracked.returncode != 1:
                        message = "personal config must not be tracked" if tracked.returncode == 0 else "cannot verify personal config is untracked"
                        self.errors.append({"file": name, "key": "document", "error": message})
                        continue
                    path = self.repo / name
                    if not path.resolve().is_relative_to(self.repo) or not self.sources.ignored(path):
                        self.errors.append({"file": name, "key": "document", "error": "personal config must be git-ignored"})
                        continue
                if name == ".av/config.toml":
                    self.exists = True
                try:
                    raw = content.decode()
                except UnicodeError:
                    self.errors.append({"file": name, "key": "document", "error": "invalid text encoding"})
                    continue
            try:
                parsed = tomllib.loads(raw)
            except tomllib.TOMLDecodeError:
                self.errors.append({"file": name, "key": "document", "error": "invalid TOML"})
                continue
            if name == ".av/config.toml":
                self._shared_tables = {key for key, value in parsed.items() if isinstance(value, dict)}
            self._merge(self.data, parsed, name)
        if self.exists:
            self._validate_env()

    def _merge(self, destination: dict[str, object], source: Mapping[str, object], filename: str, prefix: str = "") -> None:
        for key, item in source.items():
            path = f"{prefix}.{key}" if prefix else key
            if isinstance(item, dict):
                existing = destination.get(key)
                if not isinstance(existing, dict):
                    existing = {}
                    destination[key] = existing
                    for old in list(self.provenance):
                        if old.startswith(path + "."):
                            del self.provenance[old]
                self.provenance[path] = filename
                self._merge(existing, item, filename, path)
            else:
                destination[key] = item
                for old in list(self.provenance):
                    if old.startswith(path + "."):
                        del self.provenance[old]
                self.provenance[path] = filename

    def file_for(self, key: str) -> str:
        path = key
        while path:
            if path in self.provenance:
                return self.provenance[path]
            path = path.rpartition(".")[0]
        return ".av/config.toml"

    def error(self, key: str, message: str) -> None:
        self.errors.append({"file": self.file_for(key), "key": key, "error": message})

    def table(self, value: object, key: str) -> dict[str, object]:
        if not isinstance(value, dict):
            self.error(key, "expected a table")
            return {}
        return value

    def keys(self, table: Mapping[str, object], allowed: set[str], prefix: str) -> None:
        for key in table.keys() - allowed:
            self.error(f"{prefix}.{key}", "unknown key")

    def source(self, value: object, key: str, *, secret: bool = False, literal_allowed: bool = False) -> None:
        rule = SourceRule(local=self.file_for(key) == ".av/local.toml", secret=secret, literal_allowed=literal_allowed)
        self.rules[key] = rule
        problem = self.sources.validate(value, key, **asdict(rule))
        if problem:
            self.error(key, problem)

    def resolve(self, source: str, key: str, *, trusted: bool, execute: Callable[[str, str], str] | None = None) -> str:
        """Resolve with the recorded restrictions; executors receive command/key."""
        rule = self.rules.get(key)
        if rule is None:
            raise ConfigError(f"{key}: source was not validated")
        return self.sources.resolve(source, key, trusted=trusted, execute=execute, **asdict(rule))

    def _validate_env(self) -> None:
        if type(self.data.get("version")) is not int or self.data.get("version") != 1:
            self.error("version", "expected schema version 1")
        env = self.table(self.data.get("env", {}), "env")
        for name, value in env.items():
            prefix = f"env.{name}"
            if name not in {"targets", "services", "secrets", "values", "stores"}:
                self.warnings.append({"file": self.file_for(prefix), "key": prefix, "warning": "unknown environment sub-table"})
                continue
            table = self.table(value, prefix)
            if name == "targets":
                self._validate_targets(table)
            elif name in {"secrets", "values"}:
                self._validate_sources(table, prefix, secret=name == "secrets")
            elif name == "services":
                self._validate_services(table, env.get("targets", {}))
            else:
                self._validate_stores(table)

    def _validate_targets(self, table: Mapping[str, object]) -> None:
        for target, origin in table.items():
            try:
                if not NAME.fullmatch(target) or not isinstance(origin, str):
                    raise ConfigError("invalid target")
                parse_origin(origin, origin_only=True)
            except ConfigError:
                self.error(f"env.targets.{target}", "expected an HTTP origin without userinfo, path, query or fragment")

    def _validate_sources(self, table: Mapping[str, object], prefix: str, *, secret: bool) -> None:
        for key, source in table.items():
            if not NAME.fullmatch(key):
                self.error(f"{prefix}.{key}", "invalid value name")
            self.source(source, f"{prefix}.{key}", secret=secret)

    def _validate_services(self, table: Mapping[str, object], targets: object) -> None:
        prefix = "env.services"
        self.keys(table, {"health", "up", "prepare", "down"}, prefix)
        for key in ("up", "down"):
            if key in table:
                self._validate_service_command(table[key], f"{prefix}.{key}")
        prepare = table.get("prepare", [])
        if not isinstance(prepare, list) or any(not isinstance(item, str) or not item for item in prepare):
            self.error(f"{prefix}.prepare", "expected a command list")
        else:
            for index, command in enumerate(prepare):
                self._validate_service_command(command, f"{prefix}.prepare.{index}")
        health = table.get("health", [])
        if not isinstance(health, list):
            self.error(f"{prefix}.health", "expected a probe list")
        else:
            for probe in health:
                self._validate_probe(probe, targets)
        if "up" in table and not table.get("health"):
            self.error(f"{prefix}.up", "up requires at least one health probe")
        if "prepare" in table and "up" not in table:
            self.error(f"{prefix}.prepare", "prepare requires up")
        if "down" in table and "up" not in table:
            self.error(f"{prefix}.down", "down requires up")

    def _validate_service_command(self, command: object, key: str) -> None:
        if not isinstance(command, str) or not command:
            self.error(key, "expected a non-empty command")
        elif command.startswith(SOURCE_KINDS):
            self.error(key, "a command cannot be a value source")

    def _validate_probe(self, probe: object, targets: object) -> None:
        key = "env.services.health"
        if not isinstance(probe, str) or ":" not in probe:
            self.error(key, "expected target:path probes")
            return
        target, path = probe.split(":", 1)
        if not isinstance(targets, dict) or target not in targets or not path.startswith("/") or path.startswith("//"):
            self.error(key, "probe has undefined target or invalid path")
        elif isinstance(targets[target], str):
            try:
                require_secure_transport(targets[target])
            except ConfigError as error:
                self.error(f"env.targets.{target}", str(error))

    def _validate_stores(self, table: Mapping[str, object]) -> None:
        if len({name.lower() for name in table}) != len(table):
            self.error("env.stores", "store names collide")
        for name, value in table.items():
            prefix = f"env.stores.{name}"
            if not NAME.fullmatch(name):
                self.error(prefix, "invalid store name")
            entry = self.table(value, prefix)
            kind = entry.get("kind")
            if kind == "sql":
                self.keys(entry, {"kind", "engine", "host", "port", "user", "name", "password", "path"}, prefix)
                engine = entry.get("engine")
                if engine not in ("postgres", "mysql", "sqlite"):
                    self.error(f"{prefix}.engine", "expected postgres, mysql or sqlite")
                    continue
                required = ("path",) if engine == "sqlite" else ("host", "user", "name", "password")
                for key in required:
                    if not isinstance(entry.get(key), str) or not entry.get(key):
                        self.error(f"{prefix}.{key}", "expected a non-empty string")
                if engine == "sqlite":
                    for key in {"host", "port", "user", "name", "password"} & entry.keys():
                        self.error(f"{prefix}.{key}", "not supported for sqlite")
                elif "path" in entry:
                    self.error(f"{prefix}.path", "only supported for sqlite")
            elif kind == "redis":
                self.keys(entry, {"kind", "host", "port", "db", "password"}, prefix)
                if not isinstance(entry.get("host"), str) or not entry.get("host"):
                    self.error(f"{prefix}.host", "expected a non-empty string")
                if "db" in entry and (type(entry["db"]) is not int or cast(int, entry["db"]) < 0):
                    self.error(f"{prefix}.db", "expected a non-negative integer")
            else:
                self.error(f"{prefix}.kind", "expected sql or redis")
                continue
            host = entry.get("host")
            if isinstance(host, str) and host and not is_loopback(host):
                self.error(f"{prefix}.host", "non-loopback stores require TLS")
            if "port" in entry and (type(entry["port"]) is not int or not 1 <= cast(int, entry["port"]) <= 65535):
                self.error(f"{prefix}.port", "expected a port between 1 and 65535")
            if "password" in entry and not (kind == "sql" and entry.get("engine") == "sqlite"):
                self.source(entry["password"], f"{prefix}.password", secret=True, literal_allowed=isinstance(host, str) and is_loopback(host))

    def state(self, plugin: str) -> str:
        if not self.exists:
            return "missing-file"
        if self.errors:
            return "invalid"
        return "ok" if plugin in self._shared_tables else "missing-table"

    def env_sensitive_subset(self) -> dict[str, object]:
        env = self.data.get("env", {})
        if not isinstance(env, dict):
            return {}
        subset = source_subset(env, "env")
        if env.get("services"):
            subset["env.services"] = env["services"]
        targets = env.get("targets", {})
        if isinstance(targets, dict):
            for name, origin in targets.items():
                if isinstance(origin, str):
                    try:
                        host = parse_origin(origin)[1]
                    except ConfigError:
                        continue
                    if not is_loopback(host):
                        subset[f"env.targets.{name}"] = origin
        return subset


