#!/usr/bin/env python3
"""Unit tests for check_agent_frontmatter.

Run: python3 scripts/test_check_agent_frontmatter.py
"""

from __future__ import annotations

import contextlib
import io
import sys
import tempfile
import unittest
from pathlib import Path, PurePath
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))

from check_agent_frontmatter import (
    AGENT_GLOB,
    EXPECTED_AGENT_FILES,
    PLUGINS_DIR,
    _has_inline_comment,
    _imbalance,
    check_file,
    main,
    parse_frontmatter,
    split_entries,
)

try:  # Test-time oracle only. The checker itself stays stdlib-only.
    import yaml
except ImportError:  # pragma: no cover - exercised by the skip below
    yaml = None


class TestParseFrontmatter(unittest.TestCase):
    def test_simple_key_value(self):
        text = "---\nname: agent\ndescription: does things\n---\n\nBody.\n"
        fields, errors = parse_frontmatter(text)
        self.assertEqual(errors, [])
        self.assertEqual(fields["name"], "agent")
        self.assertEqual(fields["description"], "does things")

    def test_value_containing_colon(self):
        text = "---\nname: a\ndescription: Runs /superutils:spec-review now\n---\n"
        fields, errors = parse_frontmatter(text)
        self.assertEqual(errors, [])
        self.assertEqual(fields["description"], "Runs /superutils:spec-review now")

    def test_trailing_whitespace_in_value(self):
        text = "---\nname: a\ndescription: d\nmodel: opus \n---\n"
        fields, errors = parse_frontmatter(text)
        self.assertEqual(errors, [])
        self.assertEqual(fields["model"], "opus")

    def test_block_list(self):
        text = "---\nname: a\ndescription: d\ntools:\n  - Read\n  - Grep\n---\n"
        fields, errors = parse_frontmatter(text)
        self.assertEqual(errors, [])
        self.assertEqual(fields["tools"], ["Read", "Grep"])

    def test_comment_line_ignored(self):
        # Asserting the key set, not `assertNotIn("# a comment", fields)`:
        # KEY_VALUE_RE's key group matches neither '#' nor a space, so that
        # string could never be a key under any mutation of the skip branch.
        text = "---\n# a comment\nname: a\ndescription: d\n---\n"
        fields, errors = parse_frontmatter(text)
        self.assertEqual(errors, [])
        self.assertEqual(sorted(fields), ["description", "name"])

    def test_comment_ends_a_block_list(self):
        # The comment branch clears current_list_key; without that, 'Read'
        # would silently attach itself to tools:.
        text = "---\nname: a\ntools:\n# a comment\n  - Read\n---\n"
        fields, errors = parse_frontmatter(text)
        self.assertTrue(any("no empty-valued key" in e for e in errors))
        self.assertEqual(fields["tools"], [])

    def test_block_list_items_append_to_one_list(self):
        text = "---\nname: a\ntools:\n  - Read\n  - Grep\n  - Glob\n---\n"
        fields, errors = parse_frontmatter(text)
        self.assertEqual(errors, [])
        self.assertEqual(fields["tools"], ["Read", "Grep", "Glob"])

    def test_value_starting_with_hash_is_error(self):
        # YAML reads `description: #TODO` as null, so the required key is
        # absent at runtime even though there is text on the line.
        text = "---\nname: a\ndescription: #TODO\n---\n"
        fields, errors = parse_frontmatter(text)
        self.assertTrue(any("'#'" in e for e in errors))

    def test_unbalanced_paren_does_not_hide_a_comment(self):
        # One stray '(' must not switch comment detection off for the rest of
        # the line: unbalanced parens are a typo, not a specifier.
        text = "---\nname: a\ndescription: does ( things # note\n---\n"
        fields, errors = parse_frontmatter(text)
        self.assertTrue(any("'#'" in e for e in errors))

    def test_hash_inside_balanced_parens_is_still_a_comment(self):
        # The opposite of what this test asserted for three rounds. YAML has no
        # paren rule for a plain scalar; it truncates at the ' #' whatever the
        # nesting. PyYAML on this exact line yields {'tools': 'Bash(grep'}, so
        # the mask that used to make this pass was a fail-open, not a nicety.
        text = "---\nname: a\ndescription: d\ntools: Bash(grep # x)\n---\n"
        fields, errors = parse_frontmatter(text)
        self.assertTrue(any("'#'" in e for e in errors))

    def test_hash_in_a_specifier_does_not_hide_the_dropped_tail(self):
        # PyYAML: {'tools': 'Read, Bash(gh issue view'}. Grep is gone from the
        # grant and the surviving specifier is malformed; the paren mask
        # reported neither.
        text = "---\nname: a\ndescription: d\ntools: Read, Bash(gh issue view #123), Grep\n---\n"
        fields, errors = parse_frontmatter(text)
        self.assertTrue(any("'#'" in e for e in errors))

    def test_hash_in_a_block_item_is_error(self):
        # The comma spelling of both values is a hard error and PyYAML
        # truncates the block-list spelling identically — the first item parses
        # to 'Bash(gh issue view', tail dropped and specifier malformed — so
        # only the `key: value` branch ran the check, one spelling of a defect
        # failed the build and the byte-identical other passed. The second
        # value used to surface as the misleading warning "'Read # x' is not in
        # the v2.1.220 tool list", which names everything except the comment.
        for key, item in (
            ("tools", "Bash(gh issue view #123)"),
            ("tools", "Read # x"),
            ("skills", "review # x"),
        ):
            with self.subTest(key=key, item=item):
                text = f"---\nname: a\ndescription: d\n{key}:\n  - {item}\n---\n"
                fields, errors = parse_frontmatter(text)
                # The key comes from current_list_key, so the error names the
                # list the item belongs to and not a hard-coded 'tools'.
                self.assertTrue(any("'#'" in e and repr(key) in e for e in errors))
                # Still recorded, exactly as the `key: value` branch keeps a
                # commented value: the entry goes on to the name checks too.
                self.assertEqual(len(fields[key]), 1)

    def test_hash_inside_a_quoted_block_item_is_not_a_comment(self):
        # The check runs on the raw item, before _strip_quotes. PyYAML reads
        # `- 'Read # x'` as "Read # x" — the '#' is scalar text — so checking
        # the stripped entry instead would fail the build on a legal item.
        text = "---\nname: a\ndescription: d\ntools:\n  - 'Read # x'\n---\n"
        fields, errors = parse_frontmatter(text)
        self.assertEqual(errors, [])
        self.assertEqual(fields["tools"], ["Read # x"])

    def test_hash_right_after_a_closing_quote_is_a_comment(self):
        # PyYAML: {'description': 'Does things'}. The whitespace-before-'#'
        # rule is right for a plain scalar, but the character straight after a
        # quoted scalar's closing quote is already outside the scalar.
        text = '---\nname: a\ndescription: "Does things"#TODO\n---\n'
        fields, errors = parse_frontmatter(text)
        self.assertTrue(any("'#'" in e for e in errors))

    def test_hash_glued_inside_a_plain_scalar_is_not_a_comment(self):
        # The other direction of the same rule, and the reason it cannot just
        # be deleted: PyYAML reads this line whole, as 'Reviews PR#123 now'.
        text = "---\nname: a\ndescription: Reviews PR#123 now\n---\n"
        fields, errors = parse_frontmatter(text)
        self.assertEqual(errors, [])

    def test_unterminated_quote_does_not_hide_a_comment(self):
        # The dangling quote must not switch detection off for the rest of the
        # line. Starting the scan past it instead of at 0 would report this
        # line clean; PyYAML refuses the document outright.
        text = '---\nname: a\ndescription: "does things # TODO\n---\n'
        fields, errors = parse_frontmatter(text)
        self.assertTrue(any("'#'" in e for e in errors))

    def test_doubled_apostrophe_does_not_end_a_quoted_scalar(self):
        # PyYAML: {'description': "it's # x"}. Stopping at the first half of
        # the '' pair put the closing quote before the '#'.
        text = "---\nname: a\ndescription: 'it''s # x'\n---\n"
        fields, errors = parse_frontmatter(text)
        self.assertEqual(errors, [])

    def test_missing_opening_delimiter(self):
        fields, errors = parse_frontmatter("name: a\n---\n")
        self.assertTrue(errors)

    def test_missing_closing_delimiter(self):
        fields, errors = parse_frontmatter("---\nname: a\n")
        self.assertTrue(errors)

    def test_item_after_non_empty_key_is_error(self):
        text = "---\nname: a\ndescription: d\ntools: Read\n  - Write\n---\n"
        fields, errors = parse_frontmatter(text)
        self.assertTrue(errors)

    def test_inline_comment_after_value_is_error(self):
        text = "---\nname: a\ndescription: d\nmodel: opus # fast\n---\n"
        fields, errors = parse_frontmatter(text)
        self.assertTrue(errors)

    def test_apostrophe_does_not_hide_a_comment(self):
        # A quote quotes only when the value opens with one. Treating the
        # apostrophe in a possessive as an opening quote swallowed the rest of
        # the line, and YAML applies no such rule to a plain scalar — it
        # truncates at the '#'. 'the finder's severity' is live in this repo.
        text = "---\nname: a\ndescription: Reviews the plugin's tools # TODO\n---\n"
        fields, errors = parse_frontmatter(text)
        self.assertTrue(any("'#'" in e for e in errors))

    def test_hash_inside_a_quoted_scalar_is_not_a_comment(self):
        # The other half of the same rule: a value that *does* open with a
        # quote is a YAML quoted scalar, and a '#' before its closing quote is
        # scalar text, not a comment.
        text = '---\nname: a\ndescription: "does # things"\n---\n'
        fields, errors = parse_frontmatter(text)
        self.assertEqual(errors, [])

    def test_hash_inside_a_single_quoted_scalar_is_not_a_comment(self):
        # Single quotes open a YAML quoted scalar exactly as double quotes do;
        # restricting the rule to '"' would silently re-break this half.
        text = "---\nname: a\ndescription: 'does # things'\n---\n"
        fields, errors = parse_frontmatter(text)
        self.assertEqual(errors, [])


@unittest.skipUnless(yaml is not None, "PyYAML is not installed")
class TestInlineCommentAgainstPyYAML(unittest.TestCase):
    """Differential test: _has_inline_comment vs. what PyYAML actually parses.

    Every expectation in TestParseFrontmatter is hand-written, and three review
    rounds showed hand-written expectations encoding the emulator's own bugs.
    This class asks the real parser instead. It skips when PyYAML is absent so
    the suite still runs on a bare interpreter, and the checker never imports
    it.
    """

    #: (key, authored value) — the shapes the review rounds argued about.
    CASES = (
        ("tools", "Bash(grep # x)"),
        ("tools", "Read, Bash(gh issue view #123), Grep"),
        ("tools", "Read, Bash(a,b), Grep"),
        ("tools", '"Read, Grep"'),
        ("description", '"Does things"#TODO'),
        ("description", "'Does things'#TODO"),
        ("description", "Reviews PR#123 now"),
        ("description", "a#b # c"),
        ("description", "'it''s # x'"),
        ("description", '"does # things"'),
        ("description", "'does # things'"),
        ("description", "Reviews the plugin's tools # TODO"),
        ("description", "does ( things # note"),
        ("description", "plain value"),
        ("model", "opus # fast"),
    )

    @staticmethod
    def _yaml_truncates(line: str) -> bool:
        """True when PyYAML's value scalar ends before the line does.

        Comparing parsed text to authored text would fail on quoting alone
        ("does # things" loses its quotes, 'it''s' loses a quote character).
        The scan's end mark is the unambiguous question: did YAML consume the
        whole line, or stop early and throw the rest away?
        """
        document = line + "\n"
        scalars = [
            token
            for token in yaml.scan(document)
            if isinstance(token, yaml.tokens.ScalarToken)
        ]
        # Only the key survived: `description: #TODO` parses to null.
        if len(scalars) < 2:
            return True
        return bool(document[scalars[-1].end_mark.index :].strip())

    def test_matches_pyyaml_on_every_case(self):
        for key, value in self.CASES:
            with self.subTest(value=value):
                self.assertEqual(
                    _has_inline_comment(value),
                    self._yaml_truncates(f"{key}: {value}"),
                )


class TestSplitEntries(unittest.TestCase):
    def test_comma_list(self):
        entries, error, warnings = split_entries("Read, Grep, Glob")
        self.assertEqual((error, warnings), (None, []))
        self.assertEqual(entries, ["Read", "Grep", "Glob"])

    def test_flow_sequence(self):
        entries, error, warnings = split_entries("[Read, Grep]")
        self.assertEqual((error, warnings), (None, []))
        self.assertEqual(entries, ["Read", "Grep"])

    def test_block_list_passthrough(self):
        entries, error, warnings = split_entries(["Read", "Grep"])
        self.assertEqual((error, warnings), (None, []))
        self.assertEqual(entries, ["Read", "Grep"])

    def test_quotes_stripped(self):
        entries, error, warnings = split_entries('"Read", \'Grep\'')
        self.assertEqual((error, warnings), (None, []))
        self.assertEqual(entries, ["Read", "Grep"])

    def test_whole_value_quoted_list_is_still_split(self):
        # PyYAML reads all three of these as the same scalar, 'Read, Grep', so
        # they must reach the name checks as the same two entries. Stripping
        # the quotes only after the split left the quoted spellings warning
        # that 'Read, Grep' is not a tool while the bare one passed.
        for value in ('"Read, Grep"', "'Read, Grep'", "Read, Grep"):
            with self.subTest(value=value):
                entries, error, warnings = split_entries(value)
                self.assertEqual((error, warnings), (None, []))
                self.assertEqual(entries, ["Read", "Grep"])

    def test_quoted_entries_are_not_unwrapped_as_one_scalar(self):
        # "'Read', 'Grep'" opens and ends with a quote without being one
        # scalar; unwrapping it would hand the checks a single entry spelled
        # "Read', 'Grep".
        #
        # No agent file can carry this exact value: PyYAML refuses the
        # document, because a quoted scalar may not be followed by more text on
        # the same line. There is no legal equivalent to swap in either — the
        # flow-sequence form `[Read, Grep]` reaches the split with its brackets
        # already stripped, never passing through _unwrap_quoted_value. The
        # shape is reachable only because this parser is laxer than YAML, and
        # that is what the guard is for: on the lax path, refuse to invent a
        # fused name.
        entries, error, warnings = split_entries("'Read', 'Grep'")
        self.assertEqual((error, warnings), (None, []))
        self.assertEqual(entries, ["Read", "Grep"])

    def test_imbalance_warning_quotes_the_value_as_authored(self):
        # The warning has to name the text the reader will go looking for in
        # the file. Quoting the post-unwrap form reports 'Read, Bash(npm run
        # build' for a line that reads `tools: "Read, Bash(npm run build"` — a
        # string the file does not contain.
        entries, error, warnings = split_entries('"Read, Bash(npm run build"')
        self.assertIsNone(error)
        self.assertEqual(entries, ["Read", "Bash(npm run build"])
        self.assertEqual(
            warnings,
            ["""unbalanced '(' in value '"Read, Bash(npm run build"'"""],
        )

    def test_empty_entries_are_dropped(self):
        # `Read,, Grep` is a typo, not a third tool. Keeping the empty entry
        # made the name check report that '' is not in the v2.1.220 tool list,
        # which names nothing the author can act on.
        entries, error, warnings = split_entries("Read,, Grep")
        self.assertEqual((error, warnings), (None, []))
        self.assertEqual(entries, ["Read", "Grep"])
        # The block-list branch filters separately: `- ""` strips to nothing.
        entries, error, warnings = split_entries(["Read", '""', "Grep"])
        self.assertEqual((error, warnings), (None, []))
        self.assertEqual(entries, ["Read", "Grep"])

    def test_bash_specifier_with_comma_is_kept_whole(self):
        # The comma inside the parens is what exercises the depth guard in
        # split_entries; without it this test passes even with the guard removed.
        entries, error, warnings = split_entries("Read, Bash(git commit -m a,b)")
        self.assertEqual((error, warnings), (None, []))
        self.assertEqual(entries, ["Read", "Bash(git commit -m a,b)"])

    def test_comma_inside_quotes_does_not_separate(self):
        # The quote half of the split guard, isolated from the depth half: this
        # comma sits at depth 0, so only `not quoted` keeps the entry whole.
        entries, error, warnings = split_entries('Read, "Grep, Glob", Write')
        self.assertEqual((error, warnings), (None, []))
        self.assertEqual(entries, ["Read", "Grep, Glob", "Write"])

    def test_folded_scalar_is_error(self):
        entries, error, warnings = split_entries(">")
        self.assertIsNotNone(error)

    def test_unbalanced_open_paren_warns_and_still_splits(self):
        # The round-1 critical, closed without a build-failing error: absorbing
        # the stray '(' would pin depth above zero and glue the whole tail into
        # one entry named 'Read', hiding Task and AskUserQuestion. Rejecting the
        # value outright hid them just as thoroughly. Splitting comma-blind
        # hands all four to the name checks.
        entries, error, warnings = split_entries(
            "Read, Bash(npm run build, Task, AskUserQuestion"
        )
        self.assertIsNone(error)
        self.assertEqual(
            entries, ["Read", "Bash(npm run build", "Task", "AskUserQuestion"]
        )
        self.assertTrue(any("unbalanced '('" in w for w in warnings))

    def test_unbalanced_close_paren_warns_and_still_splits(self):
        entries, error, warnings = split_entries("Read, Bash npm), Task")
        self.assertIsNone(error)
        self.assertEqual(entries, ["Read", "Bash npm)", "Task"])
        self.assertTrue(any("unbalanced ')'" in w for w in warnings))

    def test_open_paren_inside_quotes_is_literal_text(self):
        # A quoted '(' is an argument, not a nesting level. The quote-blind
        # copy of the balance rule failed the build on this shape.
        entries, error, warnings = split_entries('Read, Bash(grep -rn "foo(" src), Grep')
        self.assertEqual((error, warnings), (None, []))
        self.assertEqual(entries, ["Read", 'Bash(grep -rn "foo(" src)', "Grep"])

    def test_open_paren_inside_single_quotes_is_literal_text(self):
        # The single-quote twin. Nothing else in the suite opens a quote with
        # "'", so narrowing the scan to '"' alone reintroduced round 2's
        # regression for half the values with CI green.
        entries, error, warnings = split_entries("Read, Bash(grep -rn 'foo(' src), Grep")
        self.assertEqual((error, warnings), (None, []))
        self.assertEqual(entries, ["Read", "Bash(grep -rn 'foo(' src)", "Grep"])

    def test_close_paren_inside_quotes_is_literal_text(self):
        entries, error, warnings = split_entries('Read, Bash(echo ")"), Grep')
        self.assertEqual((error, warnings), (None, []))
        self.assertEqual(entries, ["Read", 'Bash(echo ")")', "Grep"])

    def test_split_never_disagrees_with_the_scan(self):
        # One scan, one verdict. Two rules coexisted after round 1 and the
        # stricter, quote-blind one was the one wired to a build-failing error;
        # this pins the split's warning to _imbalance's verdict on the exact
        # values that diverged, plus the two defects that must stay reported.
        values = (
            'Read, Bash(grep -rn "foo(" src), Grep',
            'Read, Bash(echo ")"), Grep',
            "Read, Bash(npm run build, Task, AskUserQuestion",
            "Read, Bash npm), Task",
            "Read, Bash(echo don't), Grep",
        )
        for value in values:
            with self.subTest(value=value):
                _, error, warnings = split_entries(value)
                self.assertIsNone(error)
                self.assertEqual(_imbalance(value) is None, warnings == [])

    def test_unbalanced_paren_in_a_block_item_warns(self):
        # The comma form of this value warns, so its block-list spelling must
        # warn too — and the item still reaches the name checks.
        entries, error, warnings = split_entries(["Read", "Bash(npm run build"])
        self.assertIsNone(error)
        self.assertEqual(entries, ["Read", "Bash(npm run build"])
        self.assertTrue(any("unbalanced '('" in w for w in warnings))


class TestImbalance(unittest.TestCase):
    def test_close_before_open_is_unbalanced(self):
        # The depth < 0 early return: without it the two cancel out and this
        # reads as clean.
        self.assertEqual(_imbalance(") ("), "unbalanced ')'")

    def test_paren_inside_quotes_does_not_count(self):
        self.assertIsNone(_imbalance('Bash(echo ")")'))

    def test_unterminated_quote_is_reported_as_a_quote(self):
        # An odd number of quote characters suspends paren accounting to end of
        # string, so the closing ')' is swallowed and the naive reading is
        # "unbalanced '('". Round 4 lost a review cycle to that wording; the
        # parenthesis is right there in the value.
        for value, kind in (
            ("Bash(echo don't)", "single"),
            ('Bash(awk "{print})', "double"),
        ):
            with self.subTest(value=value):
                self.assertEqual(_imbalance(value), f"unterminated {kind} quote")


def _agent(**fields) -> str:
    body = "\n".join(f"{key}: {value}" for key, value in fields.items())
    return f"---\n{body}\n---\n\nBody.\n"


class TestErrors(unittest.TestCase):
    def _errors(self, text: str) -> list[str]:
        errors, _ = check_file(PurePath("plugins/x/agents/a.md"), text)
        return errors

    def test_clean_agent_has_no_errors(self):
        text = _agent(name="a", description="d", tools="Read, Grep")
        self.assertEqual(self._errors(text), [])

    def test_allowed_tools_key_is_error(self):
        text = _agent(name="a", description="d", tools="Read")
        text = text.replace("tools: Read", "tools: Read\nallowed-tools: Bash(git *)")
        self.assertTrue(any("allowed-tools" in e for e in self._errors(text)))

    def test_hooks_key_is_error(self):
        text = _agent(name="a", description="d", hooks="something")
        self.assertTrue(any("hooks" in e for e in self._errors(text)))

    def test_missing_name_is_error(self):
        text = _agent(description="d", tools="Read")
        self.assertTrue(any("name" in e for e in self._errors(text)))

    def test_missing_description_is_error(self):
        text = _agent(name="a", tools="Read")
        self.assertTrue(any("description" in e for e in self._errors(text)))

    def test_always_stripped_tool_in_tools_is_error(self):
        text = _agent(name="a", description="d", tools="Read, TaskOutput")
        self.assertTrue(any("TaskOutput" in e for e in self._errors(text)))

    def test_always_stripped_tool_in_disallowed_is_not_error(self):
        text = _agent(name="a", description="d", tools="Read", disallowedTools="TaskOutput")
        self.assertEqual(self._errors(text), [])

    def test_known_bad_tool_is_error(self):
        text = _agent(name="a", description="d", tools="Read, Task")
        self.assertTrue(any("Task" in e for e in self._errors(text)))

    def test_known_bad_tool_with_specifier_is_error(self):
        text = _agent(name="a", description="d", tools="Read, Task(x)")
        self.assertTrue(any("Task" in e for e in self._errors(text)))

    def test_a_stray_paren_cannot_hide_a_bad_tool(self):
        # Invariant (a). The round-1 critical: a typo must not let entries
        # behind it go unchecked. It stays closed without the value being
        # rejected — the fallback split hands Task and AskUserQuestion to the
        # name checks, and the paren itself is reported as a warning.
        text = _agent(
            name="a",
            description="d",
            tools="Read, Bash(npm run build, Task, AskUserQuestion",
        )
        errors, warnings = check_file(PurePath("plugins/x/agents/a.md"), text)
        self.assertTrue(any("'Task'" in e for e in errors))
        self.assertTrue(any("'AskUserQuestion'" in e for e in errors))
        self.assertTrue(any("unbalanced '('" in w for w in warnings))

    def test_quotes_in_a_specifier_warn_rather_than_fail_the_build(self):
        # Invariant (b). PyYAML parses all four of these to exactly the string
        # the author typed, so none of them is a defect in the file — yet an
        # odd quote count suspends paren accounting and the balance gate read
        # every one as an unbalanced '('. Three rounds of over-rejection ended
        # here: they warn, they do not error.
        values = (
            "Read, Bash(echo don't), Grep",
            "Read, Bash(echo the user's file), Grep",
            'Read, Bash(awk "{print}), Grep',
            "Read, PowerShell(Write-Host 'hi), Grep",
        )
        for value in values:
            with self.subTest(value=value):
                errors, warnings = check_file(
                    PurePath("plugins/x/agents/a.md"),
                    _agent(name="a", description="d", tools=value),
                )
                self.assertEqual(errors, [])
                self.assertTrue(any("unterminated" in w for w in warnings))

        # "rather than", not "never" — the residual, pinned so a later round
        # meets it as documented behaviour instead of rediscovering it as a
        # critical. The apostrophe routes a paren-*balanced* value into the
        # paren-blind fallback, which then reads `Workflow` — a comma token
        # inside the specifier — as a top-level entry. PyYAML parses the line
        # verbatim, so nothing in the file is malformed. It takes both an odd
        # quote and an exact bad name in the same specifier; teaching the
        # fallback to avoid it is what rounds 1-5 oscillated over.
        errors, _ = check_file(
            PurePath("plugins/x/agents/a.md"),
            _agent(
                name="a",
                description="d",
                tools="Read, Bash(git log --author=O'Brien, Workflow, x)",
            ),
        )
        self.assertEqual(
            errors,
            ["plugins/x/agents/a.md: tools: 'Workflow' is stripped from every subagent"],
        )
        # The apostrophe alone is the difference: without it the same value
        # scans clean, `Workflow` stays inside the specifier, and it passes.
        errors, _ = check_file(
            PurePath("plugins/x/agents/a.md"),
            _agent(
                name="a",
                description="d",
                tools="Read, Bash(git log --author=OBrien, Workflow, x)",
            ),
        )
        self.assertEqual(errors, [])

    def test_an_entry_starting_with_a_paren_still_names_its_tool(self):
        # `_base_name('(Task')` was '', so KNOWN_BAD_TOOLS never matched and
        # the run passed with a warning about '' — the one string an author
        # cannot search the file for. The stray paren is the typo; the name
        # behind it still has to be checked.
        errors, _ = check_file(
            PurePath("plugins/x/agents/a.md"),
            _agent(name="a", description="d", tools="Read, (Task"),
        )
        self.assertTrue(any("'Task'" in e for e in errors))

    def test_empty_specifier_is_not_a_crash(self):
        # `Bash()` leaves the colon-form check with no tokens to look at; the
        # guard is what turns that into a clean pass instead of an IndexError.
        errors, warnings = check_file(
            PurePath("plugins/x/agents/a.md"),
            _agent(name="a", description="d", tools="Read, Bash()"),
        )
        self.assertEqual((errors, warnings), ([], []))

    def test_malformed_frontmatter_is_error(self):
        # The parse-error short-circuit must return before any other check runs.
        # Asserting only that errors is non-empty would pass even with the
        # short-circuit deleted, because the missing name/description would
        # produce errors anyway; the empty warnings list is what pins it.
        errors, warnings = check_file(PurePath("plugins/x/agents/a.md"), "no frontmatter here\n")
        self.assertEqual(warnings, [])
        self.assertTrue(any("frontmatter" in e for e in errors))


class TestWarnings(unittest.TestCase):
    def _warnings(self, text: str) -> list[str]:
        _, warnings = check_file(PurePath("plugins/x/agents/a.md"), text)
        return warnings

    def test_unknown_tool_name_warns(self):
        text = _agent(name="a", description="d", tools="Read, Sparkle")
        self.assertTrue(any("Sparkle" in w for w in self._warnings(text)))

    def test_server_grant_does_not_warn(self):
        text = _agent(
            name="a",
            description="d",
            tools="Read, mcp__playwright, mcp__plugin_playwright_playwright__*",
        )
        self.assertEqual(self._warnings(text), [])

    def test_per_tool_mcp_entry_warns(self):
        text = _agent(name="a", description="d", tools="Read, mcp__playwright__browser_navigate")
        self.assertTrue(any("browser_navigate" in w for w in self._warnings(text)))

    def test_entry_with_no_name_at_all_is_reported_verbatim(self):
        # An entry that is nothing but punctuation still has no base name after
        # the leading paren is dropped. Reporting '' points at nothing; the
        # entry as authored at least appears in the file.
        warnings = self._warnings(_agent(name="a", description="d", tools="Read, ("))
        self.assertTrue(any("'(' is not in" in w for w in warnings))
        self.assertFalse(any("'' is not in" in w for w in warnings))

    def test_background_lost_builtin_warns(self):
        text = _agent(name="a", description="d", tools="Read, TaskCreate")
        self.assertTrue(any("background" in w for w in self._warnings(text)))

    def test_bare_mcp_prefix_warns(self):
        # 'mcp__' names no server, so it is not a whole-server grant.
        text = _agent(name="a", description="d", tools="Read, mcp__")
        self.assertTrue(any("mcp__" in w for w in self._warnings(text)))

    def test_multi_segment_mcp_star_warns(self):
        # 'mcp__a__b__*' is a per-tool prefix wearing a star, not a server.
        text = _agent(name="a", description="d", tools="Read, mcp__a__b__*")
        self.assertTrue(any("mcp__a__b__*" in w for w in self._warnings(text)))

    def test_colon_form_bash_specifier_warns(self):
        text = _agent(name="a", description="d", tools="Read, Bash(git:*)")
        self.assertTrue(any("colon" in w for w in self._warnings(text)))

    def test_colon_form_powershell_specifier_warns(self):
        # PowerShell takes the same specifier form, so it needs the same guard.
        text = _agent(name="a", description="d", tools="Read, PowerShell(git:*)")
        self.assertTrue(any("colon" in w for w in self._warnings(text)))

    def test_space_form_bash_specifier_does_not_warn(self):
        text = _agent(name="a", description="d", tools="Read, Bash(git *)")
        self.assertEqual(self._warnings(text), [])

    def test_colon_in_a_bash_argument_does_not_warn(self):
        # The warning names the colon *specifier* form; a port mapping deep in
        # the argument list is not it.
        text = _agent(name="a", description="d", tools="Read, Bash(docker run -p 8080:80)")
        self.assertEqual(self._warnings(text), [])

    def test_missing_tools_key_warns(self):
        text = _agent(name="a", description="d")
        self.assertTrue(any("inherits every tool" in w for w in self._warnings(text)))

    def test_empty_tools_value_warns(self):
        # A bare `tools:` parses to [] here and to null at runtime, which
        # inherits everything exactly like an absent key.
        text = "---\nname: a\ndescription: d\ntools:\n---\n\nBody.\n"
        self.assertTrue(any("inherits every tool" in w for w in self._warnings(text)))

    def test_expected_file_count_is_a_floor_the_tree_still_meets(self):
        # Compare the constant against the tree it describes; restating its own
        # literal would assert nothing. A floor, not an equality, because the
        # constant documents one: main() guards with `<` and says "expected at
        # least", so a 26th agent file is legitimate and warning-free and must
        # not turn this step red before the validator even runs.
        actual = len(list(PLUGINS_DIR.glob(AGENT_GLOB)))
        self.assertGreaterEqual(
            actual,
            EXPECTED_AGENT_FILES,
            f"EXPECTED_AGENT_FILES is {EXPECTED_AGENT_FILES} but "
            f"{PLUGINS_DIR}/{AGENT_GLOB} matches {actual} file(s); the tree "
            "shrank below the floor, or the constant needs lowering in "
            "check_agent_frontmatter.py",
        )


_NO_ARGV = object()


class TestMain(unittest.TestCase):
    """main() drives the exit code CI reads, so every branch of it is pinned."""

    def _run(self, files, argv=_NO_ARGV) -> tuple[int, str]:
        """Build a plugins/ tree in a temp dir, run main, return (code, output).

        `files` maps a path under plugins/ to its content; bytes are written
        verbatim so encoding cases can be exercised.

        A sentinel default, not None: None is a value main() gives a distinct
        meaning to, and the old default quietly rewrote it to [], which is why
        the production argv path had no coverage at all.
        """
        with tempfile.TemporaryDirectory() as tmp:
            plugins = Path(tmp) / "plugins"
            for relative, content in files.items():
                target = plugins / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                if isinstance(content, bytes):
                    target.write_bytes(content)
                else:
                    target.write_text(content, encoding="utf-8")
            stream = io.StringIO()
            with contextlib.redirect_stdout(stream), contextlib.redirect_stderr(stream):
                code = main([] if argv is _NO_ARGV else argv, plugins_dir=plugins)
            return code, stream.getvalue()

    def test_no_agent_files_fails(self):
        # A glob that matches nothing is a false pass, not a clean tree.
        code, output = self._run({})
        self.assertEqual(code, 1)
        self.assertIn("no agent files discovered", output)

    def test_clean_tree_passes(self):
        code, output = self._run(
            {"x/agents/a.md": _agent(name="a", description="d", tools="Read, Grep")}
        )
        self.assertEqual(code, 0)
        self.assertIn("Agent frontmatter OK", output)

    def test_known_bad_tool_fails_the_run(self):
        code, output = self._run(
            {"x/agents/a.md": _agent(name="a", description="d", tools="Read, Task")}
        )
        self.assertEqual(code, 1)
        self.assertIn("FAILED", output)

    def test_warning_only_tree_still_passes(self):
        # Warnings print and never fail the build.
        code, output = self._run(
            {"x/agents/a.md": _agent(name="a", description="d", tools="Read, TaskCreate")}
        )
        self.assertEqual(code, 0)
        self.assertIn("unavailable to background subagents", output)

    def test_shrinking_tree_warns_without_failing(self):
        code, output = self._run(
            {"x/agents/a.md": _agent(name="a", description="d", tools="Read")}
        )
        self.assertEqual(code, 0)
        self.assertIn("shrinking glob is a false pass", output)

    def test_tree_at_exactly_the_floor_does_not_warn(self):
        # The boundary is now the operating point: the constant equals the
        # tree's size, so `<` mutated to `<=` would warn on every CI run.
        # The shrinking and growing cases sit on either side of that edge and
        # both survive the mutant; only a tree of exactly EXPECTED_AGENT_FILES
        # kills it.
        clean = _agent(name="a", description="d", tools="Read")
        code, output = self._run(
            {
                f"x/agents/a{index}.md": clean
                for index in range(EXPECTED_AGENT_FILES)
            }
        )
        self.assertEqual(code, 0)
        self.assertNotIn("shrinking glob is a false pass", output)

    def test_growing_tree_does_not_warn(self):
        # The floor is a floor. main() guards with `<` and says "expected at
        # least", so a tree one file larger than the constant is legitimate and
        # must stay silent — nothing else pinned that, and `<` mutated to `!=`
        # survived the whole suite while making every added agent file warn.
        clean = _agent(name="a", description="d", tools="Read")
        code, output = self._run(
            {
                f"x/agents/a{index}.md": clean
                for index in range(EXPECTED_AGENT_FILES + 1)
            }
        )
        self.assertEqual(code, 0)
        self.assertNotIn("shrinking glob is a false pass", output)

    def test_extra_arguments_are_rejected(self):
        # Ignoring them made `... check_agent_frontmatter.py plugins/qa` scan
        # the whole tree and report success. The code is 2, not 1: a usage
        # error is not a failed check, and only the exact value pins that.
        code, output = self._run(
            {"x/agents/a.md": _agent(name="a", description="d", tools="Read")},
            argv=["plugins/qa"],
        )
        self.assertEqual(code, 2)
        self.assertIn("takes no arguments", output)

    def test_arguments_are_read_from_sys_argv_when_argv_is_none(self):
        # The production path. `__main__` calls main() with no argv and CI
        # takes no other branch, so every other test here exercises a branch
        # that only tests use; dropping sys.argv[1:] restores the ignored-
        # arguments bug with the suite still green.
        with mock.patch.object(sys, "argv", ["check_agent_frontmatter.py", "plugins/qa"]):
            code, output = self._run(
                {"x/agents/a.md": _agent(name="a", description="d", tools="Read")},
                argv=None,
            )
        self.assertEqual(code, 2)
        self.assertIn("plugins/qa", output)

    def test_byte_order_mark_is_not_a_missing_delimiter(self):
        text = _agent(name="a", description="d", tools="Read")
        code, output = self._run(
            {"x/agents/a.md": b"\xef\xbb\xbf" + text.encode("utf-8")}
        )
        self.assertEqual(code, 0)
        self.assertNotIn("does not open with", output)

    def test_undecodable_file_is_reported_not_raised(self):
        code, output = self._run({"x/agents/a.md": b"---\nname: \xff\xfe\n---\n"})
        self.assertEqual(code, 1)
        self.assertIn("cannot be read as UTF-8 text", output)


if __name__ == "__main__":
    unittest.main()
