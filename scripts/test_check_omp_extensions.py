#!/usr/bin/env python3
"""Contract tests for compiled OMP extension loading, including relative CLI paths.

Run: python3 scripts/test_check_omp_extensions.py
"""

from __future__ import annotations

import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stderr
from contextlib import redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from check_omp_extensions import edition_extensions
from check_omp_extensions import load_error
from check_omp_extensions import main


FAKE_OMP = """#!/usr/bin/env python3
import sys
import time
from pathlib import Path

extension = Path(sys.argv[sys.argv.index("--trusted-extension") + 1])
if not extension.is_absolute():
    print(f"error: --trusted-extension requires an absolute path: {extension}", file=sys.stderr)
    sys.exit(2)

source = extension.read_text()
if "HANG" in source:
    time.sleep(10)
if "BROKEN" in source:
    print("  | throw err;", file=sys.stderr)
    print(
        "error: Trusted extension failed to load: Failed to load extension: "
        "Cannot find package '@oh-my-pi/pi-coding-agent' imported from " + str(extension),
        file=sys.stderr,
    )
    print("    at RT (/$bunfs/root/cli.js:1:1)", file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"""


def fake_omp(root: Path, source: str = FAKE_OMP) -> Path:
    binary = root / "omp"
    binary.write_text(source)
    binary.chmod(0o755)
    return binary


def plugin(edition: Path, name: str, extensions: dict[str, str] | None) -> list[Path]:
    root = edition / name
    root.mkdir(parents=True)

    if extensions is None:
        (root / "package.json").write_text(json.dumps({"name": name}))
        return []

    (root / "package.json").write_text(
        json.dumps({"name": name, "omp": {"extensions": list(extensions)}})
    )
    paths = []

    for entry, source in extensions.items():
        extension = root / entry
        extension.parent.mkdir(parents=True, exist_ok=True)
        extension.write_text(source)
        paths.append(extension.resolve())

    return paths


def run_check(argv: list[str]) -> tuple[int, str, str]:
    stdout = io.StringIO()
    stderr = io.StringIO()

    with redirect_stdout(stdout), redirect_stderr(stderr):
        result = main(argv)

    return result, stdout.getvalue(), stderr.getvalue()


class CheckerTest(unittest.TestCase):
    def test_loading_extensions_report_count_and_resolved_binary(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            binary = fake_omp(root)
            edition = root / "edition"
            plugin(edition, "alpha", {"extensions/one.ts": "", "extensions/two.ts": ""})
            plugin(edition, "beta", {"extensions/three.ts": ""})
            plugin(edition, "plain", None)

            result, stdout, stderr = run_check([str(binary), str(edition)])

            self.assertEqual(result, 0)
            self.assertEqual(stdout, f"3 OMP extensions load in {binary.resolve()}\n")
            self.assertEqual(stderr, "")

    def test_relative_arguments_are_resolved(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            binary = fake_omp(root)
            plugin(root / "edition", "alpha", {"extensions/a.ts": ""})
            previous_cwd = Path.cwd()

            try:
                os.chdir(root)
                result, stdout, stderr = run_check([binary.name, "edition"])
            finally:
                os.chdir(previous_cwd)

            self.assertEqual(result, 0)
            self.assertEqual(stdout, f"1 OMP extensions load in {binary.resolve()}\n")
            self.assertEqual(stderr, "")

    def test_extensions_follow_manifest_order_then_declaration_order(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            edition = Path(tmp)
            beta = plugin(edition, "beta", {"extensions/z.ts": "", "extensions/a.ts": ""})
            alpha = plugin(edition, "alpha", {"extensions/one.ts": ""})
            plugin(edition, "plain", None)
            plugin(edition, "empty", {})
            missing = edition / "missing-extensions"
            missing.mkdir()
            (missing / "package.json").write_text('{"name": "missing-extensions", "omp": {}}')

            self.assertEqual(edition_extensions(edition), alpha + beta)

    def test_broken_extension_reports_error_without_loading_extension(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            binary = fake_omp(root)
            edition = root / "edition"
            broken, loading = plugin(
                edition, "plugin", {"extensions/broken.ts": "BROKEN", "extensions/loading.ts": ""}
            )

            result, stdout, stderr = run_check([str(binary), str(edition)])

            self.assertEqual(result, 1)
            self.assertEqual(stdout, "")
            self.assertIn(
                f"{broken}: error: Trusted extension failed to load: Failed to load extension: "
                "Cannot find package '@oh-my-pi/pi-coding-agent'",
                stderr,
            )
            self.assertIn(f"1 of 2 OMP extensions fail to load in {binary.resolve()}\n", stderr)
            self.assertNotIn(str(loading), stderr)
            self.assertNotIn("throw err", stderr)
            self.assertNotIn("at RT", stderr)

    def test_hanging_extension_reports_timeout(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            binary = fake_omp(root).resolve()
            extension = plugin(root / "edition", "plugin", {"extensions/hang.ts": "HANG"})[0]

            self.assertEqual(load_error(binary, extension, timeout=1), "omp did not exit within 1 s")

    def test_wrong_platform_binary_reports_reason_without_traceback(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            binary = fake_omp(root, "\x7fELFgarbage").resolve()
            edition = root / "edition"
            extension = plugin(edition, "plugin", {"extensions/one.ts": ""})[0]

            result = subprocess.run(
                [
                    sys.executable,
                    str(Path(__file__).with_name("check_omp_extensions.py")),
                    str(binary),
                    str(edition),
                ],
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 1)
            self.assertEqual(result.stdout, "")
            self.assertIn(f"{extension}: cannot run {binary}: ", result.stderr)
            self.assertRegex(result.stderr, r": cannot run [^\n]+: [^\n]+\n")
            self.assertIn(f"1 of 1 OMP extensions fail to load in {binary}\n", result.stderr)
            self.assertNotIn("Traceback", result.stderr)

    def test_missing_binary_explains_how_to_download(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            binary = Path(tmp) / "missing"

            result, stdout, stderr = run_check([str(binary)])

            self.assertEqual(result, 2)
            self.assertEqual(stdout, "")
            self.assertIn(f"{binary} is not an executable file", stderr)
            self.assertIn("dir=$(mktemp -d) && gh release download", stderr)
            self.assertIn('-D "$dir"', stderr)

    def test_nonexecutable_binary_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            binary = fake_omp(Path(tmp))
            binary.chmod(0o644)

            result, stdout, stderr = run_check([str(binary)])

            self.assertEqual(result, 2)
            self.assertEqual(stdout, "")
            self.assertIn("is not an executable file", stderr)

    def test_no_declared_extension_is_configuration_error(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            binary = fake_omp(root)
            edition = root / "edition"
            plugin(edition, "empty", {})

            result, stdout, stderr = run_check([str(binary), str(edition)])

            self.assertEqual(result, 2)
            self.assertEqual(stdout, "")
            self.assertEqual(stderr, f"no extension declared in {edition}/*/package.json\n")

    def test_invalid_argument_count_reports_usage(self) -> None:
        for argv in ([], ["omp", "edition", "extra"]):
            with self.subTest(argv=argv):
                result, stdout, stderr = run_check(argv)

                self.assertEqual(result, 2)
                self.assertEqual(stdout, "")
                self.assertEqual(
                    stderr, "usage: check_omp_extensions.py <omp binary> [<edition dir>]\n"
                )

    def test_failed_load_uses_first_error_then_stderr_then_exit_code(self) -> None:
        cases = (
            ("  diagnostic\n  error: first\nerror: second\n  trace\n", "error: first"),
            ("  diagnostic\n  last detail  \n\n", "last detail"),
            (" \n\t\n", "exit code 3"),
            ("", "exit code 3"),
        )

        for stderr, expected in cases:
            with self.subTest(stderr=stderr), tempfile.TemporaryDirectory() as tmp:
                source = (
                    "#!/usr/bin/env python3\nimport sys\n"
                    f"sys.stderr.write({stderr!r})\nsys.exit(3)\n"
                )
                binary = fake_omp(Path(tmp), source).resolve()

                self.assertEqual(load_error(binary, (Path(tmp) / "extension.ts").resolve()), expected)


if __name__ == "__main__":
    unittest.main()
