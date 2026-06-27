---
title: 'ai-pod-doctor: System File Integrity Verification Command — Test Plan'
type: plan-test
status: draft
lineage: ai-pod-doctor-integrity-check
parent: lifecycle/requirements/ai-pod-doctor-integrity-check-2.md
created: "2026-06-27T00:00:00+10:00"
priority: normal
assignees:
    - role: test-developer
      who: agent
---

# ai-pod-doctor: System File Integrity Verification Command — Test Plan

`lib/integrity.sh` is a function library sourced by `bin/ai-pod-doctor`. Tests
drive it by sourcing it directly in a controlled environment — no network, no
real release tarball. A fixture tarball and a fixture install root are built at
test-setup time, so every test runs offline and deterministically.

Tests follow the repo convention: `tests/test_integrity.sh`, `set -uo
pipefail`, source `tests/helpers/setup.bash`, registered in
`tests/run_tests.sh`. Shellcheck coverage goes in `tests/00_static.sh`.

The backend plan requires `lib/integrity.sh` to export its functions cleanly
when sourced with `INTEGRITY_SOURCE_ONLY=1` (add a one-line guard above the
`main "$@"` call in `bin/ai-pod-doctor`). Flag this requirement to the backend
developer.

## Shared fixture setup

A `_build_fixture()` helper (in `tests/test_integrity.sh`) constructs:

1. A fixture install root at `${BATS_TMPDIR}/install/` containing:
   - `VERSION` with content `0.0.0-test`
   - `bin/ai-build` and `bin/ai-new` (small shell stubs)
   - `lib/common.sh` (small stub)
2. A fixture tarball at `${BATS_TMPDIR}/release.tgz` whose internal tree
   mirrors the fixture install root under `ai-podbuilder-0.0.0-test/`.
3. `curl` stub on `PATH` that serves `${BATS_TMPDIR}/release.tgz` for the
   expected tarball URL and exits non-zero for any other URL.

The fixture is built once in a `setup_file` block (bats-core style) and
cleaned in `teardown_file`. Individual test cases may mutate the install root
copy; mutations are isolated per-test via a per-test `cp -a` of the install
root.

## Milestone 1 — Happy path: clean installation exits 0 silently (AC1)

**Description.** Source `lib/integrity.sh` with `AI_PODMAN_JAILS_DIR` pointing
at the fixture install root. Run the full pipeline:
`detect_version` → `_ic_setup_tmpdir` → `fetch_tarball` → `build_manifest` →
`enumerate_installed` → `compare_files` → `print_exceptions`.

Assert:
- Exit status is 0.
- stdout is empty or contains only `all files OK`.
- `_ic_mismatch`, `_ic_missing`, `_ic_unexpected` are all empty.

**Files to change.**
- `tests/test_integrity.sh` (new)
- `tests/run_tests.sh` (register new file)

**Acceptance criteria.**
- Test passes on a clean fixture install.
- Test fails (catches the regression) if `compare_files` is patched to inject
  a false mismatch.

## Milestone 2 — Mismatch and missing/unexpected file detection (AC2, AC10)

**Description.** Three sub-cases, each run against an isolated mutated copy of
the fixture install root:

**2a — Modified file (AC2).** Overwrite `bin/ai-new` with different content.
Run the pipeline. Assert:
- Exit status 1.
- stdout contains a `MODIFIED` line for `bin/ai-new` with both the expected
  and actual hashes.
- No other files appear in exception output.

**2b — Missing file (AC10, error).** Delete `lib/common.sh` from the install
root. Run the pipeline. Assert:
- Exit status 1.
- stdout contains a `MISSING` line for `lib/common.sh`.

**2c — Unexpected file (AC10, warning).** Add `bin/extra-tool` to the install
root (not present in the tarball). Run the pipeline. Assert:
- Exit status 0 (warning only, not error — confirmed by requirement answer).
- stdout contains an `UNEXPECTED` line for `bin/extra-tool`.

**Files to change.**
- `tests/test_integrity.sh`

**Acceptance criteria.**
- Each sub-case asserts the correct exit status.
- The `MODIFIED` line includes both hash values.
- The `MISSING` line does not appear in the unexpected-file sub-case.
- The unexpected-file sub-case exits 0.

## Milestone 3 — `--verbose` and `--diff` output modes (AC3, AC4)

**Description.** Two sub-cases:

**3a — `--verbose` on clean install (AC3).** Source, run pipeline with verbose
flag set. Assert:
- Every file in the fixture install root appears in stdout with status `OK`.
- Output is sorted by relative path.
- Exit status 0.

**3b — `--diff` on modified file (AC4).** Mutate `bin/ai-new`. Run pipeline
with diff flag set. Assert:
- stdout contains a non-empty unified diff block labelled with `bin/ai-new`.
- Exit status 1.
- The diff block contains `---` and `+++` lines referencing `bin/ai-new`.

**Files to change.**
- `tests/test_integrity.sh`

**Acceptance criteria.**
- `--verbose` test fails if any file row is missing or if status is not `OK`
  for an unmodified fixture.
- `--diff` test fails if the diff block is empty.
- Combined `--verbose --diff` on a modified file produces both the full table
  and the diff (one additional test case).

## Milestone 4 — Interactive repair and `--repair` flag (AC5, AC6)

**Description.** Two sub-cases, each starting from a mutated fixture install
root with `bin/ai-new` overwritten:

**4a — Accepting interactive repair (AC5).** Pipe `y\n` into stdin (or use a
here-string). Run `bin/ai-pod-doctor integrity-check` as a subprocess
(not sourced). Assert:
- Exit status 0.
- `bin/ai-new` in the install root matches the fixture tarball content after
  the run.
- Unmodified files (`bin/ai-build`, `lib/common.sh`) are unchanged.

**4b — Declining interactive repair (AC6).** Pipe `n\n` into stdin. Run
as subprocess. Assert:
- Exit status 1.
- `bin/ai-new` in the install root still has the mutated content (unchanged).

**4c — `--repair` non-interactive.** Run `bin/ai-pod-doctor integrity-check
--repair` with stdin closed. Assert:
- Exit status 0.
- `bin/ai-new` restored to tarball content.
- No prompt on stdout/stderr.

**Files to change.**
- `tests/test_integrity.sh`

**Acceptance criteria.**
- Sub-case 4a: exit 0 + file content restored.
- Sub-case 4b: exit 1 + file content unchanged.
- Sub-case 4c: exit 0 + no prompt text in output.
- Permissions on restored file match the fixture tarball entry permissions.

## Milestone 5 — Error paths: version missing, network failure, temp cleanup (AC7, AC8, AC9)

**Description.** Three error-path sub-cases:

**5a — No VERSION file (AC7).** Remove `VERSION` from the fixture install root.
Run the command. Assert:
- Exit status 3.
- stderr contains "version" and "reinstall" (or equivalent clear guidance).

**5b — Unreachable tarball (AC8).** Override the `curl` stub to exit non-zero
for the tarball URL. Run the command. Assert:
- Exit status 2.
- stderr contains the attempted URL.

**5c — Temp directory cleanup (AC9).** Capture the temp directory path from a
debug-mode run (or check `/tmp` before and after). Assert:
- After exit (both success and failure paths), no `tmp.*` directory belonging
  to the run remains under `/tmp` or `${TMPDIR}`.

Run 5c for at least: clean path, mismatch path, and error path (version
missing).

**Files to change.**
- `tests/test_integrity.sh`

**Acceptance criteria.**
- Sub-case 5a exits 3 with an informative message.
- Sub-case 5b exits 2 with the URL in stderr.
- Sub-case 5c: temp directory absent after exit on all three tested paths.

## Milestone 6 — Static lint coverage (`shellcheck`)

**Description.** Add `bin/ai-pod-doctor` and `lib/integrity.sh` to the
`shellcheck` invocations in `tests/00_static.sh`. Use `-x` to follow
`source` directives. The check must pass with zero warnings.

**Files to change.**
- `tests/00_static.sh`

**Acceptance criteria.**
- `shellcheck -x bin/ai-pod-doctor lib/integrity.sh` exits 0.
- The `00_static.sh` test fails if either file is removed from the check list.

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
