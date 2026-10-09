"""Durable run/sidecar records and validation against their declared schemas."""
from __future__ import annotations

from functools import cache
from types import UnionType
from typing import Any
from typing import Literal
from typing import NotRequired
from typing import TypeGuard
from typing import TypeVar
from typing import TypedDict
from typing import Union
from typing import final
from typing import get_args
from typing import get_origin
from typing import get_type_hints
from typing import is_typeddict

JSON = dict[str, Any]
T = TypeVar("T")


# The sidecar and run.json schema. Every field is declared once here; writers
# are checked by mypy and loaded files are validated against the same classes.
Fingerprints = dict[str, str]


class Gap(TypedDict):
    kind: str | None
    missing: list[str]


class AssertionRecord(TypedDict):
    result: str
    observed_status: int | None
    crash: bool
    auth: bool
    refutation: str | None


class TesterDispatch(TypedDict):
    kind: Literal["tester"]
    section: str
    phase: str
    scenarios: list[str]
    edges: dict[str, int]
    guarded: list[str]
    tag: str
    iteration: int | None
    ingested: bool
    time: float


class FixDispatch(TypedDict):
    kind: Literal["fix"]
    qa: str
    key: str
    iteration: int
    dirty_before: Fingerprints
    result: str | None
    warnings: list[str]
    time: float


class OpenIteration(TypedDict):
    iteration: int
    snapshot: dict[str, str]
    dispatch_count: int
    opened: float


class LoopEnd(TypedDict):
    decision: str
    reason: str
    detail: NotRequired[str]


class IterationResult(TypedDict):
    decision: str
    reason: str
    now_passing: list[str]
    regressions: list[str]
    fix_touched_files: list[str]
    overlap: list[str]


# ``@final`` lets mypy tell a history row's result apart by ``"overlap" in row["result"]``.
@final
class FinalResult(TypedDict):
    fixed: list[str]
    regressions: list[str]


class HistoryRow(TypedDict):
    failing_in: list[str]
    now_passing: list[str]
    still_failing: list[str]
    warnings: list[str]
    regressions: list[str]
    dispatch_count: int
    elapsed_s: int


class IterationRow(HistoryRow):
    iteration: int
    attempted_fixes: list[str]
    fix_results: dict[str, str | None]
    result: IterationResult


class FinalRow(HistoryRow):
    iteration: Literal["Final"]
    result: FinalResult


class PersistentState(TypedDict):
    """Kept across runs of one plan (idempotency ``reuse`` and ``adopt``); the rest is reset by ``run start``."""

    created: str
    scenario_issues: dict[str, list[str]]
    issue_assertion: dict[str, str]
    scenario_kind: dict[str, str]
    scenario_reason: dict[str, str]
    unverified_issues: list[str]
    need_info: dict[str, Gap]
    auto_generated: bool


class SidecarState(PersistentState):
    plan_sha256: str
    plan_path: str
    report_file: str
    topic: str
    run_id: str
    baseline: dict[str, str]
    current: dict[str, str]
    assertions: dict[str, AssertionRecord]
    pre_loop_dirty: list[str]
    pre_loop: Fingerprints
    fix_touched_files: list[str]
    dispatch_count: int
    dispatches: dict[str, TesterDispatch | FixDispatch]
    iteration: int
    open_iteration: OpenIteration | None
    loop_end: LoopEnd | None
    iterations: list[IterationRow | FinalRow]


class RunRecord(TypedDict):
    """The private ``run.json``; ``config`` is the masked effective config ``config.py`` validated."""

    run_id: str
    repo: str
    plan: str
    plan_sha256: str
    started: float
    sidecar: str
    report: str
    config: JSON
    config_hash: str
    trust_hash: str
    origins: list[str]
    locks: str
    pre_loop: Fingerprints
    bootstrap_dirty: list[str]
    services_up: NotRequired[bool]


def _conforms(value: object, schema: type[T]) -> TypeGuard[T]:
    """Whether loaded JSON has exactly the shape a schema class or alias declares."""
    return _matches(value, schema)


def _matches(value: object, hint: object) -> bool:
    if hint is Any:
        return True
    if is_typeddict(hint):
        fields = _fields(hint)
        return (
            isinstance(value, dict) and value.keys() <= fields.keys()
            and all(name in value for name, (_, required) in fields.items() if required)
            and all(_matches(item, fields[name][0]) for name, item in value.items())
        )
    origin, args = get_origin(hint), get_args(hint)
    if origin is Union or origin is UnionType:
        return any(_matches(value, option) for option in args)
    if origin is Literal:
        return any(type(value) is type(option) and value == option for option in args)
    if origin is list:
        return isinstance(value, list) and all(_matches(item, args[0]) for item in value)
    if origin is dict:
        return isinstance(value, dict) and all(_matches(key, args[0]) and _matches(item, args[1]) for key, item in value.items())
    if hint is float:
        return type(value) in {int, float}
    # Exact types: a JSON boolean is not a count, and hints spell ``None`` as ``NoneType``.
    return type(value) is hint


@cache
def _fields(schema: object) -> dict[str, tuple[object, bool]]:
    """A TypedDict's keys, each with its value type and whether it is required."""
    fields: dict[str, tuple[object, bool]] = {}
    # ``__required_keys__`` misses ``NotRequired`` under postponed annotations, so read the hints.
    for name, hint in get_type_hints(schema, include_extras=True).items():
        optional = get_origin(hint) is NotRequired
        fields[name] = (get_args(hint)[0] if optional else hint, not optional)
    return fields


