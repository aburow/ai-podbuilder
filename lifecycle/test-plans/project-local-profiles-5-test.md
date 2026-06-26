---
title: Project-Local Profile Canonicalization — Test Plan
type: plan-test
status: in-development
lineage: project-local-profiles
parent: lifecycle/frontend-plans/project-local-profiles-4-fe.md
---

# Project-Local Profile Canonicalization — Test Plan

Updates existing suites that assert the removed mirror/copy-back behavior (R4.2)
and adds coverage for the new dual-read / dual-discovery semantics. All
acceptance criteria AC1–AC8 must be covered. Tests use the existing
`tests/helpers/setup.bash` harness (temp `CODEX_JAILS_DIR`, seeded
`profiles/esp32.env` + `profiles/uxplay.env`, podman stub).

## Milestone 1 — Fix tests that assert removed behavior (R4.2, AC8)

Files to change:
- `tests/10_profile.sh` — `test_load_profile_recovers_from_project_profile`
  (lines 129–159) currently asserts that loading from the project tree **writes**
  `profiles/recoverme.env`. Invert it: assert the project-local file loads AND
  that `profiles/recoverme.env` is **not** created (AC6). Rename to reflect
  dual-read, not "recover".
- `tests/61_list.sh`:
  - `test_ai_list_missing_profiles_dir_exits_nonzero` (lines 73–83) — invert to
    `test_ai_list_missing_profiles_dir_exits_zero`: with no `profiles/` and no
    projects, `ai-list` exits 0 and prints the empty-state line (AC2).
  - `test_ai_list_sees_registered_generated_project` (93–123) — drop the
    `install_generated_profile` call; assert the project is listed straight from
    `projects/alex/profile.env` with no mirror written (AC3/AC4).
  - `test_ai_list_syncs_project_profiles_automatically` (125–157) — remove the
    `[[ -f profiles/alex-sync.env ]]` sync assertion; keep the "listed" assertion,
    add a negative assertion that no mirror file was created.
- `tests/test_scaffold_layout.sh`, `tests/test_generated_scaffold.sh` — confirm
  they only assert `projects/<name>/profile.env` is created (they do today); add
  a negative assertion that scaffold/`ai-new` does not create `profiles/<slug>.env`.
- `tests/test_no_dead_install_code.sh` — add an assertion that
  `install_generated_profile` no longer appears in `lib/`, `bin/` (R3.3).

Acceptance criteria:
- Full suite (`tests/run_tests.sh`) passes; no test asserts copy-back, mirror,
  or required `profiles/` directory (AC8).

## Milestone 2 — Dual-read resolution coverage (R1.1–R1.4, AC1/AC5/AC6)

Files to change:
- `tests/10_profile.sh` — add:
  - `test_project_local_preferred_over_legacy`: write both
    `projects/p/profile.env` (PROFILE_NAME=from-project) and
    `profiles/p.env` (PROFILE_NAME=from-legacy); assert `load_profile p` yields
    the project-local value.
  - `test_legacy_fallback_loads`: only `profiles/<slug>.env` present →
    `load_profile <name>` succeeds (AC5).
  - `test_name_slug_divergence_resolves`: project dir named with a raw name whose
    slug differs (e.g. `My Proj` → `my-proj`); only the project tree exists;
    assert resolution succeeds keyed by raw name (Q1 regression guard).
  - `test_missing_profile_names_both_paths`: `load_profile nope` dies non-zero and
    the message contains both the `projects/.../profile.env` and
    `profiles/....env` candidate paths.
  - `test_no_writeback_on_project_local_load`: after a project-local load, assert
    `profiles/` contains no new file (AC6).

Acceptance criteria:
- Each test above passes against the new `load_profile`.

## Milestone 3 — Dual-discovery / dedup coverage (R2.1–R2.3, AC2/AC3)

Files to change:
- `tests/61_list.sh` — add:
  - `test_list_dedupes_by_slug`: create `projects/dup/profile.env` and a legacy
    `profiles/dup.env` for the same slug; assert exactly one `dup` row.
  - `test_list_shows_legacy_only`: a legacy `profiles/legacyonly.env` with no
    project tree appears in the listing (AC3).
  - `test_list_works_without_profiles_dir`: remove `profiles/`, keep one project;
    assert it lists and exit code is 0 (AC2).

Acceptance criteria:
- Dedup row count and legacy-only visibility verified; absent `profiles/` is
  non-fatal.

## Milestone 4 — Mirror-free lifecycle paths (R2.4, AC4/AC7)

Files to change / add:
- Extend or add to `tests/test_reconcile_resume.sh` and the gate suite
  (`tests/test_gate_pass.sh`): after a reconcile / quality-gate run on a project,
  assert no `profiles/<slug>.env` was created or refreshed (AC7).
- `tests/test_generated_scaffold.sh` (or `tests/11_ai-build.sh` flow): after the
  `ai-new` create path, assert no mirror exists under `profiles/` (AC4).

Acceptance criteria:
- AC4 and AC7 each have a dedicated negative assertion.

## Milestone 5 — Deprecation notice (R3.2, AC5)

Files to change:
- `tests/10_profile.sh` — `test_legacy_load_emits_deprecation_info`: capture
  stderr of a legacy-only load; assert exactly one `[INFO]` deprecation line that
  names the canonical project-local path. Add the paired negative:
  project-local load produces no such line.

Acceptance criteria:
- Notice present once for legacy loads, absent for project-local loads.

## End-to-end gate

- `tests/run_tests.sh` green with all of the above (AC8).
- Spot-check AC1 manually or via an existing build/launch test stub: a project
  with only `projects/<name>/profile.env` drives `ai-build`/`ai-launch`/
  `ai-terminal` profile loading without a legacy copy.
