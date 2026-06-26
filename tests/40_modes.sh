#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# 2026 - Anthony Burow - https://github.com/aburow
# T5a — Mode dispatch: codex/bash map to the right in-container command (AC4).
# All Tier A (DRY_RUN).
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

_dry_run() {
    local mode="$1"
    DRY_RUN=1 AI_PODMAN_JAILS_DIR="$_TMPDIR" PATH="${STUBS_DIR}:${PATH}" \
        "${BIN_DIR}/ai-launch" esp32 "$mode" 2>/dev/null
}

test_codex_mode_command() {
    local _fail=0
    local out; out="$(_dry_run codex)"
    # The DRY_RUN output for normal modes shows the podman create args;
    # the mode command (codex) is NOT in the create args — it is passed to exec.
    # What we can assert: DRY_RUN:create emitted (not DRY_RUN:run = builder)
    assert_contains "DRY_RUN:create" "$out" "codex mode uses normal (non-builder) create" || _fail=1
    assert_not_contains "--privileged" "$out" "codex mode must not be privileged" || _fail=1
    return $_fail
}

test_bash_mode_command() {
    local _fail=0
    local out; out="$(_dry_run bash)"
    assert_contains "DRY_RUN:create" "$out" "bash mode uses normal create" || _fail=1
    assert_not_contains "--privileged" "$out" || _fail=1
    return $_fail
}

test_shell_mode_is_default() {
    local _fail=0
    # shell (default) and bash should produce identical policy output
    local out_shell out_bash
    out_shell="$(DRY_RUN=1 AI_PODMAN_JAILS_DIR="$_TMPDIR" PATH="${STUBS_DIR}:${PATH}" \
        "${BIN_DIR}/ai-launch" esp32 2>/dev/null)"
    out_bash="$(_dry_run bash)"
    # Both should be normal-mode creates
    assert_contains "DRY_RUN:create" "$out_shell" || _fail=1
    assert_contains "DRY_RUN:create" "$out_bash"  || _fail=1
    return $_fail
}

test_unknown_mode_exits_nonzero() {
    local _fail=0
    local out rc=0
    out="$(DRY_RUN=1 AI_PODMAN_JAILS_DIR="$_TMPDIR" PATH="${STUBS_DIR}:${PATH}" \
        "${BIN_DIR}/ai-launch" esp32 totally_unknown_mode 2>&1)" || rc=$?
    assert_failure $rc "unknown mode should exit non-zero" || _fail=1
    assert_contains "totally_unknown_mode" "$out" "error names the bad mode" || _fail=1
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "codex mode uses normal (non-builder) container"  test_codex_mode_command
run_test "bash mode uses normal container"                 test_bash_mode_command
run_test "shell (default) mode uses normal container"      test_shell_mode_is_default
run_test "unknown mode → non-zero + mode named in error"   test_unknown_mode_exits_nonzero

print_summary "40_modes"
