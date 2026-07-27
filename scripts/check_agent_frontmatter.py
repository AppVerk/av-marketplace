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
