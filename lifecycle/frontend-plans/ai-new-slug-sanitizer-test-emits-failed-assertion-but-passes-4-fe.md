---
title: 'Fix slug-sanitizer test: remove masking fallback — Frontend Plan'
type: plan-frontend
status: planning
lineage: ai-new-slug-sanitizer-test-emits-failed-assertion-but-passes
parent: lifecycle/requirements/ai-new-slug-sanitizer-test-emits-failed-assertion-but-passes-2.md
created: "2026-06-27T00:00:00+10:00"
priority: high
assignees:
    - role: frontend-developer
      who: agent
---

# Fix slug-sanitizer test: remove masking fallback — Frontend Plan

This plan covers the **user-visible surface** of `tests/test_slug_sanitizer.sh`:
the two lines that a developer sees when they run the suite. The frontend here
is the test runner's stdout and exit code — what `bash tests/test_slug_sanitizer.sh`
prints and returns. The fix must make the runner's output truthful: `PASS` means
the assertion passed, `0 failed` means zero assertions failed, exit 0 means the
suite is clean.

The backend plan (`ai-new-slug-sanitizer-test-emits-failed-assertion-but-passes-3-be.md`)
confirms no production-code change is needed. This plan owns the single two-line
edit that fixes what the developer sees.

---

## Milestone F1 — Replace the masking `assert_eq` call with the correct expectation

**Description.** Rewrite lines 85-86 of `tests/test_slug_sanitizer.sh` to
satisfy R1 and R2 simultaneously. The change is one logical operation: swap the
wrong expected value AND delete the recovery fallback in a single edit so the
two bugs cannot be fixed in opposite order and leave a window where a third
state (correct value, still-masked failure) exists undetected.

Current (lines 85-86):
```bash
assert_eq "my-proj-ect-" "$out" "illegal chars should be replaced with dashes" \
    || { out="$(echo "$out" | tr -d '\n')"; assert_contains "my" "$out" || _fail=1; }
```

After:
```bash
assert_eq "my-proj-ect" "$out" "illegal chars should be replaced with dashes" || _fail=1
```

The change:
- Corrects the expected value from `my-proj-ect-` to `my-proj-ect` (R1,
  mandated by R20.1 in `ai-new-9.md`: "trim leading/trailing `.`, `_`, and `-`").
- Removes the `|| { … }` recovery block entirely, leaving only `|| _fail=1`
  so a failed `assert_eq` propagates unconditionally (R2).
- Does not touch lines 87-92 (the illegal-char secondary guard), which already
  sets `_fail=1` and satisfies R3.

**Files to change.**

- `tests/test_slug_sanitizer.sh` lines 85-86 — the two-line replacement above.

**Acceptance criteria.**

- `bash tests/test_slug_sanitizer.sh` exits 0 and its final summary line
  reads `13 passed  0 failed` (or equivalent runner phrasing) — no
  `ASSERT_EQ fail` line appears in stdout/stderr (AC1, AC2).
- `grep -n '|| {' tests/test_slug_sanitizer.sh` produces no output inside
  `test_illegal_chars_become_dash` (AC5).
- The illegal-char secondary guard (lines 87-92) is unchanged and present
  (R3 — verified by `diff`).
- No other test case changes pass/fail status (AC4 — run the full suite and
  compare before/after summary counts).

---

## Milestone F2 — Verify exit-code propagation end-to-end

**Description.** The runner's `print_summary` and exit-code logic are not
changed (R4 states this is a verification requirement). This milestone confirms
the existing runner plumbing correctly surfaces a failure after the F1 fix —
i.e., that `_fail=1` set inside `test_illegal_chars_become_dash` reaches the
runner's failure counter and the script's final exit code.

- Temporarily replace the corrected expected value with a known-wrong value
  (`BOGUS`) and run the suite; assert the script exits non-zero and the
  summary reports `1 failed`.
- Revert the temporary change.
- The verification may be done manually once or captured as the AC3 test case
  in the test plan (`ai-new-slug-sanitizer-test-emits-failed-assertion-but-passes-5-test.md`).

**Files to change.**

- None permanently. The temporary `BOGUS` substitution is a manual check,
  not a committed state.

**Acceptance criteria.**

- With expected value temporarily set to `BOGUS`, `bash tests/test_slug_sanitizer.sh`
  exits non-zero and the summary reports `1 failed` (AC3).
- After reverting, the suite exits 0 and reports `13 passed  0 failed` (AC1).
- No change to the runner (`print_summary`, the outer `run_tests` loop, or
  exit-code logic) is needed or made (R4).

---

## Cross-cutting acceptance (frontend contribution to requirement ACs)

- **AC1** Suite exits 0; `13 passed  0 failed` (F1).
- **AC2** No `ASSERT_EQ fail` line emitted for `illegal chars replaced with dash` (F1).
- **AC3** Known-wrong expectation causes non-zero exit and `1 failed` (F2).
- **AC5** `|| { … }` fallback gone from `test_illegal_chars_become_dash` (F1).

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
