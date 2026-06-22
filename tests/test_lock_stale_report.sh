#!/usr/bin/env bash
# T11 — Stale lock detection; report with safe clear path; non-interactive fails closed (AC24, D3).
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

# ── Helpers ───────────────────────────────────────────────────────────────────

_lock_helper() {
    local _script="$1"
    cat > "${_TMPDIR}/stale_lock_helper.sh" <<SCRIPT
#!/usr/bin/env bash
set -uo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/lock.sh'
export CODEX_JAILS_DIR='${_TMPDIR}'
export SLUG='testslug'
export AI_NEW_LOCK_STALE_AFTER=10s
${_script}
SCRIPT
    bash "${_TMPDIR}/stale_lock_helper.sh" 2>&1
}

_make_proj() {
    local _name="$1"
    local _root="${_TMPDIR}/projects/${_name}"
    mkdir -p "${_root}/bootstrap"
    echo "$_root"
}

_write_stale_lock_info() {
    local _proj="$1"
    local _lock_dir="${_proj}/bootstrap/session.lock"
    mkdir -p "$_lock_dir"
    # Use PID 1 (always dead in this context) and an old heartbeat.
    cat > "${_lock_dir}/info.json" <<'EOF'
{
  "pid": 99999999,
  "hostname": "stalehost",
  "container_name": "ai-new-bootstrap-stale",
  "started_at": "2000-01-01T00:00:00Z",
  "last_heartbeat": "2000-01-01T00:00:00Z"
}
EOF
}

# ── Tests ─────────────────────────────────────────────────────────────────────

test_lock_is_stale_returns_true_for_dead_pid_old_heartbeat() {
    local _fail=0
    local _proj
    _proj="$(_make_proj "stale1")"
    _write_stale_lock_info "$_proj"

    local out rc=0
    out="$(_lock_helper "
        lock_is_stale '${_proj}' && echo STALE || echo LIVE
    ")" || rc=$?
    assert_success $rc || _fail=1
    assert_contains "STALE" "$out" "dead pid + old heartbeat → stale" || _fail=1
    return $_fail
}

test_lock_is_stale_returns_false_without_lock_dir() {
    local _fail=0
    local _proj
    _proj="$(_make_proj "stale2")"

    local out rc=0
    out="$(_lock_helper "
        lock_is_stale '${_proj}' && echo STALE || echo LIVE
    ")" || rc=$?
    assert_success $rc || _fail=1
    # No lock dir → not stale (doesn't exist at all).
    assert_contains "LIVE" "$out" "no lock dir → not stale" || _fail=1
    return $_fail
}

test_lock_is_stale_returns_true_for_no_info_file() {
    local _fail=0
    local _proj
    _proj="$(_make_proj "stale3")"
    # Create lock dir but no info.json.
    mkdir -p "${_proj}/bootstrap/session.lock"

    local out rc=0
    out="$(_lock_helper "
        lock_is_stale '${_proj}' && echo STALE || echo LIVE
    ")" || rc=$?
    assert_success $rc || _fail=1
    assert_contains "STALE" "$out" "lock dir with no info.json → stale" || _fail=1
    return $_fail
}

test_report_stale_lock_prints_details() {
    local _fail=0
    local _proj
    _proj="$(_make_proj "stale4")"
    _write_stale_lock_info "$_proj"

    local out rc=0
    out="$(_lock_helper "
        report_stale_lock '${_proj}' 99999999 stalehost ai-new-bootstrap-stale \
            '2000-01-01T00:00:00Z' '2000-01-01T00:00:00Z'
    ")" || rc=$?
    assert_success $rc || _fail=1
    assert_contains "99999999" "$out" "report should include pid" || _fail=1
    assert_contains "stalehost" "$out" "report should include hostname" || _fail=1
    assert_contains "rm -rf" "$out" "report should include manual clear command" || _fail=1
    assert_contains "session.lock" "$out" "report should include lock dir path" || _fail=1
    return $_fail
}

test_acquire_lock_stale_noninteractive_fails_closed() {
    local _fail=0
    local _proj
    _proj="$(_make_proj "stale5")"
    _write_stale_lock_info "$_proj"

    # Non-interactive: stdin is not a TTY; acquire_lock should refuse without clearing.
    local out rc=0
    out="$(_lock_helper "
        # Force non-interactive by redirecting stdin.
        (acquire_lock '${_proj}' < /dev/null) 2>&1 || true
        echo ATTEMPTED
    ")" || rc=$?
    assert_contains "ATTEMPTED" "$out" || _fail=1
    assert_contains "Non-interactive" "$out" "non-interactive should mention non-interactive" || _fail=1
    return $_fail
}

test_acquire_stale_lock_shows_manual_clear_command() {
    local _fail=0
    local _proj
    _proj="$(_make_proj "stale6")"
    _write_stale_lock_info "$_proj"

    local out rc=0
    out="$(_lock_helper "
        acquire_lock '${_proj}' < /dev/null || true
    ")" || rc=$?
    assert_contains "rm -rf" "$out" "stale lock error should show manual clear command" || _fail=1
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "lock_is_stale: true for dead pid + old heartbeat"      test_lock_is_stale_returns_true_for_dead_pid_old_heartbeat
run_test "lock_is_stale: false without lock dir"                 test_lock_is_stale_returns_false_without_lock_dir
run_test "lock_is_stale: true when no info.json"                 test_lock_is_stale_returns_true_for_no_info_file
run_test "report_stale_lock prints pid, hostname, rm command"    test_report_stale_lock_prints_details
run_test "non-interactive stale lock: fails closed"             test_acquire_lock_stale_noninteractive_fails_closed
run_test "stale lock error includes manual rm -rf command"       test_acquire_stale_lock_shows_manual_clear_command

print_summary "test_lock_stale_report"
