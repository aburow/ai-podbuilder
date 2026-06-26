---
title: Publish and verify a SHA-256 checksum for the install.sh release asset — Test Plan
type: plan-test
status: draft
lineage: release-asset-integrity
parent: lifecycle/requirements/release-asset-integrity-2.md
created: "2026-06-26T00:00:00+10:00"
priority: medium
assignees:
    - role: test-developer
      who: agent
---

# Publish and verify a SHA-256 checksum for the install.sh release asset — Test Plan

`devops/release.sh` has no existing test. The network/`gh`-dependent steps
(`create_tag`, `create_release`, `upload_asset`, `verify_public_url`) cannot run
in CI, but the integrity logic added by R1–R6 can be exercised offline by
**sourcing the script and calling its functions directly** — the file is
function-structured with `main "$@"` at the bottom, so guard the source with
`RELEASE_SOURCE_ONLY` (a one-line `[[ -n "${RELEASE_SOURCE_ONLY:-}" ]] && return 0`
above the `main "$@"` call — a backend change to enable testability; flag to the
backend dev).

Tests follow the repo convention: `tests/test_*.sh`, `set -uo pipefail`, source
`tests/helpers/setup.bash`, register in `tests/run_tests.sh`. New file:
`tests/test_release_checksum.sh`. Static lint coverage goes in `00_static.sh`.

## Milestone 1 — Checksum generation matches uploaded bytes (R1, AC2)

**Description.** Source `release.sh`, run `upload_asset` with `gh` stubbed to a
no-op on `PATH`, against a temp `REPO_ROOT` containing a known `install.sh`.
Assert `install.sh.sha256` is created with the bare filename and a hash equal to
`sha256sum < install.sh`. Mutate `install.sh`, re-run, assert the checksum file
is regenerated (not stale).

**Files to change.** `tests/test_release_checksum.sh` (new); `tests/run_tests.sh`.

**Acceptance criteria.**
- `install.sh.sha256` exists, single line `<64-hex>␠␠install.sh`, hash correct.
- Re-run after mutating `install.sh` updates the hash (proves fresh generation).

## Milestone 2 — Asset-presence verification fails closed (R3, R6, AC3)

**Description.** Drive `verify_asset` with a stubbed `gh release view … --json
assets` returning canned JSON. Cases:
- both assets `state=uploaded`, size>0 → passes (exit 0).
- `install.sh.sha256` absent → exits non-zero, message names the checksum asset.
- `install.sh.sha256` present but `state!=uploaded` or `size==0` → exits non-zero.

**Files to change.** `tests/test_release_checksum.sh`.

**Acceptance criteria.**
- Each case yields the expected exit status; failure messages identify
  `install.sh.sha256` distinctly from `install.sh`.

## Milestone 3 — Content/checksum verification, match and mismatch (R4, R6, AC2/AC3)

**Description.** Drive `verify_content` with `curl` stubbed on `PATH` to serve
local fixtures for both the `install.sh` URL and the `install.sh.sha256` URL.
Cases:
- published checksum matches the served script → passes, proceeds to
  shebang/marker checks.
- tampered served script (hash differs) → exits non-zero, message names a
  *checksum mismatch* (distinct wording from the M2 "missing asset" failure).
- verify the temp-filename normalisation: the published file records
  `install.sh` while the download is a `mktemp` path — confirm a correct hash
  still passes (guards against the R4 spurious-failure note).

**Files to change.** `tests/test_release_checksum.sh`.

**Acceptance criteria.**
- Match → exit 0; mismatch → non-zero with mismatch-specific message; `VERIFIED`
  never printed on the mismatch path.
- A correct hash passes despite the recorded-vs-actual filename difference.

## Milestone 4 — Offline bypass consistency (R5, AC5)

**Description.** With `RELEASE_SKIP_NETWORK=1`: assert `upload_asset` still
generates `install.sh.sha256` (M1 stub reused), and `verify_content` returns 0
emitting the "NOT fully verified" warning without invoking `curl` (stub `curl` to
fail loudly if called, proving the network path is skipped).

**Files to change.** `tests/test_release_checksum.sh`.

**Acceptance criteria.**
- Generation/upload run; `verify_content` skips the network compare with the
  warning; `curl` is not called; run is not reported as fully verified.

## Milestone 5 — Static lint (M7-style)

**Description.** Extend the existing `tests/00_static.sh` shellcheck/static sweep
to cover the new `release.sh` code paths (it already lints repo scripts — confirm
`devops/release.sh` is in scope, add it if not).

**Files to change.** `tests/00_static.sh`.

**Acceptance criteria.**
- `00_static.sh` passes shellcheck on the modified `devops/release.sh`.

## Out of scope

- Live `gh`/GitHub release round-trips and real `verify_public_url` (network +
  credentials) — AC1/AC4 are validated manually against a real release per the
  requirement, not in offline CI.
- The tgz-vs-install.sh Q2 ambiguity flagged in the backend plan: if resolved
  toward a tarball, these tests need revision.

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
