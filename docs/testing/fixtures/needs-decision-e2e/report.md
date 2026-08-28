# Code Review Report: needs-decision end-to-end fixture

Synthetic report used to exercise the `needs-decision` batch-resolution
design end to end, via `/fix-all` and `/fix-report`. See `RUNBOOK.md` in
this directory for how to run it and `ANSWERS.md` for the scripted
answers. Do not "fix" this report for real — it is test input, restored
from a pristine snapshot before each run.

## Summary

- Total: 5 | Auto: 2 | Needs-decision: 3
- Findings point at `target-a.md` and `target-b.md` in this same directory.

## Issues Found

### [MEDIUM] DOC-001: Documented Node.js version is stale

**ID:** DOC-001
**Location:** `docs/testing/fixtures/needs-decision-e2e/target-a.md:8`
**Category:** Documentation
**Drift-class:** mechanical
**Fix-policy:** auto

**Problem:**
`target-a.md` states the supported Node.js version is 16. The fixture's
canonical value for this run is 18.

**Remediation:**
Change the line to read `- Supported Node.js version: 18`.

---

### [MEDIUM] DOC-002: Documented retry count is stale

**ID:** DOC-002
**Location:** `docs/testing/fixtures/needs-decision-e2e/target-a.md:9`
**Category:** Documentation
**Drift-class:** mechanical
**Fix-policy:** auto

**Problem:**
`target-a.md` states the maximum retry attempts as 3. The fixture's
canonical value for this run is 5. This finding sits one line below
DOC-001 in the same file, on purpose — the two exercise sequential,
not concurrent, dispatch of edits against one file.

**Remediation:**
Change the line to read `- Maximum retry attempts: 5`.

---

### [LOW] DOC-003: FEATURE_X_ENABLED has no documentation entry

**ID:** DOC-003
**Location:** —
**Category:** Documentation
**Drift-class:** decision
**Fix-policy:** needs-decision

**Problem:**
The fixture service reads an environment variable `FEATURE_X_ENABLED`
that has no corresponding documentation anywhere in this fixture set.
Nothing in `target-a.md` or `target-b.md` covers it, so there is no
existing location to anchor this finding — authoring the new entry (and
choosing which file it belongs in) is a judgment call, not a location
lookup.

**Remediation:**
Add a subsection documenting `FEATURE_X_ENABLED`: purpose, default value
(`false`), and how to enable it. Requires a target file to be supplied
before analysis can proceed.

---

### [MEDIUM] DOC-004: Rollback cross-reference appears dead

**ID:** DOC-004
**Location:** `docs/testing/fixtures/needs-decision-e2e/target-a.md:13`
**Category:** Documentation
**Drift-class:** dead-reference
**Fix-policy:** needs-decision

**Problem:**
`target-a.md`'s Rollback section links to a section titled "Rollback
Procedures" in `target-b.md`, but `target-b.md` has no section with that
exact title — an apparent dead cross-reference, possibly left over from
a docs restructuring.

**Remediation:**
Update the cross-reference in `target-a.md` to the correct section title
in `target-b.md`, or restore a section literally titled "Rollback
Procedures" in `target-b.md` if the retitling was unintended.

---

### [HIGH] DOC-005: Report-generation script does not exist

**ID:** DOC-005
**Location:** `docs/testing/fixtures/needs-decision-e2e/target-b.md:13`
**Category:** Documentation
**Drift-class:** dead-reference
**Fix-policy:** needs-decision

**Problem:**
`target-b.md`'s Report Generation section instructs readers to run
`scripts/generate-legacy-report.sh`, but no file at that path exists
anywhere in the repository. Unlike DOC-004, there is no renamed or
relocated referent to find — the script is simply gone.

**Remediation:**
Either remove the mention of `scripts/generate-legacy-report.sh` from
`target-b.md`, or add the script back at that path.
