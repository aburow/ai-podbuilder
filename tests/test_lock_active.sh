#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# 2026 - Anthony Burow - https://github.com/aburow
# T11 — Active lock refusal with details (AC24, R19).
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

# ── Helpers ───────────────────────────────────────────────────────────────────

_lock_helper() {
    local _script="$1"
    cat > "${_TMPDIR}/lock_helper.sh" <<SCRIPT
#!/usr/bin/env bash
set -uo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/lock.sh'
export AI_PODMAN_JAILS_DIR='${_TMPDIR}'
export SLUG='testslug'
${_script}
SCRIPT
    bash "${_TMPDIR}/lock_helper.sh" 2>&1
}

_make_proj() {
    local _name="$1"
    local _root="${_TMPDIR}/projects/${_name}"
    mkdir -p "${_root}/bootstrap"
    echo "$_root"
}

_write_active_lock_info() {
    local _proj="$1"
    local _pid="${2:-$$}"
    local _lock_dir="${_proj}/bootstrap/session.lock"
    mkdir -p "$_lock_dir"
    local _now
    _now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    cat > "${_lock_dir}/info.json" <<EOF
{
  "pid": ${_pid},
  "hostname": "testhost",
  "container_name": "ai-new-bootstrap-testslug",
  "started_at": "${_now}",
  "last_heartbeat": "${_now}"
}
EOF
}

# ── Tests ─────────────────────────────────────────────────────────────────────

test_acquire_lock_creates_lock_dir() {
    local _fail=0
    local _proj
    _proj="$(_make_proj "lock1")"

    local out rc=0
    out="$(_lock_helper "
        acquire_lock '${_proj}'
        echo ACQUIRED
        release_lock '${_proj}'
    ")" || rc=$?
    assert_success $rc "acquire_lock should succeed on fresh project" || _fail=1
    assert_contains "ACQUIRED" "$out" || _fail=1
    return $_fail
}

test_acquire_lock_twice_fails_on_second() {
    local _fail=0
    local _proj
    _proj="$(_make_proj "lock2")"
    # Create a live lock manually (using the current PID so it appears active).
    _write_active_lock_info "$_proj" "$$"

    # The stub podman inspect returns 1 (no container), so the container check fails.
    # But the PID is alive (it's $$), so lock_is_stale returns 1 (not stale).
    # acquire_lock should fail with "locked by" message.
    local out rc=0
    out="$(_lock_helper "
        (acquire_lock '${_proj}') 2>&1 || true
        echo ATTEMPTED
    ")" || rc=$?
    assert_contains "ATTEMPTED" "$out" || _fail=1
    assert_contains "locked" "$out" "second acquire should report locked" || _fail=1
    return $_fail
}

test_release_lock_removes_lock_dir() {
    local _fail=0
    local _proj
    _proj="$(_make_proj "lock3")"
    local out rc=0
    out="$(_lock_helper "
        acquire_lock '${_proj}'
        release_lock '${_proj}'
        [[ ! -d '${_proj}/bootstrap/session.lock' ]] && echo RELEASED || echo STILL_LOCKED
    ")" || rc=$?
    assert_success $rc || _fail=1
    assert_contains "RELEASED" "$out" "lock dir should be removed after release" || _fail=1
    return $_fail
}

test_lock_is_active_returns_true_for_live_lock() {
    local _fail=0
    local _proj
    _proj="$(_make_proj "lock4")"
    _write_active_lock_info "$_proj" "$$"  # use live PID

    local out rc=0
    out="$(_lock_helper "
        lock_is_active '${_proj}' && echo ACTIVE || echo INACTIVE
    ")" || rc=$?
    assert_success $rc || _fail=1
    assert_contains "ACTIVE" "$out" "live lock should be active" || _fail=1
    return $_fail
}

test_lock_is_active_returns_false_without_lock_dir() {
    local _fail=0
    local _proj
    _proj="$(_make_proj "lock5")"
    # No lock dir.

    local out rc=0
    out="$(_lock_helper "
        lock_is_active '${_proj}' && echo ACTIVE || echo INACTIVE
    ")" || rc=$?
    assert_success $rc || _fail=1
    assert_contains "INACTIVE" "$out" "no lock dir → inactive" || _fail=1
    return $_fail
}

test_lock_info_written_with_pid_hostname() {
    local _fail=0
    local _proj
    _proj="$(_make_proj "lock6")"

    local out rc=0
    out="$(_lock_helper "
        acquire_lock '${_proj}'
        cat '${_proj}/bootstrap/session.lock/info.json'
        release_lock '${_proj}'
    ")" || rc=$?
    assert_success $rc || _fail=1
    assert_contains '"pid"' "$out" "lock info should have pid field" || _fail=1
    assert_contains '"hostname"' "$out" "lock info should have hostname field" || _fail=1
    assert_contains '"container_name"' "$out" "lock info should have container_name" || _fail=1
    assert_contains '"started_at"' "$out" "lock info should have started_at" || _fail=1
    assert_contains '"last_heartbeat"' "$out" "lock info should have last_heartbeat" || _fail=1
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "acquire_lock creates lock dir and succeeds"      test_acquire_lock_creates_lock_dir
run_test "second acquire_lock fails with 'locked' message" test_acquire_lock_twice_fails_on_second
run_test "release_lock removes lock dir"                   test_release_lock_removes_lock_dir
run_test "lock_is_active: true for live lock"              test_lock_is_active_returns_true_for_live_lock
run_test "lock_is_active: false without lock dir"          test_lock_is_active_returns_false_without_lock_dir
run_test "lock info.json has all required fields"          test_lock_info_written_with_pid_hostname

print_summary "test_lock_active"
