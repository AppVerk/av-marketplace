"""Machine-wide target-origin and store-endpoint locks and holder lifetime checks."""
from __future__ import annotations

from collections.abc import Iterator
from collections.abc import Sequence
from contextlib import contextmanager
from datetime import UTC
from datetime import datetime
import fcntl
import hashlib
import json
from pathlib import Path

from av_config.files import atomic_write
from av_config.files import default_state_home
from qa_engine.models import StateStop
from qa_engine.schema import JSON

LOCK_GRACE_MINUTES = 15


class OriginLocks:
    """One lock file per target origin or store endpoint, shared by every checkout."""

    def __init__(self, directory: Path) -> None:
        self.directory = directory

    @contextmanager
    def _exclusive(self) -> Iterator[None]:
        self.directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        with (self.directory / ".mutex").open("a") as handle:
            fcntl.flock(handle, fcntl.LOCK_EX)
            yield

    def _path(self, origin: str) -> Path:
        return self.directory / f"{hashlib.sha256(origin.encode()).hexdigest()[:32]}.json"

    def _holders(self) -> list[tuple[Path, JSON]]:
        return [(path, _lock_data(path) or {}) for path in sorted(self.directory.glob("*.json"))]

    def acquire(self, origins: Sequence[str], holder: JSON, now: float, takeover: str | None) -> list[Path]:
        """Take every origin in sorted order, or none; return taken-over run directories.

        The check runs before any write, under the lock directory's mutex, so a
        conflict leaves nothing behind. A lock is live until released or older
        than its holder's limit; ``takeover`` names the one holder that may be
        displaced, and every other lock of that holder is released as well.
        """
        with self._exclusive():
            displaced: set[str] = set()
            for origin in sorted(origins):
                current = _lock_data(self._path(origin))
                if current is None or not _live(current, now):
                    continue
                if takeover is not None and current.get("run_id") == takeover:
                    displaced.add(str(current.get("dir", "")))
                    continue
                raise StateStop("a live run holds this stack", {"holder": {
                    "run": current.get("run_id"), "started": _iso(float(current["started"])), "origin": origin,
                }})
            acquired: list[Path] = []
            try:
                for origin in sorted(origins):
                    path = self._path(origin)
                    atomic_write(path, json.dumps({**holder, "origin": origin}).encode(), 0o600)
                    acquired.append(path)
            except OSError:
                for path in acquired:
                    path.unlink(missing_ok=True)
                raise
            if displaced:
                for path, data in self._holders():
                    if data.get("run_id") == takeover:
                        path.unlink(missing_ok=True)

        return [Path(directory) for directory in sorted(displaced) if directory]

    def release(self, run_id: str) -> list[str]:
        if not self.directory.is_dir():
            return []
        released: list[str] = []
        with self._exclusive():
            for path, data in self._holders():
                if data.get("run_id") == run_id:
                    path.unlink(missing_ok=True)
                    released.append(str(data.get("origin")))

        return sorted(released)


def default_lock_directory() -> Path:
    return default_state_home() / "av-marketplace/qa-locks"


def _iso(timestamp: float) -> str:
    return datetime.fromtimestamp(timestamp, tz=UTC).isoformat(timespec="seconds")


def _lock_data(path: Path) -> JSON | None:
    """A lock's holder; an unreadable lock is stale (``{}``), a missing one ``None``."""
    try:
        value = json.loads(path.read_text())
    except FileNotFoundError:
        return None
    except (OSError, ValueError, UnicodeError):
        return {}
    return value if isinstance(value, dict) else {}


def _live(data: JSON, now: float) -> bool:
    started = data.get("started")
    limit = data.get("limit_minutes")
    if isinstance(started, bool) or isinstance(limit, bool):
        return False
    if not isinstance(started, (int, float)) or not isinstance(limit, (int, float)):
        return False
    return now < started + limit * 60


