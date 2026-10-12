"""Behavioral checks for code-review's opt-in policy and documentation paths.

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
BASE = "version = 1\n[code-review]\n"
KEY = "code-review.auto_accept_min_confidence"


class AutoAcceptTests(unittest.TestCase):
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
        path.write_text(text, encoding="utf-8")
        return path

    def cli(self, *args: str, repo: Path | None = None) -> subprocess.CompletedProcess[str]:
        # Insert before doc-paths' --, never among its path arguments.
        index = 3 if args[:2] == ("trust", "accept") else 1
        command = [*args[:index], "--repo", str(repo or self.repo), *args[index:]]
        return self.raw_cli(*command)

    def raw_cli(self, *args: str, cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(SCRIPT), *args],
            cwd=cwd or self.repo,
            env={**os.environ, "XDG_STATE_HOME": str(self.state)},
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
        self.assertEqual(report["policy"], {"auto_accept_min_confidence": None})
        self.assertEqual(report["trust"], "not-required")

    def test_missing_table_uses_disabled_policy(self) -> None:
        self.put("version = 1\n")
        report = self.report(self.cli("config"))
        self.assertEqual(report["state"], "missing-table")
        self.assertEqual(report["policy"], {"auto_accept_min_confidence": None})
        self.assertEqual(report["trust"], "not-required")

    def test_empty_table_does_not_need_trust(self) -> None:
        self.put(BASE)
        report = self.report(self.cli("config"))
        self.assertEqual(report["state"], "ok")
        self.assertEqual(report["policy"], {"auto_accept_min_confidence": None})
        self.assertEqual(report["trust_subset"], {})
        self.assertEqual(report["trust"], "not-required")

    def test_threshold_is_trusted_and_changes_require_new_approval(self) -> None:
        self.put(BASE + "auto_accept_min_confidence = 90\n")
        report = self.report(self.cli("config"))
        self.assertEqual(report["state"], "ok")
        self.assertEqual(report["policy"], {"auto_accept_min_confidence": 90})
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
        for value in ("69", "101", "-1", '"90"', "true", "90.5"):
            with self.subTest(value=value):
                self.put(BASE + f"auto_accept_min_confidence = {value}\n")
                report = self.report(self.cli("config"), 2)
                self.assertEqual(report["state"], "invalid")
                self.assertIn(
                    {"file": ".av/config.toml", "key": KEY, "error": "expected an integer from 70 to 100"},
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
                self.assertEqual(report["policy"], {"auto_accept_min_confidence": value})
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
        self.assertEqual(report["policy"], {"auto_accept_min_confidence": 95})
        self.assertEqual(cast(dict[str, str], report["provenance"])[KEY], ".av/local.toml")

    def test_local_override_cannot_supply_shared_plugin_presence(self) -> None:
        self.put("[code-review]\nauto_accept_min_confidence = 95\n", ".av/local.toml")
        self.assertEqual(self.report(self.cli("config"))["state"], "missing-file")
        self.put("version = 1\n")
        self.assertEqual(self.report(self.cli("config"))["state"], "missing-table")

    def test_shared_environment_sources_are_trust_pinned(self) -> None:
        self.put(BASE + 'auto_accept_min_confidence = 90\n[env.values]\nGREETING = "env:AV_GREETING"\n')
        report = self.report(self.cli("config"))
        self.assertEqual(report["trust_subset"], {KEY: 90, "env.values.GREETING": "env:AV_GREETING"})
        self.assertEqual(report["trust"], "new")

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
        self.assertEqual(report["policy"], {"auto_accept_min_confidence": 90})

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
