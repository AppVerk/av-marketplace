#!/usr/bin/env python3
"""Check plugin version parity across the marketplace.

Enforces that every local plugin has the same version declared in all four
canonical locations:

  1. plugins/<name>/.claude-plugin/plugin.json        -> ".version"
  2. .claude-plugin/marketplace.json                  -> ".plugins[name==<name>].version"
  3. README.md                                        -> row in the "Available Plugins" table
  4. docs/plugins/<name>.md                           -> "**Version:** X.Y.Z" header

Exits 0 on success, 1 on any mismatch or missing version source.

Usage:
    python3 scripts/check_plugin_versions.py

Run from GitHub Actions on Ubuntu; only the Python 3 standard library is used.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
PLUGINS_DIR = REPO_ROOT / "plugins"
MARKETPLACE_JSON = REPO_ROOT / ".claude-plugin" / "marketplace.json"
README_MD = REPO_ROOT / "README.md"
DOCS_DIR = REPO_ROOT / "docs" / "plugins"

# README row pattern:
#   | [Plugin Name](docs/plugins/<slug>.md) | X.Y.Z | ... |
README_ROW_RE = re.compile(
    r"^\|\s*\[[^\]]+\]\(docs/plugins/(?P<slug>[a-z0-9][a-z0-9-]*)\.md\)\s*\|\s*"
    r"(?P<version>\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?)\s*\|",
    re.MULTILINE,
)

# Plugin doc Version header:
#   **Version:** X.Y.Z
DOC_VERSION_RE = re.compile(
    r"^\*\*Version:\*\*\s*(?P<version>\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?)\s*$",
    re.MULTILINE,
)


def _read_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as fh:
        return json.load(fh)


def _collect_local_plugins() -> list[str]:
    """Return sorted slugs of plugins that have plugins/<slug>/.claude-plugin/plugin.json."""
    if not PLUGINS_DIR.is_dir():
        return []
    slugs: list[str] = []
    for entry in sorted(PLUGINS_DIR.iterdir()):
        if entry.is_dir() and (entry / ".claude-plugin" / "plugin.json").is_file():
            slugs.append(entry.name)
    return slugs


def _marketplace_versions() -> dict[str, str]:
    """Return {slug: version} for entries with a version field in marketplace.json."""
    data = _read_json(MARKETPLACE_JSON)
    versions: dict[str, str] = {}
    for entry in data.get("plugins", []):
        name = entry.get("name")
        version = entry.get("version")
        if name and version:
            versions[name] = version
    return versions


def _readme_versions() -> dict[str, str]:
    """Return {slug: version} parsed from the README Available Plugins table."""
    text = README_MD.read_text(encoding="utf-8")
    return {m.group("slug"): m.group("version") for m in README_ROW_RE.finditer(text)}


def _doc_version(slug: str) -> str | None:
    """Return the version string from docs/plugins/<slug>.md, or None if absent."""
    doc_path = DOCS_DIR / f"{slug}.md"
    if not doc_path.is_file():
        return None
    text = doc_path.read_text(encoding="utf-8")
    match = DOC_VERSION_RE.search(text)
    return match.group("version") if match else None


def main() -> int:
    slugs = _collect_local_plugins()
    if not slugs:
        print("error: no local plugins discovered under plugins/", file=sys.stderr)
        return 1

    marketplace = _marketplace_versions()
    readme = _readme_versions()

    errors: list[str] = []

    for slug in slugs:
        sources: dict[str, str | None] = {
            "plugin.json": _read_json(
                PLUGINS_DIR / slug / ".claude-plugin" / "plugin.json"
            ).get("version"),
            "marketplace.json": marketplace.get(slug),
            "README.md": readme.get(slug),
            f"docs/plugins/{slug}.md": _doc_version(slug),
        }

        missing = [label for label, value in sources.items() if not value]
        if missing:
            errors.append(
                f"[{slug}] missing version in: {', '.join(missing)}"
            )
            continue

        unique = set(sources.values())
        if len(unique) != 1:
            details = ", ".join(
                f"{label}={value}" for label, value in sources.items()
            )
            errors.append(f"[{slug}] version mismatch: {details}")
            continue

        print(f"[{slug}] {next(iter(unique))} (OK)")

    if errors:
        print("\nVersion parity check FAILED:\n", file=sys.stderr)
        for line in errors:
            print(f"  - {line}", file=sys.stderr)
        print(
            "\nUpdate the affected file(s) so all four sources agree, "
            "then re-run this script.",
            file=sys.stderr,
        )
        return 1

    print(f"\nVersion parity OK for {len(slugs)} plugin(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
