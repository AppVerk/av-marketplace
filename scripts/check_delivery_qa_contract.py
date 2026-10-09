#!/usr/bin/env python3
"""Check the stop-message prefix Delivery uses to classify QA as Nothing to test.

Usage: python3 scripts/check_delivery_qa_contract.py
Exit codes: 0 for parity, 1 for missing/drifting/unreadable sources, 2 for usage.
The message suffix is prose; only the prefix consumed by Delivery is fixed.
"""

from __future__ import annotations

import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
STOP_MESSAGE = "Generated plan has no executable FE or BE scenarios"
CONTRACT_FILES = (
    Path("plugins/qa/commands/run.md"),
    Path("plugins/delivery/skills/orchestration/SKILL.md"),
    Path("omp/native/delivery/skills/orchestration/SKILL.md"),
)


def check(root: Path) -> list[str]:
    """Return every source that no longer contains the shared message prefix."""
    errors: list[str] = []
    for relative in CONTRACT_FILES:
        try:
            text = (root / relative).read_text(encoding="utf-8")
        except (OSError, UnicodeError) as error:
            errors.append(f"{relative.as_posix()}: cannot read UTF-8 source: {error}")
            continue

        if STOP_MESSAGE not in text:
            errors.append(f"{relative.as_posix()}: missing stop-message prefix {STOP_MESSAGE!r}")

    return errors


def main(argv: list[str], root: Path = REPO_ROOT) -> int:
    """Report message drift and return the exit status consumed by CI."""
    if argv:
        print("usage: python3 scripts/check_delivery_qa_contract.py", file=sys.stderr)
        return 2

    errors = check(root)
    if errors:
        print("Delivery/QA stop-message contract FAILED:", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        print(
            "Keep the generated-plan stop prefix and both Delivery consumers in sync.",
            file=sys.stderr,
        )
        return 1

    print(f"Delivery/QA stop-message contract OK: {len(CONTRACT_FILES)} sources checked.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
