"""Section-preserving compare-and-swap configuration transactions."""
from __future__ import annotations

from collections.abc import Callable
from collections.abc import Mapping
from difflib import unified_diff
import hashlib
import json
from pathlib import Path
import re
import tomllib
from typing import cast

from av_config.errors import ConfigError
from av_config.errors import InvalidConfig
from av_config.files import Diagnostic
from av_config.files import atomic_write
from av_config.files import read_bytes
from av_config.sources import mask

TABLE = re.compile(r"^\s*(\[\[?[^\]\n]+\]\]?)\s*(?:#.*)?$")
ALLOWED_IGNORES = frozenset({".av/local.toml", ".av/secrets.local.env"})


def _fingerprint(content: bytes | None) -> str | None:
    return hashlib.sha256(content).hexdigest() if content is not None else None


def _key_paths(value: Mapping[str, object], prefix: tuple[str, ...] = ()) -> dict[tuple[str, ...], object]:
    result: dict[tuple[str, ...], object] = {}
    for key, item in value.items():
        path = (*prefix, key)
        if isinstance(item, dict) and item:
            result.update(_key_paths(item, path))
        else:
            result[path] = item
    return result


def _permitted(key: tuple[str, ...], allowed: list[str]) -> bool:
    for prefix in allowed:
        parts = tuple(prefix.split("."))
        if key[:len(parts)] == parts:
            return True
    return False


def _protected_sections(text: str, allowed: list[str]) -> dict[tuple[str, ...], str]:
    """Keep non-whitespace TOML content and section comments byte-exact."""
    sections: dict[tuple[str, ...], list[str]] = {(): []}
    current: tuple[str, ...] = ()
    header = ""
    statement: list[str] = []
    comments: list[str] = []

    def finish_comments() -> None:
        if not _permitted(current, allowed):
            sections[current].extend(comments)
        comments.clear()

    def finish() -> None:
        if not statement:
            return
        chunk = "".join(statement)
        try:
            parsed = tomllib.loads(header + chunk)
        except tomllib.TOMLDecodeError:
            sections[current].append(chunk)
        else:
            paths = _key_paths(parsed)
            if not paths or not any(_permitted(path, allowed) for path in paths):
                sections[current].append(chunk)
        statement.clear()

    for line in text.splitlines(keepends=True):
        match = TABLE.fullmatch(line.rstrip("\r\n")) if not statement else None
        if match:
            header = match.group(1) + "\n"
            current = next(iter(_key_paths(tomllib.loads(header))))
            sections.setdefault(current, [])
            finish_comments()
            if not _permitted(current, allowed) and not any(tuple(key.split("."))[:len(current)] == current for key in allowed):
                sections[current].append(line)
            continue
        if not statement:
            if not line.strip():
                continue
            if line.lstrip().startswith("#"):
                comments.append(line)
                continue
        finish_comments()
        statement.append(line)
        try:
            tomllib.loads(header + "".join(statement))
        except tomllib.TOMLDecodeError:
            continue
        finish()
    finish()
    finish_comments()
    return {key: "".join(lines) for key, lines in sections.items() if lines}


class ConfigTransaction:
    """Preview and compare-and-swap the shared config and root ignore file.

    A snapshot contains content hashes, never file contents. Originals read at
    apply time are rollback snapshots only after they match those hashes.
    """

    def __init__(self, repo: Path, validate: Callable[[str, str], dict[str, object]], accept: Callable[[str], object], *, value_source_keys: re.Pattern[str]) -> None:
        self.repo = repo.resolve()
        self.validate = validate
        self.accept = accept
        self.value_source_keys = value_source_keys
        self.paths = (self.repo / ".av/config.toml", self.repo / ".gitignore")

    def _proposal(self, proposal: Mapping[str, object], original_ignore: bytes | None) -> tuple[str, str, list[str]]:
        if set(proposal) != {"config_text", "gitignore_add", "allowed_keys"}:
            raise InvalidConfig("proposal: expected config_text, gitignore_add and allowed_keys")
        text, additions, allowed = proposal["config_text"], proposal["gitignore_add"], proposal["allowed_keys"]
        if not isinstance(text, str) or not isinstance(additions, list) or not isinstance(allowed, list):
            raise InvalidConfig("proposal: invalid transaction types")
        if any(not isinstance(key, str) or not key or "\n" in key for key in allowed):
            raise InvalidConfig("proposal.allowed_keys: expected key paths")
        if any(not isinstance(line, str) or line not in ALLOWED_IGNORES for line in additions):
            raise InvalidConfig("proposal.gitignore_add: only the standard personal-file entries are allowed")
        try:
            ignore = original_ignore.decode() if original_ignore is not None else ""
        except UnicodeError as error:
            raise ConfigError(".gitignore: invalid text encoding") from error
        for line in additions:
            if line not in ignore.splitlines():
                if ignore and not ignore.endswith("\n"):
                    ignore += "\n"
                ignore += line + "\n"
        return text, ignore, cast(list[str], allowed)

    def preview(self, proposal: Mapping[str, object]) -> dict[str, object]:
        originals = tuple(read_bytes(path) for path in self.paths)
        snapshot = json.dumps({"config": _fingerprint(originals[0]), "gitignore": _fingerprint(originals[1])}, separators=(",", ":"))
        text, ignore, allowed = self._proposal(proposal, originals[1])
        report = self.validate(text, ignore)
        errors = list(cast(list[Diagnostic], report.get("errors", [])))
        if errors:
            return {"ok": False, "errors": errors, "diff": [], "trust_subset": {}, "trust_hash": None, "snapshot": snapshot}
        try:
            original = originals[0].decode() if originals[0] is not None else ""
        except UnicodeError as error:
            raise ConfigError(".av/config.toml: invalid text encoding") from error
        try:
            old_data = tomllib.loads(original) if original else {}
            new_data = tomllib.loads(text)
        except tomllib.TOMLDecodeError:
            errors.append({"file": ".av/config.toml", "key": "document", "error": "invalid original TOML"})
            return {"ok": False, "errors": errors, "diff": [], "trust_subset": {}, "trust_hash": None, "snapshot": snapshot}
        before_keys = {key: value for key, value in _key_paths(old_data).items() if not isinstance(value, dict)}
        after_keys = {key: value for key, value in _key_paths(new_data).items() if not isinstance(value, dict)}
        changed = {
            key for key in before_keys.keys() | after_keys.keys()
            if key not in before_keys or key not in after_keys
            or json.dumps(before_keys[key], sort_keys=True, default=str) != json.dumps(after_keys[key], sort_keys=True, default=str)
        }
        for key in changed:
            if not _permitted(key, allowed):
                errors.append({"file": ".av/config.toml", "key": ".".join(key), "error": "proposal changes an unapproved key"})
        protected_before = _protected_sections(original, allowed)
        protected_after = _protected_sections(text, allowed)
        if originals[0] is None:
            protected_after.pop((), None)
        if protected_before != protected_after:
            errors.append({"file": ".av/config.toml", "key": "allowed_keys", "error": "proposal changes an unapproved section, key or comment"})
        if errors:
            return {"ok": False, "errors": errors, "diff": [], "trust_subset": {}, "trust_hash": None, "snapshot": snapshot}
        # A semantic, masked diff avoids copying local literals or secret text
        # into stdout. Protected non-whitespace content was compared above.
        before = json.dumps(mask(old_data, self.value_source_keys), indent=2, sort_keys=True, default=str).splitlines()
        after = json.dumps(mask(new_data, self.value_source_keys), indent=2, sort_keys=True, default=str).splitlines()
        diff = "\n".join(unified_diff(before, after, fromfile=".av/config.toml", tofile="proposed .av/config.toml", lineterm=""))
        # Show every ignore addition without exposing unrelated existing lines.
        ignore_before = originals[1].decode().splitlines() if originals[1] is not None else []
        ignore_diff = "\n".join(unified_diff(ignore_before, ignore.splitlines(), fromfile=".gitignore", tofile="proposed .gitignore", n=0, lineterm=""))
        diff = "\n".join(part for part in (diff, ignore_diff) if part)
        return {"ok": True, "errors": [], "diff": diff, "gitignore_add": proposal["gitignore_add"], "trust_subset": report["trust_subset"], "trust_hash": report["trust_hash"], "snapshot": snapshot}

    def apply(self, proposal: Mapping[str, object], snapshot: str, approved_hash: str) -> dict[str, object]:
        try:
            expected = json.loads(snapshot)
        except (ValueError, TypeError) as error:
            raise InvalidConfig("snapshot: invalid token") from error
        if not isinstance(expected, dict) or set(expected) != {"config", "gitignore"}:
            raise InvalidConfig("snapshot: invalid token")
        originals = tuple(read_bytes(path) for path in self.paths)
        if expected != {"config": _fingerprint(originals[0]), "gitignore": _fingerprint(originals[1])}:
            raise ConfigError("configuration conflict: files changed after preview")
        preview = self.preview(proposal)
        if not preview["ok"]:
            raise InvalidConfig("proposal: validation or section guard failed")
        if preview["snapshot"] != snapshot:
            raise ConfigError("configuration conflict: files changed after preview")
        text, ignore, _ = self._proposal(proposal, originals[1])
        written = (text.encode(), ignore.encode())
        applied: list[int] = []
        try:
            for index, path in enumerate(self.paths):
                if read_bytes(path) != originals[index]:
                    raise ConfigError("configuration conflict: files changed during apply")
                atomic_write(path, written[index])
                applied.append(index)
            actual_text = read_bytes(self.paths[0])
            actual_ignore = read_bytes(self.paths[1])
            if (actual_text, actual_ignore) != written:
                raise ConfigError("configuration conflict: files changed during apply")
            report = self.validate(text, ignore)
            if report.get("errors") or report.get("trust_hash") != approved_hash:
                raise ConfigError("post-write validation or approved hash check failed")
            self.accept(approved_hash)
        except (ConfigError, OSError) as error:
            conflicts = False
            for index in applied:
                path = self.paths[index]
                if read_bytes(path) != written[index]:
                    conflicts = True
                    continue
                if originals[index] is None:
                    path.unlink(missing_ok=True)
                else:
                    atomic_write(path, cast(bytes, originals[index]))
            if conflicts:
                raise ConfigError("configuration conflict: concurrent edits left untouched") from error
            if isinstance(error, ConfigError):
                raise
            raise ConfigError("configuration transaction failed") from error
        return {"applied": True}
