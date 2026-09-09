#!/usr/bin/env python3
"""Check that the /superutils:spec-review contract vocabulary agrees across
the command, its two skills, its three agents, the acceptance protocol and the
user docs.

Required tokens must appear verbatim; forbidden tokens (the vocabulary the
2.0.0 triage pipeline deleted) must not. The README check is scoped to the
superutils row of the "Available Plugins" table.

Usage: python3 plugins/superutils/tests/check_contract.py [--file KEY]
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PLUGIN = ROOT / "plugins" / "superutils"

FILES: dict[str, Path] = {
    "cmd": PLUGIN / "commands" / "spec-review.md",
    "cat": PLUGIN / "skills" / "lens-catalog" / "SKILL.md",
    "fmt": PLUGIN / "skills" / "spec-report-format" / "SKILL.md",
    "rev": PLUGIN / "agents" / "spec-reviewer.md",
    "chl": PLUGIN / "agents" / "spec-challenger.md",
    "fix": PLUGIN / "agents" / "spec-fixer.md",
    "acc": PLUGIN / "tests" / "ACCEPTANCE.md",
    "doc": ROOT / "docs" / "plugins" / "superutils.md",
    "wf": ROOT / "docs" / "workflow.md",
    "readme": ROOT / "README.md",
}

FLAGS = ["--no-approve", "--auto", "--allow-dirty", "--max-dispatches", "--time-budget"]
OUTCOMES = [
    "`applied`",
    "`applied (not re-reviewed)`",
    "`fix-failed`",
    "`refuted`",
    "`reported-only`",
    "`accepted-risk`",
    "`pending-decision`",
    "`declined`",
    "`confirmed (not fixed — stopped)`",
]
STATUSES = [
    "`TRIAGED`",
    "`TRIAGED (incomplete)`",
    "STOPPED(user-declined | budget | interaction-unavailable | external-edit)",
]
DELETED = [
    "CONVERGED",
    "--max-iterations",
    "unlanded",
    "unconfirmed",
    "fix_failures",
    "obsolete",
    "no-progress",
    "oscillation",
    "last_written_hash",
]

REQUIRED: dict[str, list[str]] = {
    "cmd": FLAGS + OUTCOMES + STATUSES + [
        "re-derive", "re-fix", "fix-coherence", "Outcomes at a stop",
        "Re-reviewed (advisory)", "Not re-reviewed (verifier not returned)",
        "post-loop", "sr_ids", "Empty batch", "run<N>.bak", "| 20 |", "| 900 |",
    ],
    "cat": ["fix-coherence", "does not arbitrate", "No cap"],
    "fmt": OUTCOMES + STATUSES + [
        "sr_ids", '"growth"', "fix_induced", "introduced_by", '"resolved"',
        "post-loop", "Panel reviewers never emit SR ids", "SR-001",
        "re-derive", "re-fix",
    ],
    "rev": ["fix-coherence", "echo"],
    "chl": ["critical"],
    "fix": ["sr_ids", "growth", "re-derive", "re-fix", "Rewrite before append"],
    "acc": ["`TRIAGED`"],
    "doc": FLAGS + STATUSES + ["**Version:** 2.0.0", "Honest limits", "| 20 |", "| 900 |"],
    "wf": ["`TRIAGED`"],
    "readme": ["2.0.0", "triage"],
}

FORBIDDEN: dict[str, list[str]] = {key: list(DELETED) for key in FILES}
for key in ("fmt", "rev", "chl", "fix", "acc", "wf"):
    FORBIDDEN[key].append("sidecar")
# The lens catalog quotes the qa:loop-engineering bar verbatim (items 7 and 10 name
# no-progress, oscillation and the durable sidecar); that copy is untouched by design,
# so only the catalog's own panel-selection prose is checked for the sidecar.
FORBIDDEN["cat"] = [tok for tok in DELETED if tok not in ("no-progress", "oscillation")]
FORBIDDEN["cat"] += ["Cap at 6", "logged in the sidecar"]
FORBIDDEN["readme"] += ["sidecar", "convergence", "quorum"]


def haystack(key: str) -> str:
    text = FILES[key].read_text(encoding="utf-8")
    if key != "readme":
        return text
    rows = [line for line in text.splitlines() if "[Superutils](docs/plugins/superutils.md)" in line]
    return "\n".join(rows)


def check(key: str) -> list[str]:
    text = haystack(key)
    problems = [f"{key}: missing '{tok}'" for tok in REQUIRED.get(key, []) if tok not in text]
    problems += [f"{key}: forbidden '{tok}' found" for tok in FORBIDDEN.get(key, []) if tok in text]
    return problems


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--file", choices=sorted(FILES), help="check one file only")
    args = parser.parse_args(argv)
    keys = [args.file] if args.file else list(FILES)
    problems: list[str] = []
    for key in keys:
        if not FILES[key].exists():
            problems.append(f"{key}: file not found: {FILES[key]}")
            continue
        problems += check(key)
    for line in problems:
        print(line)
    if problems:
        print(f"Contract violations: {len(problems)}")
        return 1
    print(f"Contract OK: {len(keys)} file(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
