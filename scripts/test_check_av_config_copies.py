#!/usr/bin/env python3
"""Unit tests for check_av_config_copies.

Run: python3 scripts/test_check_av_config_copies.py
"""

from __future__ import annotations

import contextlib
import io
import sys
import tempfile
import unittest
from pathlib import Path

from check_av_config_copies import main


CANONICAL = "plugins/qa/skills/engine/scripts/av_config"
COPY = "plugins/code-review/skills/decision-gate/scripts/av_config"
REMEDIATION = (
    "Copy plugins/qa/skills/engine/scripts/av_config/ over every copy and "
    "bump each changed plugin's version."
)


class TestMain(unittest.TestCase):
    def _clean_files(self) -> dict[str, bytes]:
        package = {
            "__init__.py": b"# shared package\n",
            "errors.py": b"# errors\n",
            "trust.py": b"# trust\n",
        }
        return {
            f"{root}/{relative}": content
            for root in (CANONICAL, COPY)
            for relative, content in package.items()
        }

    def _run(
        self,
        files: dict[str, bytes],
        argv: list[str] | None = None,
        *,
        directories: tuple[str, ...] = (),
    ) -> tuple[int, str, str]:
        """Build a temporary plugins tree and capture the check's two streams."""

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            plugins = root / "plugins"
            plugins.mkdir()

            for relative in directories:
                (root / relative).mkdir(parents=True, exist_ok=True)

            for relative, content in files.items():
                target = root / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(content)

            stdout = io.StringIO()
            stderr = io.StringIO()

            with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                code = main([] if argv is None else argv, plugins_dir=plugins)

            return code, stdout.getvalue(), stderr.getvalue()

    def test_identical_copy_passes(self) -> None:
        code, stdout, stderr = self._run(self._clean_files())
        self.assertEqual(code, 0)
        self.assertEqual(
            stdout,
            f"av_config copies OK: 1 copy(ies) match {CANONICAL}\n",
        )
        self.assertEqual(stderr, "")

    def test_single_byte_difference_fails(self) -> None:
        files = self._clean_files()
        files[f"{COPY}/trust.py"] = b"# trusT\n"

        code, stdout, stderr = self._run(files)
        self.assertEqual(code, 1)
        self.assertEqual(stdout, "")
        self.assertEqual(
            stderr,
            f"{COPY}: trust.py differs from {CANONICAL}/trust.py\n"
            f"{REMEDIATION}\n",
        )

    def test_missing_file_fails(self) -> None:
        files = self._clean_files()
        del files[f"{COPY}/errors.py"]

        code, stdout, stderr = self._run(files)
        self.assertEqual(code, 1)
        self.assertEqual(stdout, "")
        self.assertEqual(stderr, f"{COPY}: missing errors.py\n{REMEDIATION}\n")

    def test_extra_file_fails(self) -> None:
        files = self._clean_files()
        files[f"{COPY}/notes.py"] = b"# extra file\n"

        code, stdout, stderr = self._run(files)
        self.assertEqual(code, 1)
        self.assertEqual(stdout, "")
        self.assertEqual(stderr, f"{COPY}: extra notes.py\n{REMEDIATION}\n")

    def test_cache_files_are_ignored(self) -> None:
        for relative in (
            "__pycache__/x.cpython-312.pyc",
            "__pycache__/notes.txt",
            "nested/__pycache__/notes.txt",
            "nested/x.pyc",
        ):
            with self.subTest(relative=relative):
                files = self._clean_files()
                files[f"{COPY}/{relative}"] = b"ignored\n"

                code, stdout, stderr = self._run(files)
                self.assertEqual(code, 0)
                self.assertIn("av_config copies OK: 1", stdout)
                self.assertEqual(stderr, "")

    def test_nested_files_are_compared_as_bytes(self) -> None:
        files = self._clean_files()
        files[f"{CANONICAL}/nested/data.bin"] = b"\xff\x00\x01"
        files[f"{COPY}/nested/data.bin"] = b"\xff\x00\x02"

        code, stdout, stderr = self._run(files)
        self.assertEqual(code, 1)
        self.assertEqual(stdout, "")
        self.assertIn(
            f"{COPY}: nested/data.bin differs from {CANONICAL}/nested/data.bin",
            stderr,
        )

    def test_all_differences_are_reported(self) -> None:
        files = self._clean_files()
        del files[f"{COPY}/errors.py"]
        files[f"{COPY}/notes.py"] = b"# extra file\n"
        files[f"{COPY}/trust.py"] = b"# trusT\n"

        code, stdout, stderr = self._run(files)
        self.assertEqual(code, 1)
        self.assertEqual(stdout, "")
        self.assertEqual(
            stderr,
            f"{COPY}: missing errors.py\n"
            f"{COPY}: extra notes.py\n"
            f"{COPY}: trust.py differs from {CANONICAL}/trust.py\n"
            f"{REMEDIATION}\n",
        )

    def test_multiple_copies_are_counted(self) -> None:
        files = self._clean_files()
        second_copy = "plugins/other/skills/config/scripts/av_config"
        files.update(
            {
                f"{second_copy}/{Path(relative).name}": content
                for relative, content in self._clean_files().items()
                if relative.startswith(f"{CANONICAL}/")
            }
        )

        code, stdout, stderr = self._run(files)
        self.assertEqual(code, 0)
        self.assertIn("av_config copies OK: 2", stdout)
        self.assertEqual(stderr, "")

    def test_no_copy_is_an_error(self) -> None:
        files = {
            relative: content
            for relative, content in self._clean_files().items()
            if relative.startswith(f"{CANONICAL}/")
        }
        code, stdout, stderr = self._run(files)
        self.assertEqual(code, 2)
        self.assertEqual(stdout, "")
        self.assertTrue(stderr.startswith("error: "))
        self.assertIn("no av_config copies", stderr)

    def test_non_directory_copy_is_not_counted(self) -> None:
        files = {
            relative: content
            for relative, content in self._clean_files().items()
            if relative.startswith(f"{CANONICAL}/")
        }
        files[COPY] = b"not a directory\n"

        code, stdout, stderr = self._run(files)
        self.assertEqual(code, 2)
        self.assertEqual(stdout, "")
        self.assertIn("no av_config copies", stderr)

    def test_missing_canonical_is_an_error(self) -> None:
        files = {
            relative: content
            for relative, content in self._clean_files().items()
            if relative.startswith(f"{COPY}/")
        }
        code, stdout, stderr = self._run(files)
        self.assertEqual(code, 2)
        self.assertEqual(stdout, "")
        self.assertTrue(stderr.startswith("error: "))
        self.assertIn(CANONICAL, stderr)
        self.assertIn("missing", stderr)

    def test_empty_canonical_is_an_error(self) -> None:
        files = {
            relative: content
            for relative, content in self._clean_files().items()
            if relative.startswith(f"{COPY}/")
        }
        code, stdout, stderr = self._run(files, directories=(CANONICAL,))
        self.assertEqual(code, 2)
        self.assertEqual(stdout, "")
        self.assertTrue(stderr.startswith("error: "))
        self.assertIn("empty", stderr)

    def test_canonical_with_only_cache_files_is_empty(self) -> None:
        files = {
            relative: content
            for relative, content in self._clean_files().items()
            if relative.startswith(f"{COPY}/")
        }
        files[f"{CANONICAL}/__pycache__/x.cpython-312.pyc"] = b"ignored\n"

        code, stdout, stderr = self._run(files)
        self.assertEqual(code, 2)
        self.assertEqual(stdout, "")
        self.assertIn("empty", stderr)

    def test_any_argument_is_an_error(self) -> None:
        for argv in (["--help"], ["code-review"], ["--repo", "elsewhere"]):
            with self.subTest(argv=argv):
                code, stdout, stderr = self._run(self._clean_files(), argv)
                self.assertEqual(code, 2)
                self.assertEqual(stdout, "")
                self.assertTrue(stderr.startswith("error: "))
                self.assertIn("takes no arguments", stderr)

    def test_none_argv_reads_process_arguments(self) -> None:
        original_argv = sys.argv
        sys.argv = ["check_av_config_copies.py", "--help"]
        stdout = io.StringIO()
        stderr = io.StringIO()

        try:
            with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                code = main(None)
        finally:
            sys.argv = original_argv

        self.assertEqual(code, 2)
        self.assertEqual(stdout.getvalue(), "")
        self.assertIn("takes no arguments", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
