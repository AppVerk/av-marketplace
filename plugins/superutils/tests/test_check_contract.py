#!/usr/bin/env python3
"""Unit tests for check_contract.

Run: python3 plugins/superutils/tests/test_check_contract.py
     python3 -m unittest plugins/superutils/tests/test_check_contract.py -v

The checker resolves its targets from `__file__`, so the fixture trees here
point `check_contract.FILES` at a temp dir through `mock.patch.dict` rather
than patching ROOT: the relative layout is read back off the real map, so a
new contract file is picked up by these tests the moment it is added to FILES.
"""

from __future__ import annotations

import contextlib
import io
import re
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))

import check_contract
from check_contract import (
    DELETED,
    FILES,
    FORBIDDEN,
    REQUIRED,
    ROOT,
    check,
    haystack,
    main,
)

# Every FILES path is inside ROOT, so the whole map can be re-rooted at a temp
# dir without restating any of it.
RELATIVE = {key: path.relative_to(ROOT) for key, path in FILES.items()}

README_LINK = "[Superutils](docs/plugins/superutils.md)"

# A forbidden token that stays stable across the rest of this fix batch. One of
# the pending fixes narrows `obsolete` to its backticked form, so no test here
# seeds or asserts the bare word.
STABLE_FORBIDDEN = "CONVERGED"

# The catalog quotes the qa:loop-engineering bar verbatim, so two DELETED
# tokens are exempt there by design. Asserted below so the exemption cannot
# quietly grow.
CAT_EXEMPTIONS = {"no-progress", "oscillation"}

# The doc's "Upgrade Notes" section names the flag 2.0.0 removed and the status
# it renamed away, so those two DELETED tokens are exempt there by design.
DOC_EXEMPTIONS = {"CONVERGED", "--max-iterations"}

# REQUIRED tokens deliberately left as a bare word, with the reason each is
# safe. The first cut of the checker guarded the reviewer agent with `echo` and
# the challenger with `critical`; both matched prose anywhere in the file and
# so guarded nothing. Anything else bare has to be argued for here.
BARE_WORD_EXEMPTIONS = {
    ("fix", "growth"): "a sidecar field name inside the fixer's own contract",
    ("readme", "triage"): "the README haystack is the single superutils row",
}

# Heading, numbered-step and table-cell tokens: structural anchors that name one
# passage each.
STRUCTURAL_TOKEN = re.compile(r"^(#{2,} |\d+\. \*\*|\| )")


def _readme(row_tokens, *, other_rows=()) -> str:
    """A minimal 'Available Plugins' table whose superutils row carries the tokens."""
    row = f"| {README_LINK} | " + " ".join(row_tokens) + " |"
    return "\n".join(
        [
            "| Plugin | Description |",
            "|---|---|",
            "| [Other](docs/plugins/other.md) | Something unrelated |",
            row,
            *other_rows,
        ]
    ) + "\n"


def _readme_without_the_row() -> str:
    return "| Plugin | Description |\n|---|---|\n| [Other](docs/plugins/other.md) | x |\n"


def _body(key: str, *, drop: str | None = None, add: str | None = None) -> str:
    """The smallest text that satisfies `key`, optionally mutated.

    `drop` removes the token *and every token containing it*, so that a token
    nested inside a longer one (`Outcomes at a stop` inside `## Outcomes at a
    stop`) is really absent from the result.
    """
    tokens = [
        tok for tok in REQUIRED[key] if drop is None or (tok != drop and drop not in tok)
    ]
    if add is not None:
        tokens.append(add)
    if key == "readme":
        # Sound only while the README tokens are single-line; asserted below.
        return _readme(tokens)
    return "\n\n".join(tokens) + "\n"


@contextlib.contextmanager
def _tree(overrides=None, *, omit=()):
    """Materialise a passing fixture tree in a temp dir and point FILES at it."""
    overrides = overrides or {}
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        mapping = {key: root / rel for key, rel in RELATIVE.items()}
        for key, target in mapping.items():
            if key in omit:
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(overrides.get(key, _body(key)), encoding="utf-8")
        with mock.patch.dict(check_contract.FILES, mapping, clear=True):
            yield root


def _run(argv=None, **tree_kwargs) -> tuple[int, str]:
    """Run main() against a fixture tree; return (exit code, printed output)."""
    with _tree(**tree_kwargs):
        stream = io.StringIO()
        with contextlib.redirect_stdout(stream), contextlib.redirect_stderr(stream):
            code = main([] if argv is None else argv)
        return code, stream.getvalue()


def _check_one(key: str, text: str) -> list[str]:
    """Run check() for one key over one supplied file body."""
    with _tree(overrides={key: text}):
        return check(key)


class TestMaps(unittest.TestCase):
    """The three maps are the whole contract; nothing else pins their shape."""

    def test_required_covers_every_file(self):
        # A file listed in FILES with no REQUIRED entry is checked for the
        # forbidden vocabulary only — a silent half-check.
        self.assertEqual(set(REQUIRED), set(FILES))

    def test_forbidden_covers_every_file(self):
        self.assertEqual(set(FORBIDDEN), set(FILES))

    def test_every_deleted_token_is_forbidden_everywhere_but_the_catalog(self):
        exemptions = {"cat": CAT_EXEMPTIONS, "doc": DOC_EXEMPTIONS}
        for key in FILES:
            exempt = exemptions.get(key, set())
            expected = set(DELETED) - exempt
            with self.subTest(key=key):
                self.assertLessEqual(expected, set(FORBIDDEN[key]))
                # Exact, not merely sufficient: neither exemption may grow.
                self.assertEqual(set(DELETED) - set(FORBIDDEN[key]), exempt)

    def test_the_catalog_exemption_is_exactly_the_quoted_pair(self):
        self.assertEqual(set(DELETED) - set(FORBIDDEN["cat"]), CAT_EXEMPTIONS)

    def test_no_required_token_contains_a_forbidden_one(self):
        # Substring, not equality: FORBIDDEN is matched with `in`, so a
        # forbidden token nested inside a required one makes the file
        # unsatisfiable — every tree fails, whatever the sources say.
        for key in FILES:
            for required in REQUIRED[key]:
                for forbidden in FORBIDDEN[key]:
                    with self.subTest(key=key, required=required, forbidden=forbidden):
                        self.assertNotIn(forbidden, required)

    def test_required_tokens_are_specific_enough_to_guard_a_passage(self):
        for key, tokens in REQUIRED.items():
            for tok in tokens:
                if not re.fullmatch(r"[A-Za-z]+", tok):
                    continue
                with self.subTest(key=key, token=tok):
                    self.assertIn(
                        (key, tok),
                        BARE_WORD_EXEMPTIONS,
                        f"bare word {tok!r} guards {key} but matches any prose; "
                        "quote the phrase it belongs to, or document it in "
                        "BARE_WORD_EXEMPTIONS",
                    )

    def test_readme_tokens_stay_single_line(self):
        # _body() lays the README tokens out on one table row; a multi-line
        # token there would build a fixture the checker could never satisfy.
        for tok in REQUIRED["readme"]:
            self.assertNotIn("\n", tok)


class TestCheck(unittest.TestCase):
    """check() is where a mutation has to be caught, one file at a time."""

    def test_a_satisfying_file_reports_nothing(self):
        for key in FILES:
            with self.subTest(key=key):
                self.assertEqual(_check_one(key, _body(key)), [])

    def test_every_required_token_is_caught_when_missing(self):
        for key, tokens in REQUIRED.items():
            for tok in tokens:
                with self.subTest(key=key, token=tok):
                    problems = _check_one(key, _body(key, drop=tok))
                    self.assertIn(f"{key}: missing '{tok}'", problems)

    def test_every_forbidden_token_is_caught_when_present(self):
        for key, tokens in FORBIDDEN.items():
            for tok in tokens:
                with self.subTest(key=key, token=tok):
                    problems = _check_one(key, _body(key, add=tok))
                    self.assertIn(f"{key}: forbidden '{tok}' found", problems)

    def test_the_catalog_still_admits_its_quoted_pair(self):
        # The other side of both exemptions — the catalog's quoted pair and the
        # doc's upgrade-note pair: these must *not* be reported.
        for key, exempt in (("cat", CAT_EXEMPTIONS), ("doc", DOC_EXEMPTIONS)):
            for tok in sorted(exempt):
                with self.subTest(key=key, token=tok):
                    self.assertEqual(_check_one(key, _body(key, add=tok)), [])


class TestReadmeScoping(unittest.TestCase):
    """The README haystack is one table row, not the whole file."""

    def test_the_haystack_keeps_only_the_superutils_row(self):
        text = _readme(REQUIRED["readme"], other_rows=("| [X](x.md) | quorum |",))
        with _tree(overrides={"readme": text}):
            scoped = haystack("readme")
        self.assertIn(README_LINK, scoped)
        self.assertNotIn("quorum", scoped)
        self.assertNotIn("Something unrelated", scoped)

    def test_a_forbidden_token_in_another_row_is_not_a_violation(self):
        other = f"| [X](docs/plugins/x.md) | {STABLE_FORBIDDEN} sidecar quorum |"
        text = _readme(REQUIRED["readme"], other_rows=(other,))
        self.assertEqual(_check_one("readme", text), [])

    def test_a_forbidden_token_in_the_superutils_row_is_a_violation(self):
        problems = _check_one("readme", _body("readme", add="quorum"))
        self.assertEqual(problems, ["readme: forbidden 'quorum' found"])

    def test_a_required_token_outside_the_row_does_not_count(self):
        other = f"| [X](docs/plugins/x.md) | {' '.join(REQUIRED['readme'])} |"
        text = _readme([], other_rows=(other,))
        problems = _check_one("readme", text)
        self.assertEqual(
            problems, [f"readme: missing '{tok}'" for tok in REQUIRED["readme"]]
        )

    def test_a_readme_with_no_superutils_row_fails(self):
        # Exit code only; the diagnostic text is asserted below.
        code, _ = _run(overrides={"readme": _readme_without_the_row()})
        self.assertEqual(code, 1)

    def test_a_readme_with_no_superutils_row_reports_row_not_found(self):
        # An empty haystack must name the real cause, not surface as a pile of
        # "missing '<token>'" lines that point at the wrong root cause.
        problems = _check_one("readme", _readme_without_the_row())
        self.assertEqual(
            problems,
            ["readme: Superutils row not found in the Available Plugins table"],
        )
        self.assertNotIn("readme: missing 'triage'", problems)


class TestMain(unittest.TestCase):
    """main() drives the exit code CI reads."""

    def test_a_clean_tree_passes(self):
        code, output = _run()
        self.assertEqual(code, 0)
        self.assertIn(f"Contract OK: {len(FILES)} file(s)", output)

    def test_a_seeded_missing_token_fails_the_run(self):
        code, output = _run(overrides={"cmd": _body("cmd", drop="--no-approve")})
        self.assertEqual(code, 1)
        self.assertIn("cmd: missing '--no-approve'", output)
        self.assertIn("Contract violations: 1", output)

    def test_removing_the_seeded_mutation_restores_the_pass(self):
        # Paired with the test above: a checker never seen to go red and then
        # green again on one edit has proved nothing.
        code, output = _run()
        self.assertEqual(code, 0)
        self.assertNotIn("missing", output)

    def test_a_seeded_forbidden_token_fails_the_run(self):
        code, output = _run(overrides={"fmt": _body("fmt", add=STABLE_FORBIDDEN)})
        self.assertEqual(code, 1)
        self.assertIn(f"fmt: forbidden '{STABLE_FORBIDDEN}' found", output)

    def test_the_violation_count_is_the_number_of_problems(self):
        code, output = _run(
            overrides={
                "cmd": _body("cmd", drop="--auto", add=STABLE_FORBIDDEN),
                "wf": _body("wf", drop="triage pipeline"),
            }
        )
        self.assertEqual(code, 1)
        self.assertIn("Contract violations: 3", output)

    def test_a_missing_file_is_reported_not_raised(self):
        code, output = _run(omit=("doc",))
        self.assertEqual(code, 1)
        self.assertIn("doc: file not found", output)

    def test_a_missing_file_does_not_stop_the_other_checks(self):
        code, output = _run(
            omit=("doc",), overrides={"wf": _body("wf", drop="nothing repeats")}
        )
        self.assertEqual(code, 1)
        self.assertIn("doc: file not found", output)
        self.assertIn("wf: missing 'nothing repeats'", output)

    def test_the_file_filter_checks_one_file_only(self):
        code, output = _run(
            argv=["--file", "cmd"], overrides={"fmt": "nothing the contract wants\n"}
        )
        self.assertEqual(code, 0)
        self.assertIn("Contract OK: 1 file(s)", output)

    def test_the_file_filter_still_reports_that_file(self):
        code, output = _run(
            argv=["--file", "fmt"], overrides={"fmt": "nothing the contract wants\n"}
        )
        self.assertEqual(code, 1)
        self.assertIn("fmt: missing", output)

    def test_every_file_key_is_selectable(self):
        for key in FILES:
            with self.subTest(key=key):
                code, output = _run(argv=["--file", key])
                self.assertEqual(code, 0)
                self.assertIn("Contract OK: 1 file(s)", output)

    def test_an_unknown_file_key_is_rejected(self):
        with self.assertRaises(SystemExit) as caught:
            _run(argv=["--file", "nope"])
        self.assertEqual(caught.exception.code, 2)

    def test_argv_defaults_to_the_command_line(self):
        # main(None) means "read sys.argv"; the CI step passes no arguments.
        with _tree():
            stream = io.StringIO()
            with mock.patch.object(sys, "argv", ["check_contract.py", "--file", "acc"]):
                with contextlib.redirect_stdout(stream):
                    code = main(None)
        self.assertEqual(code, 0)
        self.assertIn("Contract OK: 1 file(s)", stream.getvalue())


class TestRealTree(unittest.TestCase):
    """The repository's own contract, checked with the same code CI runs."""

    def test_the_repository_tree_passes(self):
        stream = io.StringIO()
        with contextlib.redirect_stdout(stream):
            code = main([])
        self.assertEqual(code, 0, stream.getvalue())
        self.assertIn(f"Contract OK: {len(FILES)} file(s)", stream.getvalue())

    def test_every_contract_file_exists(self):
        for key, path in FILES.items():
            with self.subTest(key=key):
                self.assertTrue(path.is_file(), f"{key}: {path}")

    def test_structural_anchors_name_exactly_one_passage(self):
        # Headings, numbered steps and table cells are the tokens whose whole
        # job is to point at one place. Two `### Stage 3` headings, or a second
        # `| 20 |` row, and the token stops guarding what it names.
        for key, tokens in REQUIRED.items():
            text = haystack(key)
            for tok in tokens:
                if not STRUCTURAL_TOKEN.match(tok):
                    continue
                with self.subTest(key=key, token=tok):
                    self.assertEqual(text.count(tok), 1)


if __name__ == "__main__":
    unittest.main()
