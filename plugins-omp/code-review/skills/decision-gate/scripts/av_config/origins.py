"""HTTP origins and exact-loopback transport policy."""
from __future__ import annotations

from urllib.parse import urlsplit

from av_config.errors import ConfigError

Origin = tuple[str, str, int]


def parse_origin(url: str, *, origin_only: bool = False) -> Origin:
    """Return the exact HTTP origin, rejecting credentials and malformed URLs.

    ``origin_only`` also rejects paths (including a trailing slash), query and
    fragment; the default accepts resource URLs for consumer origin guards.
    """
    try:
        parts = urlsplit(url)
        host = parts.hostname
        port = parts.port
    except ValueError as error:
        raise ConfigError("invalid origin") from error
    if (
        parts.scheme not in {"http", "https"} or not host or not parts.netloc
        or parts.username is not None or parts.password is not None
        or any(character.isspace() or ord(character) < 32 for character in url)
        or "\\" in url or "%" in host
        or (origin_only and (parts.path or "?" in url or "#" in url))
        or port == 0 or parts.netloc.endswith(":")
    ):
        raise ConfigError("invalid origin")
    return parts.scheme.lower(), host.lower(), port if port is not None else (443 if parts.scheme == "https" else 80)


def is_loopback(host: str) -> bool:
    normalized = host.lower().removeprefix("[").removesuffix("]")
    return normalized in {"localhost", "127.0.0.1", "::1"} or normalized.endswith(".localhost")


def require_secure_transport(url: str) -> None:
    """Keep recipe and probe traffic on HTTPS except exact loopback hosts."""
    scheme, host, _ = parse_origin(url)
    if scheme != "https" and not is_loopback(host):
        raise ConfigError("non-loopback targets must use https")


