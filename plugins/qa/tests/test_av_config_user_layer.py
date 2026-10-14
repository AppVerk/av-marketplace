"""Behavioral checks for the opt-in personal plugin policy configuration layer.

Run: python3 -m unittest discover -s plugins/qa/tests -p 'test_*.py'
"""
from __future__ import annotations

from collections.abc import Collection
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from typing import cast

SCRIPTS = Path(__file__).resolve().parents[1] / "skills/engine/scripts"
sys.path.insert(0, str(SCRIPTS))

from av_config.files import Configuration
from av_config.files import default_config_home

TABLE = "code-review"
BASE = "version = 1\n[code-review]\n"


class UserLayerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.repo = Path(self.tmp.name) / "repo"
        self.repo.mkdir()
        subprocess.run(["git", "init", "-q", str(self.repo)], check=True)
        self.config_home = Path(self.tmp.name) / "config"
        self.user_file = self.config_home / "av/config.toml"
        self.put_repo(".av/local.toml\n", ".git/info/exclude")

    def put_repo(self, text: str, name: str = ".av/config.toml") -> Path:
        path = self.repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def put_user(self, text: str) -> None:
        self.user_file.parent.mkdir(parents=True, exist_ok=True)
        self.user_file.write_text(text, encoding="utf-8")

    def config(self, *, user_keys: Collection[str] = ("a", "b")) -> Configuration:
        return Configuration(
            self.repo, plugin_prefix="AV_", user_table=TABLE,
            user_keys=user_keys, config_home=self.config_home,
        )

    def set_env(self, key: str, value: str | None) -> None:
        previous = os.environ.get(key)
        self.addCleanup(self.restore_env, key, previous)
        self.restore_env(key, value)

    @staticmethod
    def restore_env(key: str, value: str | None) -> None:
        if value is None:
            os.environ.pop(key, None)
        else:
            os.environ[key] = value

    def assert_error(self, config: Configuration, key: str, error: str) -> None:
        self.assertIn({"file": config.user_label, "key": key, "error": error}, config.errors)
        self.assertEqual(config.state(TABLE), "invalid")

    def test_user_file_is_not_read_without_opt_in(self) -> None:
        for shared in (None, "version = 1\n[qa]\nfix = 'approve'\n"):
            with self.subTest(shared=shared):
                if shared is not None:
                    self.put_repo(shared)
                baseline = Configuration(self.repo, plugin_prefix="AV_", config_home=self.config_home)
                self.put_user("version = 1\n[qa]\nfix = 'auto'\n[code-review]\na = 1\n[env]\n")
                config = Configuration(self.repo, plugin_prefix="AV_", config_home=self.config_home)
                self.assertEqual(config.data, baseline.data)
                self.assertEqual(config.provenance, baseline.provenance)
                self.assertEqual(config.errors, baseline.errors)
                self.assertEqual(config.state("qa"), baseline.state("qa"))
                self.assertFalse(config.user_exists)
                self.assertFalse(config.from_user("qa.fix"))
                self.user_file.unlink()

    def test_user_only_table_supplies_plugin_presence_and_provenance(self) -> None:
        self.put_user(BASE + "a = 1\n")
        config = self.config(user_keys={"a", "b"})
        self.assertFalse(config.exists)
        self.assertTrue(config.user_exists)
        self.assertEqual(config.state(TABLE), "ok")
        self.assertEqual(config.data, {TABLE: {"a": 1}})
        self.assertEqual(config.provenance[f"{TABLE}.a"], str(self.user_file))
        self.assertEqual(config.user_label, str(self.user_file))
        self.assertTrue(config.from_user(f"{TABLE}.a"))
        self.assertFalse(config.from_user("version"))
        self.assertEqual(config.errors, [])
        self.assertEqual(config.env_sensitive_subset(), {})

    def test_repository_layers_override_user_values_without_losing_other_keys(self) -> None:
        self.put_user(BASE + "a = 1\nb = 1\n")
        self.put_repo(BASE + "a = 2\n")
        config = self.config()
        self.assertEqual(config.data[TABLE], {"a": 2, "b": 1})
        self.assertEqual(config.provenance[f"{TABLE}.a"], ".av/config.toml")
        self.assertEqual(config.provenance[f"{TABLE}.b"], config.user_label)
        self.assertFalse(config.from_user(f"{TABLE}.a"))
        self.assertTrue(config.from_user(f"{TABLE}.b"))
        self.put_repo("[code-review]\na = 3\n", ".av/local.toml")
        config = self.config()
        self.assertEqual(config.data[TABLE], {"a": 3, "b": 1})
        self.assertEqual(config.provenance[f"{TABLE}.a"], ".av/local.toml")
        self.assertFalse(config.from_user(f"{TABLE}.a"))
        self.assertTrue(config.from_user(f"{TABLE}.b"))

    def test_user_environment_is_forbidden_and_never_merged(self) -> None:
        self.put_user(BASE + "a = 1\n[env.values]\nTOKEN = 'env:TOKEN'\n")
        config = self.config()
        self.assert_error(config, "env", "not allowed in the user config")
        self.assertNotIn("env", config.data)
        self.assertEqual(config.env_sensitive_subset(), {})

    def test_unknown_user_keys_are_forbidden_and_never_merged(self) -> None:
        self.put_user(BASE + "a = 1\nc = 2\n")
        config = self.config()
        self.assert_error(config, f"{TABLE}.c", "not allowed in the user config")
        self.assertEqual(config.data[TABLE], {"a": 1})

    def test_user_version_must_be_schema_one(self) -> None:
        for version in ("", "version = 2\n", "version = true\n", "version = '1'\n"):
            with self.subTest(version=version):
                self.put_user(version + "[code-review]\na = 1\n")
                self.assert_error(self.config(), "version", "expected schema version 1")

    def test_other_user_tables_are_ignored(self) -> None:
        self.put_user(BASE + "a = 1\n[qa]\nanything = 42\n")
        config = self.config()
        self.assertEqual(config.data, {TABLE: {"a": 1}})
        self.assertEqual(config.errors, [])
        self.assertEqual(config.state("qa"), "missing-table")
        self.assertNotIn("qa", config.provenance)

    def test_non_table_user_top_level_keys_are_forbidden(self) -> None:
        self.put_user("version = 1\nother = 2\n[code-review]\na = 1\n")
        config = self.config()
        self.assert_error(config, "other", "not allowed in the user config")
        self.assertNotIn("other", config.data)

    def test_invalid_user_document_reports_its_file(self) -> None:
        for raw, error in ((b"version = 1\n[code-review", "invalid TOML"), (b"\xff", "invalid text encoding")):
            with self.subTest(error=error):
                self.user_file.parent.mkdir(parents=True, exist_ok=True)
                self.user_file.write_bytes(raw)
                config = self.config()
                self.assert_error(config, "document", error)
                self.assertTrue(config.user_exists)

    def test_file_and_table_absence_states(self) -> None:
        config = self.config()
        self.assertEqual(config.state(TABLE), "missing-file")
        self.assertFalse(config.user_exists)
        self.assertFalse(config.from_user(f"{TABLE}.a"))
        self.put_user("version = 1\n[qa]\nfix = 'auto'\n")
        config = self.config()
        self.assertEqual(config.state(TABLE), "missing-table")
        self.assertTrue(config.user_exists)
        self.assertEqual(config.data, {})

    def test_local_override_counts_when_only_user_table_supplies_presence(self) -> None:
        self.put_user(BASE + "a = 1\n")
        self.put_repo("[code-review]\na = 3\n", ".av/local.toml")
        config = self.config()
        self.assertFalse(config.exists)
        self.assertEqual(config.state(TABLE), "ok")
        self.assertEqual(config.data[TABLE], {"a": 3})
        self.assertEqual(config.provenance[f"{TABLE}.a"], ".av/local.toml")
        self.assertEqual(config.errors, [])

    def test_default_config_home_uses_xdg_and_labels_paths_under_home(self) -> None:
        home = Path(self.tmp.name) / "home"
        self.set_env("HOME", str(home))
        self.set_env("XDG_CONFIG_HOME", str(home / "settings"))
        self.config_home = home / "settings"
        self.user_file = self.config_home / "av/config.toml"
        self.put_user(BASE + "a = 1\n")
        config = Configuration(self.repo, plugin_prefix="AV_", user_table=TABLE, user_keys={"a"})
        self.assertEqual(default_config_home(), self.config_home)
        self.assertEqual(config.user_label, "~/settings/av/config.toml")
        self.assertEqual(config.provenance[f"{TABLE}.a"], config.user_label)
        self.assertEqual(cast(dict[str, object], config.data[TABLE])["a"], 1)

    def test_default_config_home_falls_back_when_xdg_is_missing_or_empty(self) -> None:
        home = Path(self.tmp.name) / "home"
        self.set_env("HOME", str(home))
        self.config_home = home / ".config"
        self.user_file = self.config_home / "av/config.toml"
        self.put_user(BASE + "a = 1\n")
        for value in (None, ""):
            with self.subTest(value=value):
                self.set_env("XDG_CONFIG_HOME", value)
                config = Configuration(self.repo, plugin_prefix="AV_", user_table=TABLE, user_keys={"a"})
                self.assertEqual(default_config_home(), self.config_home)
                self.assertEqual(config.user_label, "~/.config/av/config.toml")
                self.assertTrue(config.from_user(f"{TABLE}.a"))

    def test_default_config_home_keeps_external_labels_absolute(self) -> None:
        self.set_env("HOME", str(Path(self.tmp.name) / "home"))
        self.set_env("XDG_CONFIG_HOME", str(self.config_home))
        self.put_user(BASE + "a = 1\n")
        config = Configuration(self.repo, plugin_prefix="AV_", user_table=TABLE, user_keys={"a"})
        self.assertEqual(config.user_label, str(self.user_file))
        self.assertEqual(config.provenance[f"{TABLE}.a"], str(self.user_file))


if __name__ == "__main__":
    unittest.main()
