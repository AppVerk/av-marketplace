#!/usr/bin/env python3
"""Unit tests for check_agent_frontmatter.

Run: python3 scripts/test_check_agent_frontmatter.py
"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from check_agent_frontmatter import parse_frontmatter, split_entries


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
        entries, error = split_entries("Read, Bash(git commit -m *)")
        self.assertIsNone(error)
        self.assertEqual(entries, ["Read", "Bash(git commit -m *)"])

    def test_folded_scalar_is_error(self):
        entries, error = split_entries(">")
        self.assertIsNotNone(error)


if __name__ == "__main__":
    unittest.main()
