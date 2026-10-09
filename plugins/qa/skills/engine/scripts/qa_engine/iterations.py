"""Bounded fix iterations, recovery history and the authoritative final pass."""
from __future__ import annotations

from collections.abc import Mapping
import time

from qa_engine.assertions import _ordered
from qa_engine.candidates import failures_remain
from qa_engine.git import _dirty
from qa_engine.hardcoding import _hardcoding_warnings
from qa_engine.models import Run
from qa_engine.models import StateStop
from qa_engine.schema import FinalResult
from qa_engine.schema import FinalRow
from qa_engine.schema import FixDispatch
from qa_engine.schema import IterationResult
from qa_engine.schema import IterationRow
from qa_engine.schema import JSON
from qa_engine.schema import OpenIteration
from qa_engine.schema import SidecarState


def iteration_open(run: Run) -> JSON:
    """Decide whether another fix iteration starts; increment only on iterate."""
    state = run.state
    iteration = state["iteration"]
    if not run.plan_unchanged():
        return {"decision": "stop", "iteration": iteration, "reason": "plan changed mid-run (hash mismatch)"}
    if state["open_iteration"] is not None:
        return {"decision": "iterate", "iteration": iteration, "reason": "iteration already open"}
    if state["loop_end"] is not None:
        return {"decision": state["loop_end"]["decision"], "iteration": iteration, "reason": state["loop_end"]["reason"]}
    if not failures_remain(run):
        return {"decision": "final", "iteration": iteration, "reason": "no failures remain"}
    exhausted = _budget_exhausted(run)
    if exhausted is not None:
        return {"decision": "final", "iteration": iteration, "reason": exhausted}

    state["iteration"] = iteration + 1
    state["open_iteration"] = {
        "iteration": iteration + 1, "snapshot": dict(state["current"]),
        "dispatch_count": state["dispatch_count"], "opened": time.time(),
    }

    return {"decision": "iterate", "iteration": iteration + 1, "reason": "failures remain"}


def _unfinished_fixes(run: Run, iteration: int) -> list[FixDispatch]:
    fixes = [record for record in run.state["dispatches"].values()
             if record["kind"] == "fix" and record["iteration"] == iteration]
    for record in fixes:
        if record["result"] is None:
            warnings = _hardcoding_warnings(run, record) if run.plan_unchanged() else [
                f"{record['qa']}: Anti-hardcoding check unavailable: plan changed mid-run"
            ]
            record["result"] = "failed"
            record["warnings"] = warnings
    return fixes


def _iteration_recovery(run: Run) -> tuple[list[str], list[str]]:
    dirty = _dirty(run.repo)
    pre_loop: dict[str, str] = run.record["pre_loop"]
    artifacts = run.artifacts()
    touched = sorted(set(run.state["fix_touched_files"]) | {path for path in dirty if path not in pre_loop and path not in artifacts})
    overlap = sorted(path for path, fingerprint in pre_loop.items() if dirty.get(path) != fingerprint and path not in artifacts)
    run.state["fix_touched_files"] = touched
    return touched, overlap


def _iteration_decision(run: Run, now_passing: list[str], regressions: list[str], *, decide: bool) -> tuple[str, str]:
    if not decide:
        return "closed", "iteration closed at exit"
    if not run.plan_unchanged():
        return "continue", "plan changed mid-run; the next iteration open stops"
    if regressions:
        return "final", f"scenario regression detected: {', '.join(regressions)}"
    if not now_passing:
        return "final", "no progress this iteration (no newly passing scenarios)"
    exhausted = _budget_exhausted(run)
    return ("final", exhausted) if exhausted is not None else ("continue", "progress this iteration")


def _iteration_history(run: Run, opened: OpenIteration, fixes: list[FixDispatch], result: IterationResult) -> IterationRow:
    return {
        "iteration": opened["iteration"],
        "failing_in": _ordered(sid for sid, verdict in opened["snapshot"].items() if verdict == "fail"),
        "attempted_fixes": [record["qa"] for record in fixes],
        "fix_results": {record["qa"]: record["result"] for record in fixes},
        "now_passing": result["now_passing"],
        "still_failing": _ordered(sid for sid, verdict in run.state["current"].items() if verdict == "fail"),
        "regressions": result["regressions"],
        "warnings": [warning for record in fixes for warning in record["warnings"]],
        "dispatch_count": run.state["dispatch_count"] - opened["dispatch_count"],
        "elapsed_s": int(time.time() - float(run.record["started"])),
        "result": result,
    }


def _iteration_progress(state: SidecarState, snapshot: Mapping[str, str]) -> tuple[list[str], list[str]]:
    current: dict[str, str] = state["current"]
    now_passing = _ordered(sid for sid, verdict in snapshot.items() if verdict == "fail" and current.get(sid) == "pass")
    regressions = _ordered(sid for sid, verdict in current.items() if verdict == "fail" and state["baseline"].get(sid) == "pass")
    return now_passing, regressions


def iteration_close(run: Run, *, decide: bool = True) -> IterationResult | FinalResult:
    """Commit one history row; exit closures collect recovery without deciding the loop end."""
    state = run.state
    opened = state["open_iteration"]
    if opened is None:
        if state["iterations"]:
            return state["iterations"][-1]["result"]
        raise StateStop("no iteration is open")
    fixes = _unfinished_fixes(run, opened["iteration"])
    now_passing, regressions = _iteration_progress(state, opened["snapshot"])
    touched, overlap = _iteration_recovery(run)
    decision, reason = _iteration_decision(run, now_passing, regressions, decide=decide)

    result: IterationResult = {
        "decision": decision, "reason": reason, "now_passing": now_passing, "regressions": regressions,
        "fix_touched_files": touched, "overlap": overlap,
    }
    state["iterations"].append(_iteration_history(run, opened, fixes, result))
    state["open_iteration"] = None
    if decision == "final" and not run.stopped:
        state["loop_end"] = {"decision": decision, "reason": reason}

    return result


def record_final(run: Run, verdicts: Mapping[str, str], fixed: list[str], still_failing: list[str]) -> None:
    """Replace the Final history row with the authoritative final pass, measured against the baseline."""
    state = run.state
    baseline = state["baseline"]
    regressions = [sid for sid, verdict in verdicts.items() if verdict == "fail" and baseline.get(sid) == "pass"]
    row: FinalRow = {
        "iteration": "Final", "failing_in": [sid for sid, verdict in baseline.items() if verdict == "fail"],
        "now_passing": [sid for sid, verdict in verdicts.items() if verdict == "pass" and baseline.get(sid) != "pass"],
        "still_failing": still_failing, "warnings": [], "regressions": regressions,
        "dispatch_count": sum(record["kind"] == "tester" and record["phase"] == "final" for record in state["dispatches"].values()),
        "elapsed_s": run.elapsed(), "result": {"fixed": fixed, "regressions": regressions},
    }
    state["iterations"] = [old for old in state["iterations"] if old["iteration"] != "Final"] + [row]


def _budget_exhausted(run: Run) -> str | None:
    state = run.state
    if state["iteration"] >= run.budget["iterations"]:
        return "max iterations reached"
    if state["dispatch_count"] >= run.budget["dispatches"]:
        return "dispatch budget exhausted"
    if time.time() - float(run.record["started"]) >= float(run.budget["minutes"]) * 60:
        return "time budget exhausted"
    return None


