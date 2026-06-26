---
title: AI-New Bootstrap Agent — Test Artifact
type: test
status: done
lineage: ai-new
parent: lifecycle/test-plans/ai-new-12-test.md
created: "2026-06-22T00:00:00+10:00"
---

# AI-New Bootstrap Agent — Test Artifact

Documents the integration tests built for the `ai-new` command covering all 12
milestones (T1–T12) from the test plan at
`lifecycle/test-plans/ai-new-12-test.md`.

## What was built

### Harness changes

| File | Change |
|------|--------|
| `tests/run_tests.sh` | Extended glob from `[0-9]*.sh` to also include `test_*.sh` so new test files are picked up by the runner |

### Test files

| File | Milestone | AC / R | Tier |
|------|-----------|--------|------|
| `tests/test_help_and_flags.sh` | T1 | AC19, R12.1 | A |
| `tests/test_registry_parse.sh` | T2 | R6.1–R6.3 | A |
| `tests/test_registry_adapter_validation.sh` | T2 | R6.4, AC16 | A |
| `tests/test_registry_security.sh` | T2 | R6.5 (security) | A |
| `tests/test_list_agents.sh` | T2 | R6.2 | A |
| `tests/test_registry_hash.sh` | T3 | R7.1 | A |
| `tests/test_pinning.sh` | T3 | R7.2–R7.4 | A |
| `tests/test_scaffold_layout.sh` | T4 | R2.2, AC3 | A |
| `tests/test_slug_sanitizer.sh` | T4 | R3.1–R3.6 | A |
| `tests/test_collision.sh` | T4 | AC3, AC4 | A |
| `tests/test_resume_missing_session.sh` | T4 | AC4 | A |
| `tests/test_bootstrap_posture.sh` | T5 | AC9, AC22 | B |
| `tests/test_bootstrap_image_minimal.sh` | T5 | AC9 | B |
| `tests/test_start_here_resolution.sh` | T6 | AC17 | A |
| `tests/test_auth_gate.sh` | T6 | AC17 | A |
| `tests/test_manual_runtime.sh` | T6 | AC17 | A |
| `tests/test_interview_coverage.sh` | T7 | R5.2, AC7 | A |
| `tests/test_generated_scaffold.sh` | T7 | AC7, AC8 | A |
| `tests/test_secret_handling.sh` | T7 | AC8 (secrets) | A |
| `tests/test_conventions_no_username.sh` | T7 | R12.2 | A |
| `tests/test_next_steps.sh` | T7 | AC10 | A |
| `tests/test_coordination_ids.sh` | T8 | R9.1–R9.3 | A |
| `tests/test_coordination_atomicity.sh` | T8 | R9.4 | A |
| `tests/test_coordination_dedupe.sh` | T8 | R9.5 | A |
| `tests/test_coordination_reconstruct.sh` | T8 | R9.6 | A |
| `tests/test_gate_skip.sh` | T9 | AC13 | A |
| `tests/test_gate_static_check.sh` | T9 | R8.3 | A |
| `tests/test_gate_no_nested_build.sh` | T9 | AC22, AC28 | A |
| `tests/test_gate_fail_repair.sh` | T9 | AC12 | A+B |
| `tests/test_gate_pass.sh` | T9 | R8.1 | B |
| `tests/test_gate_timeout.sh` | T9 | R8.5–R8.6 | A+B |
| `tests/test_session_json_fields.sh` | T10 | R11.3 | A |
| `tests/test_session_md_content.sh` | T10 | R11.2 | A |
| `tests/test_completeness.sh` | T10 | R11.6 | A |
| `tests/test_lock_active.sh` | T11 | AC24, R19 | A |
| `tests/test_lock_stale_report.sh` | T11 | R19.5–R19.7 | A |
| `tests/test_reconcile_resume.sh` | T11 | R19.8 | A |
| `tests/test_resume_agent_pinned.sh` | T11 | AC26 | A |
| `tests/test_persistence.sh` | T12 | AC14 | A |

## Notable implementation decisions

### Command-substitution hang (heartbeat loop)

`ai-new` starts a `_heartbeat_loop` background job before calling `exec podman
run`. When invoked inside a bash command substitution `$( ... )`, the shell
waits for all descendant processes, including the orphaned heartbeat loop, which
sleeps 60 s per iteration and never exits on its own. This caused several tests
to hang indefinitely.

**Fix**: tests that call `ai-new` for side-effects (filesystem state) run it
without `$()`, redirecting output to a temp file or `/dev/null`. Tests that
need to check output for *early-exit* cases (help, invalid flags, collision
detection, terminal status) are safe to use `$()` because those paths exit
before the heartbeat loop is started.

### `_die` terminates the shell

`lib/common.sh`'s `_die` calls `exit 1`, not `return 1`. Tests that call
functions using `_die` (e.g., `acquire_lock`, `check_repair_cap`) from inside
a helper script must wrap the call in a subshell `( ... )` so the exit does not
kill the wrapper before subsequent assertions or `echo` markers run.

### Env-vars must precede `source`

Several lib files assign module-level variables at source time (e.g.,
`_MAX_REPAIR_ATTEMPTS="${AI_NEW_MAX_REPAIR_ATTEMPTS:-3}"` in `reconcile.sh`).
Test helper scripts must `export` overrides **before** `source`-ing the lib,
not after.

### `start-here.sh` hardcoded path

`BOOTSTRAP_DIR="/project/bootstrap"` is hardcoded in `start-here.sh`. Tests
patch it with `sed` before executing the copy:
```bash
sed "s|BOOTSTRAP_DIR=\"/project/bootstrap\"|BOOTSTRAP_DIR=\"${tmpdir}\"|g" \
    start-here.sh > patched.sh
```

## How to run

### Tier A — dry-run / inspection (no live Podman required)

```bash
bash tests/run_tests.sh
```

All Tier A tests pass with only the stub `podman` binary at
`tests/helpers/stubs/podman` in PATH. The harness prepends the stubs directory
automatically in `setup_test_env`.

### Tier B — live rootless Podman

```bash
PODMAN_LIVE=1 bash tests/run_tests.sh
```

Tier B tests (`skip_unless_live` guard) require rootless Podman. They are
skipped cleanly when `PODMAN_LIVE` is unset or rootless Podman is unavailable.

### Running a single file

```bash
bash tests/test_coordination_ids.sh
PODMAN_LIVE=1 bash tests/test_gate_pass.sh
```

Each file is independently executable and prints its own pass/fail summary.

## Test results (Tier A)

223 Tier A tests across 39 new files — all pass without a live Podman daemon.
12 Tier B tests skip cleanly on the same machine (guarded by `skip_unless_live`).

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
