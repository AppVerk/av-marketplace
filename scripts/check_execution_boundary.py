#!/usr/bin/env python3
"""Check the decision stage's execution boundary against its consumers' grants.

Usage:
    python3 scripts/check_execution_boundary.py

`plugins/code-review/skills/decision-gate/SKILL.md` states, in prose, what a
verification check may execute during the decision stage. The commands that run
that stage declare `allowed-tools:` in YAML two files away. Nothing compared
them, and twice a fix changed the skill and left a consumer contradicting it.

A naive diff of the two is useless: `allowed-tools:` governs what the command
may do *at all* and legitimately carries `Edit`, `Write`, `Task` and the project
test runners, none of which are boundary violations. What is checkable is
narrower and is the property that actually matters: **a pre-approved `Bash(...)`
grant removes the platform's permission prompt.** For anything the boundary
excludes, that prompt is the last mechanical backstop before a prose lapse
executes something. So this is a registry-parity check, in the shape
`plugins/code-review/scripts/check-prefix-sync.sh` already uses here — a
canonical table in the document that owns the concept, diffed against its
consumers:

  1. Every `Bash(...)` grant on a runs-the-stage consumer is declared and
     classified in the skill's grant registry, and every registry row names a
     grant its consumer really carries.
  2. Every file that mentions the skill is classified in the registry's scope
     table, so a third command that starts running the stage cannot be silently
     unscanned — the blind spot `check_agent_frontmatter.py`'s
     `*/agents/*.md` glob has for commands and skills.
  3. A row claiming `inside-boundary` is verified against the boundary text
     itself, parsed from the skill rather than hardcoded here.
  4. A wildcard over a command family the boundary admits only *partly* —
     `Bash(git:*)` against five named git subcommands — fails. No registry row
     can make the rest of that family prompt-free-and-acceptable.

Errors exit non-zero; warnings print and do not fail the build. Exit 2 is a
usage error or an unparseable source, which is not a failed check.

Frontmatter parsing is imported from `check_agent_frontmatter` rather than
rewritten: that parser is covered by 85 tests, including the comma-and-comment
cases a hand-rolled split gets wrong. Its *glob* and its `_uses_colon_specifier`
are the blind spots; its parser is not.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path, PurePath

sys.path.insert(0, str(Path(__file__).resolve().parent))

from check_agent_frontmatter import parse_frontmatter, split_entries

REPO_ROOT = Path(__file__).resolve().parent.parent
PLUGINS_DIR = REPO_ROOT / "plugins"

SKILL_RELPATH = PurePath("plugins/code-review/skills/decision-gate/SKILL.md")

# Commands and skills both — the two file kinds `check_agent_frontmatter.py`
# never looks at, and the two kinds whose `allowed-tools:` is a real
# pre-approval.
CONSUMER_GLOBS = ("*/commands/*.md", "*/skills/*/SKILL.md")

# Any mention at all, not just the `code-review:decision-gate` Skill-load
# spelling: `/qa:loop` refers to the skill as "`code-review`'s `decision-gate`
# skill" and must still be classified.
CONSUMER_TOKEN = "decision-gate"

BOUNDARY_ANCHOR = "execution-boundary"
REGISTRY_ANCHOR = "grant-registry"

# The bullet that defines read-only inspection. Anchored on the bolded term so
# a reworded tail does not move it.
BOUNDARY_BULLET_RE = re.compile(r"^-\s+\*\*Read-only inspection\*\*")
BACKTICKED_RE = re.compile(r"`([^`]+)`")
TOOL_TOKEN_RE = re.compile(r"^[A-Z][A-Za-z]*$")
FAMILY_SUBCOMMAND_RE = re.compile(r"^(?P<family>[a-z][a-z0-9-]*) (?P<sub>[a-z][a-z0-9-]*)$")

ANCHOR_RE = re.compile(r'^<a id="(?P<id>[^"]+)"></a>\s*$')
HEADING_RE = re.compile(r"^(?P<hashes>#{1,6})\s")
TABLE_SEPARATOR_RE = re.compile(r"^\|[\s:|-]+\|$")

BASH_GRANT_RE = re.compile(r"^Bash\((?P<spec>.*)\)$", re.DOTALL)

CLASSES = frozenset({"inside-boundary", "pipeline", "outside-escalates"})
STAGE_RUNNING_KIND = "runs-the-stage"
SCOPE_KINDS = frozenset(
    {STAGE_RUNNING_KIND, "render-only", "dispatch-only", "reference-only"}
)

# False-pass floors, in the spirit of check-prefix-sync.sh's `>= 5` prefixes and
# check_agent_frontmatter.py's EXPECTED_AGENT_FILES. Each guards a way this
# check could report success having measured nothing. Unlike that constant these
# are hard: a parse that yields fewer has failed, not shrunk.
MIN_BOUNDARY_TOOLS = 3
MIN_BOUNDARY_SUBCOMMANDS = 5
MIN_SCOPE_ROWS = 1
MIN_GRANT_ROWS = 1


class SourceError(Exception):
    """A source file is missing, unreadable or does not parse — exit 2, not 1."""


def read_text(path: Path) -> str:
    """Read a file as UTF-8, tolerating a byte-order mark."""
    try:
        return path.read_text(encoding="utf-8-sig")
    except (OSError, UnicodeDecodeError) as exc:
        raise SourceError(f"{path}: cannot be read as UTF-8 text: {exc}") from exc


def section_lines(text: str, anchor: str) -> list[str]:
    """Return the lines of the section introduced by `<a id="anchor"></a>`.

    The anchor sits immediately above its own heading, exactly as
    `category-prefix-mapping` does in docs/plugins/code-review.md. The first
    heading after the anchor is the section's own; the section then runs to the
    next heading of that level **or shallower**. Deeper headings are subsections
    and stay in — the registry's own `#### Scope` and `#### Grants` tables would
    otherwise fall outside the section that owns them.
    """
    lines = text.split("\n")
    start = None
    for index, line in enumerate(lines):
        match = ANCHOR_RE.match(line)
        if match and match.group("id") == anchor:
            start = index + 1
            break
    if start is None:
        raise SourceError(f'anchor <a id="{anchor}"></a> not found')

    collected: list[str] = []
    own_level = None
    for line in lines[start:]:
        heading = HEADING_RE.match(line)
        if heading:
            level = len(heading.group("hashes"))
            if own_level is None:
                own_level = level
                continue
            if level <= own_level:
                break
            continue
        collected.append(line)
    return collected


def parse_boundary(text: str) -> tuple[frozenset[str], dict[str, frozenset[str]]]:
    """Parse the execution boundary into (tools, {family: subcommands}).

    Reads the terms out of the skill's own prose rather than restating them,
    so a boundary edit moves this check instead of silently invalidating it.
    """
    bullet = None
    for line in section_lines(text, BOUNDARY_ANCHOR):
        if BOUNDARY_BULLET_RE.match(line.strip()):
            bullet = line
            break
    if bullet is None:
        raise SourceError(
            f"{SKILL_RELPATH}: no '- **Read-only inspection**' bullet in the "
            f"{BOUNDARY_ANCHOR!r} section"
        )

    tools: set[str] = set()
    families: dict[str, set[str]] = {}
    for token in BACKTICKED_RE.findall(bullet):
        token = token.strip()
        if TOOL_TOKEN_RE.match(token):
            tools.add(token)
            continue
        match = FAMILY_SUBCOMMAND_RE.match(token)
        if match:
            families.setdefault(match.group("family"), set()).add(match.group("sub"))

    subcommand_count = sum(len(subs) for subs in families.values())
    if len(tools) < MIN_BOUNDARY_TOOLS or subcommand_count < MIN_BOUNDARY_SUBCOMMANDS:
        raise SourceError(
            f"{SKILL_RELPATH}: boundary parsed {len(tools)} tool(s) and "
            f"{subcommand_count} subcommand(s); expected at least "
            f"{MIN_BOUNDARY_TOOLS} and {MIN_BOUNDARY_SUBCOMMANDS} — the parser "
            "no longer understands the boundary bullet"
        )
    return frozenset(tools), {
        family: frozenset(subs) for family, subs in families.items()
    }


def table_rows(lines: list[str]) -> list[list[str]]:
    """Return every markdown table data row in `lines`, as trimmed cell lists.

    Header and separator rows are dropped. Rows from several tables in one
    section are returned together; the callers tell them apart by cell shape,
    which is what keeps a reordered section from breaking the parse.
    """
    rows: list[list[str]] = []
    for line in lines:
        stripped = line.strip()
        if not stripped.startswith("|") or not stripped.endswith("|"):
            continue
        if TABLE_SEPARATOR_RE.match(stripped):
            continue
        cells = [cell.strip() for cell in stripped[1:-1].split("|")]
        rows.append(cells)
    return rows


def consumer_key(path: str) -> str:
    """The short name a grant row uses to refer to a scope row.

    A file's stem, except that every skill is named `SKILL.md`, so a skill is
    keyed by the directory that names it. Keeping the keys short is what makes
    the Consumers column readable; keeping them unique is checked below.
    """
    pure = PurePath(path)
    if pure.name == "SKILL.md":
        return pure.parent.name
    return pure.stem


def _unbacktick(cell: str) -> str:
    match = BACKTICKED_RE.search(cell)
    return match.group(1).strip() if match else cell.strip()


def parse_registry(text: str) -> tuple[dict[str, tuple[str, str]], list[dict[str, object]]]:
    """Parse the grant registry into (scope, grants).

    scope maps a repo-relative consumer path to (kind, rationale).
    grants is a list of {grant, klass, consumers, rationale} rows, where
    consumers are the scope paths' stems.
    """
    lines = section_lines(text, REGISTRY_ANCHOR)
    scope: dict[str, tuple[str, str]] = {}
    grants: list[dict[str, object]] = []
    errors: list[str] = []

    for cells in table_rows(lines):
        first = _unbacktick(cells[0])
        if len(cells) == 3 and cells[1].strip() in SCOPE_KINDS:
            if first in scope:
                errors.append(f"duplicate scope row for {first!r}")
            scope[first] = (cells[1].strip(), cells[2].strip())
        elif len(cells) == 4 and cells[1].strip() in CLASSES:
            consumers = [
                _unbacktick(part) for part in cells[2].split(",") if part.strip()
            ]
            grants.append(
                {
                    "grant": first,
                    "klass": cells[1].strip(),
                    "consumers": consumers,
                    "rationale": cells[3].strip(),
                }
            )
        elif len(cells) in (3, 4) and cells[1].strip().lower() not in ("kind", "class"):
            # Not a header row and not a shape we recognise: the classification
            # column holds a value that is neither a kind nor a class. Silently
            # skipping it is how a typo'd class would erase a grant from the
            # registry while the parity check still reported success.
            errors.append(
                f"row {first!r} has an unrecognised classification "
                f"{cells[1].strip()!r}"
            )

    if errors:
        raise SourceError(
            f"{SKILL_RELPATH}: " + "; ".join(errors)
        )
    if len(scope) < MIN_SCOPE_ROWS or len(grants) < MIN_GRANT_ROWS:
        raise SourceError(
            f"{SKILL_RELPATH}: registry parsed {len(scope)} scope row(s) and "
            f"{len(grants)} grant row(s); expected at least {MIN_SCOPE_ROWS} "
            f"and {MIN_GRANT_ROWS}"
        )

    keys: dict[str, str] = {}
    for path in scope:
        key = consumer_key(path)
        if key in keys:
            raise SourceError(
                f"{SKILL_RELPATH}: scope rows {keys[key]!r} and {path!r} share "
                f"the short name {key!r}, so a grant row's consumer list is "
                "ambiguous"
            )
        keys[key] = path
    return scope, grants


def bash_grants(text: str) -> tuple[list[str], list[str]]:
    """Return (Bash grants, parse errors) from a file's `allowed-tools:`.

    A file with no frontmatter and no `allowed-tools:` yields no grants and no
    error — `render-only` and `dispatch-only` consumers are legitimately here.
    """
    fields, parse_errors = parse_frontmatter(text)
    if parse_errors:
        return [], parse_errors
    value = fields.get("allowed-tools")
    if not value:
        return [], []
    entries, split_error, _ = split_entries(value)
    if split_error:
        return [], [f"allowed-tools: {split_error}"]
    return [entry for entry in entries if BASH_GRANT_RE.match(entry)], []


def grant_prefix(grant: str) -> str:
    """The command prefix a `Bash(...)` grant pre-approves.

    `Bash(git:*)` -> 'git'; `Bash(npm test:*)` -> 'npm test'. The trailing
    `:*` is stripped from the end of the spec, not from its first whitespace
    token — that narrower reading is why `check_agent_frontmatter.py` cannot
    see `Bash(git log:*)` at all.
    """
    match = BASH_GRANT_RE.match(grant)
    spec = match.group("spec").strip() if match else grant.strip()
    if spec.endswith(":*"):
        spec = spec[:-2]
    return " ".join(spec.split())


def classify_prefix(
    prefix: str, families: dict[str, frozenset[str]]
) -> tuple[bool, str | None]:
    """Return (is_inside_boundary, over_wide_family) for a grant prefix.

    A `Bash(...)` grant can only be inside the boundary as a named subcommand of
    an admitted family: the boundary's other members are the `Read`, `Grep` and
    `Glob` *tools*, which no `Bash(...)` grant confers. A shell `grep` is not
    the `Grep` tool.
    """
    words = prefix.split()
    if len(words) == 2 and words[0] in families and words[1] in families[words[0]]:
        return True, None
    if len(words) == 1 and words[0] in families:
        return False, words[0]
    return False, None


def check(skill_text: str, consumers: dict[str, str]) -> tuple[list[str], list[str]]:
    """Return (errors, warnings). `consumers` maps repo-relative path to text."""
    errors: list[str] = []
    warnings: list[str] = []

    tools, families = parse_boundary(skill_text)
    scope, grant_rows = parse_registry(skill_text)

    # 1. Discovery parity: nothing may mention the skill without being classified.
    for path in sorted(consumers):
        if CONSUMER_TOKEN in consumers[path] and path not in scope:
            errors.append(
                f"{path}: mentions {CONSUMER_TOKEN!r} but is not classified in the "
                f"grant registry's scope table"
            )
    for path in sorted(scope):
        if path not in consumers:
            errors.append(
                f"{SKILL_RELPATH}: scope row names {path!r}, which does not exist"
            )

    # 2. Grant parity, both directions, per (consumer, grant) pair.
    key_to_path = {consumer_key(path): path for path in scope}
    declared: set[tuple[str, str]] = set()
    for row in grant_rows:
        grant = str(row["grant"])
        if not row["rationale"]:
            errors.append(
                f"{SKILL_RELPATH}: row for {grant!r} carries no rationale — the "
                "written justification is the registry's whole value"
            )
        for key in row["consumers"]:
            path = key_to_path.get(key)
            if path is None:
                errors.append(
                    f"{SKILL_RELPATH}: row for {grant!r} names consumer {key!r}, "
                    "which is not in the scope table"
                )
                continue
            declared.add((path, grant))

    actual: set[tuple[str, str]] = set()
    for path, (kind, _) in sorted(scope.items()):
        text = consumers.get(path)
        if text is None:
            continue
        grants, parse_errors = bash_grants(text)
        for message in parse_errors:
            errors.append(f"{path}: {message}")
        if kind != STAGE_RUNNING_KIND:
            continue
        for grant in grants:
            actual.add((path, grant))

    # No floor on `actual` here. A parser regression that empties it does not
    # slip through as a clean tree: every registry row turns stale below, which
    # is exit 1 with the paths named. A floor would instead have reported that
    # real divergence as exit 2, "I could not read the source" — a worse answer
    # to a question the check can in fact answer. The registry's own
    # MIN_GRANT_ROWS covers the remaining case, an empty table.
    for path, grant in sorted(actual - declared):
        errors.append(
            f"{path}: allowed-tools: {grant!r} is not declared in the grant "
            "registry — it runs prompt-free during the decision stage"
        )
    for path, grant in sorted(declared - actual):
        errors.append(
            f"{SKILL_RELPATH}: registry declares {grant!r} for {path!r}, which "
            "carries no such grant"
        )

    # 3. The boundary comparison itself, over the rows that name a real grant.
    for row in grant_rows:
        grant = str(row["grant"])
        klass = str(row["klass"])
        paths = sorted(
            key_to_path[key] for key in row["consumers"] if key in key_to_path
        )
        if not any((path, grant) in actual for path in paths):
            continue
        prefix = grant_prefix(grant)
        inside, over_wide = classify_prefix(prefix, families)

        if over_wide is not None:
            admitted = ", ".join(sorted(families[over_wide]))
            carriers = ", ".join(path for path in paths if (path, grant) in actual)
            errors.append(
                f"{carriers}: allowed-tools: {grant!r} is a wildcard over the "
                f"{over_wide!r} family, of which the execution boundary admits "
                f"only: {admitted}. Every other {over_wide} subcommand runs "
                "prompt-free during the decision stage, and no registry "
                "classification makes that acceptable — narrow the grant"
            )
            continue

        if klass == "inside-boundary" and not inside:
            errors.append(
                f"{SKILL_RELPATH}: {grant!r} is classified 'inside-boundary', but "
                f"the boundary does not admit {prefix!r} (its non-git members are "
                f"the {', '.join(sorted(tools))} tools, which no Bash grant confers)"
            )
        elif klass != "inside-boundary" and inside:
            warnings.append(
                f"{SKILL_RELPATH}: {grant!r} is classified {klass!r} but is inside "
                "the boundary — 'inside-boundary' keeps the count of prompt-free "
                "outside-the-boundary grants honest"
            )

    return errors, warnings


def discover(plugins_dir: Path) -> dict[str, str]:
    """Map every candidate consumer's repo-relative path to its text."""
    root = plugins_dir.parent
    paths: list[Path] = []
    for glob in CONSUMER_GLOBS:
        paths.extend(plugins_dir.glob(glob))
    consumers: dict[str, str] = {}
    for path in sorted(set(paths)):
        consumers[path.relative_to(root).as_posix()] = read_text(path)
    return consumers


def main(argv: list[str] | None = None, plugins_dir: Path = PLUGINS_DIR) -> int:
    args = sys.argv[1:] if argv is None else list(argv)
    if args:
        # Silently ignoring arguments is how a path-scoped invocation reports
        # success having scanned something else entirely.
        print(
            f"error: this check takes no arguments, got {' '.join(args)!r}",
            file=sys.stderr,
        )
        print(f"usage: python3 {Path(__file__).name}", file=sys.stderr)
        return 2

    try:
        consumers = discover(plugins_dir)
        if not consumers:
            raise SourceError(
                f"no command or skill files discovered under {plugins_dir}"
            )
        skill_path = str(SKILL_RELPATH)
        if skill_path not in consumers:
            raise SourceError(f"{skill_path}: not found — the boundary lives here")
        errors, warnings = check(consumers[skill_path], consumers)
    except SourceError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    for line in warnings:
        print(f"  warning: {line}")

    if errors:
        print("\nExecution boundary check FAILED:\n", file=sys.stderr)
        for line in errors:
            print(f"  - {line}", file=sys.stderr)
        print(
            "\nA pre-approved Bash(...) grant removes the platform's permission "
            f"prompt. Every such grant on a {STAGE_RUNNING_KIND} consumer must be "
            f"declared and classified in the grant registry in {skill_path}.",
            file=sys.stderr,
        )
        return 1

    print(
        f"\nExecution boundary OK: {len(consumers)} file(s) scanned, "
        f"{len(warnings)} warning(s)."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
