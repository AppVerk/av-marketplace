"""Durable sidecar reuse, adoption, rebaselining and assertion reconstruction."""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
import json
import os
from pathlib import Path
import re

from qa_engine.common import assertion_for
from qa_engine.common import assertion_keys
from qa_engine.files import display_path
from qa_engine.issue_blocks import _issue_blocks
from qa_engine.plan import Plan
from qa_engine.plan import Scenario
from qa_engine.schema import Fingerprints
from qa_engine.schema import PersistentState
from qa_engine.schema import SidecarState
from qa_engine.schema import _conforms
from qa_engine.schema import _fields


@dataclass(frozen=True)
class StoredSidecar:
    """A prior sidecar's identity and its kept fields over fresh defaults."""

    plan_sha256: str
    report_file: object
    kept: PersistentState


@dataclass(frozen=True)
class SidecarContext:
    """Run identity and baseline used to initialize a durable sidecar."""

    plan_sha256: str
    run_id: str
    pre_loop: Fingerprints
    generated: bool


def _prepare_sidecar(repo: Path, plan: Plan, context: SidecarContext) -> tuple[str, Path, Path, SidecarState]:
    """Resolve the four idempotency cases (reuse, rebaseline, adopt, fresh) and build the run's sidecar."""
    reports = repo / "docs/testing/reports"
    topic = _topic(plan.path)
    sidecar = reports / f"{topic}-loop-state.json"
    newest = _newest_report(reports, topic)
    today = datetime.now().astimezone().date().isoformat()
    fresh = reports / f"{today}-{topic}-report.md"
    kept: PersistentState = {
        "created": today, "scenario_issues": {}, "issue_assertion": {}, "scenario_kind": {}, "scenario_reason": {},
        "unverified_issues": [], "need_info": {}, "auto_generated": context.generated,
    }

    if sidecar.exists():
        stored = _stored_sidecar(sidecar, kept)
        previous = _stored_report(reports, stored.report_file if stored is not None else None) or newest
        if stored is not None and stored.plan_sha256 == context.plan_sha256:
            idempotency = "reuse"
            report = previous or fresh
            kept = stored.kept
            _reconstruct(kept, report, plan)
        else:
            idempotency = "rebaseline"
            os.replace(sidecar, sidecar.with_suffix(".bak"))
            if previous is not None:
                # Fresh IDs start at QA-001, so the old report must leave the ID union.
                os.replace(previous, previous.with_suffix(".bak"))
            report = fresh
    elif newest is not None:
        idempotency = "adopt"
        report = newest
        prior_text = newest.read_text()
        kept["auto_generated"] = bool(re.search(r"^- Plan provenance: auto-generated$", prior_text, re.MULTILINE))
        for qa, block in _issue_blocks(prior_text).items():
            if block.scenario is not None:
                kept["scenario_issues"].setdefault(block.scenario, []).append(qa)
        _reconstruct(kept, report, plan)
    else:
        idempotency = "fresh"
        report = fresh

    if context.generated:
        kept["auto_generated"] = True
    state: SidecarState = {
        "plan_sha256": context.plan_sha256, "plan_path": display_path(repo, plan.path), "report_file": display_path(repo, report),
        "topic": topic, "run_id": context.run_id, "baseline": {}, "current": {}, "assertions": {},
        "pre_loop_dirty": sorted(context.pre_loop), "pre_loop": context.pre_loop, "fix_touched_files": [],
        "dispatch_count": 0, "dispatches": {}, "iteration": 0, "open_iteration": None, "loop_end": None,
        "iterations": [], **kept,
    }

    return idempotency, sidecar, report, state


def _reconstruct(carried: PersistentState, report: Path, plan: Plan) -> None:
    """Map unmapped issue IDs to assertion keys from Scenario and Expected, only when unique."""
    issue_assertion = carried["issue_assertion"]
    scenario_issues = carried["scenario_issues"]
    unmapped = [qa for owners in scenario_issues.values() for qa in owners if qa not in issue_assertion]
    if not unmapped:
        return
    try:
        blocks = _issue_blocks(report.read_text())
    except FileNotFoundError:
        return
    scenarios = {scenario.id: scenario for scenario in plan.scenarios}
    claimed = set(issue_assertion.values())
    found: dict[str, list[str]] = {}
    for qa in unmapped:
        block = blocks.get(qa)
        scenario = scenarios.get(block.scenario) if block is not None and block.scenario else None
        if block is None or scenario is None or not block.expected or qa not in scenario_issues.get(scenario.id, []):
            continue
        matches = _matching(scenario, block.expected)
        if len(matches) == 1 and matches[0] not in claimed:
            found.setdefault(matches[0], []).append(qa)
    for key, owners in found.items():
        if len(owners) == 1:
            issue_assertion[owners[0]] = key


def _matching(scenario: Scenario, expected: str) -> list[str]:
    def normalize(text: str) -> str:
        return " ".join(text.replace("`", "").split())

    wanted = normalize(expected)
    options = [(key, normalize(assertion_for(scenario, key).text)) for key in assertion_keys(scenario)]
    exact = [key for key, text in options if text and text == wanted]
    if exact:
        return exact
    return [key for key, text in options if text and (text in wanted or wanted in text)]


def _stored_sidecar(path: Path, defaults: PersistentState) -> StoredSidecar | None:
    """A prior sidecar whose kept fields have the right types; anything else rebaselines."""
    try:
        value = json.loads(path.read_text())
    except (ValueError, UnicodeError):
        return None
    if not isinstance(value, dict) or not isinstance(value.get("plan_sha256"), str):
        return None
    # A sidecar from an older engine may lack kept fields; those start from the fresh defaults.
    kept = {**defaults, **{key: value[key] for key in _fields(PersistentState) if key in value}}
    if not _conforms(kept, PersistentState):
        return None
    return StoredSidecar(value["plan_sha256"], value.get("report_file"), kept)


def _stored_report(reports: Path, name: object) -> Path | None:
    """The sidecar's report, only when it is an existing report of this directory."""
    if not isinstance(name, str) or not name.endswith("-report.md"):
        return None
    # Only the file name is taken from the sidecar, so it cannot point outside the reports directory.
    candidate = reports / Path(name).name
    return candidate if candidate.is_file() else None


def _newest_report(reports: Path, topic: str) -> Path | None:
    pattern = re.compile(rf"\d{{4}}-\d{{2}}-\d{{2}}-{re.escape(topic)}-report\.md\Z")
    found = [path for path in reports.glob("*-report.md") if pattern.fullmatch(path.name) and path.is_file()]
    return max(found, key=lambda path: (path.stat().st_mtime_ns, path.name), default=None)


def _topic(plan: Path) -> str:
    stem = re.sub(r"^\d{4}-\d{2}-\d{2}-", "", plan.stem)
    stem = re.sub(r"-(?:test-)?plan$", "", stem)
    return re.sub(r"[^A-Za-z0-9._-]+", "-", stem).strip("-.") or "qa"


