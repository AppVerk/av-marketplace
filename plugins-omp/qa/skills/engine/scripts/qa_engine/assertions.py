"""Plan assertion identities and deterministic scenario ordering."""
from __future__ import annotations

from collections.abc import Iterable
import re
from typing import Any

from qa_engine.common import ASSERTION_KEY
FAILING = frozenset({"FAIL"})


def _scenario_of(key: str) -> str:
    match = ASSERTION_KEY.fullmatch(key)
    return match.group(1) if match else key


def _forget(entries: dict[str, Any], sid: str) -> None:
    for key in [key for key in entries if key == sid or key.startswith(f"{sid} (edge ")]:
        del entries[key]


def _ordered(ids: Iterable[str]) -> list[str]:
    def order(sid: str) -> tuple[int, int, str]:
        match = re.fullmatch(r"(FE|BE)-(\d+)", sid)
        return (0 if sid.startswith("FE") else 1, int(match.group(2)) if match else 0, sid)
    return sorted(set(ids), key=order)


