#!/usr/bin/env python3
"""Contract tests for build_omp_edition.

Run: python3 scripts/test_build_omp_edition.py
"""

from __future__ import annotations

import json
import os
import re
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))

from build_omp_edition import HOOK_TOOL_MAP, BuildError, build, build_native, guarded, main


AGENT = "---\nname: worker\ndescription: Does work\ntools: Read, Bash\nskills: review\n---\n\nAgent body.\n"
SKILL = "---\nname: review\ndescription: Reviews work\n---\n\nSkill body.\n"
MANIFEST = {"name": "sample", "version": "1.2.3", "description": "Sample plugin", "category": "development"}
ENTRY = {"name": "sample", "version": "1.2.3", "description": "Catalog entry", "category": "development"}


def put(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


def put_json(path: Path, value: object) -> None:
    put(path, json.dumps(value))


def fixture(root: Path) -> None:
    put(root / "omp/preamble.md", "Source: {plugin}/{relpath}\n")
    put_json(root / ".claude-plugin/marketplace.json", {
        "name": "test", "owner": {"name": "tester"}, "plugins": [ENTRY],
    })
    put_json(root / "omp/overlay/sample.json", {
        "plugin": "sample", "agents": {"worker": {"role": "analyst"}},
    })
    plugin = root / "plugins/sample"
    put_json(plugin / ".claude-plugin/plugin.json", MANIFEST)
    put(plugin / "agents/worker.md", AGENT)
    put(plugin / "skills/review/SKILL.md", SKILL)
    put(plugin / "commands/check.md", "---\ndescription: Check\nargument-hint: [target]\n---\n\nCommand body.\n")
    put(plugin / "scripts/utility.py", "print('ok')\n")


HOOK_COMMAND = "${CLAUDE_PLUGIN_ROOT}/scripts/guard.sh"
HOOK_GROUP = {"matcher": "Bash", "hooks": [{"type": "command", "command": HOOK_COMMAND}]}


def hooks_fixture(root: Path) -> None:
    put_json(root / "plugins/sample/hooks/hooks.json", {"hooks": {"PreToolUse": [HOOK_GROUP]}})
    put(root / "plugins/sample/scripts/guard.sh", "#!/bin/bash\nexit 0\n")
    put(root / "omp/claude-hooks/claude-hooks.ts", "// adapter\n")


def native_fixture(root: Path) -> Path:
    native = root / "native"
    put_json(native / ".omp-plugin/plugin.json", {
        "name": "native", "version": "0.1.0", "description": "Native", "category": "development",
    })
    put(native / "agents/worker.md", "---\nname: native:worker\ndescription: Native worker\n---\n\nBody.\n")
    put(native / "skills/review/SKILL.md", "---\nname: native:review\ndescription: Native review\n---\n\nBody.\n")
    put(native / "tests/ignored.txt", "not generated\n")
    return native


class TestGenerated(unittest.TestCase):
    def test_builds_from_explicit_source_and_preserves_rendered_content(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source, output = root / "source", root / "output"
            fixture(source)
            build(output, source)
            catalog = json.loads((output / ".omp-plugin/marketplace.json").read_text())
            self.assertEqual(catalog["plugins"], [{**ENTRY, "source": "./sample"}])
            plugin = output / "plugins-omp/sample"
            agent = (plugin / "agents/worker.md").read_text()
            self.assertIn('name: "sample:worker"', agent)
            self.assertIn("tools: read, bash", agent)
            self.assertIn('autoloadSkills: ["sample:review"]', agent)
            self.assertIn("Source: sample/agents/worker.md", agent)
            self.assertIn("Agent body.", agent)
            self.assertIn('name: "sample:review"', (plugin / "skills/review/SKILL.md").read_text())
            command = (plugin / "commands/check.md").read_text()
            self.assertIn('argument-hint: "[target]"', command)
            self.assertIn("Source: sample/commands/check.md", command)
            self.assertEqual((plugin / "scripts/utility.py").read_text(), "print('ok')\n")
            self.assertEqual(json.loads((plugin / ".omp-plugin/plugin.json").read_text()), MANIFEST)

    def test_overlay_description_replaces_claude_capability_in_generated_agent(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "source"
            fixture(source)
            agent_path = source / "plugins/sample/agents/worker.md"
            put(agent_path, AGENT.replace("Does work", "Runs tests using Playwright MCP"))
            put_json(source / "omp/overlay/sample.json", {
                "plugin": "sample",
                "agents": {
                    "worker": {"role": "tester", "description": "Runs tests with OMP's built-in browser"},
                },
            })

            build(root / "output", source)
            agent = (root / "output/plugins-omp/sample/agents/worker.md").read_text()
            frontmatter = agent.split("---", 2)[1]
            self.assertIn('description: "Runs tests with OMP\'s built-in browser"', frontmatter)
            self.assertNotIn("Playwright MCP", frontmatter)
            self.assertIn("Playwright MCP", agent_path.read_text())

    def test_hookable_tools_match_generated_hook_targets(self) -> None:
        source = (Path(__file__).resolve().parent.parent / "omp/claude-hooks/claude-hooks.ts").read_text()
        match = re.search(r"\bconst HOOKABLE_TOOLS\s*=\s*(\[[^\]]*\])\s*;", source, re.S)
        if match is None:
            self.fail("HOOKABLE_TOOLS declaration not found")
        self.assertEqual(json.loads(match.group(1)), sorted(set(HOOK_TOOL_MAP.values())))

    def test_hooks_become_the_claude_hooks_extension(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "source"
            fixture(source)
            hooks_fixture(source)

            build(root / "output", source)
            plugin = root / "output/plugins-omp/sample"
            self.assertEqual(
                (plugin / "extensions/claude-hooks.ts").read_text(),
                (source / "omp/claude-hooks/claude-hooks.ts").read_text(),
            )
            self.assertEqual(json.loads((plugin / "extensions/claude-hooks.json").read_text()), {
                "PreToolUse": [{
                    "tool": "bash", "claudeTool": "Bash", "command": "scripts/guard.sh",
                }],
            })
            self.assertEqual(json.loads((plugin / "package.json").read_text()), {
                "name": "sample", "version": "1.2.3", "private": True, "type": "module",
                "omp": {"extensions": ["./extensions/claude-hooks.ts"]},
            })
            self.assertFalse((plugin / "hooks").exists())

            put(source / "plugins/sample/scripts/second.sh", "#!/usr/bin/env bash\nexit 0\n")
            put_json(source / "plugins/sample/hooks/hooks.json", {
                "$schema": "https://example.test/hooks.schema.json",
                "description": "Sample hooks",
                "hooks": {"PreToolUse": [
                    HOOK_GROUP,
                    {"matcher": "Bash", "hooks": [{
                        "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/scripts/second.sh",
                    }]},
                ]},
            })
            build(root / "second-output", source)
            config = json.loads(
                (root / "second-output/plugins-omp/sample/extensions/claude-hooks.json").read_text()
            )
            self.assertEqual(config, {"PreToolUse": [
                {"tool": "bash", "claudeTool": "Bash", "command": "scripts/guard.sh"},
                {"tool": "bash", "claudeTool": "Bash", "command": "scripts/second.sh"},
            ]})

    def test_plugin_without_hooks_gets_no_extension(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "source"
            fixture(source)
            self.assertFalse((source / "omp/claude-hooks").exists())

            build(root / "output", source)
            plugin = root / "output/plugins-omp/sample"
            self.assertFalse((plugin / "package.json").exists())
            self.assertFalse((plugin / "extensions").exists())

    def test_unsupported_hooks_fail_closed(self) -> None:
        def group(matcher: object = "Bash", hook: object = None) -> dict:
            return {"matcher": matcher, "hooks": [hook if hook is not None else {
                "type": "command", "command": HOOK_COMMAND,
            }]}

        cases = {
            "missing hooks key": ({}, "malformed hooks.json"),
            "top level list": ([], "malformed hooks.json"),
            "unknown top-level key": ({"hooks": {"PreToolUse": [group()]}, "surprise": True}, "unknown hooks.json keys"),
            "non-object hooks": ({"hooks": []}, "malformed hooks.json"),
            "empty hooks": ({"hooks": {}}, "malformed hooks.json"),
            "empty event": ({"hooks": {"PreToolUse": []}}, "malformed hooks.json"),
            "group extra key": ({"hooks": {"PreToolUse": [{**group(), "surprise": True}]}}, "malformed hooks.json"),
            "empty group hooks": ({"hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": []}]}}, "malformed hooks.json"),
            "numeric matcher": ({"hooks": {"PreToolUse": [group(42)]}}, "malformed hooks.json"),
            "hook without type": ({"hooks": {"PreToolUse": [group(hook={
                "command": HOOK_COMMAND,
            })]}}, "malformed hooks.json"),
            "numeric command": ({"hooks": {"PreToolUse": [group(hook={
                "type": "command", "command": 3,
            })]}}, "malformed hooks.json"),
            "unsupported event": ({"hooks": {"SessionStart": [group()]}}, "no OMP mapping for hook event"),
            "missing matcher": ({"hooks": {"PreToolUse": [{"hooks": group()["hooks"]}]}}, "no OMP mapping for hook matcher"),
            "skill matcher": ({"hooks": {"PreToolUse": [group("Skill")]}}, "no OMP mapping for hook matcher"),
            "write matcher": ({"hooks": {"PreToolUse": [group("Write")]}}, "no OMP mapping for hook matcher"),
            "webfetch matcher": ({"hooks": {"PreToolUse": [group("WebFetch")]}}, "no OMP mapping for hook matcher"),
            "regex matcher": ({"hooks": {"PreToolUse": [group("Bash|Edit")]}}, "no OMP mapping for hook matcher"),
            "prompt hook": ({"hooks": {"PreToolUse": [group(hook={
                "type": "prompt", "prompt": "Is this safe?",
            })]}}, "hook type"),
            "timeout hook": ({"hooks": {"PreToolUse": [group(hook={
                "type": "command", "command": HOOK_COMMAND, "timeout": 3,
            })]}}, "unknown hook keys"),
            "missing command": ({"hooks": {"PreToolUse": [group(hook={
                "type": "command",
            })]}}, "unknown hook keys"),
        }
        for label, (data, error) in cases.items():
            with self.subTest(label=label), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                source = root / "source"
                fixture(source)
                hooks_fixture(source)
                put_json(source / "plugins/sample/hooks/hooks.json", data)
                with self.assertRaisesRegex(BuildError, error):
                    build(root / "output", source)

        commands = (
            "scripts/guard.sh",
            f"{HOOK_COMMAND} --dry-run",
            "${CLAUDE_PLUGIN_ROOT}/hooks/hooks.json",
            "${CLAUDE_PLUGIN_ROOT}/scripts/../hooks/hooks.json",
            "${CLAUDE_PLUGIN_ROOT}/scripts/x/../guard.sh",
            "${CLAUDE_PLUGIN_ROOT}/scripts/missing.sh",
        )
        for command in commands:
            with self.subTest(command=command), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                source = root / "source"
                fixture(source)
                hooks_fixture(source)
                put_json(source / "plugins/sample/hooks/hooks.json", {
                    "hooks": {"PreToolUse": [group(hook={
                        "type": "command", "command": command,
                    })]},
                })
                with self.assertRaisesRegex(BuildError, "hook command"):
                    build(root / "output", source)

        for first_line in ("#!/usr/bin/env python3\n", "#!/bin/sh\n", "#!/bin/bash -e\n", "#!/bin/bash\r\n"):
            with self.subTest(first_line=first_line), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                source = root / "source"
                fixture(source)
                hooks_fixture(source)
                (source / "plugins/sample/scripts/guard.sh").write_bytes(
                    first_line.encode() + b"exit 0\n"
                )
                with self.assertRaisesRegex(BuildError, "not a shell script"):
                    build(root / "output", source)

        for invalid in ("extra file", "hooks is file", "hooks.json is directory"):
            with self.subTest(invalid=invalid), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                source = root / "source"
                fixture(source)
                hooks_fixture(source)
                hooks = source / "plugins/sample/hooks"
                if invalid == "extra file":
                    put(hooks / "extra.sh", "#!/bin/bash\n")
                elif invalid == "hooks is file":
                    (hooks / "hooks.json").unlink()
                    hooks.rmdir()
                    put(hooks, "invalid\n")
                else:
                    (hooks / "hooks.json").unlink()
                    (hooks / "hooks.json").mkdir()
                with self.assertRaisesRegex(BuildError, "no OMP mapping for"):
                    build(root / "output", source)

        with self.subTest(invalid="inline manifest hooks"), tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "source"
            fixture(source)
            hooks_fixture(source)
            put_json(source / "plugins/sample/.claude-plugin/plugin.json", {
                **MANIFEST, "hooks": {},
            })
            with self.assertRaisesRegex(BuildError, "inline hooks"):
                build(root / "output", source)

        with self.subTest(invalid="missing adapter"), tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "source"
            fixture(source)
            hooks_fixture(source)
            (source / "omp/claude-hooks/claude-hooks.ts").unlink()
            with self.assertRaisesRegex(BuildError, "missing"):
                build(root / "output", source)
            self.assertFalse((root / "output/plugins-omp/sample").exists())

    def test_claude_hooks_adapter_rejects_source_symlinks(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "source"
            fixture(source)
            adapter_dir = source / "omp/claude-hooks"
            put(adapter_dir / "claude-hooks.ts", "// adapter\n")
            external = root / "helper.ts"
            external.write_text("// external\n")
            (adapter_dir / "helper.ts").symlink_to(external)
            with self.assertRaisesRegex(BuildError, "symlinks are not allowed"):
                build(root / "output", source)

    def test_unknown_source_entries_and_overlay_entries_fail_closed(self):
        cases = {
            "unmapped source entry": ("plugins/sample/surprise.txt", "x", "no OMP mapping for"),
            "unknown overlay key": ("omp/overlay/sample.json", {"plugin": "sample", "agents": {"worker": {"role": "analyst"}}, "surprise": True}, "unknown overlay keys"),
            "overlay plugin mismatch": ("omp/overlay/sample.json", {"plugin": "other", "agents": {}}, "must equal the file name"),
            "missing catalog registration": (".claude-plugin/marketplace.json", {"name": "test", "owner": {}, "plugins": []}, "not in the Claude catalog"),
            "stale overlay agent": ("omp/overlay/sample.json", {"plugin": "sample", "agents": {"worker": {"role": "analyst"}, "gone": {"role": "analyst"}}}, "agents that do not exist"),
        }
        for label, (path, value, error) in cases.items():
            with self.subTest(label=label), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                source = root / "source"
                fixture(source)
                if isinstance(value, str):
                    put(source / path, value)
                else:
                    put_json(source / path, value)
                with self.assertRaisesRegex(BuildError, error):
                    build(root / "output", source)

    def test_unmapped_agent_tools_frontmatter_and_overlay_specs_fail_closed(self):
        agent_cases = {
            "unknown tool": (AGENT.replace("Bash", "UnmappedTool"), "no OMP mapping for tool"),
            "unknown frontmatter key": (AGENT.replace("tools:", "surprise: yes\ntools:"), "no OMP mapping for frontmatter keys"),
            "agent missing name": (AGENT.replace("name: worker\n", ""), "agent needs name and description"),
            "agent missing description": (AGENT.replace("description: Does work\n", ""), "agent needs name and description"),
            "denied tool": (AGENT.replace("skills: review", "disallowedTools: Bash\nskills: review"), "are in disallowedTools"),
            "unknown denied tool": (AGENT.replace("skills: review", "disallowedTools: Mystery\nskills: review"), "no OMP mapping for tool"),
            "MCP denial": (
                AGENT.replace(
                    "skills: review",
                    "disallowedTools: mcp__postgres, mcp__postgres__query\nskills: review",
                ),
                "MCP entries in disallowedTools cannot be enforced in OMP",
            ),
            "unknown autoload skill": (AGENT.replace("skills: review", "skills: gone"), "autoload skills"),
            "missing frontmatter": ("name: worker\n", "missing frontmatter"),
            "unterminated frontmatter": ("---\nname: worker\n", "unterminated frontmatter"),
            "unsupported frontmatter line": (AGENT.replace("tools:", "  surprise: yes\ntools:"), "unsupported frontmatter line"),
        }
        for label, (content, error) in agent_cases.items():
            with self.subTest(label=label), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                source = root / "source"
                fixture(source)
                put(source / "plugins/sample/agents/worker.md", content)
                with self.assertRaisesRegex(BuildError, error):
                    build(root / "output", source)

        overlay_cases = {
            "agent without overlay entry": ({}, "has no entry"),
            "unknown agent spec key": ({"worker": {"role": "analyst", "surprise": True}}, "unknown keys"),
            "agent without role": ({"worker": {}}, "has no role"),
            "unknown overlay autoload": ({"worker": {"role": "analyst", "autoload": ["gone"]}}, "autoload skills"),
        }
        for label, (agents, error) in overlay_cases.items():
            with self.subTest(label=label), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                source = root / "source"
                fixture(source)
                put_json(source / "omp/overlay/sample.json", {"plugin": "sample", "agents": agents})
                with self.assertRaisesRegex(BuildError, error):
                    build(root / "output", source)

    def test_drops_mcp_grants_from_agent_tools(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "source"
            fixture(source)
            agent_path = source / "plugins/sample/agents/worker.md"
            put(
                agent_path,
                AGENT.replace(
                    "tools: Read, Bash",
                    "tools: Read, mcp__postgres, mcp__postgres__*, "
                    "mcp__plugin_playwright_playwright__browser_navigate, Bash",
                ),
            )

            build(root / "output", source)
            agent = (root / "output/plugins-omp/sample/agents/worker.md").read_text()
            self.assertIn("tools: read, bash\n", agent)
            self.assertNotIn("mcp__", agent)

            put(agent_path, AGENT.replace("tools: Read, Bash", "tools: mcp__postgres, mcp__postgres__*"))
            with self.assertRaisesRegex(BuildError, "declared tools map to no usable OMP tools"):
                build(root / "output", source)

    def test_rejects_invalid_overlay_role_tools_thinking_and_description(self):
        cases = {
            "misspelled role": ({"role": "exector"}, "unknown role.*allowed project roles:.*docs/oh-my-pi.md.*MODEL_ROLES"),
            "non-string role": ({"role": True}, "unknown role"),
            "misspelled tool": ({"role": "executor", "add_tools": ["ast-edit"]}, "unknown OMP tool"),
            "non-list tools": ({"role": "executor", "add_tools": "lsp"}, "add_tools must be a list"),
            "non-string tool": ({"role": "executor", "add_tools": [True]}, "unknown OMP tool"),
            "boolean thinking": ({"role": "executor", "thinking": True}, "unknown thinking level"),
            "misspelled thinking": ({"role": "executor", "thinking": "hgh"}, "unknown thinking level"),
            "non-string description": ({"role": "executor", "description": True}, "description must be a non-empty string"),
            "blank description": ({"role": "executor", "description": "  "}, "description must be a non-empty string"),
            "string advisor": ({"role": "executor", "advisor": "on"}, "advisor must be true"),
            "false advisor": ({"role": "executor", "advisor": False}, "advisor must be true"),
        }
        for label, (spec, error) in cases.items():
            with self.subTest(label=label), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                source = root / "source"
                fixture(source)
                put_json(source / "omp/overlay/sample.json", {
                    "plugin": "sample", "agents": {"worker": spec},
                })
                with self.assertRaisesRegex(BuildError, error):
                    build(root / "output", source)

    def test_accepts_documented_role_and_supported_tools_and_thinking(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "source"
            fixture(source)
            put_json(source / "omp/overlay/sample.json", {
                "plugin": "sample", "agents": {
                    "worker": {"role": "executor", "add_tools": ["ast_edit"], "thinking": "high"},
                },
            })
            build(root / "output", source)
            agent = (root / "output/plugins-omp/sample/agents/worker.md").read_text()
            self.assertIn('model: "@executor"', agent)
            self.assertIn("tools: read, bash, ast_edit", agent)
            self.assertIn("thinking-level: high", agent)

    def test_accepts_tester_role(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "source"
            fixture(source)
            put_json(source / "omp/overlay/sample.json", {
                "plugin": "sample", "agents": {"worker": {"role": "tester"}},
            })

            build(root / "output", source)
            agent = (root / "output/plugins-omp/sample/agents/worker.md").read_text()
            self.assertIn('model: "@tester"', agent)

    def test_overlay_advisor_pairs_only_that_agent_with_omp_advisor(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "source"
            fixture(source)
            put_json(source / "omp/overlay/sample.json", {
                "plugin": "sample", "agents": {"worker": {"role": "plan", "advisor": True}},
            })
            build(root / "output", source)
            advised = (root / "output/plugins-omp/sample/agents/worker.md").read_text()
            self.assertRegex(advised, r"(?m)^advisor: true$")

            put_json(source / "omp/overlay/sample.json", {
                "plugin": "sample", "agents": {"worker": {"role": "plan"}},
            })
            build(root / "output", source)
            unadvised = (root / "output/plugins-omp/sample/agents/worker.md").read_text()
            self.assertNotRegex(unadvised, r"(?m)^advisor:")

    def test_rejects_agent_restrictions_that_would_become_unrestricted(self):
        cases = {
            "skill only": ("tools: Skill\n", "no usable OMP tools"),
            "parent-owned todo only": ("tools: TaskCreate, TaskUpdate, TaskList\n", "no usable OMP tools"),
            "empty tools": ("tools:\n", "no usable OMP tools"),
            "denials without allowlist": ("disallowedTools: Edit, Write\n", "disallowedTools requires tools"),
        }
        for label, restriction in cases.items():
            with self.subTest(label=label), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                source = root / "source"
                fixture(source)
                content = AGENT.replace("tools: Read, Bash\n", restriction[0])
                put(source / "plugins/sample/agents/worker.md", content)
                with self.assertRaisesRegex(BuildError, restriction[1]):
                    build(root / "output", source)

    def test_malformed_skill_and_command_fail_instead_of_disappearing(self):
        cases = {
            "wrong skill name": ("plugins/sample/skills/review/SKILL.md", SKILL.replace("name: review", "name: elsewhere"), "skill name must equal"),
            "command with no frontmatter": ("plugins/sample/commands/check.md", "Command body.\n", "missing frontmatter"),
            "unknown command key": ("plugins/sample/commands/check.md", "---\ndescription: Check\nsurprise: yes\n---\n\nCommand body.\n", "no OMP mapping for frontmatter keys"),
        }
        for label, (path, content, error) in cases.items():
            with self.subTest(label=label), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                source = root / "source"
                fixture(source)
                put(source / path, content)
                with self.assertRaisesRegex(BuildError, error):
                    build(root / "output", source)

    def test_output_path_must_remain_within_generated_root(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            with self.assertRaisesRegex(BuildError, "refusing to write outside"):
                guarded(root / "elsewhere", root / "plugins-omp")

    def test_generated_sources_reject_symlinks_before_copying_or_reading(self):
        cases = (
            "plugins/sample/scripts/utility.py",
            "plugins/sample/skills/review/SKILL.md",
            "plugins/sample/commands/check.md",
            "plugins/sample/agents/worker.md",
        )
        for rel in cases:
            with self.subTest(source=rel), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                source = root / "source"
                fixture(source)
                original = source / rel
                external = root / "private.txt"
                external.write_bytes(original.read_bytes())
                original.unlink()
                original.symlink_to(external)
                with self.assertRaisesRegex(BuildError, "symlinks are not allowed"):
                    build(root / "output", source)
                self.assertFalse((root / "output/plugins-omp/sample" / rel.removeprefix("plugins/sample/")).exists())

    def test_generated_sources_reject_symlinked_directories(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "source"
            fixture(source)
            skills = source / "plugins/sample/skills"
            skills.rename(root / "outside-skills")
            skills.symlink_to(root / "outside-skills", target_is_directory=True)
            with self.assertRaisesRegex(BuildError, "symlinks are not allowed"):
                build(root / "output", source)

    def test_overlaid_plugin_sources_still_reject_a_symlinked_node_modules(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "source"
            fixture(source)
            put(root / "global/pkg/index.js", "installed\n")
            (source / "plugins/sample/scripts/node_modules").symlink_to(
                root / "global", target_is_directory=True
            )

            with self.assertRaisesRegex(BuildError, "symlinks are not allowed"):
                build(root / "output", source)

    def test_regeneration_rejects_symlinked_output_root(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            fixture(root)
            outside = root / "elsewhere"
            outside.mkdir()
            (root / "plugins-omp").symlink_to(outside, target_is_directory=True)
            with patch("build_omp_edition.REPO", root), patch.object(sys, "argv", ["build_omp_edition.py"]):
                self.assertEqual(main(), 1)
            self.assertEqual(list(outside.iterdir()), [])

    def test_failed_regeneration_keeps_existing_output_until_build_succeeds(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            fixture(root)
            output = root / "plugins-omp"
            put(output / "old-plugin/marker.txt", "old output\n")
            catalog = root / ".omp-plugin/marketplace.json"
            put(catalog, "old catalog\n")
            overlay = root / "omp/overlay/sample.json"
            put_json(overlay, {
                "plugin": "sample",
                "agents": {"worker": {"role": "analyst"}, "gone": {"role": "analyst"}},
            })
            with (
                patch("build_omp_edition.REPO", root),
                patch("build_omp_edition.build", side_effect=lambda dest: build(dest, root)),
                patch.object(sys, "argv", ["build_omp_edition.py"]),
            ):
                self.assertEqual(main(), 1)
                self.assertEqual((output / "old-plugin/marker.txt").read_text(), "old output\n")
                self.assertEqual(catalog.read_text(), "old catalog\n")
                put_json(overlay, {"plugin": "sample", "agents": {"worker": {"role": "analyst"}}})
                self.assertEqual(main(), 0)
            self.assertFalse((output / "old-plugin").exists())
            self.assertTrue((output / "sample/.omp-plugin/plugin.json").is_file())
            self.assertEqual(json.loads(catalog.read_text())["plugins"][0]["name"], "sample")


class TestNative(unittest.TestCase):
    def test_builds_native_plugin_without_tests(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            native = native_fixture(root)
            entry = build_native(native, root / "out", set())
            self.assertEqual(entry["name"], "native")
            self.assertTrue((root / "out/native/agents/worker.md").is_file())
            self.assertFalse((root / "out/native/tests/ignored.txt").exists())

    def test_native_copy_omits_dependency_install_artifacts(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            native = native_fixture(root)
            excluded = [
                "node_modules/@oh-my-pi/pi-coding-agent/package.json",
                "skills/review/node_modules/dependency/index.js",
                "bun.lock",
                "bun.lockb",
                "package-lock.json",
            ]
            for rel in excluded:
                put(native / rel, "installed dependency\n")
            put(native / "scripts/run.js", "console.log('run')\n")

            build_native(native, root / "out", set())

            for rel in excluded:
                with self.subTest(path=rel):
                    self.assertFalse((root / "out/native" / rel).exists())
            self.assertEqual((root / "out/native/scripts/run.js").read_text(), "console.log('run')\n")

    def test_native_build_skips_an_installed_node_modules(self) -> None:
        for mode in ("linked", "installed"):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                native = native_fixture(root)
                if mode == "linked":
                    put(root / "global/pkg/index.js", "installed\n")
                    (native / "node_modules").symlink_to(root / "global", target_is_directory=True)
                else:
                    put(native / "node_modules/@oh-my-pi/pi-coding-agent/dist/cli.js", "cli\n")
                    (native / "node_modules/.bin").mkdir()
                    (native / "node_modules/.bin/omp").symlink_to(
                        "../@oh-my-pi/pi-coding-agent/dist/cli.js"
                    )

                build_native(native, root / "out", set())
                self.assertTrue((root / "out/native/agents/worker.md").is_file())
                self.assertFalse(os.path.lexists(root / "out/native/node_modules"))

    def test_build_skips_node_modules_under_omp_native(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "source"
            fixture(source)
            native = native_fixture(source / "omp/native")
            put(root / "global/pkg/index.js", "installed\n")
            (native / "node_modules").symlink_to(root / "global", target_is_directory=True)

            build(root / "output", source)
            self.assertTrue((root / "output/plugins-omp/native/agents/worker.md").is_file())

    def test_native_sources_reject_symlinks_even_when_the_target_is_missing(self):
        for target_exists in (True, False):
            with self.subTest(target_exists=target_exists), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                native = native_fixture(root)
                secret = root / "private.txt"
                if target_exists:
                    secret.write_text("private data\n")
                (native / "leaked.txt").symlink_to(secret)
                with self.assertRaisesRegex(BuildError, "symlinks are not allowed"):
                    build_native(native, root / "out", set())
                self.assertFalse((root / "out/native/leaked.txt").exists())

    def test_native_manifest_and_catalog_guards(self):
        cases = {
            "missing manifest": (None, "missing .omp-plugin/plugin.json"),
            "missing manifest key": ({"name": "native"}, "missing keys"),
            "wrong manifest name": ({"name": "wrong", "version": "0.1.0", "description": "Native", "category": "development"}, "must equal its directory"),
        }
        for label, (manifest, error) in cases.items():
            with self.subTest(label=label), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                native = native_fixture(root)
                path = native / ".omp-plugin/plugin.json"
                if manifest is None:
                    path.unlink()
                else:
                    put_json(path, manifest)
                with self.assertRaisesRegex(BuildError, error):
                    build_native(native, root / "out", set())
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            with self.assertRaisesRegex(BuildError, "collides with a generated plugin"):
                build_native(native_fixture(root), root / "out", {"native"})

    def test_scripts_both_editions_ship_must_be_identical(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            native = native_fixture(root)
            twin = root / "plugins/native"
            put(native / "scripts/router.py", "print('route')\n")
            put(twin / "scripts/router.py", "print('route')\n")
            put(twin / "scripts/hook.py", "print('claude only')\n")
            build_native(native, root / "out", set(), twin)
            self.assertEqual((root / "out/native/scripts/router.py").read_text(), "print('route')\n")
            self.assertFalse((root / "out/native/scripts/hook.py").exists())

            put(twin / "scripts/router.py", "print('drifted')\n")
            with self.assertRaisesRegex(BuildError, "must be identical"):
                build_native(native, root / "out", set(), twin)

    def test_native_edition_of_a_claude_plugin_without_overlay_builds(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "source"
            fixture(source)
            native = native_fixture(source / "omp/native")
            catalog = json.loads((source / ".claude-plugin/marketplace.json").read_text())
            catalog["plugins"].append({"name": "native", "source": "./plugins/native", "version": "0.1.0", "description": "Claude edition", "category": "development"})
            put_json(source / ".claude-plugin/marketplace.json", catalog)
            put(native / "scripts/router.py", "print('route')\n")
            put(source / "plugins/native/scripts/router.py", "print('drifted')\n")
            with self.assertRaisesRegex(BuildError, "must be identical"):
                build(root / "output", source)

            put(source / "plugins/native/scripts/router.py", "print('route')\n")
            build(root / "output", source)
            omp_catalog = json.loads((root / "output/.omp-plugin/marketplace.json").read_text())
            self.assertEqual({entry["name"] for entry in omp_catalog["plugins"]}, {"sample", "native"})

    def test_native_extension_guards(self):
        cases = {
            "package mismatch": ({"name": "different", "version": "0.1.0", "omp": {"extensions": ["index.ts"]}}, "name and version must equal"),
            "no extensions": ({"name": "native", "version": "0.1.0", "omp": {"extensions": []}}, "omp.extensions must list"),
            "missing extension file": ({"name": "native", "version": "0.1.0", "omp": {"extensions": ["missing.ts"]}}, "is not a file"),
        }
        for label, (package, error) in cases.items():
            with self.subTest(label=label), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                native = native_fixture(root)
                put_json(native / "package.json", package)
                with self.assertRaisesRegex(BuildError, error):
                    build_native(native, root / "out", set())

    def test_native_agent_and_skill_guards(self):
        cases = {
            "unknown agent key": ("agents/worker.md", "---\nname: native:worker\nsurprise: yes\n---\n", "unknown OMP agent frontmatter keys"),
            "unprefixed agent": ("agents/worker.md", "---\nname: worker\n---\n", "agent name must start"),
            "unprefixed skill": ("skills/review/SKILL.md", "---\nname: review\n---\n", "skill name must be"),
        }
        for label, (path, content, error) in cases.items():
            with self.subTest(label=label), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                native = native_fixture(root)
                put(native / path, content)
                with self.assertRaisesRegex(BuildError, error):
                    build_native(native, root / "out", set())

    def test_native_agents_validate_csv_and_inline_list_tools(self):
        for tools in ("read, ast-edit", "[read, ast-edit]", '["read", "ast-edit"]'):
            with self.subTest(tools=tools), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                native = native_fixture(root)
                put(native / "agents/worker.md", f"---\nname: native:worker\ndescription: Worker\ntools: {tools}\n---\n\nBody.\n")
                with self.assertRaisesRegex(BuildError, "unknown OMP tool"):
                    build_native(native, root / "out", set())

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            native = native_fixture(root)
            put(native / "agents/worker.md", "---\nname: native:worker\ndescription: Worker\ntools: [read, ast_edit]\n---\n\nBody.\n")
            build_native(native, root / "out", set())
            self.assertTrue((root / "out/native/agents/worker.md").is_file())


if __name__ == "__main__":
    unittest.main()
