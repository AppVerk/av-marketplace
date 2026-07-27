#!/usr/bin/env python3
"""Unit tests for check_agent_frontmatter.

Run: python3 scripts/test_check_agent_frontmatter.py
"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path, PurePath

sys.path.insert(0, str(Path(__file__).resolve().parent))

from check_agent_frontmatter import parse_frontmatter, split_entries, check_file


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
        text = "---\n# a comment\nname: a\ndescription: d\n---\n"
        fields, errors = parse_frontmatter(text)
        self.assertEqual(errors, [])
        self.assertNotIn("# a comment", fields)

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


class TestSplitEntries(unittest.TestCase):
    def test_comma_list(self):
        entries, error = split_entries("Read, Grep, Glob")
        self.assertIsNone(error)
        self.assertEqual(entries, ["Read", "Grep", "Glob"])

    def test_flow_sequence(self):
        entries, error = split_entries("[Read, Grep]")
        self.assertIsNone(error)
        self.assertEqual(entries, ["Read", "Grep"])

    def test_block_list_passthrough(self):
        entries, error = split_entries(["Read", "Grep"])
        self.assertIsNone(error)
        self.assertEqual(entries, ["Read", "Grep"])

    def test_quotes_stripped(self):
        entries, error = split_entries('"Read", \'Grep\'')
        self.assertIsNone(error)
        self.assertEqual(entries, ["Read", "Grep"])

    def test_bash_specifier_with_comma_is_kept_whole(self):
        # The comma inside the parens is what exercises the depth guard in
        # split_entries; without it this test passes even with the guard removed.
        entries, error = split_entries("Read, Bash(git commit -m a,b)")
        self.assertIsNone(error)
        self.assertEqual(entries, ["Read", "Bash(git commit -m a,b)"])

    def test_folded_scalar_is_error(self):
        entries, error = split_entries(">")
        self.assertIsNotNone(error)


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

    def test_malformed_frontmatter_is_error(self):
        # The parse-error short-circuit must return before any other check runs.
        # Asserting only that errors is non-empty would pass even with the
        # short-circuit deleted, because the missing name/description would
        # produce errors anyway; the empty warnings list is what pins it.
        errors, warnings = check_file(PurePath("plugins/x/agents/a.md"), "no frontmatter here\n")
        self.assertEqual(warnings, [])
        self.assertTrue(any("frontmatter" in e for e in errors))


if __name__ == "__main__":
    unittest.main()
