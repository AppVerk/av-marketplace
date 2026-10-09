"""Leaf run handle and safe stop errors, independent of plans and lifecycle commands."""
from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path

from av_config.errors import ConfigError
from qa_engine.files import _plan_hash
from qa_engine.files import display_path
from qa_engine.schema import JSON
from qa_engine.schema import RunRecord
from qa_engine.schema import SidecarState

LIMITS: dict[str, int] = {"iterations": 3, "dispatches": 50, "minutes": 30}
"""Fixed loop limits; not configurable."""


class StateStop(ConfigError):
    """A domain stop (exit 1); ``details`` carries only run IDs, times and origins."""

    def __init__(self, message: str, details: Mapping[str, object] | None = None) -> None:
        super().__init__(message)
        self.details: dict[str, object] = dict(details or {})


@dataclass
class Run:
    """A started run: its private record and the sidecar state it mutates."""

    repo: Path
    run_id: str
    directory: Path
    record: RunRecord
    state: SidecarState

    @property
    def policy(self) -> JSON:
        qa = self.record["config"]["qa"]
        return {key: qa[key] for key in ("fix", "mutations", "start_services")}

    @property
    def budget(self) -> dict[str, int]:
        return LIMITS

    @property
    def plan_path(self) -> Path:
        return Path(self.record["plan"])

    @property
    def stopped(self) -> bool:
        """Whether ``run stop`` ended the loop; no later decision or ``--final`` overrides it."""
        end = self.state["loop_end"]
        return end is not None and end["decision"] == "stop"

    def plan_unchanged(self) -> bool:
        return _plan_hash(self.plan_path) == str(self.record["plan_sha256"])

    def report_text(self) -> str:
        try:
            return Path(self.record["report"]).read_text()
        except FileNotFoundError:
            return ""

    def artifacts(self) -> set[str]:
        """Repository-relative paths the loop itself writes, never counted as fix edits."""
        paths = {Path(self.record["sidecar"]), Path(self.record["report"])}
        paths |= {path.with_suffix(".bak") for path in paths}
        paths |= {self.repo / path for path in self.record["bootstrap_dirty"]}
        return {display_path(self.repo, path) for path in paths}

    def elapsed(self) -> int:
        """Seconds of run activity as recorded, never the reading process's clock, so re-renders agree."""
        started = self.record["started"]
        latest = max((record["time"] for record in self.state["dispatches"].values()), default=started)
        return max(int(latest - started), max((row["elapsed_s"] for row in self.state["iterations"]), default=0))


