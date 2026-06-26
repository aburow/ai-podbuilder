#!/usr/bin/env bash
# T8a — Legacy compatibility wrappers delegate to the right generic command (AC12).
# All Tier A (DRY_RUN intercept).
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

# Each wrapper is exec'd via the bin/ directory.
# We use DRY_RUN=1 for wrappers that forward to ai-launch, and direct invocation
# for wrappers that forward to ai-build (which requires an IMAGE_DIR to exist).

_dry_run_wrapper() {
    local wrapper="$1"
    DRY_RUN=1 AI_PODMAN_JAILS_DIR="$_TMPDIR" PATH="${STUBS_DIR}:${PATH}" \
        "${BIN_DIR}/${wrapper}" 2>/dev/null
}

test_launch_esp32_workspace_delegates_to_ai_launch() {
    # launch-esp32-workspace → ai-launch esp32 [args]
    local _fail=0
    local out; out="$(_dry_run_wrapper launch-esp32-workspace)"
    assert_contains "DRY_RUN:create" "$out" "delegates to ai-launch (create)" || _fail=1
    assert_contains "esp32" "$out" "uses esp32 profile" || _fail=1
    return $_fail
}

test_short_launch_esp32_workspace_delegates() {
    local _fail=0
    local out; out="$(_dry_run_wrapper short-launch-esp32-workspace)"
    assert_contains "DRY_RUN:create" "$out" || _fail=1
    assert_contains "esp32" "$out" || _fail=1
    return $_fail
}

test_launch_uxplay_workspace_delegates() {
    local _fail=0
    local out; out="$(_dry_run_wrapper launch-uxplay-workspace)"
    assert_contains "DRY_RUN:create" "$out" "delegates to ai-launch (create)" || _fail=1
    assert_contains "uxplay" "$out" "uses uxplay profile" || _fail=1
    return $_fail
}

test_launch_uxplay_builder_delegates_builder_mode() {
    local _fail=0
    local out; out="$(_dry_run_wrapper launch-uxplay-builder)"
    # builder mode → DRY_RUN:run with --privileged
    assert_contains "DRY_RUN:run"  "$out" "builder wrapper uses podman run" || _fail=1
    assert_contains "--privileged" "$out" "builder wrapper is privileged"   || _fail=1
    assert_contains "uxplay"       "$out" "uses uxplay profile"             || _fail=1
    return $_fail
}

test_update_codex_esp32_image_delegates_to_ai_build() {
    # update-codex-esp32-image → ai-build esp32
    # ai-build will fail because IMAGE_DIR doesn't exist; that's expected.
    local _fail=0
    local out rc=0
    out="$(AI_PODMAN_JAILS_DIR="$_TMPDIR" PATH="${STUBS_DIR}:${PATH}" \
        "${BIN_DIR}/update-codex-esp32-image" 2>&1)" || rc=$?
    # Must fail because IMAGE_DIR absent — but must reference esp32
    assert_failure $rc "delegates to ai-build (fails without IMAGE_DIR)" || _fail=1
    assert_contains "esp32" "$out" "references esp32 profile" || _fail=1
    return $_fail
}

test_update_codex_uxplay_image_delegates_to_ai_build() {
    local _fail=0
    local out rc=0
    out="$(AI_PODMAN_JAILS_DIR="$_TMPDIR" PATH="${STUBS_DIR}:${PATH}" \
        "${BIN_DIR}/update-codex-uxplay-image" 2>&1)" || rc=$?
    assert_failure $rc "delegates to ai-build (fails without IMAGE_DIR)" || _fail=1
    assert_contains "uxplay" "$out" "references uxplay profile" || _fail=1
    return $_fail
}

test_extra_terminal_delegates_to_ai_terminal() {
    # extra-terminal defaults to esp32; ai-terminal exits non-zero when not running.
    local _fail=0
    local out rc=0
    out="$(AI_PODMAN_JAILS_DIR="$_TMPDIR" PATH="${STUBS_DIR}:${PATH}" \
        "${BIN_DIR}/extra-terminal" 2>&1)" || rc=$?
    assert_failure $rc "extra-terminal → ai-terminal → non-zero (not running)" || _fail=1
    assert_contains "esp32" "$out" "references esp32 by default" || _fail=1
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "launch-esp32-workspace → ai-launch esp32"        test_launch_esp32_workspace_delegates_to_ai_launch
run_test "short-launch-esp32-workspace → ai-launch esp32"  test_short_launch_esp32_workspace_delegates
run_test "launch-uxplay-workspace → ai-launch uxplay"      test_launch_uxplay_workspace_delegates
run_test "launch-uxplay-builder → ai-launch uxplay builder" test_launch_uxplay_builder_delegates_builder_mode
run_test "update-codex-esp32-image → ai-build esp32"       test_update_codex_esp32_image_delegates_to_ai_build
run_test "update-codex-uxplay-image → ai-build uxplay"     test_update_codex_uxplay_image_delegates_to_ai_build
run_test "extra-terminal → ai-terminal esp32"               test_extra_terminal_delegates_to_ai_terminal

print_summary "70_wrappers"
