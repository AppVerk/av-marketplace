"""Tester/fixer assignments, dispatch ordering and fix completion bookkeeping."""
from __future__ import annotations

import re
import secrets
import time
from typing import cast

from av_config.errors import InvalidConfig
from qa_engine.users import prepare_capture
from qa_engine.assertions import _scenario_of
from qa_engine.candidates import candidates
from qa_engine.config import Config
from qa_engine.git import _dirty
from qa_engine.hardcoding import _hardcoding_warnings
from qa_engine.common import ISSUE_ID
from qa_engine.models import Run
from qa_engine.models import StateStop
from qa_engine.plan import check_plan
from qa_engine.plan import run_plan
from qa_engine.runs import check_drift
from qa_engine.schema import FixDispatch
from qa_engine.schema import JSON
from qa_engine.schema import SidecarState
from qa_engine.schema import TesterDispatch


def dispatch_tester(run: Run, config: Config, section: str, phase: str) -> JSON:
    """Record a tester assignment with its private capture directory and tag."""
    check_drift(run, config)
    state = run.state
    plan = run_plan(run)
    ids = plan.sections.get(section, [])
    if not ids:
        raise StateStop(f"the plan has no {section} scenarios")
    opened = state["open_iteration"]
    if phase in {"baseline", "retry"} and (state["iteration"] or opened is not None):
        raise StateStop("baseline and retry dispatches precede the first iteration")
    if phase == "iteration" and opened is None:
        raise StateStop("no iteration is open; run iteration open first")

    scenarios = {scenario.id: scenario for scenario in plan.scenarios}
    checked = check_plan(plan, config)
    guarded = [sid for sid in cast(list[str], checked["guarded"]) if sid in ids]
    checks = cast(dict[str, list[str]], checked["state_checks"])
    stores = sorted({store for sid in ids for store in checks.get(sid, [])})
    edges = {sid: len(scenarios[sid].edges) for sid in ids}
    tag = secrets.token_hex(4)
    dispatch = _record_dispatch(state, {
        "kind": "tester", "section": section, "phase": phase, "scenarios": ids, "edges": edges,
        "guarded": guarded, "tag": tag,
        "iteration": opened["iteration"] if opened else None, "ingested": False, "time": time.time(),
    })
    prepare_capture(run, dispatch)

    return {
        "dispatch": dispatch, "scenarios": ids, "edges": edges, "guarded": guarded, "tag": tag, "stores": stores,
        "dispatch_count": state["dispatch_count"], "budget_left": _budget_left(run),
    }


def dispatch_fix(run: Run, config: Config, qa: str) -> JSON:
    """Record a fix-auto dispatch for a current candidate of the open iteration."""
    check_drift(run, config)
    if not ISSUE_ID.fullmatch(qa):
        raise InvalidConfig("invalid QA ID")
    state = run.state
    opened = state["open_iteration"]
    if opened is None:
        raise StateStop("no iteration is open; run iteration open first")
    entry = next((item for item in candidates(run)["fix"] if item["qa"] == qa), None)
    if entry is None:
        raise StateStop(f"{qa} is not a fix candidate")

    dispatch = _record_dispatch(state, {
        "kind": "fix", "qa": qa, "key": entry["key"], "iteration": opened["iteration"],
        "dirty_before": _dirty(run.repo), "result": None, "warnings": [], "time": time.time(),
    })

    return {
        "dispatch": dispatch, "qa": qa, "scenarios": [_scenario_of(entry["key"])], "edges": {},
        "dispatch_count": state["dispatch_count"], "budget_left": _budget_left(run),
    }


def fix_done(run: Run, dispatch_id: str, result: str) -> JSON:
    """Record a fix attempt and its anti-hardcoding warnings; verdicts stay with the re-run."""
    state = run.state
    record = state["dispatches"].get(dispatch_id)
    if record is None or record["kind"] != "fix":
        raise StateStop("unknown fix dispatch")
    if record["result"] is not None:
        if record["result"] == result:
            return {"warnings": record["warnings"]}
        raise StateStop("a different result is already recorded for this dispatch")
    opened = state["open_iteration"]
    if opened is None or opened["iteration"] != record["iteration"]:
        raise StateStop("the iteration of this fix is closed")

    warnings = _hardcoding_warnings(run, record)
    record["result"] = result
    record["warnings"] = warnings

    return {"warnings": warnings}


def _tester_record(state: SidecarState, dispatch_id: str) -> TesterDispatch:
    record = state["dispatches"].get(dispatch_id)
    if record is None or record["kind"] != "tester":
        raise StateStop("unknown tester dispatch")
    if record["ingested"]:
        raise StateStop("dispatch already ingested")
    for key, other in state["dispatches"].items():
        if other["kind"] != "tester" or other["section"] != record["section"]:
            continue
        if other["ingested"] and _dispatch_number(key) > _dispatch_number(dispatch_id):
            raise StateStop("a later dispatch of this section was already ingested")
    return record


def _budget_left(run: Run) -> int:
    return max(0, int(run.budget["dispatches"]) - int(run.state["dispatch_count"]))


def _record_dispatch(state: SidecarState, record: TesterDispatch | FixDispatch) -> str:
    state["dispatch_count"] += 1
    dispatch = f"D{len(state['dispatches']) + 1:03d}"
    state["dispatches"][dispatch] = record
    return dispatch


def _dispatch_number(dispatch: str) -> int:
    match = re.fullmatch(r"D(\d+)", dispatch)
    return int(match.group(1)) if match else 0


