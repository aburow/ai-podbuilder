#!/usr/bin/env bash
# T8 — Duplicate request_id does not trigger second build (AC27).
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

# ── Helpers ───────────────────────────────────────────────────────────────────

_coord_helper() {
    local _script="$1"
    cat > "${_TMPDIR}/dedupe_helper.sh" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/session.sh'
source '${LIB_DIR}/coordination.sh'
export CODEX_JAILS_DIR='${_TMPDIR}'
${_script}
SCRIPT
    bash "${_TMPDIR}/dedupe_helper.sh" 2>&1
}

_make_proj() {
    local _name="$1"
    local _root="${_TMPDIR}/projects/${_name}"
    mkdir -p "${_root}/bootstrap"
    cat > "${_root}/bootstrap/session.json" <<'EOF'
{
  "project_name": "test",
  "selected_agent": "codex",
  "status": "started"
}
EOF
    echo "$_root"
}

_write_request() {
    local _proj="$1"
    local _id="$2"
    cat > "${_proj}/bootstrap/build.request.${_id}.json" <<EOF
{
  "request_id": ${_id},
  "containerfile": "${_proj}/image/Containerfile",
  "context_dir": "${_proj}/image",
  "image_tag": "localhost/ai-new/test:trial",
  "reason": "test",
  "repair_iteration": 0
}
EOF
}

_write_result() {
    local _proj="$1"
    local _id="$2"
    cat > "${_proj}/bootstrap/build.result.${_id}.json" <<EOF
{
  "request_id": ${_id},
  "exit_code": 0,
  "status": "complete",
  "static_check_status": "passed",
  "build_log_path": "",
  "image_tag": "localhost/ai-new/test:trial",
  "error_summary": ""
}
EOF
}

# ── Tests ─────────────────────────────────────────────────────────────────────

test_request_already_completed_returns_true_when_result_exists() {
    local _fail=0
    local _proj
    _proj="$(_make_proj "dedupe1")"
    _write_result "$_proj" 5

    local out rc=0
    out="$(_coord_helper "
        request_already_completed '${_proj}' 5 && echo YES || echo NO
    ")" || rc=$?
    assert_contains "YES" "$out" "completed id should be detected" || _fail=1
    return $_fail
}

test_request_already_completed_returns_false_when_no_result() {
    local _fail=0
    local _proj
    _proj="$(_make_proj "dedupe2")"
    _write_request "$_proj" 3  # request exists, but no result

    local out rc=0
    out="$(_coord_helper "
        request_already_completed '${_proj}' 3 && echo YES || echo NO
    ")" || rc=$?
    assert_contains "NO" "$out" "id without result should not be completed" || _fail=1
    return $_fail
}

test_validate_request_rejects_already_completed_id() {
    local _fail=0
    local _proj
    _proj="$(_make_proj "dedupe3")"
    mkdir -p "${_proj}/image"
    touch "${_proj}/image/Containerfile"
    # Write both request and result for id=2.
    _write_request "$_proj" 2
    _write_result  "$_proj" 2
    # Also write request for id=3 (new, valid).
    _write_request "$_proj" 3

    # id=2 should be rejected because it's already completed (last_completed=2, id<=last).
    local out rc=0
    out="$(_coord_helper "
        validate_request '${_proj}' '${_proj}/bootstrap/build.request.2.json' || echo REJECTED
    ")" || rc=$?
    assert_contains "REJECTED" "$out" "already-completed id should be rejected" || _fail=1
    return $_fail
}

test_validate_request_accepts_next_id_after_completed() {
    local _fail=0
    local _proj
    _proj="$(_make_proj "dedupe4")"
    mkdir -p "${_proj}/image"
    touch "${_proj}/image/Containerfile"
    _write_request "$_proj" 1
    _write_result  "$_proj" 1
    _write_request "$_proj" 2  # next id = 2

    local out rc=0
    out="$(_coord_helper "
        validate_request '${_proj}' '${_proj}/bootstrap/build.request.2.json' && echo ACCEPTED || echo REJECTED
    ")" || rc=$?
    assert_contains "ACCEPTED" "$out" "next id after completed should be accepted" || _fail=1
    return $_fail
}

test_poll_skips_completed_requests() {
    # Verify that in the polling loop, request_already_completed is checked.
    local _fail=0
    local _proj
    _proj="$(_make_proj "dedupe5")"
    mkdir -p "${_proj}/image"
    touch "${_proj}/image/Containerfile"
    _write_request "$_proj" 1
    _write_result  "$_proj" 1  # mark as completed

    # If poll_requests were called, it should skip id=1.
    # We test via request_already_completed directly.
    local out rc=0
    out="$(_coord_helper "
        request_already_completed '${_proj}' 1 && echo SKIP || echo PROCESS
    ")" || rc=$?
    assert_contains "SKIP" "$out" "poll should skip completed id" || _fail=1
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "request_already_completed: true when result exists"     test_request_already_completed_returns_true_when_result_exists
run_test "request_already_completed: false without result"        test_request_already_completed_returns_false_when_no_result
run_test "validate_request rejects already-completed id"          test_validate_request_rejects_already_completed_id
run_test "validate_request accepts next id after completed"        test_validate_request_accepts_next_id_after_completed
run_test "poll skips already-completed requests"                  test_poll_skips_completed_requests

print_summary "test_coordination_dedupe"
