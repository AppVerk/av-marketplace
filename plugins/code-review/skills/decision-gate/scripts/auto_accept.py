#!/usr/bin/env python3
"""Stdlib-only JSON interface for code-review's opt-in auto-accept policy."""
from __future__ import annotations

import argparse
from collections.abc import Mapping
from collections.abc import Sequence
import json
from pathlib import Path
import re
import subprocess
import sys
from typing import cast
from typing import NoReturn

# Check before importing tomllib through av_config, so older interpreters get
# the actionable version error rather than an import traceback.
if sys.version_info < (3, 11):
    print(json.dumps({
        "error": "Error: the code-review auto-accept engine needs Python 3.11 or newer "
        f"(found {sys.version_info.major}.{sys.version_info.minor})",
    }, sort_keys=True))
    raise SystemExit(2)

from av_config.errors import ConfigError
from av_config.errors import InvalidConfig
from av_config.files import Configuration
from av_config.sources import mask
from av_config.trust import canonical_hash
from av_config.trust import TrustStore

TABLE = "code-review"
AUTO_ACCEPT = "auto_accept_min_confidence"
FLOOR = 70
VALUE_SOURCE_KEYS = re.compile(
    r"env\.(?:secrets|values)\.[A-Za-z_][A-Za-z0-9_]*|env\.stores\.[A-Za-z_][A-Za-z0-9_]*\.password"
)
DOC_SUFFIXES = {".md", ".mdx", ".rst", ".adoc"}
DOC_DIRS = {"docs", "doc"}
DOC_STEMS = {"README", "CHANGELOG", "CONTRIBUTING"}


class AutoAcceptConfig:
    """Validate only code-review's table and the shared environment schema.

    ``report()`` masks value sources for display; ``accept()`` reloads from disk
    under the trust-store lock so approval cannot pin a stale configuration.
    """

    def __init__(self, repo: Path, *, state_home: Path | None = None) -> None:
        self.repo = repo.resolve()
        self.state_home = state_home
        self.shared = Configuration(self.repo, plugin_prefix="AV_")
        self.errors = self.shared.errors
        self.store = TrustStore(self.repo, TABLE, state_home)
        table = self.shared.data.get(TABLE)
        self.table = cast(dict[str, object], table) if isinstance(table, dict) else {}

        if self.shared.exists and TABLE in self.shared.data:
            self._validate()

        self.trust_subset = {} if self.errors else self.shared.env_sensitive_subset()

        if not self.errors and AUTO_ACCEPT in self.table:
            self.trust_subset[f"{TABLE}.{AUTO_ACCEPT}"] = self.table[AUTO_ACCEPT]

        self.trust_hash = canonical_hash(self.trust_subset)
        self.trust = self.store.status(self.trust_subset)

    @property
    def state(self) -> str:
        return self.shared.state(TABLE)

    def _validate(self) -> None:
        table = self.shared.table(self.shared.data[TABLE], TABLE)
        self.shared.keys(table, {AUTO_ACCEPT}, TABLE)

        if AUTO_ACCEPT in table:
            value = table[AUTO_ACCEPT]

            if type(value) is not int or not FLOOR <= value <= 100:
                self.shared.error(f"{TABLE}.{AUTO_ACCEPT}", "expected an integer from 70 to 100")

    def report(self) -> dict[str, object]:
        """Return JSON-safe policy metadata without resolving value sources."""

        report: dict[str, object] = {
            "state": self.state,
            "errors": self.errors,
            "warnings": self.shared.warnings,
            "provenance": self.shared.provenance,
            "trust": self.trust,
            "trust_hash": self.trust_hash,
            "trust_subset": mask(self.trust_subset, VALUE_SOURCE_KEYS),
        }

        if not self.errors:
            report["policy"] = {AUTO_ACCEPT: self.table.get(AUTO_ACCEPT)}

        return report

    def accept(self, approved_hash: str) -> dict[str, object]:
        """Pin the current policy only if it still matches the approved hash."""

        def current() -> Mapping[str, object]:
            config = AutoAcceptConfig(self.repo, state_home=self.state_home)

            if config.errors:
                raise InvalidConfig("invalid config cannot be trusted")

            return config.trust_subset

        self.store.accept(approved_hash, current)

        return {"trusted": approved_hash}


def _doc_path_reason(repo: Path, path: str) -> str | None:
    if "'" in path or any(ord(character) < 0x20 or ord(character) == 0x7F for character in path):
        return "unsafe characters"

    lexical = path

    while lexical.startswith("./"):
        lexical = lexical[2:]

    candidate = Path(lexical)

    if not lexical or candidate.is_absolute() or ".." in candidate.parts:
        return "outside the repository"

    # Resolve the complete parent, including dangling symlinks. The final file
    # may not exist yet, but must not itself be a symbolic link.
    try:
        parent = (repo / candidate.parent).resolve(strict=False)
    except (OSError, RuntimeError):
        return "unresolvable path"

    if not parent.is_relative_to(repo):
        return "outside the repository"

    if (repo / candidate).is_symlink():
        return "symbolic link"

    physical = (parent / candidate.name).relative_to(repo)

    if physical.suffix.lower() in DOC_SUFFIXES and (
        (physical.parts and physical.parts[0] in DOC_DIRS)
        or physical.stem.upper() in DOC_STEMS
    ):
        return None

    return "not a documentation path" if physical == candidate else f"resolves to {physical.as_posix()}"


def classify_doc_paths(repo: Path, paths: list[str]) -> dict[str, object]:
    """Classify lexical and physical documentation paths, preserving input order."""

    root = repo.resolve()
    documentation: list[str] = []
    other: list[str] = []
    reasons: dict[str, str] = {}

    for path in paths:
        reason = _doc_path_reason(root, path)

        if reason is None:
            documentation.append(path)
        else:
            other.append(path)
            reasons[path] = reason

    return {"documentation": documentation, "other": other, "reasons": reasons}


class UsageError(ConfigError):
    """Invalid command syntax, without echoing user-provided values."""


class Parser(argparse.ArgumentParser):
    def error(self, message: str) -> NoReturn:
        raise UsageError("invalid command arguments; use --help")

    def format_help(self) -> str:
        return json.dumps({"help": super().format_help()}, sort_keys=True) + "\n"


def repo_option(parser: argparse.ArgumentParser) -> argparse.ArgumentParser:
    parser.add_argument("--repo", type=Path, default=argparse.SUPPRESS)

    return parser


def parser() -> argparse.ArgumentParser:
    root = repo_option(Parser(description="Code-review auto-accept engine (JSON output)"))
    root.set_defaults(repo=None)
    commands = root.add_subparsers(dest="command", required=True)
    repo_option(commands.add_parser("config"))
    trust = repo_option(commands.add_parser("trust"))
    operations = trust.add_subparsers(dest="operation", required=True)
    accept = repo_option(operations.add_parser("accept"))
    accept.add_argument("hash")
    doc_paths = repo_option(commands.add_parser("doc-paths"))
    doc_paths.add_argument("paths", nargs="+")

    return root


def repository(explicit: Path | None) -> Path:
    if explicit is not None:
        if not explicit.is_dir():
            raise UsageError("repository root is not a directory")

        return explicit.resolve()

    result = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=False,
    )

    if result.returncode:
        raise UsageError("repository root unavailable; supply --repo")

    return Path(result.stdout.strip()).resolve()


def execute(args: argparse.Namespace) -> tuple[dict[str, object], int]:
    repo = repository(args.repo)

    if args.command == "doc-paths":
        return classify_doc_paths(repo, args.paths), 0

    config = AutoAcceptConfig(repo)

    if args.command == "trust":
        return config.accept(args.hash), 0

    return config.report(), 2 if config.errors else 0


def main(argv: Sequence[str] | None = None) -> int:
    try:
        args = parser().parse_args(argv)
        result, code = execute(args)
    except (UsageError, InvalidConfig) as error:
        result, code = {"error": str(error)}, 2
    except ConfigError as error:
        result, code = {"error": str(error)}, 1
    except (OSError, UnicodeError):
        # File/process errors may contain paths or values in their details.
        result, code = {"error": "auto-accept engine I/O operation failed"}, 1

    print(json.dumps(result, sort_keys=True))

    return code


if __name__ == "__main__":
    raise SystemExit(main())
