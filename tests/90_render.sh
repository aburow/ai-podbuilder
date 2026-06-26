#!/usr/bin/env bash
# T10 — User-surface rendering: banner (F2), stale prompt (F3), help text (F1).
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

# ── Help text (F1): every command exits 0 on -h ───────────────────────────────

test_ai_launch_help_exits_zero() {
    local _fail=0
    local rc=0
    "${BIN_DIR}/ai-launch" --help 2>/dev/null || rc=$?
    assert_success $rc "ai-launch --help exits 0" || _fail=1
    return $_fail
}

test_ai_launch_help_lists_modes() {
    local _fail=0
    local out
    out="$("${BIN_DIR}/ai-launch" --help 2>&1)"
    assert_contains "codex"   "$out" "help lists codex mode"   || _fail=1
    assert_contains "codex"  "$out" "help lists codex mode"  || _fail=1
    assert_contains "builder" "$out" "help lists builder mode" || _fail=1
    assert_contains "--reset" "$out" "help lists --reset flag" || _fail=1
    return $_fail
}

test_ai_build_help_exits_zero() {
    local _fail=0
    local rc=0
    "${BIN_DIR}/ai-build" --help 2>/dev/null || rc=$?
    assert_success $rc "ai-build --help exits 0" || _fail=1
    local out
    out="$("${BIN_DIR}/ai-build" --help 2>&1)"
    assert_contains "--edit" "$out" "ai-build help should mention edit mode" || _fail=1
    return $_fail
}

test_ai_list_help_exits_zero_render() {
    local _fail=0
    local rc=0
    "${BIN_DIR}/ai-list" --help 2>/dev/null || rc=$?
    assert_success $rc "ai-list --help exits 0" || _fail=1
    return $_fail
}

test_ai_terminal_help_exits_zero_render() {
    local _fail=0
    local rc=0
    "${BIN_DIR}/ai-terminal" --help 2>/dev/null || rc=$?
    assert_success $rc "ai-terminal --help exits 0" || _fail=1
    return $_fail
}

# ── Pre-launch banner (F2): R4.8 required fields ─────────────────────────────

test_banner_contains_all_r48_fields() {
    # Capture the banner from render_launch_summary directly.
    local _fail=0
    local out
    out="$(CODEX_JAILS_DIR="$_TMPDIR" bash -c "
        export CODEX_JAILS_DIR='${_TMPDIR}'
        source '${LIB_DIR}/common.sh'
        source '${LIB_DIR}/profile.sh'
        source '${LIB_DIR}/render.sh'
        resolve_base_dir
        load_profile esp32
        _LAUNCH_MODE=shell
        render_launch_summary no
    " 2>&1)"
    assert_contains "Profile"    "$out" "banner: Profile field"    || _fail=1
    assert_contains "Container"  "$out" "banner: Container field"  || _fail=1
    assert_contains "Image"      "$out" "banner: Image field"      || _fail=1
    assert_contains "Workspace"  "$out" "banner: Workspace field"  || _fail=1
    assert_contains "Mode"       "$out" "banner: Mode field"       || _fail=1
    assert_contains "Network"    "$out" "banner: Network field"    || _fail=1
    assert_contains "SELinux"    "$out" "banner: SELinux field"    || _fail=1
    assert_contains "Reusing"    "$out" "banner: Reusing field"    || _fail=1
    return $_fail
}

test_banner_flags_builder_as_privileged() {
    local _fail=0
    local out
    out="$(CODEX_JAILS_DIR="$_TMPDIR" bash -c "
        export CODEX_JAILS_DIR='${_TMPDIR}'
        source '${LIB_DIR}/common.sh'
        source '${LIB_DIR}/profile.sh'
        source '${LIB_DIR}/render.sh'
        resolve_base_dir
        load_profile esp32
        _LAUNCH_MODE=builder
        render_launch_summary no
    " 2>&1)"
    assert_contains "PRIVILEGED" "$out" "builder banner flags PRIVILEGED" || _fail=1
    assert_contains "EPHEMERAL"  "$out" "builder banner flags EPHEMERAL"  || _fail=1
    return $_fail
}

# ── Stale prompt (F3): three labelled choices, empty → continue ───────────────

test_stale_prompt_shows_three_choices() {
    local _fail=0
    local out
    out="$(CODEX_JAILS_DIR="$_TMPDIR" bash -c "
        export CODEX_JAILS_DIR='${_TMPDIR}'
        source '${LIB_DIR}/common.sh'
        source '${LIB_DIR}/profile.sh'
        source '${LIB_DIR}/render.sh'
        resolve_base_dir
        load_profile esp32
        CONTAINER_NAME='codex-esp32'
        # Pipe empty input so prompt_stale_choice gets default
        printf '' | prompt_stale_choice
    " 2>&1)"
    assert_contains "Continue"  "$out" "stale prompt: Continue choice"  || _fail=1
    assert_contains "Recreate"  "$out" "stale prompt: Recreate choice"  || _fail=1
    assert_contains "Cancel"    "$out" "stale prompt: Cancel choice"    || _fail=1
    return $_fail
}

test_stale_prompt_empty_input_returns_continue() {
    local _fail=0
    local result
    result="$(CODEX_JAILS_DIR="$_TMPDIR" bash -c "
        export CODEX_JAILS_DIR='${_TMPDIR}'
        source '${LIB_DIR}/common.sh'
        source '${LIB_DIR}/profile.sh'
        source '${LIB_DIR}/render.sh'
        resolve_base_dir
        load_profile esp32
        CONTAINER_NAME='codex-esp32'
        printf '\n' | prompt_stale_choice
    " 2>/dev/null)"
    assert_eq "continue" "$result" "empty input → continue" || _fail=1
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "ai-launch --help exits 0"                           test_ai_launch_help_exits_zero
run_test "ai-launch --help lists modes and flags"             test_ai_launch_help_lists_modes
run_test "ai-build --help exits 0"                            test_ai_build_help_exits_zero
run_test "ai-list --help exits 0"                             test_ai_list_help_exits_zero_render
run_test "ai-terminal --help exits 0"                         test_ai_terminal_help_exits_zero_render
run_test "launch banner contains all R4.8 fields"             test_banner_contains_all_r48_fields
run_test "builder banner flags PRIVILEGED and EPHEMERAL"      test_banner_flags_builder_as_privileged
run_test "stale prompt shows three labelled choices"          test_stale_prompt_shows_three_choices
run_test "stale prompt: empty input defaults to continue"     test_stale_prompt_empty_input_returns_continue

print_summary "90_render"
