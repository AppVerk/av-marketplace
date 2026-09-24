# Code Review: feat/omp-edition — commit OMP edition

**Scope:** `git diff 74285756ddb9ec55b531b7a0dab5594f0b3edf39..HEAD` on `feat/omp-edition` (5 delivered tasks of `docs/plans/2026-09-24-commit-omp-edition.md`). Generated files (`plugins-omp/**`, `.omp-plugin/marketplace.json`) were reviewed through their sources.
**Date:** 2026-09-24
**Result:** 11 issues — 0 CRITICAL, 0 HIGH, 0 MEDIUM, 11 LOW. No blocking issues.

## Automated scans

| Scan | Tool | Result |
|------|------|--------|
| Secrets | trufflehog 3.97.9 (git + filesystem), fallback regex | 0 findings |
| SAST | semgrep (322 rules), bandit, manual A10 review | 0 findings |
| Dependencies | no third-party dependencies added | nothing to scan |
| Python lint | ruff (fallback E,W,F), mypy | 1 × E303 (MAINT-004); mypy 0 |
| Tests | `python3 scripts/test_build_omp_edition.py`, `bun test` in `omp/claude-hooks/` | 26 OK; 16 pass, 0 fail |

Every failure path of the new adapter fails closed (hook error, non-0/2 exit, invalid JSON, missing decision, timeout, unresolvable cwd, unreadable config), and OMP's host blocks on handler errors and timeouts.

---

### [LOW] SEC-001: Push-guard confirmation dialog omits the bash call's cwd and env [verified]

**ID:** SEC-001
**Location:** `omp/claude-hooks/claude-hooks.ts:158`
**Category:** Security
**OWASP:** A06:2025
**CWE:** CWE-451
**Effort:** easy

**Problem:**
When a hook returns `ask`, the extension opens `ctx.ui.confirm` with the hook's reason and `input.command` only. OMP's `bash` input also carries `cwd` (and `env` in service mode), which change where and how the command runs but are not part of the command text. In Claude Code the equivalent `cd <other> && git push` would appear in the confirmed command. A call `{command: "git push", cwd: <second repo on main>}` produced a dialog that names only `git push`.

**Impact:**
The user can approve a push without seeing which repository (or which git overrides) it runs with, for example a push to another repository's protected branch.

**Remediation:**

```ts
// Before
const shown = typeof input?.command === "string" ? input.command : JSON.stringify(event.input);
if (await ctx.ui.confirm("Confirm command", `${askReason}\n\n${shown}`)) return undefined;

// After
const lines = [typeof input?.command === "string" ? input.command : JSON.stringify(event.input)];
if (cwd !== ctx.cwd) lines.push(`cwd: ${cwd}`);
if (input?.env && typeof input.env === "object" && Object.keys(input.env).length > 0) lines.push(`env: ${JSON.stringify(input.env)}`);
if (await ctx.ui.confirm("Confirm command", `${askReason}\n\n${lines.join("\n")}`)) return undefined;
```

Add a regression test for an `ask` with a non-default `cwd` and with `env`.

---

### [LOW] ARCH-001: Shared hooks adapter ships inside versioned plugins with no enforced version bump [verified]

**ID:** ARCH-001
**Location:** `scripts/build_omp_edition.py:543-558`
**Category:** Architecture
**Effort:** easy

**Problem:**
The generator copies `omp/claude-hooks/claude-hooks.ts` into every generated plugin that has hooks and stamps `package.json` with that plugin's catalog version. `CLAUDE.md:54` requires bumping every such plugin when `omp/claude-hooks/` changes, because OMP's update check compares versions. Nothing enforces it: `build_omp_edition.py --check` only diffs output, and `check_plugin_versions.py` checks four-place parity and (opt-in) regressions. An adapter edit touches no `plugins/<name>/` directory, so the usual "modifying a plugin" cue never comes up. (Downgraded from MEDIUM by the challenger: the risk concerns a later adapter change, not a missing bump in this change.)

**Impact:**
A fix to the guard adapter can merge, regenerate cleanly and pass CI, yet never reach installed OMP editions of `commit`.

**Remediation:**
Add a PR-time check (e.g. in `scripts/check_plugin_versions.py`, run in CI with the base branch fetched): when `omp/claude-hooks/claude-hooks.ts` differs from the base branch, every overlaid plugin with `hooks/hooks.json` must have a version different from the base branch.

---

### [LOW] ARCH-002: `HOOKABLE_TOOLS` and `HOOK_TOOL_MAP` are kept equal only by comments [verified]

**ID:** ARCH-002
**Location:** `omp/claude-hooks/claude-hooks.ts:29`
**Category:** Architecture
**Effort:** easy

**Problem:**
`HOOKABLE_TOOLS` (`omp/claude-hooks/claude-hooks.ts:28-29`) must list exactly the OMP tools of `HOOK_TOOL_MAP` (`scripts/build_omp_edition.py:101-104`). Only comments say so. The repository already checks a similar cross-language parity with a script (`scripts/check_omp_tools.py` for `OMP_TOOLS`).

**Impact:**
A tool added on one side only makes the generated config invalid (`validConfig` rejects it, so every `bash` call is blocked), or leaves the new tool unguarded when the config cannot be read. Today the lists agree.

**Remediation:**
Add a unittest to `scripts/test_build_omp_edition.py` that parses `HOOKABLE_TOOLS` from the TS source and asserts it equals `sorted(set(HOOK_TOOL_MAP.values()))`.

---

### [LOW] PERF-001: Every agent `bash` call pays for two sequential hook spawns [verified]

**ID:** PERF-001
**Location:** `omp/claude-hooks/claude-hooks.ts:145-155`
**Category:** Performance
**Effort:** medium

**Problem:**
The handler runs the commit and push hooks one after another for every `bash` call. Measured with the shipped `plugins-omp/commit` extension (20 runs each): `ls -la` median 37.6 ms (p90 39.8 ms), `git push origin feature/x` median 66.9 ms (p90 69.0 ms). Sequential execution and "later entries do not run after a deny" are deliberate (plan Task 1; listed deviation from Claude Code, which runs hooks in parallel).

**Impact:**
A small fixed latency on every agent shell command.

**Remediation:**
Optional: run the entries concurrently and aggregate deny > ask > allow, keeping the first-deny reason. Only worth doing if the latency becomes noticeable; it changes a documented behaviour.

---

### [LOW] PERF-002: Hook stdout and stderr are buffered without a size bound [verified]

**ID:** PERF-002
**Location:** `omp/claude-hooks/claude-hooks.ts:78`
**Category:** Performance
**Effort:** easy

**Problem:**
`runHook` reads both pipes completely into strings (`new Response(proc.stdout).text()`) before deciding. The 10 s timeout bounds the duration, not the bytes.

**Impact:**
A misbehaving hook can grow OMP's memory until it times out. Hooks are trusted plugin scripts, so the risk is low.

**Remediation:**
Cap the bytes read per pipe (e.g. 1 MiB) and treat an overflow as a failed hook (`failed: output too large`).

---

### [LOW] MAINT-001: The "clears its timeout timer" test cannot fail [verified]

**ID:** MAINT-001
**Location:** `omp/claude-hooks/tests/claude-hooks.test.ts:173-178`
**Category:** Maintainability
**Effort:** trivial

**Problem:**
The test runs a fast hook with `timeoutMs: 100`, sleeps 300 ms and asserts nothing more. A late timer can never throw in `runHook` (the callback returns on `settled`, and `process.kill` is in `try/catch`). With both `clearTimeout` calls and the `settled` guard removed, the test still passes, although a late `SIGKILL` could then hit a reused process group.

**Impact:**
False confidence: a refactor that drops both safeguards passes CI.

**Remediation:**

```ts
test("a successful hook never kills its process group later", async () => {
	const hook = handler({ PreToolUse: [script("fast.sh", "exit 0")] }, { timeoutMs: 100 });
	const kill = spyOn(process, "kill");
	try {
		expect(await call(hook)).toBeUndefined();
		await Bun.sleep(300);
		expect(kill).not.toHaveBeenCalled();
	} finally {
		kill.mockRestore();
	}
});
```

---

### [LOW] MAINT-002: The `..` check in `map_hooks` has no isolating test [verified]

**ID:** MAINT-002
**Location:** `scripts/test_build_omp_edition.py:205`
**Category:** Maintainability
**Effort:** trivial

**Problem:**
The only `..` case, `${CLAUDE_PLUGIN_ROOT}/scripts/../hooks/hooks.json`, also escapes `scripts/`, so the `is_relative_to(scripts_root)` check rejects it anyway. With the `".." in rel.parts` check removed, the suite still passes and `${CLAUDE_PLUGIN_ROOT}/scripts/x/../guard.sh` builds; the adapter's `validConfig` would then reject the generated config at runtime and block every `bash` call.

**Impact:**
A regression in the build-time check would surface only at runtime.

**Remediation:**
Add `"${CLAUDE_PLUGIN_ROOT}/scripts/x/../guard.sh"` to the `commands` tuple next to the existing `..` case.

---

### [LOW] MAINT-003: `hookCwd` checks "only slashes" before expanding `~` [verified]

**ID:** MAINT-003
**Location:** `omp/claude-hooks/claude-hooks.ts:47-49`
**Category:** Maintainability
**Effort:** trivial

**Problem:**
OMP's `resolveToCwd` (`src/tools/path-utils.ts:381-391`) expands `~` first and then maps a slashes-only result to the session cwd. `hookCwd` tests the raw input first. With `HOME=/`, `input.cwd: "~"` gives the hook `/`, while OMP runs the command in `ctx.cwd`.

**Impact:**
In that rare environment the push guard inspects a different directory than the one the command runs in.

**Remediation:**

```ts
const p = inputCwd.startsWith("~") ? path.join(homedir(), inputCwd.slice(1)) : inputCwd;
if (/^\/+$/u.test(p)) cwd = projectCwd;
else if (path.isAbsolute(p)) cwd = p;
else cwd = path.resolve(projectCwd, p);
```

---

### [LOW] MAINT-004: Two consecutive blank lines inside `build_generated` (ruff E303) [verified]

**ID:** MAINT-004
**Location:** `scripts/build_omp_edition.py:503-504`
**Category:** Maintainability
**Effort:** trivial

**Problem:**
The new inline-hooks block ends with a blank line right before the existing one, giving two blank lines inside the function (pycodestyle E303; the baseline had none).

**Impact:**
Style only.

**Remediation:**
Delete one of the two blank lines.

---

### [LOW] MAINT-005: New prose lines are not wrapped like their neighbours [verified]

**ID:** MAINT-005
**Location:** `CLAUDE.md:54`
**Category:** Maintainability
**Effort:** trivial

**Problem:**
The new paragraph at `CLAUDE.md:54` is one line of about 1,000 characters in a section wrapped at about 78 columns; the new `jq dependency` bullet at `docs/plugins/commit.md:110` is likewise one line among wrapped bullets.

**Impact:**
Rendering is unchanged; source readability and future diffs suffer.

**Remediation:**
Re-wrap both at about 78 columns without changing the wording.

---

### [LOW] DOC-001: Commit OMP section omits the extension's own fail-closed blocks on non-git bash calls [verified]

**ID:** DOC-001
**Location:** `docs/plugins/commit.md:120`
**Category:** Documentation
**Effort:** easy
**Drift-class:** decision
**Fix-policy:** needs-decision

**Problem:**
The `## Oh My Pi` section lists when the extension blocks a call (a push-guard prompt without a UI, an unparsable push command, a failed or slow guard) but not the two blocks the extension adds itself: any `bash` call whose `cwd` does not resolve to an existing directory is blocked, OMP-only forms such as `@/…` and `file://…` included (`omp/claude-hooks/claude-hooks.ts:139-143`), and an unreadable `extensions/claude-hooks.json` blocks every `bash` call (`:184-192`).

**Impact:**
A user who sees `commit: cannot resolve the bash cwd (@/src); …` on a non-git command finds no explanation in the Commit guide.

**Remediation:**
Add a sentence to the paragraph at line 120 about the cwd block (the fix is a plain absolute or relative path). Decide whether to mention the unreadable-config block as well, or leave it to its block reason.

---

## Verification Summary

**Method:** Cross-domain correlation and adversarial review (Cross-Verifier + Challenger)

| Metric | Count |
|--------|-------|
| Findings verified | 11 |
| False positives removed | 2 |
| Severity adjustments | 1 |
| Cross-analysis findings | 0 |

### Cross-Analysis (Security <-> Quality)
- SEC-001 + MAINT-003: the approval dialog can hide a mismatch between the directory the push guard inspects and the directory where `bash` runs. Fix MAINT-003's resolution order and show the effective cwd (SEC-001).
- SEC-001 + ARCH-001: a fix to the shared adapter (such as SEC-001's) reaches installed editions only with a version bump that nothing enforces.
- Coverage gaps noted by the cross-verifier: divergent cwd resolution against distinct repositories (the `HOME=/` path), and whether `bash` `env` (service mode only) can change git's push destination without the guard seeing it — both belong to SEC-001's remediation.

### Challenged Findings
- Removed (false positive): "tool_call handler repeats the tool-match predicate and walks entries by index with `!`" — the loop keeps config order without allocating a filtered array; no defect or convention supports the change.
- Removed (false positive): "Hooks handling split across `build_generated` with a sentinel between the blocks" — the grouping is a subjective split; the measurable complexity belongs to the linter result.
- Downgraded MEDIUM → LOW: ARCH-001 — the risk concerns a later adapter change without its documented bump, not a missing bump in this change.

### Rejected by auditors (self-falsification)
- quality: `map_hooks` cyclomatic complexity 21 — already reported by ruff C901; other functions in the file are at 21
- quality: Repeated temp-source setup in test_unsupported_hooks_fail_closed — the file's established pattern
- quality: Error `hook command <command>` does not say what is wrong — message prescribed by the plan; CLAUDE.md documents the accepted form
- quality: A command hook without `command` is reported as unknown hook keys — prescribed by the plan
- quality: Unwrapped read_text/UnicodeDecodeError in map_hooks — same pattern elsewhere in the file; the build still fails closed
- quality: `hookCwd` expands `~user` to `$HOME/user` — matches OMP's expandTilde
- quality: Preamble bullet added to every generated command and agent — plan choice
- quality: Preamble change without version bumps for other plugins — only commit uses inline `!` context
- quality: Delivery depends on commit's `AV_COMMIT_SKILL=1` marker string — plan decision
- quality: commit.json is one compact line — literal content from the plan
- quality: Source test imports generated plugins-omp — the plan requires testing the shipped copy; CI runs `--check` first
- documentation: CLAUDE.md generator-source sentence omits omp/claude-hooks — covered by CLAUDE.md:54 and contributing
- documentation: Contributing Hooks section lacks the OMP-edition hook restrictions — it points to CLAUDE.md#omp-edition
- documentation: Delivery guide Prerequisites omit the Commit and jq interaction — README and commit.md cover it
- documentation: Contributing OMP-edition bullet says the workflow runs only generator and delivery tests — the new bullet covers the hooks tests
- documentation: claude-hooks.ts header omits the cwd-resolution block from its deviations list — not a deviation from Claude's contract
- documentation: Block reasons still say "Use the /commit skill" and "blocked for Claude Code" in OMP — kept by the plan; docs map the wording
- security: None

### Doctrine-gap candidates
- quality: Cross-language constant parity enforced only by comment (`HOOK_TOOL_MAP` vs `HOOKABLE_TOOLS`) — see ARCH-002.
- documentation: No version-bump rule for generator or preamble output changes — the preamble bullet changed every generated command and agent without bumps (harmless here; a future preamble change that matters would not reach installed editions).
