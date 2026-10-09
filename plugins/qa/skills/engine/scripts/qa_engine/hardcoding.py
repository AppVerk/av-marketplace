"""Anti-hardcoding warnings derived from added request-payload literals."""
from __future__ import annotations

from collections.abc import Iterator
import json
import re

from qa_engine.assertions import _scenario_of
from qa_engine.git import _dirty
from qa_engine.git import _git
from qa_engine.models import Run
from qa_engine.plan import FIELD
from qa_engine.plan import TOKEN
from qa_engine.plan import Scenario
from qa_engine.plan import run_plan
from qa_engine.schema import FixDispatch

CODE_FENCE = re.compile(r"^[ \t]*(?:`{3,}|~{3,}).*$", re.MULTILINE)
LITERAL = re.compile(r'"((?:[^"\\\n]|\\.)*)"|\'((?:[^\'\\\n]|\\.)*)\'|`([^`\n]*)`')
PAYLOAD_FIELDS = frozenset({"payload", "request payload", "body", "request body"})


def _hardcoding_warnings(run: Run, record: FixDispatch) -> list[str]:
    """Anti-hardcoding check: added string literals equal to a request-payload value of the issue's BE scenario."""
    scenarios = {scenario.id: scenario for scenario in run_plan(run).scenarios}
    scenario = scenarios.get(_scenario_of(record["key"]))
    if scenario is None or scenario.section != "BE":
        return []
    values = _payload_values(scenario)
    if not values:
        return []
    before: dict[str, str] = record["dirty_before"]
    now = _dirty(run.repo)
    touched = ({path for path in now if before.get(path) != now[path]} | {path for path in before if path not in now}) - run.artifacts()
    if not touched:
        return []
    literals: set[str] = set()
    for line in _git(run.repo, "diff", "--unified=0", "HEAD", "--", *sorted(touched)).splitlines():
        if line.startswith("+") and not line.startswith("+++"):
            literals.update(first or second or third for first, second, third in LITERAL.findall(line[1:]))

    return [
        f"{record['qa']}: Possible hardcoding: added literal matches scenario request-payload value {json.dumps(value)}"
        for value in sorted(literals & values)
    ]


def _payload_values(scenario: Scenario) -> set[str]:
    """String values of the main flow's payload field; placeholders never count."""
    text = scenario.main_flow
    matches = list(FIELD.finditer(text))
    values: set[str] = set()
    for index, match in enumerate(matches):
        if match.group(1).strip().lower() not in PAYLOAD_FIELDS:
            continue
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        content = CODE_FENCE.sub("", text[match.start(2):end]).strip().strip("`").strip()
        try:
            values.update(_json_strings(json.loads(content)))
        except ValueError:
            values.update(first or second or third for first, second, third in LITERAL.findall(content))
    return {value for value in values if value and not TOKEN.search(value)}


def _json_strings(value: object) -> Iterator[str]:
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for item in value.values():
            yield from _json_strings(item)
    elif isinstance(value, list):
        for item in value:
            yield from _json_strings(item)


