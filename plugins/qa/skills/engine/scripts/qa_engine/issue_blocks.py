"""QA report issue fields, location parsing and block boundaries."""
from __future__ import annotations

from dataclasses import dataclass
import re

from qa_engine.common import ISSUE_HEADING
from qa_engine.common import report_blocks
from qa_engine.common import report_field

SCENARIO_REFERENCE = re.compile(r"\b(?:FE|BE)-\d{2,}\b")
EXPECTED_LINE = re.compile(r"^[ \t]*[-*][ \t]*(?:\*\*Expected:\*\*|Expected:)[ \t]*(.+)$", re.MULTILINE)
LOCATION = re.compile(r"\S+:\d+(?:-\d+)?\Z")


@dataclass
class IssueBlock:
    """The fields of one ``### [SEVERITY] QA-NNN`` report block the loop reads."""

    severity: str
    status: str | None
    location: str | None
    problem: bool
    remediation: bool
    scenario: str | None
    expected: str | None

    @property
    def rejected(self) -> bool:
        # Prefix match: a rejected Status carries a reason tail we do not control.
        return self.status is not None and self.status.startswith("🚫 Rejected")

    @property
    def located(self) -> bool:
        return self.location is not None and self.location != "unknown:0" and bool(LOCATION.fullmatch(self.location))


def _issue_blocks(text: str) -> dict[str, IssueBlock]:
    """Parse issue blocks the way fix and fix-report bound them; the first block of an ID wins."""
    blocks: dict[str, IssueBlock] = {}
    for qa, body in report_blocks(text).items():
        match = ISSUE_HEADING.match(body)
        assert match is not None
        scenario = report_field(body, "Scenario")
        reference = SCENARIO_REFERENCE.search(scenario) if scenario else None
        expected = EXPECTED_LINE.search(body)
        blocks[qa] = IssueBlock(
            severity=match.group(1).upper(), status=report_field(body, "Status"), location=_location(report_field(body, "Location")),
            problem=report_field(body, "Problem") is not None, remediation=report_field(body, "Remediation") is not None,
            scenario=reference.group(0) if reference else None, expected=expected.group(1).strip() if expected else None,
        )
    return blocks


def _location(value: str | None) -> str | None:
    """Two-clause read rule: the first backticked token, else the first bare token."""
    if value is None:
        return None
    backticked = re.search(r"`([^`]*)`", value)
    if backticked:
        return backticked.group(1).strip()
    tokens = value.split()
    return tokens[0] if tokens else None


