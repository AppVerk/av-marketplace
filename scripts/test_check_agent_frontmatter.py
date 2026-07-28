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

sys.path.insert(0, str(Path(__file__).resolve().parent))

from check_agent_frontmatter import (
    AGENT_GLOB,
    EXPECTED_AGENT_FILES,
    PLUGINS_DIR,
    check_file,
    main,
    parse_frontmatter,
    split_entries,
)


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

    def test_hash_inside_balanced_parens_is_not_a_comment(self):
        text = "---\nname: a\ndescription: d\ntools: Bash(grep # x)\n---\n"
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

    def test_unbalanced_open_paren_is_error(self):
        # Absorbing the stray '(' would pin depth above zero, glue the whole
        # tail into one entry named 'Read' and hide every later tool.
        entries, error = split_entries("Read, Bash(npm run build, Task, AskUserQuestion")
        self.assertIsNotNone(error)
        self.assertEqual(entries, [])

    def test_unbalanced_close_paren_is_error(self):
        entries, error = split_entries("Read, Bash npm), Task")
        self.assertIsNotNone(error)
        self.assertEqual(entries, [])


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

    def test_unbalanced_paren_in_tools_is_error(self):
        # check_file must surface a split failure as an error, not a warning:
        # a value it cannot split is a value it has not checked.
        text = _agent(
            name="a",
            description="d",
            tools="Read, Bash(npm run build, Task, AskUserQuestion",
        )
        self.assertTrue(any("unbalanced" in e for e in self._errors(text)))

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

    def test_expected_file_count_matches_the_tree(self):
        # Compare the constant against the tree it describes. Restating its own
        # literal would go green when the tree grows past it and red when a
        # maintainer correctly bumps it — the wrong way round on both counts.
        actual = len(list(PLUGINS_DIR.glob(AGENT_GLOB)))
        self.assertEqual(
            actual,
            EXPECTED_AGENT_FILES,
            f"EXPECTED_AGENT_FILES is {EXPECTED_AGENT_FILES} but "
            f"{PLUGINS_DIR}/{AGENT_GLOB} matches {actual} file(s); update the "
            "constant in check_agent_frontmatter.py",
        )


class TestMain(unittest.TestCase):
    """main() drives the exit code CI reads, so every branch of it is pinned."""

    def _run(self, files, argv=None) -> tuple[int, str]:
        """Build a plugins/ tree in a temp dir, run main, return (code, output).

        `files` maps a path under plugins/ to its content; bytes are written
        verbatim so encoding cases can be exercised.
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
                code = main(argv if argv is not None else [], plugins_dir=plugins)
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

    def test_extra_arguments_are_rejected(self):
        # Ignoring them made `... check_agent_frontmatter.py plugins/qa` scan
        # the whole tree and report success.
        code, output = self._run(
            {"x/agents/a.md": _agent(name="a", description="d", tools="Read")},
            argv=["plugins/qa"],
        )
        self.assertNotEqual(code, 0)
        self.assertIn("takes no arguments", output)

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
