---
name: "code-review:linter-integration"
description: Runs the linters, typecheckers and formatter checks a project configures, Python (ruff, mypy, flake8, pylint) and TypeScript/JavaScript (eslint, tsc, prettier), with the project's own configuration and only on the files in review scope. Reports their output as evidence and one linters status line, never as findings.
allowed-tools: Read, Grep, Glob, Bash(ruff:*), Bash(mypy:*), Bash(flake8:*), Bash(pylint:*), Bash(eslint:*), Bash(tsc:*), Bash(npx:*), Bash(prettier:*), Bash(node:*), Bash(command:*), Bash(grep:*), Bash(mktemp:*), Bash(git diff:*), Bash(git ls-files:*), Bash(xargs:*), Bash(wc:*)
---

# Linter Integration - Run the Project's Own Tools

Runs the linters, typecheckers and formatter checks the project configures, with the project's configuration, on the files in review scope, and returns their output as evidence.

---

## Core Principles

1. **Only what the project configures.** A tool runs only when the project has its configuration, and with that configuration. There is no default rule set: when no tool is configured for the languages in scope, the status line is `- linters: skipped (no project configuration)`.
2. **Only the files in scope.** In a changes-since scope a tool gets only the changed files of its language; tsc is the one exception (Step 4).
3. **Evidence, not findings.** Diagnostics go to Linter Results and the `linters` line. Only a diagnostic that shows a defect the change causes may back a finding (Step 6).
4. **Read-only.** Tools run in checking mode only — never `--fix`, `--write`, or a formatter without `--check` — and nothing is installed. Every result goes to the run directory, outside the repository.

---

## Step 1: Read the Check Plan

The scope block's `Checks:` line says what to lint. Obey it:

- `linters skipped (<reason>)` — run nothing. The status line is `- linters: skipped (<reason>)`.
- `linters run (<languages>)` — lint only the languages it names. `Python` covers `*.py` and `*.pyi`; `TypeScript/JavaScript` covers `*.ts`, `*.tsx`, `*.js`, `*.jsx`, `*.mjs` and `*.cjs`.
- No `Checks:` line (no scope block) — lint each of those languages the repository has files of.

`Review scope: changes since <REVIEW_BASE>` lints the changed files; `Review scope: whole repository`, or no scope block, lints the repository.

---

## Step 2: Create the Run Directory

Once per run — when another skill already created the run's directory, use that one:

```bash
OUT=$(mktemp -d) && echo "$OUT"
```

Bash calls do not keep shell variables. In every later command, write the printed path, single-quoted, in place of `$OUT` (`>'<printed path>/ruff.json'` for `>"$OUT/ruff.json"`), and the full SHA from the scope, single-quoted, in place of `$REVIEW_BASE`, so each command still starts with git's or the tool's name. The Read tool reads `"$OUT/<name>"`, with the printed path for `$OUT`. Nothing goes to a fixed `/tmp` path or into the repository.

---

## Step 3: Find the Configured and Installed Tools

From the repository root:

```bash
echo "=== Configured ==="
{ [ -f ruff.toml ] || [ -f .ruff.toml ] || grep -Eq '^\[tool\.ruff[].]' pyproject.toml 2>/dev/null; } && echo "ruff"
{ [ -f mypy.ini ] || [ -f .mypy.ini ] || grep -Eq '\[tool\.mypy[].]' pyproject.toml 2>/dev/null || grep -q '^\[mypy\]' setup.cfg 2>/dev/null; } && echo "mypy"
{ [ -f .flake8 ] || grep -qs '^\[flake8\]' setup.cfg tox.ini; } && echo "flake8"
{ [ -f pylintrc ] || [ -f .pylintrc ] || grep -Eq '^\[tool\.pylint[].]' pyproject.toml 2>/dev/null; } && echo "pylint"
for f in eslint.config.js eslint.config.mjs eslint.config.cjs eslint.config.ts eslint.config.mts eslint.config.cts .eslintrc .eslintrc.js .eslintrc.cjs .eslintrc.json .eslintrc.yml .eslintrc.yaml; do [ -f "$f" ] && echo "eslint ($f)"; done
grep -q '"eslintConfig"' package.json 2>/dev/null && echo "eslint (package.json)"
[ -f tsconfig.json ] && echo "tsc (tsconfig.json)"
for f in .prettierrc .prettierrc.json .prettierrc.json5 .prettierrc.yml .prettierrc.yaml .prettierrc.toml .prettierrc.js .prettierrc.cjs .prettierrc.mjs prettier.config.js prettier.config.cjs prettier.config.mjs; do [ -f "$f" ] && echo "prettier ($f)"; done
[ -f package.json ] && node -e 'process.exit("prettier" in require("./package.json") ? 0 : 1)' 2>/dev/null && echo "prettier (package.json)"
echo "=== Installed ==="
for t in ruff mypy flake8 pylint; do command -v "$t" >/dev/null 2>&1 && echo "$t"; done
for t in eslint tsc prettier; do npx --no-install "$t" --version >/dev/null 2>&1 && echo "$t"; done
```

Select, for each language Step 1 admits, its configured tools — flake8 and pylint only when ruff is not configured, since they would repeat its checks. A selected tool that is not installed is `unavailable`: never substitute another tool or install one (`npx --no-install` keeps npx from downloading).

---

## Step 4: Run the Selected Tools

In a changes-since scope, Git supplies the names NUL-delimited and `xargs -0` passes them as argv after the tool's `--`, as the scope block's **Shell safety** suffix requires: one command for the changes since the base and one for untracked files, the second appending. Never build a file list from the `Changed files` display. The `[ "$#" -eq 0 ]` guard skips an empty batch, which would otherwise make the tool check the whole directory. Stderr goes to `<name>.err`, never to `/dev/null`, so a failure stays visible.

### Count the files first

`<n>` in the status line is the number of files the linters covered. For each language to lint, add the two counts:

```bash
git diff --name-only --diff-filter=d "$REVIEW_BASE" -- '*.py' '*.pyi' | wc -l
git ls-files --others --exclude-standard -- '*.py' '*.pyi' | wc -l
```

Use the TypeScript/JavaScript patterns for that language; with a whole-repository scope, count `git ls-files --cached --others --exclude-standard -- '*.py' '*.pyi' | wc -l`. Line output is safe here: the names are only counted, never passed to a command. A language whose count is 0 — its changes are all deletions — runs no tool; its status is `skipped (no <language> files left to lint)`.

### Python, changes since a base

```bash
git diff -z --name-only --diff-filter=d "$REVIEW_BASE" -- '*.py' '*.pyi' | xargs -0 sh -c '[ "$#" -eq 0 ] || exec ruff check --force-exclude --no-cache --output-format=json -- "${@}"' sh >"$OUT/ruff.json" 2>"$OUT/ruff.err"
git ls-files -z --others --exclude-standard -- '*.py' '*.pyi' | xargs -0 sh -c '[ "$#" -eq 0 ] || exec ruff check --force-exclude --no-cache --output-format=json -- "${@}"' sh >>"$OUT/ruff.json" 2>>"$OUT/ruff.err"
```

The other Python tools take the same two commands, changing only the part after `exec` and the output names:

| Tool | After `exec` | Output, errors |
|------|--------------|----------------|
| mypy | `mypy --show-error-codes --cache-dir=/dev/null -- "${@}"` | `mypy.txt`, `mypy.err` |
| flake8 | `flake8 -- "${@}"` | `flake8.txt`, `flake8.err` |
| pylint | `pylint --output-format=json -- "${@}"` | `pylint.json`, `pylint.err` |

`--force-exclude` keeps ruff's own excludes for files named on its command line; `--no-cache` and `--cache-dir=/dev/null` keep ruff's and mypy's caches out of the repository.

### TypeScript/JavaScript, changes since a base

```bash
git diff -z --name-only --diff-filter=d "$REVIEW_BASE" -- '*.ts' '*.tsx' '*.js' '*.jsx' '*.mjs' '*.cjs' | xargs -0 sh -c '[ "$#" -eq 0 ] || exec npx --no-install eslint --format=json -- "${@}"' sh >"$OUT/eslint.json" 2>"$OUT/eslint.err"
git ls-files -z --others --exclude-standard -- '*.ts' '*.tsx' '*.js' '*.jsx' '*.mjs' '*.cjs' | xargs -0 sh -c '[ "$#" -eq 0 ] || exec npx --no-install eslint --format=json -- "${@}"' sh >>"$OUT/eslint.json" 2>>"$OUT/eslint.err"
```

prettier takes the same two commands with `npx --no-install prettier --check -- "${@}"` after `exec`, writing `prettier.txt` and `prettier.err`.

### Whole repository

```bash
ruff check --no-cache --output-format=json . >"$OUT/ruff.json" 2>"$OUT/ruff.err"
mypy --show-error-codes --cache-dir=/dev/null . >"$OUT/mypy.txt" 2>"$OUT/mypy.err"
flake8 . >"$OUT/flake8.txt" 2>"$OUT/flake8.err"
pylint --output-format=json --recursive=y . >"$OUT/pylint.json" 2>"$OUT/pylint.err"
npx --no-install eslint --format=json . >"$OUT/eslint.json" 2>"$OUT/eslint.err"
npx --no-install prettier --check . >"$OUT/prettier.txt" 2>"$OUT/prettier.err"
```

Run the selected tools' lines only. When the mypy configuration sets `files`, drop mypy's `.` so that setting decides what it checks.

### tsc, in either scope

```bash
npx --no-install tsc --noEmit --pretty false -p ./tsconfig.json >"$OUT/tsc.txt" 2>"$OUT/tsc.err"
```

Given file arguments, tsc ignores `tsconfig.json`, so it always checks the project as configured; in a changes-since scope Step 6 keeps only the diagnostics in scope. When the tsconfig, or a config it extends, sets `incremental` or `composite`, add `--tsBuildInfoFile "$OUT/tsc.tsbuildinfo"` so tsc writes no build-info file into the repository.

---

## Step 5: Read the Results

Read each result file with the Read tool. A tool **ran** when its result has its normal form:

| Tool | Normal result | Fields |
|------|---------------|--------|
| ruff | JSON arrays, one per invocation (`[]` when clean) | `.code`, `.filename`, `.location.row`, `.message` |
| mypy | a closing `Success: no issues found…` or `Found <n> errors…` line per invocation | `path:line: error: message  [code]` |
| flake8 | `path:row:col: CODE message` lines, or none, with no traceback in `flake8.err` | the same lines |
| pylint | JSON arrays without `fatal` entries (a `fatal` entry is a file pylint could not check) | `.type`, `.path`, `.line`, `.symbol`, `.message` |
| eslint | JSON arrays | `.filePath`, `.messages[].severity` (2 error, 1 warning), `.messages[].line`, `.messages[].ruleId`, `.messages[].message` |
| tsc | nothing, or only lines `path(line,col): error TS<code>: message` | the same lines |
| prettier | `Checking formatting...` in `prettier.txt` and no `[error]` line in `prettier.err` | `[warn] <path>` lines in `prettier.err` name unformatted files |

Any other result means the tool **failed**: its status is `failed (<first error line>)`, from the first non-empty line of its `.err` file — or, for tsc, the first `error TS` line without a file location, which is a configuration error. A failed tool's missing output never reads as "no issues".

---

## Step 6: Scope, and the One Exception

**Scope.** In a changes-since scope, ruff, flake8, pylint, eslint and prettier saw only changed files. mypy also reports on modules it follows from them, and tsc on the whole project: keep a diagnostic outside the changed files only when a changed line causes it — an unchanged caller of a signature the change altered, an import of a name the change removed — and count the rest as outside scope.

**Evidence, never findings.** Every diagnostic in scope belongs in Linter Results, and none is a finding on its own: not a style, formatting, naming or import-order code; not a complexity or size rule (ruff `C901` and the `PLR09xx` too-many rules, pylint `too-many-*`, eslint `complexity`, `max-lines`, `max-params`, `max-depth`); not an unused import or variable that shows no wrong logic; not a prettier result; not a diagnostic that was there before the change.

**The exception.** A linter or type-checker diagnostic that shows a defect the change causes — a type error, an undefined name, a broken import, unreachable or wrong logic, a failing compile — may back one finding. Its description (the report's **Problem:**) names the changed line that causes it, even when the diagnostic's own location is an unchanged line. Several diagnostics of one defect back that one finding. Typical sources: mypy and tsc errors (`TS2304` cannot find name, `TS2339` property does not exist, `TS2345` argument type mismatch); ruff or flake8 `F821` (undefined name) and syntax errors; pylint `E` messages; eslint `no-undef`, `no-unreachable` and `import/no-unresolved`. An import error for a third-party package the project declares is a gap in the tool's environment, not a broken import.

---

## Step 7: Report

Return two parts to the auditor.

**Linter Results** — the evidence:

```markdown
## Linter Results

| Tool | Config | Files | Diagnostics | Top codes |
|------|--------|-------|-------------|-----------|
| ruff | pyproject.toml [tool.ruff] | 4 | 6 | E501 (5), F821 (1) |
| mypy | pyproject.toml [tool.mypy] | 4 | 1 | arg-type (1) |

- src/billing.py:42 mypy arg-type: Argument 1 to "charge" has incompatible type "str"; expected "Decimal" — backs: Amount passed to charge as str
- src/billing.py:7 ruff F821: Undefined name `settings` — backs: Undefined settings in billing handler
- src/billing.py:88 ruff E501: Line too long (104 > 88)
```

Below the table, list the diagnostics that back a finding (`— backs: <finding title>`), then the other diagnostics in scope — type and logic errors before style — at most 20 per tool, then `… <k> more`. Add `<tool>: <k> diagnostics outside the changed files` when mypy or tsc reported any. A tool that did not run appears with its status in place of counts, never with zeros.

**The `linters` line** — exactly one line for the auditor's `## Checks` section:

- `- linters: ran (<tools>, <n> files)` — the tools that ran, and the files Step 4 counted
- `- linters: skipped (<reason>)` — the reason from the `Checks:` line, or `no project configuration` when no tool is configured for the languages in scope
- `- linters: unavailable (<tool> not installed)`
- `- linters: failed (<first error line>)`

When the tools ended differently, the line gives one form per outcome, joined by `; `, `ran` first: `- linters: ran (ruff, 4 files); unavailable (mypy not installed)`. A language in scope with no configured tool, beside one that ran, adds `skipped (no project configuration for <language>)`. A skipped, unavailable or failed tool is never described as clean.

---

## Red Flags - STOP if you

- Lint a language the `Checks:` line does not name, or anything when it marks linters skipped
- Run a tool the project does not configure, or supply a default rule set
- Install a tool, or run one with `--fix`, `--write`, or a formatter without `--check`
- Lint the whole repository in a changes-since scope (tsc aside), or build a file list from the `Changed files` display
- Write a result to a fixed `/tmp` path or into the repository, or send a tool's stderr to `/dev/null`
- Run flake8 or pylint beside a configured ruff
- Turn a diagnostic into a finding outside Step 6's exception
- Report a skipped, unavailable or failed tool as clean

**When these occur:** Go back and redo the step.

---

## Final Checklist

Before completing linter integration, verify:

- [ ] Read the `Checks:` line and linted only the languages it names
- [ ] Created one run directory with `mktemp -d`; every result and `.err` file is in it
- [ ] Ran only configured, installed tools, with the project's configuration
- [ ] Passed changed files NUL-delimited, after `--` (changes-since scope)
- [ ] Set each tool's status from its output: ran, unavailable or failed
- [ ] Kept diagnostics as evidence; backed a finding only through Step 6's exception
- [ ] Returned Linter Results and one `linters` line
