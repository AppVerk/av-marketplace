#!/usr/bin/env python3
"""Route delivery tasks to the developer agent that owns their stack.

A task's stack comes from the files it touches: `.py` is Python, `.php` is
PHP, and TypeScript/JavaScript/CSS is React frontend only when the nearest
manifest above the file is a `package.json` that depends on React. Docs and
config files do not vote. Nothing here calls a model.

Usage:
    route_task.py plan <root> <plan.md>   # JSON list, one entry per task
    route_task.py check <root> <plan.md>  # JSON {"tasks": N, "problems": [...], "no_files": [...]}
    route_task.py message <root> <plan.md> <N> [--open-findings]  # task commit with trailers
    route_task.py done <root> <plan.md>  # JSON delivered tasks, conflicts, base
    route_task.py files <root> <path>...  # JSON routing for these paths
    route_task.py layout <root>           # JSON repo layout for a judge
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path

AGENTS = {
    "python": "python-developer:developer",
    "frontend": "frontend-developer:developer",
    "php": "php-developer:developer",
    "generic": "delivery:implementer",
}
PY_MANIFESTS = ("pyproject.toml", "setup.py", "setup.cfg", "requirements.txt")
FRONTEND_EXT = {".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs", ".css", ".scss"}
SKIP_DIRS = {"node_modules", "vendor", "dist", "build", "target", "__pycache__", "venv"}
LAYOUT_DEPTH = 3

PY_FRAMEWORKS = ("fastapi", "django", "flask", "celery", "sqlalchemy", "pydantic")
PHP_FRAMEWORKS = {
    "symfony/framework-bundle": "symfony",
    "doctrine/orm": "doctrine",
    "laravel/framework": "laravel",
}
JS_FRAMEWORKS = (
    "next", "vite", "tailwindcss", "zustand",
    "@tanstack/react-query", "@tanstack/react-router", "react-hook-form",
)

TASK_HEADING = re.compile(r"^### Task (\d+):[ \t]*(\S.*?)[ \t]*$", re.MULTILINE)
SECTION_END = re.compile(r"^#{2,3} ", re.MULTILINE)
FILE_LINE = re.compile(r"^[ \t]*[-*][ \t]*(?:Create|Modify|Test|Delete):[ \t]*(\S.*?)[ \t]*$", re.MULTILINE)
COMMIT_LINE = re.compile(r"^\*\*Commit:\*\*[ \t]*(\S.*?)[ \t]*$", re.MULTILINE)
TASK_CANDIDATE = re.compile(r"^### Task(?=[ \t:]|$)[^\n]*", re.MULTILINE)
EMPTY_COMMIT = re.compile(r"^\*\*Commit:\*\*[ \t]*$", re.MULTILINE)
BACKTICKED = re.compile(r"`([^`]+)`")
FENCE = re.compile(r"^ {0,3}(`{3,}|~{3,})(.*)$", re.MULTILINE)


def clean_path(raw: str) -> str:
    """Strip backticks, whitespace and a `:12-34` line-range suffix."""
    return raw.strip().strip("`").strip().split(":", 1)[0]


def read_json(path: Path) -> dict:
    try:
        data = json.loads(path.read_text())
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def js_dependencies(package_json: Path) -> set[str]:
    data = read_json(package_json)
    deps: set[str] = set()
    for key in ("dependencies", "devDependencies"):
        section = data.get(key)
        if isinstance(section, dict):
            deps.update(section)
    return deps


def has_manifest(directory: Path) -> bool:
    return any((directory / name).is_file() for name in (*PY_MANIFESTS, "composer.json", "package.json"))


def frontend_or_generic(root: Path, rel: Path) -> str:
    """A web file is frontend only when its nearest manifest is a React package.json."""
    directory = (root / rel).parent
    for candidate in [directory, *directory.parents]:
        if candidate != root and root not in candidate.parents:
            break
        if candidate.is_dir() and has_manifest(candidate):
            package_json = candidate / "package.json"
            if package_json.is_file() and "react" in js_dependencies(package_json):
                return "frontend"
            return "generic"
        if candidate == root:
            break
    return "generic"


def classify(root: Path, raw: str) -> str | None:
    """Stack of one path, or None when the file is neutral (docs, config)."""
    rel = Path(clean_path(raw))
    if rel.is_absolute() or ".." in rel.parts:
        return None
    suffix = rel.suffix.lower()
    if suffix == ".py":
        return "python"
    if suffix == ".php":
        return "php"
    if suffix in FRONTEND_EXT:
        return frontend_or_generic(root, rel)
    return None


def route(root: Path, paths: list[str]) -> dict:
    files = [clean_path(p) for p in paths]
    groups: dict[str, list[str]] = {}
    for raw, path in zip(paths, files):
        stack = classify(root, raw)
        if stack is not None:
            groups.setdefault(stack, []).append(path)
    if not files:
        stack = "unknown"
    elif not groups:
        stack = "generic"
    elif len(groups) == 1:
        stack = next(iter(groups))
    else:
        stack = "split"
    return {"files": files, "stack": stack, "agent": AGENTS.get(stack), "groups": groups}


def fenced_spans(text: str) -> list[tuple[int, int]]:
    """Offsets of fenced code blocks, fences included; an unclosed fence runs to the end."""
    spans = []
    opening = None
    for fence in FENCE.finditer(text):
        marker = fence.group(1)
        if opening is None:
            opening = fence
        elif marker[0] == opening.group(1)[0] and len(marker) >= len(opening.group(1)) and not fence.group(2).strip():
            spans.append((opening.start(), fence.end()))
            opening = None
    if opening is not None:
        spans.append((opening.start(), len(text)))
    return spans


def parse_plan(text: str) -> list[dict]:
    """Task blocks of a plan. Headings and file lines inside fenced code blocks are content, not structure."""
    fences = fenced_spans(text)

    def unfenced(pattern: re.Pattern[str], start: int = 0, end: int | None = None) -> list[re.Match[str]]:
        matches = pattern.finditer(text, start, len(text) if end is None else end)
        return [m for m in matches if not any(a <= m.start() < b for a, b in fences)]

    tasks = []
    for heading in unfenced(TASK_HEADING):
        stops = unfenced(SECTION_END, heading.end())
        end = stops[0].start() if stops else len(text)
        paths = []
        for match in unfenced(FILE_LINE, heading.end(), end):
            value = match.group(1)
            quoted = BACKTICKED.search(value)
            paths.append(quoted.group(1) if quoted else value.split()[0])
        commit = unfenced(COMMIT_LINE, heading.end(), end)
        tasks.append({
            "task": int(heading.group(1)),
            "title": heading.group(2),
            "commit": commit[0].group(1) if commit else None,
            "block": text[heading.start():end].rstrip(),
            "paths": paths,
        })
    return tasks


def duplicate_tasks(tasks: list[dict]) -> list[str]:
    counts = Counter(task["task"] for task in tasks)
    return [
        f"Task {number} appears {counts[number]} times. Number tasks 1, 2, 3… once each."
        for number in sorted(n for n, count in counts.items() if count > 1)
    ]


def check(root: Path, text: str) -> dict:
    """Report plan errors in problems and tasks without a Files block in no_files."""
    tasks = parse_plan(text)
    fences = fenced_spans(text)
    problems = []
    no_files = []
    for heading in TASK_CANDIDATE.finditer(text):
        if not any(start <= heading.start() < end for start, end in fences) and not TASK_HEADING.fullmatch(heading.group()):
            problems.append(f"Invalid task heading {heading.group()!r}. Use '### Task N: <title>' on one line.")
    for task in tasks:
        routed = route(root, task["paths"])
        label = f"Task {task['task']} ({task['title']})"
        block_fences = fenced_spans(task["block"])
        if any(not any(start <= match.start() < end for start, end in block_fences)
               for match in EMPTY_COMMIT.finditer(task["block"])):
            problems.append(f"{label}: empty **Commit:**. Add a subject or remove the line.")
        if routed["stack"] == "split":
            groups = "; ".join(f"{stack}: {', '.join(files)}" for stack, files in routed["groups"].items())
            problems.append(f"{label}: touches several stacks ({groups}). Split it into one task per stack.")
        elif routed["stack"] == "unknown":
            no_files.append(f'{label}: lists no files. Add a **Files:** block with "- Create|Modify|Test|Delete: `path`" lines.')
    problems.extend(duplicate_tasks(tasks))
    return {"tasks": len(tasks), "problems": problems, "no_files": no_files}


def manifest_kinds(directory: Path) -> list[tuple[str, str]]:
    """(kind, evidence) for every manifest in one directory."""
    kinds: list[tuple[str, str]] = []
    py_files = [name for name in PY_MANIFESTS if (directory / name).is_file()]
    if py_files:
        text = " ".join((directory / name).read_text(errors="replace").lower() for name in py_files)
        found = [fw for fw in PY_FRAMEWORKS if fw in text]
        kinds.append(("python", ", ".join(found) or py_files[0]))
    composer = directory / "composer.json"
    if composer.is_file():
        require = read_json(composer).get("require")
        keys = set(require) if isinstance(require, dict) else set()
        found = [label for key, label in PHP_FRAMEWORKS.items() if key in keys]
        kinds.append(("php", ", ".join(found) or "composer.json"))
    package_json = directory / "package.json"
    if package_json.is_file():
        deps = js_dependencies(package_json)
        found = [fw for fw in JS_FRAMEWORKS if fw in deps]
        kind = "frontend" if "react" in deps else "node"
        kinds.append((kind, ", ".join(found) or "package.json"))
    return kinds


def layout(root: Path) -> dict:
    lines: list[str] = []
    present: set[str] = set()
    for current, dirs, _ in os.walk(root):
        here = Path(current)
        depth = len(here.relative_to(root).parts)
        dirs[:] = sorted(d for d in dirs if not d.startswith(".") and d not in SKIP_DIRS)
        if depth >= LAYOUT_DEPTH:
            dirs[:] = []
        rel = here.relative_to(root).as_posix()
        for kind, evidence in manifest_kinds(here):
            lines.append(f"{rel}/: {kind} ({evidence})")
            present.add(kind)
    stacks = [s for s in ("python", "frontend", "php") if s in present]
    return {"stacks": stacks, "lines": lines}


def plan_rel(root: Path, plan_path: Path) -> str:
    """Return the plan's POSIX path relative to the repository root."""
    return plan_path.resolve().relative_to(root).as_posix()


def commit_message(rel: str, tasks: list[dict], number: int, open_findings: bool) -> str:
    """Build a task commit message with delivery trailers."""
    task = next((task for task in tasks if task["task"] == number), None)
    if task is None:
        raise ValueError(f"task {number} is not in the plan")
    lines = [
        task["commit"] or f"chore: {task['title']}",
        "",
        f"Delivery-Plan: {rel}",
        f"Delivery-Task: {number}",
        f"Delivery-Task-Title: {task['title']}",
    ]
    if open_findings:
        lines.append("Delivery-Review: accepted-with-open-findings")
    return "\n".join(lines) + "\n"


def scan_delivery_log(log: str, rel: str, titles: dict[int, str]) -> tuple[set[int], list[dict], str | None]:
    """Parse git log's NUL-delimited commit bodies without I/O."""
    done: set[int] = set()
    conflicts = []
    first_commit = None
    entries = log.split("\0")
    for index in range(0, len(entries) - 1, 2):
        sha = entries[index].strip()
        lines = entries[index + 1].split("\n")
        if f"Delivery-Plan: {rel}" not in lines:
            continue
        if first_commit is None:
            first_commit = sha
        committed_title = next(
            (line.removeprefix("Delivery-Task-Title: ") for line in lines
             if line.startswith("Delivery-Task-Title: ")),
            None,
        )
        for line in lines:
            match = re.fullmatch(r"Delivery-Task: ([0-9]+)", line)
            if match is None:
                continue
            number = int(match.group(1))
            if number not in titles:
                continue
            if committed_title == titles[number]:
                done.add(number)
            else:
                conflicts.append({
                    "commit": sha,
                    "task": number,
                    "committed_title": committed_title,
                    "plan_title": titles[number],
                })

    return done, conflicts, first_commit


def delivered(root: Path, rel: str, tasks: list[dict]) -> dict:
    """Find delivered tasks by exact plan and task trailers in git history."""
    log = subprocess.run(
        ["git", "-C", str(root), "log", "--no-show-signature", "--topo-order", "--reverse", "-F",
         f"--grep=Delivery-Plan: {rel}", "--format=%H%x00%B%x00"],
        capture_output=True, text=True,
    )
    if log.returncode != 0:
        raise RuntimeError(log.stderr.strip())

    done, conflicts, first_commit = scan_delivery_log(
        log.stdout, rel, {task["task"]: task["title"] for task in tasks},
    )
    base_ref = f"{first_commit}^" if first_commit is not None else "HEAD"
    base = subprocess.run(
        ["git", "-C", str(root), "rev-parse", base_ref],
        capture_output=True, text=True,
    )
    if base.returncode != 0:
        raise RuntimeError(base.stderr.strip())
    return {"done": sorted(done), "conflicts": conflicts, "base": base.stdout.strip()}


def main(argv: list[str]) -> int:
    if len(argv) < 2 or argv[0] not in {"plan", "check", "files", "layout", "message", "done"}:
        print(__doc__, file=sys.stderr)
        return 2
    command, root = argv[0], Path(argv[1]).resolve()
    if command == "layout":
        print(json.dumps(layout(root)))
        return 0
    if command == "files":
        print(json.dumps(route(root, argv[2:])))
        return 0
    if command == "message":
        valid = len(argv) == 4 or (len(argv) == 5 and argv[4] == "--open-findings")
    else:
        valid = len(argv) == 3
    if not valid:
        print(f"usage: route_task.py {command} <root> <plan.md>"
              + (" <N> [--open-findings]" if command == "message" else ""), file=sys.stderr)
        return 2
    plan_path = Path(argv[2])
    if not plan_path.is_absolute():
        plan_path = root / plan_path
    if not plan_path.is_file():
        print(f"plan not found: {plan_path}", file=sys.stderr)
        return 2
    text = plan_path.read_text()
    if command == "check":
        print(json.dumps(check(root, text)))
        return 0
    tasks = parse_plan(text)
    if not tasks:
        print(f"no '### Task N:' headings in {plan_path}", file=sys.stderr)
        return 2
    duplicates = duplicate_tasks(tasks)
    if duplicates:
        print("\n".join(duplicates), file=sys.stderr)
        return 2
    if command in {"message", "done"}:
        try:
            rel = plan_rel(root, plan_path)
        except ValueError:
            print(f"plan must be inside {root}", file=sys.stderr)
            return 2
        if command == "message":
            try:
                number = int(argv[3])
            except ValueError:
                print(f"invalid task number: {argv[3]}", file=sys.stderr)
                return 2
            try:
                message = commit_message(rel, tasks, number, len(argv) == 5)
            except ValueError:
                print(f"task {number} is not in {plan_path}", file=sys.stderr)
                return 2
            sys.stdout.write(message)
        else:
            try:
                result = delivered(root, rel, tasks)
            except RuntimeError as error:
                print(error, file=sys.stderr)
                return 2
            print(json.dumps(result))
        return 0
    out = []
    for task in tasks:
        routed = route(root, task["paths"])
        out.append({
            "task": task["task"],
            "title": task["title"],
            "commit": task["commit"],
            "block": task["block"],
            "files": routed["files"],
            "stack": routed["stack"],
            "agent": routed["agent"],
            "groups": routed["groups"],
        })
    print(json.dumps(out))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
