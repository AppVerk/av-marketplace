"""Tracked working-tree fingerprints used by fix recovery."""
from __future__ import annotations

import hashlib
from pathlib import Path
import subprocess

from av_config.errors import ConfigError


def git_command(repo: Path, *args: str) -> subprocess.CompletedProcess[str]:
    """Run Git with the engine's bounded timeout, leaving exit-status policy to callers."""
    try:
        return subprocess.run(
            ["git", "-c", "core.quotePath=false", *args], cwd=repo, capture_output=True, text=True, check=False, timeout=30,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise ConfigError("git operation failed") from error


def _git(repo: Path, *args: str) -> str:
    result = git_command(repo, *args)
    if result.returncode:
        raise ConfigError("git operation failed")
    return result.stdout


def _dirty(repo: Path) -> dict[str, str]:
    """Tracked paths modified against HEAD, each with a content fingerprint."""
    names = [name for name in _git(repo, "diff", "--name-only", "-z", "HEAD").split("\0") if name]
    return {name: _fingerprint(repo / name) for name in names}


def _fingerprint(path: Path) -> str:
    try:
        return hashlib.sha256(path.read_bytes()).hexdigest()
    except FileNotFoundError:
        return "absent"
    except OSError:
        return "unreadable"


