#!/usr/bin/env python3
"""Routing contract for delivery tasks: which developer agent owns a task.

Run: python3 omp/native/delivery/tests/test_route_task.py
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent.parent / "scripts"
sys.path.insert(0, str(SCRIPTS))

from route_task import check, layout, parse_plan, route, scan_delivery_log  # noqa: E402

ROUTER = SCRIPTS / "route_task.py"


def write(root: Path, rel: str, content: str) -> None:
    path = root / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)


class RoutingFixture(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        cls.root = Path(cls._tmp.name)
        write(cls.root, "backend/pyproject.toml", '[project]\nname = "api"\ndependencies = ["fastapi"]\n')
        write(cls.root, "web/package.json", json.dumps({"dependencies": {"react": "^19", "@tanstack/react-query": "^5"}}))
        write(cls.root, "shop/composer.json", json.dumps({"require": {"symfony/framework-bundle": "^7"}}))
        write(cls.root, "tools/package.json", json.dumps({"dependencies": {"commander": "^12"}}))
        write(cls.root, "services/reports/pyproject.toml", '[project]\nname = "reports"\n')
        write(cls.root, "services/reports/web/package.json", json.dumps({"dependencies": {"react": "^19"}}))

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def routed(self, *paths: str) -> dict:
        return route(self.root, list(paths))

    def run_router(self, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run([sys.executable, str(ROUTER), *args], capture_output=True, text=True)


class RouteTest(RoutingFixture):
    def test_python_backend_task(self) -> None:
        r = self.routed("backend/app/orders.py", "backend/tests/test_orders.py")
        self.assertEqual((r["stack"], r["agent"]), ("python", "python-developer:developer"))

    def test_react_task(self) -> None:
        r = self.routed("web/src/List.tsx", "web/src/List.test.tsx")
        self.assertEqual((r["stack"], r["agent"]), ("frontend", "frontend-developer:developer"))

    def test_php_task(self) -> None:
        r = self.routed("shop/src/Controller/OrderController.php")
        self.assertEqual((r["stack"], r["agent"]), ("php", "php-developer:developer"))

    def test_new_file_in_missing_directory(self) -> None:
        self.assertEqual(self.routed("backend/app/billing/invoices.py")["stack"], "python")

    def test_backticks_and_line_range_are_stripped(self) -> None:
        r = self.routed("`backend/app/orders.py:120-145`")
        self.assertEqual(r["stack"], "python")
        self.assertEqual(r["files"], ["backend/app/orders.py"])

    def test_two_stacks_split(self) -> None:
        r = self.routed("backend/app/orders.py", "web/src/api.ts")
        self.assertEqual(r["stack"], "split")
        self.assertIsNone(r["agent"])
        self.assertEqual(set(r["groups"]), {"python", "frontend"})

    def test_docs_only_is_generic(self) -> None:
        r = self.routed("docs/a.md", "README.md")
        self.assertEqual((r["stack"], r["agent"]), ("generic", "delivery:implementer"))

    def test_node_without_react_is_generic(self) -> None:
        self.assertEqual(self.routed("tools/cli.ts")["stack"], "generic")

    def test_nearest_manifest_wins_for_nested_react_app(self) -> None:
        self.assertEqual(self.routed("services/reports/web/src/Chart.tsx")["stack"], "frontend")

    def test_python_file_of_nested_service(self) -> None:
        self.assertEqual(self.routed("services/reports/build.py")["stack"], "python")

    def test_python_file_outside_any_project(self) -> None:
        self.assertEqual(self.routed("scripts/gen.py")["stack"], "python")

    def test_web_file_under_python_project_is_generic(self) -> None:
        self.assertEqual(self.routed("backend/app/widget.ts")["stack"], "generic")

    def test_docs_beside_code_do_not_vote(self) -> None:
        r = self.routed("backend/app/orders.py", "docs/orders.md", "backend/pyproject.toml")
        self.assertEqual(r["stack"], "python")

    def test_no_paths_is_unknown(self) -> None:
        r = self.routed()
        self.assertEqual(r["stack"], "unknown")
        self.assertIsNone(r["agent"])


PLAN = """# Plan

## Goal
Something.

### Task 1: Orders endpoint
**Commit:** feat: add orders endpoint

**Files:**
- Create: `backend/app/orders.py`
- Modify: `backend/app/main.py:10-20`
- Test: `backend/tests/test_orders.py`

Steps.

### Task 2: Docs
**Files:**
- Create: docs/orders.md

## Notes
Not part of task 2: `- Create: ignored.py`
"""


class ParsePlanTest(unittest.TestCase):
    def test_tasks_paths_and_commit(self) -> None:
        tasks = parse_plan(PLAN)
        self.assertEqual([t["task"] for t in tasks], [1, 2])
        self.assertEqual(tasks[0]["title"], "Orders endpoint")
        self.assertEqual(tasks[0]["commit"], "feat: add orders endpoint")
        self.assertEqual(
            tasks[0]["paths"],
            ["backend/app/orders.py", "backend/app/main.py:10-20", "backend/tests/test_orders.py"],
        )
        self.assertIsNone(tasks[1]["commit"])
        self.assertEqual(tasks[1]["paths"], ["docs/orders.md"])
        self.assertNotIn("Notes", tasks[1]["block"])

    def test_fenced_markdown_stays_inside_the_task(self) -> None:
        tasks = parse_plan(FENCED_PLAN)
        self.assertEqual([t["task"] for t in tasks], [1])
        self.assertEqual(tasks[0]["paths"], ["README.md"])
        self.assertIn("## Usage", tasks[0]["block"])
        self.assertTrue(tasks[0]["block"].endswith("Append it after the intro."), tasks[0]["block"])


FENCED_PLAN = """# Plan

### Task 1: Usage docs
**Files:**
- Modify: `README.md`

````markdown
## Usage

```python
from calc.ops import add
```

### Task 9: Not a task
- Create: `not/a/task/file.py`
````

Append it after the intro.

## Verification
- pytest
"""


SPLIT_PLAN = """# Plan

### Task 1: Orders
**Files:**
- Modify: `backend/app/orders.py`
- Modify: `web/src/api.ts`

### Task 2: Notes
Write the release notes.

### Task 2: Docs
**Files:**
- Create: `docs/orders.md`
"""


class CheckTest(RoutingFixture):
    def test_reports_every_unroutable_task(self) -> None:
        result = check(self.root, SPLIT_PLAN)
        self.assertEqual(result["tasks"], 3)
        problems = result["problems"]
        self.assertEqual(len(problems), 2, problems)
        self.assertTrue(problems[0].startswith("Task 1 (Orders): touches several stacks"), problems[0])
        self.assertIn("python: backend/app/orders.py; frontend: web/src/api.ts", problems[0])
        self.assertTrue(problems[1].startswith("Task 2 appears 2 times"), problems[1])
        self.assertEqual(len(result["no_files"]), 1, result)
        self.assertTrue(result["no_files"][0].startswith("Task 2 (Notes): lists no files"), result)

    def test_routable_plan_has_no_problems(self) -> None:
        self.assertEqual(check(self.root, PLAN), {"tasks": 2, "problems": [], "no_files": []})

    def test_empty_task_title_does_not_consume_files_heading(self) -> None:
        plan = """### Task 1:
**Files:**
- Modify: `backend/app/orders.py`
"""
        self.assertEqual(parse_plan(plan), [])
        result = check(self.root, plan)
        self.assertEqual(result["tasks"], 0)
        self.assertTrue(any("### Task 1:" in problem for problem in result["problems"]), result)

    def test_empty_title_does_not_consume_commit_line(self) -> None:
        plan = """### Task 1:
**Commit:** feat: add orders
**Files:**
- Modify: `backend/app/orders.py`
"""
        self.assertEqual(parse_plan(plan), [])
        self.assertTrue(check(self.root, plan)["problems"])

    def test_empty_commit_does_not_consume_files_heading(self) -> None:
        plan = """### Task 1: Orders
**Commit:**
**Files:**
- Modify: `backend/app/orders.py`
"""
        tasks = parse_plan(plan)
        self.assertEqual(tasks[0]["commit"], None)
        result = check(self.root, plan)
        self.assertEqual(result["tasks"], 1)
        self.assertTrue(any("Commit" in problem for problem in result["problems"]), result)

    def test_empty_file_entry_does_not_consume_next_line(self) -> None:
        plan = """### Task 1: Orders
**Files:**
- Modify:
`backend/app/orders.py`
"""
        self.assertEqual(parse_plan(plan)[0]["paths"], [])
        result = check(self.root, plan)
        self.assertEqual(result["problems"], [])
        self.assertTrue(any("lists no files" in message for message in result["no_files"]), result)

    def test_invalid_task_heading_in_fence_is_not_reported(self) -> None:
        plan = """### Task 1: Orders
**Files:**
- Modify: `backend/app/orders.py`
```
### Task 2:
**Commit:**
```
"""
        self.assertEqual(check(self.root, plan), {"tasks": 1, "problems": [], "no_files": []})

    def test_malformed_heading_is_reported_beside_valid_task(self) -> None:
        plan = """### Task 1: Orders
**Files:**
- Modify: `backend/app/orders.py`
### Task two: Docs
**Files:**
- Modify: `docs/orders.md`
"""
        result = check(self.root, plan)
        self.assertEqual(result["tasks"], 1)
        self.assertTrue(any("### Task two: Docs" in problem for problem in result["problems"]), result)


class LayoutTest(RoutingFixture):
    def test_stacks_and_framework_evidence(self) -> None:
        result = layout(self.root)
        self.assertEqual(result["stacks"], ["python", "frontend", "php"])
        self.assertIn("backend/: python (fastapi)", result["lines"])
        self.assertIn("tools/: node (package.json)", result["lines"])


class CliTest(RoutingFixture):
    def test_plan_without_tasks_exits_2(self) -> None:
        write(self.root, "empty-plan.md", "# Nothing here\n")
        result = self.run_router("plan", str(self.root), "empty-plan.md")
        self.assertEqual(result.returncode, 2)
        self.assertIn("no '### Task N:' headings", result.stderr)

    def test_plan_rejects_duplicate_task_numbers(self) -> None:
        write(self.root, "duplicate-plan.md", """### Task 1: Orders
**Files:**
- Modify: `backend/app/orders.py`

### Task 1: Docs
**Files:**
- Modify: `docs/orders.md`
""")
        result = self.run_router("plan", str(self.root), "duplicate-plan.md")
        self.assertEqual(result.returncode, 2)
        self.assertIn("Task 1 appears 2 times", result.stderr)

    def test_check_without_tasks_reports_zero(self) -> None:
        write(self.root, "empty-plan.md", "# Nothing here\n")
        result = self.run_router("check", str(self.root), "empty-plan.md")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), {"tasks": 0, "problems": [], "no_files": []})

    def test_check_cli_separates_tasks_without_files(self) -> None:
        write(self.root, "notes-plan.md", """### Task 1: Notes
Write release notes.

### Task 2: Orders
**Files:**
- Modify: `backend/app/orders.py`
""")
        result = self.run_router("check", str(self.root), "notes-plan.md")
        self.assertEqual(result.returncode, 0, result.stderr)
        checked = json.loads(result.stdout)
        self.assertEqual(checked["tasks"], 2)
        self.assertEqual(checked["problems"], [])
        self.assertEqual(len(checked["no_files"]), 1, checked)
        self.assertIn("Task 1 (Notes)", checked["no_files"][0])

    def test_check_cli_reports_empty_title_and_commit(self) -> None:
        write(self.root, "invalid-plan.md", """### Task 1:
**Files:**
- Modify: `backend/app/orders.py`
### Task 2: Orders
**Commit:**
**Files:**
- Modify: `backend/app/orders.py`
""")
        result = self.run_router("check", str(self.root), "invalid-plan.md")
        self.assertEqual(result.returncode, 0, result.stderr)
        checked = json.loads(result.stdout)
        self.assertEqual(checked["tasks"], 1)
        self.assertEqual(len(checked["problems"]), 2, checked)
        self.assertTrue(any("### Task 1:" in problem for problem in checked["problems"]), checked)
        self.assertTrue(any("empty **Commit:**" in problem for problem in checked["problems"]), checked)

    def test_plan_routes_every_task(self) -> None:
        write(self.root, "plan.md", PLAN)
        result = self.run_router("plan", str(self.root), "plan.md")
        self.assertEqual(result.returncode, 0, result.stderr)
        routed = json.loads(result.stdout)
        self.assertEqual([(t["task"], t["agent"]) for t in routed], [(1, "python-developer:developer"), (2, "delivery:implementer")])


class MessageTest(RoutingFixture):
    def setUp(self) -> None:
        write(self.root, "plan.md", PLAN)

    def test_message_uses_commit_and_exact_trailers(self) -> None:
        result = self.run_router("message", str(self.root), "plan.md", "1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout,
            "feat: add orders endpoint\n\nDelivery-Plan: plan.md\n"
            "Delivery-Task: 1\nDelivery-Task-Title: Orders endpoint\n",
        )

    def test_message_falls_back_to_chore_and_adds_review_trailer(self) -> None:
        result = self.run_router("message", str(self.root), "plan.md", "2", "--open-findings")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(result.stdout.startswith("chore: Docs\n\n"), result.stdout)
        self.assertTrue(
            result.stdout.endswith("Delivery-Task-Title: Docs\nDelivery-Review: accepted-with-open-findings\n"),
            result.stdout,
        )

    def test_message_rejects_unknown_task(self) -> None:
        result = self.run_router("message", str(self.root), "plan.md", "3")
        self.assertEqual(result.returncode, 2)
        self.assertIn("task 3 is not in", result.stderr)

    def test_message_rejects_unknown_option(self) -> None:
        result = self.run_router("message", str(self.root), "plan.md", "1", "--bogus")
        self.assertEqual(result.returncode, 2)

    def test_message_rejects_plan_outside_root(self) -> None:
        with tempfile.TemporaryDirectory() as elsewhere:
            external = Path(elsewhere) / "plan.md"
            external.write_text(PLAN)
            result = self.run_router("message", str(self.root), str(external), "1")
        self.assertEqual(result.returncode, 2)
        self.assertIn("plan must be inside", result.stderr)

    def test_message_rejects_plan_without_tasks(self) -> None:
        write(self.root, "empty.md", "# Empty\n")
        result = self.run_router("message", str(self.root), "empty.md", "1")
        self.assertEqual(result.returncode, 2)
        self.assertIn("no '### Task N:' headings", result.stderr)

    def test_message_rejects_duplicate_task_numbers(self) -> None:
        write(self.root, "duplicate.md", "### Task 1: First\n### Task 1: Second\n")
        result = self.run_router("message", str(self.root), "duplicate.md", "1")
        self.assertEqual(result.returncode, 2)
        self.assertIn("Task 1 appears 2 times", result.stderr)


class ScanDeliveryLogTest(unittest.TestCase):
    def test_exact_plan_and_titles_with_conflicts(self) -> None:
        rel = "docs/plans/plan.md"
        titles = {1: "Orders endpoint", 2: "Docs"}
        log = (
            "other\0feat: other\n\nDelivery-Plan: docs/plans/plan.md.bak\n"
            "Delivery-Task: 1\nDelivery-Task-Title: Orders endpoint\n\0\n"
            "first\0feat: docs\n\nDelivery-Plan: docs/plans/plan.md\n"
            "Delivery-Task: 2\nDelivery-Task-Title: Docs\n\0\n"
            "unknown\0Delivery-Plan: docs/plans/plan.md\nDelivery-Task: 9\n"
            "Delivery-Task-Title: Other\n\0\n"
            "changed\0Delivery-Plan: docs/plans/plan.md\nDelivery-Task: 1\n"
            "Delivery-Task-Title: Old name\n\0\n"
            "missing\0Delivery-Plan: docs/plans/plan.md\nDelivery-Task: 1\n\0\n"
            "matched\0Delivery-Plan: docs/plans/plan.md\nDelivery-Task: 1\n"
            "Delivery-Task-Title: Orders endpoint\n\0\n"
        )

        done, conflicts, first = scan_delivery_log(log, rel, titles)

        self.assertEqual(done, {1, 2})
        self.assertEqual(conflicts, [
            {"commit": "changed", "task": 1, "committed_title": "Old name", "plan_title": "Orders endpoint"},
            {"commit": "missing", "task": 1, "committed_title": None, "plan_title": "Orders endpoint"},
        ])
        self.assertEqual(first, "first")

    def test_empty_log_has_no_first_commit(self) -> None:
        self.assertEqual(scan_delivery_log("", "docs/plans/plan.md", {1: "Orders"}), (set(), [], None))


class DoneTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        write(self.root, "docs/plans/plan.md", PLAN)
        self.initial = self.commit(self.root, "init\n")

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def commit(self, repo: Path, message: str, signed: bool = False) -> str:
        subprocess.run(
            ["git", "-C", str(repo), "-c", "user.name=test", "-c", "user.email=test@example.com",
             "-c", f"commit.gpgsign={'true' if signed else 'false'}", "commit", "-q", "--allow-empty", "-F", "-"],
            input=message, text=True, check=True,
        )
        return subprocess.run(
            ["git", "-C", str(repo), "rev-parse", "HEAD"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()

    def run_router(self, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run([sys.executable, str(ROUTER), *args], capture_output=True, text=True)

    def done(self) -> dict:
        result = self.run_router("done", str(self.root), "docs/plans/plan.md")
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def delivery_message(self, number: int, title: str | None, plan: str = "docs/plans/plan.md") -> str:
        message = f"feat: x\n\nDelivery-Plan: {plan}\nDelivery-Task: {number}\n"
        if title is not None:
            message += f"Delivery-Task-Title: {title}\n"
        return message

    def test_done_without_delivery_commits_uses_head_as_base(self) -> None:
        self.assertEqual(self.done(), {"done": [], "conflicts": [], "base": self.initial})

    def test_done_recognizes_matching_title_and_uses_parent_as_base(self) -> None:
        self.commit(self.root, self.delivery_message(1, "Orders endpoint"))
        self.assertEqual(self.done(), {"done": [1], "conflicts": [], "base": self.initial})

    def test_done_ignores_signature_output_from_git_log(self) -> None:
        signing_key = self.root / ".git" / "signing-key"
        subprocess.run(
            ["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(signing_key)],
            check=True, capture_output=True,
        )
        for option, value in (
            ("gpg.format", "ssh"),
            ("user.signingkey", str(signing_key)),
            ("log.showSignature", "true"),
        ):
            subprocess.run(["git", "-C", str(self.root), "config", option, value], check=True)
        self.commit(self.root, self.delivery_message(1, "Orders endpoint"), signed=True)
        sha = self.commit(self.root, self.delivery_message(1, "Old name"), signed=True)
        self.assertEqual(self.done(), {
            "done": [1],
            "conflicts": [{"commit": sha, "task": 1, "committed_title": "Old name", "plan_title": "Orders endpoint"}],
            "base": self.initial,
        })

    def test_done_ignores_substring_plan_match(self) -> None:
        sha = self.commit(self.root, self.delivery_message(1, "Orders endpoint", "docs/plans/plan.md.bak"))
        self.assertEqual(self.done(), {"done": [], "conflicts": [], "base": sha})

    def test_done_ignores_unknown_task_but_uses_its_commit_as_base(self) -> None:
        self.commit(self.root, self.delivery_message(9, "Other"))
        self.assertEqual(self.done(), {"done": [], "conflicts": [], "base": self.initial})

    def test_done_sorts_tasks_and_uses_first_delivery_parent(self) -> None:
        self.commit(self.root, self.delivery_message(2, "Docs"))
        self.commit(self.root, self.delivery_message(1, "Orders endpoint"))
        self.assertEqual(self.done(), {"done": [1, 2], "conflicts": [], "base": self.initial})

    def test_done_matches_backticks_in_title_byte_for_byte(self) -> None:
        write(self.root, "docs/plans/plan.md", "### Task 1: Rename `foo`\n")
        self.commit(self.root, self.delivery_message(1, "Rename `foo`"))
        self.assertEqual(self.done(), {"done": [1], "conflicts": [], "base": self.initial})

    def test_done_preserves_unicode_line_separator_in_title(self) -> None:
        title = "A\u2028B"
        write(self.root, "docs/plans/plan.md", f"### Task 1: {title}\n")
        message = self.run_router("message", str(self.root), "docs/plans/plan.md", "1")
        self.assertEqual(message.returncode, 0, message.stderr)
        self.commit(self.root, message.stdout)
        self.assertEqual(self.done(), {"done": [1], "conflicts": [], "base": self.initial})


    def test_done_reports_git_failure(self) -> None:
        with tempfile.TemporaryDirectory() as elsewhere:
            root = Path(elsewhere)
            write(root, "plan.md", PLAN)
            result = self.run_router("done", str(root), "plan.md")
        self.assertEqual(result.returncode, 2)
        self.assertIn("not a git repository", result.stderr)


if __name__ == "__main__":
    unittest.main()
