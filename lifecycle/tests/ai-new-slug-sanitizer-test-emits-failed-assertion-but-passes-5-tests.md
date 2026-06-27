---
title: Fix slug-sanitizer test — Test Artifact
type: test
status: done
lineage: ai-new-slug-sanitizer-test-emits-failed-assertion-but-passes
parent: lifecycle/test-plans/ai-new-slug-sanitizer-test-emits-failed-assertion-but-passes-5-test.md
created: "2026-06-27T00:00:00+10:00"
---

# Fix slug-sanitizer test — Test Artifact

Documents the integration tests built to verify the B2 fix
(`1a35a3f`) against the five acceptance criteria (AC1–AC5) and
supporting requirement R3.

The artefact under test is `tests/test_slug_sanitizer.sh` after the
masking `|| { … }` fallback was removed and the expected value corrected
from `"my-proj-ect-"` to `"my-proj-ect"` (R20.1).

---

## What was built

### Test file

| File | Milestones | AC / R | Tier |
|------|-----------|--------|------|
| `tests/test_slug_sanitizer_fix.sh` | T1–T4 | AC1–AC5, R3 | A |

No existing files were modified; no new helpers were added.

### Test coverage

| Test label | Milestone | ACs verified |
|------------|-----------|--------------|
| T1: suite exits 0, 13 passed 0 failed | T1 | AC1 |
| T1: no ASSERT_EQ fail for illegal-chars case | T1 | AC2 |
| T2: failure injection causes non-zero exit | T2 | AC3 |
| T3: masking `\|\| {` fallback absent | T3 | AC5 |
| T3: secondary guard sets `_fail=1` | T3 | R3 |
| T3: test function count unchanged at 13 | T3 | AC4 |
| T4: all `\|\| {` blocks set `_fail=1` | T4 | B2 audit |

---

## Notable implementation decisions

### T2 — temp copy stays inside `tests/`

The BOGUS-injection test makes a `mktemp` copy inside `tests/` (not
`/tmp`) so that the suite's `SELF_DIR` computation (`dirname
"${BASH_SOURCE[0]}"`) resolves to the real `tests/` directory and
`helpers/setup.bash` is found. The copy is removed immediately after
the run regardless of outcome.

### T3 — AC5 tested at the assertion level, not by counting `|| {`

The test plan's `grep -n '|| {' tests/test_slug_sanitizer.sh` produces
output because the secondary guard (`[[ … ]] || { … _fail=1 … }`) is
intentionally present (R3). Rather than counting total `|| {` hits,
`test_t3_masking_fallback_absent` checks two things directly:
- The old masking pattern (`assert_eq … || {`) is absent.
- The corrected pattern (`assert_eq "my-proj-ect" … || _fail=1`) is
  present.

### T4 — awk block scanner

`test_t4_all_or_blocks_set_fail` uses a two-state awk scanner: it
enters a block on `|| {`, watches for `_fail=1`, and reports any block
that closes (`}`) without having seen it. This avoids a fragile
line-offset grep while remaining one readable awk program.

---

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
