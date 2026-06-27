---
title: 'Fix slug-sanitizer test: remove masking fallback and correct expected value'
type: requirement
status: planning
lineage: ai-new
parent: lifecycle/defects/ai-new-slug-sanitizer-test-emits-failed-assertion-but-passes.md
assignees:
    - role: product-owner
      who: agent
---

## Problem

`tests/test_slug_sanitizer.sh` contains two compounding bugs in
`test_illegal_chars_become_dash` (line 80–93):

1. **Wrong expected value.** The test asserts the slug of `my@proj#ect!` equals
   `my-proj-ect-` (trailing dash retained). R20.1 requires trailing punctuation
   to be trimmed, so the implementation correctly returns `my-proj-ect`. The
   expectation is wrong, not the implementation.

2. **Masked assertion failure.** The `assert_eq` call is followed by a `|| {
   … assert_contains "my" "$out" … }` fallback. When `assert_eq` fails, the
   fallback runs a trivially weak check (`"my"` is a substring of virtually any
   output) and does **not** set `_fail=1`, so the test function returns 0. The
   outer runner reports the case as `PASS`, the summary prints `0 failed`, and
   the script exits 0.

Net effect: a real assertion failure is silently swallowed. A broken
`sanitize_slug` that still produces output containing `"my"` would pass this
test indefinitely.

## Goals / Non-goals

**Goals**

- Any `assert_eq` failure in `test_illegal_chars_become_dash` must propagate to
  `_fail=1` without exception.
- The expected slug for `my@proj#ect!` must match what R20.1 mandates
  (trailing-dash trimmed → `my-proj-ect`).
- The illegal-char exclusion check (no `@`, `#`, `!` in output) may be retained
  as a secondary guard, but must also set `_fail=1` on its own if it triggers.
- `bash tests/test_slug_sanitizer.sh` exits non-zero whenever any case fails.

**Non-goals**

- Changing `sanitize_slug` logic — the implementation is correct per R20.1.
- Altering any other test case in the file.
- Adding new test cases beyond the existing thirteen.

## Detailed Requirements

### R1 — Correct expected value

The first `assert_eq` in `test_illegal_chars_become_dash` must use `my-proj-ect`
(no trailing dash) as the expected value.

```bash
# before
assert_eq "my-proj-ect-" "$out" "illegal chars should be replaced with dashes" \
    || { out="$(echo "$out" | tr -d '\n')"; assert_contains "my" "$out" || _fail=1; }

# after
assert_eq "my-proj-ect" "$out" "illegal chars should be replaced with dashes" || _fail=1
```

### R2 — No recovery fallback on primary assertion

The `|| { … }` recovery block must be deleted. A failed `assert_eq` must
immediately set `_fail=1` with no alternate code path that could mask it.

### R3 — Illegal-char secondary guard retained, failure-safe

The existing guard that rejects output containing `@`, `#`, or `!` (lines 88–92)
may remain. It must set `_fail=1` on failure (it already does — verify it is not
accidentally removed in the refactor).

### R4 — Script exit code matches failure count

No change to the runner or `print_summary` is expected; this is a verification
requirement. After the fix, a deliberately broken expectation (e.g. expected
`BOGUS`) must cause the script to exit non-zero.

## Acceptance Criteria

| # | Criterion |
|---|-----------|
| AC1 | `bash tests/test_slug_sanitizer.sh` exits 0 and reports `13 passed  0 failed`. |
| AC2 | The `illegal chars replaced with dash` case emits no `ASSERT_EQ fail` line. |
| AC3 | If the expected value in `test_illegal_chars_become_dash` is temporarily changed to a wrong value (e.g. `BOGUS`), the script exits non-zero and reports `1 failed`. |
| AC4 | No other test case changes pass/fail status compared to the pre-fix baseline. |
| AC5 | The `|| { … }` fallback block no longer exists anywhere in `test_illegal_chars_become_dash`. |

## Answers

1. **Other tests for similar fallback pattern.** Are there other test cases in
   the suite that use a `|| { … }` recovery block instead of `|| _fail=1`? If
   so, they should be audited in the same pass — but that is out of scope for
   this requirement unless the reviewer finds them.

Answer: agreed for auditing, whether that pattern is used and should or should not be is currently unknown.

3. **R20.1 authoritative source.** The defect references R20.1 by identifier
   only. Confirm which requirement document owns that rule so the test comment
   can cite the correct path (currently the file header cites `R20.1` without a
   path reference).

Answer: ai-new-9.md

- **R20.1 <E2><80><94> Slug sanitizer.** The trial build tags the durable image as
  `localhost/ai-new/<slug>:trial`, where `<slug>` is derived from `<name>` by a deterministic
  sanitizer: convert to lowercase ASCII where possible; replace any character outside `[a-z0-9._-]`
  with `-`; collapse repeated `-`; trim leading/trailing `.`, `_`, and `-`; fail clearly if empty;
  cap at 63 characters; append `-<8-char-hash>` (hash of the original name) when truncation occurs;
  and fail if two distinct project names produce the same slug unless the user chooses a distinct
  name in a future flow.
