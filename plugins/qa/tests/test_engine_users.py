"""Process-bound user channel, registration ledger and cleanup contracts."""
from __future__ import annotations

from http.server import BaseHTTPRequestHandler
from http.server import ThreadingHTTPServer
import json
import os
from pathlib import Path
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
from threading import Thread
import unittest
from urllib.parse import parse_qs
from urllib.parse import urlsplit
from urllib.request import Request

SCRIPTS = Path(__file__).resolve().parents[1] / "skills/engine/scripts"
sys.path.insert(0, str(SCRIPTS))

from av_config.errors import ConfigError
from qa_engine.recipes import http_request

PLAN = '''# Test Plan
## Users
- admin: existing — administrator
- owner: registered — plain user
## BE Test Scenarios
### BE-01: Request
- **Writes:** yes
- **Preconditions:** Register qa+$QA_TAG-owner@test.local with $QA_NEW_PASSWORD; login with $QA_ADMIN_EMAIL and $QA_ADMIN_PASSWORD.
- **Method:** GET /items
- **Expected:** 200 returned. (src/app.py:1)
'''
USER = '''[qa.users.admin]
email = "literal:admin@test.local"
password = "env:QA_ADMIN_SECRET"
id = "literal:admin-1"
description = "administrator"
'''
CLEANUP = '''[qa.cleanup]
kind = "http"
target = "backend"
method = "DELETE"
path = "/users/{email}"
headers = { apikey = "{secret.ADMIN}" }
expect = [200, 404]
'''


class AccountServer(ThreadingHTTPServer):
    events: list[tuple[str, dict[str, object]]]
    mode: str
    health_status: int

    def __init__(self) -> None:
        super().__init__(("127.0.0.1", 0), AccountHandler)
        self.events = []
        self.mode = "ok"
        self.health_status = 200


class AccountHandler(BaseHTTPRequestHandler):
    server: AccountServer

    def log_message(self, format: str, *args: object) -> None:
        return

    def do_GET(self) -> None:
        self.reply(self.server.health_status, {})

    def do_DELETE(self) -> None:
        self.server.events.append((self.path, {name.lower(): value for name, value in self.headers.items()}))
        if self.server.mode == "unavailable":
            self.close_connection = True
        elif self.server.mode == "redirect":
            self.reply(302, {}, location="/other")
        elif self.server.mode == "500":
            self.reply(500, {})
        elif self.server.mode == "missing":
            self.reply(404, {})
        else:
            self.reply(200 if self.headers.get("apikey") == "admin-secret" else 403, {})

    def reply(self, status: int, payload: object, *, location: str | None = None) -> None:
        self.send_response(status)
        if location:
            self.send_header("Location", location)
        self.end_headers()
        self.wfile.write(json.dumps(payload).encode())


class UserTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        self.env = {**os.environ, "TMPDIR": str(self.root), "XDG_STATE_HOME": str(self.root / "state"),
                    "AV_ADMIN": "admin-secret", "QA_ADMIN_SECRET": "private-password"}
        subprocess.run(["git", "init", "-q", str(self.repo)], check=True)
        subprocess.run(["git", "-c", "user.name=QA", "-c", "user.email=qa@test.local", "commit", "--allow-empty", "-qm", "fixture"], cwd=self.repo, check=True)
        self.put(".av/local.toml\n", ".git/info/exclude")
        self.server = self.new_server()
        self.origin = f"http://127.0.0.1:{self.server.server_port}"
        self.base = f'''version = 1
[env.targets]
backend = "{self.origin}"
ui = "http://localhost:5173"
[env.secrets]
ADMIN = "env:AV_ADMIN"
[qa]
fix = "approve"
mutations = "allow"
'''
        self.config = self.base + USER + CLEANUP
        self.put(self.config, ".av/config.toml")
        self.plan = self.put(PLAN, "docs/testing/plans/users-plan.md")
        self.trust()

    def new_server(self) -> AccountServer:
        server = AccountServer()
        Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        return server

    def put(self, text: str, name: str) -> Path:
        path = self.repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def cli(self, *args: str, code: int = 0) -> dict[str, object]:
        process = subprocess.run([sys.executable, str(SCRIPTS / "qa.py"), *args, "--repo", str(self.repo)],
                                 env=self.env, capture_output=True, text=True, check=False)
        self.assertEqual(process.returncode, code, process.stdout + process.stderr)
        for value in ("admin-secret", "private-password", "Aa1!"):
            self.assertNotIn(value, process.stdout + process.stderr)
        return json.loads(process.stdout)

    def trust(self) -> None:
        self.cli("trust", "accept", str(self.cli("config")["trust_hash"]))

    def start(self) -> tuple[str, Path]:
        result = self.cli("run", "start", str(self.plan))
        run, directory = str(result["run"]), Path(str(result["dir"]))
        self.cli("users", "provision", "--run", run)
        return run, directory

    def dispatch(self, run: str, section: str = "BE") -> dict[str, object]:
        return self.cli("dispatch", "--run", run, "tester", "--section", section, "--phase", "baseline")

    def ledger(self) -> list[dict[str, object]]:
        return json.loads((self.root / "state/av-marketplace/qa-accounts.json").read_text())[str(self.repo.resolve())]

    def channel(self, directory: Path) -> dict[str, str]:
        return json.loads((directory / "secrets.json").read_text())

    def ingest(self, run: str, dispatch: dict[str, object], accounts: object) -> dict[str, object]:
        data = {"section": "BE", "scenarios": [{"id": "BE-01", "status": "PASS", "observed_status": 200}], "accounts": accounts}
        path = self.put("```json qa-results\n" + json.dumps(data) + "\n```\n", "results.md")
        return self.cli("ingest", "--run", run, "--dispatch", str(dispatch["dispatch"]), str(path))

    def register(self, run: str, dispatch: dict[str, object], *, id: str | None = "u1") -> str:
        email = f"qa+{dispatch['tag']}-owner@test.local"
        options = ["--id", id] if id is not None else []
        self.cli("users", "record", "--run", run, "--dispatch", str(dispatch["dispatch"]), "--email", email, *options)
        return email

    def configure_stores(self, *, audit: bool = False) -> None:
        stores = '[env.stores.main]\nkind="sql"\nengine="postgres"\nhost="127.0.0.1"\nuser="postgres"\nname="app"\npassword="literal:main-secret"\n[env.stores.cache]\nkind="redis"\nhost="127.0.0.1"\n'
        if audit:
            stores += '[env.stores.audit]\nkind="sql"\nengine="postgres"\nhost="127.0.0.1"\nuser="postgres"\nname="audit"\npassword="literal:audit-secret"\n'
        self.put(self.config + stores, ".av/config.toml")
        checks = '- **State Check:** main: SELECT 1 → 1\n- **State Check:** cache: GET k → v\n'
        if audit:
            checks += '- **State Check:** audit: SELECT 1 → 1\n'
        self.plan.write_text(PLAN + checks)
        self.trust()

    def test_provision_exposes_namespaced_store_values_and_native_redact_names(self) -> None:
        self.configure_stores()
        self.put((self.repo / ".av/config.toml").read_text() + '[env.stores.unused]\nkind="redis"\nhost="localhost"\n', ".av/config.toml")
        run, directory = self.start()
        values = self.channel(directory)
        expected = {"STORE_MAIN_PGHOST": "127.0.0.1", "STORE_MAIN_PGPORT": "5432",
                    "STORE_MAIN_PGUSER": "postgres", "STORE_MAIN_PGDATABASE": "app",
                    "STORE_MAIN_PGPASSWORD": "main-secret", "STORE_MAIN_PGOPTIONS": "-c default_transaction_read_only=on",
                    "STORE_CACHE_REDIS_HOST": "127.0.0.1", "STORE_CACHE_REDIS_PORT": "6379", "STORE_CACHE_REDIS_DB": "0"}
        self.assertEqual({key: value for key, value in values.items() if key.startswith("STORE_")}, expected)
        names = set((directory / "redact-names").read_text().splitlines())
        native = {"PGHOST", "PGPORT", "PGUSER", "PGDATABASE", "PGPASSWORD", "REDIS_HOST", "REDIS_PORT", "REDIS_DB"}
        self.assertEqual(names, {key for key in values if not key.endswith("_PGOPTIONS")} | native)
        self.assertEqual(self.dispatch(run)["stores"], ["cache", "main"])
        self.cli("run", "end", "--run", run)

    def test_loader_store_controls_export_native_names_and_reject_unknown_stores(self) -> None:
        self.configure_stores()
        _, directory = self.start()
        loader = shlex.quote(str(directory / "load.sh"))
        env = {**self.env, "PGHOST": "inherited", "STORE_X_Y": "inherited", "REDIS_HOST": "inherited"}
        commands = (
            (f'qa_load_store=main qa_load_require=PGPASSWORD . {loader} && printf "%s|%s|%s" "$PGHOST" "$PGOPTIONS" "$PGPASSWORD"', 0, "127.0.0.1|-c default_transaction_read_only=on|main-secret", ""),
            (f'qa_load_store=nope . {loader}', 1, "", "NOPE: unknown store"),
            (f'qa_load_require=PGPASSWORD . {loader}', 1, "", "PGPASSWORD: required value missing"),
            (f'. {loader} && printf "%s|%s|%s" "${{PGHOST:-}}" "${{STORE_X_Y:-}}" "${{REDIS_HOST:-}}"', 0, "||", ""),
        )
        shells = (["sh"], ["bash", "--posix"], *([["dash"]] if shutil.which("dash") else []))
        for shell in shells:
            for command, code, stdout, stderr in commands:
                with self.subTest(shell=shell, command=command):
                    result = subprocess.run([*shell, "-c", command], env=env, capture_output=True, text=True)
                    self.assertEqual(result.returncode, code, result.stderr)
                    self.assertEqual(result.stdout, stdout)
                    self.assertIn(stderr, result.stderr)

    def test_loader_refuses_selected_store_without_an_endpoint(self) -> None:
        self.configure_stores()
        _, directory = self.start()
        loader = shlex.quote(str(directory / "load.sh"))
        channel = directory / "secrets.env"
        channel.write_text(channel.read_text().replace("export STORE_MAIN_PGHOST='127.0.0.1'", "export STORE_MAIN_PGHOST=''"))
        command = f'qa_load_store=main qa_load_require=PGPASSWORD . {loader} && printf "client would run"'
        for shell in (["sh"], ["bash", "--posix"], *([["dash"]] if shutil.which("dash") else [])):
            with self.subTest(shell=shell):
                result = subprocess.run([*shell, "-c", command], env={**self.env, "PGHOST": "inherited"}, capture_output=True, text=True, check=False)
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertEqual(result.stdout, "")
                self.assertIn("MAIN: store not exported", result.stderr)

    def test_loader_required_controls_fail_before_a_request_and_ignore_caller_arguments(self) -> None:
        _, directory = self.start()
        loader = shlex.quote(str(directory / "load.sh"))
        for shell in (["sh"], ["bash", "--posix"], *([["dash"]] if shutil.which("dash") else [])):
            with self.subTest(shell=shell):
                command = f'set -- unrelated arguments; qa_load_require="QA_ADMIN_EMAIL QA_MISSING" . {loader} && printf "request would run"'
                result = subprocess.run([*shell, "-c", command], env={**self.env, "QA_MISSING": "inherited"}, capture_output=True, text=True, check=False)
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertEqual(result.stdout, "")
                self.assertIn("QA_MISSING: required value missing", result.stderr)
                command = f'set -- unrelated arguments; qa_load_require=QA_ADMIN_EMAIL . {loader} && printf "%s|%s|%s" "$QA_ADMIN_EMAIL" "$1" "$2"'
                result = subprocess.run([*shell, "-c", command], env=self.env, capture_output=True, text=True, check=False)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, "admin@test.local|unrelated|arguments")

    def test_loader_store_selection_keeps_overlapping_names_distinct(self) -> None:
        self.configure_stores(audit=True)
        config = self.repo / ".av/config.toml"
        config.write_text(config.read_text().replace("[env.stores.audit]", "[env.stores.main_audit]"))
        self.plan.write_text(self.plan.read_text().replace("audit: SELECT", "main_audit: SELECT"))
        self.trust()
        _, directory = self.start()
        loader = shlex.quote(str(directory / "load.sh"))
        for store, expected in (("main", "app|main-secret||"), ("main_audit", "audit|audit-secret||")):
            with self.subTest(store=store):
                command = (
                    f'unset AUDIT_PGDATABASE AUDIT_PGPASSWORD; qa_load_store={store} qa_load_require=PGPASSWORD . {loader} && '
                    'printf "%s|%s|%s|%s" "$PGDATABASE" "$PGPASSWORD" '
                    '"${AUDIT_PGDATABASE+set}" "${AUDIT_PGPASSWORD+set}"'
                )
                result = subprocess.run(["sh", "-c", command], env=self.env, capture_output=True, text=True, check=False)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, expected)

    def test_loader_rejects_a_store_name_that_is_only_a_prefix(self) -> None:
        self.configure_stores()
        config = self.repo / ".av/config.toml"
        config.write_text(config.read_text().replace("[env.stores.main]", "[env.stores.a_b]"))
        self.plan.write_text(self.plan.read_text().replace("main: SELECT", "a_b: SELECT"))
        self.trust()
        _, directory = self.start()
        command = f'qa_load_store=a . {shlex.quote(str(directory / "load.sh"))}'
        result = subprocess.run(["sh", "-c", command], env=self.env, capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertIn("A: unknown store", result.stderr)

    @unittest.skipUnless(shutil.which("bash"), "bash unavailable")
    def test_loader_keeps_response_text_and_store_values_out_of_eval_syntax(self) -> None:
        self.configure_stores()
        response_marker = self.root / "response-executed"
        value_marker = self.root / "value-executed"
        password = f"pa'ss\\word\n$(touch {value_marker}); `touch {value_marker}`"
        self.env["AV_STORE_PASSWORD"] = password
        config = self.repo / ".av/config.toml"
        config.write_text(config.read_text().replace("literal:main-secret", "env:AV_STORE_PASSWORD"))
        self.trust()
        _, directory = self.start()
        response = f"HTTP/1.1 200 OK\nSTORE_MAIN_A}};touch${{IFS}}{response_marker};#=x"
        command = (
            f'RESP={shlex.quote(response)}; qa_load_store=main qa_load_require=PGPASSWORD '
            f'. {shlex.quote(str(directory / "load.sh"))} && printf "%s" "$PGPASSWORD"'
        )
        for shell in (["sh"], ["bash", "--posix"]):
            with self.subTest(shell=shell):
                result = subprocess.run([*shell, "-c", command], env=self.env, capture_output=True, text=True, check=False)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, password)
                self.assertFalse(response_marker.exists())
                self.assertFalse(value_marker.exists())

    def test_dispatch_lists_the_section_stores(self) -> None:
        self.configure_stores()
        self.plan.write_text(self.plan.read_text() + '### FE-01: UI\n- **Writes:** no\n- **URL:** /items\n- **Expected:** Items visible. (src/app.py:1)\n')
        run, _ = self.start()
        self.assertEqual(self.dispatch(run)["stores"], ["cache", "main"])
        self.assertEqual(self.dispatch(run, "FE")["stores"], [])

    def test_store_passwords_are_masked_after_the_real_loader(self) -> None:
        self.configure_stores(audit=True)
        _, directory = self.start()
        redactor = SCRIPTS.parents[1] / "be-testing/scripts/qa-redact.pl"
        for controls, main in (("", "$STORE_MAIN_PGPASSWORD"), ("qa_load_store=main qa_load_require=PGPASSWORD", "$PGPASSWORD")):
            with self.subTest(controls=controls):
                command = f'{controls} . {shlex.quote(str(directory / "load.sh"))} && printf \'{{"a":"%s","b":"%s"}}\' "{main}" "$STORE_AUDIT_PGPASSWORD" | perl {shlex.quote(str(redactor))} {shlex.quote(str(directory / "redact-names"))}'
                result = subprocess.run(["sh", "-c", command], env=self.env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(result.stdout), {"a": "***", "b": "***"})

    @unittest.skipUnless(shutil.which("sqlite3"), "sqlite3 unavailable")
    def test_sql_cleanup_deletes_by_email_in_sqlite(self) -> None:
        self.sqlite_cleanup(null_id=False)

    @unittest.skipUnless(shutil.which("sqlite3"), "sqlite3 unavailable")
    def test_sql_cleanup_quotes_values_and_substitutes_null_id(self) -> None:
        self.sqlite_cleanup(null_id=True)

    def sqlite_cleanup(self, *, null_id: bool) -> None:
        query = "DELETE FROM users WHERE email = {email}"
        if null_id:
            query += " AND (id IS {id} OR id = {id})"
        self.put(self.base + USER + '[env.stores.main]\nkind="sql"\nengine="sqlite"\npath="qa.sqlite"\n[qa.cleanup]\nkind="sql"\nstore="main"\n' + f'query="{query}"\n', ".av/config.toml")
        self.trust()
        run, directory = self.start()
        email = self.register(run, self.dispatch(run), id=None if null_id else "u1")
        db = self.repo / "qa.sqlite"
        subprocess.run(["sqlite3", str(db), f"CREATE TABLE users(email TEXT, id TEXT); INSERT INTO users VALUES ('{email}', NULL), ('keep@test.local', 'keep');"], check=True)
        self.assertEqual(self.cli("users", "teardown", "--run", run), {"deleted": [email], "left": [], "manual": []})
        result = subprocess.run(["sqlite3", str(db), "SELECT email FROM users"], capture_output=True, text=True, check=True)
        self.assertEqual(result.stdout.strip(), "keep@test.local")
        self.assertNotIn(email, (directory / "engine.log").read_text())

    def test_sql_cleanup_runs_the_client_in_a_sanitised_environment(self) -> None:
        clients = (
            ("postgres", "psql", ["-X"], "PGHOST", "PGPASSWORD"),
            ("mysql", "mysql", ["--no-defaults", "--no-login-paths"], "MYSQL_HOST", "MYSQL_PWD"),
        )
        for engine, client, startup_flags, host_name, password_name in clients:
            with self.subTest(engine=engine):
                self.configure_stores()
                config = (self.repo / ".av/config.toml").read_text().replace('engine="postgres"', f'engine="{engine}"')
                self.put(config.replace(CLEANUP, '[qa.cleanup]\nkind="sql"\nstore="main"\nquery="DELETE FROM users WHERE email = {email}"\n'), ".av/config.toml")
                self.trust()
                capture = self.root / "client-environment"
                arguments = self.root / "client-arguments"
                fake = self.put('#!/bin/sh\nenv > "$CLIENT_ENV"\nprintf "%s\\n" "$@" > "$CLIENT_ARGS"\n', f"bin/{client}")
                fake.chmod(0o700)
                self.env.update({"PATH": str(fake.parent) + os.pathsep + self.env["PATH"],
                                 "CLIENT_ENV": str(capture), "CLIENT_ARGS": str(arguments),
                                 "PSQLRC": str(self.root / "untrusted.psqlrc"),
                                 "PGHOSTADDR": "10.0.0.9", "PGSERVICE": "x", "PGOPTIONS": "-c default_transaction_read_only=on"})
                run, _ = self.start()
                try:
                    email = self.register(run, self.dispatch(run))
                    self.assertEqual(self.cli("users", "teardown", "--run", run)["deleted"], [email])
                    self.assertEqual(arguments.read_text().splitlines()[:len(startup_flags)], startup_flags)
                    recorded = dict(line.split("=", 1) for line in capture.read_text().splitlines())
                    for name in ("PSQLRC", "PGHOSTADDR", "PGSERVICE", "PGOPTIONS", "STORE_MAIN_PGPASSWORD", "QA_NEW_PASSWORD"):
                        self.assertNotIn(name, recorded)
                    self.assertEqual(recorded[host_name], "127.0.0.1")
                    self.assertEqual(recorded[password_name], "main-secret")
                    self.assertEqual(recorded["QA_SQL"], f"DELETE FROM users WHERE email = '{email}'")
                finally:
                    self.cli("run", "end", "--run", run)

    def test_provision_writes_users_values_and_new_password_only_for_plan_tokens(self) -> None:
        run, directory = self.start()
        result = self.cli("users", "provision", "--run", run)
        values = self.channel(directory)
        self.assertEqual(set(values), {"QA_ADMIN_EMAIL", "QA_ADMIN_PASSWORD", "QA_NEW_PASSWORD"})
        self.assertRegex(values["QA_NEW_PASSWORD"], r"^[A-Za-z0-9_-]{24}Aa1!$")
        self.assertEqual((directory / "redact-names").read_text().splitlines(), sorted(values))
        process = subprocess.run(["sh", "-c", f"qa_load_require=QA_ADMIN_EMAIL . {shlex.quote(str(directory / 'load.sh'))} && printf '%s' \"$QA_ADMIN_EMAIL\""], env=self.env, capture_output=True, text=True)
        self.assertEqual(process.stdout, "admin@test.local")
        self.assertEqual(result["users"], ["admin"])

    def test_dispatch_issues_a_distinct_tag_per_dispatch_and_no_refresh_key(self) -> None:
        run, directory = self.start()
        first, second = self.dispatch(run), self.dispatch(run)
        self.assertNotEqual(first["tag"], second["tag"])
        self.assertRegex(first["tag"], r"^[0-9a-f]{8}$")
        self.assertNotIn("refreshed", first)
        state = json.loads((directory / "run.json").read_text())
        sidecar = json.loads(Path(state["sidecar"]).read_text())
        self.assertEqual(sidecar["dispatches"][first["dispatch"]]["tag"], first["tag"])

    def test_dispatch_before_provision_can_be_retried(self) -> None:
        for partial_capture in (False, True):
            with self.subTest(partial_capture=partial_capture):
                started = self.cli("run", "start", str(self.plan))
                run, directory = str(started["run"]), Path(str(started["dir"]))
                captured = directory / "results" / "D001"
                result = self.cli("dispatch", "--run", run, "tester", "--section", "BE", "--phase", "baseline", code=1)
                self.assertEqual(result["error"], "run users provision before dispatch")
                self.assertFalse(captured.exists())
                self.cli("users", "provision", "--run", run)
                if partial_capture:
                    captured.mkdir(parents=True)
                    captured.chmod(0o755)
                    (captured / "captured.env").write_text("stale credentials")
                    (captured / "redact-names").write_text("stale names")
                dispatch = self.dispatch(run)
                self.assertEqual(dispatch["dispatch"], "D001")
                self.assertEqual(captured.stat().st_mode & 0o777, 0o700)
                self.assertEqual((captured / "captured.env").read_bytes(), b"")
                self.assertEqual((captured / "captured.env").stat().st_mode & 0o777, 0o600)
                self.assertEqual((captured / "redact-names").read_bytes(), (directory / "redact-names").read_bytes())
                self.assertEqual((captured / "redact-names").stat().st_mode & 0o777, 0o600)
                self.cli("run", "end", "--run", run)

    def test_ingest_records_tagged_accounts_and_rejects_the_rest(self) -> None:
        run, _ = self.start()
        dispatch = self.dispatch(run)
        tag = str(dispatch["tag"])
        bad = f"qa+{tag}-bad@test.local"
        result = self.ingest(run, dispatch, [
            {"email": f"qa+{tag}-owner@test.local", "id": "u1"},
            {"email": f"qa+{tag.upper()}-x@test.local", "id": None},
            {"email": "stranger@test.local", "id": None},
            {"email": "admin@test.local", "id": None},
            {"email": bad, "id": "x;drop"},
        ])
        self.assertEqual(result["accounts"], {"recorded": 2, "rejected": sorted(["admin@test.local", bad, "stranger@test.local"])})
        self.assertEqual(result["verdicts"], {"BE-01": "pass"})
        records = self.ledger()
        self.assertEqual(len(records), 2)
        for record in records:
            self.assertEqual((record["status"], record["attempts"], record["run_id"], record["tag"], record["dispatch"]), ("pending", 0, run, tag, dispatch["dispatch"]))

    def test_capture_helper_records_accounts_and_credentials_before_ingest(self) -> None:
        run, directory = self.start()
        dispatch = self.dispatch(run)
        captured = directory / "results" / str(dispatch["dispatch"])
        self.assertEqual(captured.stat().st_mode & 0o777, 0o700)
        self.assertEqual((captured / "captured.env").stat().st_mode & 0o777, 0o600)
        self.assertEqual((captured / "redact-names").read_text(), (directory / "redact-names").read_text())
        helper = ["sh", str(directory / "capture.sh"), str(dispatch["dispatch"])]
        value = "tok'en\\x"
        process = subprocess.run([*helper, "QA_CAPTURED_OWNER_TOKEN"], input=value + "\n", env=self.env, capture_output=True, text=True)
        self.assertEqual(process.returncode, 0, process.stderr)
        sourced = subprocess.run(["sh", "-c", f". {shlex.quote(str(captured / 'captured.env'))}; printf '%s' \"$QA_CAPTURED_OWNER_TOKEN\""], capture_output=True, text=True)
        self.assertEqual(sourced.stdout, value)
        before = (captured / "captured.env").read_bytes()
        invalid = subprocess.run([*helper, "FOO"], input="invalid", capture_output=True, text=True)
        self.assertEqual(invalid.returncode, 1)
        self.assertEqual((captured / "captured.env").read_bytes(), before)
        email = f"qa+{dispatch['tag']}-owner@test.local"
        recorded = subprocess.run([*helper, "--account", email, ""], env=self.env, capture_output=True, text=True)
        self.assertEqual(recorded.returncode, 0, recorded.stdout + recorded.stderr)
        self.assertIsNone(self.ledger()[0]["id"])
        self.assertEqual(self.ledger()[0]["destination"], self.origin)
        subprocess.run([*helper, "--account", email, "u1"], env=self.env, check=True, capture_output=True)
        self.ingest(run, dispatch, [{"email": email, "id": "u1"}])
        self.assertEqual(len(self.ledger()), 1)
        self.assertEqual(self.ledger()[0]["id"], "u1")
        bad = subprocess.run([*helper, "--account", "stranger@test.local"], env=self.env, capture_output=True, text=True)
        self.assertEqual(bad.returncode, 1)
        self.assertIn("email not tagged for this dispatch", bad.stdout)
        self.cli("run", "end", "--run", run)
        run, _ = self.start()
        dispatch = self.dispatch(run)
        email2 = self.register(run, dispatch)
        result = self.cli("users", "teardown", "--run", run)
        self.assertEqual(result["deleted"], sorted([email, email2]))
        self.cli("run", "end", "--run", run)
        self.assertEqual(len(self.ledger()), 2)

    def test_invalid_accounts_value_invalidates_the_block(self) -> None:
        for accounts in ("nope", [{}], [{"email": 1}]):
            with self.subTest(accounts=accounts):
                run, directory = self.start()
                result = self.ingest(run, self.dispatch(run), accounts)
                self.assertIn("error", result)
                state = json.loads(Path(json.loads((directory / "run.json").read_text())["sidecar"]).read_text())
                self.assertEqual(state["scenario_reason"]["BE-01"], "cannot-confirm")
                self.cli("run", "end", "--run", run)

    def test_teardown_http_cleanup_deletes_by_email_and_reports_outcomes(self) -> None:
        for path in ("/users/{email}", "/users?email={email}"):
            with self.subTest(path=path):
                self.put(self.config.replace("/users/{email}", path), ".av/config.toml")
                self.trust()
                run, _ = self.start()
                dispatch = self.dispatch(run)
                email = self.register(run, dispatch)
                result = self.cli("users", "teardown", "--run", run)
                self.assertEqual(result, {"deleted": [email], "left": [], "manual": []})
                actual, headers = self.server.events[-1]
                self.assertEqual(headers["apikey"], "admin-secret")
                if "?" in path:
                    self.assertEqual(parse_qs(urlsplit(actual).query)["email"], [email])
                else:
                    self.assertEqual(actual, f"/users/qa%2B{dispatch['tag']}-owner%40test.local")
                self.assertEqual(self.cli("users", "teardown", "--run", run), {"deleted": [], "left": [], "manual": []})
                self.assertTrue(self.ledger()[-1]["deleted"])
                self.cli("run", "end", "--run", run)

    def test_teardown_reuses_command_secret_after_a_record_failure_across_runs(self) -> None:
        self.put(self.config.replace('ADMIN = "env:AV_ADMIN"', 'ADMIN = "cmd:sh scripts/source-helper.sh"'),
                 ".av/config.toml")
        self.put('''printf '%s\\n' resolve >> source-calls.txt
if [ ! -e source-ready ]; then
    touch source-ready
    exit 1
fi
if [ -e source-used ]; then
    exit 1
fi
touch source-used
printf '%s' "$AV_ADMIN"
''', "scripts/source-helper.sh")
        self.trust()
        previous, _ = self.start()
        failed = self.register(previous, self.dispatch(previous))
        self.cli("run", "end", "--run", previous)
        run, _ = self.start()
        dispatch = self.dispatch(run)
        emails = [f"qa+{dispatch['tag']}-{name}@test.local" for name in ("owner", "other")]
        for email in emails:
            self.cli("users", "record", "--run", run, "--dispatch", str(dispatch["dispatch"]), "--email", email)

        self.assertEqual(self.cli("users", "teardown", "--run", run),
                         {"deleted": sorted(emails), "left": [failed], "manual": []})
        self.assertEqual((self.repo / "source-calls.txt").read_text().splitlines(), ["resolve", "resolve"])
        self.assertEqual([(record["email"], record["attempts"], record["deleted"]) for record in self.ledger()],
                         [(failed, 1, False), *[(email, 0, True) for email in emails]])

    def test_teardown_leaves_legacy_records_untouched_and_cleans_current_records(self) -> None:
        run, _ = self.start()
        dispatch = self.dispatch(run)
        email = self.register(run, dispatch)
        legacy = [
            {"persona": "owner", "email": "qa-old-owner@test.local", "id": "old-1",
             "run_id": "old-run", "origin": "http://127.0.0.1:9999",
             "recipe_hash": "old-hash", "deleted": False, "status": "created"},
            {"email": f"qa+{dispatch['tag']}-missing-destination@test.local",
             "id": None, "tag": dispatch["tag"], "attempts": 0,
             "deleted": False, "status": "pending"},
            {"email": "qa-old-missing-tag@test.local", "id": None,
             "destination": self.origin, "attempts": 0, "deleted": False, "status": "pending"},
        ]
        path = self.root / "state/av-marketplace/qa-accounts.json"
        path.write_text(json.dumps({str(self.repo.resolve()): [*legacy, *self.ledger()]}))
        for attempt in range(2):
            process = subprocess.run([sys.executable, str(SCRIPTS / "qa.py"), "users", "teardown",
                                      "--run", run, "--repo", str(self.repo)],
                                     env=self.env, capture_output=True, text=True, check=False)
            self.assertEqual(process.returncode, 0, process.stdout + process.stderr)
            self.assertEqual(json.loads(process.stdout),
                             {"deleted": [email] if attempt == 0 else [],
                              "left": sorted(str(record["email"]) for record in legacy), "manual": []})
            self.assertIn("legacy", process.stderr.lower())
            self.assertEqual(self.ledger()[:len(legacy)], legacy)
            self.assertTrue(self.ledger()[-1]["deleted"])
        self.assertEqual([event[0] for event in self.server.events],
                         [f"/users/qa%2B{dispatch['tag']}-owner%40test.local"])

    def test_teardown_revalidates_ledger_records_before_cleanup(self) -> None:
        run, _ = self.start()
        dispatch = self.dispatch(run)
        email = self.register(run, dispatch)
        current = self.ledger()[0]
        changes: list[dict[str, object]] = [
            {"email": f"qa+{dispatch['tag']}-bad';delete@test.local"},
            {"id": "u1;delete"},
            {"id": 1},
            {"id": ""},
            {"email": 1},
            {"email": ""},
            {"tag": None},
            {"tag": "bad';delete"},
            {"tag": "00000000" if dispatch["tag"] != "00000000" else "11111111"},
            {"destination": 1},
            {"attempts": "bad"},
            {"attempts": None},
            {"attempts": -1},
            {"attempts": True},
        ]
        invalid = [{**current, "email": f"qa+{dispatch['tag']}-bad{index}@test.local", **change}
                   for index, change in enumerate(changes)]
        missing_email = dict(current)
        del missing_email["email"]
        invalid.append(missing_email)
        missing_attempts = {**current, "email": f"qa+{dispatch['tag']}-missing-attempts@test.local"}
        del missing_attempts["attempts"]
        invalid.append(missing_attempts)
        path = self.root / "state/av-marketplace/qa-accounts.json"
        path.write_text(json.dumps({str(self.repo.resolve()): [*invalid, current]}))
        process = subprocess.run([sys.executable, str(SCRIPTS / "qa.py"), "users", "teardown",
                                  "--run", run, "--repo", str(self.repo)],
                                 env=self.env, capture_output=True, text=True, check=False)
        self.assertEqual(process.returncode, 0, process.stdout + process.stderr)
        self.assertEqual(json.loads(process.stdout),
                         {"deleted": [email],
                          "left": sorted(record["email"] for record in invalid
                                         if isinstance(record.get("email"), str) and record["email"]),
                          "manual": []})
        for reason in ("email", "id", "tag", "destination", "attempts"):
            self.assertIn(reason, process.stderr.lower())
        self.assertNotIn("delete@test.local", process.stderr)
        self.assertNotIn("u1;delete", process.stderr)
        self.assertEqual(self.ledger()[:-1], invalid)
        self.assertTrue(self.ledger()[-1]["deleted"])
        self.assertEqual([event[0] for event in self.server.events],
                         [f"/users/qa%2B{dispatch['tag']}-owner%40test.local"])

    def test_teardown_isolates_a_failed_account_from_later_cleanup(self) -> None:
        self.put(self.base + USER + '[qa.cleanup]\nkind="command"\nrun="sh scripts/cleanup.sh"\n',
                 ".av/config.toml")
        self.put('case "$QA_EMAIL" in *-fail@*) exit 1 ;; esac\nprintf "%s\\n" "$QA_EMAIL" >> deleted.txt\n',
                 "scripts/cleanup.sh")
        self.trust()
        run, _ = self.start()
        dispatch = self.dispatch(run)
        failed = f"qa+{dispatch['tag']}-fail@test.local"
        self.cli("users", "record", "--run", run, "--dispatch", str(dispatch["dispatch"]), "--email", failed)
        email = self.register(run, dispatch)
        self.assertEqual(self.cli("users", "teardown", "--run", run),
                         {"deleted": [email], "left": [failed], "manual": []})
        self.assertEqual((self.repo / "deleted.txt").read_text().splitlines(), [email])
        self.assertEqual([(record["email"], record["attempts"], record["deleted"]) for record in self.ledger()],
                         [(failed, 1, False), (email, 0, True)])

    def test_teardown_persists_each_outcome_before_a_later_interruption(self) -> None:
        self.put(self.base + USER + '[qa.cleanup]\nkind="command"\nrun="exec python3 scripts/cleanup.py"\n',
                 ".av/config.toml")
        self.put('''import os
from pathlib import Path
import signal
import sys

email = os.environ["QA_EMAIL"]
if "-interrupt@" in email and not Path("resume").exists():
    os.kill(os.getppid(), signal.SIGKILL)
    sys.exit(0)
if "-fail@" in email or "-manual@" in email:
    sys.exit(1)
with Path("deleted.txt").open("a") as handle:
    handle.write(email + "\\n")
''', "scripts/cleanup.py")
        self.trust()
        run, _ = self.start()
        dispatch = self.dispatch(run)
        emails = [f"qa+{dispatch['tag']}-{name}@test.local"
                  for name in ("success", "fail", "manual", "interrupt")]
        for email in emails:
            self.cli("users", "record", "--run", run, "--dispatch", str(dispatch["dispatch"]), "--email", email)
        records = self.ledger()
        records[2]["attempts"] = 2
        path = self.root / "state/av-marketplace/qa-accounts.json"
        path.write_text(json.dumps({str(self.repo.resolve()): records}))

        process = subprocess.run([sys.executable, str(SCRIPTS / "qa.py"), "users", "teardown",
                                  "--run", run, "--repo", str(self.repo)],
                                 env=self.env, capture_output=True, text=True, check=False, timeout=15)
        self.assertEqual(process.returncode, -signal.SIGKILL, process.stdout + process.stderr)
        self.assertEqual((self.repo / "deleted.txt").read_text().splitlines(), emails[:1])
        self.assertEqual([(record["deleted"], record["attempts"], record["status"]) for record in self.ledger()],
                         [(True, 0, "deleted"), (False, 1, "pending"),
                          (False, 3, "manual-cleanup"), (False, 0, "pending")])

        self.put("", "resume")
        self.assertEqual(self.cli("users", "teardown", "--run", run),
                         {"deleted": [emails[3]], "left": [emails[1]], "manual": []})
        self.assertEqual((self.repo / "deleted.txt").read_text().splitlines(), [emails[0], emails[3]])
        self.assertEqual([record["attempts"] for record in self.ledger()], [0, 2, 3, 0])
        self.cli("run", "end", "--run", run)

    def test_record_rejects_invalid_and_configured_identities(self) -> None:
        run, _ = self.start()
        dispatch = self.dispatch(run)
        tagged = f"qa+{dispatch['tag']}-owner@test.local"
        for email, account_id, reason in (
            (f"qa+{dispatch['tag']}/owner@test.local", None, "invalid email"),
            (tagged, "u1;delete", "invalid id"),
            ("admin@test.local", None, "configured user"),
            ("stranger@test.local", None, "email not tagged for this dispatch"),
        ):
            with self.subTest(reason=reason):
                options = ["--id", account_id] if account_id is not None else []
                result = self.cli("users", "record", "--run", run, "--dispatch", str(dispatch["dispatch"]), "--email", email, *options, code=1)
                self.assertEqual(result["error"], reason)
        self.assertEqual(self.register(run, dispatch), tagged)
        self.assertEqual([record["email"] for record in self.ledger()], [tagged])

    def test_record_only_fills_missing_id_and_preserves_cleanup_state(self) -> None:
        run, _ = self.start()
        dispatch = self.dispatch(run)
        email = self.register(run, dispatch, id=None)
        self.server.mode = "500"
        self.assertEqual(self.cli("users", "teardown", "--run", run)["left"], [email])
        self.register(run, dispatch, id="u1")
        self.assertEqual((self.ledger()[0]["id"], self.ledger()[0]["attempts"]), ("u1", 1))
        self.server.mode = "ok"
        self.assertEqual(self.cli("users", "teardown", "--run", run)["deleted"], [email])
        self.register(run, dispatch, id="u2")
        record = self.ledger()[0]
        self.assertEqual((record["id"], record["attempts"], record["status"], record["deleted"]), ("u1", 1, "deleted", True))
        self.assertEqual(self.cli("users", "teardown", "--run", run), {"deleted": [], "left": [], "manual": []})

    def test_http_failures_count_attempts_and_never_follow_redirects(self) -> None:
        run, _ = self.start()
        email = self.register(run, self.dispatch(run))
        for attempt, mode in enumerate(("unavailable", "redirect", "500"), 1):
            self.server.mode = mode
            result = self.cli("users", "teardown", "--run", run)
            self.assertEqual(self.ledger()[0]["attempts"], attempt)
            self.assertEqual(result, {"deleted": [], "left": [email] if attempt < 3 else [], "manual": [email] if attempt == 3 else []})
            self.assertEqual(len(self.server.events), attempt)
        self.assertFalse(any(path == "/other" for path, _ in self.server.events))

    def test_http_cleanup_without_required_id_waits_then_uses_recorded_id(self) -> None:
        self.put(self.config.replace("/users/{email}", "/users/{email}/{id}"), ".av/config.toml")
        self.trust()
        run, _ = self.start()
        dispatch = self.dispatch(run)
        email = self.register(run, dispatch, id=None)
        self.assertEqual(self.cli("users", "teardown", "--run", run)["left"], [email])
        self.assertEqual(self.server.events, [])
        self.assertEqual(self.ledger()[0]["attempts"], 1)
        self.register(run, dispatch, id="u1")
        self.assertEqual(self.cli("users", "teardown", "--run", run)["deleted"], [email])
        self.assertTrue(self.server.events[-1][0].endswith("/u1"))

    def test_teardown_command_cleanup_sees_email_id_tag_and_no_password(self) -> None:
        self.put('test "$QA_EMAIL" = "qa+$QA_TAG-owner@test.local" && test "$QA_ID" = u1 && test -z "${QA_PASSWORD:-}" && test -z "${QA_NEW_PASSWORD:-}"\n', "scripts/cleanup.sh")
        self.put(self.base + USER + '[qa.cleanup]\nkind="command"\nrun="sh scripts/cleanup.sh"\n', ".av/config.toml")
        self.env.update(QA_PASSWORD="inherited-secret", QA_NEW_PASSWORD="inherited-new-secret")
        self.trust()
        run, directory = self.start()
        email = self.register(run, self.dispatch(run))
        self.assertEqual(self.cli("users", "teardown", "--run", run)["deleted"], [email])
        self.assertNotIn("private-password", (directory / "engine.log").read_text())

    def test_cleanup_destination_provenance_is_honoured(self) -> None:
        server2 = self.new_server()
        origin2 = f"http://127.0.0.1:{server2.server_port}"
        config = self.config.replace('[env.secrets]', f'backend2="{origin2}"\n[env.secrets]')
        self.put(config, ".av/config.toml")
        self.trust()
        run, _ = self.start()
        email = self.register(run, self.dispatch(run))
        self.put(config.replace('target = "backend"', 'target = "backend2"'), ".av/config.toml")
        self.trust()
        self.assertEqual(self.cli("users", "teardown", "--run", run)["left"], [email])
        self.assertEqual(self.ledger()[0]["attempts"], 0)
        self.put(config, ".av/config.toml")
        self.trust()
        self.assertEqual(self.cli("users", "teardown", "--run", run)["deleted"], [email])

    def test_failed_cleanup_counts_attempts_and_stops_after_three(self) -> None:
        self.put(self.base + USER + '[qa.cleanup]\nkind="command"\nrun="exit 1"\n', ".av/config.toml")
        self.trust()
        for attempt in range(1, 5):
            run, _ = self.start()
            if attempt == 1:
                email = self.register(run, self.dispatch(run))
            result = self.cli("users", "teardown", "--run", run)
            self.assertEqual(self.ledger()[0]["attempts"], min(attempt, 3))
            self.assertEqual(result["left"], [email] if attempt < 3 else [])
            self.assertEqual(result["manual"], [email] if attempt == 3 else [])
            self.cli("run", "end", "--run", run)
        self.assertEqual(self.ledger()[0]["status"], "manual-cleanup")

    def test_missing_cleanup_is_a_soft_gap_that_leaves_accounts(self) -> None:
        self.put(self.base + USER, ".av/config.toml")
        self.trust()
        checked = self.cli("plan", "check", str(self.plan))
        self.assertTrue(checked["ok"])
        self.assertTrue(checked["missing"]["cleanup"])
        self.assertEqual(checked["registrations"], ["owner"])
        run, _ = self.start()
        email = self.register(run, self.dispatch(run))
        self.assertEqual(self.cli("users", "teardown", "--run", run)["left"], [email])
        self.assertEqual(self.ledger()[0]["attempts"], 0)
        self.assertIsNone(self.ledger()[0]["destination"])
        self.put(self.config, ".av/config.toml")
        self.trust()
        self.assertEqual(self.cli("users", "teardown", "--run", run)["deleted"], [email])
        self.assertEqual(self.ledger()[0]["destination"], self.origin)

    def test_untrusted_config_leaves_accounts_without_counting_attempts(self) -> None:
        run, _ = self.start()
        email = self.register(run, self.dispatch(run))
        self.put(self.config.replace('fix = "approve"', 'fix = "off"'), ".av/config.toml")
        self.assertEqual(self.cli("users", "teardown", "--run", run)["left"], [email])
        self.assertEqual(self.ledger()[0]["attempts"], 0)
        self.trust()
        self.assertEqual(self.cli("users", "teardown", "--run", run)["deleted"], [email])

    def test_invalid_config_leaves_accounts_without_interpreting_destinations(self) -> None:
        for target in ("1", json.dumps(f"{self.origin}/x")):
            with self.subTest(target=target):
                run, directory = self.start()
                dispatch = self.dispatch(run)
                email = self.register(run, dispatch)
                self.put(self.config.replace(f'backend = "{self.origin}"', f"backend = {target}"), ".av/config.toml")
                self.assertEqual(self.cli("users", "teardown", "--run", run), {"deleted": [], "left": [email], "manual": []})
                ingested = f"qa+{dispatch['tag']}-ingested@test.local"
                result = self.ingest(run, dispatch, [{"email": ingested, "id": "u2"}])
                self.assertEqual(result["accounts"], {"recorded": 1, "rejected": []})
                self.assertEqual(result["verdicts"], {"BE-01": "pass"})
                state = json.loads(Path(json.loads((directory / "run.json").read_text())["sidecar"]).read_text())
                self.assertEqual(state["current"]["BE-01"], "pass")
                second = f"qa+{dispatch['tag']}-second@test.local"
                self.assertEqual(self.cli("users", "record", "--run", run, "--dispatch", str(dispatch["dispatch"]), "--email", second),
                                 {"recorded": True})
                records = {record["email"]: record for record in self.ledger() if record["run_id"] == run}
                self.assertEqual(set(records), {email, ingested, second})
                self.assertEqual(records[email]["destination"], self.origin)
                self.assertIsNone(records[ingested]["destination"])
                self.assertIsNone(records[second]["destination"])
                self.assertTrue(all(record["attempts"] == 0 for record in records.values()))
                self.put(self.config, ".av/config.toml")
                self.assertEqual(self.cli("users", "teardown", "--run", run)["deleted"], sorted([email, ingested, second]))
                self.cli("run", "end", "--run", run)

    def test_cleanup_destination_must_be_locked_by_this_run(self) -> None:
        run, _ = self.start()
        email = self.register(run, self.dispatch(run))
        server2 = self.new_server()
        config = self.config.replace(self.origin, f"http://127.0.0.1:{server2.server_port}")
        self.put(config, ".av/config.toml")
        self.trust()
        self.assertEqual(self.cli("users", "teardown", "--run", run)["left"], [email])
        self.assertEqual(self.ledger()[0]["attempts"], 0)
        self.put(self.config, ".av/config.toml")
        self.trust()
        self.assertEqual(self.cli("users", "teardown", "--run", run)["deleted"], [email])

    def test_repeated_provision_keeps_the_run_password(self) -> None:
        run, directory = self.start()
        password = self.channel(directory)["QA_NEW_PASSWORD"]
        self.cli("users", "provision", "--run", run)
        self.assertEqual(self.channel(directory)["QA_NEW_PASSWORD"], password)

    def test_http_cleanup_must_reference_email_and_refuses_cleartext_off_loopback(self) -> None:
        self.put(self.config.replace("/users/{email}", "/users/{id}"), ".av/config.toml")
        errors = self.cli("config", code=2)["errors"]
        self.assertIn({"file": ".av/config.toml", "key": "qa.cleanup", "error": "cleanup recipe must use {email}"}, errors)
        self.put(self.config.replace(self.origin, "http://staging.example.com"), ".av/config.toml")
        self.assertTrue(any(error["key"] == "env.targets.backend" for error in self.cli("config", code=2)["errors"]))
        with self.assertRaises(ConfigError):
            http_request(Request("http://staging.example.com/users", headers={"Authorization": "private"}))

    def test_zero_users_and_values_still_write_channel(self) -> None:
        self.plan.write_text('### BE-01: Fetch\n- **Writes:** no\n- **Method:** GET /items\n- **Expected:** 200. (src/app.py:1)\n')
        run, directory = self.start()
        self.assertEqual(set(self.channel(directory)), {"QA_NEW_PASSWORD"})
        self.assertEqual(self.dispatch(run)["scenarios"], ["BE-01"])
        self.cli("run", "end", "--run", run)
        self.plan.write_text(self.plan.read_text() + '- **State Check:** main: SELECT 1\n')
        self.put(self.config + '[env.stores.main]\nkind="sql"\nengine="sqlite"\npath="db.sqlite"\n', ".av/config.toml")
        self.trust()
        _, directory = self.start()
        self.assertEqual(self.channel(directory)["STORE_MAIN_SQLITE_DB"], str(self.repo.resolve() / "db.sqlite"))

    def test_loader_fails_closed_and_shell_quotes_password(self) -> None:
        self.env["QA_ADMIN_SECRET"] = "pa'ss\\word"
        run, directory = self.start()
        command = f"qa_load_require=QA_ADMIN_PASSWORD . {shlex.quote(str(directory / 'load.sh'))} && printf '%s' \"$QA_ADMIN_PASSWORD\""
        process = subprocess.run(["sh", "-c", command], env=self.env, capture_output=True, text=True)
        self.assertEqual(process.stdout, "pa'ss\\word")
        (directory / "secrets.env").unlink()
        process = subprocess.run(["sh", "-c", command], env={**self.env, "QA_ADMIN_PASSWORD": "inherited"}, capture_output=True, text=True)
        self.assertNotEqual(process.returncode, 0)
        self.assertEqual(process.stdout, "")

    def test_services_run_with_inherited_environment_and_down_only_after_up(self) -> None:
        self.put(self.config + '[env.services]\nhealth=["backend:/"]\nup="printf \'%s\' \\\"$AV_ADMIN\\\" > up.txt"\nprepare=["touch prepared"]\ndown="touch down.txt"\n', ".av/config.toml")
        self.trust()
        run, _ = self.start()
        self.assertEqual(self.cli("services", "check", "--run", run), {"up": True, "probes": [{"target": "backend", "path": "/", "status": 200}]})
        self.server.health_status = 503
        self.assertEqual(self.cli("services", "check", "--run", run), {"up": False, "probes": [{"target": "backend", "path": "/", "status": 503}]})
        self.assertFalse(self.cli("services", "down", "--run", run)["ran"])
        self.cli("services", "up", "--run", run)
        self.assertEqual((self.repo / "up.txt").read_text(), "admin-secret")
        self.cli("services", "prepare", "--run", run)
        self.assertTrue((self.repo / "prepared").exists())
        self.cli("services", "down", "--run", run)
        self.assertTrue((self.repo / "down.txt").exists())

    def test_drift_refuses_provision_but_cleanup_uses_recorded_commands(self) -> None:
        self.put(self.config + '[env.services]\nhealth=["backend:/"]\nup="true"\ndown="touch down.txt"\n', ".av/config.toml")
        self.trust()
        run, _ = self.start()
        self.cli("services", "up", "--run", run)
        self.put(self.config.replace('fix = "approve"', 'fix = "off"'), ".av/config.toml")
        self.assertEqual(self.cli("users", "provision", "--run", run, code=1)["error"], "config changed during run")
        self.cli("services", "down", "--run", run)
        self.assertTrue((self.repo / "down.txt").exists())


if __name__ == "__main__":
    unittest.main()
