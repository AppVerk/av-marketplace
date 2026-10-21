#!/usr/bin/env python3
"""Check that every shipped av_config copy is byte-identical to QA's package.

Run: python3 scripts/check_av_config_copies.py
"""

from __future__ import annotations

import sys
from pathlib import Path


PLUGINS_DIR = Path(__file__).resolve().parent.parent / "plugins"
CANONICAL_RELPATH = Path("qa/skills/engine/scripts/av_config")


def file_map(directory: Path) -> dict[str, bytes]:
    """Read package files, excluding Python bytecode and cache directories."""

    files: dict[str, bytes] = {}

    for path in directory.rglob("*"):
        relative = path.relative_to(directory)

        if "__pycache__" in relative.parts or path.suffix == ".pyc":
            continue

        if path.is_file():
            files[relative.as_posix()] = path.read_bytes()

    return files


def main(argv: list[str] | None = None, plugins_dir: Path = PLUGINS_DIR) -> int:
    """Return 0 for matching copies, 1 for differences, or 2 for invalid inputs."""

    args = sys.argv[1:] if argv is None else argv

    if args:
        print(
            f"error: this check takes no arguments, got {' '.join(args)!r}",
            file=sys.stderr,
        )
        return 2

    canonical = plugins_dir / CANONICAL_RELPATH
    canonical_label = f"plugins/{CANONICAL_RELPATH.as_posix()}"

    if not canonical.is_dir():
        print(f"error: {canonical_label}: canonical package is missing", file=sys.stderr)
        return 2

    expected = file_map(canonical)

    if not expected:
        print(f"error: {canonical_label}: canonical package is empty", file=sys.stderr)
        return 2

    copies = sorted(
        path
        for path in plugins_dir.glob("*/skills/*/scripts/av_config")
        if path != canonical and path.is_dir()
    )

    if not copies:
        print(f"error: no av_config copies found under {plugins_dir}", file=sys.stderr)
        return 2

    differences: list[str] = []
    expected_names = expected.keys()

    for copy in copies:
        label = copy.relative_to(plugins_dir.parent).as_posix()
        actual = file_map(copy)
        actual_names = actual.keys()

        for relative in sorted(expected_names - actual_names):
            differences.append(f"{label}: missing {relative}")

        for relative in sorted(actual_names - expected_names):
            differences.append(f"{label}: extra {relative}")

        for relative in sorted(expected_names & actual_names):
            if actual[relative] != expected[relative]:
                differences.append(
                    f"{label}: {relative} differs from {canonical_label}/{relative}"
                )

    if differences:
        for difference in differences:
            print(difference, file=sys.stderr)

        print(
            f"Copy {canonical_label}/ over every copy and bump each changed plugin's version.",
            file=sys.stderr,
        )
        return 1

    print(f"av_config copies OK: {len(copies)} copy(ies) match {canonical_label}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
