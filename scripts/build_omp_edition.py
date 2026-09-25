#!/usr/bin/env python3
"""Build the OMP edition of this marketplace from the Claude Code sources.

`plugins/<name>/` stays the single source of truth. For every plugin with an
overlay at `omp/overlay/<name>.json`, this script writes `plugins-omp/<name>/`:

- `scripts/` is copied verbatim;
- `skills/` is copied verbatim except each `SKILL.md` frontmatter `name`,
  which becomes `<plugin>:<skill>` so same-named skills of different plugins
  stay distinct;
- `commands/*.md` keep `description` / `argument-hint`, drop `allowed-tools` /
  `model` (OMP commands read neither), and gain the harness preamble
  (`omp/preamble.md`) above the unchanged body;
- `agents/*.md` get OMP frontmatter — `<plugin>:<agent>` names, OMP tool
  names, a role-routed `model` — and the preamble above the unchanged body;
- `hooks/hooks.json` maps Bash PreToolUse command hooks to an OMP extension
  and its `package.json`; unsupported hooks fail the build;
- `.omp-plugin/plugin.json` mirrors the Claude manifest.

`omp/native/<name>/` holds OMP-only plugins. They are copied as-is (minus
`tests/` and caches) and listed with the version from their own
`.omp-plugin/plugin.json`.

It also writes `.omp-plugin/marketplace.json`, listing only plugins that have
an OMP edition, with versions of generated plugins taken from the Claude
catalog.

Every mapping is total: an unknown source entry, tool, frontmatter key, or an
agent without an overlay entry fails the build instead of disappearing silently.
The one prefix rule is `mcp__`: MCP grants in an agent's `tools:` are dropped,
because an OMP subagent receives the session's MCP tools whatever its `tools:` says.

Usage:
    python3 scripts/build_omp_edition.py          # (re)generate
    python3 scripts/build_omp_edition.py --check  # exit 1 if output is stale
"""

from __future__ import annotations

import argparse
import filecmp
import json
import os
import re
import shutil
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
OUTPUT_DIR_NAME = "plugins-omp"
OMP_CATALOG_REL = Path(".omp-plugin") / "marketplace.json"

VERBATIM_DIRS = ("scripts",)
KNOWN_ENTRIES = {".claude-plugin", "agents", "commands", "skills", "hooks", *VERBATIM_DIRS}
COMMAND_KEYS = ("description", "argument-hint")
# OMP commands read only `description` and `argument-hint`; these Claude Code
# keys are dropped on purpose.
COMMAND_DROPPED_KEYS = {"allowed-tools", "model"}
AGENT_SOURCE_KEYS = {"name", "description", "tools", "disallowedTools", "model", "skills"}
OVERLAY_KEYS = {"plugin", "agents", "fallback_model"}
AGENT_SPEC_KEYS = {"role", "add_tools", "thinking", "autoload", "description"}

NATIVE_MANIFEST_KEYS = {"name", "version", "description", "category"}
NATIVE_AGENT_KEYS = {
    "name", "description", "tools", "spawns", "model", "thinking-level", "output",
    "blocking", "autoloadSkills", "read-summarize", "prewalk", "advisor",
}
# Project model roles documented in README (including the plan-mode role);
# `tester` runs the QA testers. These are user-configurable OMP aliases, not
# a list of OMP built-in models.
MODEL_ROLES = {"code_review", "executor", "challenger", "analyst", "plan", "tester"}
# OMP_TOOLS mirrors OMP's tools/builtin-names.ts; scripts/check_omp_tools.py
# verifies the names against an installed OMP package in CI.
OMP_TOOLS = {
    "read", "bash", "edit", "ast_grep", "ast_edit", "ask", "debug", "eval",
    "github", "glob", "grep", "find", "lsp", "checkpoint", "rewind",
    "context_notes", "new_context", "security_scan", "task", "wait", "todo",
    "web_search", "write", "memory_edit", "retain", "recall", "reflect",
    "learn", "manage_skill",
}
# OMP parses these values via parseConfiguredThinkingLevel.
THINKING_LEVELS = {"inherit", "off", "min", "low", "medium", "high", "xhigh", "max", "auto"}

# Claude MCP grants (`mcp__<server>`, `mcp__<server>__*`,
# `mcp__<server>__<tool>`) are dropped: OMP task-spawned subagents receive
# every session MCP tool regardless of `tools:` (OMP src/sdk.ts, custom tools
# are always included), so a grant cannot be expressed there. The preamble
# tells the model.
MCP_GRANT_PREFIX = "mcp__"

# Claude Code tool name -> OMP tool name. None = no equivalent; dropped on
# purpose (the preamble tells the model what replaces it).
TOOL_MAP: dict[str, str | None] = {
    "Read": "read",
    "Grep": "grep",
    "Glob": "glob",
    "Bash": "bash",
    "Edit": "edit",
    "NotebookEdit": "edit",
    "Write": "write",
    "WebSearch": "web_search",
    "WebFetch": "read",
    "Task": "task",
    "TaskCreate": "todo",
    "TaskUpdate": "todo",
    "TaskList": "todo",
    "AskUserQuestion": "ask",
    "Skill": None,
}
# Add a tool only after checking its OMP input shape matches Claude's, and add
# its OMP name to HOOKABLE_TOOLS in omp/claude-hooks/claude-hooks.ts, which
# blocks these tools when the hook config cannot be read.
HOOK_TOOL_MAP = {"Bash": "bash"}
SCOPED_GRANT = re.compile(r"^(?P<tool>[A-Za-z]+)\(.*\)$")
SKILL_NAME_LINE = re.compile(r"^name:.*$", re.MULTILINE)


class BuildError(Exception):
    pass


def split_frontmatter(text: str, origin: Path) -> tuple[list[tuple[str, str]], str]:
    """Return ordered (key, raw value) pairs and the body after the closing fence."""
    if not text.startswith("---\n"):
        raise BuildError(f"{origin}: missing frontmatter")
    end = text.find("\n---\n", 4)
    if end == -1:
        raise BuildError(f"{origin}: unterminated frontmatter")
    pairs: list[tuple[str, str]] = []
    for line in text[4:end].splitlines():
        if not line.strip():
            continue
        key, sep, value = line.partition(":")
        if not sep or line[0].isspace():
            raise BuildError(f"{origin}: unsupported frontmatter line {line!r}")
        pairs.append((key.strip(), value.strip()))
    return pairs, text[end + len("\n---\n") :]


def yaml_str(value: str) -> str:
    # A JSON string literal is a valid double-quoted YAML scalar.
    return json.dumps(value, ensure_ascii=False)


def scalar(raw: str) -> str:
    """Re-emit a raw source value as a string scalar.

    Claude Code reads `argument-hint: [pr-number]` as text; a YAML parser reads
    it as a list. Quote every value unless the source already quoted it.
    """
    if len(raw) >= 2 and raw[0] == raw[-1] and raw[0] in "\"'":
        return raw
    return yaml_str(raw)


def unquote(raw: str) -> str:
    """Inverse of `scalar` for the quoting styles frontmatter values use."""
    if raw.startswith('"'):
        return json.loads(raw)
    if len(raw) >= 2 and raw[0] == raw[-1] == "'":
        return raw[1:-1]
    return raw


def build_skill(src: Path, plugin: str) -> str:
    """Rename the skill to `<plugin>:<skill>`; every other byte is unchanged."""
    text = src.read_text()
    pairs, _ = split_frontmatter(text, src)
    skill_dir = src.parent.name
    if unquote(dict(pairs).get("name", "")) != skill_dir:
        raise BuildError(f"{src}: skill name must equal its directory {skill_dir!r}")
    end = text.find("\n---\n", 4)
    head = SKILL_NAME_LINE.sub(f"name: {yaml_str(f'{plugin}:{skill_dir}')}", text[:end], count=1)
    return head + text[end:]


def render(frontmatter: list[tuple[str, str]], preamble: str, body: str) -> str:
    lines = ["---", *(f"{key}: {value}" for key, value in frontmatter), "---", ""]
    return "\n".join(lines) + preamble + "\n" + body.lstrip("\n")


def map_tools(raw: str, origin: Path) -> list[str]:
    mapped: list[str] = []
    for token in (t.strip() for t in raw.split(",")):
        if not token:
            continue
        scoped = SCOPED_GRANT.match(token)
        name = scoped.group("tool") if scoped else token
        if name.startswith(MCP_GRANT_PREFIX):
            continue
        if name not in TOOL_MAP:
            raise BuildError(f"{origin}: no OMP mapping for tool {token!r}")
        target = TOOL_MAP[name]
        if target and target not in mapped:
            mapped.append(target)
    return mapped


def validate_omp_tool(name: object, origin: Path) -> None:
    if not isinstance(name, str) or name not in OMP_TOOLS:
        raise BuildError(f"{origin}: unknown OMP tool {name!r}")


def build_agent(
    src: Path, plugin: str, overlay: dict, preamble: str, skill_names: set[str], src_root: Path
) -> str:
    pairs, body = split_frontmatter(src.read_text(), src)
    fields = dict(pairs)
    unknown = set(fields) - AGENT_SOURCE_KEYS
    if unknown:
        raise BuildError(f"{src}: no OMP mapping for frontmatter keys {sorted(unknown)}")
    name = fields.get("name")
    if not name or not fields.get("description"):
        raise BuildError(f"{src}: agent needs name and description")
    spec = overlay["agents"].get(name)
    if spec is None:
        raise BuildError(f"{src}: agent {name!r} has no entry in omp/overlay/{plugin}.json")
    extra = set(spec) - AGENT_SPEC_KEYS
    if extra:
        raise BuildError(f"{src}: unknown keys {sorted(extra)} for agent {name!r} in omp/overlay/{plugin}.json")
    if "role" not in spec:
        raise BuildError(f"{src}: agent {name!r} has no role in omp/overlay/{plugin}.json")
    role = spec["role"]
    if not isinstance(role, str) or role not in MODEL_ROLES:
        raise BuildError(
            f"{src}: unknown role {role!r} in omp/overlay/{plugin}.json; "
            f"allowed project roles: {', '.join(sorted(MODEL_ROLES))}. "
            "To add a new role, document it in README.md and add it to MODEL_ROLES."
        )
    extras = spec.get("add_tools", [])
    if not isinstance(extras, list):
        raise BuildError(f"{src}: add_tools must be a list in omp/overlay/{plugin}.json")
    for extra in extras:
        validate_omp_tool(extra, src)
    if "thinking" in spec and (
        not isinstance(spec["thinking"], str) or spec["thinking"] not in THINKING_LEVELS
    ):
        raise BuildError(f"{src}: unknown thinking level {spec['thinking']!r} in omp/overlay/{plugin}.json")
    if "description" in spec and (
        not isinstance(spec["description"], str) or not spec["description"].strip()
    ):
        raise BuildError(f"{src}: description must be a non-empty string in omp/overlay/{plugin}.json")

    # `todo` is parent-owned in OMP: the task executor strips it from every
    # subagent, so granting it would only mislead a reader of the frontmatter.
    tools = [t for t in map_tools(fields.get("tools", ""), src) if t != "todo"]
    if "disallowedTools" in fields and "tools" not in fields:
        raise BuildError(f"{src}: disallowedTools requires tools (an explicit allowlist in OMP)")
    if "tools" in fields and not tools:
        raise BuildError(f"{src}: declared tools map to no usable OMP tools")
    for extra in extras:
        if extra not in tools:
            tools.append(extra)
    # OMP's `tools:` is an allowlist, so `disallowedTools` has nothing to say
    # there — but the denial must still hold after mapping and overlay extras.
    if any(
        token.strip().startswith(MCP_GRANT_PREFIX)
        for token in fields.get("disallowedTools", "").split(",")
    ):
        raise BuildError(
            f"{src}: MCP entries in disallowedTools cannot be enforced in OMP "
            "(subagents receive every session MCP tool)"
        )
    denied = set(map_tools(fields.get("disallowedTools", ""), src)) & set(tools)
    if denied:
        raise BuildError(f"{src}: granted tools {sorted(denied)} are in disallowedTools")
    # Claude Code's `inherit` (and an absent `model:`) means "the parent's
    # model"; OMP falls back to the parent when no listed entry resolves, so
    # the role alias alone expresses it.
    selectors = [f"@{spec['role']}"]
    fallback = fields.get("model") or overlay.get("fallback_model")
    if fallback and fallback != "inherit":
        selectors.append(fallback)

    out: list[tuple[str, str]] = [
        ("name", yaml_str(f"{plugin}:{name}")),
        (
            "description",
            yaml_str(spec["description"]) if "description" in spec else scalar(fields["description"]),
        ),
    ]
    if tools:
        out.append(("tools", ", ".join(tools)))
    out.append(("model", yaml_str(", ".join(selectors))))
    if "thinking" in spec:
        out.append(("thinking-level", spec["thinking"]))
    if "autoload" in spec:
        autoload = list(spec["autoload"])
    else:
        autoload = [s.strip() for s in fields.get("skills", "").split(",") if s.strip()]
    missing = [s for s in autoload if s not in skill_names]
    if missing:
        raise BuildError(f"{src}: autoload skills {missing} do not exist in plugins/{plugin}/skills/")
    if autoload:
        # OMP matches autoload entries by skill name, which build_skill prefixed.
        out.append(("autoloadSkills", json.dumps([f"{plugin}:{s}" for s in autoload])))
    relpath = src.relative_to(src_root).as_posix()
    return render(out, preamble.format(plugin=plugin, relpath=relpath), body)


def build_command(src: Path, plugin: str, preamble: str, src_root: Path) -> str:
    pairs, body = split_frontmatter(src.read_text(), src)
    unknown = {k for k, _ in pairs} - set(COMMAND_KEYS) - COMMAND_DROPPED_KEYS
    if unknown:
        raise BuildError(f"{src}: no OMP mapping for frontmatter keys {sorted(unknown)}")
    kept = [(k, scalar(v)) for k, v in pairs if k in COMMAND_KEYS]
    relpath = src.relative_to(src_root).as_posix()
    return render(kept, preamble.format(plugin=plugin, relpath=relpath), body)


NATIVE_SKIPPED_DIRS = frozenset({"node_modules"})


def reject_source_symlinks(root: Path, skip_dirs: frozenset[str] = frozenset()) -> None:
    """Reject links before any source file is opened, including linked directories.

    Directories named in skip_dirs are neither inspected nor descended.
    """
    if root.is_symlink():
        raise BuildError(f"{root}: symlinks are not allowed in plugin sources")
    for current, dirs, files in os.walk(root):
        for name in (*dirs, *files):
            if name not in skip_dirs:
                path = Path(current) / name
                if path.is_symlink():
                    raise BuildError(f"{path}: symlinks are not allowed in plugin sources")
        dirs[:] = [name for name in dirs if name not in skip_dirs]


def guarded(path: Path, out_root: Path) -> Path:
    # The one invariant this script guarantees: nothing outside the output root.
    resolved = path.resolve()
    if out_root.resolve() not in resolved.parents:
        raise BuildError(f"refusing to write outside {out_root}: {resolved}")
    resolved.parent.mkdir(parents=True, exist_ok=True)
    return resolved


def write(path: Path, content: str, out_root: Path) -> None:
    guarded(path, out_root).write_text(content)


def copy(src: Path, path: Path, out_root: Path) -> None:
    if src.is_symlink():
        raise BuildError(f"{src}: symlinks are not allowed in plugin sources")
    # copy2 keeps the executable bit the scripts rely on.
    shutil.copy2(src, guarded(path, out_root), follow_symlinks=False)


def native_skipped(rel: Path) -> bool:
    return (
        rel.parts[0] == "tests"
        or "__pycache__" in rel.parts
        or not NATIVE_SKIPPED_DIRS.isdisjoint(rel.parts)
        or rel.name in {"bun.lock", "bun.lockb", "package-lock.json"}
        or rel.suffix == ".pyc"
        or rel.name == ".DS_Store"
    )


def build_native(src_root: Path, out_root: Path, taken: set[str]) -> dict:
    """Copy an OMP-only plugin and return its catalog entry."""
    reject_source_symlinks(src_root, NATIVE_SKIPPED_DIRS)
    manifest_path = src_root / ".omp-plugin" / "plugin.json"
    if not manifest_path.is_file():
        raise BuildError(f"{src_root}: missing .omp-plugin/plugin.json")
    manifest = json.loads(manifest_path.read_text())
    missing = NATIVE_MANIFEST_KEYS - set(manifest)
    if missing:
        raise BuildError(f"{manifest_path}: missing keys {sorted(missing)}")
    name = manifest["name"]
    if name != src_root.name:
        raise BuildError(f"{manifest_path}: name {name!r} must equal its directory {src_root.name!r}")
    if name in taken:
        raise BuildError(f"native plugin {name!r} collides with a generated plugin")
    package_path = src_root / "package.json"
    if package_path.is_file():
        package = json.loads(package_path.read_text())
        if package.get("name") != name or package.get("version") != manifest["version"]:
            raise BuildError(f"{package_path}: name and version must equal {name!r} and {manifest['version']!r} from .omp-plugin/plugin.json")
        entries = (package.get("omp") or {}).get("extensions")
        if not isinstance(entries, list) or not entries:
            raise BuildError(f"{package_path}: omp.extensions must list the extension entry files")
        for entry in entries:
            if not isinstance(entry, str) or not (src_root / entry).is_file():
                raise BuildError(f"{package_path}: omp.extensions entry {entry!r} is not a file in the plugin")

    for src in sorted((src_root / "agents").glob("*.md")):
        fields = dict(split_frontmatter(src.read_text(), src)[0])
        extra = set(fields) - NATIVE_AGENT_KEYS
        if extra:
            raise BuildError(f"{src}: unknown OMP agent frontmatter keys {sorted(extra)}")
        if not unquote(fields.get("name", "")).startswith(f"{name}:"):
            raise BuildError(f"{src}: agent name must start with {name + ':'!r}")
        if "tools" in fields:
            raw_tools = fields["tools"]
            if raw_tools.startswith("[") and raw_tools.endswith("]"):
                tokens = raw_tools[1:-1].split(",")
            else:
                tokens = unquote(raw_tools).split(",")
            for tool in tokens:
                if tool.strip():
                    validate_omp_tool(unquote(tool.strip()), src)
    for src in sorted((src_root / "skills").glob("*/SKILL.md")):
        expected = f"{name}:{src.parent.name}"
        if unquote(dict(split_frontmatter(src.read_text(), src)[0]).get("name", "")) != expected:
            raise BuildError(f"{src}: skill name must be {expected!r}")

    for src in sorted(src_root.rglob("*")):
        rel = src.relative_to(src_root)
        if src.is_file() and not native_skipped(rel):
            copy(src, out_root / name / rel, out_root)
    return {
        "name": name,
        "source": f"./{name}",
        "description": manifest["description"],
        "version": manifest["version"],
        "category": manifest["category"],
    }


def map_hooks(path: Path, src_root: Path) -> dict:
    """Map supported Claude command hooks to the OMP extension config."""
    try:
        data = json.loads(path.read_text())
    except json.JSONDecodeError as error:
        raise BuildError(f"{path}: malformed hooks.json") from error
    if not isinstance(data, dict) or "hooks" not in data:
        raise BuildError(f"{path}: malformed hooks.json")
    unknown = set(data) - {"hooks", "$schema", "description"}
    if unknown:
        raise BuildError(f"{path}: unknown hooks.json keys {sorted(unknown)}")

    events = data["hooks"]
    if not isinstance(events, dict) or not events:
        raise BuildError(f"{path}: malformed hooks.json")
    for groups in events.values():
        if not isinstance(groups, list) or not groups:
            raise BuildError(f"{path}: malformed hooks.json")
        for group in groups:
            if (
                not isinstance(group, dict)
                or set(group) - {"matcher", "hooks"}
                or ("matcher" in group and not isinstance(group["matcher"], str))
                or not isinstance(group.get("hooks"), list)
                or not group["hooks"]
            ):
                raise BuildError(f"{path}: malformed hooks.json")
            for hook in group["hooks"]:
                if (
                    not isinstance(hook, dict)
                    or not isinstance(hook.get("type"), str)
                    or ("command" in hook and not isinstance(hook["command"], str))
                ):
                    raise BuildError(f"{path}: malformed hooks.json")

    mapped = []
    scripts_root = (src_root / "scripts").resolve()
    for event, groups in events.items():
        if event != "PreToolUse":
            raise BuildError(f"{path}: no OMP mapping for hook event {event!r}")
        for group in groups:
            matcher = group.get("matcher")
            if matcher not in HOOK_TOOL_MAP:
                raise BuildError(f"{path}: no OMP mapping for hook matcher {matcher!r}")
            for hook in group["hooks"]:
                if hook["type"] != "command":
                    raise BuildError(f"{path}: no OMP mapping for hook type {hook['type']!r}")
                if set(hook) != {"type", "command"}:
                    raise BuildError(f"{path}: unknown hook keys {sorted(hook)}")

                command = hook["command"]
                match = re.fullmatch(r"\$\{CLAUDE_PLUGIN_ROOT\}/(scripts/\S+)", command)
                if match is None:
                    raise BuildError(f"{path}: hook command {command}")
                rel = Path(match.group(1))
                script = (src_root / rel).resolve()
                if ".." in rel.parts or not script.is_relative_to(scripts_root) or not script.is_file():
                    raise BuildError(f"{path}: hook command {command}")
                with script.open("rb") as source:
                    first_line = source.readline().removesuffix(b"\n")
                if first_line not in (b"#!/bin/bash", b"#!/usr/bin/env bash"):
                    raise BuildError(
                        f"{path}: hook command {command}: not a shell script bash can run as is; "
                        "the first line must be exactly #!/bin/bash or #!/usr/bin/env bash"
                    )
                mapped.append({
                    "tool": HOOK_TOOL_MAP[matcher], "claudeTool": matcher, "command": rel.as_posix(),
                })

    return {"PreToolUse": mapped}


def build_generated(
    src_root: Path, overlay_path: Path, entry: dict, out_root: Path, preamble: str, adapter: Path
) -> dict:
    """Build one overlaid Claude plugin and return its OMP catalog entry."""
    reject_source_symlinks(src_root)
    reject_source_symlinks(overlay_path)
    overlay = json.loads(overlay_path.read_text())
    extra = set(overlay) - OVERLAY_KEYS
    if extra:
        raise BuildError(f"{overlay_path}: unknown overlay keys {sorted(extra)}")
    plugin = overlay["plugin"]
    if plugin != overlay_path.stem:
        raise BuildError(f"{overlay_path}: 'plugin' must equal the file name")
    dst_root = out_root / plugin
    unknown = {path.name for path in src_root.iterdir()} - KNOWN_ENTRIES - {"tests"}
    if unknown:
        raise BuildError(f"{src_root}: no OMP mapping for {sorted(unknown)}")
    hooks_root = src_root / "hooks"
    hooks_path = hooks_root / "hooks.json"
    hooks_config = None
    if hooks_root.exists():
        if (
            not hooks_root.is_dir()
            or {path.name for path in hooks_root.iterdir()} != {"hooks.json"}
            or not hooks_path.is_file()
        ):
            raise BuildError(f"{hooks_root}: no OMP mapping for hooks other than hooks/hooks.json")
        if not adapter.is_file():
            raise BuildError(f"{adapter}: missing; {src_root.name} has hooks/hooks.json")
        hooks_config = map_hooks(hooks_path, src_root)

    manifest_path = src_root / ".claude-plugin" / "plugin.json"
    manifest = json.loads(manifest_path.read_text())
    if "hooks" in manifest:
        raise BuildError(f"{manifest_path}: inline hooks are not mapped")

    for name in VERBATIM_DIRS:
        if (src_root / name).is_dir():
            for src in sorted((src_root / name).rglob("*")):
                if src.is_file():
                    copy(src, dst_root / src.relative_to(src_root), out_root)

    skills_root = src_root / "skills"
    skill_names: set[str] = set()
    if skills_root.is_dir():
        for src in sorted(skills_root.rglob("*")):
            if not src.is_file():
                continue
            dst = dst_root / src.relative_to(src_root)
            if src.name == "SKILL.md" and src.parent.parent == skills_root:
                skill_names.add(src.parent.name)
                write(dst, build_skill(src, plugin), out_root)
            else:
                copy(src, dst, out_root)

    for src in sorted((src_root / "commands").glob("*.md")):
        write(
            dst_root / "commands" / src.name,
            build_command(src, plugin, preamble, src_root),
            out_root,
        )

    seen = set()
    for src in sorted((src_root / "agents").glob("*.md")):
        seen.add(dict(split_frontmatter(src.read_text(), src)[0]).get("name"))
        write(
            dst_root / "agents" / src.name,
            build_agent(src, plugin, overlay, preamble, skill_names, src_root),
            out_root,
        )
    stale = set(overlay["agents"]) - seen
    if stale:
        raise BuildError(f"{overlay_path}: overlay names agents that do not exist: {sorted(stale)}")

    if hooks_config is not None:
        extensions = dst_root / "extensions"
        write(
            extensions / "claude-hooks.json",
            json.dumps(hooks_config, indent=2) + "\n",
            out_root,
        )
        copy(adapter, extensions / "claude-hooks.ts", out_root)
        package = {
            "name": plugin,
            "version": entry["version"],
            "private": True,
            "type": "module",
            "omp": {"extensions": ["./extensions/claude-hooks.ts"]},
        }
        write(dst_root / "package.json", json.dumps(package, indent=2) + "\n", out_root)
    write(
        dst_root / ".omp-plugin" / "plugin.json",
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
        out_root,
    )
    return {
        "name": plugin,
        "source": f"./{plugin}",
        "description": entry["description"],
        "version": entry["version"],
        "category": entry["category"],
    }


def build(dest_repo: Path, source_repo: Path = REPO) -> None:
    for root in (source_repo / "omp", source_repo / ".claude-plugin"):
        if root.is_symlink():
            raise BuildError(f"{root}: symlinks are not allowed in plugin sources")
    reject_source_symlinks(source_repo / "plugins")
    reject_source_symlinks(source_repo / "omp" / "overlay")
    reject_source_symlinks(source_repo / "omp" / "native", NATIVE_SKIPPED_DIRS)
    reject_source_symlinks(source_repo / "omp" / "claude-hooks", NATIVE_SKIPPED_DIRS)
    for path in (source_repo / "omp" / "preamble.md", source_repo / ".claude-plugin" / "marketplace.json"):
        if path.is_symlink():
            raise BuildError(f"{path}: symlinks are not allowed in plugin sources")
    out_root = dest_repo / OUTPUT_DIR_NAME
    if out_root.is_symlink():
        raise BuildError(f"{out_root}: symlinked output directory is not allowed")
    preamble = (source_repo / "omp" / "preamble.md").read_text()
    catalog = json.loads((source_repo / ".claude-plugin" / "marketplace.json").read_text())
    entries = {p["name"]: p for p in catalog["plugins"]}
    omp_plugins = []

    for overlay_path in sorted((source_repo / "omp" / "overlay").glob("*.json")):
        plugin = overlay_path.stem
        if plugin not in entries:
            raise BuildError(f"{overlay_path}: {plugin!r} is not in the Claude catalog")
        omp_plugins.append(
            build_generated(
                source_repo / "plugins" / plugin, overlay_path, entries[plugin], out_root,
                preamble, source_repo / "omp" / "claude-hooks" / "claude-hooks.ts",
            )
        )

    native_dir = source_repo / "omp" / "native"
    if native_dir.is_dir():
        taken = set(entries) | {entry["name"] for entry in omp_plugins}
        for native in sorted(p for p in native_dir.iterdir() if p.is_dir()):
            omp_plugins.append(build_native(native, out_root, taken))
    omp_plugins.sort(key=lambda entry: entry["name"])

    omp_catalog = {
        "name": catalog["name"],
        "owner": catalog["owner"],
        "metadata": {
            "description": "OMP edition, generated from .claude-plugin/marketplace.json by scripts/build_omp_edition.py",
            "pluginRoot": f"./{OUTPUT_DIR_NAME}",
        },
        "plugins": omp_plugins,
    }
    # The catalog is the only output outside plugins-omp/, at a fixed path.
    catalog_path = dest_repo / OMP_CATALOG_REL
    catalog_path.parent.mkdir(parents=True, exist_ok=True)
    catalog_path.write_text(json.dumps(omp_catalog, indent=2, ensure_ascii=False) + "\n")


def diff_trees(expected: Path, actual: Path) -> list[str]:
    problems: list[str] = []

    def walk(cmp: filecmp.dircmp, rel: Path) -> None:
        problems.extend(f"missing: {rel / n}" for n in cmp.left_only)
        problems.extend(f"unexpected: {rel / n}" for n in cmp.right_only)
        _, mismatch, errors = filecmp.cmpfiles(cmp.left, cmp.right, cmp.common_files, shallow=False)
        problems.extend(f"stale: {rel / n}" for n in mismatch + errors)
        for name, sub in cmp.subdirs.items():
            walk(sub, rel / name)

    if not actual.exists():
        return [f"missing: {actual.name}/"]
    walk(filecmp.dircmp(expected, actual), Path(actual.name))
    return problems


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="fail if the committed output is stale")
    args = parser.parse_args()
    try:
        out_root = REPO / OUTPUT_DIR_NAME
        if out_root.is_symlink():
            raise BuildError(f"{out_root}: symlinked output directory is not allowed")
        if not args.check:
            # Build on the same filesystem so a failed build leaves both
            # published outputs untouched and the finished tree can be renamed.
            with tempfile.TemporaryDirectory(prefix=".omp-build-", dir=REPO) as tmp:
                staged = Path(tmp)
                build(staged)
                catalog_path = REPO / OMP_CATALOG_REL
                catalog_path.parent.mkdir(parents=True, exist_ok=True)
                previous = staged / "previous-plugins-omp"
                if out_root.exists():
                    out_root.rename(previous)
                try:
                    (staged / OUTPUT_DIR_NAME).rename(out_root)
                    (staged / OMP_CATALOG_REL).replace(catalog_path)
                except OSError:
                    if out_root.exists():
                        shutil.rmtree(out_root)
                    if previous.exists():
                        previous.rename(out_root)
                    raise
            print(f"wrote {OUTPUT_DIR_NAME}/ and {OMP_CATALOG_REL}")
            return 0
        with tempfile.TemporaryDirectory() as tmp:
            build(Path(tmp))
            problems = diff_trees(Path(tmp) / OUTPUT_DIR_NAME, REPO / OUTPUT_DIR_NAME)
            committed = REPO / OMP_CATALOG_REL
            if not committed.exists():
                problems.append(f"missing: {OMP_CATALOG_REL}")
            elif not filecmp.cmp(Path(tmp) / OMP_CATALOG_REL, committed, shallow=False):
                problems.append(f"stale: {OMP_CATALOG_REL}")
        for problem in problems:
            print(problem, file=sys.stderr)
        if problems:
            print("OMP edition is stale: run python3 scripts/build_omp_edition.py", file=sys.stderr)
            return 1
        print("OMP edition is up to date")
        return 0
    except BuildError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
