"""Behavioral run, assignment, verdict, and bounded-loop contracts.

Run: uv run python -m unittest discover -s plugins/qa/tests -p test_engine_state.py
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

SCRIPTS = Path(__file__).resolve().parents[1] / "skills/engine/scripts"
sys.path.insert(0, str(SCRIPTS))

from qa_engine.models import LIMITS

RESULTS = Path(__file__).parent / "fixtures/results"
BASE = '''version = 1
[env.targets]
backend = "http://localhost:8000"
ui = "http://localhost:5173"
supabase = "http://127.0.0.1:54321"
[qa]
fix = "approve"
'''
PLAN = '''# Test Plan
## FE Test Scenarios
### FE-01: Display items
- **Writes:** no
- **URL:** /items
- **Expected:** Items are displayed. (src/app.py:1)
## BE Test Scenarios
### BE-01: Fetch items
- **Writes:** no
- **Method:** GET /items
- **Request payload:** {"name": "sample-item"}
- **Expected:** 200 items returned. (src/app.py:1)
- **Edge cases:**
  - Missing item: 404. (src/app.py:2)
### BE-02: Health
- **Writes:** no
- **Method:** GET /health
- **Expected:** 200 healthy. (src/app.py:1)
'''


def outcome(status: str = "PASS", observed: int | None = 200, **extra: object) -> dict[str, object]:
    return {"status": status, "observed_status": observed, "crash": False, "kind": None,
            "missing": [], "skip_reason": None, "refutation": None, **extra}


class StateTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        self.env = {**os.environ, "TMPDIR": str(self.root), "XDG_STATE_HOME": str(self.root / "state")}
        self.git("init", "-q")
        self.git("config", "user.name", "QA Tests")
        self.git("config", "user.email", "qa@test.local")
        self.put(".av/local.toml\n", ".git/info/exclude")
        self.put("name = 'original'\n", "src/app.py")
        self.git("add", "src")
        self.git("commit", "-qm", "initial")
        self.put(BASE, ".av/config.toml")
        self.plan = self.put(PLAN, "docs/testing/plans/2026-09-30-state-test-plan.md")
        self.trust()

    def put(self, content: str, name: str) -> Path:
        path = self.repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        return path

    def git(self, *args: str) -> str:
        return subprocess.run(["git", *args], cwd=self.repo, capture_output=True, text=True, check=True).stdout

    def cli(self, *args: str, code: int = 0) -> dict[str, object]:
        result = subprocess.run([sys.executable, str(SCRIPTS / "qa.py"), *args, "--repo", str(self.repo)],
                                env=self.env, capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, code, result.stdout + result.stderr)
        return json.loads(result.stdout)

    def trust(self) -> None:
        config = self.cli("config")
        self.cli("trust", "accept", config["trust_hash"])

    def start(self, **kwargs: object) -> dict[str, object]:
        result = self.cli("run", "start", str(self.plan), **kwargs)
        if kwargs.get("code", 0) == 0:
            self.cli("users", "provision", "--run", result["run"])
        return result

    def sidecar(self, run: dict[str, object]) -> dict[str, object]:
        return json.loads(Path(run["sidecar"]).read_text())

    def change_state(self, run: dict[str, object], **extra: object) -> None:
        Path(run["sidecar"]).write_text(json.dumps({**self.sidecar(run), **extra}))

    def dispatch(self, run: dict[str, object], section: str = "BE", phase: str = "baseline") -> dict[str, object]:
        return self.cli("dispatch", "--run", run["run"], "tester", "--section", section, "--phase", phase)

    def ingest(self, run: dict[str, object], dispatch: dict[str, object], main: dict[str, object] | None = None,
               edge: dict[str, object] | None = None, second: dict[str, object] | None = None,
               *, section: str = "BE", omit_second: bool = False, raw: str | None = None) -> dict[str, object]:
        rows = [{"id": "BE-01", **(main or outcome()), "edges": [{"n": 1, **(edge or outcome(observed=404))}]}]
        if not omit_second:
            rows.append({"id": "BE-02", **(second or outcome()), "edges": []})
        text = raw if raw is not None else "```json qa-results\n" + json.dumps({"section": section, "scenarios": rows}) + "\n```\n"
        file = self.put(text, "result.md")
        return self.cli("ingest", "--run", run["run"], "--dispatch", dispatch["dispatch"], str(file))

    def report(self, run: dict[str, object], qa: str = "QA-001", status: str = "", location: str = "`src/app.py:1`",
               severity: str = "HIGH") -> None:
        Path(run["report"]).write_text(f"### [{severity}] {qa}: Failure\n{status}\n**ID:** {qa}\n"
                                       f"**Scenario:** BE-01\n**Location:** {location}\n**Problem:** Wrong items\n"
                                       "- **Expected:** 200 items returned. (src/app.py:1)\n**Remediation:** Fix items\n")

    def test_run_record_origins_include_store_keys(self) -> None:
        for store, expected in (
            ('kind="sql"\nengine="postgres"\nhost="127.0.0.1"\nport=54322\nuser="u"\nname="app"\npassword="literal:pw"\n', "sql:127.0.0.1:54322/app"),
            ('kind="sql"\nengine="sqlite"\npath="qa.sqlite"\n', f"sql:{self.repo.resolve() / 'qa.sqlite'}"),
            ('kind="redis"\nhost="127.0.0.1"\n', "redis:127.0.0.1:6379/0"),
        ):
            with self.subTest(store=store):
                self.put(BASE + '[env.stores.main]\n' + store, ".av/config.toml")
                self.trust()
                run = self.start()
                record = json.loads((Path(run["dir"]) / "run.json").read_text())
                self.assertIn(expected, record["origins"])
                self.cli("run", "end", "--run", run["run"])

    def test_store_endpoints_are_locked_across_disjoint_targets(self) -> None:
        store = '[env.stores.main]\nkind="sql"\nengine="postgres"\nhost="127.0.0.1"\nport=54322\nuser="u"\nname="app"\npassword="literal:pw"\n'
        self.put('version=1\n[env.targets]\nbackend="http://localhost:8000"\n[qa]\n' + store, ".av/config.toml")
        self.trust()
        holder = self.start()
        second = self.root / "second"
        second.mkdir()
        subprocess.run(["git", "init", "-q", str(second)], check=True)
        subprocess.run(["git", "-C", str(second), "-c", "user.name=QA", "-c", "user.email=qa@test.local", "commit", "--allow-empty", "-qm", "fixture"], check=True)
        config = second / ".av/config.toml"
        config.parent.mkdir()
        config.write_text('version=1\n[env.targets]\nbackend="http://localhost:9000"\n[qa]\n' + store)
        plan = second / "plan.md"
        plan.write_text(PLAN)
        def cli(*args: str) -> dict[str, object]:
            result = subprocess.run([sys.executable, str(SCRIPTS / "qa.py"), *args, "--repo", str(second)], env=self.env, capture_output=True, text=True)
            return json.loads(result.stdout)
        cli("trust", "accept", str(cli("config")["trust_hash"]))
        blocked = cli("run", "start", str(plan))
        self.assertEqual(blocked["holder"]["run"], holder["run"])
        self.assertEqual(blocked["holder"]["origin"], "sql:127.0.0.1:54322/app")
        config.write_text(config.read_text().replace('name="app"', 'name="other"'))
        other = cli("run", "start", str(plan))
        self.assertIn("run", other)
        cli("run", "end", "--run", str(other["run"]))

    def failed(self, *, second_pass: bool = True) -> dict[str, object]:
        run = self.start()
        self.ingest(run, self.dispatch(run), outcome("FAIL", 500), second=outcome() if second_pass else outcome("FAIL", 500))
        self.cli("issues", "--run", run["run"])
        self.report(run, severity="CRITICAL")
        return run

    def test_sidecar_off_schema_stops_instead_of_summarizing(self) -> None:
        run = self.start()
        dispatch = self.dispatch(run)
        self.ingest(run, dispatch)
        original = self.sidecar(run)
        corruptions = {
            "missing dirty baseline": lambda state: state.pop("pre_loop"),
            "misspelled key": lambda state: state.update(dispatchCount=1),
            "boolean dispatch count": lambda state: state.update(dispatch_count=True),
            "invalid assertion status": lambda state: state["assertions"]["BE-01"].update(observed_status="200"),
            "invalid dispatch tag": lambda state: state["dispatches"][dispatch["dispatch"]].update(tag=[1]),
        }
        for name, corrupt in corruptions.items():
            with self.subTest(name=name):
                state = json.loads(json.dumps(original))
                corrupt(state)
                Path(run["sidecar"]).write_text(json.dumps(state))
                stopped = self.cli("summary", "--run", run["run"], code=1)
                self.assertIn("sidecar", stopped["error"])

    def test_run_record_off_schema_stops_instead_of_summarizing(self) -> None:
        run = self.start()
        path = Path(run["dir"]) / "run.json"
        record = json.loads(path.read_text())
        record["sidecar"] = 42
        path.write_text(json.dumps(record))
        stopped = self.cli("summary", "--run", run["run"], code=1)
        self.assertIn("run record", stopped["error"])

    def test_generated_provenance_is_kept_when_reusing_a_plan(self) -> None:
        run = self.cli("run", "start", str(self.plan), "--generated")
        self.assertTrue(self.sidecar(run)["auto_generated"])
        self.cli("run", "end", "--run", run["run"])
        reused = self.start()
        self.assertTrue(self.sidecar(reused)["auto_generated"])
        self.cli("run", "end", "--run", reused["run"])

        Path(reused["sidecar"]).unlink()
        fresh = self.start()
        self.assertFalse(self.sidecar(fresh)["auto_generated"])
        self.cli("run", "end", "--run", fresh["run"])
        existing = self.cli("run", "start", str(self.plan), "--generated")
        self.assertTrue(self.sidecar(existing)["auto_generated"])

    def test_generated_flag_overrides_legacy_report_adoption(self) -> None:
        self.put("# QA Report\n", "docs/testing/reports/2026-09-29-state-report.md")
        run = self.cli("run", "start", str(self.plan), "--generated")
        self.assertEqual(run["idempotency"], "adopt")
        self.assertTrue(self.sidecar(run)["auto_generated"])

    def test_repair_restart_keeps_baseline_after_old_directory_is_deleted(self) -> None:
        self.put(".av/local.toml\n", ".gitignore")
        self.git("add", ".av/config.toml", ".gitignore")
        self.git("commit", "-qm", "configuration")
        self.put("name = 'user edit'\n", "src/app.py")
        run = self.start()
        original = json.loads((Path(run["dir"]) / "run.json").read_text())["pre_loop"]
        self.assertEqual(self.sidecar(run)["pre_loop_dirty"], ["src/app.py"])
        self.cli("run", "end", "--run", run["run"])
        self.assertFalse(Path(run["dir"]).exists())

        self.put(BASE + "\n# repaired service recipe\n", ".av/config.toml")
        self.put(".av/local.toml\n.av/secrets.local.env\n", ".gitignore")
        self.put("name = 'later edit'\n", "src/app.py")
        restarted = self.cli("run", "start", str(self.plan), "--baseline-run", run["run"])
        self.assertEqual(self.sidecar(restarted)["pre_loop_dirty"], ["src/app.py"])
        record = json.loads((Path(restarted["dir"]) / "run.json").read_text())
        self.assertEqual(record["pre_loop"], original)

    def test_initial_baseline_excludes_bootstrap_writes_not_user_config_dirt(self) -> None:
        self.put(".av/local.toml\n", ".gitignore")
        self.git("add", ".av/config.toml", ".gitignore")
        self.git("commit", "-qm", "configuration")
        baseline = self.put(json.dumps(["src/app.py"]), "baseline.json")
        self.put("name = 'user edit'\n", "src/app.py")
        self.put(BASE + "\n# bootstrap addition\n", ".av/config.toml")
        self.put(".av/local.toml\n.av/secrets.local.env\n", ".gitignore")
        run = self.cli("run", "start", str(self.plan), "--baseline-file", str(baseline))
        self.assertEqual(self.sidecar(run)["pre_loop_dirty"], ["src/app.py"])
        self.cli("run", "end", "--run", run["run"])

        baseline.write_text(json.dumps([".av/config.toml", "src/app.py"]))
        run = self.cli("run", "start", str(self.plan), "--baseline-file", str(baseline))
        self.assertEqual(self.sidecar(run)["pre_loop_dirty"], [".av/config.toml", "src/app.py"])

    def test_missing_restart_baseline_fails_without_starting_a_run(self) -> None:
        result = self.cli("run", "start", str(self.plan), "--baseline-run", "deadbeef", code=1)
        self.assertIn("baseline", result["error"])
        self.assertFalse(list(self.root.glob("qa-run-*")))

    def test_private_run_records_and_releases_origin_locks(self) -> None:
        run = self.start()
        directory = Path(run["dir"])
        self.assertEqual(directory.stat().st_mode & 0o777, 0o700)
        record = json.loads((directory / "run.json").read_text())
        self.assertIn("trust_hash", record)
        self.assertNotIn("literal:password", json.dumps(record))
        held = self.start(code=1)
        self.assertIn(run["run"], json.dumps(held))
        self.cli("run", "end", "--run", run["run"])
        self.assertFalse(directory.exists())
        self.assertEqual(self.start()["idempotency"], "reuse")

    def test_ipv6_origin_locks_use_bracketed_canonical_origins(self) -> None:
        config = BASE.replace("localhost:8000", "[::1]:8000")
        config = config.replace('ui = "http://localhost:5173"\n', "").replace('supabase = "http://127.0.0.1:54321"\n', "")
        self.put(config, ".av/config.toml")
        self.trust()
        run = self.start()
        conflict = self.start(code=1)
        self.assertEqual(conflict["holder"]["origin"], "http://[::1]:8000")
        self.assertEqual(conflict["holder"]["run"], run["run"])
        released = self.cli("run", "end", "--run", run["run"])["released"]
        self.assertIn("http://[::1]:8000", released)

    def test_shared_origins_exclude_and_disjoint_origins_succeed(self) -> None:
        run = self.start()
        self.put(BASE.replace('ui = "http://localhost:5173"\n', ''), ".av/config.toml")
        self.assertIn("live run", self.start(code=1)["error"])
        self.put(BASE.replace(":8000", ":9000").replace(":5173", ":9173").replace(":54321", ":54322"), ".av/config.toml")
        self.trust()
        other = self.start()
        self.assertNotEqual(run["run"], other["run"])

    def test_partial_acquisition_leaves_no_lock(self) -> None:
        # The free Supabase origin sorts first, so the conflict happens after one acquisition.
        self.put(BASE.replace(":54321", ":54322"), ".av/config.toml")
        self.trust()
        holder = self.start()
        self.put(BASE, ".av/config.toml")
        self.trust()
        self.start(code=1)
        locks = list((self.root / "state/av-marketplace/qa-locks").glob("*.json"))
        self.assertEqual({json.loads(file.read_text())["run_id"] for file in locks}, {holder["run"]})

    def test_failed_adoption_releases_locks_and_removes_run_directory(self) -> None:
        report = self.put("", "docs/testing/reports/2026-09-30-state-report.md")
        report.write_bytes(b"\xff")
        self.assertEqual(self.start(code=1)["error"], "engine I/O operation failed")
        self.assertEqual(list((self.root / "state/av-marketplace/qa-locks").glob("*.json")), [])
        self.assertEqual(list(self.root.glob("qa-run-*")), [])

        report.write_text("# QA Report\n")
        self.assertEqual(self.start()["idempotency"], "adopt")

    def test_takeover_deletes_holder_directory(self) -> None:
        holder = self.start()
        self.cli("run", "start", str(self.plan), "--takeover", "deadbeef", code=1)
        replacement = self.cli("run", "start", str(self.plan), "--takeover", holder["run"])
        self.assertFalse(Path(holder["dir"]).exists())
        self.assertNotEqual(holder["run"], replacement["run"])

    def test_lock_age_and_stale_repository_cleanup(self) -> None:
        holder = self.start()
        for lock in (self.root / "state/av-marketplace/qa-locks").glob("*.json"):
            data = json.loads(lock.read_text())
            data["started"] = time.time() - 3 * 86400
            lock.write_text(json.dumps(data))
        directory = Path(holder["dir"])
        record = json.loads((directory / "run.json").read_text())
        record["started"] = time.time() - 3 * 86400
        (directory / "run.json").write_text(json.dumps(record))
        self.start()
        self.assertFalse(directory.exists())

    def test_drift_checks_all_effective_targets(self) -> None:
        run = self.start()
        self.put(BASE.replace(":8000", ":8001"), ".av/config.toml")
        result = self.cli("dispatch", "--run", run["run"], "tester", "--section", "BE", "--phase", "baseline", code=1)
        self.assertEqual(result["error"], "config changed during run")
        self.cli("run", "end", "--run", run["run"])

    def test_unknown_environment_datetime_does_not_affect_start_or_drift(self) -> None:
        extra = '[env.extra]\nwhen = 2026-01-01T00:00:00Z\n'
        self.put(BASE + extra, ".av/config.toml")
        config = self.cli("config")
        self.assertEqual(config["state"], "ok")
        self.assertEqual(config["trust"], "trusted")
        run = self.start()
        self.put(BASE + extra.replace("2026-01-01", "2026-02-01"), ".av/config.toml")
        self.assertEqual(self.dispatch(run)["scenarios"], ["BE-01", "BE-02"])

    def test_start_requires_retrust_after_sensitive_edit(self) -> None:
        self.put(BASE.replace('fix = "approve"', 'fix = "auto"'), ".av/config.toml")
        self.assertEqual(self.start(code=1)["error"], "trust required")

    def test_idempotency_reuse_adopt_and_rebaseline_archive(self) -> None:
        run = self.failed()
        self.cli("run", "end", "--run", run["run"])
        reused = self.start()
        self.assertEqual(reused["idempotency"], "reuse")
        self.assertEqual(self.sidecar(reused)["issue_assertion"], {"QA-001": "BE-01"})
        self.cli("run", "end", "--run", reused["run"])
        Path(reused["sidecar"]).unlink()
        adopted = self.start()
        self.assertEqual(adopted["idempotency"], "adopt")
        self.assertEqual(self.sidecar(adopted)["issue_assertion"], {"QA-001": "BE-01"})
        self.cli("run", "end", "--run", adopted["run"])
        self.plan.write_text(PLAN + "\nNew notes\n")
        rebaseline = self.start()
        self.assertEqual(rebaseline["idempotency"], "rebaseline")
        self.assertTrue(Path(rebaseline["sidecar"]).with_suffix(".bak").exists())
        self.assertTrue(Path(rebaseline["report"]).with_suffix(".bak").exists())
        self.assertEqual(self.sidecar(rebaseline)["scenario_issues"], {})

    def test_missing_assigned_scenario_cannot_retain_previous_pass(self) -> None:
        run = self.start()
        self.ingest(run, self.dispatch(run))
        result = self.ingest(run, self.dispatch(run, phase="retry"), omit_second=True)
        self.assertEqual(result["verdicts"]["BE-02"], "skip")
        self.assertEqual(self.sidecar(run)["scenario_reason"]["BE-02"], "cannot-confirm")
        self.assertIn("BE-02", result["incomplete"])

    def test_invalid_blocks_fail_closed_without_human_prose(self) -> None:
        for raw, section in [(None, "FE"), ("Human: PASS", "BE"), ("```json qa-results\n{}\n```", "BE")]:
            with self.subTest(raw=raw, section=section):
                run = self.start()
                result = self.ingest(run, self.dispatch(run), raw=raw, section=section)
                self.assertEqual(set(result["verdicts"].values()), {"skip"})
                self.assertIn("error", result)
                self.assertEqual(set(self.sidecar(run)["scenario_reason"].values()), {"cannot-confirm"})
                self.cli("run", "end", "--run", run["run"])

    def test_missing_and_duplicate_edges_never_credit_pass(self) -> None:
        for edges in [[], [{"n": 1, **outcome()}, {"n": 1, **outcome()}]]:
            with self.subTest(edges=edges):
                run = self.start()
                raw = "```json qa-results\n" + json.dumps({"section": "BE", "scenarios": [
                    {"id": "BE-01", **outcome(), "edges": edges}, {"id": "BE-02", **outcome(), "edges": []}]}) + "\n```"
                result = self.ingest(run, self.dispatch(run), raw=raw)
                self.assertEqual(result["verdicts"]["BE-01"], "skip")
                self.cli("run", "end", "--run", run["run"])

    def test_guarded_post_pass_is_skipped_without_minting_issues(self) -> None:
        self.put(BASE.replace('fix = "approve"', 'fix = "approve"\nmutations = "deny"'), ".av/config.toml")
        self.plan.write_text(PLAN.replace("GET /items", "POST /items"))
        self.trust()
        self.assertEqual(self.cli("plan", "check", str(self.plan))["guarded"], ["BE-01"])
        run = self.start()
        dispatch = self.dispatch(run)
        self.assertEqual(dispatch["guarded"], ["BE-01"])
        self.assertEqual(self.ingest(run, dispatch)["verdicts"]["BE-01"], "skip")
        self.assertEqual(self.sidecar(run)["scenario_reason"]["BE-01"], "mutation-guard")
        self.assertEqual(self.cli("issues", "--run", run["run"]), {"assign": [], "open": []})

    def test_skip_reasons_are_normalized_for_tool_and_transport(self) -> None:
        cases = [("no psql client available", "tool-unavailable"), ("connection refused", "transport")]
        for skip_reason, reason in cases:
            with self.subTest(skip_reason=skip_reason):
                run = self.start()
                result = self.ingest(run, self.dispatch(run), outcome("SKIP", None, skip_reason=skip_reason))
                self.assertEqual(result["verdicts"]["BE-01"], "skip")
                self.assertEqual(self.sidecar(run)["scenario_reason"]["BE-01"], reason)
                self.cli("run", "end", "--run", run["run"])

    def test_all_verdict_precedence_rules(self) -> None:
        cases = [(outcome("FAIL", 500), outcome("NEED_INFO", kind="tool", missing=["jq"]), "fail"),
                 (outcome("FAIL", 401), outcome("FAIL", 500), "fail"),
                 (outcome("PASS"), outcome("NEED_INFO", kind="fixture", missing=["upload"]), "need-info"),
                 (outcome("FAIL", 401), outcome("NEED_INFO", kind="tool", missing=["jq"]), "fail"),
                 (outcome("FAIL", 401), outcome("SKIP"), "fail"),
                 (outcome("PASS"), outcome("SKIP", skip_reason="harness error: failed"), "skip"),
                 (outcome("PASS"), outcome("PASS"), "pass")]
        for main, edge, verdict in cases:
            with self.subTest(verdict=verdict, main=main, edge=edge):
                run = self.start()
                result = self.ingest(run, self.dispatch(run), main, edge)
                self.assertEqual(result["verdicts"]["BE-01"], verdict)
                self.cli("run", "end", "--run", run["run"])

    def test_need_info_rebuild_preserves_other_sections(self) -> None:
        run = self.start()
        frontend = self.dispatch(run, "FE")
        text = "```json qa-results\n" + json.dumps({"section": "FE", "scenarios": [{"id": "FE-01",
                **outcome("NEED_INFO", None, kind="tool", missing=["browser"]), "edges": []}]}) + "\n```"
        self.ingest(run, frontend, raw=text)
        self.ingest(run, self.dispatch(run), edge=outcome("NEED_INFO", kind="fixture", missing=["upload"]))
        self.assertIn("BE-01 (edge 1)", self.sidecar(run)["need_info"])
        self.ingest(run, self.dispatch(run, phase="retry"))
        self.assertEqual(self.sidecar(run)["need_info"], {"FE-01": {"kind": "tool", "missing": ["browser"]}})
        self.assertEqual(self.sidecar(run)["scenario_kind"], {"FE-01": "feature", "BE-01": "feature", "BE-02": "sanity"})

    def test_auth_failure_is_a_flagged_fail_never_auto_fixed(self) -> None:
        for mode in ("approve", "auto"):
            with self.subTest(mode=mode):
                self.put(BASE.replace('fix = "approve"', f'fix = "{mode}"'), ".av/config.toml")
                self.trust()
                run = self.start()
                dispatch = self.dispatch(run)
                self.assertRegex(dispatch["tag"], r"^[0-9a-f]{8}$")
                self.assertNotIn("refreshed", dispatch)
                self.assertEqual(self.ingest(run, dispatch, outcome("FAIL", 401))["verdicts"]["BE-01"], "fail")
                self.assertTrue(self.sidecar(run)["assertions"]["BE-01"]["auth"])
                self.cli("issues", "--run", run["run"])
                self.report(run)
                chosen = self.cli("candidates", "--run", run["run"])
                if mode == "approve":
                    self.assertEqual(chosen["fix"][0]["flags"], ["auth"])
                else:
                    self.assertIn({"qa": "QA-001", "reason": "auth"}, chosen["dropped"])
                self.cli("run", "end", "--run", run["run"])

    def test_later_main_failure_gets_new_id_after_edge_and_history_union(self) -> None:
        run = self.start()
        self.ingest(run, self.dispatch(run), edge=outcome("FAIL", 500))
        first = self.cli("issues", "--run", run["run"])
        self.assertEqual(first["assign"][0]["key"], "BE-01 (edge 1)")
        Path(run["report"]).write_text("## Loop History\n| 1 | QA-010 |\n")
        self.ingest(run, self.dispatch(run, phase="retry"), outcome("FAIL", 500))
        assigned = self.cli("issues", "--run", run["run"])["assign"]
        self.assertEqual(assigned[0]["qa"], "QA-011")
        self.assertEqual(self.sidecar(run)["issue_assertion"], {"QA-001": "BE-01 (edge 1)", "QA-011": "BE-01"})

    def test_rejected_issue_and_repaired_location_candidate_filters(self) -> None:
        run = self.failed()
        self.report(run, status="**Status:** 🚫 Rejected — intentional", severity="CRITICAL")
        self.assertEqual(self.cli("candidates", "--run", run["run"])["fix"], [])
        self.report(run, location="`src/app.py:1` (was: unknown:0)", severity="CRITICAL")
        self.assertEqual(self.cli("candidates", "--run", run["run"])["fix"][0]["qa"], "QA-001")

    def test_unverified_and_mechanical_severity(self) -> None:
        self.plan.write_text(PLAN.replace("200 items returned. (src/app.py:1)", "200 items returned. (unverified — confirm at run time)"))
        run = self.start()
        self.ingest(run, self.dispatch(run), outcome("FAIL", 400), outcome("FAIL", 500))
        assigned = self.cli("issues", "--run", run["run"])["assign"]
        self.assertEqual([(row["unverified"], row["severity_floor"]) for row in assigned], [(True, "LOW"), (False, "CRITICAL")])
        self.assertEqual(self.sidecar(run)["unverified_issues"], ["QA-001"])

    def test_iteration_open_increments_only_on_iterate(self) -> None:
        run = self.start()
        self.ingest(run, self.dispatch(run))
        self.assertEqual(self.cli("iteration", "open", "--run", run["run"])["decision"], "final")
        self.assertEqual(self.sidecar(run)["iteration"], 0)
        self.plan.write_text(PLAN + "\nchanged\n")
        self.assertEqual(self.cli("iteration", "open", "--run", run["run"])["decision"], "stop")
        self.assertEqual(self.sidecar(run)["iteration"], 0)

    def test_no_progress_and_single_history_row(self) -> None:
        run = self.failed()
        opened = self.cli("iteration", "open", "--run", run["run"])
        self.assertEqual(opened["decision"], "iterate")
        self.assertEqual(self.cli("iteration", "open", "--run", run["run"])["iteration"], 1)
        self.ingest(run, self.dispatch(run, phase="iteration"), outcome("FAIL", 500))
        closed = self.cli("iteration", "close", "--run", run["run"])
        self.assertEqual(closed["decision"], "final")
        self.assertIn("no progress", closed["reason"])
        self.assertEqual(self.cli("iteration", "close", "--run", run["run"]), closed)
        self.assertEqual(len(self.sidecar(run)["iterations"]), 1)
        self.assertEqual(self.cli("iteration", "open", "--run", run["run"])["decision"], "final")

    def test_regression_stops_loop(self) -> None:
        run = self.failed()
        self.cli("iteration", "open", "--run", run["run"])
        self.ingest(run, self.dispatch(run, phase="iteration"), second=outcome("FAIL", 500))
        closed = self.cli("iteration", "close", "--run", run["run"])
        self.assertEqual(closed["decision"], "final")
        self.assertIn("regression", closed["reason"])
        self.assertEqual(closed["regressions"], ["BE-02"])

    def test_fix_done_warns_and_records_attempt_without_grading_verdict(self) -> None:
        run = self.failed()
        self.cli("iteration", "open", "--run", run["run"])
        dispatch = self.cli("dispatch", "--run", run["run"], "fix", "--qa", "QA-001")
        self.put("name = 'sample-item'\n", "src/app.py")
        warning = self.cli("fix", "done", "--run", run["run"], "--dispatch", dispatch["dispatch"], "--result", "fixed")
        self.assertIn("Possible hardcoding", warning["warnings"][0])
        self.assertEqual(self.sidecar(run)["current"]["BE-01"], "fail")
        self.ingest(run, self.dispatch(run, phase="iteration"))
        closed = self.cli("iteration", "close", "--run", run["run"])
        self.assertEqual(closed["fix_touched_files"], ["src/app.py"])
        history = self.sidecar(run)["iterations"][0]
        self.assertEqual(history["attempted_fixes"], ["QA-001"])
        self.assertTrue(history["warnings"])

    def test_dispatch_budget_does_not_gate_final_run(self) -> None:
        run = self.failed()
        self.change_state(run, dispatch_count=LIMITS["dispatches"])
        self.assertEqual(self.cli("iteration", "open", "--run", run["run"])["reason"], "dispatch budget exhausted")
        self.cli("dispatch", "--run", run["run"], "tester", "--section", "BE", "--phase", "iteration", code=1)
        self.assertEqual(self.dispatch(run, phase="final")["dispatch_count"], LIMITS["dispatches"] + 1)

    def test_recorded_tester_answers_ingest(self) -> None:
        run = self.start()
        for section, file in [("BE", "be-baseline.md"), ("FE", "fe-baseline.md")]:
            dispatch = self.dispatch(run, section)
            result = self.ingest(run, dispatch, raw=(RESULTS / file).read_text())
            self.assertTrue(all(verdict == "pass" for verdict in result["verdicts"].values()))


if __name__ == "__main__":
    unittest.main()
