"""Parsing of a tester's ``json qa-results`` block and its application to a recorded tester assignment."""
from __future__ import annotations

from collections.abc import Mapping
import json
import re

from av_config.errors import InvalidConfig
from qa_engine.assertions import FAILING
from qa_engine.assertions import _forget
from qa_engine.common import assertion_keys
from qa_engine.dispatch import _tester_record
from qa_engine.issues import _claims
from qa_engine.issues import _refresh_guards
from qa_engine.plan import Scenario
from qa_engine.plan import run_plan
from qa_engine.models import Run
from qa_engine.schema import Gap
from qa_engine.schema import JSON
from qa_engine.schema import SidecarState
from qa_engine.schema import TesterDispatch
from qa_engine.verdicts import Evaluation
from qa_engine.verdicts import _evaluate
from qa_engine.users import record_accounts

RESULT_FENCE = re.compile(r"^(`{3,}|~{3,})[ \t]*json[ \t]+qa-results[ \t]*$", re.MULTILINE)
STATUSES = frozenset({"PASS", "FAIL", "SKIP", "NEED_INFO"})
KINDS = frozenset({"credentials", "service", "fixture", "tool"})


def _apply_evaluation(state: SidecarState, sid: str, outcome: Evaluation, phase: str) -> None:
    _forget(state["need_info"], sid)
    _forget(state["assertions"], sid)
    state["need_info"].update(outcome.gaps)
    state["assertions"].update(outcome.assertions)
    state["scenario_kind"][sid] = outcome.kind
    if outcome.reason is None:
        state["scenario_reason"].pop(sid, None)
    else:
        state["scenario_reason"][sid] = outcome.reason
    state["current"][sid] = outcome.verdict
    if phase in {"baseline", "retry"}:
        state["baseline"][sid] = outcome.verdict


def _new_failures(state: SidecarState, record: TesterDispatch, scenarios: Mapping[str, Scenario]) -> list[str]:
    claims = _claims(state)
    failures: list[str] = []
    for sid in record["scenarios"]:
        for key in assertion_keys(scenarios[sid]):
            assertion = state["assertions"].get(key)
            if assertion is not None and assertion["result"] in FAILING and key not in claims:
                failures.append(key)
    return failures


def _ingest_changes(
    state: SidecarState, record: TesterDispatch, scenarios: Mapping[str, Scenario],
    verdicts: Mapping[str, str], previous: Mapping[str, str],
) -> JSON:
    comparing = record["phase"] in {"iteration", "final"}
    return {
        "new_failures": _new_failures(state, record, scenarios),
        "regressions": [sid for sid in verdicts if comparing and state["baseline"].get(sid) == "pass" and verdicts[sid] == "fail"],
        "now_passing": [sid for sid in verdicts if previous.get(sid) == "fail" and verdicts[sid] == "pass"],
    }


def ingest(run: Run, dispatch_id: str, text: str) -> JSON:
    """Apply a tester's ``json qa-results`` block to its dispatch's assignment: per-scenario gaps, assertion records, kind, verdict and reason."""
    state = run.state
    record = _tester_record(state, dispatch_id)
    plan = run_plan(run)
    scenarios = {scenario.id: scenario for scenario in plan.scenarios}
    planned: dict[str, int] = record["edges"]
    rows, entries, error = _parse_results(text, record["section"], planned)
    previous = dict(state["current"])
    verdicts: dict[str, str] = {}
    gaps: dict[str, Gap] = {}
    incomplete: list[str] = []

    for sid in record["scenarios"]:
        scenario = scenarios[sid]
        outcome = _evaluate(scenario, rows.get(sid) if rows is not None else None, planned[sid], sid in record["guarded"])
        _apply_evaluation(state, sid, outcome, record["phase"])
        verdicts[sid] = outcome.verdict
        gaps.update(outcome.gaps)
        if not outcome.complete:
            incomplete.append(sid)

    record["ingested"] = True
    _refresh_guards(state, plan)
    result: JSON = {"verdicts": verdicts, "need_info": gaps, "incomplete": incomplete,
                    "accounts": record_accounts(run, dispatch_id, record["tag"], entries),
                    **_ingest_changes(state, record, scenarios, verdicts, previous)}
    if error is not None:
        result["error"] = error

    return result


def _results_payload(text: str, section: str) -> JSON:
    openings = list(RESULT_FENCE.finditer(text))
    if not openings:
        raise InvalidConfig("missing qa-results block")
    if len(openings) > 1:
        raise InvalidConfig("more than one qa-results block")
    fence = openings[0].group(1)
    closing = re.compile(rf"^{re.escape(fence[0])}{{{len(fence)},}}[ \t]*$", re.MULTILINE).search(text, openings[0].end())
    if closing is None:
        raise InvalidConfig("unterminated qa-results block")
    try:
        data = json.loads(text[openings[0].end():closing.start()])
    except ValueError as error:
        raise InvalidConfig("qa-results block is not valid JSON") from error
    if not isinstance(data, dict) or not isinstance(data.get("scenarios"), list):
        raise InvalidConfig("qa-results block lacks its scenarios")
    if data.get("section") != section:
        raise InvalidConfig("qa-results block is for another section")
    entries = data.get("accounts", [])
    if not isinstance(entries, list) or any(not isinstance(entry, dict) or not isinstance(entry.get("email"), str) for entry in entries):
        raise InvalidConfig("qa-results block has invalid accounts")
    return data


def _result_edges(edges: list[object], section: str, planned: int) -> dict[int, JSON]:
    parsed: dict[int, JSON] = {}
    for edge in edges:
        outcome = _outcome(edge, section)
        number = edge.get("n") if isinstance(edge, dict) else None
        if outcome is None or isinstance(number, bool) or not isinstance(number, int):
            raise InvalidConfig("qa-results block has an invalid edge entry")
        if not 1 <= number <= planned:
            raise InvalidConfig("qa-results block reports an unplanned edge")
        if number in parsed:
            raise InvalidConfig("qa-results block repeats an edge")
        parsed[number] = outcome
    return parsed


def _result_rows(data: JSON, section: str, planned: Mapping[str, int]) -> dict[str, JSON]:
    rows: dict[str, JSON] = {}
    for item in data["scenarios"]:
        row = _outcome(item, section)
        sid = item.get("id") if isinstance(item, dict) else None
        edges = item.get("edges", []) if isinstance(item, dict) else None
        if row is None or not isinstance(sid, str) or not isinstance(edges, list):
            raise InvalidConfig("qa-results block has an invalid scenario entry")
        if sid not in planned:
            raise InvalidConfig("qa-results block reports an unassigned scenario")
        if sid in rows:
            raise InvalidConfig("qa-results block repeats a scenario")
        rows[sid] = {**row, "edges": _result_edges(edges, section, planned[sid])}
    return rows


def _parse_results(text: str, section: str, planned: Mapping[str, int]) -> tuple[dict[str, JSON] | None, list[JSON], str | None]:
    """Read the single results block; any structural problem rejects it entirely."""
    try:
        payload = _results_payload(text, section)
        return _result_rows(payload, section, planned), payload.get("accounts", []), None
    except InvalidConfig as error:
        return None, [], str(error)


def _outcome(item: object, section: str) -> JSON | None:
    """Validate one ``json qa-results`` entry; ``None`` when any field has the wrong shape."""
    if not isinstance(item, dict) or item.get("status") not in STATUSES:
        return None
    observed = item.get("observed_status")
    crash = item.get("crash", False)
    kind = item.get("kind")
    missing = item.get("missing", [])
    skip_reason = item.get("skip_reason")
    refutation = item.get("refutation")
    valid = (
        (observed is None or (isinstance(observed, int) and not isinstance(observed, bool) and 100 <= observed <= 599))
        and isinstance(crash, bool) and (kind is None or kind in KINDS)
        and isinstance(missing, list) and all(isinstance(name, str) for name in missing)
        and (skip_reason is None or isinstance(skip_reason, str)) and (refutation is None or isinstance(refutation, str))
    )
    if not valid:
        return None

    return {
        "status": item["status"], "observed_status": None if section == "FE" else observed, "crash": crash,
        "kind": kind, "missing": missing, "skip_reason": skip_reason, "refutation": refutation,
    }


