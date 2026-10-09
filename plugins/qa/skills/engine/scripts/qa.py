#!/usr/bin/env python3
"""Stdlib-only JSON command interface for the QA engine."""
from __future__ import annotations

import argparse
from collections.abc import Callable
from collections.abc import Mapping
from collections.abc import Sequence
import json
from pathlib import Path
import shutil
import subprocess
import sys
from typing import NoReturn

# Check before importing tomllib or any engine module, so older interpreters
# receive the actionable version error rather than an import traceback.
if sys.version_info < (3, 11):
    print(json.dumps({"error": f"Error: the qa engine needs Python 3.11 or newer (found {sys.version_info.major}.{sys.version_info.minor})"}))
    raise SystemExit(2)

from av_config.errors import ConfigError
from av_config.errors import InvalidConfig
from qa_engine.config import Config
from qa_engine.users import provision
from qa_engine.users import record_account_cli
from qa_engine.users import teardown
from qa_engine.services import services
from qa_engine.plan import check_plan
from qa_engine.plan import parse_plan
from qa_engine.plan import resolve_plan
from qa_engine.report import refresh_accounts
from qa_engine.report import render_report
from qa_engine.report import render_summary
from qa_engine.runs import STOP_REASONS
from qa_engine.runs import RunStartOptions
from qa_engine.models import Run
from qa_engine.models import StateStop
from qa_engine.issues import assign_issues
from qa_engine.candidates import candidates
from qa_engine.runs import check_drift
from qa_engine.dispatch import dispatch_fix
from qa_engine.dispatch import dispatch_tester
from qa_engine.runs import end_run
from qa_engine.dispatch import fix_done
from qa_engine.results import ingest
from qa_engine.iterations import iteration_close
from qa_engine.iterations import iteration_open
from qa_engine.runs import open_run
from qa_engine.runs import start_run
from qa_engine.runs import stop_run

CommandResult = Mapping[str, object] | str


class UsageError(ConfigError):
    """Invalid command syntax, with no user-provided value echoed."""


class Parser(argparse.ArgumentParser):
    def error(self, message: str) -> NoReturn:
        raise UsageError("invalid command arguments; use --help")

    def format_help(self) -> str:
        return json.dumps({"help": super().format_help()}) + "\n"


def repo_option(parser: argparse.ArgumentParser) -> argparse.ArgumentParser:
    parser.add_argument("--repo", type=Path, default=argparse.SUPPRESS)
    return parser


def run_option(parser: argparse.ArgumentParser) -> argparse.ArgumentParser:
    parser.add_argument("--run", required=True)
    return repo_option(parser)


def parser() -> argparse.ArgumentParser:
    root = repo_option(Parser(description="QA engine (JSON output)"))
    root.set_defaults(repo=None, close_iteration=False)
    commands = root.add_subparsers(dest="command", required=True)
    config = repo_option(commands.add_parser("config"))
    config.set_defaults(handler=_execute_config)
    operations = config.add_subparsers(dest="operation")
    preview = repo_option(operations.add_parser("preview"))
    preview.set_defaults(handler=_execute_preview)
    preview.add_argument("proposal", type=Path)
    apply = repo_option(operations.add_parser("apply"))
    apply.set_defaults(handler=_execute_apply)
    apply.add_argument("proposal", type=Path)
    apply.add_argument("--snapshot", required=True)
    apply.add_argument("--approved-hash", required=True)
    trust = repo_option(commands.add_parser("trust"))
    trust_operations = trust.add_subparsers(dest="operation", required=True)
    accept = repo_option(trust_operations.add_parser("accept"))
    accept.set_defaults(handler=_execute_trust)
    accept.add_argument("hash")
    repo_option(commands.add_parser("tools")).set_defaults(handler=_execute_tools)
    plan = repo_option(commands.add_parser("plan"))
    plan_operations = plan.add_subparsers(dest="operation", required=True)
    resolve = repo_option(plan_operations.add_parser("resolve"))
    resolve.set_defaults(handler=_execute_plan_resolve)
    resolve.add_argument("argument", nargs="?", default="")
    check = repo_option(plan_operations.add_parser("check"))
    check.set_defaults(handler=_execute_plan_check)
    check.add_argument("plan", type=Path)
    run = repo_option(commands.add_parser("run"))
    run_operations = run.add_subparsers(dest="operation", required=True)
    start = repo_option(run_operations.add_parser("start"))
    start.set_defaults(handler=_execute_run_start)
    start.add_argument("plan", type=Path)
    start.add_argument("--takeover")
    start.add_argument("--generated", action="store_true")
    baseline = start.add_mutually_exclusive_group()
    baseline.add_argument("--baseline-run")
    baseline.add_argument("--baseline-file", type=Path)
    run_option(run_operations.add_parser("end")).set_defaults(handler=_execute_run_end)
    stop = run_option(run_operations.add_parser("stop"))
    stop.set_defaults(handler=run_state, state_handler=_state_stop, close_iteration=True)
    stop.add_argument("--reason", required=True, choices=sorted(STOP_REASONS))
    stop.add_argument("--detail")
    dispatch = run_option(commands.add_parser("dispatch"))
    dispatch.set_defaults(handler=run_state)
    dispatch_operations = dispatch.add_subparsers(dest="operation", required=True)
    tester = repo_option(dispatch_operations.add_parser("tester"))
    tester.set_defaults(state_handler=_state_dispatch_tester)
    tester.add_argument("--section", required=True, choices=["FE", "BE"])
    tester.add_argument("--phase", required=True, choices=["baseline", "retry", "iteration", "final"])
    dispatch_fix_parser = repo_option(dispatch_operations.add_parser("fix"))
    dispatch_fix_parser.set_defaults(state_handler=_state_dispatch_fix)
    dispatch_fix_parser.add_argument("--qa", required=True)
    fix = repo_option(commands.add_parser("fix"))
    done = run_option(fix.add_subparsers(dest="operation", required=True).add_parser("done"))
    done.set_defaults(handler=run_state, state_handler=_state_fix_done)
    done.add_argument("--dispatch", required=True)
    done.add_argument("--result", required=True, choices=["fixed", "partial", "failed"])
    results = run_option(commands.add_parser("ingest"))
    results.set_defaults(handler=run_state, state_handler=_state_ingest)
    results.add_argument("--dispatch", required=True)
    results.add_argument("file", type=Path)
    run_option(commands.add_parser("issues")).set_defaults(handler=run_state, state_handler=_state_issues)
    run_option(commands.add_parser("candidates")).set_defaults(handler=run_state, state_handler=_state_candidates)
    iteration = repo_option(commands.add_parser("iteration"))
    iteration.set_defaults(handler=run_state)
    iteration_operations = iteration.add_subparsers(dest="operation", required=True)
    run_option(iteration_operations.add_parser("open")).set_defaults(state_handler=_state_iteration_open)
    run_option(iteration_operations.add_parser("close")).set_defaults(state_handler=_state_iteration_close)
    users = repo_option(commands.add_parser("users"))
    users.set_defaults(handler=run_state)
    user_operations = users.add_subparsers(dest="operation", required=True)
    for operation, handler in (("provision", _state_provision), ("teardown", _state_teardown)):
        run_option(user_operations.add_parser(operation)).set_defaults(state_handler=handler)
    record = run_option(user_operations.add_parser("record"))
    record.set_defaults(state_handler=_state_record)
    record.add_argument("--dispatch", required=True)
    record.add_argument("--email", required=True)
    record.add_argument("--id")
    service = repo_option(commands.add_parser("services"))
    service.set_defaults(handler=run_state, state_handler=_state_services)
    service_operations = service.add_subparsers(dest="operation", required=True)
    for operation in ("check", "up", "prepare", "down"):
        run_option(service_operations.add_parser(operation))
    report = run_option(commands.add_parser("report"))
    report.set_defaults(handler=run_state, state_handler=_state_report)
    report_input = report.add_mutually_exclusive_group(required=True)
    report_input.add_argument("--issues", type=Path)
    report_input.add_argument("--accounts", action="store_true")
    report.add_argument("--final", action="store_true")
    run_option(commands.add_parser("summary")).set_defaults(handler=run_state, state_handler=_state_summary, close_iteration=True)
    return root


def repository(explicit: Path | None) -> Path:
    if explicit is not None:
        if not explicit.is_dir():
            raise UsageError("repository root is not a directory")
        return explicit.resolve()
    result = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=False)
    if result.returncode:
        raise UsageError("repository root unavailable; supply --repo")
    return Path(result.stdout.strip()).resolve()


def tools() -> dict[str, object]:
    result: dict[str, object] = {name: shutil.which(name) is not None for name in ("curl", "jq", "psql", "mysql", "sqlite3")}
    result["redis_cli"] = shutil.which("redis-cli") is not None
    perl = shutil.which("perl")
    result["perl_json_pp"] = perl is not None and subprocess.run([perl, "-MJSON::PP", "-e", "1"], capture_output=True, check=False).returncode == 0
    result["httpie"] = shutil.which("http") is not None
    return result


def read_proposal(path: Path) -> dict[str, object]:
    try:
        value = json.loads(path.read_text())
    except (OSError, UnicodeError, ValueError) as error:
        raise UsageError("proposal: unreadable or invalid JSON") from error
    if not isinstance(value, dict):
        raise UsageError("proposal: expected a JSON object")
    return value


def run_state(repo: Path, args: argparse.Namespace) -> tuple[CommandResult, int]:
    """Run the parser-selected bookkeeping handler under the run's state lock."""
    handler: Callable[[Run, argparse.Namespace], CommandResult] = args.state_handler
    with open_run(repo, args.run, close_iteration=args.close_iteration or getattr(args, "final", False)) as run:
        return handler(run, args), 0


def _state_report(run: Run, args: argparse.Namespace) -> Mapping[str, object]:
    if args.accounts:
        if args.final:
            raise UsageError("--accounts cannot be combined with --final")
        return refresh_accounts(run)
    path = args.issues if args.issues.is_absolute() else run.repo / args.issues
    return render_report(run, path, final=args.final)


def _state_summary(run: Run, args: argparse.Namespace) -> str:
    return render_summary(run)


def _state_provision(run: Run, args: argparse.Namespace) -> Mapping[str, object]:
    config = Config(run.repo)
    check_drift(run, config)
    return provision(run, config)


def _state_record(run: Run, args: argparse.Namespace) -> Mapping[str, object]:
    return record_account_cli(run, Config(run.repo), args.dispatch, args.email, args.id)


def _state_teardown(run: Run, args: argparse.Namespace) -> Mapping[str, object]:
    return teardown(run, Config(run.repo))


def _state_services(run: Run, args: argparse.Namespace) -> Mapping[str, object]:
    config = Config(run.repo)
    if args.operation != "down":
        check_drift(run, config)
    return services(run, config, args.operation)


def _state_dispatch_tester(run: Run, args: argparse.Namespace) -> Mapping[str, object]:
    return dispatch_tester(run, Config(run.repo), args.section, args.phase)


def _state_dispatch_fix(run: Run, args: argparse.Namespace) -> Mapping[str, object]:
    return dispatch_fix(run, Config(run.repo), args.qa)


def _state_fix_done(run: Run, args: argparse.Namespace) -> Mapping[str, object]:
    return fix_done(run, args.dispatch, args.result)


def _state_ingest(run: Run, args: argparse.Namespace) -> Mapping[str, object]:
    path = args.file if args.file.is_absolute() else run.repo / args.file
    return ingest(run, args.dispatch, path.read_text())


def _state_issues(run: Run, args: argparse.Namespace) -> Mapping[str, object]:
    return assign_issues(run)


def _state_candidates(run: Run, args: argparse.Namespace) -> Mapping[str, object]:
    return candidates(run)


def _state_iteration_open(run: Run, args: argparse.Namespace) -> Mapping[str, object]:
    return iteration_open(run)


def _state_iteration_close(run: Run, args: argparse.Namespace) -> Mapping[str, object]:
    return iteration_close(run)


def _state_stop(run: Run, args: argparse.Namespace) -> Mapping[str, object]:
    return stop_run(run, args.reason, args.detail)


def _execute_run_start(repo: Path, args: argparse.Namespace) -> tuple[Mapping[str, object], int]:
    path = args.plan if args.plan.is_absolute() else repo / args.plan
    baseline = args.baseline_file
    if baseline is not None and not baseline.is_absolute():
        baseline = repo / baseline
    options = RunStartOptions(
        takeover=args.takeover, generated=args.generated, baseline_run=args.baseline_run, baseline_file=baseline,
    )
    return start_run(Config(repo), path, options), 0


def _execute_run_end(repo: Path, args: argparse.Namespace) -> tuple[Mapping[str, object], int]:
    return end_run(repo, args.run), 0


def _execute_plan_resolve(repo: Path, args: argparse.Namespace) -> tuple[dict[str, object], int]:
    return resolve_plan(repo, args.argument), 0


def _execute_plan_check(repo: Path, args: argparse.Namespace) -> tuple[dict[str, object], int]:
    config = Config(repo)
    if config.errors:
        return config.report(), 2
    path = args.plan if args.plan.is_absolute() else repo / args.plan
    result = check_plan(parse_plan(path), config)
    return result, 0 if result["ok"] else 1


def _execute_config(repo: Path, args: argparse.Namespace) -> tuple[dict[str, object], int]:
    config = Config(repo)
    return config.report(), 2 if config.errors else 0


def _execute_preview(repo: Path, args: argparse.Namespace) -> tuple[dict[str, object], int]:
    result = Config(repo).preview(read_proposal(args.proposal))
    return result, 0 if result["ok"] else 2


def _execute_apply(repo: Path, args: argparse.Namespace) -> tuple[dict[str, object], int]:
    return Config(repo).apply(read_proposal(args.proposal), args.snapshot, args.approved_hash), 0


def _execute_trust(repo: Path, args: argparse.Namespace) -> tuple[dict[str, object], int]:
    return Config(repo).accept(args.hash), 0


def _execute_tools(repo: Path, args: argparse.Namespace) -> tuple[dict[str, object], int]:
    return tools(), 0


def execute(args: argparse.Namespace) -> tuple[CommandResult, int]:
    handler: Callable[[Path, argparse.Namespace], tuple[CommandResult, int]] = args.handler
    return handler(repository(args.repo), args)


def main(argv: Sequence[str] | None = None) -> int:
    try:
        args = parser().parse_args(argv)
        result, code = execute(args)
    except (UsageError, InvalidConfig) as error:
        result, code = {"error": str(error)}, 2
    except StateStop as error:
        result, code = {"error": str(error), **error.details}, 1
    except ConfigError as error:
        result, code = {"error": str(error)}, 1
    except (OSError, UnicodeError):
        # File/process errors may contain paths or values in their details.
        result, code = {"error": "engine I/O operation failed"}, 1
    if isinstance(result, str):
        print(result, end="" if result.endswith("\n") else "\n")
    else:
        print(json.dumps(result, sort_keys=True))
    return code


if __name__ == "__main__":
    raise SystemExit(main())
