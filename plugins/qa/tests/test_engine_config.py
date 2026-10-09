"""Behavioral checks for marketplace config, trust, and the origin guard.

Run: uv run python -m unittest discover -s plugins/qa/tests -p test_engine_config.py
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[1] / "skills/engine/scripts"
sys.path.insert(0, str(SCRIPTS))

from av_config.errors import ConfigError
from av_config.origins import is_loopback
from av_config.origins import parse_origin
from av_config.sources import SOURCE_KINDS
from av_config.sources import ValueSources
from av_config.sources import mask
from av_config.transaction import ConfigTransaction
from av_config.trust import TrustStore
from qa_engine.config import Config
from qa_engine.config import VALUE_SOURCE_KEYS
from qa_engine.services import Runtime
from qa_engine.models import Run

BASE = 'version = 1\n[env.targets]\nbackend = "http://localhost:8000"\n[qa]\n'


class ConfigTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.repo = Path(self.tmp.name) / "repo"
        self.repo.mkdir()
        subprocess.run(["git", "init", "-q", str(self.repo)], check=True)
        self.state = Path(self.tmp.name) / "state"
        self.put(".av/local.toml\n", ".git/info/exclude")

    def put(self, text: str, name: str = ".av/config.toml") -> Path:
        path = self.repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def config(self) -> Config:
        return Config(self.repo, state_home=self.state)

    def cli(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(SCRIPTS / "qa.py"), *args, "--repo", str(self.repo)],
            env={**os.environ, "XDG_STATE_HOME": str(self.state)},
            capture_output=True, text=True, check=False,
        )

    def test_states_and_merge_provenance(self) -> None:
        self.assertEqual(self.config().report()["state"], "missing-file")
        self.put("version = 1\n")
        self.assertEqual(self.config().report()["state"], "missing-table")
        self.put('version = 2\n[qa]\n')
        self.assertEqual(self.config().report()["state"], "invalid")
        self.put(BASE + 'fix = "approve"\nmutations = "deny"\n')
        self.put('[qa]\nfix = "auto"\n', ".av/local.toml")
        report = self.config().report()
        self.assertEqual(report["state"], "ok")
        self.assertEqual(report["policy"], {"fix": "auto", "mutations": "deny", "start_services": "ask"})
        self.assertEqual(report["provenance"]["qa.fix"], ".av/local.toml")
        self.assertNotIn("budget", report)

    def test_local_overrides_without_shared_file_need_bootstrap(self) -> None:
        self.put('[qa]\nfix = "auto"\n', ".av/local.toml")
        report = self.config().report()
        self.assertEqual(report["state"], "missing-file")
        self.assertEqual(report["errors"], [])
        self.assertEqual(report["policy"]["fix"], "auto")
        self.assertEqual(report["provenance"]["qa.fix"], ".av/local.toml")
        supplied = Config(self.repo, state_home=self.state, config_text=BASE)
        self.assertEqual(supplied.state, "ok")
        self.assertEqual(supplied.policy["fix"], "auto")

    def test_local_qa_table_does_not_replace_shared_table(self) -> None:
        without_qa = 'version = 1\n[env.targets]\nbackend = "http://localhost:8000"\n'
        self.put('[qa]\nfix = "auto"\n', ".av/local.toml")
        for shared_text, config_text in ((without_qa, None), (BASE, without_qa)):
            with self.subTest(config_text=config_text):
                self.put(shared_text)
                report = Config(self.repo, state_home=self.state, config_text=config_text).report()
                self.assertEqual(report["state"], "missing-table")
                self.assertEqual(report["errors"], [])
                self.assertEqual(report["policy"]["fix"], "auto")
        self.put(without_qa)
        result = self.cli("config")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["state"], "missing-table")

    def test_local_mutations_without_shared_file_need_bootstrap(self) -> None:
        self.put('[qa]\nmutations = "deny"\n', ".av/local.toml")
        report = self.config().report()
        result = self.cli("config")
        self.assertEqual(report["state"], "missing-file")
        self.assertEqual(report["errors"], [])
        self.assertEqual(report["policy"]["mutations"], "deny")
        self.assertEqual(result.returncode, 0, result.stderr)
        cli_report = json.loads(result.stdout)
        self.assertEqual(cli_report["state"], "missing-file")
        self.assertEqual(cli_report["errors"], [])
        self.assertEqual(cli_report["policy"]["mutations"], "deny")

    def test_validation_errors_identify_file_and_key_without_values(self) -> None:
        cases = [
            ('[qa]\n', "version"), ('version = true\n[qa]\n', "version"),
            ('version = 2\n[qa]\n', "version"), ('version = 1\nqa = "sensitive"\n', "qa"),
            (BASE + 'surprise = "sensitive"\n', "qa.surprise"),
            (BASE + 'fix = "sensitive"\n', "qa.fix"),
            (BASE + 'mutations = "sensitive"\n', "qa.mutations"),
            (BASE + 'mutations = "rejections-only"\n', "qa.mutations"),
            (BASE + 'start_services = "always"\n', "qa.start_services"),
            (BASE + '[env.services]\nup = "sh up.sh"\n', "env.services.up"),
            (BASE + '[env.services]\nprepare = ["sh m.sh"]\n', "env.services.prepare"),
            (BASE + '[env.services]\ndown = "sh down.sh"\n', "env.services.down"),
            (BASE + '[qa.policy]\nfix = "approve"\n', "qa.policy"),
            (BASE + '[qa.budget]\niterations = 3\n', "qa.budget"),
            (BASE + '[qa.defaults]\nbe_target = "backend"\n', "qa.defaults"),
            (BASE + '[qa.accounts]\npersonas=["user"]\n', "qa.accounts"),
            (BASE + '[qa.users.new]\nemail="literal:a@b"\npassword="env:QA_X"\ndescription="d"\n', "qa.users.new"),
            (BASE + '[qa.users.Admin]\nemail="literal:a@b"\npassword="env:QA_X"\ndescription="d"\n', "qa.users.Admin"),
            (BASE + '[qa.users.admin]\nemail="literal:a@b"\npassword="env:QA_X"\n', "qa.users.admin.description"),
            (BASE + '[qa.users.admin]\npassword="env:QA_X"\ndescription="d"\n', "qa.users.admin.email"),
            (BASE + '[env.values]\nTAG="literal:x"\n', "env.values.TAG"),
            (BASE + '[env.values]\nNEW_PASSWORD="literal:x"\n', "env.values.NEW_PASSWORD"),
            (BASE + '[env.services]\nenv = { up = [] }\n', "env.services.env"),
            (BASE + '[qa.cleanup]\nkind="command"\nrun="true"\nenv=[]\n', "qa.cleanup.env"),
            (BASE + '[qa.cleanup]\nkind="http"\ntarget="sensitive"\nmethod="DELETE"\npath="/{email}"\nexpect=[200]\n', "qa.cleanup.target"),
            (BASE + '[qa.cleanup]\nkind="http"\ntarget="backend"\nmethod="DELETE"\npath="/users/{password}"\nexpect=[204]\n', "qa.cleanup.path"),
            (BASE + '[qa.cleanup]\nkind="http"\ntarget="backend"\nmethod="DELETE"\npath="/{email}"\nexpect=[200]\nheaders={x="{secret.MISSING}"}\n', "qa.cleanup.headers.x"),
            (BASE + '[qa.cleanup]\nkind="http"\ntarget="backend"\nmethod="DELETE"\npath="/{email}"\nexpect=[200]\njson={x="{value.MISSING}"}\n', "qa.cleanup.json.x"),
            (BASE + '[env.services]\nhealth=["missing:/"]\n', "env.services.health"),
            (BASE + '[env.services]\nunknown="sensitive"\n', "env.services.unknown"),
            (BASE + '[env.stores.main]\nkind="sql"\nengine="sensitive"\n', "env.stores.main.engine"),
            (BASE + '[env.stores.main]\nkind="sql"\nengine="sqlite"\npath="db"\nunknown="sensitive"\n', "env.stores.main.unknown"),
            ('version=1\nenv="sensitive"\n[qa]\n', "env"),
            (BASE + '[qa.defaults]\nunknown="sensitive"\n', "qa.defaults"),
            (BASE + '[qa.cleanup]\nkind="sensitive"\n', "qa.cleanup.kind"),
            (BASE + '[qa.cleanup]\nkind="command"\nrun=1\n', "qa.cleanup.run"),
            (BASE + '[qa.cleanup]\nkind="http"\ntarget="backend"\nmethod="sensitive"\npath="https://evil.test/"\nexpect=["sensitive"]\nheaders={x=1}\n', "qa.cleanup.method"),
            (BASE + '[qa.cleanup]\nkind="http"\ntarget="backend"\nmethod="POST"\npath="//evil.test/{email}"\nexpect=[200]\n', "qa.cleanup.path"),
            (BASE + '[qa.cleanup]\nkind="http"\ntarget="backend"\nmethod="POST"\npath="/{email}"\nexpect=[true]\n', "qa.cleanup.expect"),
            (BASE + '[qa.cleanup]\nkind="http"\ntarget="backend"\nmethod="POST"\npath="/{email}"\nexpect=[200]\nheaders={x=1}\n', "qa.cleanup.headers.x"),
            (BASE + '[env.services]\nhealth=1\nup=1\ndown=1\nprepare=[1]\n', "env.services.health"),
            (BASE + '[env.services]\nhealth=["sensitive"]\n', "env.services.health"),
            (BASE + '[env.stores.main]\nkind="sql"\nengine="sqlite"\n', "env.stores.main.path"),
            (BASE + '[env.stores.main]\nkind="sql"\nengine="postgres"\nhost="localhost"\nuser="user"\nname="db"\npassword="env:AV_DB"\nport=true\n', "env.stores.main.port"),
            (BASE + '[env.values]\n"bad-name"="env:AV_X"\n', "env.values.bad-name"),
            (BASE + '[env.values]\nX="sensitive"\n', "env.values.X"),
            (BASE + '[env.stores.x]\nkind="mongo"\n', "env.stores.x.kind"),
            (BASE + '[env.stores.x]\nkind="sql"\nengine="oracle"\n', "env.stores.x.engine"),
            (BASE + '[env.stores.x]\nkind="sql"\nengine="sqlite"\npath="db"\nhost="localhost"\n', "env.stores.x.host"),
            (BASE + '[env.stores.x]\nkind="sql"\nengine="postgres"\nhost="localhost"\nuser="u"\nname="db"\n', "env.stores.x.password"),
            (BASE + '[env.stores.x]\nkind="redis"\n', "env.stores.x.host"),
            (BASE + '[env.stores.x]\nkind="redis"\nhost="localhost"\ndb=-1\n', "env.stores.x.db"),
            (BASE + '[env.stores.main]\nkind="redis"\nhost="localhost"\n[env.stores.Main]\nkind="redis"\nhost="localhost"\n', "env.stores"),
            (BASE + '[qa.cleanup]\nkind="sql"\nstore="nope"\nquery="DELETE FROM u WHERE email = {email}"\n', "qa.cleanup.store"),
            (BASE + '[env.stores.cache]\nkind="redis"\nhost="localhost"\n[qa.cleanup]\nkind="sql"\nstore="cache"\nquery="DELETE FROM u WHERE email = {email}"\n', "qa.cleanup.store"),
            (BASE + '[env.stores.main]\nkind="sql"\nengine="sqlite"\npath="db"\n[qa.cleanup]\nkind="sql"\nstore="main"\nquery="DELETE FROM u WHERE id = {id}"\n', "qa.cleanup"),
            (BASE + '[env.stores.main]\nkind="sql"\nengine="sqlite"\npath="db"\n[qa.cleanup]\nkind="sql"\nstore="main"\nquery="DELETE FROM u WHERE email = {email} AND x = {secret.X}"\n', "qa.cleanup.query"),
        ]
        expected_errors = {
            "qa.mutations": "unsupported policy value",
            "qa.start_services": "unsupported policy value",
            "env.services.up": "up requires at least one health probe",
            "env.services.prepare": "prepare requires up",
            "env.services.down": "down requires up",
            "env.stores.x.kind": "expected sql or redis",
            "env.stores.x.engine": "expected postgres, mysql or sqlite",
            "env.stores.x.password": "expected a non-empty string",
            "env.stores.x.db": "expected a non-negative integer",
            "env.stores": "store names collide",
            "qa.cleanup.kind": "expected sql, http or command",
            "qa.cleanup.store": "undefined sql store",
            "qa.cleanup": "cleanup recipe must use {email}",
            "qa.cleanup.query": "unsupported recipe placeholder",
        }
        for text, key in cases:
            with self.subTest(key=key, text=text):
                self.put(text)
                report = self.config().report()
                self.assertEqual(report["state"], "invalid")
                self.assertTrue(any(e["file"] == ".av/config.toml" and e["key"] == key for e in report["errors"]), report["errors"])
                if key in {"qa.defaults", "qa.accounts", "env.services.env", "qa.cleanup.env"}:
                    self.assertIn({"file": ".av/config.toml", "key": key, "error": "unknown key"}, report["errors"])
                if key in expected_errors:
                    self.assertIn({"file": ".av/config.toml", "key": key, "error": expected_errors[key]}, report["errors"])
                self.assertNotIn("sensitive", json.dumps(report))

    def test_removed_database_is_an_environment_warning(self) -> None:
        self.put(BASE + '[env.database]\nkind="postgres"\n')
        report = self.config().report()
        self.assertEqual(report["state"], "ok")
        self.assertIn({"file": ".av/config.toml", "key": "env.database", "warning": "unknown environment sub-table"}, report["warnings"])

    def test_stores_report_and_source_masking(self) -> None:
        self.put(BASE + '[env.stores.main]\nkind="sql"\nengine="postgres"\nhost="localhost"\nuser="u"\nname="db"\npassword="literal:private-store-secret"\n[env.stores.cache]\nkind="redis"\nhost="localhost"\n')
        report = self.config().report()
        self.assertEqual(report["stores"], {"main": {"kind": "sql", "engine": "postgres"}, "cache": {"kind": "redis"}})
        self.assertNotIn("database", report)
        self.assertEqual(report["trust_subset"]["env.stores.main.password"], "literal:***")
        self.assertNotIn("env.stores.main.host", report["trust_subset"])
        preview = self.config().preview({"config_text": (self.repo / ".av/config.toml").read_text().replace("private-store-secret", "changed-store-secret"),
                                         "gitignore_add": [], "allowed_keys": ["env.stores.main.password"]})
        self.assertNotIn("changed-store-secret", json.dumps(preview))

    def test_network_stores_require_exact_loopback_hosts(self) -> None:
        stores = (
            'kind="sql"\nengine="postgres"\nuser="u"\nname="db"\npassword="env:AV_DB"\n',
            'kind="sql"\nengine="mysql"\nuser="u"\nname="db"\npassword="env:AV_DB"\n',
            'kind="redis"\npassword="env:AV_DB"\n',
        )
        hosts = (
            ("localhost", "ok"),
            ("127.0.0.1", "ok"),
            ("::1", "ok"),
            ("[::1]", "ok"),
            ("app.LOCALHOST", "ok"),
            ("db.example.com", "invalid"),
            ("192.168.1.10", "invalid"),
            ("127.0.0.2", "invalid"),
            ("0.0.0.0", "invalid"),
            ("localhost.example.com", "invalid"),
            ("2001:db8::1", "invalid"),
        )
        for store in stores:
            for host, state in hosts:
                with self.subTest(store=store, host=host):
                    self.put(BASE + '[env.stores.main]\n' + store + f'host={json.dumps(host)}\n')
                    report = self.config().report()
                    self.assertEqual(report["state"], state, report["errors"])
                    if state == "invalid":
                        self.assertTrue(any(error["key"] == "env.stores.main.host" for error in report["errors"]), report["errors"])

    def test_store_transport_cannot_be_overridden_by_local_config_or_trust(self) -> None:
        self.put(BASE + '[env.stores.main]\nkind="sql"\nengine="postgres"\nhost="localhost"\nuser="u"\nname="db"\npassword="env:AV_DB"\n')
        secure = self.config()
        secure.accept(secure.trust_hash)
        self.put('[env.stores.main]\nhost="db.example.com"\n', ".av/local.toml")
        cfg = self.config()
        self.assertEqual(cfg.state, "invalid")
        self.assertTrue(any(error["file"] == ".av/local.toml" and error["key"] == "env.stores.main.host" for error in cfg.errors), cfg.errors)
        with self.assertRaises(ConfigError):
            cfg.accept(cfg.trust_hash)
        result = self.cli("config")
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertEqual(json.loads(result.stdout)["state"], "invalid")

    def test_sql_cleanup_pins_its_store_destination(self) -> None:
        for store, key, old, new in (
            ('kind="sql"\nengine="sqlite"\npath="a.sqlite"\n', "path", "a.sqlite", "b.sqlite"),
            ('kind="sql"\nengine="postgres"\nhost="localhost"\nuser="u"\nname="a"\nport=5432\npassword="literal:private"\n', "name", "a", "b"),
            ('kind="sql"\nengine="postgres"\nhost="localhost"\nuser="u"\nname="a"\nport=5432\npassword="literal:private"\n', "port", "5432", "5433"),
        ):
            with self.subTest(key=key):
                text = BASE + '[env.stores.main]\n' + store + '[qa.cleanup]\nkind="sql"\nstore="main"\nquery="DELETE FROM users WHERE email = {email}"\n'
                self.put(text)
                cfg = self.config()
                self.assertEqual(cfg.errors, [])
                cfg.accept(cfg.trust_hash)
                before = f'{key}={old}' if key == "port" else f'{key}="{old}"'
                after = f'{key}={new}' if key == "port" else f'{key}="{new}"'
                self.put(text.replace(before, after))
                report = self.config().report()
                self.assertEqual(report["trust"], "changed")
                pinned = report["trust_subset"]["env.stores.main"]
                self.assertEqual(str(pinned[key]), new)
                if "password" in pinned:
                    self.assertEqual(pinned["password"], "literal:***")

    def test_removed_source_dependencies_are_an_environment_warning(self) -> None:
        self.put(BASE + '[env.source_env]\n"env.values.X" = []\n')
        report = self.config().report()
        self.assertEqual(report["state"], "ok")
        self.assertEqual(report["errors"], [])
        self.assertIn({"file": ".av/config.toml", "key": "env.source_env", "warning": "unknown environment sub-table"}, report["warnings"])

    def test_allow_needs_no_disposable_flag(self) -> None:
        self.put(BASE + 'mutations = "allow"\n')
        report = self.config().report()
        self.assertEqual(report["state"], "ok", report["errors"])
        self.assertEqual(report["policy"]["mutations"], "allow")

    def test_target_validation(self) -> None:
        for origin in ("ftp://localhost", "http://user:pass@localhost", "http://localhost/", "http://localhost?q=x", "http://localhost#x", "http://localhost:bad", "http://localhost:70000"):
            with self.subTest(origin=origin):
                self.put(f'version=1\n[env.targets]\nbackend={json.dumps(origin)}\n[qa]\n')
                self.assertTrue(any(e["key"] == "env.targets.backend" for e in self.config().errors))

    def test_recipe_and_health_targets_require_https_outside_loopback(self) -> None:
        usages = [
            '[env.services]\nhealth=["backend:/health"]\n',
            '[qa.cleanup]\nkind="http"\ntarget="backend"\nmethod="DELETE"\npath="/users/{email}"\nexpect=[200]\n',
        ]
        origins = (
            ("http://localhost:8000", "ok"),
            ("http://127.0.0.1:8000", "ok"),
            ("http://[::1]:8000", "ok"),
            ("http://app.LOCALHOST:8000", "ok"),
            ("https://staging.example.com", "ok"),
            ("https://192.168.1.10:8443", "ok"),
            ("http://staging.example.com", "invalid"),
            ("http://192.168.1.10:8000", "invalid"),
            ("http://127.0.0.2:8000", "invalid"),
            ("http://localhost.evil.com:8000", "invalid"),
            ("http://[2001:db8::1]:8000", "invalid"),
        )
        for usage in usages:
            for origin, state in origins:
                with self.subTest(usage=usage, origin=origin):
                    self.put(f'version=1\n[env.targets]\nbackend={json.dumps(origin)}\n[qa]\n' + usage)
                    report = self.config().report()
                    self.assertEqual(report["state"], state, report["errors"])
                    if state == "invalid":
                        self.assertTrue(any(error["key"] == "env.targets.backend" for error in report["errors"]), report["errors"])

    def test_trust_cannot_override_cleartext_recipe_target_from_local_config(self) -> None:
        recipe = '[qa.cleanup]\nkind="http"\ntarget="backend"\nmethod="DELETE"\npath="/users/{email}"\nexpect=[200]\n'
        self.put('version=1\n[env.targets]\nbackend="https://staging.example.com"\n[qa]\n' + recipe)
        secure = self.config()
        secure.accept(secure.trust_hash)
        self.put('[env.targets]\nbackend="http://staging.example.com"\n', ".av/local.toml")
        cfg = self.config()
        self.assertEqual(cfg.state, "invalid")
        self.assertTrue(any(error["file"] == ".av/local.toml" and error["key"] == "env.targets.backend" for error in cfg.errors), cfg.errors)
        with self.assertRaises(ConfigError):
            cfg.accept(cfg.trust_hash)
        result = self.cli("config")
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertEqual(json.loads(result.stdout)["state"], "invalid")

    def test_unused_cleartext_target_retains_the_normal_origin_trust_gate(self) -> None:
        self.put('version=1\n[env.targets]\nbackend="http://staging.example.com"\n[qa]\n')
        cfg = self.config()
        self.assertEqual(cfg.state, "ok")
        self.assertEqual(cfg.trust, "new")
        cfg.accept(cfg.trust_hash)
        self.assertEqual(self.config().trust, "trusted")

    def test_unknown_env_and_other_plugin_are_ignored_for_trust(self) -> None:
        self.put(BASE + '[env.browser]\nengine = "chromium"\n')
        cfg = self.config()
        self.assertEqual(cfg.report()["state"], "ok")
        self.assertEqual(cfg.warnings[0]["key"], "env.browser")
        before = cfg.trust_hash
        self.put(BASE + '[env.browser]\nengine = "chromium"\n[delivery]\nanything="cmd:evil"\n')
        self.assertEqual(self.config().trust_hash, before)
        self.assertEqual(self.config().report()["state"], "ok")

    def test_source_restrictions_by_file(self) -> None:
        for source in ("env:GH_TOKEN", "file:/tmp/private.env#X"):
            with self.subTest(source=source):
                self.put(BASE + f'[env.values]\nX={json.dumps(source)}\n')
                self.assertTrue(any(e["key"] == "env.values.X" for e in self.config().errors))
                self.put(BASE)
                self.put(f'[env.values]\nX={json.dumps(source)}\n', ".av/local.toml")
                self.assertEqual(self.config().report()["state"], "ok")
                (self.repo / ".av/local.toml").unlink()
        self.put(BASE + '[qa.users.user]\nemail="env:QA_USER_EMAIL"\npassword="literal:secret"\ndescription="plain user"\n')
        self.assertTrue(any(e["key"] == "qa.users.user.password" for e in self.config().errors))
        self.put(BASE + '[env.secrets]\nX="literal:secret"\n')
        self.assertTrue(self.config().errors)
        self.put(BASE + '[env.stores.main]\nkind="sql"\nengine="postgres"\nhost="localhost"\nport=5432\nuser="user"\nname="db"\npassword="literal:secret"\n')
        self.assertFalse(self.config().errors)
        self.put((self.repo / ".av/config.toml").read_text().replace('host="localhost"', 'host="db.example.com"'))
        self.assertTrue(any(e["key"] == "env.stores.main.password" for e in self.config().errors))

    def test_unignored_personal_config_is_not_loaded_or_trusted(self) -> None:
        self.put(BASE)
        self.put("", ".git/info/exclude")
        self.put('[env.values]\nX="env:GITHUB_TOKEN"\nFILE="file:/tmp/private.env#X"\n'
                 '[env.secrets]\nSECRET="literal:private-secret"\n', ".av/local.toml")
        cfg = self.config()
        report = cfg.report()
        self.assertEqual(report["state"], "invalid", report)
        self.assertTrue(any(error["file"] == ".av/local.toml" and error["key"] == "document"
                            for error in report["errors"]), report["errors"])
        self.assertNotIn("X", cfg.values)
        self.assertNotIn("env.values.X", cfg.provenance)
        with self.assertRaises(ConfigError):
            cfg.accept(cfg.trust_hash)
        result = self.cli("config")
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertEqual(json.loads(result.stdout)["state"], "invalid")
        self.assertNotIn("private-secret", result.stdout + result.stderr)

    def test_tracked_personal_config_is_rejected_even_with_ignore_rules(self) -> None:
        self.put(BASE)
        self.put('[env.values]\nX="env:GITHUB_TOKEN"\n', ".av/local.toml")
        subprocess.run(["git", "add", "-f", "--", ".av/local.toml"], cwd=self.repo, check=True)
        subprocess.run(["git", "-c", "user.name=QA", "-c", "user.email=qa@test.local",
                        "commit", "-qm", "tracked personal config"], cwd=self.repo, check=True)
        cfg = self.config()
        self.assertEqual(cfg.state, "invalid", cfg.errors)
        self.assertTrue(any(error["file"] == ".av/local.toml" and error["key"] == "document"
                            for error in cfg.errors), cfg.errors)
        self.assertNotIn("X", cfg.values)
        with self.assertRaises(ConfigError):
            cfg.accept(cfg.trust_hash)
        proposal = {"config_text": BASE, "gitignore_add": [".av/local.toml"], "allowed_keys": []}
        preview = cfg.preview(proposal)
        self.assertFalse(preview["ok"])
        self.assertTrue(any(error["file"] == ".av/local.toml" and error["key"] == "document"
                            for error in preview["errors"]), preview["errors"])
        self.assertFalse((self.repo / ".gitignore").exists())

    def test_preview_can_ignore_an_untracked_personal_config(self) -> None:
        self.put(BASE)
        self.put("", ".git/info/exclude")
        self.put('[env.values]\nX="env:GITHUB_TOKEN"\n', ".av/local.toml")
        cfg = self.config()
        self.assertEqual(cfg.state, "invalid", cfg.errors)
        proposal = {"config_text": BASE, "gitignore_add": [".av/local.toml"], "allowed_keys": []}
        preview = cfg.preview(proposal)
        self.assertTrue(preview["ok"], preview["errors"])
        self.assertFalse((self.repo / ".gitignore").exists())
        result = cfg.apply(proposal, preview["snapshot"], preview["trust_hash"])
        self.assertTrue(result["applied"])
        current = self.config()
        self.assertEqual(current.state, "ok", current.errors)
        self.assertEqual(current.values["X"], "env:GITHUB_TOKEN")
        self.assertEqual(current.provenance["env.values.X"], ".av/local.toml")

    def test_personal_symlink_name_must_be_ignored_not_only_its_target(self) -> None:
        self.put(BASE)
        self.put(".av/ignored.toml\n", ".git/info/exclude")
        self.put('[env.values]\nX="env:GITHUB_TOKEN"\n', ".av/ignored.toml")
        (self.repo / ".av/local.toml").symlink_to("ignored.toml")
        cfg = self.config()
        self.assertEqual(cfg.state, "invalid", cfg.errors)
        self.assertNotIn("X", cfg.values)
        self.put(".av/local.toml\n", ".git/info/exclude")
        cfg = self.config()
        self.assertEqual(cfg.state, "ok", cfg.errors)
        self.assertEqual(cfg.values["X"], "env:GITHUB_TOKEN")

    def test_trust_transitions_and_stale_accept(self) -> None:
        self.put(BASE)
        self.assertEqual(self.config().trust, "not-required")
        self.put(BASE + '[env.values]\nX="cmd:printf x"\n')
        cfg = self.config()
        self.assertEqual(cfg.trust, "new")
        cfg.accept(cfg.trust_hash)
        self.assertEqual(self.config().trust, "trusted")
        self.put('# changed comment\n' + BASE + '[env.values]\nX="cmd:printf x"\n')
        self.assertEqual(self.config().trust, "trusted")
        for fragment in ('[env.values]\nX="cmd:printf y"\n', '[env.values]\nX="env:AV_X"\n', '[env.values]\nX="env:AV_Y"\n', 'fix="approve"\nmutations="deny"\n'):
            with self.subTest(fragment=fragment):
                old = self.config().trust_hash
                self.put(BASE + fragment)
                cfg = self.config()
                self.assertEqual(cfg.trust, "changed")
                with self.assertRaises(ConfigError):
                    cfg.accept(old)
                cfg.accept(cfg.trust_hash)
        cfg = self.config()
        self.assertEqual(cfg.trust_subset, {"qa.fix": "approve", "qa.mutations": "deny"})
        self.put(BASE + 'fix="auto"\nmutations="deny"\n')
        cfg = self.config()
        self.assertEqual(cfg.trust, "changed")
        self.assertEqual(cfg.trust_subset, {"qa.fix": "auto", "qa.mutations": "deny"})
        cfg.accept(cfg.trust_hash)
        self.put(BASE + 'fix="auto"\nmutations="deny"\nstart_services="auto"\n')
        cfg = self.config()
        self.assertEqual(cfg.trust, "changed")
        self.assertEqual(cfg.trust_subset["qa.start_services"], "auto")
        cfg.accept(cfg.trust_hash)
        old = cfg.trust_hash
        self.put(BASE + 'fix="off"\n')
        with self.assertRaises(ConfigError):
            cfg.accept(old)

    def test_local_password_changes_hash_but_is_never_displayed(self) -> None:
        self.put(BASE)
        self.put('[qa.users.user]\nemail="literal:user@test.local"\npassword="literal:never-display-me"\ndescription="plain user"\n', ".av/local.toml")
        cfg = self.config()
        old = cfg.trust_hash
        self.assertNotIn("never-display-me", json.dumps(cfg.report()))
        result = self.cli("config")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("never-display-me", result.stdout + result.stderr)
        proposal = {"config_text": BASE, "gitignore_add": [], "allowed_keys": []}
        self.assertNotIn("never-display-me", json.dumps(cfg.preview(proposal)))
        self.put('[qa.users.user]\nemail="literal:user@test.local"\npassword="literal:different"\ndescription="plain user"\n', ".av/local.toml")
        self.assertNotEqual(self.config().trust_hash, old)
        self.put('[qa.users.user]\npassword="literal:never-display-me"\nunknown="literal:never-display-me"\n', ".av/local.toml")
        result = self.cli("config")
        self.assertEqual(result.returncode, 2)
        self.assertNotIn("never-display-me", result.stdout + result.stderr)

    def test_trust_mask_preserves_commands_and_masks_only_value_sources(self) -> None:
        command = "literal:; touch HIDDEN_LOGIN_COMMAND_RAN"
        recipe = {"kind": "command", "run": command}
        services = {"up": command, "prepare": [command], "down": command}
        subset = {
            "env.secrets.KEY": "literal:private-secret",
            "env.values.VALUE": "literal:private-value",
            "env.stores.main.password": "literal:private-database",
            "qa.users.user.email": "literal:private-email",
            "qa.users.user.password": "literal:private-static-password",
            "qa.users.user.id": "literal:private-id",
            "qa.cleanup": recipe,
            "qa.cleanup.run": command,
            "env.services": services,
            "env.services.up": command,
        }
        shown = mask(subset, VALUE_SOURCE_KEYS)
        self.assertEqual(shown, {
            **{key: "literal:***" for key in subset if key.startswith(("env.secrets.", "env.values.", "env.stores.main.password", "qa.users."))},
            "qa.cleanup": recipe,
            "qa.cleanup.run": command,
            "env.services": services,
            "env.services.up": command,
        })
        self.assertEqual(subset["env.secrets.KEY"], "literal:private-secret")

    def test_value_source_prefixes_are_invalid_in_commands_and_http_templates(self) -> None:
        for source in SOURCE_KINDS:
            value = source + "touch must-not-exist"
            cases = [(f'[qa.cleanup]\nkind="command"\nrun={json.dumps(value)}\n', "qa.cleanup.run")]
            cases.extend([
                (f'[env.services]\nhealth=["backend:/"]\nup="true"\n{key}={json.dumps(value)}\n' if key == "down" else
                 f'[env.services]\nhealth=["backend:/"]\nup={json.dumps(value)}\n', f"env.services.{key}")
                for key in ("up", "down")
            ])
            cases.append((f'[env.services]\nhealth=["backend:/"]\nup="true"\nprepare=["true", {json.dumps(value)}]\n', "env.services.prepare.1"))
            http = '[qa.cleanup]\nkind="http"\ntarget="backend"\nmethod="DELETE"\nexpect=[200]\n'
            cases.extend([
                (http + f'path={json.dumps(value)}\n', "qa.cleanup.path"),
                (http + f'path="/users/{{email}}"\nheaders={{x={json.dumps(value)}}}\n', "qa.cleanup.headers.x"),
                (http + f'path="/users/{{email}}"\nform={{x={json.dumps(value)}}}\n', "qa.cleanup.form.x"),
                (http + f'path="/users/{{email}}"\njson={{nested={{items=[{{x={json.dumps(value)}}}]}}}}\n', "qa.cleanup.json.nested.items.0.x"),
            ])
            for text, key in cases:
                with self.subTest(source=source, key=key):
                    self.put(BASE + text)
                    report = self.config().report()
                    self.assertEqual(report["state"], "invalid")
                    self.assertTrue(any(error["file"] == ".av/config.toml" and error["key"] == key for error in report["errors"]), report["errors"])
                    self.assertNotIn(value, json.dumps(report))

    def test_preview_repair_shows_old_command_verbatim_but_masks_value_literals(self) -> None:
        command = "literal:; touch HIDDEN_LOGIN_COMMAND_RAN"
        old = BASE + f'[qa.cleanup]\nkind="command"\nrun={json.dumps(command)}\n'
        old += '[env.values]\nVALUE="literal:private-value"\n'
        self.put(old)
        proposal = {"config_text": old.replace(command, "printf safe"), "gitignore_add": [], "allowed_keys": ["qa.cleanup.run"]}
        preview = self.config().preview(proposal)
        self.assertTrue(preview["ok"], preview["errors"])
        self.assertIn(command, preview["diff"])
        self.assertNotIn("private-value", json.dumps(preview))
        self.assertEqual(preview["trust_subset"]["env.values.VALUE"], "literal:***")
        self.assertEqual(preview["trust_subset"]["qa.cleanup"]["run"], "printf safe")

    def test_user_field_and_value_name_collisions(self) -> None:
        text = BASE + '[qa.users.user]\nemail="literal:user@test.local"\npassword="env:QA_PASSWORD"\nid="literal:u1"\ndescription="plain user"\n'
        self.put(text)
        cfg = self.config()
        self.assertFalse(cfg.errors)
        self.assertIn("QA_USER_ID", cfg.report()["exposed"])
        self.assertEqual(cfg.report()["users"], {"user": "plain user"})
        self.assertNotIn("personas", cfg.report())
        for name in ("USER_EMAIL", "SUPPORT_TOKEN", "CAPTURED_X"):
            with self.subTest(name=name):
                self.put(text + f'[env.values]\n{name}="env:AV_X"\n')
                self.assertTrue(any(e["key"] == f"env.values.{name}" for e in self.config().errors))
        self.put(text.replace("qa.users.user", "qa.users.captured_owner"))
        self.assertTrue(any(e["error"] == "reserved user name" for e in self.config().errors))
        self.put(BASE + '[env.values]\nx="env:AV_X"\nX="env:AV_Y"\n')
        self.assertTrue(any(e["key"] == "env.values.X" for e in self.config().errors))

    def test_cleanup_destination_changes_require_trust(self) -> None:
        text = BASE + '[qa.cleanup]\nkind="http"\ntarget="backend"\nmethod="DELETE"\npath="/users/{email}"\nexpect=[200]\n'
        self.put(text)
        cfg = self.config()
        cfg.accept(cfg.trust_hash)
        self.put(text.replace("/users/", "/accounts/"))
        cfg = self.config()
        self.assertEqual(cfg.trust, "changed")
        self.assertEqual(cfg.trust_subset["qa.cleanup"]["path"], "/accounts/{email}")

    def test_preview_section_guard_and_no_writes(self) -> None:
        original = BASE + 'fix="approve"\n[delivery]\n# keep this comment\nmode="old"\n'
        self.put(original)
        cfg = self.config()
        proposal = {"config_text": original.replace('fix="approve"', 'fix="auto"'), "gitignore_add": [], "allowed_keys": ["qa.fix"]}
        preview = cfg.preview(proposal)
        self.assertTrue(preview["ok"], preview["errors"])
        self.assertEqual((self.repo / ".av/config.toml").read_text(), original)
        self.assertFalse((self.repo / ".gitignore").exists())
        for replacement in ('mode="new"', '# changed comment\nmode="old"'):
            with self.subTest(replacement=replacement):
                changed = {**proposal, "config_text": proposal["config_text"].replace('mode="old"', replacement)}
                self.assertFalse(cfg.preview(changed)["ok"])
        inline = 'version=1\n[env.targets]\nbackend = "http://localhost:8000"\n[qa]\nusers={user={email="literal:user@test.local", password="env:QA_PASSWORD", description="plain user"}}\n[delivery]\n# protected\nmode="old"\n'
        self.put(inline)
        proposal = {"config_text": inline.replace('description="plain user"', 'description="owner"'), "gitignore_add": [], "allowed_keys": ["qa.users.user.description"]}
        self.assertTrue(self.config().preview(proposal)["ok"])
        proposal["config_text"] = proposal["config_text"].replace("user@test.local", "other@test.local")
        self.assertFalse(self.config().preview(proposal)["ok"])
        self.put(BASE)
        proposal = {"config_text": BASE + 'fix="auto"\n', "gitignore_add": [], "allowed_keys": ["qa.fix"]}
        self.assertTrue(self.config().preview(proposal)["ok"])
        quoted = 'version=1\n[qa]\n["qa.extra"]\n# another plugin table\nvalue="old"\n'
        self.put(quoted)
        proposal = {"config_text": quoted.replace('value="old"', 'value="new"'), "gitignore_add": [], "allowed_keys": ["qa"]}
        self.assertFalse(self.config().preview(proposal)["ok"])

    def test_create_preview_accepts_bootstrap_layout_and_root_comments(self) -> None:
        proposals = (
            'version = 1\n\n[qa]\n',
            '# Project configuration\nversion = 1\n\n[qa]\n',
            'version = 1\n\n# ---- shared environment (any plugin) ----\n\n'
            '[env.targets]  # named origins\nbackend = "http://localhost:8000"\n\n'
            '# ---- QA ----\n\n[qa]\nfix = "approve"\n',
        )
        for text in proposals:
            with self.subTest(text=text):
                proposal = {"config_text": text, "gitignore_add": [], "allowed_keys": ["version", "env", "qa"]}
                preview = self.config().preview(proposal)
                self.assertTrue(preview["ok"], preview["errors"])
                self.assertFalse((self.repo / ".av/config.toml").exists())
                self.assertFalse((self.repo / ".gitignore").exists())
                proposal["config_text"] = text + '[delivery]\nmode = "auto"\n'
                self.assertFalse(self.config().preview(proposal)["ok"])

    def test_extend_preview_accepts_separators_and_qa_header_comments(self) -> None:
        original = 'version = 1\n\n[env.targets]\nbackend = "http://localhost:8000"\n'
        self.put(original)
        cfg = self.config()
        self.assertEqual(cfg.state, "missing-table")
        for separator in ("\n", "\n# QA policy\n# Derived from settings.py\n"):
            with self.subTest(separator=separator):
                text = original + separator + '[qa]\nfix = "approve"\n'
                proposal = {"config_text": text, "gitignore_add": [], "allowed_keys": ["qa"]}
                preview = cfg.preview(proposal)
                self.assertTrue(preview["ok"], preview["errors"])
                self.assertEqual((self.repo / ".av/config.toml").read_text(), original)
                self.assertFalse((self.repo / ".gitignore").exists())

    def test_preview_ignores_blank_lines_but_protects_header_comments(self) -> None:
        original = BASE + '\n# Delivery settings\n# Derived from delivery.toml\n[delivery]\nmode = "old"\n'
        self.put(original)
        text = original.replace('[delivery]\n', '\n[delivery]\n\n \t\n')
        proposal = {"config_text": text, "gitignore_add": [], "allowed_keys": ["qa"]}
        preview = self.config().preview(proposal)
        self.assertTrue(preview["ok"], preview["errors"])
        proposal["config_text"] = original.replace("# Delivery settings", "# Changed delivery settings")
        self.assertFalse(self.config().preview(proposal)["ok"])

    def first_proposal(self) -> dict[str, object]:
        return {"config_text": BASE + '[env.values]\nX="file:.av/secrets.local.env#X"\n', "gitignore_add": [".av/local.toml", ".av/secrets.local.env"], "allowed_keys": ["version", "env", "qa"]}

    def test_first_run_virtual_ignore_and_apply(self) -> None:
        cfg = self.config()
        proposal = self.first_proposal()
        preview = cfg.preview(proposal)
        self.assertTrue(preview["ok"], preview["errors"])
        self.assertFalse((self.repo / ".av/config.toml").exists())
        result = cfg.apply(proposal, preview["snapshot"], preview["trust_hash"])
        self.assertTrue(result["applied"])
        self.assertEqual((self.repo / ".av/config.toml").read_text(), proposal["config_text"])
        self.assertIn(".av/secrets.local.env", (self.repo / ".gitignore").read_text())
        self.assertEqual(self.config().trust, "trusted")

    def test_transactions_reject_nonstandard_gitignore_entries_without_writes(self) -> None:
        original_ignore = ".env*\nservice-key.txt\n"
        self.put(BASE)
        self.put(original_ignore, ".gitignore")
        self.put("fixture-only\n", ".env.private")
        before = {path: path.read_bytes() for path in (self.repo / ".av/config.toml", self.repo / ".gitignore")}
        cfg = self.config()
        proposal = {"config_text": BASE, "gitignore_add": [], "allowed_keys": []}
        approved = cfg.preview(proposal)
        self.assertTrue(approved["ok"], approved["errors"])
        invalid_entries = (
            "!service-key.txt", "!.env*", ".av/*", "**/.av/local.toml",
            "/.av/local.toml", "./.av/local.toml", ".av/local.toml ",
            "", ".av/local.toml\n!.env*", ".av/local.toml\r", ".av/local.toml\x00",
            "unrelated.txt", 1, None, [".av/local.toml"],
        )
        for entry in invalid_entries:
            with self.subTest(entry=entry):
                invalid = {**proposal, "gitignore_add": [".av/local.toml", entry]}
                with self.assertRaises(ConfigError):
                    cfg.preview(invalid)
                with self.assertRaises(ConfigError):
                    cfg.apply(invalid, approved["snapshot"], approved["trust_hash"])
                self.assertEqual(before, {path: path.read_bytes() for path in before})
                ignored = subprocess.run(["git", "-C", str(self.repo), "check-ignore", "-q", ".env.private"], check=False)
                self.assertEqual(ignored.returncode, 0)

    def test_preview_shows_gitignore_changes_and_applies_only_standard_entries(self) -> None:
        proposal = {"config_text": BASE, "gitignore_add": [".av/local.toml", ".av/secrets.local.env"], "allowed_keys": []}
        for original_ignore in (None, ".env*\n# unrelated private-comment\n", ".av/local.toml\n", ".av/local.toml\n.av/secrets.local.env\n"):
            with self.subTest(original_ignore=original_ignore):
                self.put(BASE)
                ignore_path = self.repo / ".gitignore"
                if original_ignore is None:
                    ignore_path.unlink(missing_ok=True)
                else:
                    self.put(original_ignore, ".gitignore")
                cfg = self.config()
                preview = cfg.preview(proposal)
                self.assertTrue(preview["ok"], preview["errors"])
                added = [line for line in proposal["gitignore_add"] if line not in (original_ignore or "").splitlines()]
                if added:
                    self.assertIn("--- .gitignore\n+++ proposed .gitignore\n", preview["diff"])
                    for line in added:
                        self.assertIn("\n+" + line, preview["diff"])
                else:
                    self.assertEqual(preview["diff"], "")
                self.assertNotIn("private-comment", preview["diff"])
                self.assertEqual(ignore_path.read_text() if ignore_path.exists() else None, original_ignore)
                self.assertTrue(cfg.apply(proposal, preview["snapshot"], preview["trust_hash"])["applied"])
                self.assertEqual(ignore_path.read_text(), (original_ignore or "") + "".join(line + "\n" for line in added))
                self.assertEqual((self.repo / ".av/config.toml").read_text(), BASE)
                ignored = subprocess.run(["git", "-C", str(self.repo), "check-ignore", ".av/local.toml", ".av/secrets.local.env"], capture_output=True, text=True, check=False)
                self.assertEqual(ignored.returncode, 0, ignored.stderr)
                self.assertEqual(ignored.stdout.splitlines(), [".av/local.toml", ".av/secrets.local.env"])

    def test_cas_no_write_for_either_changed_file(self) -> None:
        for name in (".av/config.toml", ".gitignore"):
            with self.subTest(name=name):
                cfg = self.config()
                proposal = self.first_proposal()
                preview = cfg.preview(proposal)
                self.put("# concurrent\n", name)
                before = {p: p.read_bytes() if p.exists() else None for p in (self.repo / ".av/config.toml", self.repo / ".gitignore")}
                with self.assertRaises(ConfigError):
                    cfg.apply(proposal, preview["snapshot"], preview["trust_hash"])
                self.assertEqual(before, {p: p.read_bytes() if p.exists() else None for p in before})
                (self.repo / name).unlink()

    def test_failed_postwrite_rolls_back_only_owned_bytes(self) -> None:
        for changed_file in (None, ".av/config.toml", ".gitignore"):
            with self.subTest(changed_file=changed_file):
                cfg = self.config()
                proposal = self.first_proposal()
                preview = cfg.preview(proposal)

                def reject_after_write(text: str, ignore: str) -> dict[str, object]:
                    report = Config(self.repo, state_home=self.state, config_text=text, gitignore_text=ignore).report()
                    if (self.repo / ".av/config.toml").exists():
                        if changed_file is not None:
                            (self.repo / changed_file).write_text("# concurrent\n")
                        report["errors"] = [{"file": ".av/config.toml", "key": "version", "error": "post-write validation failed"}]
                    return report

                transaction = ConfigTransaction(self.repo, reject_after_write, cfg.accept, value_source_keys=VALUE_SOURCE_KEYS)
                with self.assertRaises(ConfigError):
                    transaction.apply(proposal, preview["snapshot"], preview["trust_hash"])
                for name in (".av/config.toml", ".gitignore"):
                    path = self.repo / name
                    if name == changed_file:
                        self.assertEqual(path.read_text(), "# concurrent\n")
                        path.unlink()
                    else:
                        self.assertFalse(path.exists())

    def test_sources_resolve_and_errors_do_not_echo_values(self) -> None:
        self.put('X="private-value"\n', ".av/secrets.local.env")
        self.put('.av/secrets.local.env\n', ".gitignore")
        resolver = ValueSources(self.repo, plugin_prefix="QA_", environ={"AV_X": "private-value"})
        for source in ("literal:private-value", "env:AV_X", "file:.av/secrets.local.env#X", "cmd:printf private-value"):
            with self.subTest(source=source):
                self.assertEqual(resolver.resolve(source, "env.values.X", trusted=True), "private-value")
        for source in ("env:MISSING", "file:.av/secrets.local.env#MISSING", "cmd:printf private-value; exit 1", "cmd:true"):
            with self.subTest(source=source):
                with self.assertRaises(ConfigError) as error:
                    resolver.resolve(source, "env.values.X", trusted=True)
                self.assertIn("env.values.X", str(error.exception))
                self.assertNotIn("private-value", str(error.exception))
        with self.assertRaises(ConfigError):
            resolver.resolve("cmd:touch should-not-exist", "env.values.X", trusted=False)
        self.assertFalse((self.repo / "should-not-exist").exists())
        timed = ValueSources(self.repo, plugin_prefix="QA_", timeout=0.2)
        with self.assertRaises(ConfigError) as error:
            timed.resolve("cmd:/bin/sleep 10", "env.values.X", trusted=True)
        self.assertIn("timed out", str(error.exception))

    def test_dependency_declarations_are_rejected_without_execution(self) -> None:
        sources = '[env.values]\nX="cmd:touch source-ran; printf value"\n'
        cases = (
            ('[qa.cleanup]\nkind="command"\nrun="sh scripts/cleanup.sh"\nenv=["value.X"]\n', "qa.cleanup.env"),
            ('[env.services]\nhealth=["backend:/"]\nup="sh scripts/up.sh"\nenv={up=["value.X"]}\n', "env.services.env"),
        )
        for fragment, key in cases:
            with self.subTest(key=key):
                self.put(BASE + sources + fragment)
                self.assertIn({"file": ".av/config.toml", "key": key, "error": "unknown key"}, self.config().errors)
                self.assertFalse((self.repo / "source-ran").exists())
        self.put(BASE + sources + '[env.source_env]\n"env.values.X"=["value.X"]\n')
        config = self.config()
        self.assertEqual(config.errors, [])
        self.assertIn({"file": ".av/config.toml", "key": "env.source_env", "warning": "unknown environment sub-table"}, config.warnings)
        self.assertFalse((self.repo / "source-ran").exists())

    def test_runtime_command_sources_use_validated_keys_and_engine_executor(self) -> None:
        command = 'printf executed >> source-count; printf runtime-source-value; printf executor-stderr >&2'
        self.put(BASE + '[env.values]\nX=' + json.dumps("cmd:" + command) + '\n')
        config = self.config()
        self.assertEqual(config.state, "ok")
        config.accept(config.trust_hash)
        config = self.config()
        directory = Path(self.tmp.name) / "run"
        directory.mkdir()
        run = Run(self.repo, "test-run", directory, {}, {})
        with Runtime(run, config) as runtime:
            with self.assertRaises(ConfigError):
                runtime.resolve("cmd:touch unvalidated-source; printf invalid", "env.values.UNKNOWN")
            self.assertFalse((self.repo / "unvalidated-source").exists())
            self.assertEqual(runtime.named("value", "X"), "runtime-source-value")
            self.assertEqual(runtime.named("value", "X"), "runtime-source-value")
        self.assertEqual((self.repo / "source-count").read_text(), "executed")
        log = (directory / "engine.log").read_text()
        self.assertIn("env.values.X", log)
        self.assertNotIn("executor-stderr", log)
        self.assertNotIn("runtime-source-value", log)

    def test_cli_preview_apply_trust_tools_and_usage(self) -> None:
        proposal = self.first_proposal()
        path = self.put(json.dumps(proposal), "proposal.json")
        result = self.cli("config", "preview", str(path))
        self.assertEqual(result.returncode, 0, result.stderr)
        preview = json.loads(result.stdout)
        result = self.cli("config", "apply", str(path), "--snapshot", preview["snapshot"], "--approved-hash", preview["trust_hash"])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(json.loads(result.stdout)["applied"])
        result = self.cli("trust", "accept", "stale")
        self.assertEqual(result.returncode, 1)
        self.assertIn("error", json.loads(result.stdout))
        tools = json.loads(self.cli("tools").stdout)
        self.assertEqual(set(tools), {"curl", "jq", "perl_json_pp", "psql", "mysql", "sqlite3", "redis_cli", "httpie"})
        result = self.cli("no-such-command", "literal:do-not-echo")
        self.assertEqual(result.returncode, 2)
        self.assertNotIn("do-not-echo", result.stdout + result.stderr)
        self.assertIn("error", json.loads(result.stdout))

    def test_hash_mismatch_restores_existing_snapshot(self) -> None:
        original = BASE + 'fix="approve"\n'
        self.put(original)
        self.put("# original ignore\n", ".gitignore")
        cfg = self.config()
        proposal = {"config_text": original.replace('fix="approve"', 'fix="auto"'), "gitignore_add": [".av/local.toml"], "allowed_keys": ["qa.fix"]}
        preview = cfg.preview(proposal)
        self.assertTrue(preview["ok"], preview["errors"])
        with self.assertRaises(ConfigError):
            cfg.apply(proposal, preview["snapshot"], "stale")
        self.assertEqual((self.repo / ".av/config.toml").read_text(), original)
        self.assertEqual((self.repo / ".gitignore").read_text(), "# original ignore\n")

    def test_sources_are_not_executed_by_config_or_preview(self) -> None:
        text = BASE + '[env.values]\nX="cmd:touch must-not-exist; printf value"\n'
        self.put(text)
        cfg = self.config()
        self.assertEqual(cfg.state, "ok")
        self.assertTrue(cfg.preview({"config_text": text, "gitignore_add": [], "allowed_keys": []})["ok"])
        self.assertEqual(self.cli("config").returncode, 0)
        self.assertFalse((self.repo / "must-not-exist").exists())

    def test_trust_is_scoped_to_plugin_and_real_repository(self) -> None:
        self.put(BASE + 'fix="auto"\n')
        cfg = self.config()
        cfg.accept(cfg.trust_hash)
        other = TrustStore(self.repo, "delivery", self.state)
        self.assertEqual(other.status({"delivery.policy.fix": "auto"}), "new")
        alias = Path(self.tmp.name) / "alias"
        alias.symlink_to(self.repo, target_is_directory=True)
        self.assertEqual(Config(alias, state_home=self.state).trust, "trusted")
        another = Path(self.tmp.name) / "another"
        another.mkdir()
        self.assertEqual(TrustStore(another, "qa", self.state).status(cfg.trust_subset), "new")
        self.put(BASE + 'fix="auto"\n[delivery]\npolicy={fix="auto"}\n')
        self.assertEqual(self.config().trust, "trusted")

    def test_gitignore_semantics_and_parameterized_source_prefix(self) -> None:
        source = "file:.av/secrets.local.env#X"
        resolver = ValueSources(self.repo, plugin_prefix="DELIVERY_")
        self.assertIsNotNone(resolver.validate(source, "env.values.X"))
        self.put(".av/*.env\n!.av/secrets.local.env\n", ".gitignore")
        self.assertIsNotNone(resolver.validate(source, "env.values.X"))
        virtual = ValueSources(self.repo, plugin_prefix="DELIVERY_", gitignore_text=".av/*.env\n")
        self.assertIsNone(virtual.validate(source, "env.values.X"))
        self.assertIsNone(resolver.validate("env:DELIVERY_TOKEN", "delivery.token"))
        self.assertIsNotNone(resolver.validate("env:DELIVERY_TOKEN", "env.values.X"))
        self.assertIsNotNone(resolver.validate("file:../secret.env#X", "delivery.token", local=True))

    def test_malformed_types_and_documents_do_not_crash_or_echo(self) -> None:
        for text in ('version=1\n[qa]\nfix=[]\n', 'version=1\n[qa.cleanup]\nkind=[]\n', 'version=1\n[env.stores.main]\nkind=[]\n', 'version=1\n[qa]\nbudget=1\n', 'version=1\n[qa]\nusers=1\n', 'version=1\n[env]\nvalues=1\n', 'version=1\n[qa]\nbudget="sensitive\n'):
            with self.subTest(text=text):
                self.put(text)
                result = self.cli("config")
                self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                self.assertEqual(json.loads(result.stdout)["state"], "invalid")
                self.assertNotIn("sensitive", result.stdout + result.stderr)

    def test_sensitive_env_sources_and_qa_gates_are_pinned(self) -> None:
        cases = ('[env.browser]\nsource="cmd:printf value"\n', '[env.browser]\nsources=["env:AV_BROWSER"]\n', '[env.targets]\nremote="https://example.com"\n', '[env.stores.main]\nkind="sql"\nengine="postgres"\nhost="localhost"\nuser="user"\nname="db"\npassword="env:AV_DB"\n', 'fix="off"\n', 'mutations="deny"\n', 'start_services="auto"\n')
        for section in cases:
            with self.subTest(section=section):
                self.put(('version=1\n[qa]\n' if section.startswith("[env.targets]") else BASE) + section)
                cfg = self.config()
                self.assertFalse(cfg.errors)
                self.assertNotEqual(cfg.trust, "not-required")

    def test_recipe_json_rejects_non_json_toml_values(self) -> None:
        for value in ("2000-01-01", "nan", "inf"):
            with self.subTest(value=value):
                self.put(BASE + f'[qa.cleanup]\nkind="http"\ntarget="backend"\nmethod="DELETE"\npath="/users/{{email}}"\nexpect=[200]\njson={{x={value}}}\n')
                result = self.cli("config")
                self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                report = json.loads(result.stdout)
                self.assertTrue(any(error["key"] == "qa.cleanup.json.x" for error in report["errors"]))

    def test_nested_placeholder_and_shell_environment_syntax(self) -> None:
        self.put(BASE + '[qa.cleanup]\nkind="http"\ntarget="backend"\nmethod="DELETE"\npath="/users/{email}"\nexpect=[200]\njson={items=[{secret="{secret.MISSING}"}]}\n')
        self.assertTrue(any("json.items" in error["key"] for error in self.config().errors))
        self.put(BASE + '[qa.cleanup]\nkind="command"\nrun="printf \\"${QA_EMAIL}\\""\n')
        self.assertFalse(self.config().errors)

    def test_command_recipe_braces_are_not_http_placeholders(self) -> None:
        cases = (
            ("cleanup", "curl -s localhost | jq -c '{count: .count}'"),
            ("cleanup", 'printf \'{"count":"%s"}\' "$T"'),
            ("cleanup", "echo {email}"),
        )
        for recipe, command in cases:
            with self.subTest(recipe=recipe, command=command):
                self.put(BASE + f'[qa.{recipe}]\nkind="command"\nrun={json.dumps(command)}\n')
                report = self.config().report()
                self.assertEqual(report["state"], "ok", report["errors"])
                self.assertEqual(report["errors"], [])

    def test_cli_rejects_malformed_transaction_with_usage_exit(self) -> None:
        path = self.put('{"config_text":"literal:never-display-me"}', "bad-proposal.json")
        result = self.cli("config", "preview", str(path))
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertIn("error", json.loads(result.stdout))
        self.assertNotIn("never-display-me", result.stdout + result.stderr)
        proposal = {"config_text": 'version=1\n[qa..policy]\npassword="literal:never-display-me"\n', "gitignore_add": [], "allowed_keys": ["version", "qa"]}
        path.write_text(json.dumps(proposal))
        result = self.cli("config", "preview", str(path))
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertFalse(json.loads(result.stdout)["ok"])
        self.assertNotIn("never-display-me", result.stdout + result.stderr)

    def test_empty_xdg_state_home_keeps_trust_outside_repository(self) -> None:
        self.put(BASE + 'fix="auto"\n')
        home = Path(self.tmp.name) / "home"
        home.mkdir()
        result = subprocess.run(
            [sys.executable, str(SCRIPTS / "qa.py"), "trust", "accept", self.config().trust_hash, "--repo", str(self.repo)],
            cwd=self.repo, env={**os.environ, "XDG_STATE_HOME": "", "HOME": str(home)},
            capture_output=True, text=True, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse((self.repo / "av-marketplace").exists())
        self.assertEqual(Config(self.repo, state_home=home / ".local/state").trust, "trusted")



class OriginTests(unittest.TestCase):
    def test_loopback_edges(self) -> None:
        for host, expected in (("127.0.0.1.evil.com", False), ("0.0.0.0", False), ("::1", True), ("app.localhost", True), ("LOCALHOST", True)):
            with self.subTest(host=host):
                self.assertEqual(is_loopback(host), expected)
        self.assertEqual(parse_origin("http://[::1]:8000"), ("http", "::1", 8000))
        self.assertEqual(parse_origin("https://EXAMPLE.com"), ("https", "example.com", 443))


if __name__ == "__main__":
    unittest.main()
