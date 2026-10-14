"""Behavioral checks for code-review's opt-in policy, secret masking and documentation paths.

Run: PYTHONDONTWRITEBYTECODE=1 uv run python3 plugins/code-review/tests/test_auto_accept.py
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from typing import cast

SCRIPT = Path(__file__).resolve().parents[1] / "skills/decision-gate/scripts/auto_accept.py"
sys.path.insert(0, str(SCRIPT.parent))

from av_config.errors import InvalidConfig
from auto_accept import AutoAcceptConfig

BASE = "version = 1\n[code-review]\n"
KEY = "code-review.auto_accept_min_confidence"
GATE_KEY = "code-review.auto_accept_gate"


class AutoAcceptTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.repo = Path(self.tmp.name) / "repo"
        self.repo.mkdir()
        subprocess.run(["git", "init", "-q", str(self.repo)], check=True)
        self.state = Path(self.tmp.name) / "state"
        self.config_home = Path(self.tmp.name) / "config"
        self.user_file = self.config_home / "av/config.toml"
        self.put(".av/local.toml\n", ".git/info/exclude")

    def put(self, text: str, name: str = ".av/config.toml") -> Path:
        path = self.repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def put_user(self, text: str) -> None:
        self.user_file.parent.mkdir(parents=True, exist_ok=True)
        self.user_file.write_text(text, encoding="utf-8")

    def cli(self, *args: str, repo: Path | None = None) -> subprocess.CompletedProcess[str]:
        # Insert before doc-paths' --, never among its path arguments.
        index = 3 if args[:2] == ("trust", "accept") else 1
        command = [*args[:index], "--repo", str(repo or self.repo), *args[index:]]
        return self.raw_cli(*command)

    def raw_cli(self, *args: str, cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(SCRIPT), *args],
            cwd=cwd or self.repo,
            env={
                **os.environ, "XDG_STATE_HOME": str(self.state),
                "XDG_CONFIG_HOME": str(self.config_home),
            },
            capture_output=True,
            text=True,
            check=False,
        )

    def report(self, result: subprocess.CompletedProcess[str], code: int = 0) -> dict[str, object]:
        self.assertEqual(result.returncode, code, result.stderr or result.stdout)
        self.assertEqual(result.stderr, "")
        value = json.loads(result.stdout)
        self.assertIsInstance(value, dict)
        return cast(dict[str, object], value)

    def test_missing_file_uses_disabled_policy(self) -> None:
        report = self.report(self.cli("config"))
        self.assertEqual(report["state"], "missing-file")
        self.assertEqual(report["policy"], {"auto_accept_min_confidence": None, "auto_accept_gate": "analyst"})
        self.assertEqual(report["trust"], "not-required")

    def test_missing_table_uses_disabled_policy(self) -> None:
        self.put("version = 1\n")
        report = self.report(self.cli("config"))
        self.assertEqual(report["state"], "missing-table")
        self.assertEqual(report["policy"], {"auto_accept_min_confidence": None, "auto_accept_gate": "analyst"})
        self.assertEqual(report["trust"], "not-required")

    def test_empty_table_does_not_need_trust(self) -> None:
        self.put(BASE)
        report = self.report(self.cli("config"))
        self.assertEqual(report["state"], "ok")
        self.assertEqual(report["policy"], {"auto_accept_min_confidence": None, "auto_accept_gate": "analyst"})
        self.assertEqual(report["trust_subset"], {})
        self.assertEqual(report["trust"], "not-required")

    def test_threshold_is_trusted_and_changes_require_new_approval(self) -> None:
        self.put(BASE + "auto_accept_min_confidence = 90\n")
        report = self.report(self.cli("config"))
        self.assertEqual(report["state"], "ok")
        self.assertEqual(report["policy"], {"auto_accept_min_confidence": 90, "auto_accept_gate": "analyst"})
        self.assertEqual(report["trust"], "new")
        self.assertEqual(report["trust_subset"], {KEY: 90})
        approved_hash = cast(str, report["trust_hash"])
        self.assertEqual(
            self.report(self.cli("trust", "accept", approved_hash)),
            {"trusted": approved_hash},
        )
        self.assertEqual(self.report(self.cli("config"))["trust"], "trusted")
        self.put(BASE + "auto_accept_min_confidence = 80\n")
        self.assertEqual(self.report(self.cli("config"))["trust"], "changed")

    def test_trust_is_scoped_to_each_worktree_real_path(self) -> None:
        self.put(BASE + "auto_accept_min_confidence = 90\n")
        subprocess.run(["git", "add", ".av/config.toml"], cwd=self.repo, check=True)
        subprocess.run(
            ["git", "-c", "user.name=t", "-c", "user.email=t@example.invalid", "commit", "-qm", "config"],
            cwd=self.repo,
            check=True,
        )
        approved_hash = cast(str, self.report(self.cli("config"))["trust_hash"])
        self.report(self.cli("trust", "accept", approved_hash))
        worktree = Path(self.tmp.name) / "wt"
        subprocess.run(["git", "worktree", "add", "-q", str(worktree)], cwd=self.repo, check=True)
        self.assertEqual(self.report(self.cli("config", repo=worktree))["trust"], "new")
        self.assertEqual(self.report(self.cli("config"))["trust"], "trusted")

    def test_threshold_rejects_wrong_types_and_out_of_range_values(self) -> None:
        for value in ("69", "101", "-1", "0", '"90"', '"false"', "true", "90.5"):
            with self.subTest(value=value):
                self.put(BASE + f"auto_accept_min_confidence = {value}\n")
                report = self.report(self.cli("config"), 2)
                self.assertEqual(report["state"], "invalid")
                self.assertIn(
                    {"file": ".av/config.toml", "key": KEY, "error": "expected an integer from 70 to 100, or false"},
                    cast(list[dict[str, str]], report["errors"]),
                )
                self.assertNotIn("policy", report)
                self.assertEqual(report["trust_subset"], {})

    def test_threshold_accepts_both_boundaries(self) -> None:
        for value in (70, 100):
            with self.subTest(value=value):
                self.put(BASE + f"auto_accept_min_confidence = {value}\n")
                report = self.report(self.cli("config"))
                self.assertEqual(report["state"], "ok")
                self.assertEqual(report["policy"], {"auto_accept_min_confidence": value, "auto_accept_gate": "analyst"})
                self.assertEqual(report["trust_subset"], {KEY: value})

    def test_unknown_plugin_key_is_invalid(self) -> None:
        self.put(BASE + "foo = 1\n")
        report = self.report(self.cli("config"), 2)
        self.assertIn(
            {"file": ".av/config.toml", "key": "code-review.foo", "error": "unknown key"},
            cast(list[dict[str, str]], report["errors"]),
        )
        self.assertNotIn("policy", report)

    def test_plugin_value_must_be_a_table(self) -> None:
        self.put("version = 1\ncode-review = 5\n")
        report = self.report(self.cli("config"), 2)
        self.assertIn(
            {"file": ".av/config.toml", "key": "code-review", "error": "expected a table"},
            cast(list[dict[str, str]], report["errors"]),
        )
        self.assertNotIn("policy", report)

    def test_stale_hash_cannot_record_trust(self) -> None:
        self.put(BASE + "auto_accept_min_confidence = 90\n")
        self.assertEqual(
            self.report(self.cli("trust", "accept", "0" * 64), 1),
            {"error": "trust hash changed; preview the current configuration"},
        )
        self.assertEqual(self.report(self.cli("config"))["trust"], "new")

    def test_invalid_configuration_cannot_be_trusted(self) -> None:
        self.put(BASE + "auto_accept_min_confidence = 69\n")
        self.assertEqual(
            self.report(self.cli("trust", "accept", "0" * 64), 2),
            {"error": "invalid config cannot be trusted"},
        )

    def test_local_override_has_local_provenance(self) -> None:
        self.put(BASE)
        self.put("[code-review]\nauto_accept_min_confidence = 95\n", ".av/local.toml")
        report = self.report(self.cli("config"))
        self.assertEqual(report["state"], "ok")
        self.assertEqual(report["policy"], {"auto_accept_min_confidence": 95, "auto_accept_gate": "analyst"})
        self.assertEqual(cast(dict[str, str], report["provenance"])[KEY], ".av/local.toml")

    def test_local_override_cannot_supply_shared_plugin_presence(self) -> None:
        for value in ("95", '"x"'):
            with self.subTest(value=value, state="missing-file"):
                self.put(
                    f"[code-review]\nauto_accept_min_confidence = {value}\n",
                    ".av/local.toml",
                )
                report = self.report(self.cli("config"))
                self.assertEqual(report["state"], "missing-file")
                self.assertEqual(report["policy"], {"auto_accept_min_confidence": None, "auto_accept_gate": "analyst"})
                self.assertEqual(report["trust_subset"], {})
                self.assertEqual(report["trust"], "not-required")

        self.put("[code-review]\nauto_accept_min_confidence = 95\n", ".av/local.toml")
        self.put("version = 1\n")
        report = self.report(self.cli("config"))
        self.assertEqual(report["state"], "missing-table")
        self.assertEqual(report["policy"], {"auto_accept_min_confidence": None, "auto_accept_gate": "analyst"})
        self.assertEqual(report["trust_subset"], {})
        self.assertEqual(report["trust"], "not-required")

        self.put('version = 1\n[env.values]\nGREETING = "env:AV_GREETING"\n')
        report = self.report(self.cli("config"))
        self.assertEqual(report["state"], "missing-table")
        self.assertEqual(report["policy"], {"auto_accept_min_confidence": None, "auto_accept_gate": "analyst"})
        self.assertEqual(report["trust_subset"], {"env.values.GREETING": "env:AV_GREETING"})
        self.assertEqual(report["trust"], "new")

    def test_user_only_policy_does_not_require_repository_trust(self) -> None:
        self.put_user(BASE + "auto_accept_min_confidence = 90\n")
        report = self.report(self.cli("config"))
        self.assertFalse((self.repo / ".av").exists())
        self.assertEqual(report["state"], "ok")
        self.assertEqual(report["policy"], {
            "auto_accept_min_confidence": 90, "auto_accept_gate": "analyst",
        })
        self.assertEqual(report["trust"], "not-required")
        self.assertEqual(report["trust_subset"], {})
        self.assertEqual(cast(dict[str, str], report["provenance"])[KEY], str(self.user_file))

    def test_user_decision_model_gate_does_not_require_trust(self) -> None:
        self.put_user(BASE + 'auto_accept_min_confidence = 90\nauto_accept_gate = "decision-model"\n')
        report = self.report(self.cli("config"))
        self.assertEqual(report["state"], "ok")
        self.assertEqual(report["policy"], {
            "auto_accept_min_confidence": 90, "auto_accept_gate": "decision-model",
        })
        self.assertEqual(report["trust"], "not-required")
        self.assertEqual(report["trust_subset"], {})
        provenance = cast(dict[str, str], report["provenance"])
        self.assertEqual(provenance[KEY], str(self.user_file))
        self.assertEqual(provenance[GATE_KEY], str(self.user_file))

    def test_repository_decision_model_gate_is_pinned_but_analyst_is_not(self) -> None:
        self.put_user(BASE + "auto_accept_min_confidence = 90\n")
        for gate, subset, trust in (
            ("decision-model", {GATE_KEY: "decision-model"}, "new"),
            ("analyst", {}, "not-required"),
        ):
            with self.subTest(gate=gate):
                self.put(BASE + f'auto_accept_gate = "{gate}"\n')
                report = self.report(self.cli("config"))
                self.assertEqual(report["policy"], {
                    "auto_accept_min_confidence": 90, "auto_accept_gate": gate,
                })
                self.assertEqual(report["trust_subset"], subset)
                self.assertEqual(report["trust"], trust)
                self.assertEqual(cast(dict[str, str], report["provenance"])[GATE_KEY], ".av/config.toml")

    def test_shared_false_vetoes_user_threshold_and_local_can_override(self) -> None:
        self.put_user(BASE + "auto_accept_min_confidence = 90\n")
        self.put(BASE + "auto_accept_min_confidence = false\n")
        report = self.report(self.cli("config"))
        self.assertEqual(report["state"], "ok")
        self.assertEqual(report["policy"], {
            "auto_accept_min_confidence": None, "auto_accept_gate": "analyst",
        })
        self.assertEqual(report["trust"], "not-required")
        self.assertEqual(report["trust_subset"], {})
        self.assertEqual(cast(dict[str, str], report["provenance"])[KEY], ".av/config.toml")
        self.put("[code-review]\nauto_accept_min_confidence = 95\n", ".av/local.toml")
        report = self.report(self.cli("config"))
        self.assertEqual(report["policy"], {
            "auto_accept_min_confidence": 95, "auto_accept_gate": "analyst",
        })
        self.assertEqual(report["trust_subset"], {KEY: 95})
        self.assertEqual(report["trust"], "new")
        self.assertEqual(cast(dict[str, str], report["provenance"])[KEY], ".av/local.toml")

    def test_local_policy_overrides_user_only_table_and_is_pinned(self) -> None:
        self.put_user(BASE + "auto_accept_min_confidence = 90\n")
        self.put(
            '[code-review]\nauto_accept_min_confidence = 95\nauto_accept_gate = "decision-model"\n',
            ".av/local.toml",
        )
        report = self.report(self.cli("config"))
        self.assertEqual(report["state"], "ok")
        self.assertEqual(report["policy"], {
            "auto_accept_min_confidence": 95, "auto_accept_gate": "decision-model",
        })
        self.assertEqual(report["trust_subset"], {KEY: 95, GATE_KEY: "decision-model"})
        self.assertEqual(report["trust"], "new")
        provenance = cast(dict[str, str], report["provenance"])
        self.assertEqual(provenance[KEY], ".av/local.toml")
        self.assertEqual(provenance[GATE_KEY], ".av/local.toml")

    def test_false_is_allowed_in_every_layer_without_pinning(self) -> None:
        for layer in ("user", "shared", "local"):
            with self.subTest(layer=layer):
                self.put_user(BASE + "auto_accept_min_confidence = false\n")
                if layer == "shared":
                    self.put(BASE + "auto_accept_min_confidence = false\n")
                elif layer == "local":
                    self.put("[code-review]\nauto_accept_min_confidence = false\n", ".av/local.toml")
                report = self.report(self.cli("config"))
                self.assertEqual(report["state"], "ok")
                self.assertEqual(report["policy"], {
                    "auto_accept_min_confidence": None, "auto_accept_gate": "analyst",
                })
                self.assertEqual(report["trust_subset"], {})
                self.assertEqual(report["trust"], "not-required")

    def test_gate_rejects_unknown_names_and_wrong_types(self) -> None:
        for value in ('"jev"', "1", "false"):
            with self.subTest(value=value):
                self.put(BASE + f"auto_accept_gate = {value}\n")
                report = self.report(self.cli("config"), 2)
                self.assertEqual(report["state"], "invalid")
                self.assertIn(
                    {"file": ".av/config.toml", "key": GATE_KEY, "error": 'expected "analyst" or "decision-model"'},
                    cast(list[dict[str, str]], report["errors"]),
                )
                self.assertNotIn("policy", report)
                self.assertEqual(report["trust_subset"], {})

    def test_user_values_use_policy_validation_with_user_provenance(self) -> None:
        for text, key, message in (
            ("auto_accept_min_confidence = true\n", KEY, "expected an integer from 70 to 100, or false"),
            ('auto_accept_gate = "jev"\n', GATE_KEY, 'expected "analyst" or "decision-model"'),
        ):
            with self.subTest(key=key):
                self.put_user(BASE + text)
                report = self.report(self.cli("config"), 2)
                self.assertEqual(report["state"], "invalid")
                self.assertIn(
                    {"file": str(self.user_file), "key": key, "error": message},
                    cast(list[dict[str, str]], report["errors"]),
                )
                self.assertNotIn("policy", report)

    def test_user_forbidden_keys_and_environment_disable_the_policy(self) -> None:
        for text, key in (("foo = 1\n", "code-review.foo"), ("[env]\n", "env")):
            with self.subTest(key=key):
                self.put_user(BASE + text)
                report = self.report(self.cli("config"), 2)
                self.assertEqual(report["state"], "invalid")
                self.assertIn(
                    {"file": str(self.user_file), "key": key, "error": "not allowed in the user config"},
                    cast(list[dict[str, str]], report["errors"]),
                )
                self.assertNotIn("policy", report)

    def test_explicit_config_home_is_preserved_when_accepting_trust(self) -> None:
        self.put_user(BASE + "auto_accept_min_confidence = 90\n")
        self.put(BASE + 'auto_accept_gate = "decision-model"\n')
        config = AutoAcceptConfig(self.repo, state_home=self.state, config_home=self.config_home)
        self.assertEqual(config.trust_subset, {GATE_KEY: "decision-model"})
        self.assertEqual(config.accept(config.trust_hash), {"trusted": config.trust_hash})
        reloaded = AutoAcceptConfig(self.repo, state_home=self.state, config_home=self.config_home)
        self.assertEqual(reloaded.trust, "trusted")
        self.assertEqual(reloaded.report()["policy"], {
            "auto_accept_min_confidence": 90, "auto_accept_gate": "decision-model",
        })
        self.put_user(BASE + "foo = 1\n")
        with self.assertRaisesRegex(InvalidConfig, "invalid config cannot be trusted"):
            config.accept(config.trust_hash)

    def test_shared_environment_sources_are_trust_pinned(self) -> None:
        self.put(BASE + 'auto_accept_min_confidence = 90\n[env.values]\nGREETING = "env:AV_GREETING"\n')
        report = self.report(self.cli("config"))
        self.assertEqual(report["trust_subset"], {KEY: 90, "env.values.GREETING": "env:AV_GREETING"})
        self.assertEqual(report["trust"], "new")

    def test_literal_store_password_is_masked_in_trust_report(self) -> None:
        self.put(
            BASE + 'auto_accept_min_confidence = 90\n'
            '[env.stores.db]\nkind = "sql"\nengine = "postgres"\n'
            'host = "localhost"\nuser = "u"\nname = "db"\npassword = "literal:hunter2"\n'
        )
        result = self.cli("config")
        report = self.report(result)
        self.assertEqual(report["state"], "ok")
        self.assertEqual(
            cast(dict[str, object], report["trust_subset"])["env.stores.db.password"],
            "literal:***",
        )
        self.assertNotIn("hunter2", result.stdout)

    def test_regular_file_is_not_a_repository_directory(self) -> None:
        regular_file = self.put("text", "regular-file")
        self.assertEqual(
            self.report(self.cli("config", repo=regular_file), 2),
            {"error": "repository root is not a directory"},
        )

    def test_repository_defaults_to_git_root(self) -> None:
        self.put(BASE + "auto_accept_min_confidence = 90\n")
        nested = self.repo / "nested"
        nested.mkdir()
        report = self.report(self.raw_cli("config", cwd=nested))
        self.assertEqual(report["policy"], {"auto_accept_min_confidence": 90, "auto_accept_gate": "analyst"})

    def test_repository_outside_git_needs_explicit_root(self) -> None:
        self.assertEqual(
            self.report(self.raw_cli("config", cwd=Path(self.tmp.name)), 2),
            {"error": "repository root unavailable; supply --repo"},
        )

    def test_documentation_paths_use_positive_lexical_identification(self) -> None:
        documentation = [
            "docs/guide.md", "./docs/api/index.mdx", "README.md", "src/pkg/readme.rst",
            "CHANGELOG.md", "doc/x.adoc",
        ]
        other = [
            "requirements.txt", "CMakeLists.txt", "plugins/x/skills/y/SKILL.md", "CLAUDE.md",
            "notes.md", "docs/conf.py", "../docs/a.md", "/etc/docs/a.md",
        ]
        report = self.report(self.cli("doc-paths", "--", *documentation, *other))
        self.assertEqual(report["documentation"], documentation)
        self.assertEqual(report["other"], other)
        reasons = cast(dict[str, str], report["reasons"])
        self.assertEqual(reasons["requirements.txt"], "not a documentation path")
        self.assertEqual(reasons["../docs/a.md"], "outside the repository")
        self.assertEqual(reasons["/etc/docs/a.md"], "outside the repository")

    def test_doc_paths_reject_loop_records_case_insensitively(self) -> None:
        documentation = [
            "docs/guide.md", "doc/guide.md", "README.md",
            "docs/reviews-guide.md", "docs/reviews-archive/guide.md",
            "docs/testing-guide/README.md", "docs/plans-archive/index.mdx",
        ]
        records = [
            "docs/reviews/finding.md", "docs/reviews/README.md",
            "docs/testing/reports/QA-001.md", "docs/testing/guide.mdx",
            "docs/plans/delivery.rst", "./docs/plans/CONTRIBUTING.adoc",
            "docs/Reviews/review.md", "DOCS/TESTING/reports/QA-001.md",
            "Docs/Plans/CHANGELOG.md",
        ]
        report = self.report(self.cli("doc-paths", "--", *documentation, *records))
        self.assertEqual(report, {
            "documentation": documentation,
            "other": records,
            "reasons": {path: "review or QA record, not documentation" for path in records},
        })

    def test_doc_paths_reject_physical_record_targets_through_parent_aliases(self) -> None:
        (self.repo / "doc").mkdir()
        (self.repo / "src").mkdir()
        records = []

        for name in ("reviews", "testing", "plans"):
            target = self.put("# Record\n", f"docs/{name}/README.md")
            (self.repo / "doc" / name).symlink_to(target.parent, target_is_directory=True)
            records.append(f"doc/{name}/README.md")

        (self.repo / "docs/ordinary").symlink_to("reviews", target_is_directory=True)
        (self.repo / "src/records").symlink_to("../docs/reviews", target_is_directory=True)
        (self.repo / "doc/dangling").symlink_to("../docs/plans/missing", target_is_directory=True)
        records.extend([
            "docs/ordinary/README.md", "src/records/README.md", "doc/dangling/new.md",
        ])
        report = self.report(self.cli("doc-paths", "--", *records))
        self.assertEqual(report, {
            "documentation": [],
            "other": records,
            "reasons": {path: "review or QA record, not documentation" for path in records},
        })

    def test_documentation_paths_follow_parent_symlinks_and_reject_file_symlinks(self) -> None:
        self.put("# Guide\n", "docs/guide.md")
        (self.repo / "src").mkdir()
        (self.repo / "docs/link").symlink_to("../src", target_is_directory=True)
        (self.repo / "docs/sym.md").symlink_to("../src/app.py")
        external = Path(self.tmp.name) / "external"
        external.mkdir()
        (self.repo / "docs/external").symlink_to(external, target_is_directory=True)
        (self.repo / "docs/dangling").symlink_to("../src/missing", target_is_directory=True)
        (self.repo / "docs/dangling-out").symlink_to(external / "missing", target_is_directory=True)
        documentation = ["docs/guide.md", "docs/new/page.md"]
        other = [
            "docs/link/notes.md", "docs/sym.md", "docs/external/guide.md",
            "docs/dangling/page.md", "docs/dangling-out/page.md",
        ]
        report = self.report(self.cli("doc-paths", "--", *documentation, *other))
        self.assertEqual(report["documentation"], documentation)
        self.assertEqual(report["other"], other)
        self.assertEqual(report["reasons"], {
            "docs/link/notes.md": "resolves to src/notes.md",
            "docs/sym.md": "symbolic link",
            "docs/external/guide.md": "outside the repository",
            "docs/dangling/page.md": "resolves to src/missing/page.md",
            "docs/dangling-out/page.md": "outside the repository",
        })

    def test_documentation_alias_may_resolve_to_another_documentation_directory(self) -> None:
        (self.repo / "docs").mkdir()
        (self.repo / "doc/shared").mkdir(parents=True)
        (self.repo / "docs/shared").symlink_to("../doc/shared", target_is_directory=True)
        report = self.report(self.cli("doc-paths", "--", "docs/shared/notes.md"))
        self.assertEqual(report, {"documentation": ["docs/shared/notes.md"], "other": [], "reasons": {}})

    def test_doc_paths_reject_symlink_loops_in_any_parent(self) -> None:
        (self.repo / "docs").mkdir()
        (self.repo / "docs/loop").symlink_to("loop", target_is_directory=True)
        (self.repo / "docs/cycle-a").symlink_to("cycle-b", target_is_directory=True)
        (self.repo / "docs/cycle-b").symlink_to("cycle-a", target_is_directory=True)
        paths = [
            "docs/loop/x.md",
            "docs/loop/new/deep/x.md",
            "docs/cycle-a/x.md",
            "docs/cycle-b/new/x.md",
        ]
        report = self.report(self.cli("doc-paths", "--", *paths))
        self.assertEqual(report, {
            "documentation": [],
            "other": paths,
            "reasons": {path: "unresolvable path" for path in paths},
        })

    def test_doc_paths_reject_unsafe_characters_before_other_rules(self) -> None:
        for path in ("docs/it's.md", "docs/a\tb.md", "docs/a\x7fb.md", "/outside/it's.md"):
            with self.subTest(path=path):
                report = self.report(self.cli("doc-paths", "--", path))
                self.assertEqual(report, {"documentation": [], "other": [path], "reasons": {path: "unsafe characters"}})

    def test_doc_paths_reject_empty_and_parent_segments(self) -> None:
        paths = ["", "./../docs/a.md", "docs/../README.md"]
        report = self.report(self.cli("doc-paths", "--", *paths))
        self.assertEqual(report, {
            "documentation": [], "other": paths,
            "reasons": {path: "outside the repository" for path in paths},
        })

    def test_doc_paths_require_at_least_one_path(self) -> None:
        self.assertEqual(
            self.report(self.cli("doc-paths", "--"), 2),
            {"error": "invalid command arguments; use --help"},
        )

    def test_command_help_and_usage_are_json(self) -> None:
        help_report = self.report(self.raw_cli("--help"))
        self.assertIn("doc-paths", cast(str, help_report["help"]))
        self.assertIn("trust", cast(str, help_report["help"]))
        self.assertEqual(
            self.report(self.raw_cli("unknown-command"), 2),
            {"error": "invalid command arguments; use --help"},
        )


if __name__ == "__main__":
    unittest.main()
