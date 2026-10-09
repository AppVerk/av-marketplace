"""Leaf file helpers for plan fingerprints, display paths and sidecar JSON."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

from av_config.errors import ConfigError


def _plan_hash(path: Path) -> str | None:
    try:
        return hashlib.sha256(path.read_bytes()).hexdigest()
    except OSError:
        return None


def _load_json(path: Path) -> object:
    """The parsed file, ``None`` when absent; invalid JSON is a stop."""
    try:
        raw = path.read_text()
    except FileNotFoundError:
        return None
    try:
        return json.loads(raw)
    except ValueError as error:
        raise ConfigError(f"{path.name} is not valid JSON") from error


def display_path(repo: Path, path: Path) -> str:
    try:
        return str(path.relative_to(repo))
    except ValueError:
        return str(path)
