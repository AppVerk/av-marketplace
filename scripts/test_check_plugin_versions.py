#!/usr/bin/env python3
"""Unit tests for check_plugin_versions: per-skill VERSION files.

Run: python3 scripts/test_check_plugin_versions.py
"""

from __future__ import annotations

import contextlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))

import check_plugin_versions as cpv


def _write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


class TempMarketplace:
    """A minimal marketplace with one plugin "demo" at one version in all four places."""

    def __init__(self, root: Path, version: str = "1.2.3") -> None:
        self.root = root
        _write(root / "plugins/demo/.claude-plugin/plugin.json", json.dumps({"name": "demo", "version": version}))
        _write(root / ".claude-plugin/marketplace.json", json.dumps({"plugins": [{"name": "demo", "version": version}]}))
        _write(
            root / "README.md",
            "# M\n\n## Available Plugins\n\n| Plugin | Version |\n|---|---|\n"
            f"| [Demo](docs/plugins/demo.md) | {version} |\n\n## Other\n",
        )
        _write(root / "docs/plugins/demo.md", f"# Demo\n\n**Version:** {version}\n")

    def skill_version(self, skill: str, text: str) -> None:
        _write(self.root / f"plugins/demo/skills/{skill}/VERSION", text)

    def run(self) -> tuple[int, str]:
        patches = {
            "REPO_ROOT": self.root,
            "PLUGINS_DIR": self.root / "plugins",
            "MARKETPLACE_JSON": self.root / ".claude-plugin" / "marketplace.json",
            "README_MD": self.root / "README.md",
            "DOCS_DIR": self.root / "docs" / "plugins",
        }
        out, err = io.StringIO(), io.StringIO()
        with contextlib.ExitStack() as stack:
            for name, value in patches.items():
                stack.enter_context(mock.patch.object(cpv, name, value))
            stack.enter_context(contextlib.redirect_stdout(out))
            stack.enter_context(contextlib.redirect_stderr(err))
            code = cpv.main([])
        return code, out.getvalue() + err.getvalue()


class TestSkillVersions(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.market = TempMarketplace(Path(self._tmp.name))

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_plugin_without_skill_version_files_passes(self) -> None:
        code, out = self.market.run()
        self.assertEqual(code, 0, out)
        self.assertIn("[demo] 1.2.3 (OK)", out)

    def test_matching_skill_versions_pass(self) -> None:
        self.market.skill_version("alpha", "1.2.3\n")
        self.market.skill_version("beta", "  1.2.3  \n")
        code, out = self.market.run()
        self.assertEqual(code, 0, out)

    def test_skill_version_mismatch_fails_and_names_the_file(self) -> None:
        self.market.skill_version("alpha", "1.2.3\n")
        self.market.skill_version("beta", "1.2.2\n")
        code, out = self.market.run()
        self.assertEqual(code, 1, out)
        self.assertIn("version mismatch", out)
        self.assertIn("skills/beta/VERSION=1.2.2", out)

    def test_empty_skill_version_file_is_missing(self) -> None:
        self.market.skill_version("alpha", "\n")
        code, out = self.market.run()
        self.assertEqual(code, 1, out)
        self.assertIn("missing version in: skills/alpha/VERSION", out)

    def test_skill_versions_are_read_in_name_order(self) -> None:
        self.market.skill_version("zeta", "1.2.3")
        self.market.skill_version("alpha", "1.2.3")
        with mock.patch.object(cpv, "PLUGINS_DIR", self.market.root / "plugins"):
            self.assertEqual(
                list(cpv._skill_versions("demo")),
                ["skills/alpha/VERSION", "skills/zeta/VERSION"],
            )


if __name__ == "__main__":
    unittest.main()
