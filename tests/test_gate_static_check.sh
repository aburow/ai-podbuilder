#!/usr/bin/env bash
# T9 — Static check is advisory: skip when no tool; failure alone doesn't fail gate (AC12).
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

# ── Helpers ───────────────────────────────────────────────────────────────────

_gate_helper() {
    local _script="$1"
    cat > "${_TMPDIR}/static_helper.sh" <<SCRIPT
#!/usr/bin/env bash
set -uo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/quality_gate.sh'
export AI_PODMAN_JAILS_DIR='${_TMPDIR}'
export SLUG='testslug'
${_script}
SCRIPT
    # Run with a PATH that has no hadolint (static check tool).
    PATH="${STUBS_DIR}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
        bash "${_TMPDIR}/static_helper.sh" 2>&1
}

# ── Tests ─────────────────────────────────────────────────────────────────────

test_static_check_skipped_when_no_tool() {
    local _fail=0
    local _cfile="${_TMPDIR}/Containerfile"
    local _log="${_TMPDIR}/static.log"
    printf 'FROM fedora:latest\nRUN echo hi\n' > "$_cfile"

    local out rc=0
    out="$(_gate_helper "
        # Remove hadolint from PATH by not including it.
        static_check '${_cfile}' '${_log}' || true
        printf 'STATUS=%s\n' \"\$STATIC_CHECK_STATUS\"
    ")" || rc=$?
    assert_success $rc || _fail=1
    # With no hadolint and no podman dry-run (stub), status should be skipped.
    # (The stub podman's dry-run doesn't actually work but exits 0, so it might pass.)
    assert_contains "STATUS=" "$out" || _fail=1
    # Either skipped or passed is acceptable when no real tool is available.
    local _status
    _status="$(echo "$out" | grep 'STATUS=' | cut -d= -f2)"
    case "$_status" in
        skipped|passed) ;;
        *)
            printf '    Unexpected static_check status: %s\n' "$_status" >&2
            _fail=1 ;;
    esac
    return $_fail
}

test_map_gate_status_static_fail_plus_build_fail_is_quality_gate_failed() {
    local _fail=0
    local out rc=0
    out="$(_gate_helper "
        map_gate_status 1 1 0
        printf 'GATE=%s\n' \"\$GATE_STATUS\"
    ")" || rc=$?
    assert_success $rc || _fail=1
    assert_contains "GATE=quality-gate-failed" "$out" \
        "static+build fail → quality-gate-failed" || _fail=1
    return $_fail
}

test_map_gate_status_static_fail_build_pass_is_complete() {
    local _fail=0
    local out rc=0
    out="$(_gate_helper "
        map_gate_status 1 0 0
        printf 'GATE=%s\n' \"\$GATE_STATUS\"
    ")" || rc=$?
    assert_success $rc || _fail=1
    # Static failure alone does NOT fail the gate; build_rc=0 → complete.
    assert_contains "GATE=complete" "$out" \
        "static fail + build pass → complete (static is advisory)" || _fail=1
    return $_fail
}

test_map_gate_status_timeout_is_quality_gate_timeout() {
    local _fail=0
    local out rc=0
    out="$(_gate_helper "
        map_gate_status 0 2 0
        printf 'GATE=%s\n' \"\$GATE_STATUS\"
    ")" || rc=$?
    assert_success $rc || _fail=1
    assert_contains "GATE=quality-gate-timeout" "$out" \
        "build_rc=2 (timeout) → quality-gate-timeout" || _fail=1
    return $_fail
}

test_map_gate_status_build_pass_is_complete() {
    local _fail=0
    local out rc=0
    out="$(_gate_helper "
        map_gate_status 0 0 0
        printf 'GATE=%s\n' \"\$GATE_STATUS\"
    ")" || rc=$?
    assert_success $rc || _fail=1
    assert_contains "GATE=complete" "$out" "build pass → complete" || _fail=1
    return $_fail
}

test_map_gate_status_build_fail_is_quality_gate_failed() {
    local _fail=0
    local out rc=0
    out="$(_gate_helper "
        map_gate_status 0 1 0
        printf 'GATE=%s\n' \"\$GATE_STATUS\"
    ")" || rc=$?
    assert_success $rc || _fail=1
    assert_contains "GATE=quality-gate-failed" "$out" "build fail → quality-gate-failed" || _fail=1
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "static_check: skipped or passed when no tool available" test_static_check_skipped_when_no_tool
run_test "map_gate_status: static+build fail → quality-gate-failed" test_map_gate_status_static_fail_plus_build_fail_is_quality_gate_failed
run_test "map_gate_status: static fail + build pass → complete (advisory)" test_map_gate_status_static_fail_build_pass_is_complete
run_test "map_gate_status: build timeout → quality-gate-timeout"    test_map_gate_status_timeout_is_quality_gate_timeout
run_test "map_gate_status: build pass → complete"                  test_map_gate_status_build_pass_is_complete
run_test "map_gate_status: build fail → quality-gate-failed"       test_map_gate_status_build_fail_is_quality_gate_failed

print_summary "test_gate_static_check"
