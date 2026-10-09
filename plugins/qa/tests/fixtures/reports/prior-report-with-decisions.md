# Test Report: Prior decisions

## Summary
- Accounts: none

## Issues Found

### [HIGH] QA-001: Old title
**Status:** ⚠️ Partially Fixed (2026-09-29)
**Decision:** keep contract — preserve authorization [user, 2026-09-29; attempt 1: partial]
**Decision-retired:** old contract — retired [user, 2026-09-28]
**Verification-plan:** GET /items → 200; anonymous GET /items → 401
**Decision-pin:** block=123abc | src/app.py=absent:edit
**Dispatch:** attempt 1 dispatched 2026-09-29
**Verification:** hard — anonymous request rejected

**ID:** QA-001
**Location:** `src/corrected.py:42-44` (was: `unknown:0`)
**Category:** Testing

**Problem:**
- Expected: 200 items returned. (src/app.py:1)
- Actual: Wrong items returned.
- Refutation: re-verified: yes; env: n/a; scope: in; harness: ok

**Remediation:**
Preserve the authorization contract and return the correct items.

**Scenario:** BE-01

### [HIGH] QA-002: Rejected sibling
**Status:** 🚫 Rejected (2026-09-29) — duplicate of QA-001

**ID:** QA-002
**Location:** `src/app.py:2`
**Category:** Testing

**Problem:**
- Expected: Missing item: 404. (src/app.py:2)
- Actual: Item unexpectedly exists.
- Refutation: re-verified: yes; env: n/a; scope: in; harness: ok

**Remediation:**
Return 404 for a missing item.

**Scenario:** BE-01 (edge 1)

## Detailed Results

### Fail: BE-01: Fetch items — see QA-001, QA-002

## Loop History

| Iteration | Failing in | Now passing | Still failing | Warnings | Regressions | Dispatches |
|======|===========|=============|===============|==========|=============|============|
| 1 | BE-01 | — | BE-01 | QA-010 ⚠ | — | 2 |
