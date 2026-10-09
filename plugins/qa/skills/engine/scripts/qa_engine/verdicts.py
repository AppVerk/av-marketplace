"""Pure scenario classification, assertion evaluation and verdict precedence."""
from __future__ import annotations

from dataclasses import dataclass
from dataclasses import field
import re
from urllib.parse import urlsplit

from qa_engine.plan import Scenario
from qa_engine.schema import AssertionRecord
from qa_engine.schema import Gap
from qa_engine.schema import JSON

TOOL_PROSE = re.compile(r"no .*client|unavailable|not supported", re.IGNORECASE)
TRANSPORT_PROSE = re.compile(r"connection refused|could not connect|timeout", re.IGNORECASE)
SANITY_PATHS = frozenset({"/health", "/healthz", "/openapi.json", "/version", "/", "/docs", "/api/docs"})


@dataclass
class Evaluation:
    """One scenario's ingested result: verdict, reason, gaps and assertion records."""

    verdict: str
    reason: str | None
    kind: str
    complete: bool
    assertions: dict[str, AssertionRecord] = field(default_factory=dict)
    gaps: dict[str, Gap] = field(default_factory=dict)


def scenario_kind(scenario: Scenario) -> str:
    """What a PASS of this scenario means for coverage: ``feature``, ``sanity`` or ``negative``."""
    if scenario.section == "FE":
        return "feature"
    statuses = scenario.expected.statuses
    if statuses and statuses[0] >= 400:
        return "negative"
    if scenario.path is not None and (urlsplit(scenario.path).path or "/") in SANITY_PATHS:
        return "sanity"
    return "feature"


def _main_result(scenario: Scenario, main: JSON, kind: str) -> tuple[str, bool]:
    statuses = scenario.expected.statuses
    if scenario.section != "BE" or kind != "feature" or main["status"] not in {"PASS", "FAIL"}:
        return main["status"], False
    if main["observed_status"] not in {401, 403} or not statuses or not 200 <= statuses[0] < 300:
        return main["status"], False
    return "FAIL", True


VERDICT_PRECEDENCE = (("FAIL", "fail"), ("NEED_INFO", "need-info"), ("SKIP", "skip"))


def _scenario_verdict(main_result: str, edges: list[JSON]) -> str:
    results = {edge["status"] for edge in edges}
    for status, verdict in VERDICT_PRECEDENCE:
        if main_result == status or status in results:
            return verdict
    return "pass"


def _evaluated_assertion(evaluation: Evaluation, key: str, row: JSON, result: str, auth: bool) -> None:
    evaluation.assertions[key] = _assertion_record(row, result, auth)
    if row["status"] == "NEED_INFO":
        evaluation.gaps[key] = {"kind": row["kind"], "missing": row["missing"]}


def _evaluate(scenario: Scenario, row: JSON | None, planned: int, guarded: bool) -> Evaluation:
    skipped: JSON = {"status": "SKIP", "observed_status": None, "crash": False, "kind": None, "missing": [], "skip_reason": None, "refutation": None}
    given: dict[int, JSON] = row["edges"] if row is not None else {}
    complete = row is not None and len(given) == planned
    main = row if row is not None else skipped
    edges = [given.get(number, skipped) for number in range(1, planned + 1)]
    if guarded:
        # The guard excluded this scenario; a reported result is neither credited nor minted.
        main, edges = skipped, [skipped] * planned
    kind = scenario_kind(scenario)
    main_result, auth = _main_result(scenario, main, kind)
    verdict = _scenario_verdict(main_result, edges)

    skip = main if main_result == "SKIP" else next((edge for edge in edges if edge["status"] == "SKIP"), None)
    evaluation = Evaluation(verdict, _reason(verdict, guarded, skip), kind, complete)
    _evaluated_assertion(evaluation, scenario.id, main, main_result, auth)
    for number, edge in enumerate(edges, 1):
        _evaluated_assertion(evaluation, f"{scenario.id} (edge {number})", edge, edge["status"], False)

    return evaluation


def _assertion_record(outcome: JSON, result: str, auth: bool) -> AssertionRecord:
    return {
        "result": result, "observed_status": outcome["observed_status"], "crash": outcome["crash"],
        "auth": auth, "refutation": outcome["refutation"],
    }


def _reason(verdict: str, guarded: bool, skip: JSON | None) -> str | None:
    """Normalize non-pass, non-fail reasons from guards, gaps and SKIP prose."""
    if verdict in {"pass", "fail"}:
        return None
    if verdict == "need-info":
        return "need-info"
    if guarded:
        return "mutation-guard"
    text = skip["skip_reason"] if skip is not None else None
    if not text or text.strip().lower().startswith(("harness error:", "out of harness scope:")):
        return "cannot-confirm"
    if TOOL_PROSE.search(text):
        return "tool-unavailable"
    if TRANSPORT_PROSE.search(text):
        return "transport"
    return "cannot-confirm"




