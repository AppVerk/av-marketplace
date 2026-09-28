#!/usr/bin/env python3
"""Check plugin version parity across the marketplace.

Enforces that every local plugin has the same version declared in all four
canonical locations, plus per-skill VERSION files when the plugin has them:

  1. plugins/<name>/.claude-plugin/plugin.json        -> ".version"
  2. .claude-plugin/marketplace.json                  -> ".plugins[name==<name>].version"
  3. README.md                                        -> row in the "Available Plugins" table
  4. docs/plugins/<name>.md                           -> "**Version:** X.Y.Z" header
  5. plugins/<name>/skills/*/VERSION (optional)       -> whole file, e.g. "0.1.0"

A plugin whose skills read their own VERSION (av-dev: gate.sh compares it with
"requires" in a repo config) must keep those files in step with plugin.json.

OMP-only plugins in omp/native/<name>/ are listed in the same README table; their
row must match omp/native/<name>/.omp-plugin/plugin.json.

Also flags orphan entries in marketplace.json or README.md that no longer have
a corresponding plugins/<slug>/ directory (or, for README.md, omp/native/<slug>/).

Checks the README table's ID, Claude Code and OMP columns against the catalogs
each tool installs from, .claude-plugin/marketplace.json and the generated
.omp-plugin/marketplace.json: a column holds ✓ when that catalog lists the
plugin and — otherwise, and every catalog entry needs a row.

Optionally (with --check-regression) compares each plugin's version against the
last commit on origin/master and fails if any plugin's version went backwards.
With --check-hooks-version-bump BASE_REF, requires a version bump of every
overlaid plugin with hooks when its previously shipped OMP hooks adapter changes.

Exits 0 on success, 1 on any mismatch, missing version source, orphan, or
README availability error.

Usage:
    python3 scripts/check_plugin_versions.py
    python3 scripts/check_plugin_versions.py --check-regression
    python3 scripts/check_plugin_versions.py --check-hooks-version-bump BASE_REF

Run from GitHub Actions on Ubuntu; only the Python 3 standard library is used.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
PLUGINS_DIR = REPO_ROOT / "plugins"
NATIVE_DIR = REPO_ROOT / "omp" / "native"
MARKETPLACE_JSON = REPO_ROOT / ".claude-plugin" / "marketplace.json"
OMP_MARKETPLACE_JSON = REPO_ROOT / ".omp-plugin" / "marketplace.json"
README_MD = REPO_ROOT / "README.md"
DOCS_DIR = REPO_ROOT / "docs" / "plugins"

# README row pattern:
#   | [Plugin Name](docs/plugins/<slug>.md) | X.Y.Z | ... |
README_ROW_RE = re.compile(
    r"^\|\s*\[[^\]]+\]\(docs/plugins/(?P<slug>[a-z0-9][a-z0-9-]*)\.md\)\s*\|\s*"
    r"(?P<version>\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?)\s*\|",
    re.MULTILINE,
)

# README availability columns and the catalog each one mirrors.
AVAILABILITY_CATALOGS = {"Claude Code": MARKETPLACE_JSON, "OMP": OMP_MARKETPLACE_JSON}
AVAILABLE, UNAVAILABLE = "✓", "—"
README_ID_RE = re.compile(r"`([a-z0-9][a-z0-9.-]*)`")

# Locates the body of the "Available Plugins" section so we never match rows
# inside other tables, code blocks, or HTML comments elsewhere in README.md.
README_TABLE_SECTION_RE = re.compile(
    r"^##\s+Available Plugins\b.*?(?=^##\s)",
    re.DOTALL | re.MULTILINE,
)

# Plugin doc Version header.
#
# We split the parse into two stages so that "header absent" and "header
# present but version unparsable" produce distinct diagnostics — the old
# single-regex approach reported both as "missing version", which sent
# maintainers chasing a phantom missing line when the real bug was a
# trailing suffix like "(deprecated)" or an HTML comment.
#
#   1. DOC_HEADER_RE locates the `**Version:**` line and captures everything
#      after the marker.
#   2. DOC_VERSION_SUFFIX_RE validates that the remainder is a SemVer string,
#      optionally followed by a parenthesised note or HTML comment.
DOC_HEADER_RE = re.compile(
    r"^\*\*Version:\*\*\s*(?P<rest>.+?)\s*$",
    re.MULTILINE,
)
DOC_VERSION_SUFFIX_RE = re.compile(
    # Accept full SemVer including both pre-release and build metadata
    # (e.g. ``1.2.3-alpha+build.7``) by allowing ``+`` inside the suffix
    # character class — not just as the leading separator.
    r"^(?P<version>\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.+-]+)?)"
    r"\s*(?:\(.*\)|<!--.*-->)?\s*$"
)

# SemVer prefix: major.minor.patch (ignores pre-release/build for comparison).
SEMVER_RE = re.compile(r"^(\d+)\.(\d+)\.(\d+)")


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


def _collect_native_plugins() -> list[str]:
    """Return sorted slugs of OMP-only plugins that have omp/native/<slug>/.omp-plugin/plugin.json."""
    if not NATIVE_DIR.is_dir():
        return []
    return [
        entry.name
        for entry in sorted(NATIVE_DIR.iterdir())
        if entry.is_dir() and (entry / ".omp-plugin" / "plugin.json").is_file()
    ]


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
    """Return {slug: version} parsed from the README Available Plugins table.

    The regex is scoped to the body of the "## Available Plugins" section so
    that plugin doc links inside code blocks, HTML comments, or unrelated
    tables elsewhere in the README cannot pollute the parity set.
    """
    text = README_MD.read_text(encoding="utf-8")
    section = README_TABLE_SECTION_RE.search(text)
    if not section:
        return {}
    return {
        m.group("slug"): m.group("version")
        for m in README_ROW_RE.finditer(section.group(0))
    }


def _doc_version(slug: str) -> tuple[str | None, str | None]:
    """Return ``(version, error_reason)`` for docs/plugins/<slug>.md.

    The two-element shape lets callers distinguish three cases:

    * file or header missing → ``(None, "header absent")`` (or file-level reason)
    * header present but malformed → ``(None, "unparsable: '<rest>'")``
    * header present and well-formed → ``(version, None)``
    """
    doc_path = DOCS_DIR / f"{slug}.md"
    if not doc_path.is_file():
        return None, "doc file missing"
    text = doc_path.read_text(encoding="utf-8")
    header = DOC_HEADER_RE.search(text)
    if not header:
        return None, "header absent"
    rest = header.group("rest").strip()
    match = DOC_VERSION_SUFFIX_RE.match(rest)
    if not match:
        return None, f"unparsable: {rest!r}"
    return match.group("version"), None


def _skill_versions(slug: str) -> dict[str, str | None]:
    """Return {"skills/<skill>/VERSION": version or None} for a plugin's per-skill VERSION files."""
    versions: dict[str, str | None] = {}
    for path in sorted((PLUGINS_DIR / slug / "skills").glob("*/VERSION")):
        try:
            value = path.read_text(encoding="utf-8").strip()
        except OSError:
            value = ""
        versions[f"skills/{path.parent.name}/VERSION"] = value or None
    return versions


def _parse_semver(version: str) -> tuple[int, int, int] | None:
    """Return (major, minor, patch) or None if the prefix is not parseable."""
    match = SEMVER_RE.match(version)
    if not match:
        return None
    return (int(match.group(1)), int(match.group(2)), int(match.group(3)))


def _git(*args: str) -> str:
    """Run a git command in REPO_ROOT and return stripped stdout, or "" on failure."""
    try:
        result = subprocess.run(
            ["git", *args],
            cwd=REPO_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return ""
    return result.stdout.strip()


def _plugin_version_at_ref(slug: str, ref: str) -> str | None:
    """Return the plugin.json version at ref, or None if absent or unreadable."""
    rel_path = f"plugins/{slug}/.claude-plugin/plugin.json"
    blob = _git("show", f"{ref}:{rel_path}")
    if not blob:
        return None
    try:
        data = json.loads(blob)
    except json.JSONDecodeError:
        return None
    version = data.get("version")
    return version if isinstance(version, str) else None


def _check_regressions(slugs: list[str]) -> list[str]:
    """Return error messages for any plugin whose version went backwards vs origin/master."""
    errors: list[str] = []

    # Make sure we actually have origin/master to compare against.
    fetch_output = _git("fetch", "--quiet", "origin", "master")
    # `git fetch` prints nothing on success; we just care that the ref resolves.
    if not _git("rev-parse", "--verify", "origin/master"):
        errors.append(
            "[regression-check] cannot resolve origin/master; "
            "skip --check-regression or ensure the remote is reachable"
        )
        # Surface fetch stderr indirectly by not silently passing.
        if fetch_output:
            errors.append(f"[regression-check] git fetch said: {fetch_output}")
        return errors

    for slug in slugs:
        plugin_json = PLUGINS_DIR / slug / ".claude-plugin" / "plugin.json"
        try:
            current = _read_json(plugin_json).get("version")
        except (OSError, json.JSONDecodeError):
            current = None
        if not isinstance(current, str):
            continue  # parity check above already flags missing versions

        previous = _plugin_version_at_ref(slug, "origin/master")
        if previous is None:
            # New plugin not yet on master, or unreadable on master — nothing to compare.
            continue

        current_tuple = _parse_semver(current)
        previous_tuple = _parse_semver(previous)
        if current_tuple is None or previous_tuple is None:
            errors.append(
                f"[{slug}] cannot parse SemVer "
                f"(current={current!r}, origin/master={previous!r})"
            )
            continue

        if current_tuple < previous_tuple:
            errors.append(
                f"[{slug}] version regression: {previous} (origin/master) "
                f"-> {current} (HEAD)"
            )

    return errors


def _check_hooks_version_bumps(slugs: list[str], base_ref: str) -> list[str]:
    """Require bumped versions if an existing shared adapter changes."""
    adapter = "omp/claude-hooks/claude-hooks.ts"
    baseline = subprocess.run(
        ["git", "ls-tree", base_ref, "--", adapter],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
    )
    if baseline.returncode != 0:
        return [f"[hooks-version-check] cannot inspect adapter at {base_ref}: {baseline.stderr.strip()}"]
    if not baseline.stdout:
        return []  # No installed OMP edition shipped this adapter at the base ref.

    diff = subprocess.run(
        ["git", "diff", "--quiet", base_ref, "--", adapter],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
    )
    if diff.returncode == 0:
        return []
    if diff.returncode != 1:
        return [f"[hooks-version-check] cannot compare adapter with {base_ref}: {diff.stderr.strip()}"]

    errors: list[str] = []
    for slug in slugs:
        if not (REPO_ROOT / "omp" / "overlay" / f"{slug}.json").is_file():
            continue
        if not (PLUGINS_DIR / slug / "hooks" / "hooks.json").is_file():
            continue
        previous = _plugin_version_at_ref(slug, base_ref)
        if previous is None:
            continue  # New plugin: there is no prior installed version to update.
        try:
            current = _read_json(PLUGINS_DIR / slug / ".claude-plugin" / "plugin.json").get("version")
        except (OSError, json.JSONDecodeError):
            continue  # The parity check reports unreadable or malformed manifests.
        if current == previous:
            errors.append(
                f"[{slug}] shared OMP hooks adapter changed, but version is still "
                f"{previous} (same as {base_ref}); bump all four version sources"
            )
    return errors


def _catalog_names(path: Path) -> set[str]:
    """Return the plugin names a marketplace catalog lists."""
    return {entry["name"] for entry in _read_json(path).get("plugins", []) if entry.get("name")}


def _check_availability() -> list[str]:
    """Return errors where the README table's ID and tool columns disagree with the catalogs."""
    errors: list[str] = []
    catalogs: dict[str, set[str]] = {}
    for column, path in AVAILABILITY_CATALOGS.items():
        try:
            catalogs[column] = _catalog_names(path)
        except (json.JSONDecodeError, OSError) as exc:
            errors.append(f"{path.relative_to(REPO_ROOT)}: cannot read: {exc}")
    if errors:
        return errors

    section = README_TABLE_SECTION_RE.search(README_MD.read_text(encoding="utf-8"))
    lines = [line.strip() for line in section.group(0).splitlines() if line.startswith("|")] if section else []
    if len(lines) < 2:
        return ["README.md: no Available Plugins table"]
    header = [cell.strip() for cell in lines[0].strip("|").split("|")]
    missing_columns = [column for column in ("ID", *AVAILABILITY_CATALOGS) if column not in header]
    if missing_columns:
        return [f"README.md: Available Plugins table lacks column(s): {', '.join(missing_columns)}"]

    rows: set[str] = set()
    for line in lines[2:]:
        cells = [cell.strip() for cell in line.strip("|").split("|")]
        if len(cells) < len(header):
            errors.append(f"README.md: Available Plugins row has too few cells: {line[:60]}")
            continue
        match = README_ID_RE.fullmatch(cells[header.index("ID")])
        if not match:
            errors.append(f"README.md: Available Plugins row {cells[0]} needs a backticked plugin ID")
            continue
        plugin = match.group(1)
        rows.add(plugin)
        if not any(plugin in names for names in catalogs.values()):
            errors.append(f"[{plugin}] README.md row is in no marketplace catalog")
            continue
        for column, names in catalogs.items():
            mark = cells[header.index(column)]
            expected = AVAILABLE if plugin in names else UNAVAILABLE
            if mark != expected:
                listed = "lists" if plugin in names else "does not list"
                errors.append(
                    f"[{plugin}] README.md {column} column is {mark!r}, expected {expected!r}: "
                    f"{AVAILABILITY_CATALOGS[column].relative_to(REPO_ROOT)} {listed} it"
                )
    for plugin in sorted(set().union(*catalogs.values()) - rows):
        errors.append(f"[{plugin}] in a marketplace catalog but has no README Available Plugins row")
    if not errors:
        print(f"README availability OK for {len(rows)} row(s).")
    return errors


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Check plugin version parity across the marketplace.",
    )
    parser.add_argument(
        "--check-regression",
        action="store_true",
        help=(
            "Also fetch origin/master and fail if any plugin's SemVer went "
            "backwards. Requires git access to the remote; opt-in only."
        ),
    )
    parser.add_argument(
        "--check-hooks-version-bump",
        metavar="BASE_REF",
        help="Require hooked OMP plugin version bumps if the shared adapter changed since BASE_REF.",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(list(sys.argv[1:] if argv is None else argv))

    slugs = _collect_local_plugins()
    if not slugs:
        print("error: no local plugins discovered under plugins/", file=sys.stderr)
        return 1

    errors: list[str] = []
    try:
        marketplace = _marketplace_versions()
    except json.JSONDecodeError as exc:
        print(
            f"error: {MARKETPLACE_JSON.name}: invalid JSON: "
            f"{exc.msg} at line {exc.lineno}",
            file=sys.stderr,
        )
        return 1
    except OSError as exc:
        print(
            f"error: {MARKETPLACE_JSON.name}: cannot read: {exc}",
            file=sys.stderr,
        )
        return 1
    readme = _readme_versions()

    for slug in slugs:
        plugin_json_path = PLUGINS_DIR / slug / ".claude-plugin" / "plugin.json"
        try:
            plugin_json_version = _read_json(plugin_json_path).get("version")
        except json.JSONDecodeError as exc:
            errors.append(
                f"[{slug}] {plugin_json_path.name}: invalid JSON: "
                f"{exc.msg} at line {exc.lineno}"
            )
            continue
        except OSError as exc:
            errors.append(
                f"[{slug}] {plugin_json_path.name}: cannot read: {exc}"
            )
            continue

        doc_label = f"docs/plugins/{slug}.md"
        doc_version, doc_reason = _doc_version(slug)

        sources: dict[str, str | None] = {
            "plugin.json": plugin_json_version,
            "marketplace.json": marketplace.get(slug),
            "README.md": readme.get(slug),
            doc_label: doc_version,
        }
        sources.update(_skill_versions(slug))

        missing = [label for label, value in sources.items() if not value]
        if missing:
            # Surface the doc-specific reason so a malformed `**Version:**`
            # line is not misreported as "missing".
            details = []
            for label in missing:
                if label == doc_label and doc_reason is not None:
                    details.append(f"{label} ({doc_reason})")
                else:
                    details.append(label)
            errors.append(
                f"[{slug}] missing version in: {', '.join(details)}"
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

    native_slugs = _collect_native_plugins()
    for slug in native_slugs:
        native_json_path = NATIVE_DIR / slug / ".omp-plugin" / "plugin.json"
        try:
            native_version = _read_json(native_json_path).get("version")
        except (json.JSONDecodeError, OSError) as exc:
            errors.append(f"[{slug}] omp/native/{slug}/.omp-plugin/plugin.json: cannot read: {exc}")
            continue
        readme_version = readme.get(slug)
        if not native_version or not readme_version:
            missing = [
                label
                for label, value in (("omp/native plugin.json", native_version), ("README.md", readme_version))
                if not value
            ]
            errors.append(f"[{slug}] missing version in: {', '.join(missing)}")
        elif native_version != readme_version:
            errors.append(
                f"[{slug}] version mismatch: omp/native plugin.json={native_version}, README.md={readme_version}"
            )
        else:
            print(f"[{slug}] {native_version} (OK, OMP-only)")

    # Orphan detection: entries that exist in marketplace.json or README.md
    # but have no plugin directory backing them. The loops above only iterate
    # over local slugs and would silently miss these.
    slug_set = set(slugs)
    for orphan in sorted(set(marketplace) - slug_set):
        errors.append(f"[{orphan}] stale entry in: marketplace.json (no plugins/{orphan}/ directory)")
    for orphan in sorted(set(readme) - slug_set - set(native_slugs)):
        errors.append(
            f"[{orphan}] stale entry in: README.md (no plugins/{orphan}/ or omp/native/{orphan}/ directory)"
        )
    errors.extend(_check_availability())

    if args.check_regression:
        errors.extend(_check_regressions(slugs))
    if args.check_hooks_version_bump:
        errors.extend(_check_hooks_version_bumps(slugs, args.check_hooks_version_bump))

    if errors:
        print("\nVersion parity check FAILED:\n", file=sys.stderr)
        for line in errors:
            print(f"  - {line}", file=sys.stderr)
        print(
            "\nFix the affected file(s), then re-run this script.",
            file=sys.stderr,
        )
        return 1

    print(f"\nVersion parity OK for {len(slugs) + len(native_slugs)} plugin(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
