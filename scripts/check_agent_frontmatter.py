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

# Agent files under plugins/*/agents/*.md at the time of the 2026-07-27 audit.
# A lower count warns; it never errors, so a legitimately shrinking tree
# cannot flip the build red.
EXPECTED_AGENT_FILES = 25


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
                    f"{path}: {key}: {entry!r} uses the undocumented colon specifier form"
                )

    return errors, warnings


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
