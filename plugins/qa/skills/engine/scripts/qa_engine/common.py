"""Shared QA report grammar, assertion identities and artifact serialization."""
from __future__ import annotations

from collections.abc import Iterator
import json
from pathlib import Path
import re
from typing import TYPE_CHECKING
from typing import Any
from urllib.parse import urlsplit

from av_config.errors import ConfigError
from av_config.errors import InvalidConfig
from av_config.files import atomic_write
from av_config.origins import Origin

if TYPE_CHECKING:
    from qa_engine.plan import Assertion
    from qa_engine.plan import Plan
    from qa_engine.plan import Scenario

ISSUE_ID = re.compile(r"QA-\d{3,}\Z")
ISSUE_NUMBER = re.compile(r"\bQA-(\d{3,})\b")
ISSUE_HEADING = re.compile(r"^###[ \t]+\[([A-Za-z]+)\][ \t]+(QA-\d{3,})\b.*$", re.MULTILINE)
HEADING_ISSUE = re.compile(r"^###[^\n]*?\b(QA-\d{3,})\b", re.MULTILINE)
BLOCK_END = re.compile(r"^(?:#{1,3}[ \t]|---[ \t]*$)", re.MULTILINE)
LOOP_HISTORY = re.compile(r"^##[ \t]+Loop History[ \t]*$(.*?)(?=^##[ \t]|\Z)", re.MULTILINE | re.DOTALL)
REPORT_FIELD = re.compile(r"^(?:[-*][ \t]*)?\*\*(?P<name>[\w-]+):\*\*[ \t]*(?P<value>[^\n]*)$", re.MULTILINE)
METADATA_FIELDS = frozenset({"Status", "Location", "Decision", "Decision-retired", "Verification-plan", "Decision-pin", "Dispatch", "Verification"})
SEVERITIES = ("LOW", "MEDIUM", "HIGH", "CRITICAL")
ASSERTION_KEY = re.compile(r"((?:FE|BE)-\d{2,})(?: \(edge ([1-9]\d*)\))?\Z")


def report_blocks(text: str) -> dict[str, str]:
    """Return full issue blocks in report order; the first occurrence of an ID wins."""
    blocks: dict[str, str] = {}
    for match in ISSUE_HEADING.finditer(text):
        end = BLOCK_END.search(text, match.end())
        blocks.setdefault(match[2], text[match.start():end.start() if end else len(text)].rstrip())
    return blocks


def report_header(block: str) -> str:
    """Bound carried metadata before Category, accepting the report's bullet form."""
    for match in REPORT_FIELD.finditer(block):
        if match["name"] == "Category":
            return block[:match.start()]
    return block


def report_fields(block: str) -> Iterator[tuple[str, str, str]]:
    """Yield field name, trimmed value and original line, preserving their order."""
    for match in REPORT_FIELD.finditer(block):
        yield match["name"], match["value"].strip(), match[0]


def report_field(block: str, name: str) -> str | None:
    """Read metadata only from the header, and issue prose fields from the full block."""
    source = report_header(block) if name in METADATA_FIELDS else block
    return next((value for field, value, _ in report_fields(source) if field == name), None)


def assertion_keys(scenario: Scenario) -> list[str]:
    return [scenario.id, *(f"{scenario.id} (edge {number})" for number in range(1, len(scenario.edges) + 1))]


def assertion_for(scenario: Scenario, key: str) -> Assertion:
    """Resolve a main or edge key, rejecting identities outside this scenario."""
    match = ASSERTION_KEY.fullmatch(key)
    if match is not None and match[1] == scenario.id:
        if match[2] is None:
            return scenario.expected
        number = int(match[2])
        if number <= len(scenario.edges):
            return scenario.edges[number - 1]
    raise InvalidConfig("issues: assertion is not in the run's plan")


def plan_assertion(plan: Plan, key: str) -> tuple[Scenario, Assertion]:
    match = ASSERTION_KEY.fullmatch(key)
    if match is not None:
        for scenario in plan.scenarios:
            if scenario.id == match[1]:
                return scenario, assertion_for(scenario, key)
    raise InvalidConfig("issues: assertion is not in the run's plan")


def format_origin(origin: Origin) -> str:
    """Serialize an origin with an explicit port and bracketed IPv6 host."""
    scheme, host, port = origin
    host = f"[{host}]" if ":" in host else host
    return f"{scheme.lower()}://{host.lower()}:{port}"


def origin_display(url: str) -> str | None:
    """Describe even a refused URL without reflecting userinfo or payloads."""
    try:
        parts = urlsplit(url)
        host = parts.hostname
        if not host:
            return None
        port = parts.port if parts.port is not None else (443 if parts.scheme.lower() == "https" else 80)
    except ValueError:
        return None
    return format_origin((parts.scheme, host, port))


def read_object(path: Path) -> dict[str, Any]:
    """Read private JSON objects; absence is empty, malformed state fails closed."""
    try:
        data = json.loads(path.read_text())
    except FileNotFoundError:
        return {}
    except (OSError, UnicodeError, ValueError) as error:
        raise ConfigError(f"{path.name}: private state unavailable") from error
    if not isinstance(data, dict):
        raise ConfigError(f"{path.name}: invalid private state")
    return data


def write_json(path: Path, value: object, mode: int | None = None) -> None:
    """Atomically persist JSON, preserving permissions unless explicitly supplied."""
    atomic_write(path, (json.dumps(value, indent=2, ensure_ascii=False) + "\n").encode(), mode)
