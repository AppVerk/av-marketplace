"""Parse QA scenarios, resolve branch plans, and check their config requirements.

Parsing never resolves a value source or runs a scenario. CLI reports contain
identifiers and sanitized origins, not scenario payloads or credential values.
Sections list scenario IDs in plan order; State Checks map them to store names.
User gaps carry ``name``, ``token``, and ``reason``; other gaps carry config names.
"""
from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass
from dataclasses import field
from pathlib import Path
import re

from av_config.errors import ConfigError
from av_config.origins import Origin
from av_config.origins import is_loopback
from av_config.origins import parse_origin
from qa_engine.config import Config
from qa_engine.config import CREDENTIAL_SUFFIX
from qa_engine.config import SECTION_TARGETS
from qa_engine.files import display_path
from qa_engine.common import origin_display
from qa_engine.git import git_command
from qa_engine.models import Run
from qa_engine.models import StateStop

SCENARIO = re.compile(r"^###[ \t]+((FE|BE)-\d{2,})(?=[ \t:]|$)[ \t]*:?[ \t]*(.*)$", re.MULTILINE)
BLOCK_BOUNDARY = re.compile(r"^#{1,3}[ \t]+.*$|^[ \t]*(?P<fence>`{3,}|~{3,})(?P<info>.*)$", re.MULTILINE)
FIELD = re.compile(r"^(?:-[ \t]*)?\*\*([^*\n]+?):\*\*[ \t]*(.*)$", re.MULTILINE)
TOKEN = re.compile(r"\$\{(QA_[A-Z0-9_]+)\}|\$(QA_[A-Z0-9_]+)(?![A-Za-z0-9_])")
URL = re.compile(r"https?://[^\s`\"'<>]+", re.IGNORECASE)
WRITE_ACTION = re.compile(r"\b(POST|PUT|PATCH|DELETE)\b", re.IGNORECASE)
SQL_WRITE = re.compile(r"\b(INSERT|UPDATE|DELETE|DROP|TRUNCATE|CREATE|UPSERT)\b", re.IGNORECASE)
REDIS_WRITE = re.compile(r"\b(SET|SETEX|SETNX|MSET|DEL|UNLINK|HSET|HDEL|LPUSH|RPUSH|LPOP|RPOP|SADD|SREM|ZADD|ZREM|INCR|INCRBY|DECR|DECRBY|EXPIRE|PERSIST|RENAME|APPEND|XADD|XDEL|FLUSHDB|FLUSHALL)\b", re.IGNORECASE)
STORE_PREFIX = re.compile(r"^`?([A-Za-z_][A-Za-z0-9_]*)`?:[ \t]+(.*)\Z", re.DOTALL)
WRITE_STEP = re.compile(r"\b(create|delete|update|insert|seed)\b", re.IGNORECASE)
CITATION = re.compile(r"\((`?[^()\s]+:\d+(?:-\d+)?`?)\)")
STATUS = re.compile(r"(?<![A-Za-z0-9_])([1-5]\d{2})(?![A-Za-z0-9_])")
USER_TOKEN = re.compile(r"(.+?)_(EMAIL|PASSWORD|ID)\Z")
ENGINE_TOKENS = frozenset({"TAG", "NEW_PASSWORD"})
USER_LINE = re.compile(r"^[ \t]*[-*][ \t]+([a-z][a-z0-9_]*)[ \t]*:[ \t]*(existing|registered)\b", re.MULTILINE)
RELATIVE_PATH = re.compile(r"(?<![A-Za-z0-9_:/])/(?!/)[A-Za-z0-9_{?]")


@dataclass
class Assertion:
    """An Expected or edge assertion with the flags used by execution guards."""

    text: str
    statuses: list[int] = field(init=False)
    unverified: bool = field(init=False)

    def __post_init__(self) -> None:
        self.statuses = [int(status) for status in STATUS.findall(CITATION.sub("", self.text))]
        self.unverified = bool(re.search(r"\(unverified\b", self.text, re.IGNORECASE))


@dataclass
class StateCheck:
    """One repeatable state assertion with an optional named-store prefix."""

    store: str | None
    text: str


@dataclass
class Scenario:
    """A scenario's original block and mechanically parsed execution requirements."""

    id: str
    section: str
    title: str
    text: str
    method: str | None
    path: str | None
    target: str | None
    writes: bool | None
    expected: Assertion
    edges: list[Assertion]
    state_checks: list[StateCheck]
    tokens: list[str]
    urls: list[str]
    actions: str
    other_steps: str

    @property
    def main_flow(self) -> str:
        """Return the original main flow without the edge-case field."""
        match = re.search(r"^(?:-\s*)?\*\*Edge cases:\*\*", self.text, re.MULTILINE | re.IGNORECASE)
        return self.text[:match.start()] if match else self.text


@dataclass
class Plan:
    """Source metadata and scenarios in the order the plan dispatches them."""

    path: Path
    branch: str | None
    head: str | None
    scenarios: list[Scenario]
    users: dict[str, str] = field(default_factory=dict)

    @property
    def sections(self) -> dict[str, list[str]]:
        return {section: [scenario.id for scenario in self.scenarios if scenario.section == section] for section in ("FE", "BE")}


def run_plan(run: Run, *, strict: bool = True) -> Plan:
    """Parse the run's plan; ``strict`` refuses a plan edited since ``run start``."""
    if strict and not run.plan_unchanged():
        raise StateStop("plan changed mid-run (hash mismatch)")
    return parse_plan(run.plan_path)


@dataclass
class _Field:
    name: str
    text: str


def _fields(text: str) -> list[_Field]:
    matches = list(FIELD.finditer(text))
    fields: list[_Field] = []
    preamble = text[:matches[0].start()] if matches else text
    preamble = preamble.partition("\n")[2].strip()
    if preamble:
        fields.append(_Field("steps", preamble))
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        continuation = text[match.end():end]
        content = (match.group(2) + continuation).strip("\r\n").rstrip()
        name = match.group(1).lower()
        # A sibling action bullet is not a continuation of an assertion or
        # request declaration. Keep it in the actions checked by both guards.
        sibling = re.search(r"^(?:[-*]|\d+[.)])[ \t]+(?!\*\*)", continuation, re.MULTILINE)
        if sibling and name not in {"steps", "preconditions", "edge cases"}:
            fields.append(_Field(name, (match.group(2) + continuation[:sibling.start()]).strip("\r\n").rstrip()))
            fields.append(_Field("steps", continuation[sibling.start():]))
        else:
            fields.append(_Field(name, content))
    return fields


def _edges(text: str) -> list[Assertion]:
    """Keep one assertion per edge bullet, including its continuation lines."""
    bullets = list(re.finditer(r"^([ \t]*)(?:[-*]|\d+[.)])[ \t]+(\S.*)$", text, re.MULTILINE))
    if not bullets:
        return [Assertion(text)] if text.strip() else []
    indentation = min(len(match.group(1)) for match in bullets)
    bullets = [match for match in bullets if len(match.group(1)) == indentation]
    return [
        Assertion((match.group(2) + text[match.end():bullets[index + 1].start() if index + 1 < len(bullets) else len(text)]).strip())
        for index, match in enumerate(bullets)
    ]


def _source(text: str) -> tuple[str | None, str | None]:
    section = re.search(r"^##[ \t]+Source[ \t]*$", text, re.MULTILINE | re.IGNORECASE)
    if section is None:
        return None, None
    following = re.search(r"^#{1,2}\s+", text[section.end():], re.MULTILINE)
    source = text[section.end():section.end() + following.start() if following else len(text)]
    metadata: dict[str, str] = {}
    for match in re.finditer(r"^[ \t]*(?:-[ \t]*)?(?:\*\*)?(Branch|Head):(?:\*\*)?[ \t]*(.*)$", source, re.MULTILINE | re.IGNORECASE):
        metadata[match.group(1).lower()] = match.group(2).strip().strip("`")
    return metadata.get("branch"), metadata.get("head")


def _users_section(text: str) -> dict[str, str]:
    section = re.search(r"^## Users[ \t]*$", text, re.MULTILINE)
    if section is None:
        return {}
    following = re.search(r"^## ", text[section.end():], re.MULTILINE)
    content = text[section.end():section.end() + following.start() if following else len(text)]
    users: dict[str, str] = {}
    for name, kind in USER_LINE.findall(content):
        users.setdefault(name, kind)
    return users


def _scenario(match: re.Match[str], text: str) -> Scenario:
    fields = _fields(text)
    values = {item.name: item.text for item in fields}
    writes_text = values.get("writes", "").strip().lower()
    writes = True if writes_text == "yes" else False if writes_text == "no" else None
    method: str | None = None
    path = values.get("path") or values.get("url")
    method_text = values.get("method", "").strip("`")
    request = re.match(r"(GET|HEAD|OPTIONS|POST|PUT|PATCH|DELETE)\b(?:[ \t]+([^\s`]+))?", method_text, re.IGNORECASE)
    if request:
        method = request.group(1).upper()
        path = request.group(2) or path
    if path:
        path = path.split()[0].strip("`")
    tokens = list(dict.fromkeys(first or second for first, second in TOKEN.findall(text)))
    urls = list(dict.fromkeys(url.rstrip(".,;:)") for url in URL.findall(text)))
    # State assertions are classified separately from HTTP/UI actions.
    actions = "\n".join(item.text for item in fields if item.name not in {"expected", "state check", "target", "area"})
    other_steps = "\n".join(item.text for item in fields if item.name not in {"method", "expected", "state check", "target", "area", "path", "url"})
    state_checks: list[StateCheck] = []
    for item in fields:
        if item.name == "state check":
            prefix = STORE_PREFIX.fullmatch(item.text)
            state_checks.append(StateCheck(prefix.group(1), prefix.group(2)) if prefix else StateCheck(None, item.text))
    return Scenario(
        id=match.group(1), section=match.group(2), title=match.group(3), text=text,
        method=method, path=path, target=values.get("target", "").strip().strip("`") or None, writes=writes,
        expected=Assertion(values.get("expected", "")),
        edges=[edge for item in fields if item.name == "edge cases" for edge in _edges(item.text)],
        state_checks=state_checks, tokens=tokens, urls=urls,
        actions=actions, other_steps=other_steps,
    )


def parse_plan(path: Path) -> Plan:
    """Read scenario blocks and Source metadata, ignoring headings inside fences.

    Raises ConfigError for an unreadable plan. Payloads remain in memory for
    engine consumers; check_plan does not expose them in its JSON report.
    """
    try:
        text = path.read_text()
    except (OSError, UnicodeError) as error:
        raise ConfigError("plan is not readable") from error
    branch, head = _source(text)
    scenarios: list[Scenario] = []
    start: re.Match[str] | None = None
    fence: str | None = None
    for match in BLOCK_BOUNDARY.finditer(text):
        marker = match.group("fence")
        if marker:
            if fence is None:
                fence = marker
            elif marker[0] == fence[0] and len(marker) >= len(fence) and not match.group("info").strip():
                fence = None
            continue
        if fence is not None:
            continue
        if start is not None:
            scenarios.append(_scenario(start, text[start.start():match.start()].rstrip()))
        start = SCENARIO.match(text, match.start())
    if start is not None:
        scenarios.append(_scenario(start, text[start.start():].rstrip()))
    return Plan(path, branch, head, scenarios, _users_section(text))


def resolve_plan(repo: Path, argument: str = "") -> dict[str, object]:
    """Reuse explicit paths or the newest current-branch plan, checking its Head.

    An explicit change source, no branch match, or detached HEAD generates a
    plan. Only automatically selected plans are checked for source staleness.
    """
    repo = repo.resolve()
    branch_result = git_command(repo, "branch", "--show-current")
    head_result = git_command(repo, "rev-parse", "HEAD")
    if branch_result.returncode or head_result.returncode:
        raise ConfigError("plan resolution needs a git repository with a HEAD")
    branch, head = branch_result.stdout.strip(), head_result.stdout.strip()
    result: dict[str, object] = {"action": "generate", "plan": None, "branch": branch, "head": head, "source": argument or branch, "changed_files": []}
    if argument:
        candidate = Path(argument)
        if not candidate.is_absolute():
            candidate = repo / candidate
        if candidate.is_file():
            result.update(action="reuse", plan=display_path(repo, candidate.resolve()))
        return result
    if not branch:
        return result
    candidates = sorted((repo / "docs/testing/plans").glob("*.md"), key=lambda path: (path.stat().st_mtime_ns, path.name), reverse=True)
    for path in candidates:
        plan = parse_plan(path)
        if plan.branch != branch:
            continue
        result.update(action="reuse", plan=display_path(repo, path))
        # Only literal commit IDs are accepted; plan metadata cannot introduce
        # git options or revision expressions that silently refer to another tip.
        if not plan.head or not re.fullmatch(r"[0-9a-fA-F]{40}|[0-9a-fA-F]{64}", plan.head) or git_command(repo, "merge-base", "--is-ancestor", plan.head, "HEAD").returncode:
            result["action"] = "stale"
            return result
        changed = git_command(repo, "diff", "--name-only", "-z", f"{plan.head}..HEAD")
        if changed.returncode:
            raise ConfigError("plan resolution cannot compare the recorded Head")
        files = [name for name in changed.stdout.split("\0") if name]
        result["changed_files"] = files
        if any(not name.startswith("docs/") for name in files):
            result["action"] = "stale"
        return result
    return result


def user_token(token: str, users: Iterable[str]) -> tuple[str, str] | None:
    """Recognize a user field using the longest declared or configured prefix."""
    name = token.removeprefix("QA_")
    for user in sorted(users, key=lambda item: (-len(item), item)):
        prefix = user.upper() + "_"
        if name.startswith(prefix) and name[len(prefix):] in {"EMAIL", "PASSWORD", "ID"}:
            return user, name[len(prefix):]
    return None


def _mutates(scenario: Scenario) -> bool:
    if scenario.section == "FE":
        return bool(WRITE_ACTION.search(scenario.actions))
    return bool(WRITE_ACTION.search(scenario.actions) or WRITE_STEP.search(scenario.other_steps)
                or any(SQL_WRITE.search(check.text) or REDIS_WRITE.search(check.text) for check in scenario.state_checks))


def _token_requirements(plan: Plan, config: Config) -> tuple[set[str], set[str], set[str], dict[str, dict[str, str]], set[str], list[dict[str, str]]]:
    known = set(plan.users) | config.users.keys()
    value_names = {name.upper(): name for name in config.values}
    users: set[str] = set()
    registrations = {name for name, kind in plan.users.items() if kind == "registered"}
    values: set[str] = set()
    user_gaps: dict[str, dict[str, str]] = {}
    missing_values: set[str] = set()
    errors: list[dict[str, str]] = [
        {"scenario": "plan", "reason": f"user {user} is configured; declare it existing"}
        for user in sorted(registrations & config.users.keys())
    ]
    for scenario in plan.scenarios:
        reasons: set[str] = set()
        for token in scenario.tokens:
            name = token.removeprefix("QA_")
            if name in ENGINE_TOKENS:
                continue
            credential = CREDENTIAL_SUFFIX.fullmatch(name)
            if credential:
                user = name[:credential.start(1) - 1]
                reasons.add(f"tokens and cookies are obtained by the tester; use $QA_{user}_EMAIL and $QA_{user}_PASSWORD")
                continue
            recognized = user_token(token, known)
            if recognized:
                user, field = recognized
                if user not in plan.users:
                    reasons.add(f"user {user} is configured but not declared under ## Users")
                elif plan.users[user] == "existing":
                    users.add(user)
                    reason = "user is not configured" if user not in config.users else "id source is not configured" if field == "ID" and field not in config.user_fields(user) else None
                    if reason:
                        user_gaps[token] = {"name": user, "token": token, "reason": reason}
            elif name in value_names:
                values.add(value_names[name])
            elif unknown := USER_TOKEN.fullmatch(name):
                reasons.add(f"user {unknown.group(1).lower()} is not declared under ## Users")
            else:
                missing_values.add(name)
        errors.extend({"scenario": scenario.id, "reason": reason} for reason in sorted(reasons))
    return users, registrations, values, user_gaps, missing_values, errors


def _cleartext_errors(plan: Plan, config: Config) -> list[dict[str, str]]:
    errors: list[dict[str, str]] = []
    known = set(plan.users) | config.users.keys()
    for scenario in plan.scenarios:
        if not any(token[3:] in ENGINE_TOKENS or user_token(token, known) for token in scenario.tokens):
            continue
        target = scenario.target or config.section_target(scenario.section)
        urls = ([config.targets[target]] if target in config.targets else []) + scenario.urls
        refused: set[str] = set()
        for url in urls:
            try:
                scheme, host, port = parse_origin(url)
            except ConfigError:
                continue
            if scheme == "http" and not is_loopback(host):
                host = f"[{host}]" if ":" in host else host
                refused.add(f"http://{host}" + (f":{port}" if port != 80 else ""))
        errors.extend({"scenario": scenario.id, "reason": f"credentials over cleartext origin {origin}"} for origin in sorted(refused))
    return errors


def _missing_target(scenario: Scenario, config: Config) -> str | None:
    if scenario.target:
        return scenario.target if scenario.target not in config.targets else None
    # An absolute-only scenario already names its origin; relative
    # actions (including setup requests) still need the section default.
    without_urls = URL.sub("", scenario.actions)
    if scenario.urls and not RELATIVE_PATH.search(without_urls):
        return None
    return None if config.section_target(scenario.section) else SECTION_TARGETS[scenario.section]


def _off_target(scenario: Scenario, origins: set[Origin]) -> list[dict[str, object]]:
    refused: list[dict[str, object]] = []
    for url in scenario.urls:
        try:
            allowed = parse_origin(url) in origins
            reason = "origin is not a configured target"
        except ConfigError:
            allowed = False
            reason = "invalid URL or userinfo is refused"
        if not allowed:
            refused.append({"scenario": scenario.id, "origin": origin_display(url), "reason": reason})
    return refused


def _mutation_guards(plan: Plan, config: Config) -> list[str]:
    if config.policy["mutations"] == "allow":
        return []
    return [scenario.id for scenario in plan.scenarios if scenario.writes is not False or _mutates(scenario)]


def check_plan(plan: Plan, config: Config) -> dict[str, object]:
    """Return user and value requirements, configuration gaps and execution guards."""
    users, registrations, values, user_gaps, missing_values, plan_errors = _token_requirements(plan, config)
    plan_errors.extend(_cleartext_errors(plan, config))
    missing_targets: set[str] = set()
    state_checks: dict[str, list[str]] = {}
    missing_stores: set[str] = set()
    off_target: list[dict[str, object]] = []
    origins: set[Origin] = {parse_origin(origin, origin_only=True) for origin in config.targets.values()}
    for scenario in plan.scenarios:
        target = _missing_target(scenario, config)
        if target is not None:
            missing_targets.add(target)
        off_target.extend(_off_target(scenario, origins))
        if scenario.state_checks:
            state_checks[scenario.id] = []
            if scenario.section == "FE":
                plan_errors.append({"scenario": scenario.id, "reason": "state checks are BE-only"})
            for check in scenario.state_checks:
                store = check.store
                if store is None:
                    if len(config.stores) != 1:
                        error = {"scenario": scenario.id, "reason": "state check must name its store"}
                        if error not in plan_errors:
                            plan_errors.append(error)
                        continue
                    store = next(iter(config.stores))
                if store not in config.stores:
                    missing_stores.add(store)
                else:
                    state_checks[scenario.id].append(store)
    guarded = _mutation_guards(plan, config)
    missing = {
        "users": [user_gaps[token] for token in sorted(user_gaps)],
        "values": sorted(missing_values), "targets": sorted(missing_targets),
        "stores": sorted(missing_stores),
        "cleanup": bool(registrations) and config.cleanup_recipe is None,
    }
    return {
        "ok": not any(value for key, value in missing.items() if key != "cleanup") and not off_target and not plan_errors,
        "sections": plan.sections, "users": sorted(users), "registrations": sorted(registrations), "values": sorted(values),
        "missing": missing, "off_target": off_target, "plan_errors": plan_errors, "guarded": guarded,
        "state_checks": state_checks,
    }
