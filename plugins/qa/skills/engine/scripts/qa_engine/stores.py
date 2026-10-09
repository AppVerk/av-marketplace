"""Named store endpoints and private native-client connection values."""
from __future__ import annotations

from collections.abc import Iterable
from collections.abc import Mapping
from pathlib import Path
from typing import TYPE_CHECKING
from typing import cast

if TYPE_CHECKING:
    from qa_engine.config import Config
    from qa_engine.services import Runtime


def store_lock_key(name: str, store: Mapping[str, object], repo: Path) -> str:
    """Coordinate identical configured endpoints, not aliases of the same host."""
    if store["kind"] == "redis":
        return f"redis:{str(store['host']).lower()}:{store.get('port', 6379)}/{store.get('db', 0)}"
    if store["engine"] == "sqlite":
        return f"sql:{(repo / str(store['path'])).resolve()}"
    port = store.get("port", 5432 if store["engine"] == "postgres" else 3306)
    return f"sql:{str(store['host']).lower()}:{port}/{store['name']}"


def store_values(runtime: Runtime, config: Config, names: Iterable[str]) -> dict[str, str]:
    """Resolve only referenced stores into namespaced native-client variables."""
    values: dict[str, str] = {}
    for name in sorted(set(names)):
        store = cast(Mapping[str, object], config.stores[name])
        prefix = f"STORE_{name.upper()}_"
        kind = store["engine"] if store["kind"] == "sql" else "redis"
        if kind == "sqlite":
            native = {"SQLITE_DB": str((runtime.run.repo / str(store["path"])).resolve())}
        elif kind == "redis":
            native = {"REDIS_HOST": str(store["host"]), "REDIS_PORT": str(store.get("port", 6379)),
                      "REDIS_DB": str(store.get("db", 0))}
            if "password" in store:
                native["REDISCLI_AUTH"] = runtime.resolve(str(store["password"]), f"env.stores.{name}.password")
        else:
            password = runtime.resolve(str(store["password"]), f"env.stores.{name}.password")
            if kind == "postgres":
                native = {"PGHOST": str(store["host"]), "PGPORT": str(store.get("port", 5432)),
                          "PGUSER": str(store["user"]), "PGDATABASE": str(store["name"]), "PGPASSWORD": password,
                          "PGOPTIONS": "-c default_transaction_read_only=on"}
            else:
                native = {"MYSQL_HOST": str(store["host"]), "MYSQL_TCP_PORT": str(store.get("port", 3306)),
                          "MYSQL_USER": str(store["user"]), "MYSQL_DATABASE": str(store["name"]), "MYSQL_PWD": password}
        values.update({prefix + key: value for key, value in native.items()})

    return values
