---
title: Reliable release process that publishes and verifies the install.sh asset — Test Plan
type: plan-test
status: done
lineage: release-installer-asset-missing
parent: lifecycle/requirements/release-installer-asset-missing-2.md
---

# Test Plan — Release Flow Verification & Installer Smoke Test

Bash integration tests in `tests/`, picked up by `run_tests.sh`'s
`[0-9]*.sh`/`test_*.sh` glob (`tests/run_tests.sh:11`). Two distinct concerns:

1. **Unit-level / offline** tests of `devops/release.sh`'s verification logic —
   the asset gate (R2) and fail-closed ordering (R6) — driven by **fixture**
   `gh`/`curl` so they need no network and assert the `0.51` regression (AC7).
2. **A content smoke test** (R4) that fetches the installer from the public
   `latest/download` URL and confirms it is the real script without executing
   it. Per Q3 this runs over the real network at this stage, so it is **gated**
   (skipped + reported, never silently passed) when offline.

All cases assert and exit non-zero on failure, matching the existing suite
(e.g. `tests/test_install_script.sh`, `tests/00_static.sh`).

## Milestone 1 — Harness & stubbed `gh`/`curl` fixtures

**Description.** Let the verification functions be tested offline by shadowing
`gh` and `curl` with fixtures on `PATH`, so each verification branch can be
driven deterministically (uploaded asset, empty assets, 200, 404).

**Files to change.**
- `tests/test_release_flow.sh` (new): `setup()` creates a temp `bin/` with stub
  `gh`/`curl` scripts whose output is controlled by env vars (e.g. a fixture
  `assets` JSON and a fixture HTTP status); prepends it to `PATH`; sources or
  invokes the relevant functions from `devops/release.sh`.

**Acceptance criteria.**
- Fixtures let a test choose the `gh release view --json assets` payload and the
  `curl -I -L` status without touching the network.
- No test performs a real network call or mutates a real GitHub release.

## Milestone 2 — Asset-verification gate (R2)

**Description.** Verify `verify_asset` accepts a good asset and rejects every
bad shape, including the empty-array `0.51` case.

**Acceptance criteria.**
- An `assets` payload with `install.sh`, `state=="uploaded"`, `size>0` → gate
  passes (R2).
- An **empty** `assets` array → gate exits non-zero naming the missing asset
  (R2, and the core of AC7).
- An asset present but `state != "uploaded"`, or `size == 0`, → gate fails.

## Milestone 3 — Public-URL verification (R3) via fixture

**Description.** Verify `verify_public_url` enforces HTTP 200 on the
`latest/download` path and fails on 404, using the stubbed `curl`.

**Acceptance criteria.**
- Fixture `curl -I -L` returning `200` → check passes (AC2 logic).
- Fixture returning `404` → check exits non-zero, message names the
  non-200/unreachable URL (AC4).
- The URL exercised is the `/releases/latest/download/install.sh` path, not the
  version-pinned `/download/<version>/` path (R3).

## Milestone 4 — Fail-closed ordering (R6)

**Description.** Verify the flow never reports success when a verification
fails, and that asset-failure vs URL-failure are distinguishable.

**Acceptance criteria.**
- A run where the asset gate fails prints no success/"done" output and exits
  non-zero (R6).
- A run where the public-URL check fails prints no success output and exits
  non-zero (R6).
- The two failure messages are distinguishable (missing asset vs non-200 URL).
- A run where both verifications pass prints the success summary and exits 0.

## Milestone 5 — `0.51` regression test (AC7)

**Description.** A dedicated test that reproduces the original failure shape — a
release published with an **empty** assets array — and asserts the flow would
have caught it (non-zero, names the missing asset / would-be 404). This is the
test that must fail against the pre-fix behaviour.

**Files to change.**
- `tests/test_release_flow.sh`: a case feeding the empty-`assets` fixture and a
  `404` URL fixture through the full `main()`/verification path.

**Acceptance criteria.**
- With empty assets + 404, the flow exits non-zero and reports the missing asset
  / unreachable installer URL (AC7).
- The test would pass against the fixed flow and fail against a flow that skips
  R2/R3 (it genuinely guards the regression).

## Milestone 6 — Public installer content smoke test (R4)

**Description.** Network smoke test that fetches `install.sh` from the public
`latest/download` URL and confirms it is the expected script — valid shebang +
known marker — and prints the first lines, **without executing it** (R4). Gated
for offline runs (Q3) consistent with the suite's existing
`AI_PODMAN_INSTALL_TARBALL` offline philosophy.

**Files to change.**
- `tests/test_installer_url_smoke.sh` (new):
  - `curl -fsSL https://github.com/aburow/ai-podbuilder/releases/latest/download/install.sh`
    into a temp file (never `| bash`).
  - Assert first line `#!/usr/bin/env bash` and presence of a stable marker
    (`REPO="aburow/ai-podbuilder"`, `install.sh:42`); `head` the file.
  - Skip with a clear "skipped: no network / RELEASE_SKIP_NETWORK" message when
    offline so it is never silently treated as passed (Q3).

**Acceptance criteria.**
- Against a correctly-published release, the fetched file is the real
  `install.sh` (shebang + marker) and the test prints its head (AC3, R4).
- The downloaded script is **never** piped into `bash` (R4).
- When the network/URL is unavailable the test reports skipped (not passed) and
  the suite makes that visible (Q3).

## Milestone 7 — Static lint gate

**Description.** Keep the new release tooling shellcheck-clean alongside the
rest of the suite.

**Files to change.**
- `tests/00_static.sh`: extend lint coverage to include `devops/release.sh` (and
  the new test scripts where the suite already lints tests).

**Acceptance criteria.**
- `shellcheck devops/release.sh` reports no new warnings, enforced by
  `00_static.sh`.
- The new test files are discovered and run by `tests/run_tests.sh`.

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
