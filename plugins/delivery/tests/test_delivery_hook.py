#!/usr/bin/env python3
"""Claude Code hooks of the delivery plugin, driven with the JSON Claude Code sends.

Run: python3 plugins/delivery/tests/test_delivery_hook.py
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

HOOK = Path(__file__).resolve().parent.parent / "scripts" / "delivery_hook.py"
SUBAGENT_DRIVEN = "superpowers:subagent-driven-development"

VALID_PLAN = """# Orders Implementation Plan

### Task 1: Orders endpoint
**Commit:** feat: add orders endpoint

**Files:**
- Create: `backend/app/orders.py`
- Test: `backend/tests/test_orders.py:1-20`

- [ ] **Step 1: Write the failing test**
"""

SPLIT_PLAN = """# Orders Implementation Plan

### Task 1: Orders everywhere
**Files:**
- Create: `backend/app/orders.py`
- Create: `web/src/Orders.tsx`
"""

NO_FILES_PLAN = """# Deploy Plan

### Task 1: Restart the service
```bash
ssh root@host 'systemctl restart api'
```
"""

TRANSLATED_PLAN = """# Plan wdrożenia

### Zadanie 1: Endpoint zamówień
**Files:**
- Create: `backend/app/orders.py`
"""


class HookTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(self._tmp.name).resolve()
        self.repo = self.tmp / "repo"
        (self.repo / "backend").mkdir(parents=True)
        (self.repo / "backend/pyproject.toml").write_text('[project]\nname = "api"\n')
        (self.repo / "web").mkdir()
        (self.repo / "web/package.json").write_text(json.dumps({"dependencies": {"react": "^19"}}))
        subprocess.run(["git", "init", "-q", str(self.repo)], check=True)
        self.data = self.tmp / "data"
        self.plan = self.repo / "docs/superpowers/plans/2026-09-28-orders.md"

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def hook(self, payload: dict, session: str = "session-a", cwd: Path | None = None) -> dict:
        payload = {"session_id": session, "cwd": str(cwd or self.repo), "permission_mode": "default", **payload}
        env = {**os.environ, "CLAUDE_PLUGIN_DATA": str(self.data)}
        result = subprocess.run([sys.executable, str(HOOK)], input=json.dumps(payload), capture_output=True, text=True, env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout) if result.stdout.strip() else {}

    def write_plan(self, text: str, path: Path | None = None, session: str = "session-a") -> dict:
        path = path or self.plan
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return self.hook({
            "hook_event_name": "PostToolUse", "tool_name": "Write",
            "tool_input": {"file_path": str(path), "content": text}, "tool_response": {"filePath": str(path)},
        }, session=session)

    def invoke_skill(self, skill: str, session: str = "session-a", args: str | None = None, cwd: Path | None = None) -> dict:
        tool_input = {"skill": skill, **({"args": args} if args is not None else {})}
        return self.hook({"hook_event_name": "PreToolUse", "tool_name": "Skill", "tool_input": tool_input}, session=session, cwd=cwd)

    @staticmethod
    def decision(output: dict) -> tuple[str | None, str]:
        specific = output.get("hookSpecificOutput", {})
        return specific.get("permissionDecision"), specific.get("permissionDecisionReason") or specific.get("additionalContext") or ""


class SuperpowersHandoverTest(HookTest):
    def test_subagent_driven_execution_runs_the_written_plan_through_delivery(self) -> None:
        self.assertEqual(self.write_plan(VALID_PLAN), {})
        decision, reason = self.decision(self.invoke_skill(SUBAGENT_DRIVEN))
        self.assertEqual(decision, "deny")
        self.assertIn("`delivery:orchestration`", reason)
        self.assertIn(f"args `{self.plan}`", reason)

    def test_non_plan_task_heading_does_not_replace_remembered_plan(self) -> None:
        self.write_plan(VALID_PLAN)
        readme = self.repo / "README.md"
        self.assertEqual(self.write_plan("# Guide\n\n### Task queue\nWork is pending.\n", path=readme), {})

        decision, reason = self.decision(self.invoke_skill(SUBAGENT_DRIVEN))
        self.assertEqual(decision, "deny")
        self.assertIn(f"args `{self.plan}`", reason)


    def test_an_explicit_plan_argument_wins_over_the_session_plan(self) -> None:
        other = self.repo / "docs/plans/other.md"
        other.parent.mkdir(parents=True)
        other.write_text(VALID_PLAN)
        self.write_plan(VALID_PLAN)
        _, reason = self.decision(self.invoke_skill(SUBAGENT_DRIVEN, args="docs/plans/other.md"))
        self.assertIn(f"args `{other}`", reason)

    def test_a_bare_plan_path_containing_spaces_still_wins_over_session_state(self) -> None:
        other = self.repo / "docs/plans/other plan.md"
        other.parent.mkdir(parents=True)
        other.write_text(VALID_PLAN)
        self.write_plan(VALID_PLAN)

        decision, reason = self.decision(self.invoke_skill(SUBAGENT_DRIVEN, args="docs/plans/other plan.md"))
        self.assertEqual(decision, "deny")
        self.assertIn(f"args `{other}`", reason)

    def test_a_plan_named_in_prose_wins_over_the_session_plan_in_both_hooks(self) -> None:
        other = self.repo / "docs/plans/other.md"
        other.parent.mkdir(parents=True)
        other.write_text(VALID_PLAN)
        self.write_plan(VALID_PLAN)

        for args in (
            "Execute `docs/plans/other.md`",
            "Execute `docs/plans/other.md`.",
            "Execute docs/plans/other.md!",
            "Execute docs/plans/other.md?",
            "Execute [the plan](docs/plans/other.md).",
            "docs/plans/other.md now",
        ):
            with self.subTest(args=args):
                decision, reason = self.decision(self.invoke_skill(SUBAGENT_DRIVEN, args=args))
                self.assertEqual(decision, "deny")
                self.assertIn(f"args `{other}`", reason)

                output = self.hook({
                    "hook_event_name": "UserPromptExpansion", "expansion_type": "slash_command",
                    "command_name": SUBAGENT_DRIVEN, "command_args": args,
                    "prompt": f"/{SUBAGENT_DRIVEN} {args}",
                })
                self.assertIn(f"args `{other}`", self.decision(output)[1])

    def test_a_missing_explicit_plan_does_not_fall_back_to_the_session_plan(self) -> None:
        self.write_plan(VALID_PLAN)
        self.assertEqual(self.invoke_skill(SUBAGENT_DRIVEN, args="Execute `docs/plans/missing.md`"), {})
        self.assertEqual(self.hook({
            "hook_event_name": "UserPromptExpansion", "expansion_type": "slash_command",
            "command_name": SUBAGENT_DRIVEN, "command_args": "docs/plans/missing.md now",
        }), {})


    def test_named_plan_outside_repo_is_not_read_by_either_hook(self) -> None:
        self.write_plan(VALID_PLAN)
        outside = self.tmp / "private.md"
        outside.write_text(VALID_PLAN + "\n### Task confidential heading\n")
        link = self.repo / "docs/plans/linked.md"
        link.parent.mkdir(parents=True, exist_ok=True)
        link.symlink_to(outside)

        with patch.dict(os.environ, {"HOME": str(self.tmp)}):
            for args in (str(outside), "../private.md", "~/private.md", "docs/plans/linked.md", f"Execute `{outside}`"):
                with self.subTest(args=args):
                    self.assertEqual(self.invoke_skill(SUBAGENT_DRIVEN, args=args), {})
                    self.assertEqual(self.hook({
                        "hook_event_name": "UserPromptExpansion", "expansion_type": "slash_command",
                        "command_name": SUBAGENT_DRIVEN, "command_args": args,
                    }), {})

    def test_remembered_external_plan_still_hands_over(self) -> None:
        outside = self.tmp / "plans/remembered.md"
        self.assertEqual(self.write_plan(VALID_PLAN, path=outside), {})
        decision, reason = self.decision(self.invoke_skill(SUBAGENT_DRIVEN))
        self.assertEqual(decision, "deny")
        self.assertIn(f"args `{outside}`", reason)


    def test_a_plan_written_in_another_session_is_not_taken_over(self) -> None:
        self.write_plan(VALID_PLAN, session="session-a")
        self.assertEqual(self.invoke_skill(SUBAGENT_DRIVEN, session="session-b"), {})

    def test_a_plan_with_errors_goes_back_to_be_fixed(self) -> None:
        written = self.write_plan(SPLIT_PLAN)
        self.assertIn("touches several stacks", self.decision(written)[1])
        decision, reason = self.decision(self.invoke_skill(SUBAGENT_DRIVEN))
        self.assertEqual(decision, "deny")
        self.assertIn("touches several stacks", reason)
        self.assertNotIn("delivery:orchestration", reason)

    def test_tasks_without_files_are_routed_not_rejected(self) -> None:
        self.write_plan(NO_FILES_PLAN)
        decision, reason = self.decision(self.invoke_skill(SUBAGENT_DRIVEN))
        self.assertEqual(decision, "deny")
        self.assertIn("`delivery:orchestration`", reason)

    def test_a_translated_task_heading_is_reported_and_left_to_superpowers(self) -> None:
        written = self.write_plan(TRANSLATED_PLAN)
        self.assertIn("### Task N: <title>", self.decision(written)[1])
        self.assertEqual(self.invoke_skill(SUBAGENT_DRIVEN), {})

    def test_the_latest_plan_of_the_session_is_the_one_handed_over(self) -> None:
        self.write_plan(VALID_PLAN)
        self.write_plan("# Notes\n\n```markdown\n### Task 1: Example\n```\n", path=self.repo / "docs/notes.md")
        self.assertIn(f"args `{self.plan}`", self.decision(self.invoke_skill(SUBAGENT_DRIVEN))[1])
        self.write_plan(TRANSLATED_PLAN, path=self.repo / "docs/superpowers/plans/2026-09-29-migration.md")
        self.assertEqual(self.invoke_skill(SUBAGENT_DRIVEN), {})

    def test_subagent_plan_write_does_not_replace_the_session_plan(self) -> None:
        self.write_plan(VALID_PLAN)
        notes = self.repo / "docs/plans/notes.md"
        notes.parent.mkdir(parents=True)
        notes.write_text("# Notes\n\nNot an implementation plan.\n")

        output = self.hook({
            "hook_event_name": "PostToolUse", "tool_name": "Write", "agent_id": "implementer-1",
            "tool_input": {"file_path": str(notes), "content": notes.read_text()},
            "tool_response": {"filePath": str(notes)},
        })

        self.assertEqual(output, {})
        decision, reason = self.decision(self.invoke_skill(SUBAGENT_DRIVEN))
        self.assertEqual(decision, "deny")
        self.assertIn(f"args `{self.plan}`", reason)

    def test_outside_git_superpowers_runs_as_usual(self) -> None:
        outside = self.tmp / "outside"
        outside.mkdir()
        plan = outside / "plans/plan.md"
        plan.parent.mkdir()
        plan.write_text(VALID_PLAN)
        self.assertEqual(self.invoke_skill(SUBAGENT_DRIVEN, args=str(plan), cwd=outside), {})

    def test_writing_plans_gets_the_delivery_task_rules(self) -> None:
        output = self.invoke_skill("superpowers:writing-plans")
        decision, text = self.decision(output)
        self.assertIsNone(decision)
        self.assertIn("### Task N: <title>", text)

    def test_other_skills_and_documents_are_left_alone(self) -> None:
        self.assertEqual(self.invoke_skill("superpowers:executing-plans"), {})
        self.assertEqual(self.write_plan("# Notes\n\nNo tasks.\n", path=self.repo / "docs/notes.md"), {})

    def test_a_typed_command_is_handed_over_as_context(self) -> None:
        self.write_plan(VALID_PLAN)
        output = self.hook({
            "hook_event_name": "UserPromptExpansion", "expansion_type": "slash_command",
            "command_name": SUBAGENT_DRIVEN, "command_args": "", "prompt": f"/{SUBAGENT_DRIVEN}",
        })
        _, text = self.decision(output)
        self.assertIn("Do not follow the skill above", text)
        self.assertIn(f"args `{self.plan}`", text)


class PlanModeTest(HookTest):
    def plan_file(self, text: str) -> Path:
        path = self.tmp / "claude/plans/whimsical-plan.md"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def exit_plan_mode(self, phase: str, path: Path) -> dict:
        payload = {"hook_event_name": phase, "tool_name": "ExitPlanMode",
                   "tool_input": {"plan": path.read_text(), "planFilePath": str(path)}}
        if phase == "PostToolUse":
            payload["tool_response"] = {"plan": path.read_text(), "filePath": str(path)}
        return self.hook(payload)

    def test_plan_mode_prompts_get_the_plan_format(self) -> None:
        output = self.hook({"hook_event_name": "UserPromptSubmit", "prompt": "Plan it", "permission_mode": "plan"})
        self.assertIn("### Task 1: <short title>", self.decision(output)[1])
        self.assertEqual(self.hook({"hook_event_name": "UserPromptSubmit", "prompt": "Do it"}), {})

    def test_unroutable_tasks_block_the_plan(self) -> None:
        decision, _ = self.decision(self.exit_plan_mode("PreToolUse", self.plan_file(NO_FILES_PLAN)))
        self.assertEqual(decision, "deny")
        self.assertEqual(self.exit_plan_mode("PreToolUse", self.plan_file(VALID_PLAN)), {})
        self.assertEqual(self.exit_plan_mode("PreToolUse", self.plan_file("# Answer\n\nNo changes.\n")), {})

    def test_research_heading_does_not_block_exit_plan_mode(self) -> None:
        path = self.plan_file("# Research\n\n### Task runner\nNo files change.\n")
        self.assertEqual(self.exit_plan_mode("PreToolUse", path), {})
        self.assertEqual(self.exit_plan_mode("PostToolUse", path), {})


    def test_an_approved_plan_with_tasks_starts_delivery(self) -> None:
        path = self.plan_file(VALID_PLAN)
        output = self.exit_plan_mode("PostToolUse", path)
        self.assertIn("1 task(s)", output.get("systemMessage", ""))
        self.assertIn(f"args `{path}`", self.decision(output)[1])
        self.assertEqual(self.exit_plan_mode("PostToolUse", self.plan_file("# Answer\n\nNo changes.\n")), {})


if __name__ == "__main__":
    unittest.main()
