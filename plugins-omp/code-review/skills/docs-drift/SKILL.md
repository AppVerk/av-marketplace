---
name: "code-review:docs-drift"
description: "Use when /code-review:review runs its documentation pre-pass or when documentation-auditor reads the pre-pass output — finds documentation references (paths and links, backticked names, file:line citations) that broke between a base revision and the working tree, and defines the output grammar."
---

# Docs Drift

The pre-pass compares deterministic documentation-reference checks at a base revision and in the working tree, keeping only references that broke within that scope. `/code-review:review` runs it before launching `documentation-auditor`, only when documentation was detected and the review scope has a base. Its hits are candidates for the auditor to verify, not findings.

## Resolve the installed script

Use the installed plugin's script, never a project's own copy.

- **Claude Code:** run `bash ${CLAUDE_PLUGIN_ROOT}/skills/docs-drift/scripts/docs_drift.sh --base <rev>`, exactly this form without quotes around the script path, to match `/code-review:review`'s permission pre-approval.
- **OMP:** run `realpath skill://code-review:docs-drift/scripts/docs_drift.sh` with Bash, then invoke `bash '<resolved path>' --base <rev>`. An OMP shell does not define `CLAUDE_PLUGIN_ROOT`; never guess a path.

Full usage: `docs_drift.sh --base REV [--root DIR] [--max N]`. The root defaults to the current repository's top level. An explicit `--root` must resolve to a repository's top level, not a subdirectory; symlinks to the top level are accepted. `--max` defaults to `200` and must be a positive integer. `-h` or `--help` prints the script header and exits `0`.

## What it checks

Each tree contributes its existing `docs/`, `doc/` and `documentation/` directories, followed by its sorted root `*.md` regular files. A tree with no inputs contributes no hits and its checkers are not called. The pre-pass excludes:

- `docs/plans/`
- `docs/reviews/`
- `docs/testing/`
- `docs/superpowers/`
- `CHANGELOG.md`

Head is the working tree, including uncommitted edits and untracked files but excluding gitignored files. Base is a temporary shared clone checked out at the base revision with full history, under the same final directory name as the repository so references to the repository's own name are classified consistently. The clone is removed on exit. The repository is not modified: no files, refs or worktrees are created in it.

The checkers skip symlinked document files and directory inputs. Before reading a cited target, a package manifest or a UTF-16 string file, they reject a symlinked final component or a containing directory whose physical path is outside the tree root. Skipped citations contribute no content-derived hits or line counts.

Requirements: bash `3.2+`, git, awk and find; jq is optional for package-name detection, and iconv is used for UTF-16 string files. Cost: two runs of the three checkers, plus a checkout of the base tree.

## Output

Successful output starts with:

```text
DOCS_DRIFT base=<first 12 characters of the base SHA> head_hits=<n> base_hits=<n> new=<n>
NEW <checker hit>
```

`head_hits` and `base_hits` count lines of kinds `MISSING`, `UNRESOLVED`, `NAME_MISSING`, `LINEREF_CHANGED`, `LINEREF_MOVED`, `LINEREF_GONE`, `LINEREF_RANGE` and `LINEREF_NOFILE`. Other checker output, including summaries and hints, is not a hit. A hit's key is its kind, doc path and target; the doc line number is ignored, and line-reference targets also drop ` -> …` candidate ranges and trailing ` (…)` notes. Renamed docs map base keys to their new paths.

Doc paths in hits are relative to the tree root. Root prefixes are stripped literally, so glob or regular-expression characters in a repository's parent directory do not make pre-existing hits appear new.

A key is new when it occurs more often at head than at base. Every head hit line for a new key is printed with the prefix `NEW `, preserving checker order: refs, then names, then line references. At most `--max` lines are printed. If there are more, output ends with:

```text
TRUNCATED shown=<max> total=<n>
```

Success exits `0`, including when new hits exist. Errors print one line on stdout and exit `2`:

```text
DOCS_DRIFT_ERROR <reason>
```

Reasons identify a missing base revision, a missing root directory (`--root needs a directory`), an invalid or missing positive maximum, an unknown option, a root that is not a repository's top level (`not a git repository: <dir>`), a base that is not a commit, a failed base checkout (with its first stderr line), or a failed checker (with the tree, `head` or `base`, and its first stdout line). A failed pre-pass never stops `/code-review:review`; the auditor falls back to semantic review.

## Reading the hits

| Kind | Candidate meaning |
|---|---|
| `MISSING` | A path with a directory, or a link, does not exist. |
| `UNRESOLVED` | A bare file name was found nowhere in the repository. |
| `NAME_MISSING` | A backticked identifier was found in no code file. The dictionary skips `*.md`, so a name that lives only in Markdown prompts is a candidate too. |
| `LINEREF_NOFILE` | A `file:line` citation names a missing file. |
| `LINEREF_RANGE` | A `file:line` citation is past the file's end. |
| `LINEREF_GONE` | The identifiers on the doc line are no longer in the cited file. |
| `LINEREF_MOVED` | The identifiers moved; the hit includes candidate ranges. |
| `LINEREF_CHANGED` | The cited file changed since the doc line was written. |

Every `NEW` line is a candidate to verify, never a finding by itself. Open the doc line, inspect its target and the scope's diff, and falsify the claim before reporting it. Classify verified drift with `docs-fact-registry`:

- A target the scope removed, or renamed without a unique successor, is `dead-reference`.
- A file path moved to exactly one new path is `mechanical`.
- Any `LINEREF_*` hit is `decision`: a cited line number always escalates, even when the new range appears unique.

## The checkers

The scripts can also be run directly from the installed plugin's `skills/docs-drift/scripts/` directory, using the same installed-path resolution above:

```text
check_refs.sh <file.md|dir> [...] [--root DIR] [--workspace DIR] [--overlay FILE] [--exclude GLOB]... [--strict]
check_names.sh <file.md|dir> [...] [--root DIR] [--ignore-file FILE]... [--overlay FILE] [--exclude GLOB]...
check_linerefs.sh <file.md|dir> [...] [--root DIR] [--overlay FILE] [--exclude GLOB]... [--strict]
```

Each checker accepts `-h` or `--help` without document arguments, prints its complete leading comment header (without the shebang), including requirements, and exits `0`.

- `check_refs.sh`: exit `0` without `MISSING`, `1` with `MISSING`, `2` for usage errors. `UNRESOLVED`, `EXTERNAL` and `WORKSPACE` do not change the exit code; `--strict` keeps the same contract.
- `check_names.sh`: exit `0` without candidates, `1` with candidates, `2` for usage errors. `KNOWN_STALE` hints do not change the exit code.
- `check_linerefs.sh`: exit `0` without hits, `1` with `CHANGED`, `MOVED`, `GONE`, `RANGE` or `NOFILE` hits, `2` for usage errors. With `--strict`, only `RANGE`, `NOFILE` and `GONE` cause exit `1`; `EXTERNAL` and `KNOWN` do not change it.

`--overlay FILE` explicitly supplies a manual list of known false paths, known false names and excluded docs, under the sections `## Known false paths`, `## Known false names` and `## Excluded docs paths`. See each checker's header for entry syntax and supported Polish aliases. `/code-review:review` passes no overlay.

The checkers were ported from av-dev's `av-docs-sync` at `debf0a7`.
