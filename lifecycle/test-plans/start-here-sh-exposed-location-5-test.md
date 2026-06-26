---
title: Relocate start-here.sh out of the user-accessible host project tree — Test Plan
type: plan-test
status: done
lineage: start-here-sh-exposed-location
parent: lifecycle/frontend-plans/start-here-sh-exposed-location-4-fe.md
created: "2026-06-26T00:00:00+10:00"
priority: medium
assignees:
    - role: test-developer
      who: agent
---

# Relocate start-here.sh out of the user-accessible host project tree — Test Plan

Most of the work is **updating existing tests** that encode the old
project-tree behaviour, not writing new suites. The relocation deliberately
breaks several current regression guards; this plan reconciles each to the new
`/start-here/start-here.sh` read-only-mount contract and adds the few checks the
new acceptance criteria need. Host-side patch-and-run harness must keep working
(R6) — verify it does not regress.

## Milestone 1 — Retire the obsolete project-copy tests (R1, AC1)

**Description.** These tests assert the script is staged into the project tree —
exactly the behaviour the requirement removes. They must be deleted or rewritten,
not left to fail.

- `tests/test_resume_refreshes_entrypoint.sh` — tests `refresh_bootstrap_entrypoint`
  copies into `bootstrap/home` and that resume calls it before build. The function
  is deleted (BE M2); **remove this file** (and its line in any runner manifest).
- `tests/test_start_here_executable.sh` (T1b) — asserts the scaffold copy carries
  an execute bit. No copy exists now; **remove**.
- `tests/test_start_here_location.sh` (T1a) — asserts the script lives under
  `bootstrap/home`. **Rewrite** to assert the opposite: after `create_scaffold`,
  **no** `start-here.sh` exists under `${project}/bootstrap/home/` (AC1).

**Files to change**
- Delete `tests/test_resume_refreshes_entrypoint.sh`, `tests/test_start_here_executable.sh`.
- Rewrite `tests/test_start_here_location.sh`.
- Update `tests/run_tests.sh` / any manifest that names the deleted files.

**Acceptance criteria**
- After `create_scaffold`, `${project}/bootstrap/home/start-here.sh` does not exist (AC1).
- No remaining test references `refresh_bootstrap_entrypoint`.
- `grep -rn refresh_bootstrap_entrypoint tests/` returns nothing.

## Milestone 2 — Update entrypoint / mount expectations (R2.a, R3.1, AC2, AC3)

**Description.** Point the launch-argv assertions at the new path and add the
read-only-mount guard.

- `tests/test_launch_entrypoint.sh` — change the three `assert_contains` targets
  (`:34,:47,:57`) from `/project/bootstrap/home/start-here.sh` to
  `/start-here/start-here.sh` (with `--resume` / `--shell-on-exit` suffixes intact).
- Add an assertion that the launch argv includes
  `--volume …/start-here.sh:/start-here/start-here.sh:ro` (read-only delivery, AC3).
- `tests/test_install_resolves_in_container.sh` and
  `tests/test_start_here_in_container.sh` (T1c, PODMAN_LIVE) — replace the
  `cp … bootstrap/home/start-here.sh` setup with the read-only mount
  `--volume "${REPO_ROOT}/start-here.sh:/start-here/start-here.sh:ro,z"` and invoke
  `/start-here/start-here.sh`.

**Files to change**
- `tests/test_launch_entrypoint.sh`, `tests/test_install_resolves_in_container.sh`,
  `tests/test_start_here_in_container.sh`.

**Acceptance criteria**
- Launch argv asserts entrypoint `/start-here/start-here.sh` for create, resume,
  and shell-on-exit cases (R3.1, R3.3, AC6).
- Launch argv asserts the script is mounted `:ro` (AC3).
- Container-live tests use the mount, not a project-tree copy (AC2).

## Milestone 3 — In-container immutability + current-version checks (AC3, AC4)

**Description.** New behaviour the requirement introduces needs direct coverage.
Both are `PODMAN_LIVE`-gated (skip when podman/image absent), matching T1c.

- **AC3 — not writable in container.** Launch with the `:ro` mount; from inside,
  attempt `echo x >> /start-here/start-here.sh` and assert it fails (read-only fs).
- **AC4 — current version served.** With the read-only mount this is inherent
  (live file), but assert it: write a sentinel marker into the framework
  `start-here.sh`, launch, and confirm the in-container `/start-here/start-here.sh`
  contains the marker — no stale copy intercepts it.

**Files to change**
- New `tests/test_start_here_readonly.sh` (or extend `test_start_here_in_container.sh`),
  `PODMAN_LIVE`-gated with skip-reason when the image is absent.

**Acceptance criteria**
- In-container write to the entrypoint fails (AC3).
- After editing the framework script, the launched entrypoint reflects the edit (AC4).

## Milestone 4 — Host-side testability and printed-path regression (R6, AC5, AC7)

**Description.** Confirm the relocation did not add a mount/path dependency before
flag parsing, and that printed guidance matches the new path.

- `tests/test_auth_gate.sh` and `tests/test_start_here_resolution.sh` — these run a
  `sed`-patched copy from the repo root with overridden `BOOTSTRAP_DIR`; re-run as-is
  and confirm green (R6, AC7). No path constant may force a `/start-here` mount
  before flag parsing.
- `tests/test_help_and_flags.sh` — assert `--help` exit 0 and that the printed
  `or:` invocation and "restart with" hint read `/start-here/start-here.sh` (AC5).
- `tests/test_spec_reconciled.sh` — re-run; confirm doc edits introduced no
  unannotated root-location claim.

**Files to change**
- `tests/test_help_and_flags.sh` — update/confirm printed-path assertions.
- Re-run (no edit expected): `test_auth_gate.sh`, `test_start_here_resolution.sh`,
  `test_spec_reconciled.sh`.

**Acceptance criteria**
- Host-side patched-copy suites pass unchanged (AC7, R6).
- `--help` prints the new path and exits 0 (AC5).
- `agent.env`, `agent.env.local`, `session.json`, bootstrap prompt still read from
  `/project/bootstrap` in the resolution suite (AC8).

## Full run

`tests/run_tests.sh` green end-to-end (PODMAN_LIVE checks skipped or passing),
mapping AC1–AC8 to the milestones above.

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
