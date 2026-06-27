---
title: 'Fix slug-sanitizer test: remove masking fallback — Backend Plan'
type: plan-backend
status: done
lineage: ai-new-slug-sanitizer-test-emits-failed-assertion-but-passes
parent: lifecycle/requirements/ai-new-slug-sanitizer-test-emits-failed-assertion-but-passes-2.md
created: "2026-06-27T00:00:00+10:00"
priority: high
assignees:
    - role: backend-developer
      who: agent
---

# Fix slug-sanitizer test: remove masking fallback — Backend Plan

This plan covers the **implementation side** of the defect: verifying that
`sanitize_slug` (the function under test) is already correct per R20.1 and
requires no change, and auditing the test suite for the `|| { … }` recovery
pattern that masked the original failure.

The production code change required by this defect is **zero lines**. The
implementation of `sanitize_slug` already trims trailing dashes as R20.1
mandates (authoritative source: `lifecycle/requirements/ai-new-9.md`). The
backend plan's sole job is to confirm that invariant and widen the blast-radius
check to other tests.

---

## Milestone B1 — Confirm `sanitize_slug` output matches R20.1

**Description.** Establish, by reading the current implementation, that
`sanitize_slug "my@proj#ect!"` already returns `my-proj-ect` (no trailing
dash) and that no production-code change is warranted. This is a verification
milestone; its artifact is the confirmation that closes the question. If the
implementation is found to disagree with R20.1, this milestone must raise a
separate defect rather than fold a silent fix into this change.

- Read `sanitize_slug` in the relevant source file (grep the plugin sources
  for the function definition).
- Confirm the trailing-dash-trim step is present and executes after
  character substitution.
- Confirm that the R20.1 requirement document (`lifecycle/requirements/ai-new-9.md`)
  specifies "trim leading/trailing `.`, `_`, and `-`" — matching the current
  implementation.
- Record the confirmation in a one-line comment at the top of the test
  function (optional; only if the function lacks a cite to R20.1).

**Files to change.**

- None in production code.
- `tests/test_slug_sanitizer.sh` — optionally add/update a cite to `ai-new-9.md R20.1`
  in the `test_illegal_chars_become_dash` function header comment if absent.

**Acceptance criteria.**

- `grep -n 'sanitize_slug\|slug' lib/*.sh bin/*.sh` (or equivalent) locates
  the implementation and a human reader confirms the trailing-dash trim is
  present.
- No diff to any production file is produced by this milestone.
- The authoritative requirement for the expected value (`my-proj-ect`) is
  traceable to `ai-new-9.md R20.1` without ambiguity.

---

## Milestone B2 — Audit test suite for other `|| { … }` recovery patterns

**Description.** The requirement's Answers section (Q1) flags that other test
cases may share the masking `|| { … }` recovery pattern. This milestone audits
the full test suite and documents findings. Fixing any discovered instances is
out of scope for this change unless they are in `test_slug_sanitizer.sh`
itself; the output of this milestone is a written finding (in this plan file or
a new defect) so nothing rots.

- `grep -n '|| {' tests/*.sh` to surface every `|| {` block in the suite.
- For each hit, check whether the block sets `_fail=1` unconditionally or
  provides an escape path that could mask a failure.
- If `test_slug_sanitizer.sh` contains additional instances beyond lines
  85-86: fix them in the same pass (same file, same PR).
- If other test files contain instances: open a follow-up defect entry under
  `lifecycle/defects/` — do not silently defer.

**Files to change.**

- `tests/test_slug_sanitizer.sh` — fix any additional masking `|| { … }`
  blocks found in the same file.
- `lifecycle/defects/` — new defect stub if other files have masking patterns
  (one defect per affected test file is acceptable).

**Acceptance criteria.**

- `grep -n '|| {' tests/test_slug_sanitizer.sh` produces no output, or
  every hit sets `_fail=1` in all code paths.
- Every `|| {` hit in other test files is either confirmed safe (always sets
  `_fail=1`) or tracked by a new defect.
- No additional test case in `test_slug_sanitizer.sh` changes pass/fail
  status relative to the pre-fix baseline (AC4).

---

## Cross-cutting acceptance (backend contribution to requirement ACs)

- **AC4** No other test case changes pass/fail status (B2 audit confirms no
  unintended touches).
- **AC5** The `|| { … }` fallback no longer exists in `test_illegal_chars_become_dash`
  — enforced structurally by the B2 grep check.

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
