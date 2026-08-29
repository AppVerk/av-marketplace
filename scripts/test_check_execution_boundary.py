#!/usr/bin/env python3
"""Unit tests for check_execution_boundary.

Run: python3 scripts/test_check_execution_boundary.py
"""

from __future__ import annotations

import contextlib
import io
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))

from check_execution_boundary import (
    CONSUMER_TOKEN,
    MIN_BOUNDARY_SUBCOMMANDS,
    MIN_BOUNDARY_TOOLS,
    PLUGINS_DIR,
    SKILL_RELPATH,
    SourceError,
    bash_grants,
    check,
    classify_prefix,
    consumer_key,
    grant_prefix,
    main,
    parse_boundary,
    parse_registry,
    section_lines,
    table_rows,
)

SKILL_PATH = str(SKILL_RELPATH)
FIX_ALL = "plugins/code-review/commands/fix-all.md"
FIX_REPORT = "plugins/code-review/commands/fix-report.md"

DEFAULT_BOUNDARY = (
    "- **Read-only inspection** is the `Read`, `Grep` and `Glob` tools plus the "
    "read-only git subcommands `git log`, `git show`, `git diff`, `git blame` "
    "and `git status`, **and nothing else**."
)


def _row(cells) -> str:
    return "| " + " | ".join(cells) + " |"


def _skill(*, boundary: str = DEFAULT_BOUNDARY, scope=(), grants=()) -> str:
    """Build a decision-gate SKILL.md with the two anchored sections.

    `scope` rows are (path, kind, why); `grants` rows are
    (grant, class, [consumer keys], why).
    """
    scope_rows = "\n".join(
        _row([f"`{path}`", kind, why]) for path, kind, why in scope
    )
    grant_rows = "\n".join(
        _row([f"`{grant}`", klass, ", ".join(f"`{c}`" for c in consumers), why])
        for grant, klass, consumers, why in grants
    )
    return f"""---
name: decision-gate
description: The decision stage.
---

# Decision Gate

## Stage 3.5: verification

<a id="execution-boundary"></a>
### The execution boundary — the one term never escalated, defined once

{boundary}

Anything outside that surface is executed only with the user's explicit approval.

<a id="grant-registry"></a>
### The grant registry — every prompt-free `Bash(...)` on a stage-running consumer

Prose about the three classes.

#### Scope — every consumer of this skill, classified

| Consumer | Kind | Why |
|---|---|---|
{scope_rows}

#### Grants — every `Bash(...)` on a runs-the-stage consumer

| Grant | Class | Consumers | Why |
|---|---|---|---|
{grant_rows}

### A refused or unrunnable check is never silently skipped

Trailing section that must not be swallowed by the registry parse.
"""


def _command(allowed_tools: str | None = None, *, mentions: bool = True) -> str:
    lines = ["---"]
    if allowed_tools is not None:
        lines.append(f"allowed-tools: {allowed_tools}")
    lines.append("description: d")
    lines.append("---")
    lines.append("")
    lines.append(
        f"Load `code-review:{CONSUMER_TOKEN}` (Skill tool)."
        if mentions
        else "This command runs the stage-free path."
    )
    return "\n".join(lines) + "\n"


# The smallest tree that passes: the skill classifies itself and one command,
# and the command's single grant is a git subcommand the boundary admits.
def _clean_scope():
    return (
        (SKILL_PATH, "runs-the-stage", "This file."),
        (FIX_ALL, "runs-the-stage", "Runs stages 0 to 3.5."),
    )


def _clean_grants():
    return (("Bash(git log:*)", "inside-boundary", ["fix-all"], "Cited history."),)


class TestSectionLines(unittest.TestCase):
    def test_section_stops_at_the_next_same_level_heading(self):
        lines = section_lines(_skill(scope=_clean_scope(), grants=_clean_grants()), "grant-registry")
        text = "\n".join(lines)
        self.assertIn("Prose about the three classes.", text)
        self.assertNotIn("must not be swallowed", text)

    def test_subsections_stay_inside_their_section(self):
        # The registry's own `####` tables live under a `###` heading. An
        # end-at-any-heading rule reads the section as empty and the parity
        # check then measures nothing at all.
        lines = section_lines(_skill(scope=_clean_scope(), grants=_clean_grants()), "grant-registry")
        text = "\n".join(lines)
        self.assertIn(FIX_ALL, text)
        self.assertIn("Bash(git log:*)", text)

    def test_own_heading_is_not_the_section_end(self):
        lines = section_lines(_skill(), "execution-boundary")
        self.assertIn("Read-only inspection", "\n".join(lines))

    def test_missing_anchor_is_a_source_error(self):
        with self.assertRaises(SourceError) as caught:
            section_lines("# Doc\n\nNo anchors here.\n", "grant-registry")
        self.assertIn("grant-registry", str(caught.exception))

    def test_anchor_must_be_alone_on_its_line(self):
        # A prose mention of the anchor id must not open a section; matching it
        # anywhere on the line would start the parse mid-paragraph.
        text = 'See <a id="grant-registry"></a> below.\n\n### H\n\nbody\n'
        with self.assertRaises(SourceError):
            section_lines(text, "grant-registry")


class TestParseBoundary(unittest.TestCase):
    def test_terms_are_read_from_the_prose(self):
        tools, families = parse_boundary(_skill())
        self.assertEqual(sorted(tools), ["Glob", "Grep", "Read"])
        self.assertEqual(
            sorted(families["git"]), ["blame", "diff", "log", "show", "status"]
        )

    def test_a_reworded_boundary_moves_the_check(self):
        # The whole point of parsing rather than restating: drop `git blame`
        # from the skill and the checker stops admitting it.
        boundary = (
            "- **Read-only inspection** is the `Read`, `Grep` and `Glob` tools "
            "plus the read-only git subcommands `git log`, `git show`, "
            "`git diff`, `git status` and `git ls-files`, **and nothing else**."
        )
        _, families = parse_boundary(_skill(boundary=boundary))
        self.assertNotIn("blame", families["git"])
        self.assertIn("ls-files", families["git"])

    def test_missing_bullet_is_a_source_error(self):
        boundary = "- **Something else entirely** is `Read` and `Grep`."
        with self.assertRaises(SourceError) as caught:
            parse_boundary(_skill(boundary=boundary))
        self.assertIn("Read-only inspection", str(caught.exception))

    def test_too_few_terms_is_a_source_error_not_a_pass(self):
        # A parser that silently returns an empty boundary would admit nothing,
        # turn every inside-boundary row into an error, and look like a real
        # finding. Exit 2 says "I could not read the source" instead.
        boundary = "- **Read-only inspection** is the `Read` tool and `git log`."
        with self.assertRaises(SourceError) as caught:
            parse_boundary(_skill(boundary=boundary))
        message = str(caught.exception)
        self.assertIn(str(MIN_BOUNDARY_TOOLS), message)
        self.assertIn(str(MIN_BOUNDARY_SUBCOMMANDS), message)


class TestTableRows(unittest.TestCase):
    def test_header_and_separator_rows_are_dropped(self):
        rows = table_rows(
            ["| A | B |", "|---|---|", "| x | y |", "not a table"]
        )
        self.assertEqual(rows, [["A", "B"], ["x", "y"]])

    def test_separator_with_alignment_colons_is_dropped(self):
        rows = table_rows(["|:--|--:|", "| x | y |"])
        self.assertEqual(rows, [["x", "y"]])


class TestParseRegistry(unittest.TestCase):
    def test_scope_and_grants_are_told_apart_by_shape(self):
        scope, grants = parse_registry(
            _skill(scope=_clean_scope(), grants=_clean_grants())
        )
        self.assertEqual(scope[FIX_ALL][0], "runs-the-stage")
        self.assertEqual(grants[0]["grant"], "Bash(git log:*)")
        self.assertEqual(grants[0]["consumers"], ["fix-all"])

    def test_unrecognised_classification_is_a_source_error(self):
        # Skipping the row instead would erase the grant from the registry
        # while the parity check still reported success — the exact false pass
        # this file exists to prevent.
        grants = (("Bash(rm:*)", "definitely-fine", ["fix-all"], "why"),)
        with self.assertRaises(SourceError) as caught:
            parse_registry(_skill(scope=_clean_scope(), grants=grants))
        self.assertIn("unrecognised classification", str(caught.exception))

    def test_two_skills_do_not_collide_on_the_shared_SKILL_stem(self):
        # Keyed by stem, every skill in the repo answers to 'SKILL' and a grant
        # row naming it binds to whichever won the dict. Keyed by directory,
        # these two are distinct — this is the case that forced consumer_key.
        scope = _clean_scope() + (
            ("plugins/qa/skills/report-format/SKILL.md", "reference-only", "docs"),
        )
        registry_scope, _ = parse_registry(
            _skill(scope=scope, grants=_clean_grants())
        )
        self.assertEqual(len(registry_scope), 3)

    def test_colliding_short_names_are_a_source_error(self):
        # Same basename in two plugins. Silently letting one shadow the other
        # would bind a grant row to the wrong consumer and still report parity.
        scope = _clean_scope() + (
            ("plugins/qa/commands/fix-all.md", "dispatch-only", "another one"),
        )
        with self.assertRaises(SourceError) as caught:
            parse_registry(_skill(scope=scope, grants=_clean_grants()))
        self.assertIn("share the short name", str(caught.exception))

    def test_empty_registry_is_a_source_error(self):
        with self.assertRaises(SourceError) as caught:
            parse_registry(_skill(scope=(), grants=()))
        self.assertIn("expected at least", str(caught.exception))


class TestConsumerKey(unittest.TestCase):
    def test_a_command_is_keyed_by_its_stem(self):
        self.assertEqual(consumer_key(FIX_ALL), "fix-all")

    def test_a_skill_is_keyed_by_its_directory(self):
        # Every skill file is named SKILL.md, so the stem is never distinctive.
        self.assertEqual(consumer_key(SKILL_PATH), "decision-gate")
        self.assertEqual(
            consumer_key("plugins/qa/skills/report-format/SKILL.md"), "report-format"
        )


class TestGrantPrefix(unittest.TestCase):
    def test_wildcard_suffix_is_stripped_from_the_end(self):
        # check_agent_frontmatter's reader inspects only the first whitespace
        # token, which is why `Bash(git log:*)` is invisible to it. Stripping
        # from the end is what keeps the two-word prefix intact here.
        self.assertEqual(grant_prefix("Bash(git log:*)"), "git log")
        self.assertEqual(grant_prefix("Bash(npm test:*)"), "npm test")
        self.assertEqual(grant_prefix("Bash(git:*)"), "git")

    def test_a_grant_without_a_wildcard_keeps_its_whole_spec(self):
        self.assertEqual(grant_prefix("Bash(git diff --stat)"), "git diff --stat")

    def test_internal_whitespace_is_normalised(self):
        self.assertEqual(grant_prefix("Bash(npm  test:*)"), "npm test")


class TestClassifyPrefix(unittest.TestCase):
    FAMILIES = {"git": frozenset({"log", "show", "diff", "blame", "status"})}

    def test_named_subcommand_is_inside(self):
        self.assertEqual(classify_prefix("git log", self.FAMILIES), (True, None))

    def test_unnamed_subcommand_is_not_inside(self):
        self.assertEqual(classify_prefix("git push", self.FAMILIES), (False, None))

    def test_bare_family_is_over_wide(self):
        self.assertEqual(classify_prefix("git", self.FAMILIES), (False, "git"))

    def test_a_shell_command_is_never_inside_via_a_tool_of_the_same_name(self):
        # The boundary admits the `Grep` tool. `Bash(grep:*)` is not that tool,
        # and reading the tool list as a shell allowlist would wave through
        # every `grep` a finding cared to cite.
        self.assertEqual(classify_prefix("grep", self.FAMILIES), (False, None))

    def test_an_unrelated_family_is_not_over_wide(self):
        self.assertEqual(classify_prefix("pytest", self.FAMILIES), (False, None))


class TestBashGrants(unittest.TestCase):
    def test_only_bash_entries_are_returned(self):
        grants, errors = bash_grants(
            _command("Read, Edit, Bash(git log:*), Task, Bash(npm test:*)")
        )
        self.assertEqual(errors, [])
        self.assertEqual(grants, ["Bash(git log:*)", "Bash(npm test:*)"])

    def test_absent_allowed_tools_is_not_an_error(self):
        # render-only and reference-only consumers legitimately declare none.
        self.assertEqual(bash_grants(_command(None)), ([], []))

    def test_a_file_without_frontmatter_reports_a_parse_error(self):
        _, errors = bash_grants("# Just a document\n")
        self.assertTrue(errors)


class TestCheck(unittest.TestCase):
    def _check(self, *, scope=None, grants=None, consumers=None):
        skill = _skill(
            scope=_clean_scope() if scope is None else scope,
            grants=_clean_grants() if grants is None else grants,
        )
        files = {SKILL_PATH: skill, FIX_ALL: _command("Read, Bash(git log:*)")}
        if consumers:
            files.update(consumers)
        return check(files[SKILL_PATH], files)

    def test_clean_tree_has_no_errors(self):
        errors, warnings = self._check()
        self.assertEqual(errors, [])
        self.assertEqual(warnings, [])

    def test_undeclared_grant_is_an_error(self):
        # The headline invariant: a grant nobody wrote down runs prompt-free.
        errors, _ = self._check(
            consumers={FIX_ALL: _command("Read, Bash(git log:*), Bash(rm:*)")}
        )
        self.assertTrue(any("Bash(rm:*)" in e and "not declared" in e for e in errors))

    def test_stale_registry_row_is_an_error(self):
        # The other direction. Without it the registry rots into a wish list.
        errors, _ = self._check(consumers={FIX_ALL: _command("Read")})
        self.assertTrue(
            any("carries no such grant" in e and "Bash(git log:*)" in e for e in errors)
        )

    def test_unclassified_consumer_is_an_error(self):
        # The discovery blind spot, closed: a third command that starts running
        # the stage cannot go unscanned the way commands go unscanned by
        # check_agent_frontmatter's */agents/*.md glob.
        errors, _ = self._check(
            consumers={FIX_REPORT: _command("Read, Bash(pytest:*)")}
        )
        self.assertTrue(
            any(FIX_REPORT in e and "not classified" in e for e in errors)
        )

    def test_a_file_that_never_mentions_the_skill_needs_no_scope_row(self):
        errors, _ = self._check(
            consumers={
                "plugins/qa/commands/run.md": _command(
                    "Read, Bash(rm:*)", mentions=False
                )
            }
        )
        self.assertEqual(errors, [])

    def test_scope_row_naming_a_missing_file_is_an_error(self):
        scope = _clean_scope() + (
            ("plugins/code-review/commands/gone.md", "render-only", "removed"),
        )
        errors, _ = self._check(scope=scope)
        self.assertTrue(any("does not exist" in e for e in errors))

    def test_grants_on_a_non_stage_consumer_are_out_of_scope(self):
        # /fix loads the render format alone and runs no check under the
        # boundary, so its Bash grants are not this registry's business.
        scope = _clean_scope() + (
            ("plugins/code-review/commands/fix.md", "render-only", "render only"),
        )
        errors, _ = self._check(
            scope=scope,
            consumers={
                "plugins/code-review/commands/fix.md": _command(
                    "Read, Bash(pytest:*)"
                )
            },
        )
        self.assertEqual(errors, [])

    def test_over_wide_wildcard_is_an_error_whatever_its_class(self):
        # A registry row cannot make `git push` acceptable by calling the grant
        # something. The class is the author's claim; this test is the machine's.
        for klass in ("pipeline", "outside-escalates", "inside-boundary"):
            with self.subTest(klass=klass):
                errors, _ = self._check(
                    grants=(("Bash(git:*)", klass, ["fix-all"], "hashing"),),
                    consumers={FIX_ALL: _command("Read, Bash(git:*)")},
                )
                self.assertTrue(
                    any("wildcard over the 'git' family" in e for e in errors)
                )

    def test_over_wide_message_names_the_admitted_subcommands(self):
        errors, _ = self._check(
            grants=(("Bash(git:*)", "pipeline", ["fix-all"], "hashing"),),
            consumers={FIX_ALL: _command("Read, Bash(git:*)")},
        )
        joined = " ".join(errors)
        self.assertIn("blame, diff, log, show, status", joined)
        self.assertIn(FIX_ALL, joined)

    def test_false_inside_boundary_claim_is_an_error(self):
        # The dangerous mislabel: outside dressed up as inside.
        errors, _ = self._check(
            grants=(("Bash(pytest:*)", "inside-boundary", ["fix-all"], "tests"),),
            consumers={FIX_ALL: _command("Read, Bash(pytest:*)")},
        )
        self.assertTrue(
            any("classified 'inside-boundary'" in e and "pytest" in e for e in errors)
        )

    def test_conservative_mislabel_warns_and_does_not_fail(self):
        # inside dressed up as outside only adds an ask, so it warns. Making it
        # an error would punish caution; making it silent would let the count of
        # prompt-free outside-the-boundary grants drift.
        errors, warnings = self._check(
            grants=(("Bash(git log:*)", "pipeline", ["fix-all"], "history"),)
        )
        self.assertEqual(errors, [])
        self.assertTrue(any("is inside the boundary" in w for w in warnings))

    def test_empty_rationale_is_an_error(self):
        errors, _ = self._check(
            grants=(("Bash(git log:*)", "inside-boundary", ["fix-all"], ""),)
        )
        self.assertTrue(any("carries no rationale" in e for e in errors))

    def test_grant_row_naming_an_unknown_consumer_is_an_error(self):
        errors, _ = self._check(
            grants=(("Bash(git log:*)", "inside-boundary", ["fix-all", "ghost"], "h"),)
        )
        self.assertTrue(any("'ghost'" in e for e in errors))

    def test_a_parse_that_yields_no_grants_reports_divergence_not_a_pass(self):
        # The false-pass case, stated as the behaviour that must hold rather
        # than as a floor: if the frontmatter reader ever returns nothing, the
        # registry's rows all turn stale and the run goes red with the paths
        # named. An earlier draft guarded this with a `not actual` floor that
        # raised SourceError — which downgraded a real, answerable divergence
        # to "I could not read the source" and hid this very case.
        scope = ((SKILL_PATH, "runs-the-stage", "This file."),)
        grants = (("Bash(git log:*)", "inside-boundary", ["decision-gate"], "h"),)
        skill = _skill(scope=scope, grants=grants)
        errors, _ = check(skill, {SKILL_PATH: skill})
        self.assertTrue(any("carries no such grant" in e for e in errors))


class _NoArgv:
    pass


_NO_ARGV = _NoArgv()


class TestMain(unittest.TestCase):
    """main() drives the exit code CI reads, so every branch of it is pinned."""

    def _run(self, files, argv=_NO_ARGV) -> tuple[int, str]:
        """Build a plugins/ tree in a temp dir, run main, return (code, output).

        A sentinel default, not None: None is a value main() gives a distinct
        meaning to — read sys.argv — and defaulting to it would hide the
        production path behind every other test.
        """
        with tempfile.TemporaryDirectory() as tmp:
            plugins = Path(tmp) / "plugins"
            for relative, content in files.items():
                target = Path(tmp) / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                if isinstance(content, bytes):
                    target.write_bytes(content)
                else:
                    target.write_text(content, encoding="utf-8")
            stream = io.StringIO()
            with contextlib.redirect_stdout(stream), contextlib.redirect_stderr(stream):
                code = main([] if argv is _NO_ARGV else argv, plugins_dir=plugins)
            return code, stream.getvalue()

    def _clean_files(self):
        return {
            SKILL_PATH: _skill(scope=_clean_scope(), grants=_clean_grants()),
            FIX_ALL: _command("Read, Bash(git log:*)"),
        }

    def test_clean_tree_passes(self):
        code, output = self._run(self._clean_files())
        self.assertEqual(code, 0)
        self.assertIn("Execution boundary OK", output)

    def test_seeded_write_capable_grant_fails_the_run(self):
        files = self._clean_files()
        files[FIX_ALL] = _command("Read, Bash(git log:*), Bash(rm -rf:*)")
        code, output = self._run(files)
        self.assertEqual(code, 1)
        self.assertIn("FAILED", output)
        self.assertIn("Bash(rm -rf:*)", output)

    def test_removing_the_seeded_grant_restores_the_pass(self):
        # Paired with the test above: a checker that has never been seen to go
        # red and then green again on one edit has proved nothing.
        code, output = self._run(self._clean_files())
        self.assertEqual(code, 0)
        self.assertNotIn("Bash(rm -rf:*)", output)

    def test_warning_only_tree_still_passes(self):
        files = self._clean_files()
        files[SKILL_PATH] = _skill(
            scope=_clean_scope(),
            grants=(("Bash(git log:*)", "pipeline", ["fix-all"], "history"),),
        )
        code, output = self._run(files)
        self.assertEqual(code, 0)
        self.assertIn("warning:", output)

    def test_empty_tree_is_a_source_error(self):
        # A glob that matches nothing is a false pass, not a clean tree.
        code, output = self._run({})
        self.assertEqual(code, 2)
        self.assertIn("no command or skill files discovered", output)

    def test_missing_skill_is_a_source_error(self):
        code, output = self._run({FIX_ALL: _command("Read")})
        self.assertEqual(code, 2)
        self.assertIn("the boundary lives here", output)

    def test_unparseable_source_is_exit_2_not_1(self):
        # A failed check and an unreadable source are different answers, and
        # only the exact code tells CI which one it got.
        files = self._clean_files()
        files[SKILL_PATH] = files[SKILL_PATH].replace(
            '<a id="grant-registry"></a>', ""
        )
        code, output = self._run(files)
        self.assertEqual(code, 2)
        self.assertIn("grant-registry", output)

    def test_extra_arguments_are_rejected(self):
        # Ignoring them is how a path-scoped invocation reports success having
        # scanned something else. The code is 2, not 1: a usage error is not a
        # failed check, and only the exact value pins that.
        code, output = self._run(self._clean_files(), argv=["plugins/qa"])
        self.assertEqual(code, 2)
        self.assertIn("takes no arguments", output)

    def test_arguments_are_read_from_sys_argv_when_argv_is_none(self):
        # The production path. `__main__` calls main() with no argv, so every
        # other test here exercises a branch only tests take; dropping
        # sys.argv[1:] restores the ignored-arguments bug with the suite green.
        with mock.patch.object(
            sys, "argv", ["check_execution_boundary.py", "plugins/qa"]
        ):
            code, output = self._run(self._clean_files(), argv=None)
        self.assertEqual(code, 2)
        self.assertIn("plugins/qa", output)

    def test_undecodable_file_is_reported_not_raised(self):
        files = self._clean_files()
        files["plugins/code-review/commands/bad.md"] = b"---\nname: \xff\xfe\n---\n"
        code, output = self._run(files)
        self.assertEqual(code, 2)
        self.assertIn("cannot be read as UTF-8 text", output)

    def test_byte_order_mark_does_not_hide_the_frontmatter(self):
        files = self._clean_files()
        files[FIX_ALL] = b"\xef\xbb\xbf" + _command("Read, Bash(git log:*)").encode()
        code, output = self._run(files)
        self.assertEqual(code, 0)
        self.assertIn("Execution boundary OK", output)


class TestRealTree(unittest.TestCase):
    """The checker's own sources must stay parseable, whatever the verdict."""

    def test_the_repository_boundary_and_registry_parse(self):
        skill = (PLUGINS_DIR.parent / SKILL_RELPATH).read_text(encoding="utf-8-sig")
        tools, families = parse_boundary(skill)
        self.assertEqual(sorted(tools), ["Glob", "Grep", "Read"])
        self.assertEqual(
            sorted(families["git"]), ["blame", "diff", "log", "show", "status"]
        )
        scope, grants = parse_registry(skill)
        self.assertIn(FIX_ALL, scope)
        self.assertIn(FIX_REPORT, scope)
        self.assertTrue(grants)


if __name__ == "__main__":
    unittest.main()
