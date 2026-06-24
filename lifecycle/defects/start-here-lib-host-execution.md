---
title: 'start-here.sh: /start-here-lib mount guard blocks all host-side test execution'
type: defect
status: draft
lineage: start-here-lib-host-execution
created: "2026-06-23T00:00:00+10:00"
priority: high
labels:
    - defect
assignees:
    - role: backend-developer
      who: agent
parent: lifecycle/test-plans/ai-new-container-setup-failures-5-test.md
---

# start-here.sh: /start-here-lib mount guard blocks all host-side test execution

## Summary

`start-here.sh` (committed in `67649b1` — feat(F1): Install the pinned runtime before validation)
checks for `/start-here-lib/common.sh` and `/start-here-lib/adapter.sh` as its **very first
action**, before argument parsing and before reading `BOOTSTRAP_DIR`. These paths are
container-only (bind-mounted from `lib/` by the launcher). The test harness patches
`BOOTSTRAP_DIR` via `sed` but cannot inject `/start-here-lib/`, so every host-side execution
of `start-here.sh` exits 1 with "Required mount is absent" before any testable code is reached.

This causes **19 test failures** across five test files.

## Reproduction Steps

1. From the repo root, run any test that executes `start-here.sh` host-side:
   ```
   bash tests/test_start_here_resolution.sh
   bash tests/test_auth_gate.sh
   bash tests/test_manual_runtime.sh
   bash tests/test_resume_agent_pinned.sh   # start-here.sh tests only
   bash tests/test_help_and_flags.sh        # start-here.sh tests only
   ```
2. Observe that each exits 1 immediately with:
   ```
   [ERROR] Required mount is absent: /start-here-lib/common.sh
           Ensure the bootstrap container was started with a current version of ai-new.
   ```
3. The guard appears at lines 12–25 of `start-here.sh`, before the `while [[ $# -gt 0 ]]`
   argument-parsing loop at line 68.

## Expected Behaviour

- `start-here.sh -h` / `--help` exits 0 and prints usage regardless of whether
  `/start-here-lib/` is present.
- The library mount check occurs **after** flag parsing so that `--help` works without
  a container mount, or the script falls back to `${BASH_SOURCE[0]%/*}/../lib/` when
  `/start-here-lib/` is absent (enabling host-side testing).
- The following 19 test assertions pass:

  | Test file | Failing tests |
  |---|---|
  | `test_start_here_resolution.sh` | all 6 (start-here.sh -h, single runtime, zero runtimes, missing agent.env, --resume, unknown flag) |
  | `test_auth_gate.sh` | 5/6 (auth failure reports error, API key var, auth success, no-auth-check, command not on PATH) |
  | `test_manual_runtime.sh` | 3/4 (reports manual setup, present command proceeds, names missing command) |
  | `test_resume_agent_pinned.sh` | 2/5 (start-here.sh --resume uses pinned runtime, does not prompt for agent) |
  | `test_help_and_flags.sh` | 3/9 (start-here.sh -h, --help, unknown flag) |

## Actual Behaviour

All 19 assertions fail. The script exits 1 unconditionally when `/start-here-lib/common.sh`
is absent, before it can process any flags or read `BOOTSTRAP_DIR`.

Representative output (every run):
```
[ERROR] Required mount is absent: /start-here-lib/common.sh
        Ensure the bootstrap container was started with a current version of ai-new.
```

Tests that expect exit 0 get exit 1; tests that expect specific error messages receive the
mount-absent error instead; the `-h` short-circuit never fires.

## Root-Cause Analysis

Commit `67649b1` inserted the library-mount guard at the top of `start-here.sh` (lines 12–25)
as part of introducing `_install_runtime`/`run_install_adapter` functionality. The guard is
correct for the container runtime, but the test harness (which pre-dates F1) expects to run
`start-here.sh` host-side by patching only `BOOTSTRAP_DIR`. No test sets up
`/start-here-lib/`, so the guard fires unconditionally.

Candidate fixes (in order of preference):
1. **Move the guard after flag parsing** so `-h`/`--help` always works; fall back to
   `$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib` when `/start-here-lib/` is absent.
2. **Allow `START_HERE_LIB` env var override** so tests can inject a local lib path without
   touching `/start-here-lib/`.
3. **Update the test harness** to create a stub `/start-here-lib/` tmpfs for each test run
   (invasive, requires root or bind-mount capability in CI).

## Logs / Output

```
=== test_start_here_resolution.sh ===
    ASSERT_SUCCESS fail: start-here.sh -h should exit 0: exit 1 (expected 0)
    ASSERT_CONTAINS fail: Usage not found in output
  FAIL  start-here.sh -h exits 0 with agent.env present
  FAIL  single configured runtime resolved automatically
    ASSERT_CONTAINS fail: error should mention no runtime: No\ agent\ runtime not found in output
  FAIL  zero runtimes → fail with setup guidance
    ASSERT_CONTAINS fail: Missing\ pinned\ agent\ registry not found in output
  FAIL  missing agent.env → fail with message
  FAIL  --resume uses pinned runtime, no re-prompt
    ASSERT_CONTAINS fail: Unknown\ flag not found in output
  FAIL  unknown flag exits non-zero
  ── test_start_here_resolution: 0 passed  6 failed  0 skipped

=== test_auth_gate.sh ===
    ASSERT_CONTAINS fail: error should mention auth: authentication not found in output
    ASSERT_CONTAINS fail: error should name the runtime: fail-bot2 not found in output
  FAIL  auth failure reports error with runtime name
    ASSERT_CONTAINS fail: error should mention required API key var: MY_API_KEY not found in output
    ASSERT_CONTAINS fail: error should mention agent.env.local path: agent.env.local not found in output
  FAIL  auth failure reports API key var and setup path
    ASSERT_CONTAINS fail: auth pass should be logged: Auth\ check\ passed not found in output
  FAIL  auth success logs pass and proceeds to launch
    ASSERT_SUCCESS fail: no auth-check with existing command should succeed: exit 1 (expected 0)
  FAIL  no auth-check: just verify command exists
    ASSERT_CONTAINS fail: error should mention not installed: not\ installed not found in output
  FAIL  command not on PATH → not installed error
  ── test_auth_gate: 1 passed  5 failed  0 skipped

=== test_manual_runtime.sh ===
    ASSERT_CONTAINS fail: error should mention manual adapter: manual not found in output
    ASSERT_CONTAINS fail: error should say install manually: manually not found in output
  FAIL  manual adapter + missing command → reports manual setup
    ASSERT_SUCCESS fail: manual + present command should succeed: exit 1 (expected 0)
  FAIL  manual adapter + present command → proceeds normally
    ASSERT_CONTAINS fail: error should name the missing command: gemini-cli-really-missing not found in output
  FAIL  manual adapter error names the missing command
  ── test_manual_runtime: 1 passed  3 failed  0 skipped

=== test_resume_agent_pinned.sh ===
    ASSERT_SUCCESS fail: --resume with pinned runtime should succeed: exit 1 (expected 0)
    ASSERT_CONTAINS fail: start-here.sh should log the resolved runtime: resolved\ runtime not found in output
  FAIL  start-here.sh --resume uses pinned runtime
    ASSERT_SUCCESS fail: exit 1 (expected 0)
  FAIL  start-here.sh --resume does not prompt for agent
  ── test_resume_agent_pinned: 3 passed  2 failed  0 skipped

=== test_help_and_flags.sh ===
    ASSERT_SUCCESS fail: start-here.sh -h should exit 0: exit 1 (expected 0)
    ASSERT_CONTAINS fail: help should print Usage: Usage not found in output
  FAIL  start-here.sh -h exits 0 and prints usage
    ASSERT_SUCCESS fail: start-here.sh --help should exit 0: exit 1 (expected 0)
    ASSERT_CONTAINS fail: Usage not found in output
  FAIL  start-here.sh --help exits 0 and prints usage
    ASSERT_CONTAINS fail: Unknown\ flag not found in output
  FAIL  start-here.sh unknown flag exits non-zero
  ── test_help_and_flags: 7 passed  3 failed  0 skipped
```
