#!/usr/bin/env python3
"""Test the Delivery/QA stop-message contract checker.

Run: python3 scripts/test_check_delivery_qa_contract.py
"""

from __future__ import annotations

import contextlib
import io
import tempfile
import unittest
from pathlib import Path

from check_delivery_qa_contract import main


STOP_MESSAGE = "Generated plan has no executable FE or BE scenarios"
SOURCES = {
    "plugins/qa/commands/run.md": (
        f"> {STOP_MESSAGE} — nothing to test; not launching testers.\n"
    ),
    "plugins/delivery/skills/orchestration/SKILL.md": (
        f"- stopped with the `{STOP_MESSAGE}` message → `Nothing to test`.\n"
    ),
    "omp/native/delivery/skills/orchestration/SKILL.md": (
        f"- stopped with the `{STOP_MESSAGE}` message → `Nothing to test`.\n"
    ),
}


class DeliveryQaContractTest(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        for relative, text in SOURCES.items():
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8")

    def run_check(self, args: list[str]) -> tuple[int, str, str]:
        stdout = io.StringIO()
        stderr = io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            code = main(args, root=self.root)
        return code, stdout.getvalue(), stderr.getvalue()

    def test_matching_producer_and_consumers_pass(self) -> None:
        code, _, stderr = self.run_check([])
        self.assertEqual(code, 0)
        self.assertEqual(stderr, "")

    def test_wording_drift_in_each_source_fails_and_names_the_path(self) -> None:
        for relative, text in SOURCES.items():
            with self.subTest(source=relative):
                path = self.root / relative
                path.write_text(text.replace(STOP_MESSAGE, "No scenarios"), encoding="utf-8")
                try:
                    code, _, stderr = self.run_check([])
                    self.assertEqual(code, 1)
                    self.assertIn(relative, stderr)
                    self.assertIn(STOP_MESSAGE, stderr)
                finally:
                    path.write_text(text, encoding="utf-8")

    def test_unrelated_explanation_can_change(self) -> None:
        path = self.root / "plugins/qa/commands/run.md"
        path.write_text(f"> {STOP_MESSAGE} — a revised explanation.\n", encoding="utf-8")
        code, _, stderr = self.run_check([])
        self.assertEqual(code, 0)
        self.assertEqual(stderr, "")

    def test_missing_source_cannot_silently_pass(self) -> None:
        relative = "omp/native/delivery/skills/orchestration/SKILL.md"
        (self.root / relative).unlink()
        code, _, stderr = self.run_check([])
        self.assertEqual(code, 1)
        self.assertIn(relative, stderr)

    def test_invalid_utf8_is_reported_as_failure(self) -> None:
        relative = "plugins/qa/commands/run.md"
        (self.root / relative).write_bytes(b"\xff")
        code, _, stderr = self.run_check([])
        self.assertEqual(code, 1)
        self.assertIn(relative, stderr)

    def test_all_drifting_sources_are_reported(self) -> None:
        for relative in SOURCES:
            (self.root / relative).write_text("No scenarios\n", encoding="utf-8")
        code, _, stderr = self.run_check([])
        self.assertEqual(code, 1)
        for relative in SOURCES:
            self.assertIn(relative, stderr)

    def test_unexpected_arguments_are_not_ignored(self) -> None:
        code, _, stderr = self.run_check(["plugins/qa"])
        self.assertEqual(code, 2)
        self.assertIn("usage:", stderr)


if __name__ == "__main__":
    unittest.main()
