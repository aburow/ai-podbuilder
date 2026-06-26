---
title: Curl-Driven Install Script — Test Artifact
type: test
status: done
lineage: curl-install-script
parent: lifecycle/test-plans/curl-install-script-6-test.md
created: "2026-06-26T00:00:00+10:00"
---

# Curl-Driven Install Script — Test Artifact

Documents the integration tests built for `install.sh` covering all seven
milestones from the test plan at
`lifecycle/test-plans/curl-install-script-6-test.md`.

## What was built

### Source changes

| File | Change |
|------|--------|
| `install.sh` | Added `AI_PODMAN_INSTALL_TARBALL` env-var bypass in `fetch_release()` so tests run offline without network or GitHub |

### Test files

| File | Milestones | AC / R | Tier |
|------|-----------|--------|------|
| `tests/test_install_script.sh` | M1–M6 | AC1–AC10, R1.1, R1.3, R6.1, R7.2 | A (offline) |
| `tests/00_static.sh` | M7 | shellcheck gate | A |

## Test inventory

| Test name | Milestone | Acceptance criteria |
|-----------|-----------|-------------------|
| fixture build and baseline fresh install | M1 | Harness builds tarball; offline install exits 0 |
| default install root is `$HOME/ai-podman-jails` | M2 | AC2 default |
| positional arg overrides install root | M2 | AC2 override |
| managed set present (bin lib config etc) | M2 | AC9 inclusion |
| excluded dirs absent (lifecycle tests doc docs) | M2 | AC9 exclusion |
| all installed bin/* and start-here.sh are +x | M2 | AC6 |
| five commands resolve on PATH after source env-file | M2 | AC1 |
| env file exports AI_PODMAN_JAILS_DIR, no CODEX ref | M3 | AC4, AC10 |
| second run does not corrupt env file | M3 | AC4 idempotency |
| bashrc guard is idempotent; profile/zshrc unwritten | M3 | AC5 |
| update preserves projects/ and user profiles/*.env | M4 | AC3 |
| missing podman exits non-zero, no install root | M5 | AC7 |
| corrupt tarball (fresh) exits non-zero, no bin/ | M5 | AC8 fresh |
| corrupt tarball (update) leaves prior install intact | M5 | AC8 update, R7.2 |
| pipe invocation produces same layout as file run | M6 | R1.1 |
| --help exits 0 with usage (both invocation forms) | M6 | R1.3 |
| CODEX_JAILS_DIR in bashrc triggers exactly one warn | M6 | Q6 a+b, R6.1 |

## Offline fixture design

`AI_PODMAN_INSTALL_TARBALL` is an env-var that `install.sh` reads inside
`fetch_release()`. When set, it bypasses curl/GitHub and copies the named
file to `$STAGE/src.tar.gz`; extraction proceeds normally. The test file
builds a tarball of the working tree (single top-level dir
`ai-podbuilder-test/`, `.git` excluded) once at module load time, shared
across all tests in the file.

Each test creates its own sandboxed `HOME` inside `_TMPDIR` (which
`setup_test_env`/`teardown_test_env` in the harness manage), so no test
writes outside its temp directory.

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
