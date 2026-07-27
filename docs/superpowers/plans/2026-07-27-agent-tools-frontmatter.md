# Agent Frontmatter Tool Declaration Repair — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Repair fifteen agent definitions whose tool access is declared under the inert `allowed-tools:` key, and add a validator plus CI check so the defect cannot silently return.

**Architecture:** Validator first, repairs second. `scripts/check_agent_frontmatter.py` is written before any agent file is touched, so its non-zero exit on today's tree is the failing test the repairs turn green. Each repair task ends by re-running the validator. The web-auditor coordinator additionally needs a body rewrite, because its frontmatter and body must agree.

**Tech Stack:** Python 3.12+ standard library only (no third-party dependencies, no pytest — this repository has no test framework and `scripts/check_plugin_versions.py` is the pattern to follow). Tests use stdlib `unittest`. GitHub Actions for CI.

## Global Constraints

- **Standard library only.** No `pip install`, no `requirements.txt`, no `pyproject.toml`. `scripts/check_plugin_versions.py` is the structural reference: module-level path constants, small helper functions, `main(argv) -> int`, `sys.exit(main())`.
- **Hand-rolled frontmatter parsing.** Do not import `yaml`; it is not available and adding it violates the constraint above.
- **Errors exit non-zero; warnings print and do not fail.**
- **Contract source:** Claude Code docs (`sub-agents`, `tools-reference`, `permissions`) as of **v2.1.220**. Every version-pinned constant carries a comment naming its source page and the date `2026-07-27`.
- **Five version-pinned constants:** `CANONICAL_TOOLS`, `PERMITTED_KEYS`, `ALWAYS_STRIPPED`, `BACKGROUND_KEPT`, `KNOWN_BAD_TOOLS`.
- **Version bumps touch four surfaces**, the set `scripts/check_plugin_versions.py` enforces: `plugins/<name>/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, the README "Available Plugins" table row, and the `**Version:**` header in `docs/plugins/<name>.md`.
- **Commit convention:** Conventional Commits. The repository has a pre-commit hook that blocks bare `git commit`; every commit command in this plan is prefixed with `AV_COMMIT_SKILL=1`.
- **Branch:** `fix/agent-tools-frontmatter`. Already exists with the spec commits on it. Do not create a new branch.
- **Never commit to `master`.** Nothing in this plan pushes.

---

## File Structure

**Created:**

| Path | Responsibility |
| --- | --- |
| `scripts/check_agent_frontmatter.py` | Parse and validate agent frontmatter. One module: constants, parser, per-file checks, CLI. |
| `scripts/test_check_agent_frontmatter.py` | stdlib `unittest` suite for the parser and each check. |
| `.github/workflows/agent-frontmatter.yml` | Run the validator on push and PR against `master`. |
| `docs/agent-tools-verification.md` | Live-layer status record: sixteen rows, `Agent \| Status \| Resolved list`. |
| `CLAUDE.md` | Tracked authoring rules. Replaces the gitignored `CLAUDE.local.md` as the authoritative copy. |

**Modified — agent frontmatter (15 files):**

`plugins/qa/agents/be-tester.md` · `plugins/web-auditor/agents/{api-security,compliance,performance,seo,web-security,supply-chain,infrastructure}-agent.md` · `plugins/web-auditor/agents/web-auditor.md` · `plugins/code-review/agents/{fix-auto,security-auditor,code-quality-auditor}.md` · `plugins/{frontend-developer,python-developer,php-developer}/agents/developer.md`

**Modified — other:**

`plugins/qa/agents/fe-tester.md` (dual-form MCP grant only) · `plugins/web-auditor/agents/web-auditor.md` (body) · `plugins/web-auditor/commands/audit.md` · six `plugin.json` · `.claude-plugin/marketplace.json` · `README.md` · six `docs/plugins/*.md`

---

### Task 1: Frontmatter parser

**Files:**
- Create: `scripts/check_agent_frontmatter.py`
- Create: `scripts/test_check_agent_frontmatter.py`

**Interfaces:**
- Produces: `parse_frontmatter(text: str) -> tuple[dict[str, object], list[str]]` — returns `(fields, errors)`. `fields` maps a key to either a `str` (from `key: value`) or a `list[str]` (from a block list). `errors` is a list of human-readable strings; non-empty means the frontmatter is not well-formed.
- Produces: `split_entries(value: object) -> tuple[list[str], str | None]` — normalises a `tools:`/`disallowedTools:` value into a list of entry strings, returning `(entries, error)`.

- [ ] **Step 1: Write the failing test**

Create `scripts/test_check_agent_frontmatter.py`:

```python
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 scripts/test_check_agent_frontmatter.py`
Expected: FAIL — `ModuleNotFoundError: No module named 'check_agent_frontmatter'`

- [ ] **Step 3: Write the parser**

Create `scripts/check_agent_frontmatter.py`:

```python
#!/usr/bin/env python3
"""Check agent frontmatter against the Claude Code subagent contract.

Usage:
    python3 scripts/check_agent_frontmatter.py

Scans plugins/*/agents/*.md and validates each file's frontmatter. Errors exit
non-zero; warnings print and do not fail the build.

Contract source: Claude Code docs (sub-agents, tools-reference) as of v2.1.220.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
PLUGINS_DIR = REPO_ROOT / "plugins"
AGENT_GLOB = "*/agents/*.md"

FLOW_SEQ_RE = re.compile(r"^\[(?P<inner>.*)\]$")
BLOCK_ITEM_RE = re.compile(r"^\s*-\s+(?P<item>.+?)\s*$")
KEY_VALUE_RE = re.compile(r"^(?P<key>[A-Za-z_][A-Za-z0-9_-]*):(?P<rest>.*)$")


def parse_frontmatter(text: str) -> tuple[dict[str, object], list[str]]:
    """Parse a frontmatter block into {key: str | list[str]} plus errors.

    Well-formed means: an opening `---` on line 1, a matching closing `---`,
    and every line between them is blank, a `#` comment, a `key: value` pair,
    or a `- item` continuation of a key introduced with an empty value.
    """
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return {}, ["frontmatter does not open with '---' on line 1"]

    end = None
    for index in range(1, len(lines)):
        if lines[index].strip() == "---":
            end = index
            break
    if end is None:
        return {}, ["frontmatter has no closing '---'"]

    fields: dict[str, object] = {}
    errors: list[str] = []
    current_list_key: str | None = None

    for raw in lines[1:end]:
        stripped = raw.strip()
        if not stripped:
            current_list_key = None
            continue
        if stripped.startswith("#"):
            current_list_key = None
            continue

        item_match = BLOCK_ITEM_RE.match(raw)
        if item_match:
            if current_list_key is None:
                errors.append(f"list item with no empty-valued key above it: {stripped!r}")
                continue
            entry = _strip_quotes(item_match.group("item"))
            existing = fields.get(current_list_key)
            if isinstance(existing, list):
                existing.append(entry)
            else:
                fields[current_list_key] = [entry]
            continue

        kv_match = KEY_VALUE_RE.match(raw)
        if not kv_match:
            errors.append(f"line is neither a key: value pair nor a - item: {stripped!r}")
            current_list_key = None
            continue

        key = kv_match.group("key")
        value = kv_match.group("rest").strip()
        if value:
            if _has_inline_comment(value):
                errors.append(f"inline '#' comment after a value on key {key!r}")
            fields[key] = value
            current_list_key = None
        else:
            fields[key] = []
            current_list_key = key

    return fields, errors


def _has_inline_comment(value: str) -> bool:
    """True when a '#' follows whitespace outside quotes and parentheses."""
    depth = 0
    quote: str | None = None
    for index, char in enumerate(value):
        if quote:
            if char == quote:
                quote = None
            continue
        if char in "\"'":
            quote = char
        elif char == "(":
            depth += 1
        elif char == ")":
            depth = max(0, depth - 1)
        elif char == "#" and depth == 0 and index > 0 and value[index - 1].isspace():
            return True
    return False


def _strip_quotes(entry: str) -> str:
    entry = entry.strip()
    if len(entry) >= 2 and entry[0] == entry[-1] and entry[0] in "\"'":
        return entry[1:-1].strip()
    return entry


def split_entries(value: object) -> tuple[list[str], str | None]:
    """Normalise a tools:/disallowedTools: value into a list of entries.

    Accepts exactly three forms: a single-line comma-separated list, a YAML
    block list (already a list here), and a flow sequence [a, b].
    """
    if isinstance(value, list):
        return [_strip_quotes(item) for item in value if _strip_quotes(item)], None

    if not isinstance(value, str):
        return [], f"unsupported value type {type(value).__name__}"

    text = value.strip()
    if text in {">", "|", ">-", "|-"} or text.startswith(("&", "*", "{")):
        return [], f"unsupported value form {text!r} (folded/literal scalar, anchor, alias or map)"

    flow = FLOW_SEQ_RE.match(text)
    if flow:
        text = flow.group("inner")

    entries: list[str] = []
    depth = 0
    buffer: list[str] = []
    for char in text:
        if char == "(":
            depth += 1
        elif char == ")":
            depth = max(0, depth - 1)
        if char == "," and depth == 0:
            entries.append("".join(buffer))
            buffer = []
        else:
            buffer.append(char)
    entries.append("".join(buffer))

    cleaned = [_strip_quotes(entry) for entry in entries]
    return [entry for entry in cleaned if entry], None
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 scripts/test_check_agent_frontmatter.py`
Expected: PASS — `OK` with 15 tests

- [ ] **Step 5: Commit**

```bash
git add scripts/check_agent_frontmatter.py scripts/test_check_agent_frontmatter.py
AV_COMMIT_SKILL=1 git commit -m "feat(scripts): add agent frontmatter parser with tests"
```

---

### Task 2: Version-pinned constants and error checks

**Files:**
- Modify: `scripts/check_agent_frontmatter.py` (append constants and `check_file`)
- Modify: `scripts/test_check_agent_frontmatter.py` (append `TestErrors`)

**Interfaces:**
- Consumes: `parse_frontmatter`, `split_entries` from Task 1.
- Produces: `check_file(path: Path, text: str) -> tuple[list[str], list[str]]` — returns `(errors, warnings)`, each a list of human-readable strings.
- Produces: constants `CANONICAL_TOOLS`, `PERMITTED_KEYS`, `ALWAYS_STRIPPED`, `BACKGROUND_KEPT`, `KNOWN_BAD_TOOLS`, `BACKGROUND_LOST`.

- [ ] **Step 1: Write the failing test**

Add `PurePath` to the existing `from pathlib import Path` line at the top of `scripts/test_check_agent_frontmatter.py` so it reads `from pathlib import Path, PurePath`, and extend the existing `from check_agent_frontmatter import ...` line to also import `check_file`. Then append the following above the `if __name__` block:

```python
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
        self.assertTrue(self._errors("no frontmatter here\n"))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 scripts/test_check_agent_frontmatter.py`
Expected: FAIL — `ImportError: cannot import name 'check_file'`

- [ ] **Step 3: Add constants and checks**

Insert the constants directly after the `KEY_VALUE_RE` line in `scripts/check_agent_frontmatter.py`:

```python
# Source: https://code.claude.com/docs/en/tools-reference
# Verified against Claude Code v2.1.220 on 2026-07-27.
CANONICAL_TOOLS = frozenset({
    "Agent", "Artifact", "AskUserQuestion", "Bash", "CronCreate", "CronDelete",
    "CronList", "Edit", "EndConversation", "EnterPlanMode", "EnterWorktree",
    "ExitPlanMode", "ExitWorktree", "Glob", "Grep", "ListMcpResourcesTool",
    "LSP", "Monitor", "NotebookEdit", "PowerShell", "PushNotification", "Read",
    "ReadMcpResourceTool", "RemoteTrigger", "ReportFindings", "ScheduleWakeup",
    "SendMessage", "SendUserFile", "ShareOnboardingGuide", "Skill",
    "TaskCreate", "TaskGet", "TaskList", "TaskOutput", "TaskStop", "TaskUpdate",
    "TodoWrite", "ToolSearch", "WaitForMcpServers", "WebFetch", "WebSearch",
    "Workflow", "Write",
})

# Source: https://code.claude.com/docs/en/sub-agents#supported-frontmatter-fields
# Verified against Claude Code v2.1.220 on 2026-07-27.
# Fail-closed by choice: a field added after v2.1.220 fails the build until
# this constant is updated. That is the price of catching the next
# `allowed-tools`. See docs/superpowers/specs/2026-07-27-agent-tools-frontmatter-design.md
PERMITTED_KEYS = frozenset({
    "name", "description", "tools", "disallowedTools", "model", "skills",
    "maxTurns", "initialPrompt", "memory", "effort", "background",
    "isolation", "color",
})

# Source: https://code.claude.com/docs/en/sub-agents#available-tools
# Verified against Claude Code v2.1.220 on 2026-07-27.
ALWAYS_STRIPPED = frozenset({
    "AskUserQuestion", "EndConversation", "EnterPlanMode", "ExitPlanMode",
    "ScheduleWakeup", "TaskOutput", "WaitForMcpServers", "Workflow",
})

# Source: https://code.claude.com/docs/en/sub-agents#available-tools
# Verified against Claude Code v2.1.220 on 2026-07-27.
BACKGROUND_KEPT = frozenset({
    "Read", "Grep", "Glob", "Bash", "PowerShell", "Edit", "Write",
    "NotebookEdit", "WebFetch", "WebSearch", "TodoWrite", "Skill", "ToolSearch",
    "EnterWorktree", "ExitWorktree", "Monitor", "TaskStop", "SendMessage",
    "Artifact", "Agent",
})

# Names that are not tools in any Claude Code version, so this gates as an
# error with no staleness risk in the red direction.
# Verified against Claude Code v2.1.220 on 2026-07-27.
KNOWN_BAD_TOOLS = frozenset({"Task"})

BACKGROUND_LOST = CANONICAL_TOOLS - BACKGROUND_KEPT - ALWAYS_STRIPPED

REQUIRED_KEYS = ("name", "description")
TOOL_KEYS = ("tools", "disallowedTools")
```

Append `check_file` and its helper to the end of the module:

```python
def _base_name(entry: str) -> str:
    """Return the ToolName part of a `ToolName(specifier)` entry."""
    return entry.split("(", 1)[0].strip()


def _is_server_grant(entry: str) -> bool:
    """True for `mcp__<server>` and `mcp__<server>__*`, false for per-tool."""
    if not entry.startswith("mcp__"):
        return False
    remainder = entry[len("mcp__"):]
    if "__" not in remainder:
        return True
    return remainder.rsplit("__", 1)[1] == "*"


def check_file(path, text: str) -> tuple[list[str], list[str]]:
    """Return (errors, warnings) for one agent file."""
    errors: list[str] = []
    warnings: list[str] = []

    fields, parse_errors = parse_frontmatter(text)
    if parse_errors:
        return [f"{path}: {message}" for message in parse_errors], []

    for key in sorted(fields):
        if key not in PERMITTED_KEYS:
            errors.append(f"{path}: unknown frontmatter key {key!r}")

    for key in REQUIRED_KEYS:
        if key not in fields or not fields[key]:
            errors.append(f"{path}: missing required key {key!r}")

    if "tools" not in fields:
        warnings.append(f"{path}: no 'tools:' key — this agent inherits every tool")

    for key in TOOL_KEYS:
        if key not in fields:
            continue
        entries, split_error = split_entries(fields[key])
        if split_error:
            errors.append(f"{path}: {key}: {split_error}")
            continue
        for entry in entries:
            base = _base_name(entry)
            if base in KNOWN_BAD_TOOLS:
                errors.append(
                    f"{path}: {key}: {base!r} is not a tool name in any Claude Code version"
                )
                continue
            if key == "tools" and base in ALWAYS_STRIPPED:
                errors.append(
                    f"{path}: tools: {base!r} is stripped from every subagent"
                )
                continue
            if _is_server_grant(base):
                continue
            if base not in CANONICAL_TOOLS:
                warnings.append(
                    f"{path}: {key}: {base!r} is not in the v2.1.220 tool list"
                )
                continue
            if key == "tools" and base in BACKGROUND_LOST:
                warnings.append(
                    f"{path}: tools: {base!r} is unavailable to background subagents"
                )
            if base == "Bash" and ":" in entry and "(" in entry:
                warnings.append(
                    f"{path}: tools: {entry!r} uses the undocumented colon specifier form"
                )

    return errors, warnings
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 scripts/test_check_agent_frontmatter.py`
Expected: PASS — `OK` with 25 tests

- [ ] **Step 5: Commit**

```bash
git add scripts/check_agent_frontmatter.py scripts/test_check_agent_frontmatter.py
AV_COMMIT_SKILL=1 git commit -m "feat(scripts): add contract constants and error checks to the agent validator"
```

---

### Task 3: Warnings, discovery guard, and CLI

**Files:**
- Modify: `scripts/check_agent_frontmatter.py` (append `main`)
- Modify: `scripts/test_check_agent_frontmatter.py` (append `TestWarnings`)

**Interfaces:**
- Consumes: `check_file` from Task 2.
- Produces: `main(argv: list[str] | None = None) -> int` — 0 on success, 1 on any error or empty discovery.
- Produces: module constant `EXPECTED_AGENT_FILES = 25`.

- [ ] **Step 1: Write the failing test**

Extend the existing `from check_agent_frontmatter import ...` line at the top of `scripts/test_check_agent_frontmatter.py` to also import `EXPECTED_AGENT_FILES`. Then append the following above the `if __name__` block:

```python
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

    def test_colon_form_bash_specifier_warns(self):
        text = _agent(name="a", description="d", tools="Read, Bash(git:*)")
        self.assertTrue(any("colon" in w for w in self._warnings(text)))

    def test_space_form_bash_specifier_does_not_warn(self):
        text = _agent(name="a", description="d", tools="Read, Bash(git *)")
        self.assertEqual(self._warnings(text), [])

    def test_missing_tools_key_warns(self):
        text = _agent(name="a", description="d")
        self.assertTrue(any("inherits every tool" in w for w in self._warnings(text)))

    def test_expected_file_count_constant(self):
        self.assertEqual(EXPECTED_AGENT_FILES, 25)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 scripts/test_check_agent_frontmatter.py`
Expected: FAIL — `ImportError: cannot import name 'EXPECTED_AGENT_FILES'`

- [ ] **Step 3: Add the CLI**

Add the constant next to `REQUIRED_KEYS` in `scripts/check_agent_frontmatter.py`:

```python
# Agent files under plugins/*/agents/*.md at the time of the 2026-07-27 audit.
# A lower count warns; it never errors, so a legitimately shrinking tree
# cannot flip the build red.
EXPECTED_AGENT_FILES = 25
```

Append to the end of the module:

```python
def main(argv: list[str] | None = None) -> int:
    del argv  # no options; kept for symmetry with check_plugin_versions.py

    paths = sorted(PLUGINS_DIR.glob(AGENT_GLOB))
    if not paths:
        print(
            f"error: no agent files discovered under {PLUGINS_DIR}/{AGENT_GLOB}",
            file=sys.stderr,
        )
        return 1

    errors: list[str] = []
    warnings: list[str] = []
    for path in paths:
        file_errors, file_warnings = check_file(
            path.relative_to(REPO_ROOT), path.read_text(encoding="utf-8")
        )
        errors.extend(file_errors)
        warnings.extend(file_warnings)

    if len(paths) < EXPECTED_AGENT_FILES:
        warnings.append(
            f"scanned {len(paths)} agent file(s), expected at least "
            f"{EXPECTED_AGENT_FILES} — a shrinking glob is a false pass"
        )

    for line in warnings:
        print(f"  warning: {line}")

    if errors:
        print("\nAgent frontmatter check FAILED:\n", file=sys.stderr)
        for line in errors:
            print(f"  - {line}", file=sys.stderr)
        print(
            "\nAgent capability is declared in 'tools:'. 'allowed-tools' belongs "
            "to skills and commands only. See CLAUDE.md.",
            file=sys.stderr,
        )
        return 1

    print(
        f"\nAgent frontmatter OK: {len(paths)} file(s) scanned, "
        f"{len(warnings)} warning(s)."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 scripts/test_check_agent_frontmatter.py`
Expected: PASS — `OK` with 33 tests

- [ ] **Step 5: Commit**

```bash
git add scripts/check_agent_frontmatter.py scripts/test_check_agent_frontmatter.py
AV_COMMIT_SKILL=1 git commit -m "feat(scripts): add warnings, discovery guard and CLI to the agent validator"
```

---

### Task 4: Capture the red-before evidence

This is the negative control the spec requires: a validator that passes before the fix is not testing anything. It runs in a throwaway detached worktree so nothing writes to the working tree.

**Files:**
- Create: `.superpowers/sdd/2026-07-27-agent-tools-frontmatter/red-before-output.txt` (git-ignored scratch; never committed)

**Interfaces:**
- Consumes: `scripts/check_agent_frontmatter.py` from Task 3.
- Produces: the raw non-zero output that goes into the pull request body.

- [ ] **Step 1: Run the validator against the pre-change tree**

```bash
test ! -e ../av-pre-change || { echo 'path in use — abort'; exit 1; }
git worktree add --detach ../av-pre-change origin/master
cp scripts/check_agent_frontmatter.py ../av-pre-change/scripts/
(cd ../av-pre-change && python3 scripts/check_agent_frontmatter.py) \
  > .superpowers/sdd/2026-07-27-agent-tools-frontmatter/red-before-output.txt 2>&1
echo "exit=$?" >> .superpowers/sdd/2026-07-27-agent-tools-frontmatter/red-before-output.txt
git worktree remove --force ../av-pre-change
```

`--detach` is required so this works from any branch, `master` included. `origin/master` avoids a stale local ref. The `test ! -e` guard exists because `remove --force` would otherwise delete a pre-existing worktree at that path.

- [ ] **Step 2: Verify the output shows the expected failures**

Run: `cat .superpowers/sdd/2026-07-27-agent-tools-frontmatter/red-before-output.txt`
Expected: `Agent frontmatter check FAILED:` followed by fifteen `unknown frontmatter key 'allowed-tools'` lines, two `missing required key` lines for `code-review/agents/fix-auto.md`, one `'Task' is not a tool name` line and one `'TaskOutput' is stripped` line for `web-auditor/agents/web-auditor.md`, and `exit=1`.

If the exit code is 0, stop: the validator is not discriminating and Tasks 1–3 need revisiting before any repair is made.

The file is git-ignored scratch and is never committed. It moves into the pull request body in Task 13.

---

### Task 5: CI workflow

**Files:**
- Create: `.github/workflows/agent-frontmatter.yml`

**Interfaces:**
- Consumes: `scripts/check_agent_frontmatter.py` from Task 3.

- [ ] **Step 1: Write the workflow**

Create `.github/workflows/agent-frontmatter.yml`. The action SHAs are copied verbatim from `.github/workflows/plugin-version-parity.yml` — do not substitute tags.

```yaml
name: Agent Frontmatter

on:
  push:
    branches: [master]
  pull_request:
    branches: [master]

permissions:
  contents: read

concurrency:
  group: agent-frontmatter-${{ github.ref }}
  cancel-in-progress: true

jobs:
  check-agent-frontmatter:
    name: Check agent frontmatter
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - name: Checkout
        uses: actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11  # v4.1.1

      - name: Set up Python
        uses: actions/setup-python@0a5c61591373683505ea898e09a3ea4f39ef2b9c  # v5.0.0
        with:
          python-version: "3.12"

      - name: Run validator unit tests
        run: python3 scripts/test_check_agent_frontmatter.py

      - name: Check agent frontmatter
        run: python3 scripts/check_agent_frontmatter.py
```

- [ ] **Step 2: Verify the SHAs match the reference workflow**

Run: `diff <(grep 'uses:' .github/workflows/plugin-version-parity.yml) <(grep 'uses:' .github/workflows/agent-frontmatter.yml)`
Expected: no output (identical `uses:` lines)

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/agent-frontmatter.yml
AV_COMMIT_SKILL=1 git commit -m "ci: run the agent frontmatter validator on push and pull request"
```

---

### Task 6: Repair qa — be-tester and fe-tester

**Files:**
- Modify: `plugins/qa/agents/be-tester.md:4-5`
- Modify: `plugins/qa/agents/fe-tester.md:4`

**Interfaces:**
- Consumes: `scripts/check_agent_frontmatter.py` from Task 3 (used as the test).

- [ ] **Step 1: Run the validator to confirm both files currently fail**

Run: `python3 scripts/check_agent_frontmatter.py 2>&1 | grep 'qa/agents'`
Expected: one line — `plugins/qa/agents/be-tester.md: unknown frontmatter key 'allowed-tools'`. `fe-tester.md` produces no error (it was repaired in 2.5.1); its change here is the dual-form grant only.

- [ ] **Step 2: Replace be-tester's tools line and delete its allowed-tools line**

In `plugins/qa/agents/be-tester.md`, replace lines 4 and 5 with this single line:

```
tools: Read, Write, Bash, Grep, Glob, mcp__postgres, mcp__postgres__*, mcp__supabase, mcp__supabase__*, mcp__neon, mcp__neon__*, mcp__mysql, mcp__mysql__*, mcp__mongodb, mcp__mongodb__*, mcp__redis, mcp__redis__*
```

- [ ] **Step 3: Put fe-tester on the dual-form grant**

In `plugins/qa/agents/fe-tester.md`, replace line 4 with:

```
tools: Read, Write, Bash, Grep, Glob, mcp__plugin_playwright_playwright, mcp__plugin_playwright_playwright__*, mcp__playwright, mcp__playwright__*
```

- [ ] **Step 4: Run the validator to verify both files are clean**

Run: `python3 scripts/check_agent_frontmatter.py 2>&1 | grep 'qa/agents'`
Expected: no output

- [ ] **Step 5: Commit**

```bash
git add plugins/qa/agents/be-tester.md plugins/qa/agents/fe-tester.md
AV_COMMIT_SKILL=1 git commit -m "fix(qa): grant database and Playwright MCP servers via the tools frontmatter"
```

---

### Task 7: Repair web-auditor — seven scanning agents

**Files:**
- Modify: `plugins/web-auditor/agents/api-security-agent.md:4-5`
- Modify: `plugins/web-auditor/agents/compliance-agent.md:4-5`
- Modify: `plugins/web-auditor/agents/performance-agent.md:4-5`
- Modify: `plugins/web-auditor/agents/seo-agent.md:4-5`
- Modify: `plugins/web-auditor/agents/web-security-agent.md:4-5`
- Modify: `plugins/web-auditor/agents/supply-chain-agent.md:4-5`
- Modify: `plugins/web-auditor/agents/infrastructure-agent.md:5`

**Interfaces:**
- Consumes: `scripts/check_agent_frontmatter.py` from Task 3.

- [ ] **Step 1: Run the validator to confirm the seven files fail**

Run: `python3 scripts/check_agent_frontmatter.py 2>&1 | grep -c 'web-auditor/agents/.*-agent.md'`
Expected: `7`

- [ ] **Step 2: Replace the tools line in the five identical agents**

In each of `api-security-agent.md`, `compliance-agent.md`, `performance-agent.md`, `seo-agent.md`, `web-security-agent.md`, replace lines 4 and 5 with this single line:

```
tools: Read, Bash, Grep, Glob, mcp__plugin_playwright_playwright, mcp__plugin_playwright_playwright__*, mcp__playwright, mcp__playwright__*
```

- [ ] **Step 3: Replace supply-chain-agent's tools line**

In `plugins/web-auditor/agents/supply-chain-agent.md`, replace lines 4 and 5 with:

```
tools: Read, Bash, Grep, Glob, WebSearch, mcp__plugin_playwright_playwright, mcp__plugin_playwright_playwright__*, mcp__playwright, mcp__playwright__*
```

- [ ] **Step 4: Delete infrastructure-agent's allowed-tools line only**

In `plugins/web-auditor/agents/infrastructure-agent.md`, delete line 5 entirely. Line 4 stays exactly as it is: `tools: Read, Bash, Grep, Glob, WebFetch`. This agent receives no Playwright grant — its checklist skill has no browser references.

- [ ] **Step 5: Run the validator to verify all seven are clean**

Run: `python3 scripts/check_agent_frontmatter.py 2>&1 | grep 'web-auditor/agents/.*-agent.md'`
Expected: no output

- [ ] **Step 6: Commit**

```bash
git add plugins/web-auditor/agents/api-security-agent.md \
        plugins/web-auditor/agents/compliance-agent.md \
        plugins/web-auditor/agents/performance-agent.md \
        plugins/web-auditor/agents/seo-agent.md \
        plugins/web-auditor/agents/web-security-agent.md \
        plugins/web-auditor/agents/supply-chain-agent.md \
        plugins/web-auditor/agents/infrastructure-agent.md
AV_COMMIT_SKILL=1 git commit -m "fix(web-auditor): grant Playwright MCP to the six scanning agents that use it"
```

---

### Task 8: Repair the web-auditor coordinator — frontmatter and body

This is the only task that rewrites prose. The coordinator declares `Task`, which is not a tool in any Claude Code version, so it has never been able to spawn anything; and it collects results through `TaskOutput`, which is stripped from every subagent.

**Files:**
- Modify: `plugins/web-auditor/agents/web-auditor.md:4-5` (frontmatter)
- Modify: `plugins/web-auditor/agents/web-auditor.md` (body: lines 186, 195, 197, 210, 212, 226, 228, 240, 242, 257, 259, 278, 280, 298, 300, 336, 339, 341, 359, 362, 364, 378, 381, 382, 404)
- Modify: `plugins/web-auditor/commands/audit.md:72,75`

**Interfaces:**
- Consumes: `scripts/check_agent_frontmatter.py` from Task 3.

- [ ] **Step 1: Record the pre-change counts**

```bash
F=plugins/web-auditor/agents/web-auditor.md
grep -c 'Task(' $F; grep -c 'run_in_background: true' $F; grep -c 'TaskOutput' $F; grep -c '(background)' $F
grep -c 'Task(\|Task tool' plugins/web-auditor/commands/audit.md
```

Expected: `9`, `9`, `4`, `2`, and `2`.

- [ ] **Step 2: Replace the frontmatter tools line**

In `plugins/web-auditor/agents/web-auditor.md`, replace lines 4 and 5 with this single line. `Task` becomes `Agent`, `TaskOutput` is dropped because it is stripped from every subagent regardless of declaration:

```
tools: Read, Write, Bash, Grep, Glob, Agent, WebFetch, WebSearch, mcp__plugin_playwright_playwright, mcp__plugin_playwright_playwright__*, mcp__playwright, mcp__playwright__*
```

- [ ] **Step 3: Rewrite the nine dispatch sites**

At each of the nine `Task(` call sites, change the tool name to `Agent(` and the background flag to `false`:

```bash
python3 - <<'PY'
from pathlib import Path
p = Path("plugins/web-auditor/agents/web-auditor.md")
text = p.read_text(encoding="utf-8")
text = text.replace("Task(", "Agent(")
text = text.replace("run_in_background: true", "run_in_background: false")
p.write_text(text, encoding="utf-8")
PY
grep -c 'Agent(' plugins/web-auditor/agents/web-auditor.md
grep -c 'run_in_background: false' plugins/web-auditor/agents/web-auditor.md
```

Expected: `9` and `10`. The tenth `run_in_background: false` is the Phase 2 lead-in at line 186, which Step 4 rewrites away.

- [ ] **Step 4: Re-word the Phase 2 lead-in**

Line 186 currently reads:

```
Launch agents in parallel (all with `run_in_background: true`) based on the requested scope.
```

Replace it with — note it carries no `run_in_background` token, which is why the post-write count is nine and not ten:

```
Launch the in-scope agents in parallel, in a single turn, and read each result inline.
```

- [ ] **Step 5: Drop the two `(background)` step labels**

Line 336: `**2. Spawn Cross-Verifier (background)**` becomes `**2. Spawn Cross-Verifier**`
Line 359: `**3. Spawn Challenger (background)**` becomes `**3. Spawn Challenger**`

- [ ] **Step 6: Rewrite the four TaskOutput sites**

Line 378 (the Phase 2.5 lead-in directing both calls):

```
Both dispatches above return their result inline; read them directly:
```

Lines 381–382 currently read:

```
cross_verifier_results = TaskOutput(cross_verifier_id, block: true)
challenger_results = TaskOutput(challenger_id, block: true)
```

Replace them with, each naming the single dispatch whose inline result it reads:

```
cross_verifier_results = the value returned by the Cross-Verifier Agent( call in step 2
challenger_results = the value returned by the Challenger Agent( call in step 3
```

Line 404 (the Phase 3 collect step) — note it refers to the in-scope scanners, not to seven always, because dispatch is scope-gated:

```
1. **Collect results** — the in-scope scanning agents returned their results inline in Phase 2; read them directly.
```

- [ ] **Step 7: Rewrite the two sites in the command file**

In `plugins/web-auditor/commands/audit.md`, line 72 becomes:

```
Launch the web-auditor coordinator agent using the Agent tool:
```

and line 75's `Task(` becomes `Agent(`. The coordinator's own dispatch mode is unchanged: line 75 passes no `run_in_background` argument today and gains none, so the coordinator keeps running under the documented background default.

- [ ] **Step 8: Run the post-write assertions**

```bash
F=plugins/web-auditor/agents/web-auditor.md
echo "absence (all must be 0):"
grep -c 'Task(' $F; grep -c 'TaskOutput' $F; grep -c 'run_in_background: true' $F; grep -c '(background)' $F; grep -c 'Task tool' $F
echo "presence:"
grep -c 'Agent(' $F; grep -c 'run_in_background: false' $F
echo "audit.md absence (both 0):"
grep -c 'Task(' plugins/web-auditor/commands/audit.md; grep -c 'Task tool' plugins/web-auditor/commands/audit.md
echo "audit.md presence (1):"
grep -c 'Agent(' plugins/web-auditor/commands/audit.md
```

Expected: five zeros, then `9` and `9`, then two zeros, then `1`.

Absence alone is not the pass condition — deleting the text would satisfy every absence check while leaving the coordinator collecting nothing. The presence counts are what distinguish a rewrite from a deletion.

- [ ] **Step 9: Run the validator**

Run: `python3 scripts/check_agent_frontmatter.py 2>&1 | grep 'web-auditor'`
Expected: no output

- [ ] **Step 10: Commit**

```bash
git add plugins/web-auditor/agents/web-auditor.md plugins/web-auditor/commands/audit.md
AV_COMMIT_SKILL=1 git commit -m "fix(web-auditor): give the coordinator the Agent tool and inline result collection"
```

---

### Task 9: Repair code-review — fix-auto identity, security-auditor, code-quality-auditor

**Files:**
- Modify: `plugins/code-review/agents/fix-auto.md:2` (replace the lone `allowed-tools:` line with four keys)
- Modify: `plugins/code-review/agents/security-auditor.md:5` (delete)
- Modify: `plugins/code-review/agents/code-quality-auditor.md:5` (delete)

**Interfaces:**
- Consumes: `scripts/check_agent_frontmatter.py` from Task 3.

- [ ] **Step 1: Run the validator to confirm the three files fail**

Run: `python3 scripts/check_agent_frontmatter.py 2>&1 | grep 'code-review/agents'`
Expected: four lines — an `unknown frontmatter key 'allowed-tools'` for each of the three files, plus `missing required key 'name'` and `missing required key 'description'` for `fix-auto.md`.

- [ ] **Step 2: Give fix-auto an identity and an explicit tool list**

`plugins/code-review/agents/fix-auto.md` currently has a single frontmatter line. Replace line 2 with these four lines. `Skill` is in the list because the body invokes `developer-plugins-integration` through the Skill tool at line 105 and the file declares no `skills:` key, so the preload path other agents rely on is unavailable to it:

```yaml
name: fix-auto
description: Applies a fix for a single code review issue end to end — analysis, implementation, verification, and reporting. Invoked as a subagent by the review, fix-report, and fix-all commands.
tools: Read, Edit, Write, Glob, Grep, Bash, Skill, TaskCreate, TaskUpdate, TaskList
model: opus
```

- [ ] **Step 3: Delete the two inert allowed-tools lines**

Delete line 5 from `plugins/code-review/agents/security-auditor.md` and line 5 from `plugins/code-review/agents/code-quality-auditor.md`. Their `tools:` lines are unchanged: both keep `Read, Bash, Grep, Glob`. Least-privilege narrowing is deferred to a follow-up that must first design a test measuring tool availability.

- [ ] **Step 4: Run the validator**

Run: `python3 scripts/check_agent_frontmatter.py 2>&1 | grep 'code-review/agents'`
Expected: no output

- [ ] **Step 5: Verify fix-auto is no longer anonymous**

Run: `head -6 plugins/code-review/agents/fix-auto.md`
Expected: the four keys above between `---` delimiters.

- [ ] **Step 6: Commit**

```bash
git add plugins/code-review/agents/fix-auto.md \
        plugins/code-review/agents/security-auditor.md \
        plugins/code-review/agents/code-quality-auditor.md
AV_COMMIT_SKILL=1 git commit -m "fix(code-review): give fix-auto a name and an explicit tool list"
```

---

### Task 10: Repair the three developer agents

These three declare a TDD workflow but have no `Bash` in `tools:`, so they cannot run a test, a linter or a typechecker. The literal string `Bash` appears in each file only on the `allowed-tools:` line being deleted; the grant follows from the commands their bodies name (`pytest`, `ruff`, `tsc`, `composer`, `git`).

**Files:**
- Modify: `plugins/frontend-developer/agents/developer.md:4-5`
- Modify: `plugins/python-developer/agents/developer.md:4-5`
- Modify: `plugins/php-developer/agents/developer.md:4-5`

**Interfaces:**
- Consumes: `scripts/check_agent_frontmatter.py` from Task 3.

- [ ] **Step 1: Run the validator to confirm the three files fail**

Run: `python3 scripts/check_agent_frontmatter.py 2>&1 | grep 'developer/agents/developer.md'`
Expected: three `unknown frontmatter key 'allowed-tools'` lines.

- [ ] **Step 2: Add Bash and delete the allowed-tools line in each file**

In each of the three files, replace lines 4 and 5 with this single line:

```
tools: Read, Edit, Write, Glob, Grep, Skill, Bash, TaskCreate, TaskUpdate, TaskList
```

Note `model: opus ` on line 6 of these files carries a trailing space. Leave it — the parser accepts it and changing it is out of scope.

- [ ] **Step 3: Run the validator**

Run: `python3 scripts/check_agent_frontmatter.py 2>&1 | grep 'developer/agents/developer.md'`
Expected: no output

- [ ] **Step 4: Run the full validator and confirm the tree is green**

Run: `python3 scripts/check_agent_frontmatter.py; echo "exit=$?"`
Expected: warning lines for `TaskCreate`/`TaskUpdate`/`TaskList` on the four agents that declare them, one colon-form warning for `code-review/agents/feedback-analyzer.md`, then `Agent frontmatter OK: 25 file(s) scanned` and `exit=0`.

This is the green half of the negative control recorded in Task 4.

- [ ] **Step 5: Commit**

```bash
git add plugins/frontend-developer/agents/developer.md \
        plugins/python-developer/agents/developer.md \
        plugins/php-developer/agents/developer.md
AV_COMMIT_SKILL=1 git commit -m "fix(developers): grant Bash so the TDD workflow can run tests and linters"
```

---

### Task 11: Body reconciliation

The post-write run of the only check that can catch an under-declared list. It greps each written file against **its own `tools:` line**, not against the spec's table, so a transcription slip is caught. Its raw output goes into the pull request body; the author's verdict is advisory and the gate is a reviewer re-running these commands against the branch's checked-out files.

**Files:**
- Create: `.superpowers/sdd/2026-07-27-agent-tools-frontmatter/body-reconciliation-output.txt` (scratch evidence, deleted in Task 13)

**Interfaces:**
- Consumes: every repair from Tasks 6–10.

- [ ] **Step 1: Run the pinned greps over the reconciliation surface**

The surface is each agent body plus every `SKILL.md` named in its `skills:` frontmatter, plus every `SKILL.md` the body invokes through the `Skill` tool. Every `allowed-tools:` line is excluded from the hit set, in agent and skill files alike — counting them is what makes a naive grep pass vacuously.

```bash
{
  for f in plugins/*/agents/*.md; do
    echo "=== $f"
    grep -nE 'Task[A-Za-z]*|mcp__|browser_[a-z_]*|Playwright|Postgres|PostgreSQL|Supabase|Neon|MySQL|MongoDB|Redis|\b(Skill|Agent|WebFetch|WebSearch|Bash|Read|Edit|Write|Glob|Grep)\b' "$f" \
      | grep -v '^[0-9]*:allowed-tools:'
  done
  echo "=== linked skills"
  for f in plugins/qa/skills/*/SKILL.md plugins/web-auditor/skills/*/SKILL.md plugins/code-review/skills/developer-plugins-integration/SKILL.md; do
    echo "--- $f"
    grep -nE 'mcp__|browser_[a-z_]*|Playwright|Postgres|Supabase|Neon|MySQL|MongoDB|Redis' "$f" \
      | grep -v '^4:allowed-tools:'
  done
} > .superpowers/sdd/2026-07-27-agent-tools-frontmatter/body-reconciliation-output.txt 2>&1
wc -l .superpowers/sdd/2026-07-27-agent-tools-frontmatter/body-reconciliation-output.txt
```

- [ ] **Step 2: Check every hit against that file's own tools line**

A hit is a *reference* when it is a call site or an instruction directing the agent to invoke that tool; a bare prose mention is not. *Covered* is not *named*: a built-in is covered by its canonical name, and an MCP tool is covered by a **server-level** entry for the server that provides it — never by a per-tool entry. A `browser_*` hit is therefore satisfied by the Playwright server grants.

Two classes produce no usable hits and are known blind spots, not failures:

- **`Bash`** — the four agents that gain it never name it; they name commands.
- **MCP entries** — only `plugins/qa/skills/be-testing/SKILL.md:36-39` names servers verbatim. Everywhere else the surface says `browser_*`.

Expected: no referenced tool is missing from its agent's `tools:` line. If one is, add it to that agent's `tools:` line and re-run — the body governs.

The file is git-ignored scratch and is never committed. It moves into the pull request body in Task 13.

---

### Task 12: Version bumps across four surfaces

Six plugins bump by PATCH. Every change repairs a declaration that never granted a tool, and none adds or removes a plugin-level feature. Two carry a deliberate behaviour change inside that repair — `fix-auto` narrows from full inheritance to an explicit list, and the `web-auditor` dispatches move to the foreground.

`docs/plugins/qa.md` is additionally carried from 2.5.0 to 2.5.2: it was left behind by the 2.5.1 bump, which is why `check_plugin_versions.py` fails on `master` today.

**Files:**
- Modify: `plugins/{qa,web-auditor,code-review,frontend-developer,python-developer,php-developer}/.claude-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json`
- Modify: `README.md` (six rows in the Available Plugins table)
- Modify: `docs/plugins/{qa,web-auditor,code-review,frontend-developer,python-developer,php-developer}.md` (`**Version:**` header)

**Interfaces:**
- Consumes: `scripts/check_plugin_versions.py` (existing) as the test.

- [ ] **Step 1: Confirm parity currently fails**

Run: `python3 scripts/check_plugin_versions.py; echo "exit=$?"`
Expected: `[qa] version mismatch: plugin.json=2.5.1, marketplace.json=2.5.1, README.md=2.5.1, docs/plugins/qa.md=2.5.0` and `exit=1`

- [ ] **Step 2: Apply all four surfaces for all six plugins**

| Plugin | From | To |
| --- | --- | --- |
| qa | 2.5.1 | 2.5.2 |
| web-auditor | 2.1.1 | 2.1.2 |
| code-review | 1.17.0 | 1.17.1 |
| frontend-developer | 1.2.0 | 1.2.1 |
| python-developer | 3.0.3 | 3.0.4 |
| php-developer | 1.0.2 | 1.0.3 |

```bash
python3 - <<'PY'
import json, re
from pathlib import Path

BUMPS = {
    "qa": ("2.5.1", "2.5.2"),
    "web-auditor": ("2.1.1", "2.1.2"),
    "code-review": ("1.17.0", "1.17.1"),
    "frontend-developer": ("1.2.0", "1.2.1"),
    "python-developer": ("3.0.3", "3.0.4"),
    "php-developer": ("1.0.2", "1.0.3"),
}

for slug, (_old, new) in BUMPS.items():
    p = Path(f"plugins/{slug}/.claude-plugin/plugin.json")
    data = json.loads(p.read_text(encoding="utf-8"))
    data["version"] = new
    p.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

mp = Path(".claude-plugin/marketplace.json")
data = json.loads(mp.read_text(encoding="utf-8"))
for entry in data["plugins"]:
    if entry["name"] in BUMPS:
        entry["version"] = BUMPS[entry["name"]][1]
mp.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

readme = Path("README.md")
text = readme.read_text(encoding="utf-8")
for slug, (old, new) in BUMPS.items():
    text = re.sub(
        rf"(\|\s*\[[^\]]+\]\(docs/plugins/{re.escape(slug)}\.md\)\s*\|\s*){re.escape(old)}(\s*\|)",
        rf"\g<1>{new}\g<2>",
        text,
    )
readme.write_text(text, encoding="utf-8")

for slug, (_old, new) in BUMPS.items():
    d = Path(f"docs/plugins/{slug}.md")
    text = d.read_text(encoding="utf-8")
    text = re.sub(r"^\*\*Version:\*\*\s*\S+", f"**Version:** {new}", text, count=1, flags=re.M)
    d.write_text(text, encoding="utf-8")
PY
```

- [ ] **Step 3: Verify parity passes**

Run: `python3 scripts/check_plugin_versions.py; echo "exit=$?"`
Expected: `Version parity OK for 9 plugin(s).` and `exit=0`

- [ ] **Step 4: Verify the JSON files did not lose formatting**

Run: `git diff --stat .claude-plugin/marketplace.json plugins/*/.claude-plugin/plugin.json`
Expected: one changed line per plugin.json and six changed lines in marketplace.json. If any file shows a wholesale rewrite, the JSON indent does not match the repository's — restore it with `git checkout -- <file>` and edit those files by hand instead.

- [ ] **Step 5: Commit**

```bash
git add plugins/*/.claude-plugin/plugin.json .claude-plugin/marketplace.json README.md docs/plugins/
AV_COMMIT_SKILL=1 git commit -m "chore(release): bump six plugins across all four parity surfaces"
```

---

### Task 13: Tracked CLAUDE.md, status record, and scratch cleanup

`CLAUDE.local.md` is excluded by `.gitignore:3`, so a rule written there never reaches the branch, the pull request, or another contributor — which is precisely how the four-surface versioning rule drifted in the first place.

**Files:**
- Create: `CLAUDE.md`
- Create: `docs/agent-tools-verification.md`
- Read (do not commit): the two git-ignored evidence files from Tasks 4 and 11

**Interfaces:**
- Consumes: the raw outputs from Tasks 4 and 11, which move into the pull request body before deletion.

- [ ] **Step 1: Create the tracked authoring rules**

Create `CLAUDE.md`:

```markdown
# Repository Rules

## Agent frontmatter

Agent capability is declared in `tools:`. Claude Code does not support
`allowed-tools:` for subagents — it contributes nothing to the resolved tool
grant. `allowed-tools` is valid in `SKILL.md` and command frontmatter, where it
pre-approves permission prompts without affecting availability.

MCP servers are granted with `mcp__<server>` or `mcp__<server>__*`. Never
enumerate individual MCP tools: those lists drift.

`scripts/check_agent_frontmatter.py` enforces this on every pull request.

## Plugin versioning

When modifying a plugin, update its version following SemVer, in **all four**
places `scripts/check_plugin_versions.py` checks:

1. `plugins/<name>/.claude-plugin/plugin.json`
2. `.claude-plugin/marketplace.json`
3. The plugin's row in the README "Available Plugins" table
4. The `**Version:**` header in `docs/plugins/<name>.md`

Missing the fourth is how `docs/plugins/qa.md` drifted a release behind.

## Marketplace registration

A new plugin is registered in `.claude-plugin/marketplace.json` with `name`,
`source`, `description`, `version` and `category`.
```

- [ ] **Step 2: Create the live-layer status record**

Create `docs/agent-tools-verification.md`. Sixteen rows: fifteen seeded `pending`, `php-developer:developer` seeded `not installed`.

```markdown
# Agent tool verification status

Records the live layer of the repair in
`docs/superpowers/specs/2026-07-27-agent-tools-frontmatter-design.md`: comparing
each agent's harness-resolved tool list against its target.

A row reads `matched — <version>` only when its Resolved list column carries the
harness's resolved list verbatim. A row reverts to `pending` when its recorded
version is older than the shipped version, or when its Resolved list no longer
matches that agent's current `tools:` value entry for entry.

A match is *declaration-confirmed*, not verified: the registry echoes the declared
list, so it cannot confirm that any entry resolves to a callable tool.

| Agent | Status | Resolved list |
| --- | --- | --- |
| `qa:be-tester` | pending | |
| `qa:fe-tester` | pending | |
| `web-auditor:api-security-agent` | pending | |
| `web-auditor:compliance-agent` | pending | |
| `web-auditor:performance-agent` | pending | |
| `web-auditor:seo-agent` | pending | |
| `web-auditor:web-security-agent` | pending | |
| `web-auditor:supply-chain-agent` | pending | |
| `web-auditor:infrastructure-agent` | pending | |
| `web-auditor:web-auditor` | pending | |
| `code-review:fix-auto` | pending | |
| `code-review:security-auditor` | pending | |
| `code-review:code-quality-auditor` | pending | |
| `frontend-developer:developer` | pending | |
| `python-developer:developer` | pending | |
| `php-developer:developer` | not installed | absent from `~/.claude/settings.json`; statically checked only |
```

- [ ] **Step 3: Carry the scratch evidence into the pull request body**

Copy the contents of the two git-ignored evidence files into the pull request description under headings "Red-before evidence" and "Body reconciliation", together with the commands that produced them. Nothing is deleted — the files live in the git-ignored workspace and disappear with it.

- [ ] **Step 4: Run both validators one final time**

```bash
python3 scripts/test_check_agent_frontmatter.py
python3 scripts/check_agent_frontmatter.py; echo "frontmatter exit=$?"
python3 scripts/check_plugin_versions.py; echo "parity exit=$?"
```

Expected: `OK` for the unit tests, and `exit=0` for both checks.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md docs/agent-tools-verification.md
AV_COMMIT_SKILL=1 git commit -m "docs: track the agent authoring rules and the live verification status record"
```

---

## After the plan

The branch is ready for a pull request. Do not push without the maintainer asking.

The pull request body must carry, per the spec's verification contract:

- the red-before command and its raw non-zero output (Task 4)
- the body reconciliation commands and their raw output (Task 11)
- a note that a green CI run is conformance to rules this change itself authored, and is never reported as verification

Deferred, and recorded in the spec's Residual risks — do not do these here:

- `Task(` prose in `code-review/commands/*.md`, `qa/commands/*.md` and `superutils/commands/spec-review.md`
- `allowed-tools` **values** in `SKILL.md` and command frontmatter that still name `Task`, `TaskOutput` or `browser_run_code`
- least-privilege `Bash` narrowing, which needs an availability test first
- the `/web-auditor:audit` run that would measure whether the dispatch repair actually works
