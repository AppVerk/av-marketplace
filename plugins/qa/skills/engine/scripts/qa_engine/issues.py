"""Assertion-based QA IDs, claims and current unverified/auth guards."""
from __future__ import annotations

from collections.abc import Iterable

from qa_engine.assertions import FAILING
from qa_engine.common import assertion_for
from qa_engine.common import assertion_keys
from qa_engine.assertions import _scenario_of
from qa_engine.common import HEADING_ISSUE
from qa_engine.common import ISSUE_NUMBER
from qa_engine.common import LOOP_HISTORY
from qa_engine.models import Run
from qa_engine.plan import Plan
from qa_engine.plan import run_plan
from qa_engine.schema import JSON
from qa_engine.schema import SidecarState


def assign_issues(run: Run) -> JSON:
    """Assign QA IDs to failing assertions in plan order, keyed by assertion: a claimed key keeps its IDs, a new key gets one past the highest QA number in the report headings, Loop History and sidecar."""
    state = run.state
    plan = run_plan(run)
    claims = _claims(state)
    number = _highest_issue(run) + 1
    assigned: list[JSON] = []
    open_ids: list[str] = []

    for scenario in plan.scenarios:
        for key in assertion_keys(scenario):
            record = state["assertions"].get(key)
            if record is None or record["result"] not in FAILING:
                continue
            if key in claims:
                open_ids.extend(claims[key])
                continue
            qa = f"QA-{number:03d}"
            number += 1
            claims[key] = [qa]
            state["issue_assertion"][qa] = key
            issues = state["scenario_issues"].setdefault(scenario.id, [])
            if qa not in issues:
                issues.append(qa)
            unverified = assertion_for(scenario, key).unverified
            observed = record["observed_status"]
            if (observed is not None and observed >= 500) or record["crash"]:
                floor: str | None = "CRITICAL"
            elif unverified:
                floor = "LOW"
            else:
                floor = None
            assigned.append({
                "qa": qa, "key": key, "scenario": scenario.id, "observed_status": observed,
                "unverified": unverified, "severity_floor": floor,
            })
            open_ids.append(qa)

    _refresh_guards(state, plan)

    return {"assign": assigned, "open": open_ids}


def _refresh_guards(state: SidecarState, plan: Plan) -> None:
    """Recompute unverified membership for every mapped issue with data."""
    scenarios = {scenario.id: scenario for scenario in plan.scenarios}
    unverified = set(state["unverified_issues"])
    for qa, key in state["issue_assertion"].items():
        scenario = scenarios.get(_scenario_of(key))
        if scenario is None or key not in assertion_keys(scenario):
            continue
        if assertion_for(scenario, key).unverified:
            unverified.add(qa)
        else:
            unverified.discard(qa)
    state["unverified_issues"] = _sorted_ids(unverified)


def _claims(state: SidecarState) -> dict[str, list[str]]:
    claims: dict[str, list[str]] = {}
    for qa, key in state["issue_assertion"].items():
        claims.setdefault(key, []).append(qa)
    return {key: _sorted_ids(owners) for key, owners in claims.items()}


def _highest_issue(run: Run) -> int:
    """The largest QA number in the report headings, Loop History and sidecar."""
    state = run.state
    text = run.report_text()
    identifiers = set(state["issue_assertion"]) | {qa for owners in state["scenario_issues"].values() for qa in owners}
    identifiers |= set(HEADING_ISSUE.findall(text))
    history = LOOP_HISTORY.search(text)
    numbers = [_issue_number(qa) for qa in identifiers]
    if history is not None:
        numbers.extend(int(number) for number in ISSUE_NUMBER.findall(history.group(1)))
    return max(numbers, default=0)


def _issue_number(qa: str) -> int:
    match = ISSUE_NUMBER.search(qa)
    return int(match.group(1)) if match else 0


def _sorted_ids(ids: Iterable[object]) -> list[str]:
    return sorted({qa for qa in ids if isinstance(qa, str)}, key=lambda qa: (_issue_number(qa), qa))


