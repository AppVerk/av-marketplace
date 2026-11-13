"""Repository-realpath and plugin-scoped marketplace trust pins."""
from __future__ import annotations

from collections.abc import Callable
from collections.abc import Mapping
import fcntl
import hashlib
import json
from pathlib import Path

from av_config.errors import ConfigError
from av_config.files import atomic_write
from av_config.files import default_state_home
from av_config.files import read_bytes


def canonical_hash(value: object) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()


class TrustStore:
    """Repository-realpath and plugin scoped pins, stored outside the checkout."""

    def __init__(self, repo: Path, plugin: str, state_home: Path | None = None) -> None:
        home = state_home or default_state_home()
        self.path = home / "av-marketplace/trust.json"
        self.repo = str(repo.resolve())
        self.plugin = plugin

    def _read(self) -> dict[str, object]:
        raw = read_bytes(self.path)
        if raw is None:
            return {}
        try:
            data = json.loads(raw)
        except (ValueError, UnicodeError) as error:
            raise ConfigError("invalid marketplace trust store") from error
        if not isinstance(data, dict):
            raise ConfigError("invalid marketplace trust store")
        return data

    def status(self, subset: Mapping[str, object]) -> str:
        if not subset:
            return "not-required"
        repositories = self._read()
        plugins = repositories.get(self.repo, {})
        previous = plugins.get(self.plugin) if isinstance(plugins, dict) else None
        if previous is None:
            return "new"
        return "trusted" if previous == canonical_hash(subset) else "changed"

    def accept(self, approved_hash: str, current_subset: Callable[[], Mapping[str, object]]) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with (self.path.parent / "trust.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            if canonical_hash(current_subset()) != approved_hash:
                raise ConfigError("trust hash changed; preview the current configuration")
            data = self._read()
            plugins = data.get(self.repo)
            if not isinstance(plugins, dict):
                plugins = {}
                data[self.repo] = plugins
            plugins[self.plugin] = approved_hash
            atomic_write(self.path, json.dumps(data, sort_keys=True).encode(), 0o600)


