---
title: 'Fix slug-sanitizer test: remove masking fallback — Test Plan'
type: plan-test
status: approved
lineage: ai-new-slug-sanitizer-test-emits-failed-assertion-but-passes
parent: lifecycle/requirements/ai-new-slug-sanitizer-test-emits-failed-assertion-but-passes-2.md
created: "2026-06-27T00:00:00+10:00"
priority: high
assignees:
    - role: test-developer
      who: agent
---

# Fix slug-sanitizer test: remove masking fallback — Test Plan

This plan defines how to verify that the backend plan
(`ai-new-slug-sanitizer-test-emits-failed-assertion-but-passes-3-be.md`) and
frontend plan (`ai-new-slug-sanitizer-test-emits-failed-assertion-but-passes-4-fe.md`)
have correctly resolved the defect against all five acceptance criteria (AC1–AC5).

The artefact under test is `tests/test_slug_sanitizer.sh` after the F1 edit.
Because the test file is itself the thing being fixed, verification here means
running the suite, inspecting its output, and mutating the expected value to
confirm failure propagation. No new test files are added — the fixed suite is
its own regression guard.

---

## Milestone T1 — Baseline run (AC1, AC2)

**Description.** Run the suite in its fixed state and capture the summary line
and exit code.

**Procedure.**

```bash
bash tests/test_slug_sanitizer.sh
echo "exit: $?"
```

**Acceptance criteria.**

- Script exits 0 (AC1).
- Summary reports `13 passed  0 failed` (or phrasing equivalent to zero
  failures across thirteen cases) (AC1).
- No line matching `ASSERT_EQ fail` appears in stdout or stderr for the
  `illegal chars replaced with dash` case (AC2).

---

## Milestone T2 — Deliberate-failure injection (AC3)

**Description.** Temporarily replace the corrected expected value with `BOGUS`
to confirm that a genuine assertion failure is no longer masked and propagates
to a non-zero exit.

**Procedure.**

1. In `tests/test_slug_sanitizer.sh`, change line 85 to:
   ```bash
   assert_eq "BOGUS" "$out" "illegal chars should be replaced with dashes" || _fail=1
   ```
2. Run: `bash tests/test_slug_sanitizer.sh; echo "exit: $?"`
3. Revert the change.

**Acceptance criteria.**

- Script exits non-zero (AC3).
- Summary reports `1 failed` (AC3).
- The `ASSERT_EQ fail` line references the `illegal chars` case, not a
  different test (confirms the failure is the injected one, not a regression).
- After revert, the suite passes T1 again.

---

## Milestone T3 — Structural checks (AC4, AC5)

**Description.** Confirm the fix's scope: the fallback block is gone, the
secondary guard is intact, and no other test case was modified.

**Procedure.**

```bash
# AC5: no || { in test_illegal_chars_become_dash
grep -n '|| {' tests/test_slug_sanitizer.sh

# R3: secondary guard still sets _fail=1
grep -A6 'test_illegal_chars_become_dash' tests/test_slug_sanitizer.sh | grep '_fail=1'

# AC4: count total test functions — must still be 13
grep -c '^test_' tests/test_slug_sanitizer.sh
```

**Acceptance criteria.**

- `grep -n '|| {' tests/test_slug_sanitizer.sh` produces no output within
  the `test_illegal_chars_become_dash` function body (AC5).
- The illegal-char secondary guard block (the `[[ "$out" != *"@"* … ]]`
  check) is present and its failure branch sets `_fail=1` (R3).
- The total number of `test_` functions in the file is unchanged from the
  pre-fix baseline (AC4 — no test cases added, removed, or renamed).
- A `git diff` of `tests/test_slug_sanitizer.sh` shows a net change of
  exactly the two lines from F1 (lines 85-86), plus any optional cite comment
  from B1, and nothing else (AC4).

---

## Milestone T4 — Suite audit result (B2 output)

**Description.** Verify the B2 audit conclusion: either no other masking
`|| { … }` patterns exist in the suite, or any found are tracked by a defect.

**Procedure.**

```bash
grep -n '|| {' tests/*.sh
```

For each hit: confirm the block always sets `_fail=1` in all branches, or
confirm a defect is filed.

**Acceptance criteria.**

- Every `|| {` block in `tests/test_slug_sanitizer.sh` sets `_fail=1` in
  all branches (no escape path that returns 0 on assertion failure).
- Any masking patterns found in other test files have a corresponding defect
  entry under `lifecycle/defects/`.
- If no masking patterns exist anywhere: `grep -c '|| {' tests/*.sh` output
  is documented here as the confirmation.

---

## Coverage map (requirement ACs → milestones)

- **AC1** exits 0, `13 passed 0 failed` → T1.
- **AC2** no `ASSERT_EQ fail` for illegal-chars case → T1.
- **AC3** deliberate wrong expectation causes non-zero exit and `1 failed` → T2.
- **AC4** no other test case changes pass/fail status → T3, T4.
- **AC5** `|| { … }` fallback absent from `test_illegal_chars_become_dash` → T3.

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
