"""QA's schema, capabilities, trust subset, and safe CLI display."""
from __future__ import annotations

from collections.abc import Mapping
from pathlib import Path
import re
from typing import cast

from av_config.errors import InvalidConfig
from av_config.transaction import ConfigTransaction
from av_config.files import Configuration
from av_config.trust import TrustStore
from av_config.trust import canonical_hash
from av_config.sources import mask
from av_config.sources import source_subset
from qa_engine.recipes import Recipe
from qa_engine.recipes import build_recipe

USER_NAME = re.compile(r"[a-z][a-z0-9_]*\Z")
RESERVED_USER_NAMES = frozenset({"new", "captured"})
RESERVED_USER_PREFIX = "captured_"
RESERVED_VALUE_NAMES = frozenset({"TAG", "NEW_PASSWORD"})
RESERVED_VALUE_PREFIX = "CAPTURED_"
CREDENTIAL_SUFFIX = re.compile(r".+_(TOKEN|COOKIE|COOKIE_[A-Z0-9_]+)\Z")
VALUE_SOURCE_KEYS = re.compile(
    r"(?:env\.(?:secrets|values)\.[A-Za-z_][A-Za-z0-9_]*|env\.stores\.[A-Za-z_][A-Za-z0-9_]*\.password|"
    r"qa\.users\.[a-z][a-z0-9_]*\.(?:email|password|id))"
)
POLICY = {"fix": "approve", "mutations": "deny", "start_services": "ask"}
FIX = ("approve", "auto", "off")
MUTATIONS = ("allow", "deny")
START_SERVICES = ("ask", "auto")
SECTION_TARGETS = {"FE": "ui", "BE": "backend"}
STORE_NAMES = {
    "postgres": ("PGHOST", "PGPORT", "PGUSER", "PGDATABASE", "PGPASSWORD", "PGOPTIONS"),
    "mysql": ("MYSQL_HOST", "MYSQL_TCP_PORT", "MYSQL_USER", "MYSQL_DATABASE", "MYSQL_PWD"),
    "sqlite": ("SQLITE_DB",),
    "redis": ("REDIS_HOST", "REDIS_PORT", "REDIS_DB", "REDISCLI_AUTH"),
}


def mapping(value: object) -> dict[str, object]:
    return value if isinstance(value, dict) else {}




class Config:
    """Effective QA configuration. Construction validates when the shared file exists.

    ``data`` retains the effective unmasked config for engine consumers;
    ``report()`` is the only tester/orchestrator display surface. ``accept``
    always reloads from disk so a stale object cannot approve a changed file.
    """

    def __init__(self, repo: Path, *, state_home: Path | None = None, config_text: str | None = None, gitignore_text: str | None = None) -> None:
        self.repo = repo.resolve()
        self.state_home = state_home
        self.shared = Configuration(self.repo, plugin_prefix="QA_", config_text=config_text, gitignore_text=gitignore_text)
        self.data = self.shared.data
        self.errors = self.shared.errors
        self.warnings = self.shared.warnings
        self.provenance = self.shared.provenance
        self.store = TrustStore(self.repo, "qa", state_home)
        self.qa = mapping(self.data.get("qa"))
        self.env = mapping(self.data.get("env"))
        self.targets = cast(dict[str, str], mapping(self.env.get("targets")))
        self.users = mapping(self.qa.get("users"))
        self.cleanup = mapping(self.qa.get("cleanup"))
        self.cleanup_recipe: Recipe | None = None
        self.policy = {**POLICY, **{key: self.qa[key] for key in POLICY if key in self.qa}}
        self.services = mapping(self.env.get("services"))
        self.values = mapping(self.env.get("values"))
        self.stores = mapping(self.env.get("stores"))
        if self.shared.exists and "qa" in self.data:
            self._validate()
        self.trust_subset = self._sensitive_subset() if not self.errors else {}
        self.trust_hash = canonical_hash(self.trust_subset)
        self.trust = self.store.status(self.trust_subset)

    @property
    def state(self) -> str:
        return self.shared.state("qa")

    def section_target(self, section: str) -> str | None:
        """Use the section's reserved target name, or the only configured target."""
        name = SECTION_TARGETS[section]
        if name in self.targets:
            return name
        if len(self.targets) == 1:
            return next(iter(self.targets))
        return None

    def _validate(self) -> None:
        validator = self.shared
        qa = validator.table(self.data["qa"], "qa")
        validator.keys(qa, {"fix", "mutations", "start_services", "users", "cleanup"}, "qa")
        for key, allowed in (("fix", FIX), ("mutations", MUTATIONS), ("start_services", START_SERVICES)):
            if key in qa and qa[key] not in allowed:
                validator.error(f"qa.{key}", "unsupported policy value")
        self._validate_users()
        self._validate_cleanup()
        self._validate_names()

    def _validate_users(self) -> None:
        validator = self.shared
        if "users" in self.qa:
            validator.table(self.qa["users"], "qa.users")
        for name, value in self.users.items():
            prefix = f"qa.users.{name}"
            if not USER_NAME.fullmatch(name):
                validator.error(prefix, "invalid user name")
            if name in RESERVED_USER_NAMES or name.startswith(RESERVED_USER_PREFIX):
                validator.error(prefix, "reserved user name")
            entry = validator.table(value, prefix)
            validator.keys(entry, {"email", "password", "id", "description"}, prefix)
            for key in ("email", "password"):
                if key not in entry:
                    validator.error(f"{prefix}.{key}", "required account source")
                else:
                    validator.source(entry[key], f"{prefix}.{key}", secret=key == "password")
            if "id" in entry:
                validator.source(entry["id"], f"{prefix}.id")
            if not isinstance(entry.get("description"), str) or not entry["description"].strip():
                validator.error(f"{prefix}.description", "expected a description")

    def _validate_cleanup(self) -> None:
        if "cleanup" in self.qa:
            self.cleanup_recipe = build_recipe(self.shared.table(self.qa["cleanup"], "qa.cleanup"), "cleanup", self)

    def user_fields(self, user: str) -> set[str]:
        return {"EMAIL", "PASSWORD"} | ({"ID"} if "id" in mapping(self.users[user]) else set())

    def _validate_names(self) -> None:
        exposed: set[str] = set()
        for user in self.users:
            for field in self.user_fields(user):
                name = f"{user.upper()}_{field}"
                if name in exposed:
                    self.shared.error("qa.users", "user field names collide")
                exposed.add(name)
        for name in self.values:
            upper = name.upper()
            if upper in exposed or upper in RESERVED_VALUE_NAMES or upper.startswith(RESERVED_VALUE_PREFIX):
                self.shared.error(f"env.values.{name}", "value name collides with an exposed name")
            if CREDENTIAL_SUFFIX.fullmatch(upper):
                self.shared.error(f"env.values.{name}", "value name uses a reserved credential suffix")
            exposed.add(upper)

    def _sensitive_subset(self) -> dict[str, object]:
        subset = self.shared.env_sensitive_subset()
        subset.update(source_subset(self.qa, "qa"))
        if "cleanup" in self.qa:
            subset["qa.cleanup"] = self.qa["cleanup"]
        store = self.cleanup.get("store")
        if self.cleanup.get("kind") == "sql" and isinstance(store, str) and store in self.stores:
            subset[f"env.stores.{store}"] = self.stores[store]
        for key in POLICY:
            if key in self.qa:
                subset[f"qa.{key}"] = self.qa[key]
        return subset

    def report(self) -> dict[str, object]:
        """Return JSON-safe metadata, never source results or secret literals."""
        report: dict[str, object] = {"state": self.state, "errors": self.errors, "warnings": self.warnings, "provenance": self.provenance, "trust": self.trust, "trust_hash": self.trust_hash, "trust_subset": mask(self.trust_subset, VALUE_SOURCE_KEYS)}
        if self.errors:
            return report
        exposed = [f"QA_{user.upper()}_{field}" for user in self.users for field in self.user_fields(user)]
        exposed.extend(f"QA_{name.upper()}" for name in self.values)
        exposed.append("QA_NEW_PASSWORD")
        report.update({"targets": self.targets, "defaults": {"FE": self.section_target("FE"), "BE": self.section_target("BE")}, "policy": self.policy, "services": {"health": [], "up": None, "prepare": [], "down": None, **self.services}, "users": {name: mapping(entry).get("description") for name, entry in self.users.items()}, "values": sorted(self.values), "exposed": sorted(exposed), "stores": {name: {key: entry[key] for key in ("kind", "engine") if key in entry} for name, value in self.stores.items() if (entry := mapping(value))}})
        return report

    def accept(self, approved_hash: str) -> dict[str, object]:
        def current() -> Mapping[str, object]:
            config = Config(self.repo, state_home=self.state_home)
            if config.errors:
                raise InvalidConfig("invalid config cannot be trusted")
            return config.trust_subset
        self.store.accept(approved_hash, current)
        return {"trusted": approved_hash}

    def _transaction(self) -> ConfigTransaction:
        def validate(text: str, ignore: str) -> dict[str, object]:
            return Config(self.repo, state_home=self.state_home, config_text=text, gitignore_text=ignore).report()
        return ConfigTransaction(self.repo, validate, self.accept, value_source_keys=VALUE_SOURCE_KEYS)

    def preview(self, proposal: Mapping[str, object]) -> dict[str, object]:
        return self._transaction().preview(proposal)

    def apply(self, proposal: Mapping[str, object], snapshot: str, approved_hash: str) -> dict[str, object]:
        return self._transaction().apply(proposal, snapshot, approved_hash)
