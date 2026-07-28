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
from pathlib import Path, PurePath

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
# `allowed-tools`. See CLAUDE.md for the authoring rules this enforces.
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

# Tools whose grants take a `Tool(specifier)` form, so the undocumented
# `Tool(cmd:*)` spelling is a plausible mistake worth warning about.
COLON_SPECIFIER_TOOLS = frozenset({"Bash", "PowerShell"})

# Agent files under plugins/*/agents/*.md at the time of the 2026-07-27 audit.
# A lower count warns; it never errors, so a legitimately shrinking tree
# cannot flip the build red.
EXPECTED_AGENT_FILES = 25


def _comment_error(key: str) -> str:
    """The one wording for a '#' comment in a value, shared by both spellings.

    `tools: Read # x` and its block-list twin are the same defect, so they get
    the same error. Only the `key: value` branch ever ran the check, which let
    `- Bash(gh issue view #123)` — PyYAML reads it as 'Bash(gh issue view' —
    pass while the byte-identical comma form failed the build.
    """
    return (
        f"'#' comment in the value on key {key!r} — YAML drops "
        "everything from the '#' onward"
    )


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
            item = item_match.group("item")
            # On the raw item and before _strip_quotes, exactly as the
            # `key: value` branch checks its raw value: YAML truncates a block
            # item at the ' #' just as it truncates a scalar on a key line.
            if _has_inline_comment(item):
                errors.append(_comment_error(current_list_key))
            entry = _strip_quotes(item)
            existing = fields[current_list_key]
            if not isinstance(existing, list):
                # Unreachable: current_list_key is only ever assigned right
                # after `fields[key] = []`, and every other branch clears it.
                raise AssertionError(
                    f"list key {current_list_key!r} holds a non-list value"
                )
            existing.append(entry)
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
                errors.append(_comment_error(key))
            fields[key] = value
            current_list_key = None
        else:
            fields[key] = []
            current_list_key = key

    return fields, errors


def _scan(value: str) -> tuple[list[tuple[int, bool]], str | None]:
    """Per-character (paren depth, inside-a-quote) marks, plus a defect reason.

    This is the module's one balance rule. Round 1 shipped two — this
    quote-aware one, and a quote-blind copy inside `split_entries` that
    rejected `Bash(grep "foo(" src)` as unbalanced. Every caller now reads this
    scan, so one value can never be balanced for one check and unbalanced for
    another.

    Quotes suspend paren accounting: a '(' inside "..." or '...' is literal
    text, not a nesting level. `reason` is None when the value scans cleanly;
    when it is not, the marks are unreliable from the defect onward and callers
    must not index them.

    An odd number of quote characters leaves a quote open, which suspends paren
    accounting to end of string and swallows the closing ')'. Reporting that as
    "unbalanced '('" sent round 4 hunting a parenthesis that was there all
    along, so the open quote is named first and in its own words.
    """
    marks: list[tuple[int, bool]] = []
    depth = 0
    quote: str | None = None
    for char in value:
        if quote is not None:
            marks.append((depth, True))
            if char == quote:
                quote = None
            continue
        if char in "\"'":
            quote = char
            marks.append((depth, True))
            continue
        if char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if depth < 0:
                return marks, "unbalanced ')'"
        marks.append((depth, False))
    if quote is not None:
        kind = "single" if quote == "'" else "double"
        return marks, f"unterminated {kind} quote"
    if depth != 0:
        return marks, "unbalanced '('"
    return marks, None


def _imbalance(value: str) -> str | None:
    """The scan's defect reason for `value`, or None when it scans cleanly."""
    return _scan(value)[1]


def _closing_quote(value: str) -> int:
    """Index of the quote closing a value that opens with one, or -1.

    In a single-quoted YAML scalar `''` is an escaped apostrophe, not the end
    of the scalar: PyYAML reads `'it''s # x'` as "it's # x". Stopping at the
    first half of the pair put the closing quote before the '#' and reported a
    comment inside the scalar.
    """
    if not value:
        return -1
    quote = value[0]
    index = 1
    while index < len(value):
        if value[index] != quote:
            index += 1
            continue
        if quote == "'" and value[index + 1 : index + 2] == "'":
            index += 2
            continue
        return index
    return -1


def _has_inline_comment(value: str) -> bool:
    """True when a '#' starts a YAML comment in this value.

    A '#' at the very start counts: YAML reads `description: #x` as null, so
    the key is absent at runtime however much text follows it here.

    A quote quotes only when the value *opens* with one — that is the sole
    shape YAML reads as a quoted scalar. In a plain scalar an apostrophe is an
    apostrophe: honouring the one in "the plugin's tools # TODO" as an opening
    quote swallowed the rest of the line and let the comment through.

    Parentheses mask nothing. YAML applies no paren rule to a plain scalar, it
    truncates at the ' #' regardless of nesting: PyYAML reads
    `tools: Read, Bash(gh issue view #123), Grep` as 'Read, Bash(gh issue view'
    — Grep is gone from the grant and the surviving specifier is malformed. The
    paren mask that used to stand here reported neither.
    """
    start = 0
    if value[:1] in ('"', "'"):
        closing = _closing_quote(value)
        # Only text past the closing quote can be a comment. An unterminated
        # quoted scalar is malformed YAML either way, so scan it whole rather
        # than let the dangling quote hide anything.
        start = closing + 1 if closing != -1 else 0

    for index in range(start, len(value)):
        if value[index] != "#":
            continue
        # A '#' needs whitespace in front of it to open a comment, or
        # `description: Reviews PR#123 now` would read as truncated. The one
        # exception is the character right after a quoted scalar's closing
        # quote: that position is already outside the scalar, and PyYAML reads
        # `description: "Does things"#TODO` as 'Does things'.
        if index and index != start and not value[index - 1].isspace():
            continue
        return True
    return False


def _strip_quotes(entry: str) -> str:
    entry = entry.strip()
    if len(entry) >= 2 and entry[0] == entry[-1] and entry[0] in "\"'":
        return entry[1:-1].strip()
    return entry


def _unwrap_quoted_value(text: str) -> str:
    """Unwrap a value that is one whole quoted scalar: `tools: "Read, Grep"`.

    Only when the opening quote's match is the last character. `"Read", 'Grep'`
    also opens and ends with a quote, and unwrapping that would fuse two
    entries into one malformed name. Stripping this before the split is what
    makes the quoted spellings of a list agree with the bare one, instead of
    warning that 'Read, Grep' is not a tool.
    """
    if text[:1] not in ('"', "'"):
        return text
    if _closing_quote(text) != len(text) - 1:
        return text
    return text[1:-1].strip()


def split_entries(value: object) -> tuple[list[str], str | None, list[str]]:
    """Normalise a tools:/disallowedTools: value into (entries, error, warnings).

    Accepts exactly three forms: a single-line comma-separated list, a YAML
    block list (already a list here), and a flow sequence [a, b].

    Parens and quotes both hide the commas inside a `Bash(a,b)` specifier, so
    the scan tracks both. When the scan reports a defect the value is *not*
    rejected: it is re-split quote-blind and paren-blind, so every entry still
    reaches the caller's name checks, and the defect is reported as a warning.

    That fallback is the design. Wiring the verdict to a build-failing error
    made every imprecision in this hand-rolled YAML emulator a false build
    failure, and three review rounds traded one class for the next —
    `Bash(grep "foo(" src)` in round 2, `Bash(echo don't)` in round 4. The
    fail-open the error was meant to close (a stray '(' pinning the depth above
    zero, gluing `Task` onto its neighbour and hiding it) is closed just as
    well by splitting anyway, and a genuinely malformed entry then surfaces
    through the ordinary name checks on its own merits.

    Two limits of that design, recorded here so a later round does not
    rediscover them as new criticals and re-open the oscillation:

    The fail-open is closed for an *unbalanced* paren only. A moved one still
    hides an entry:
    `Bash(npm run build, Task, Grep)` — the value meant to read
    `Bash(npm run build), Task, Grep` — scans clean, so the split keeps it
    whole, the fused entry's base name is `Bash`, and `Task` goes unreported
    while the `Grep` grant is silently dropped. Any paren-aware splitter has
    this blind spot: nothing distinguishes that value from a legitimate
    specifier that happens to contain commas.

    And a value YAML parses verbatim can still fail the build, in one narrow
    shape: an odd quote sends a paren-balanced value down the paren-blind
    fallback, which then reads a comma token *inside* a specifier as a
    top-level entry. `Read, Bash(git log --author=O'Brien, Workflow, x)` errors
    on `Workflow`; remove the apostrophe and it is clean. It takes an odd quote
    *and* an exact ALWAYS_STRIPPED or KNOWN_BAD_TOOLS name as a comma token in
    the same specifier. Teaching the fallback to avoid it is precisely what
    rounds 1-5 oscillated over, so it stays documented rather than fixed.

    Block-list items get the same scan. They are one entry per line, so a stray
    paren cannot swallow its neighbours, but leaving the branch unchecked made
    one spelling of a value report a defect and the byte-identical other
    spelling stay silent.
    """
    if isinstance(value, list):
        warnings: list[str] = []
        for item in value:
            reason = _imbalance(item)
            if reason:
                warnings.append(f"{reason} in item {item!r}")
        entries = [_strip_quotes(item) for item in value]
        return [entry for entry in entries if entry], None, warnings

    if not isinstance(value, str):
        return [], f"unsupported value type {type(value).__name__}", []

    text = value.strip()
    if text in {">", "|", ">-", "|-"} or text.startswith(("&", "*", "{")):
        return (
            [],
            f"unsupported value form {text!r} (folded/literal scalar, anchor, alias or map)",
            [],
        )

    original = text
    text = _unwrap_quoted_value(text)
    flow = FLOW_SEQ_RE.match(text)
    if flow:
        text = flow.group("inner")

    marks, imbalance = _scan(text)
    warnings = []
    if imbalance:
        warnings.append(f"{imbalance} in value {original!r}")
        # Quote-blind and paren-blind on purpose: the marks cannot be trusted
        # past the defect, and every entry still has to reach the name checks.
        entries = text.split(",")
    else:
        entries = []
        buffer: list[str] = []
        for char, (depth, quoted) in zip(text, marks):
            if char == "," and depth == 0 and not quoted:
                entries.append("".join(buffer))
                buffer = []
            else:
                buffer.append(char)
        entries.append("".join(buffer))

    cleaned = [_strip_quotes(entry) for entry in entries]
    return [entry for entry in cleaned if entry], None, warnings


def _base_name(entry: str) -> str:
    """Return the ToolName part of a `ToolName(specifier)` entry.

    A leading '(' is dropped first. Only a malformed value can produce one — a
    legal entry names its tool before the specifier — and keeping it made
    `Read, (Task` split into an entry whose base was '', so KNOWN_BAD_TOOLS
    never matched and the name check reported '' instead of Task.
    """
    return entry.lstrip("(").split("(", 1)[0].strip()


def _is_server_grant(entry: str) -> bool:
    """True for `mcp__<server>` and `mcp__<server>__*`, false for per-tool.

    The server segment must be non-empty and must not itself contain `__`:
    `mcp__` names no server, and `mcp__a__b__*` is a per-tool prefix wearing a
    star, not a whole-server grant.
    """
    if not entry.startswith("mcp__"):
        return False
    server = entry[len("mcp__"):]
    if server.endswith("__*"):
        server = server[: -len("__*")]
    return bool(server) and "__" not in server and server != "*"


def _uses_colon_specifier(entry: str) -> bool:
    """True for the undocumented `Tool(cmd:*)` form.

    Anchored to the head of the specifier, because a colon further along is
    ordinary argument text: `Bash(docker run -p 8080:80)` is a port mapping.
    """
    _, sep, rest = entry.partition("(")
    if not sep:
        return False
    tokens = rest.rsplit(")", 1)[0].strip().split(maxsplit=1)
    return bool(tokens) and ":" in tokens[0]


def check_file(path: PurePath, text: str) -> tuple[list[str], list[str]]:
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

    # Truthiness, not membership: a bare `tools:` stores an empty list here and
    # reads as null at runtime, which inherits everything just like no key.
    if not fields.get("tools"):
        warnings.append(
            f"{path}: 'tools:' is missing or empty — this agent inherits every tool"
        )

    for key in TOOL_KEYS:
        if key not in fields:
            continue
        entries, split_error, split_warnings = split_entries(fields[key])
        if split_error:
            errors.append(f"{path}: {key}: {split_error}")
            continue
        for message in split_warnings:
            warnings.append(f"{path}: {key}: {message}")
        for entry in entries:
            # An entry that is nothing but punctuation has no base name to
            # report; falling back to the entry keeps the offending text in the
            # warning instead of printing ''.
            base = _base_name(entry) or entry
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
            if base in COLON_SPECIFIER_TOOLS and _uses_colon_specifier(entry):
                warnings.append(
                    f"{path}: {key}: {entry!r} uses the undocumented colon specifier form"
                )

    return errors, warnings


def main(argv: list[str] | None = None, plugins_dir: Path = PLUGINS_DIR) -> int:
    args = sys.argv[1:] if argv is None else list(argv)
    if args:
        # Silently ignoring arguments made `... check_agent_frontmatter.py
        # plugins/qa` scan the whole tree and report success.
        print(
            f"error: this check takes no arguments, got {' '.join(args)!r}",
            file=sys.stderr,
        )
        print(f"usage: python3 {Path(__file__).name}", file=sys.stderr)
        return 2

    root = plugins_dir.parent
    paths = sorted(plugins_dir.glob(AGENT_GLOB))
    if not paths:
        print(
            f"error: no agent files discovered under {plugins_dir}/{AGENT_GLOB}",
            file=sys.stderr,
        )
        return 1

    errors: list[str] = []
    warnings: list[str] = []
    for path in paths:
        relative = path.relative_to(root)
        try:
            # utf-8-sig so a byte-order mark does not masquerade as a missing
            # opening '---'; the except turns an undecodable file into a
            # diagnostic instead of a traceback.
            text = path.read_text(encoding="utf-8-sig")
        except (OSError, UnicodeDecodeError) as exc:
            errors.append(f"{relative}: cannot be read as UTF-8 text: {exc}")
            continue
        file_errors, file_warnings = check_file(relative, text)
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
