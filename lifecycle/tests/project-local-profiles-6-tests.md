---
title: Project-Local Profile Canonicalization — Tests
type: test
status: done
lineage: project-local-profiles
parent: lifecycle/test-plans/project-local-profiles-5-test.md
---

# Project-Local Profile Canonicalization — Tests

Integration tests implementing every milestone in the test plan. All tests
pass against the current codebase (`tests/run_tests.sh` green).

## Files changed

| File | Change |
|------|--------|
| `tests/10_profile.sh` | Renamed recovery test; added 6 new tests (M1/M2/M5) |
| `tests/61_list.sh` | Added mirror negative + 3 discovery tests (M1/M3) |
| `tests/test_scaffold_layout.sh` | Added mirror negative assertion (M1) |
| `tests/test_no_dead_install_code.sh` | Added `install_generated_profile` absence check (M1/R3.3) |
| `tests/test_generated_scaffold.sh` | Added profiles/ mirror negative (M4/AC4) |
| `tests/test_reconcile_resume.sh` | Added reconcile mirror negative (M4/AC7) |
| `tests/test_gate_pass.sh` | Added gate mirror negative, skip unless live (M4/AC7) |

## Tests by milestone

### Milestone 1 — Removed behavior (AC6/AC8/R3.3)

- `10_profile: project-local loads, no mirror created (AC6)` — renamed from
  `test_load_profile_recovers_from_project_profile`; negative assertion that
  `profiles/recoverme.env` is not written.
- `61_list: ai-list syncs project profiles automatically` — added negative
  assertion that `profiles/alex-sync.env` is not created.
- `test_scaffold_layout: scaffold does not create profiles/ mirror (R2.4)`
- `test_no_dead_install_code: install_generated_profile absent from lib/ and bin/ (R3.3)`
- `test_generated_scaffold: scaffold does not create profiles/ mirror (AC4)`

### Milestone 2 — Dual-read resolution (R1.1–R1.4, AC1/AC5/AC6)

- `project-local preferred over legacy (R1.1)` — both paths seeded; asserts
  `from-project` wins.
- `legacy fallback loads when no project tree (AC5)` — only `profiles/` file.
- `name/slug divergence resolves via raw name (Q1)` — `"My Proj"` dir with
  space; load succeeds keyed on raw name.
- `missing profile names both candidate paths` — error message must contain
  both `projects/.../profile.env` and `profiles/....env`.
- `no writeback after project-local load (AC6)` — no new file under
  `profiles/` after load.

### Milestone 3 — Dual-discovery / dedup (R2.1–R2.3, AC2/AC3)

- `ai-list dedupes project + legacy with same slug (R2.3)` — `dup` row
  count ≤ 1.
- `ai-list shows legacy-only profile (AC3)` — no `projects/` tree needed.
- `ai-list works without profiles/ dir (AC2)` — only `projects/` present;
  exits 0 and lists the project.

### Milestone 4 — Mirror-free lifecycle paths (R2.4, AC4/AC7)

- `test_generated_scaffold: scaffold does not create profiles/ mirror (AC4)`
- `test_reconcile_resume: reconcile does not create profiles/ mirror (AC7)`
- `test_gate_pass: [slow] gate does not create profiles/ mirror (AC7)` —
  gated behind `PODMAN_LIVE=1`.

### Milestone 5 — Deprecation notice (R3.2, AC5)

- `legacy load emits deprecation [INFO] (R3.2)` — asserts ≥ 1 `[INFO]` line
  naming `projects/depr/profile.env`; paired negative asserts project-local
  load emits zero `[INFO]` lines.

## Coverage map

| AC | Test(s) |
|----|---------|
| AC2 | `test_list_works_without_profiles_dir`, `test_ai_list_empty_state_exits_zero` |
| AC3 | `test_list_shows_legacy_only` |
| AC4 | `test_no_profiles_mirror_created` (scaffold) |
| AC5 | `test_legacy_fallback_loads`, `test_legacy_load_emits_deprecation_info` |
| AC6 | `test_project_local_loads_without_mirror`, `test_no_writeback_on_project_local_load` |
| AC7 | `test_reconcile_does_not_create_profile_mirror`, `test_gate_does_not_create_profile_mirror` |
| AC8 | Full suite green, no test asserts copy-back or mirror |
| R1.1 | `test_project_local_preferred_over_legacy` |
| R1.4 (Q1) | `test_name_slug_divergence_resolves` |
| R2.3 | `test_list_dedupes_by_slug` |
| R3.2 | `test_legacy_load_emits_deprecation_info` |
| R3.3 | `test_install_generated_profile_absent` |

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
