#!/usr/bin/env python3
"""Claude Code hooks of the delivery plugin.

One entry point for every hook in hooks/hooks.json. It reads the hook input
from stdin and acts on `hook_event_name` and `tool_name`:

- PostToolUse on Write, Edit or MultiEdit of a plan (a Markdown file in a
  `plans` directory, or one with valid `### Task N: <title>` headings): runs
  the plan check, tells Claude every problem, and records the plan for this session.
- PreToolUse on the Skill `superpowers:writing-plans`: adds Delivery's task
  rules to the plan Superpowers is about to write.
- PreToolUse on the Skill `superpowers:subagent-driven-development`: when the
  session's plan has valid tasks, denies the skill and tells Claude to start
  the Delivery run instead; a plan with errors goes back to be fixed.
- UserPromptExpansion of a typed `/superpowers:subagent-driven-development`:
  the same hand-over, as context next to the expanded skill.
- UserPromptSubmit in plan mode: adds Delivery's plan format.
- PreToolUse on ExitPlanMode: rejects a plan with task errors or a task
  without a **Files:** block.
- PostToolUse on ExitPlanMode: hands an approved plan with tasks to the
  Delivery run.

Outside a git repository, an approved plan with a task-like `### Task`
heading gets a skip notice instead of a Delivery run. A Markdown file in a
`plans` directory without task headings is remembered and gets a heading
format reminder; outside `plans` directories, writes without parsed tasks
are ignored. It never asks the user anything: routing is the router's job.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from route_task import TASK_CANDIDATE, check, parse_plan  # noqa: E402

SUBAGENT_DRIVEN = "superpowers:subagent-driven-development"
WRITING_PLANS = "superpowers:writing-plans"
RUN_SKILL = "delivery:orchestration"
PLAN_EDIT_TOOLS = {"Write", "Edit", "MultiEdit"}
STATE_TTL_SECONDS = 30 * 24 * 3600
PLAN_TOKEN = re.compile(r"[^\s`'\"()\[\]<>]+\.md(?!\w)", re.IGNORECASE)

TASK_RULES = """- Every file change belongs to a task. Text outside tasks is context; nobody implements it.
- Number tasks 1, 2, 3… in execution order, each number once; producers before consumers.
- One stack per task: Python, React/TypeScript frontend, PHP, or everything else (docs, CI, configuration). A change that spans backend and frontend is two or more tasks.
- List every file the task creates, modifies, tests or deletes: repository-relative, in backticks. The file list picks the implementing agent.
- Each task stands alone: its agent implements only that task. Name the functions, types and signatures that later tasks rely on.
- Inside a task use no `##` or `###` headings outside fenced code blocks; the next one ends the task."""

PLAN_MODE_FORMAT = f"""# Delivery plans

This session has the delivery plugin. An approved plan that changes files in this git repository is delivered task by task: each `### Task` goes to the developer agent that owns its files and is reviewed and committed on its own; then the plan's `## Verification` runs, QA tests the change when it is testable, and a full code review closes the delivery. Write such a plan's steps as numbered tasks in exactly this shape:

### Task 1: <short title>
**Commit:** <conventional commit subject>

**Files:**
- Create: `path/to/new_module.py`
- Modify: `path/to/existing.py`
- Test: `tests/test_new_module.py`
- Delete: `path/to/obsolete.py`

<concrete steps; when behavior changes, the failing test comes first>

Rules:
{TASK_RULES}
- The heading is `### Task N: <title>` with the English word Task, even in a plan written in another language.
- Calling ExitPlanMode checks these rules and lists every violation.
- A plan that changes no files (research, analysis, an answer) has no `### Task` headings and runs without delivery."""

SUPERPOWERS_FORMAT = f"""Delivery is installed. When your human partner picks subagent-driven execution for this plan, the delivery plugin implements it instead of {SUBAGENT_DRIVEN}: each task goes to the developer agent that owns its files, is reviewed and committed. Keep the writing-plans structure and follow these rules as well:
- Each task heading is exactly `### Task N: <title>`, with the English word Task even when the plan is written in another language.
- Put `**Commit:** <conventional commit subject>` on the line after the heading; it becomes the task's commit subject.
- The **Files:** block has one `- Create|Modify|Test|Delete: <path in backticks>` line per file.
{TASK_RULES}
- Saving the plan runs Delivery's plan check and reports every violation."""


def git_root(cwd: str) -> Path | None:
    try:
        result = subprocess.run(
            ["git", "-C", cwd, "rev-parse", "--show-toplevel"], capture_output=True, text=True, timeout=5,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    top = result.stdout.strip()
    return Path(top) if result.returncode == 0 and top else None


def resolve(data: dict, raw: object) -> Path | None:
    """An existing Markdown file named by `raw`, relative to the session's working directory."""
    if not isinstance(raw, str) or not raw.strip():
        return None
    path = Path(raw.strip()).expanduser()
    if not path.is_absolute():
        path = Path(data.get("cwd") or ".") / path
    return path.resolve() if path.suffix.lower() == ".md" and path.is_file() else None


def state_file(data: dict) -> Path | None:
    root = os.environ.get("CLAUDE_PLUGIN_DATA")
    session = re.sub(r"[^A-Za-z0-9_-]", "", str(data.get("session_id") or ""))
    return Path(root) / "sessions" / f"{session}.json" if root and session else None


def remember_plan(data: dict, plan: Path) -> None:
    """Record the session's plan: Superpowers invokes subagent-driven development without arguments."""
    path = state_file(data)
    if path is None:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    now = time.time()
    for old in path.parent.glob("*.json"):
        try:
            if now - old.stat().st_mtime > STATE_TTL_SECONDS:
                old.unlink()
        except FileNotFoundError:
            continue
    path.write_text(json.dumps({"plan": str(plan)}))


def remembered_plan(data: dict) -> Path | None:
    path = state_file(data)
    if path is None or not path.is_file():
        return None
    try:
        return resolve(data, json.loads(path.read_text()).get("plan"))
    except (ValueError, AttributeError):
        return None


def session_plan(data: dict, raw: object, root: Path) -> Path | None:
    """Use only in-repository named plans; use session state when none is named."""
    text = raw if isinstance(raw, str) else ""
    root = root.resolve()
    direct = resolve(data, text)
    if direct is not None and direct.is_relative_to(root):
        return direct
    named = PLAN_TOKEN.findall(text)
    if not named:
        return remembered_plan(data)
    return next((plan for plan in (resolve(data, token) for token in named)
                 if plan is not None and plan.is_relative_to(root)), None)


def bullets(lines: list[str]) -> str:
    return "\n".join(f"- {line}" for line in lines)


def context(event: str, text: str, message: str | None = None) -> dict:
    output: dict = {"hookSpecificOutput": {"hookEventName": event, "additionalContext": text}}
    if message:
        output["systemMessage"] = message
    return output


def deny(reason: str) -> dict:
    return {"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": reason}}


def takeover(plan: Path, tasks: int, replaced: str) -> str:
    return (
        f"Delivery takes over this plan instead of {replaced}: {plan} has {tasks} task(s) under `### Task` headings. "
        "Each task goes to the developer agent the router picks for it, is reviewed and committed; then the plan's "
        "Verification, QA when the change is testable, and a full code review run. Do not implement the plan yourself.\n\n"
        f"Invoke the Skill tool now with skill `{RUN_SKILL}` and args `{plan}`, and carry out its Delivery run."
    )


def plan_written(data: dict) -> dict | None:
    if data.get("agent_id"):
        return None
    plan = resolve(data, (data.get("tool_input") or {}).get("file_path"))
    if plan is None:
        return None
    text = plan.read_text(errors="replace")
    in_plans_dir = plan.parent.name == "plans"
    if not in_plans_dir and not parse_plan(text):
        return None
    root = git_root(data.get("cwd") or str(plan.parent))
    if root is None:
        return None
    result = check(root, text)
    if result["tasks"] == 0 and not result["problems"] and not in_plans_dir:
        return None
    remember_plan(data, plan)
    if result["tasks"] == 0 and not result["problems"]:
        return context("PostToolUse", (
            f"Delivery found no `### Task N: <title>` headings in {plan}. If this plan changes files, give every task "
            "such a heading, with the English word Task even in a plan written in another language, and a **Files:** "
            "block; without them Delivery cannot deliver the plan."
        ))
    notes = []
    if result["problems"]:
        notes.append(f"Delivery plan check failed for {plan}:\n{bullets(result['problems'])}\nFix these tasks in the plan now.")
    if result["no_files"]:
        guidance = (
            "ExitPlanMode rejects these tasks; add a **Files:** block to each."
            if data.get("permission_mode") == "plan"
            else "Delivery routes them by their text; add the block to every task that changes files."
        )
        notes.append(
            f"Tasks without a **Files:** block in {plan}:\n{bullets(result['no_files'])}\n"
            f"{guidance}"
        )
    return context("PostToolUse", "\n\n".join(notes)) if notes else None


def hand_over(data: dict, args: object) -> dict | None:
    """Replace subagent-driven development with the Delivery run for a plan with valid tasks."""
    root = git_root(data.get("cwd") or ".")
    if root is None:
        return None
    plan = session_plan(data, args, root)
    if plan is None:
        return None
    result = check(root, plan.read_text(errors="replace"))
    if result["tasks"] == 0:
        return None
    if result["problems"]:
        return deny(
            f"Delivery takes over subagent-driven execution, but {plan} has errors:\n{bullets(result['problems'])}\n"
            f"Fix these tasks in the plan, then invoke {SUBAGENT_DRIVEN} again."
        )
    return deny(takeover(plan, result["tasks"], SUBAGENT_DRIVEN))


def expansion(data: dict) -> dict | None:
    if not str(data.get("command_name") or "").endswith("subagent-driven-development"):
        return None
    root = git_root(data.get("cwd") or ".")
    if root is None:
        return None
    plan = session_plan(data, data.get("command_args"), root)
    if plan is None:
        return None
    result = check(root, plan.read_text(errors="replace"))
    if result["tasks"] == 0:
        return None
    if result["problems"]:
        text = (
            f"Delivery replaces {SUBAGENT_DRIVEN} for {plan}, but the plan has errors:\n{bullets(result['problems'])}\n"
            f"Do not follow the skill above. Fix these tasks in the plan, then invoke the Skill tool with skill "
            f"`{RUN_SKILL}` and args `{plan}`."
        )
    else:
        text = "Do not follow the skill above. " + takeover(plan, result["tasks"], SUBAGENT_DRIVEN)
    return context("UserPromptExpansion", text)


def plan_proposed(data: dict) -> dict | None:
    tool_input = data.get("tool_input") or {}
    plan = resolve(data, tool_input.get("planFilePath"))
    text = tool_input.get("plan") if isinstance(tool_input.get("plan"), str) else None
    if text is None and plan is not None:
        text = plan.read_text(errors="replace")
    root = git_root(data.get("cwd") or ".")
    if not text or root is None:
        return None
    result = check(root, text)
    violations = result["problems"] + result["no_files"]
    if not violations:
        return None
    return deny(
        f"Delivery plan check failed for {plan or 'the plan'}:\n{bullets(violations)}\n"
        "Fix these tasks in the plan file, then call ExitPlanMode again."
    )


def plan_approved(data: dict) -> dict | None:
    response = data.get("tool_response") if isinstance(data.get("tool_response"), dict) else {}
    plan = resolve(data, response.get("filePath")) or resolve(data, (data.get("tool_input") or {}).get("planFilePath"))
    if plan is None:
        return None
    text = plan.read_text(errors="replace")
    if not TASK_CANDIDATE.search(text):
        return None
    root = git_root(data.get("cwd") or ".")
    if root is None:
        return {"systemMessage": "Delivery skipped: not a git repository. The plan runs without delivery."}
    result = check(root, text)
    if result["tasks"] == 0:
        return None
    if result["problems"]:
        return {"systemMessage": f"Delivery skipped: {plan} has errors: {' '.join(result['problems'])} The plan runs without delivery."}
    return context(
        "PostToolUse",
        "<critical>\n" + takeover(plan, result["tasks"], "executing it step by step yourself")
        + " Do not edit project files yourself.\n</critical>",
        f"Delivery: {result['tasks']} task(s) — starting the delivery run.",
    )


def dispatch(data: dict) -> dict | None:
    event = data.get("hook_event_name")
    tool = data.get("tool_name")
    tool_input = data.get("tool_input") or {}
    if event == "UserPromptSubmit":
        if data.get("permission_mode") == "plan" and git_root(data.get("cwd") or "."):
            return context("UserPromptSubmit", PLAN_MODE_FORMAT)
        return None
    if event == "UserPromptExpansion":
        return expansion(data)
    if event == "PreToolUse" and tool == "Skill":
        skill = tool_input.get("skill")
        if skill == WRITING_PLANS:
            return context("PreToolUse", SUPERPOWERS_FORMAT) if git_root(data.get("cwd") or ".") else None
        if skill == SUBAGENT_DRIVEN:
            return hand_over(data, tool_input.get("args"))
        return None
    if event == "PreToolUse" and tool == "ExitPlanMode":
        return plan_proposed(data)
    if event == "PostToolUse" and tool == "ExitPlanMode":
        return plan_approved(data)
    if event == "PostToolUse" and tool in PLAN_EDIT_TOOLS:
        return plan_written(data)
    return None


def main() -> int:
    try:
        data = json.load(sys.stdin)
    except ValueError:
        return 0
    if not isinstance(data, dict):
        return 0
    try:
        output = dispatch(data)
    except (OSError, ValueError) as error:
        output = {"systemMessage": f"Delivery hook failed: {error}"}
    if output:
        print(json.dumps(output))
    return 0


if __name__ == "__main__":
    sys.exit(main())
