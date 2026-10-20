#!/usr/bin/env python3
"""Check that every OMP edition extension loads in the compiled omp binary.

Usage: check_omp_extensions.py <omp binary> [<edition dir>]
Default edition: plugins-omp/ under the repository root.
Exit codes: 0 when all extensions load, 1 for load or binary launch failures,
2 for invalid configuration.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
TIMEOUT = 60


def edition_extensions(edition: Path) -> list[Path]:
    """Read extensions in sorted manifest order, retaining each declaration's order."""
    return [
        (manifest.parent / entry).resolve()
        for manifest in sorted(edition.glob("*/package.json"))
        for entry in json.loads(manifest.read_text()).get("omp", {}).get("extensions", [])
    ]


def load_error(binary: Path, extension: Path, timeout: int = TIMEOUT) -> str | None:
    """Load one extension with isolated settings and return its failure reason, if any."""
    with tempfile.TemporaryDirectory() as tmp:
        try:
            result = subprocess.run(
                [str(binary), "--mode", "rpc", "--no-session", "--trusted-extension", str(extension)],
                cwd=tmp,
                # Without a model omp exits 1 before serving RPC, and a fresh HOME holds no
                # credentials. A placeholder key gives it one; stdin is closed, so nothing is sent.
                env={"HOME": tmp, "PATH": os.environ.get("PATH", ""), "ANTHROPIC_API_KEY": "check-omp-extensions"},
                stdin=subprocess.DEVNULL,
                capture_output=True,
                text=True,
                timeout=timeout,
                check=False,
            )
        except subprocess.TimeoutExpired:
            return f"omp did not exit within {timeout} s"
        except OSError as exc:
            return f"cannot run {binary}: {exc.strerror}"

    if result.returncode == 0:
        return None

    lines = [line.strip() for line in result.stderr.splitlines() if line.strip()]

    for line in lines:
        if line.startswith("error:"):
            return line

    return lines[-1] if lines else f"exit code {result.returncode}"


def main(argv: list[str]) -> int:
    """Load every declared extension and report failures or a successful count."""
    if len(argv) not in (1, 2):
        sys.stderr.write("usage: check_omp_extensions.py <omp binary> [<edition dir>]\n")
        return 2

    binary = Path(argv[0]).resolve()

    if not binary.is_file() or not os.access(binary, os.X_OK):
        sys.stderr.write(
            f"{argv[0]} is not an executable file; download the compiled omp binary for your platform: "
            "dir=$(mktemp -d) && gh release download -R can1357/oh-my-pi "
            '-p "omp-<os>-<arch>" -D "$dir", then chmod +x the file\n'
        )
        return 2

    edition = Path(argv[1]) if len(argv) == 2 else REPO / "plugins-omp"
    extensions = edition_extensions(edition)

    if not extensions:
        sys.stderr.write(f"no extension declared in {edition}/*/package.json\n")
        return 2

    failed = 0

    for extension in extensions:
        error = load_error(binary, extension)

        if error is not None:
            failed += 1
            sys.stderr.write(f"{extension}: {error}\n")

    if failed:
        sys.stderr.write(f"{failed} of {len(extensions)} OMP extensions fail to load in {binary}\n")
        return 1

    sys.stdout.write(f"{len(extensions)} OMP extensions load in {binary}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
