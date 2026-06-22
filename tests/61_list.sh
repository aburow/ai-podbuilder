#!/usr/bin/env bash
# T7b — ai-list: aligned listing with state column; missing dir exits non-zero (AC11).
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

test_ai_list_prints_profiles() {
    local _fail=0
    local out rc=0
    out="$(CODEX_JAILS_DIR="$_TMPDIR" PATH="${STUBS_DIR}:${PATH}" \
        "${BIN_DIR}/ai-list" 2>/dev/null)" || rc=$?
    assert_success $rc "ai-list should exit 0 when profiles exist" || _fail=1
    assert_contains "PROFILE"   "$out" "header row present" || _fail=1
    assert_contains "IMAGE"     "$out" "IMAGE column present" || _fail=1
    assert_contains "WORKSPACE" "$out" "WORKSPACE column present" || _fail=1
    assert_contains "STATE"     "$out" "STATE column present" || _fail=1
    # Reference profiles seeded by setup
    assert_contains "esp32"  "$out" "esp32 profile listed" || _fail=1
    assert_contains "uxplay" "$out" "uxplay profile listed" || _fail=1
    return $_fail
}

test_ai_list_state_column_absent() {
    # Without live podman the stub returns non-zero for container exists,
    # so all profiles should show "absent".
    local _fail=0
    local out
    out="$(CODEX_JAILS_DIR="$_TMPDIR" PATH="${STUBS_DIR}:${PATH}" \
        "${BIN_DIR}/ai-list" 2>/dev/null)"
    assert_contains "absent" "$out" "state column shows absent when no containers" || _fail=1
    return $_fail
}

test_ai_list_column_alignment() {
    local _fail=0
    local out
    out="$(CODEX_JAILS_DIR="$_TMPDIR" PATH="${STUBS_DIR}:${PATH}" \
        "${BIN_DIR}/ai-list" 2>/dev/null)"
    # All data rows must have the same number of fields (columns) as the header.
    # Count fields in the header (space-separated columns delimited by 2+ spaces).
    local header_cols data_cols
    header_cols="$(echo "$out" | head -1 | awk '{print NF}')"
    # Every data row (skip header and separator) must have same field count
    local bad_rows=0
    while IFS= read -r line; do
        [[ -z "$line" || "$line" == ---* ]] && continue
        data_cols="$(echo "$line" | awk '{print NF}')"
        [[ "$data_cols" -ge "$header_cols" ]] || (( bad_rows++ )) || true
    done <<< "$(echo "$out" | tail -n +3)"
    [[ $bad_rows -eq 0 ]] \
        || { printf '    %d rows had fewer columns than header\n' "$bad_rows" >&2; _fail=1; }
    return $_fail
}

test_ai_list_no_ansi_when_piped() {
    # ai-list must not emit ANSI escape codes (output goes to stdout, not a TTY here).
    local _fail=0
    local out
    out="$(CODEX_JAILS_DIR="$_TMPDIR" PATH="${STUBS_DIR}:${PATH}" \
        "${BIN_DIR}/ai-list" 2>/dev/null)"
    if printf '%s' "$out" | grep -qP '\x1b\['; then
        echo "    ANSI escape codes found in piped output" >&2
        _fail=1
    fi
    return $_fail
}

test_ai_list_missing_profiles_dir_exits_nonzero() {
    local _fail=0
    # Point to a dir that has no profiles/ subdirectory
    local empty_dir="${_TMPDIR}/empty_root"
    mkdir -p "$empty_dir"
    local rc=0
    CODEX_JAILS_DIR="$empty_dir" PATH="${STUBS_DIR}:${PATH}" \
        "${BIN_DIR}/ai-list" >/dev/null 2>&1 || rc=$?
    assert_failure $rc "missing profiles dir → non-zero" || _fail=1
    return $_fail
}

test_ai_list_help_exits_zero() {
    local _fail=0
    local rc=0
    "${BIN_DIR}/ai-list" --help 2>/dev/null || rc=$?
    assert_success $rc "--help exits 0" || _fail=1
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "ai-list prints profile name, image, workspace, state"   test_ai_list_prints_profiles
run_test "ai-list state column shows 'absent' with stub podman"   test_ai_list_state_column_absent
run_test "ai-list column alignment consistent across rows"         test_ai_list_column_alignment
run_test "ai-list emits no ANSI when piped"                       test_ai_list_no_ansi_when_piped
run_test "ai-list: missing profiles dir → non-zero"               test_ai_list_missing_profiles_dir_exits_nonzero
run_test "ai-list --help exits 0"                                  test_ai_list_help_exits_zero

print_summary "61_list"
