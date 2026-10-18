#!/usr/bin/env python3
"""Contract tests for the remote plugin checks of check_plugin_versions.

Run: python3 scripts/test_check_plugin_versions.py
"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from check_plugin_versions import check_remote_entries


SHA = "0123456789abcdef0123456789abcdef01234567"
HEADER = ["Plugin", "Version", "ID", "Claude Code", "OMP", "Description"]
ROW = ["[Remote](https://github.com/owner/remote)", "0.1.0", "`remote`", "✓", "✓", "Remote plugin"]
SOURCE_ERROR = (
    '[remote] remote source must be {"source": "github", "repo": "<owner>/<repo>", '
    '"ref": "v<version>", "sha": "<40-character commit SHA>"}'
)


def entry(**overrides: object) -> dict:
    source = {"source": "github", "repo": "owner/remote", "ref": "v0.1.0", "sha": SHA}
    return {"name": "remote", "version": "0.1.0", **overrides, "source": overrides.get("source", source)}


class RemoteEntryTest(unittest.TestCase):
    def check(self, plugin: dict, rows: list[list[str]] | None = None) -> tuple[list[str], list[str]]:
        local = {"name": "local", "source": "./plugins/local", "version": "1.0.0"}
        return check_remote_entries([local, plugin], HEADER, [ROW] if rows is None else rows)

    def test_pinned_entry_with_matching_readme_row_passes(self) -> None:
        self.assertEqual(self.check(entry()), ([], ["[remote] 0.1.0 (OK, remote owner/remote@v0.1.0)"]))

    def test_ref_must_name_the_catalog_version(self) -> None:
        source = {"source": "github", "repo": "owner/remote", "ref": "v0.0.9", "sha": SHA}
        self.assertEqual(self.check(entry(source=source)), (["[remote] source.ref is 'v0.0.9', expected 'v0.1.0'"], []))

    def test_sha_must_be_a_full_lowercase_commit(self) -> None:
        for sha in (SHA[:7], SHA.upper(), 7):
            with self.subTest(sha=sha):
                source = {"source": "github", "repo": "owner/remote", "ref": "v0.1.0", "sha": sha}
                self.assertEqual(self.check(entry(source=source)), (["[remote] source.sha must be a 40-character lowercase commit SHA"], []))

    def test_other_source_shapes_are_rejected(self) -> None:
        for source in (
            {"source": "url", "url": "https://github.com/owner/remote.git", "ref": "v0.1.0", "sha": SHA},
            {"source": "github", "repo": "owner/remote", "ref": "v0.1.0"},
            {"source": "github", "repo": "owner/remote", "ref": "v0.1.0", "sha": SHA, "path": "plugin"},
            {"source": "github", "repo": "remote", "ref": "v0.1.0", "sha": SHA},
        ):
            with self.subTest(source=source):
                self.assertEqual(self.check(entry(source=source)), ([SOURCE_ERROR], []))

    def test_missing_version_is_reported(self) -> None:
        plugin = entry()
        del plugin["version"]
        self.assertEqual(self.check(plugin), (["[remote] missing version in: marketplace.json"], []))

    def test_readme_version_must_match(self) -> None:
        row = [*ROW[:1], "0.0.9", *ROW[2:]]
        self.assertEqual(self.check(entry(), [row]), (["[remote] version mismatch: marketplace.json=0.1.0, README.md=0.0.9"], []))


if __name__ == "__main__":
    unittest.main()
