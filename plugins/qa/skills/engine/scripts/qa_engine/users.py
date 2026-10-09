"""Configured users, durable registered-account cleanup and private run channels."""
from __future__ import annotations

from collections.abc import Iterator
from collections.abc import Mapping
from contextlib import ExitStack
from contextlib import contextmanager
import fcntl
import logging
from pathlib import Path
import re
import secrets
import shlex
from typing import TYPE_CHECKING
from typing import Any
from typing import cast

from av_config.errors import ConfigError
from av_config.files import atomic_write
from qa_engine.common import read_object
from qa_engine.common import write_json
from qa_engine.config import Config
from qa_engine.config import STORE_NAMES
from qa_engine.config import mapping
from qa_engine.plan import check_plan
from qa_engine.plan import run_plan
from qa_engine.plan import user_token
from qa_engine.secrets import private_values
from qa_engine.services import Runtime
from qa_engine.services import require_trust
from qa_engine.stores import store_values

if TYPE_CHECKING:
    from qa_engine.models import Run

JSON = dict[str, Any]
EMAIL_SAFE = re.compile(r"[A-Za-z0-9._+-]{1,64}@[A-Za-z0-9.-]{1,253}\Z")
ID_SAFE = re.compile(r"[A-Za-z0-9._:-]{1,128}\Z")
TAG_SAFE = re.compile(r"[0-9a-f]{8}\Z")
CLEANUP_ATTEMPTS = 3


class Ledger:
    """Cross-run, repository-scoped registrations survive private-directory removal."""

    def __init__(self, run: Run, config: Config) -> None:
        self.path = config.store.path.parent / "qa-accounts.json"
        self.repo = str(run.repo.resolve())
        self.data = read_object(self.path)
        records = self.data.setdefault(self.repo, [])
        if not isinstance(records, list) or any(not isinstance(item, dict) for item in records):
            raise ConfigError("qa-accounts.json: invalid ledger")
        self.records: list[JSON] = records

    def save(self) -> None:
        write_json(self.path, self.data, 0o600)


@contextmanager
def ledger(run: Run, config: Config) -> Iterator[Ledger]:
    path = config.store.path.parent / "qa-accounts.lock"
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a") as handle:
        path.chmod(0o600)
        fcntl.flock(handle, fcntl.LOCK_EX)
        yield Ledger(run, config)


def write_channel(run: Run, values: Mapping[str, str]) -> None:
    """Atomically write the private channel and its loader and capture helpers."""
    directory = run.directory
    lines: list[str] = []
    for name, value in sorted(values.items()):
        escaped = value.replace("'", "'\\''")
        lines.append(f"export {name}='{escaped}'\n")
    atomic_write(directory / "secrets.env", "".join(lines).encode(), 0o600)
    write_json(directory / "secrets.json", dict(values), 0o600)
    names = {name for name in values if not (name.startswith("STORE_") and name.endswith("_PGOPTIONS"))}
    clients = {client for clients in STORE_NAMES.values() for client in clients if client != "PGOPTIONS"}
    names.update(client for name in names.copy() if name.startswith("STORE_") for client in clients if name.endswith("_" + client))
    atomic_write(directory / "redact-names", ("".join(f"{name}\n" for name in sorted(names))).encode(), 0o600)
    atomic_write(directory / "load.sh", loader_script(directory).encode(), 0o600)
    atomic_write(directory / "capture.sh", capture_script(directory, run.run_id, run.repo).encode(), 0o600)


def loader_script(directory: Path) -> str:
    path = shlex.quote(str(directory / "secrets.env"))
    clients = " ".join(sorted({client for names in STORE_NAMES.values() for client in names}))
    return f'''# Private run channel. Set qa_load_store and qa_load_require before sourcing; no dot-script arguments.
qa_channel_store=${{qa_load_store:-}}
qa_channel_required=${{qa_load_require:-}}
unset qa_load_store qa_load_require
for qa_channel_name in $(set | cut -d= -f1); do
    case "$qa_channel_name" in
        *[!A-Za-z0-9_]*) continue ;;
        QA_*|PG*|MYSQL_*|SQLITE_DB|STORE_*|REDIS*) unset "$qa_channel_name" ;;
    esac
done
qa_channel_file={path}
if [ -L "$qa_channel_file" ] || [ ! -f "$qa_channel_file" ] || [ ! -r "$qa_channel_file" ] || [ ! -O "$qa_channel_file" ]; then
    printf '%s\\n' 'secrets.env: private readable regular file required' >&2
    return 1
fi
case "$-" in *a*) qa_channel_allexport=yes ;; *) qa_channel_allexport=no ;; esac
set -a
. "$qa_channel_file"
qa_channel_status=$?
[ "$qa_channel_allexport" = yes ] || set +a
[ "$qa_channel_status" = 0 ] || return 1
if [ -n "$qa_channel_store" ]; then
    case "$qa_channel_store" in *[!A-Za-z0-9_]*) printf '%s\\n' 'invalid store name' >&2; return 1 ;; esac
    qa_channel_store=$(printf '%s' "$qa_channel_store" | tr '[:lower:]' '[:upper:]')
    qa_channel_found=no
    for qa_channel_client in {clients}; do
        eval 'qa_channel_set=${{STORE_'"$qa_channel_store"'_'"$qa_channel_client"'+x}}'
        [ -n "$qa_channel_set" ] || continue
        eval 'qa_channel_value=${{STORE_'"$qa_channel_store"'_'"$qa_channel_client"'-}}'
        export "$qa_channel_client=$qa_channel_value"
        qa_channel_found=yes
    done
    if [ "$qa_channel_found" = no ]; then
        printf '%s: unknown store\\n' "$qa_channel_store" >&2
        return 1
    fi
    if [ -z "${{PGHOST:-}}${{MYSQL_HOST:-}}${{SQLITE_DB:-}}${{REDIS_HOST:-}}" ]; then
        printf '%s: store not exported\\n' "$qa_channel_store" >&2
        return 1
    fi
fi
case "$qa_channel_required" in *[!A-Z0-9_[:space:]]*) printf '%s\\n' 'invalid required channel name' >&2; return 1 ;; esac
for qa_channel_name in $qa_channel_required; do
    case "$qa_channel_name" in
        ''|*[!A-Z0-9_]*) printf '%s\\n' 'invalid required channel name' >&2; return 1 ;;
    esac
    eval 'qa_channel_value=${{'"$qa_channel_name"'-}}'
    if [ -z "$qa_channel_value" ]; then
        printf '%s: required value missing\\n' "$qa_channel_name" >&2
        unset qa_channel_value
        return 1
    fi
done
unset qa_channel_name qa_channel_file qa_channel_allexport qa_channel_status qa_channel_value qa_channel_store qa_channel_required qa_channel_client qa_channel_set qa_channel_found
'''


def capture_script(directory: Path, run_id: str, repo: Path) -> str:
    engine = shlex.quote(str(Path(__file__).resolve().parents[1] / "qa.py"))
    results = shlex.quote(str(directory / "results"))
    return f'''# Capture credentials privately or durably record a registration.
umask 077
[ "$#" -ge 2 ] || exit 1
case "$1" in D[0-9][0-9][0-9]*) ;; *) exit 1 ;; esac
case "$1" in *[!D0-9]*) exit 1 ;; esac
case "$2" in
    --account)
        [ "$#" -ge 3 ] && [ "$#" -le 4 ] || exit 1
        exec python3 {engine} users record --run {shlex.quote(run_id)} --dispatch "$1" --email "$3" ${{4:+--id "$4"}} --repo {shlex.quote(str(repo))}
        ;;
    QA_CAPTURED_*)
        case "$2" in QA_CAPTURED_|*[!A-Z0-9_]*) exit 1 ;; esac
        [ "$#" -eq 2 ] || exit 1
        ;;
    *) exit 1 ;;
esac
capture_dir={results}/"$1"
[ -d "$capture_dir" ] && [ -f "$capture_dir/captured.env" ] && [ -f "$capture_dir/redact-names" ] || exit 1
capture_value=$(cat; printf '.')
capture_value=${{capture_value%.}}
case "$capture_value" in *'
') capture_value=${{capture_value%?}} ;; esac
capture_quoted=$(printf '%s.' "$capture_value" | sed "s/'/'\\\\\\\\''/g")
capture_quoted=${{capture_quoted%.}}
printf "export %s='%s'\\n" "$2" "$capture_quoted" >> "$capture_dir/captured.env"
printf '%s\\n' "$2" >> "$capture_dir/redact-names"
'''


def prepare_capture(run: Run, dispatch: str) -> None:
    try:
        redact_names = (run.directory / "redact-names").read_bytes()
    except FileNotFoundError as exc:
        raise ConfigError("run users provision before dispatch") from exc
    directory = run.directory / "results" / dispatch
    directory.mkdir(parents=True, mode=0o700, exist_ok=True)
    directory.chmod(0o700)
    atomic_write(directory / "captured.env", b"", 0o600)
    atomic_write(directory / "redact-names", redact_names, 0o600)


def provision(run: Run, config: Config) -> JSON:
    require_trust(config)
    plan = run_plan(run)
    checked = check_plan(plan, config)
    if not checked["ok"]:
        raise ConfigError("plan requirements are not satisfied; run plan check")
    users = cast(list[str], checked["users"])
    values: dict[str, str] = {}
    requested = {recognized for scenario in plan.scenarios for token in scenario.tokens
                 if (recognized := user_token(token, users)) is not None}
    with Runtime(run, config) as runtime:
        for user, field in sorted(requested):
            source = mapping(config.users[user])[field.lower()]
            values[f"QA_{user.upper()}_{field}"] = runtime.resolve(str(source), f"qa.users.{user}.{field.lower()}")
        for name in cast(list[str], checked["values"]):
            values[f"QA_{name.upper()}"] = runtime.named("value", name)
        previous = read_object(run.directory / "secrets.json")
        values["QA_NEW_PASSWORD"] = str(previous["QA_NEW_PASSWORD"]) if "QA_NEW_PASSWORD" in previous else secrets.token_urlsafe(18) + "Aa1!"
        checks = cast(dict[str, list[str]], checked["state_checks"])
        values.update(store_values(runtime, config, {name for names in checks.values() for name in names}))
        runtime.secrets.remember(private_values(values))
        write_channel(run, values)
    return {"users": users, "exposed": sorted(values),
            "secrets_env": str(run.directory / "secrets.env"), "secrets_json": str(run.directory / "secrets.json"),
            "redact_names": str(run.directory / "redact-names"), "loader": str(run.directory / "load.sh")}


def _account_reason(email: str, account_id: object, tag: str, configured: set[str]) -> str | None:
    if not EMAIL_SAFE.fullmatch(email):
        return "invalid email"
    if account_id is not None and (not isinstance(account_id, str) or not ID_SAFE.fullmatch(account_id)):
        return "invalid id"
    if email in configured:
        return "configured user"
    if tag.lower() not in email.partition("@")[0].lower():
        return "email not tagged for this dispatch"
    return None


def record_accounts(run: Run, dispatch_id: str, tag: str, entries: list[JSON], config: Config | None = None) -> JSON:
    config = config if config is not None else Config(run.repo)
    values = read_object(run.directory / "secrets.json")
    configured = {str(value) for name, value in values.items() if name.startswith("QA_") and name.endswith("_EMAIL")}
    destination = config.cleanup_recipe.destination(config) if config.cleanup_recipe is not None and not config.errors else None
    recorded = 0
    rejected: set[str] = set()
    with ledger(run, config) as records:
        for entry in entries:
            email, account_id = str(entry["email"]), entry.get("id")
            if _account_reason(email, account_id, tag, configured):
                rejected.add(email)
                continue
            existing = next((item for item in records.records if (item.get("run_id"), item.get("dispatch"), item.get("email")) == (run.run_id, dispatch_id, email)), None)
            if existing is not None:
                if not existing.get("id") and account_id is not None:
                    existing["id"] = account_id
            else:
                records.records.append({"email": email, "id": account_id, "run_id": run.run_id, "tag": tag,
                                        "dispatch": dispatch_id, "destination": destination, "deleted": False,
                                        "status": "pending", "attempts": 0})
            recorded += 1
        records.save()
    return {"recorded": recorded, "rejected": sorted(rejected)}


def record_account_cli(run: Run, config: Config, dispatch: str, email: str, account_id: str | None) -> JSON:
    record = run.state["dispatches"].get(dispatch)
    if record is None or record["kind"] != "tester":
        raise ConfigError("unknown tester dispatch")
    values = read_object(run.directory / "secrets.json")
    configured = {str(value) for name, value in values.items() if name.startswith("QA_") and name.endswith("_EMAIL")}
    reason = _account_reason(email, account_id, record["tag"], configured)
    if reason:
        raise ConfigError(reason)
    record_accounts(run, dispatch, record["tag"], [{"email": email, "id": account_id}], config)
    return {"recorded": True}


def _cleanup_record_reason(record: JSON) -> str | None:
    """Refuse incomplete provenance or unsafe persisted identities before rendering."""
    if "tag" not in record or "destination" not in record:
        return "legacy record lacks tag or destination; manual cleanup required"
    email = record.get("email")
    if not isinstance(email, str) or not EMAIL_SAFE.fullmatch(email):
        return "invalid email"
    account_id = record.get("id")
    if account_id is not None and (not isinstance(account_id, str) or not ID_SAFE.fullmatch(account_id)):
        return "invalid id"
    tag = record["tag"]
    if not isinstance(tag, str) or not TAG_SAFE.fullmatch(tag):
        return "invalid tag"
    if tag not in email.partition("@")[0].lower():
        return "email not tagged for this dispatch"
    if record["destination"] is not None and not isinstance(record["destination"], str):
        return "invalid destination"
    attempts = record.get("attempts")
    if type(attempts) is not int or attempts < 0:
        return "invalid attempts"
    return None


def teardown(run: Run, config: Config) -> JSON:
    deleted: set[str] = set()
    left: set[str] = set()
    manual: set[str] = set()
    recipe = config.cleanup_recipe if not config.errors else None
    destination = recipe.destination(config) if recipe is not None else None
    usable = not config.errors and config.trust in {"trusted", "not-required"} and recipe is not None and destination in [*run.record["origins"], None]
    with ledger(run, config) as records, ExitStack() as stack:
        runtime: Runtime | None = None
        for index, record in enumerate(records.records, 1):
            if record.get("deleted") or record.get("status") == "manual-cleanup":
                continue
            email = record.get("email")
            reason = _cleanup_record_reason(record)
            if reason is not None:
                if isinstance(email, str) and email:
                    left.add(email)
                logging.getLogger(__name__).warning("qa-accounts.json: record %d left: %s", index, reason)
                continue
            assert isinstance(email, str)
            if not usable or (record.get("destination") is not None and record["destination"] != destination):
                left.add(email)
                continue
            assert recipe is not None
            record["destination"] = destination
            identity = {"email": email, "id": record.get("id") or "", "tag": record["tag"]}
            succeeded = False
            if not recipe.needs_id or record.get("id"):
                try:
                    if runtime is None:
                        runtime = stack.enter_context(Runtime(run, config))
                    runtime.secrets.remember(identity)
                    succeeded = recipe.succeeded(recipe.execute(runtime, identity, config.targets))
                except (ConfigError, OSError) as error:
                    logging.getLogger(__name__).warning("qa-accounts.json: record %d cleanup failed (%s)",
                                                        index, type(error).__name__)
                    succeeded = False
            if succeeded:
                record.update(deleted=True, status="deleted")
                deleted.add(email)
            else:
                record["attempts"] += 1
                if record["attempts"] >= CLEANUP_ATTEMPTS:
                    record["status"] = "manual-cleanup"
                    manual.add(email)
                else:
                    left.add(email)
            records.save()
    return {"deleted": sorted(deleted), "left": sorted(left), "manual": sorted(manual)}
