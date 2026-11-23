#!/usr/bin/env python3
"""Read `[plan-review] records` for the plan-review extension and print it as JSON.

Prints `{"records": <bool>, "warning": <str or null>}`. Records are off without a
configuration, without a `[plan-review]` table and whenever the configuration is
invalid. The warning names the problems only when a `[plan-review]` table exists,
so a repository that configures other plugins never sees one.
"""
from __future__ import annotations

import argparse
from collections.abc import Sequence
import json
from pathlib import Path
import subprocess
import sys

OFF: dict[str, object] = {"records": False, "warning": None}

# The shared loader needs tomllib (Python 3.11). Older interpreters cannot read
# the setting, so records stay off, as documented in docs/plugins/plan-review.md.
if sys.version_info < (3, 11):
    print(json.dumps(OFF))
    raise SystemExit(0)

from av_config.errors import ConfigError  # noqa: E402
from av_config.files import Configuration  # noqa: E402

TABLE = "plan-review"
RECORDS = "records"
USER_KEYS = {RECORDS}


def repository(cwd: Path) -> Path:
    """The git root of `cwd`, or `cwd` itself outside a repository."""
    try:
        result = subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=cwd, capture_output=True, text=True, check=False)
    except OSError:
        return cwd.resolve()
    root = result.stdout.strip()
    return Path(root).resolve() if result.returncode == 0 and root else cwd.resolve()


def setting(repo: Path) -> dict[str, object]:
    shared = Configuration(repo, plugin_prefix="AV_", user_table=TABLE, user_keys=USER_KEYS)
    configured = TABLE in shared.data
    # A table only in .av/local.toml does not configure the plugin (docs/configuration.md).
    local_only = shared.state(TABLE) in ("missing-file", "missing-table") and shared.file_for(TABLE) == ".av/local.toml"

    if configured and not local_only:
        table = shared.table(shared.data[TABLE], TABLE)
        shared.keys(table, USER_KEYS, TABLE)

        if RECORDS in table and type(table[RECORDS]) is not bool:
            shared.error(f"{TABLE}.{RECORDS}", "expected true or false")

    state = shared.state(TABLE)

    if state == "ok":
        table = shared.data[TABLE]
        return {"records": isinstance(table, dict) and table.get(RECORDS) is True, "warning": None}

    if state == "invalid" and configured:
        problems = "; ".join(f"{error['file']}: {error['key']}: {error['error']}" for error in shared.errors)
        return {
            "records": False,
            "warning": f"Plan review saves no record of this call: the configuration is invalid ({problems}). See docs/configuration.md.",
        }

    return OFF


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Print plan-review's [plan-review] records setting as JSON.")
    parser.add_argument("--cwd", type=Path, required=True, help="the session's working directory")
    args = parser.parse_args(argv)

    try:
        result = setting(repository(args.cwd))
    except ConfigError as error:
        result = {"records": False, "warning": f"Plan review saves no record of this call: {error}."}

    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
