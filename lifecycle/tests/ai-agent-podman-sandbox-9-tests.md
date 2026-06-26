---
title: AI Agent Podman Sandbox Framework — Test Artifact
type: test
status: done
lineage: ai-agent-podman-sandbox
parent: lifecycle/test-plans/ai-agent-podman-sandbox-8-test.md
created: "2026-06-22T00:00:00+10:00"
---

# AI Agent Podman Sandbox Framework — Test Artifact

Documents the integration tests built for the v1 acceptance criteria (AC1–AC15),
covering the test plan at `lifecycle/test-plans/ai-agent-podman-sandbox-8-test.md`.

## What was built

### Test harness

| File | Purpose |
|------|---------|
| `tests/helpers/setup.bash` | Assertion helpers, skip helpers, temp-env setup/teardown, and `run_test` / `print_summary` runner |
| `tests/helpers/stubs/podman` | Stub `podman` binary for Tier A (dry-run) tests — satisfies `require_cmd podman` and returns safe defaults without touching containers |
| `tests/run_tests.sh` | Top-level runner: executes each `[0-9]*.sh` test file and reports overall pass/fail |

### Production changes required by testability

| File | Change |
|------|--------|
| `bin/ai-launch` | Added `DRY_RUN=1` mode: after loading the profile and validating the mode, prints the fully-assembled `podman` argument vector to stdout and exits 0, without creating or touching any container |
| `lib/profile.sh` | Relaxed `BUILD_ARGS` validation to allow empty string (was incorrectly requiring non-empty); the field must still be defined |
| `bin/launch-esp32-workspace` | Added `set -euo pipefail` (R13.1 compliance) |
| `bin/launch-uxplay-workspace` | Same |
| `bin/launch-uxplay-builder` | Same |
| `bin/short-launch-esp32-workspace` | Same |
| `bin/extra-terminal` | Same |
| `bin/update-codex-esp32-image` | Same |
| `bin/update-codex-uxplay-image` | Same |

### Test files

| File | Milestone | AC | Tier |
|------|-----------|----|------|
| `tests/00_static.sh` | T1 | — | A |
| `tests/10_profile.sh` | T2a | AC1 | A |
| `tests/11_ai-build.sh` | T2b | AC1 | A+B |
| `tests/20_safety_policy.sh` | T3 | AC2 | A |
| `tests/30_persistence.sh` | T4 | AC3 | B |
| `tests/40_modes.sh` | T5a | AC4 | A |
| `tests/41_builder.sh` | T5b | AC5, AC6 | A+B |
| `tests/50_network.sh` | T6a | AC7 | A+B |
| `tests/51_extras.sh` | T6b | AC8 | A |
| `tests/52_selinux.sh` | T6c | AC9 | A |
| `tests/60_terminal.sh` | T7a | AC10 | A+B |
| `tests/61_list.sh` | T7b | AC11 | A |
| `tests/70_wrappers.sh` | T8a | AC12 | A |
| `tests/71_secrets.sh` | T8b | AC13 | A+B |
| `tests/80_stale.sh` | T9a | AC14 | A+B |
| `tests/81_reset.sh` | T9b | AC15 | A+B |
| `tests/90_render.sh` | T10 | AC2, AC14 | A |

## How to run

### Tier A — dry-run / inspection (no Podman required)

```bash
bash tests/run_tests.sh
```

All Tier A tests pass without a Podman installation. The stub `podman` binary
in `tests/helpers/stubs/` is prepended to `PATH` automatically by the harness.

**DRY_RUN mode** (`DRY_RUN=1`) is available on `ai-launch` directly:

```bash
DRY_RUN=1 CODEX_JAILS_DIR=/path/to/jails bin/ai-launch <profile> [mode]
```

Output (to stdout): one arg per line starting with `DRY_RUN:create` (normal
modes) or `DRY_RUN:run` (builder mode), followed by all assembled arguments.

### Tier B — live Podman (rootless required)

Set `PODMAN_LIVE=1` to enable live tests. Each Tier B test creates its own
temporary `CODEX_JAILS_DIR`, builds a minimal scratch image from a
`FROM busybox:latest` `Containerfile`, and removes all containers/images in
its teardown trap.

```bash
PODMAN_LIVE=1 bash tests/run_tests.sh
```

Tier B tests are skipped cleanly (not failed) when `PODMAN_LIVE` is unset or
when rootless Podman is unavailable.

### Running a single file

```bash
bash tests/20_safety_policy.sh
PODMAN_LIVE=1 bash tests/30_persistence.sh
```

Each file is independently executable and prints its own pass/fail summary.

## Test results (Tier A)

57 Tier A tests across 17 files — all pass on a machine without Podman.
11 Tier B tests skip cleanly on the same machine.

## Deferred coverage (out of v1 scope)

Per the test plan: DA1 (desktop launchers), DA2 (ai-doctor), DA3
(agent-delegated builder), DA4 (clone-to-second-host) — none implemented here.

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
