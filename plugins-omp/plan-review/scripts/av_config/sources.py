"""Value-source restrictions, resolution and schema-directed masking."""
from __future__ import annotations

from collections.abc import Callable
from collections.abc import Mapping
from dataclasses import dataclass
import os
from pathlib import Path
import re
import signal
import subprocess
import tempfile

from av_config.errors import ConfigError

SOURCE_KINDS = ("cmd:", "env:", "file:", "literal:")
NAME = re.compile(r"[A-Za-z_][A-Za-z0-9_]*\Z")


@dataclass(frozen=True)
class SourceRule:
    """Restrictions selected by schema validation for one source key."""

    local: bool
    secret: bool
    literal_allowed: bool


def mask(value: object, value_source_keys: re.Pattern[str], prefix: str = "") -> object:
    """Hide literal payloads only at the consumer's declared value-source keys.

    Accept nested config tables and dotted trust-subset keys without treating
    recipe or lifecycle command text as a secret.
    """
    if isinstance(value, str):
        return "literal:***" if value_source_keys.fullmatch(prefix) and value.startswith("literal:") else value
    if isinstance(value, dict):
        return {key: mask(item, value_source_keys, f"{prefix}.{key}" if prefix else key) for key, item in value.items()}
    if isinstance(value, list):
        return [mask(item, value_source_keys, f"{prefix}.{index}") for index, item in enumerate(value)]
    return value


def flatten(value: Mapping[str, object], prefix: str = "") -> dict[str, object]:
    result: dict[str, object] = {}
    for key, item in value.items():
        path = f"{prefix}.{key}" if prefix else key
        if isinstance(item, dict) and item:
            result.update(flatten(item, path))
        else:
            result[path] = item
    return result


def source_subset(value: Mapping[str, object], prefix: str = "") -> dict[str, object]:
    result: dict[str, object] = {}

    def visit(item: object, key: str) -> None:
        if isinstance(item, str) and item.startswith(SOURCE_KINDS):
            result[key] = item
        elif isinstance(item, dict):
            for name, child in item.items():
                visit(child, f"{key}.{name}" if key else name)
        elif isinstance(item, list):
            for index, child in enumerate(item):
                visit(child, f"{key}.{index}")

    visit(value, prefix)
    return result


def _execute_source(command: str, key: str, *, repo: Path, environ: Mapping[str, str], timeout: float) -> str:
    """Default command executor; return decoded stdout without exposing output."""
    try:
        process = subprocess.Popen(["/bin/sh", "-c", command], cwd=repo, env=environ, stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
    except OSError as error:
        raise ConfigError(f"{key}: command source unavailable") from error
    try:
        stdout, _ = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired as error:
        os.killpg(process.pid, signal.SIGKILL)
        process.communicate()
        raise ConfigError(f"{key}: command source timed out") from error
    if process.returncode:
        raise ConfigError(f"{key}: command source failed")
    try:
        return stdout.decode()
    except UnicodeError as error:
        raise ConfigError(f"{key}: invalid command source output") from error


class ValueSources:
    """Validate sources first; require trust before resolution."""

    def __init__(self, repo: Path, *, plugin_prefix: str, environ: Mapping[str, str] | None = None, timeout: float = 30, gitignore_text: str | None = None) -> None:
        self.repo = repo.resolve()
        self.plugin_prefix = plugin_prefix
        self.environ = dict(os.environ if environ is None else environ)
        self.timeout = timeout
        self.gitignore_text = gitignore_text

    def ignored(self, path: Path) -> bool:
        relative = path.absolute().relative_to(self.repo)
        if self.gitignore_text is None:
            result = subprocess.run(["git", "check-ignore", "-q", "--", str(relative)], cwd=self.repo, capture_output=True, check=False)
            return result.returncode == 0
        # Ask git itself to interpret the virtual ignore file: its negation,
        # anchoring, directory and wildcard rules are not shell glob rules.
        gitdir = subprocess.run(["git", "rev-parse", "--absolute-git-dir"], cwd=self.repo, capture_output=True, text=True, check=False)
        if gitdir.returncode != 0:
            return False
        with tempfile.TemporaryDirectory(prefix="av-ignore-") as temporary:
            worktree = Path(temporary)
            (worktree / ".gitignore").write_text(self.gitignore_text)
            parent = relative.parent
            for ancestor in (*reversed(parent.parents), parent):
                if ancestor == Path("."):
                    continue
                original = self.repo / ancestor / ".gitignore"
                if original.is_file():
                    destination = worktree / ancestor / ".gitignore"
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    destination.write_bytes(original.read_bytes())
            result = subprocess.run(["git", f"--git-dir={gitdir.stdout.strip()}", f"--work-tree={worktree}", "check-ignore", "-q", "--", str(relative)], cwd=worktree, capture_output=True, check=False)
            return result.returncode == 0

    def validate(self, source: object, key: str, *, local: bool = False, secret: bool = False, literal_allowed: bool = False) -> str | None:
        if not isinstance(source, str) or not source.startswith(SOURCE_KINDS):
            return "expected a value source"
        kind, payload = source.split(":", 1)
        if not payload:
            return "empty value source"
        if kind == "env":
            return self._validate_environment_source(payload, key, local=local)
        if kind == "file":
            return self._validate_file_source(payload, local=local)
        if kind == "literal" and secret and not local and not literal_allowed:
            return "secret literal is forbidden in shared config"
        return None

    def _validate_environment_source(self, payload: str, key: str, *, local: bool) -> str | None:
        if not NAME.fullmatch(payload):
            return "invalid environment source name"
        prefixes = ("AV_", self.plugin_prefix) if not key.startswith("env.") else ("AV_",)
        if not local and not payload.startswith(prefixes):
            return "environment source name has a forbidden prefix"
        return None

    def _validate_file_source(self, payload: str, *, local: bool) -> str | None:
        filename, separator, name = payload.rpartition("#")
        if not separator or not filename or not NAME.fullmatch(name):
            return "expected file source with a key"
        path = Path(filename)
        if path.is_absolute():
            if not local:
                return "absolute file source is forbidden in shared config"
        else:
            path = self.repo / path
            if not path.resolve().is_relative_to(self.repo):
                return "file source escapes the repository"
            if not self.ignored(path):
                return "repository file source must be git-ignored"
        return None

    def resolve(self, source: str, key: str, *, trusted: bool, execute: Callable[[str, str], str] | None = None,
                local: bool = False, secret: bool = False, literal_allowed: bool = False) -> str:
        """Resolve one validated source; errors contain keys and kinds, not data."""
        if not trusted:
            raise ConfigError(f"{key}: trust required")
        problem = self.validate(source, key, local=local, secret=secret, literal_allowed=literal_allowed)
        if problem:
            raise ConfigError(f"{key}: {problem}")
        kind, payload = source.split(":", 1)
        if kind == "literal":
            result = payload
        elif kind == "env":
            result = self.environ.get(payload, "")
        elif kind == "file":
            filename, _, name = payload.rpartition("#")
            path = Path(filename)
            if not path.is_absolute():
                path = self.repo / path
            try:
                text = path.read_text()
            except (OSError, UnicodeError) as error:
                raise ConfigError(f"{key}: file source unavailable") from error
            result = ""
            for line in text.splitlines():
                match = re.match(r"\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$", line)
                if match and match.group(1) == name:
                    raw = match.group(2).strip()
                    if raw.startswith(('"', "'")):
                        quote = raw[0]
                        end = raw.rfind(quote)
                        if end == 0 or (raw[end + 1:].strip() and not raw[end + 1:].lstrip().startswith("#")):
                            raise ConfigError(f"{key}: invalid file source")
                        result = raw[1:end]
                    else:
                        result = re.split(r"\s+#", raw, maxsplit=1)[0].rstrip()
        else:
            output = execute(payload, key) if execute is not None else _execute_source(payload, key, repo=self.repo, environ=self.environ, timeout=self.timeout)
            result = output.rstrip("\n")
        if not result:
            raise ConfigError(f"{key}: empty {kind} source")
        return result


