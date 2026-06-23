#!/usr/bin/env bash
# T2d — run_install_adapter has a reachable call site in the launch path (AC5, B2).
# Static checks that confirm the install step is not dead code.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

# ── Tests ─────────────────────────────────────────────────────────────────────

test_start_here_sources_adapter_sh() {
    # start-here.sh must source /start-here-lib/adapter.sh (the mounted helper).
    local _fail=0
    local _src="${REPO_ROOT}/start-here.sh"
    if ! grep -q 'start-here-lib/adapter.sh' "$_src" 2>/dev/null; then
        printf '    start-here.sh does not source /start-here-lib/adapter.sh\n' >&2
        _fail=1
    fi
    return $_fail
}

test_start_here_sources_common_sh() {
    # start-here.sh must source /start-here-lib/common.sh before adapter.sh.
    local _fail=0
    local _src="${REPO_ROOT}/start-here.sh"
    if ! grep -q 'start-here-lib/common.sh' "$_src" 2>/dev/null; then
        printf '    start-here.sh does not source /start-here-lib/common.sh\n' >&2
        _fail=1
    fi
    return $_fail
}

test_start_here_calls_run_install_adapter() {
    # run_install_adapter must be called (not just defined) in start-here.sh.
    local _fail=0
    local _src="${REPO_ROOT}/start-here.sh"
    if ! grep -q 'run_install_adapter' "$_src" 2>/dev/null; then
        printf '    start-here.sh does not call run_install_adapter\n' >&2
        _fail=1
    fi
    return $_fail
}

test_run_install_adapter_call_is_not_only_in_comment() {
    # Confirm the call is actual code, not just a comment.
    local _fail=0
    local _src="${REPO_ROOT}/start-here.sh"
    # Find lines with run_install_adapter that are not pure comments (# ...).
    local _non_comment_calls
    _non_comment_calls="$(grep 'run_install_adapter' "$_src" | grep -v '^\s*#' || true)"
    if [[ -z "$_non_comment_calls" ]]; then
        printf '    run_install_adapter only appears in comments; no live call site found\n' >&2
        _fail=1
    fi
    return $_fail
}

test_launch_sh_mounts_lib_for_install_helper() {
    # launch.sh must mount the plugin lib/ into the container so
    # start-here.sh can source adapter.sh at run time (B2, AC5).
    local _fail=0
    local _launch="${REPO_ROOT}/lib/launch.sh"
    if ! grep -q 'start-here-lib' "$_launch" 2>/dev/null; then
        printf '    lib/launch.sh does not mount /start-here-lib (adapter helper not exposed to container)\n' >&2
        _fail=1
    fi
    return $_fail
}

test_install_step_reachable_after_resolve_before_validate() {
    # The install step must be between _resolve_runtime and _validate_runtime in start-here.sh.
    local _fail=0
    local _src="${REPO_ROOT}/start-here.sh"

    local _resolve_line _install_line _validate_line
    _resolve_line="$(grep -n '_resolve_runtime$' "$_src" | head -1 | cut -d: -f1)"
    _install_line="$(grep -n '_install_runtime' "$_src" | grep -v '^\s*#\|^[[:space:]]*#\|function\|()' | head -1 | cut -d: -f1)"
    _validate_line="$(grep -n '_validate_runtime$' "$_src" | head -1 | cut -d: -f1)"

    if [[ -z "$_resolve_line" || -z "$_install_line" || -z "$_validate_line" ]]; then
        printf '    Could not find _resolve_runtime (%s), _install_runtime (%s), or _validate_runtime (%s) lines\n' \
            "$_resolve_line" "$_install_line" "$_validate_line" >&2
        _fail=1
    elif ! (( _resolve_line < _install_line && _install_line < _validate_line )); then
        printf '    _install_runtime call is not between _resolve_runtime and _validate_runtime\n' >&2
        printf '    resolve=%s install=%s validate=%s\n' "$_resolve_line" "$_install_line" "$_validate_line" >&2
        _fail=1
    fi
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "start-here.sh sources /start-here-lib/adapter.sh"           test_start_here_sources_adapter_sh
run_test "start-here.sh sources /start-here-lib/common.sh"            test_start_here_sources_common_sh
run_test "start-here.sh calls run_install_adapter"                     test_start_here_calls_run_install_adapter
run_test "run_install_adapter call is live code, not just a comment"   test_run_install_adapter_call_is_not_only_in_comment
run_test "launch.sh mounts lib/ as /start-here-lib in container"       test_launch_sh_mounts_lib_for_install_helper
run_test "_install_runtime called between _resolve and _validate"      test_install_step_reachable_after_resolve_before_validate

print_summary "test_no_dead_install_code"
