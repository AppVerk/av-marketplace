#!/usr/bin/env python3
"""Compare this edition's tool names with an installed OMP package.

Usage: check_omp_tools.py [<pi-coding-agent package dir>]
Default: omp/native/delivery/node_modules/@oh-my-pi/pi-coding-agent
Exit codes: 0 for a match, 1 for a mismatch, 2 when OMP is not installed or its tool list cannot be read.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

from build_omp_edition import OMP_TOOLS

DEFAULT_PACKAGE = Path("omp/native/delivery/node_modules/@oh-my-pi/pi-coding-agent")
NAMES = re.compile(r"export const BUILTIN_TOOL_NAMES = \[(.*?)\] as const;", re.S)


def builtin_tool_names(source: str) -> set[str]:
    """Read only BUILTIN_TOOL_NAMES, raising ValueError when it is absent."""
    match = NAMES.search(source)
    if match is None:
        raise ValueError("BUILTIN_TOOL_NAMES not found")
    return set(re.findall(r'"([^"]+)"', match.group(1)))


def main(argv: list[str]) -> int:
    """Compare the installed OMP tools with OMP_TOOLS and report differences."""
    package = Path(argv[0]) if argv else DEFAULT_PACKAGE
    names_file = package / "src/tools/builtin-names.ts"
    if not names_file.is_file():
        sys.stderr.write(
            f"builtin-names.ts not found under {package}; run: "
            "bun install --no-save --cwd omp/native/delivery @oh-my-pi/pi-coding-agent@latest\n"
        )
        return 2

    manifest = package / "package.json"
    version = json.loads(manifest.read_text()).get("version", "?") if manifest.is_file() else "?"
    try:
        installed = builtin_tool_names(names_file.read_text())
    except ValueError as error:
        sys.stderr.write(f"{names_file}: {error}; update NAMES in scripts/check_omp_tools.py\n")
        return 2
    if installed == OMP_TOOLS:
        sys.stdout.write(f"OMP_TOOLS matches OMP {version} ({len(OMP_TOOLS)} tools)\n")
        return 0

    differences = []
    missing = installed - OMP_TOOLS
    stale = OMP_TOOLS - installed
    if missing:
        differences.append(f"missing from OMP_TOOLS: {', '.join(sorted(missing))}")
    if stale:
        differences.append(f"not in OMP: {', '.join(sorted(stale))}")
    sys.stderr.write(
        f"OMP_TOOLS in scripts/build_omp_edition.py is out of date for OMP {version}: "
        + "; ".join(differences) + "\n"
    )
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
