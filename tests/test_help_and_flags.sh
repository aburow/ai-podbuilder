#!/usr/bin/env bash
# T1 — Command surface, help & flag handling (AC19, R12.1).
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

# ── Helpers ───────────────────────────────────────────────────────────────────

_ai_new() {
    CODEX_JAILS_DIR="${_TMPDIR}" bash "${BIN_DIR}/ai-new" "$@" 2>&1
}

_start_here() {
    bash "${REPO_ROOT}/start-here.sh" "$@" 2>&1
}

# ── Tests ─────────────────────────────────────────────────────────────────────

test_ai_new_help_exits_zero() {
    local _fail=0
    local out rc=0
    out="$(_ai_new -h)" || rc=$?
    assert_success $rc "ai-new -h should exit 0" || _fail=1
    assert_contains "Usage" "$out" "help should print Usage" || _fail=1
    assert_contains "ai-new" "$out" "help should mention ai-new" || _fail=1
    return $_fail
}

test_ai_new_help_long_form_exits_zero() {
    local _fail=0
    local out rc=0
    out="$(_ai_new --help)" || rc=$?
    assert_success $rc "ai-new --help should exit 0" || _fail=1
    assert_contains "Usage" "$out" || _fail=1
    return $_fail
}

test_start_here_help_exits_zero() {
    local _fail=0
    local out rc=0
    out="$(_start_here -h)" || rc=$?
    assert_success $rc "start-here.sh -h should exit 0" || _fail=1
    assert_contains "Usage" "$out" "help should print Usage" || _fail=1
    assert_contains "start-here.sh" "$out" "help should mention script name" || _fail=1
    return $_fail
}

test_start_here_help_long_form_exits_zero() {
    local _fail=0
    local out rc=0
    out="$(_start_here --help)" || rc=$?
    assert_success $rc "start-here.sh --help should exit 0" || _fail=1
    assert_contains "Usage" "$out" || _fail=1
    return $_fail
}

test_force_flag_is_deferred() {
    local _fail=0
    local out rc=0
    out="$(_ai_new myproject --force 2>&1)" || rc=$?
    assert_failure $rc "--force should exit non-zero" || _fail=1
    assert_contains "deferred" "$out" "--force should mention deferred" || _fail=1
    return $_fail
}

test_refresh_agent_registry_is_deferred() {
    local _fail=0
    local out rc=0
    out="$(_ai_new myproject --refresh-agent-registry 2>&1)" || rc=$?
    assert_failure $rc "--refresh-agent-registry should exit non-zero" || _fail=1
    assert_contains "deferred" "$out" "--refresh-agent-registry should mention deferred" || _fail=1
    return $_fail
}

test_unknown_flag_exits_nonzero() {
    local _fail=0
    local out rc=0
    out="$(_ai_new myproject --totally-unknown-flag 2>&1)" || rc=$?
    assert_failure $rc "unknown flag should exit non-zero" || _fail=1
    assert_contains "Unknown flag" "$out" "error should mention unknown flag" || _fail=1
    return $_fail
}

test_no_name_prints_usage_and_exits_nonzero() {
    local _fail=0
    local out rc=0
    out="$(_ai_new 2>&1)" || rc=$?
    assert_failure $rc "no name should exit non-zero" || _fail=1
    assert_contains "Usage" "$out" "should print usage when no name given" || _fail=1
    return $_fail
}

test_podman_unavailable_exits_nonzero() {
    local _fail=0
    # Create a minimal PATH with essential tools but no podman.
    # Use a fake dir that has symlinks to the essential tools but not podman.
    local _no_podman_bin="${_TMPDIR}/no_podman_bin"
    mkdir -p "$_no_podman_bin"
    # Symlink essential posix tools but not podman.
    local _tool
    for _tool in bash sh date hostname grep awk sed cat mkdir rm mv cp printf; do
        local _real
        _real="$(command -v "$_tool" 2>/dev/null || true)"
        [[ -n "$_real" ]] && ln -sf "$_real" "${_no_podman_bin}/${_tool}" 2>/dev/null || true
    done
    local out rc=0
    out="$(PATH="${_no_podman_bin}" CODEX_JAILS_DIR="${_TMPDIR}" bash "${BIN_DIR}/ai-new" anything --agent codex 2>&1)" || rc=$?
    assert_failure $rc "missing podman should exit non-zero" || _fail=1
    # The error message should mention podman.
    local _found=0
    [[ "$out" == *"podman"* ]] && _found=1
    [[ "$_found" -eq 1 ]] || {
        printf '    Expected podman-related error message, got: %s\n' "$out" >&2
        _fail=1
    }
    return $_fail
}

test_start_here_unknown_flag_exits_nonzero() {
    local _fail=0
    local out rc=0
    out="$(_start_here --totally-bogus 2>&1)" || rc=$?
    assert_failure $rc "start-here.sh unknown flag should exit non-zero" || _fail=1
    assert_contains "Unknown flag" "$out" || _fail=1
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "ai-new -h exits 0 and prints usage"             test_ai_new_help_exits_zero
run_test "ai-new --help exits 0 and prints usage"         test_ai_new_help_long_form_exits_zero
run_test "start-here.sh -h exits 0 and prints usage"      test_start_here_help_exits_zero
run_test "start-here.sh --help exits 0 and prints usage"  test_start_here_help_long_form_exits_zero
run_test "--force exits non-zero with deferred message"   test_force_flag_is_deferred
run_test "--refresh-agent-registry exits non-zero"        test_refresh_agent_registry_is_deferred
run_test "unknown flag exits non-zero"                    test_unknown_flag_exits_nonzero
run_test "no project name prints usage and exits non-zero" test_no_name_prints_usage_and_exits_nonzero
run_test "podman unavailable exits non-zero with message" test_podman_unavailable_exits_nonzero
run_test "start-here.sh unknown flag exits non-zero"      test_start_here_unknown_flag_exits_nonzero

print_summary "test_help_and_flags"
