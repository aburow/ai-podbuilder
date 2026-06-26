#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# 2026 - Anthony Burow - https://github.com/aburow
# T8 — Coordination protocol: request_id allocation and rejection (R8.7–R8.13, AC27).
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

# ── Helpers ───────────────────────────────────────────────────────────────────

_coord_helper() {
    local _script="$1"
    cat > "${_TMPDIR}/coord_helper.sh" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/session.sh'
source '${LIB_DIR}/coordination.sh'
export AI_PODMAN_JAILS_DIR='${_TMPDIR}'
${_script}
SCRIPT
    bash "${_TMPDIR}/coord_helper.sh" 2>&1
}

_make_proj() {
    local _name="$1"
    local _root="${_TMPDIR}/projects/${_name}"
    mkdir -p "${_root}/bootstrap"
    cat > "${_root}/bootstrap/session.json" <<EOF
{
  "project_name": "${_name}",
  "selected_agent": "codex",
  "status": "started",
  "last_updated": "2026-01-01T00:00:00Z",
  "generated_files": [],
  "last_request_id": 0
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
  "reason": "initial",
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
  "status": "complete"
}
EOF
}

# ── Tests ─────────────────────────────────────────────────────────────────────

test_next_id_starts_at_one_for_empty_dir() {
    local _fail=0
    local _proj
    _proj="$(_make_proj "idtest1")"
    local out rc=0
    out="$(_coord_helper "next_request_id '${_proj}'")" || rc=$?
    assert_success $rc "next_request_id should succeed" || _fail=1
    assert_eq "1" "$out" "first id should be 1" || _fail=1
    return $_fail
}

test_next_id_increments_beyond_existing_requests() {
    local _fail=0
    local _proj
    _proj="$(_make_proj "idtest2")"
    _write_request "$_proj" 3

    local out rc=0
    out="$(_coord_helper "next_request_id '${_proj}'")" || rc=$?
    assert_success $rc || _fail=1
    assert_eq "4" "$out" "next id should be max(existing)+1" || _fail=1
    return $_fail
}

test_next_id_increments_beyond_existing_results() {
    local _fail=0
    local _proj
    _proj="$(_make_proj "idtest3")"
    _write_request "$_proj" 2
    _write_result  "$_proj" 2

    local out rc=0
    out="$(_coord_helper "next_request_id '${_proj}'")" || rc=$?
    assert_success $rc || _fail=1
    assert_eq "3" "$out" "next id should be max(results)+1" || _fail=1
    return $_fail
}

test_next_id_uses_session_json_last_request_id() {
    local _fail=0
    local _proj
    _proj="$(_make_proj "idtest4")"
    # Manually set last_request_id in session.json.
    python3 - "${_proj}/bootstrap/session.json" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
d['last_request_id'] = 7
with open(sys.argv[1], 'w') as f:
    json.dump(d, f)
PYEOF

    local out rc=0
    out="$(_coord_helper "next_request_id '${_proj}'")" || rc=$?
    assert_success $rc || _fail=1
    assert_eq "8" "$out" "next id should exceed session.json last_request_id" || _fail=1
    return $_fail
}

test_validate_request_rejects_stale_id() {
    local _fail=0
    local _proj
    _proj="$(_make_proj "idtest5")"
    # Create a result for id=2 (so last completed = 2).
    _write_result "$_proj" 2
    # Now write a request with id=1 (stale).
    _write_request "$_proj" 1

    local out rc=0
    out="$(_coord_helper "
        validate_request '${_proj}' '${_proj}/bootstrap/build.request.1.json' || echo REJECTED
    ")" || rc=$?
    assert_contains "REJECTED" "$out" "stale id should be rejected" || _fail=1
    return $_fail
}

test_validate_request_rejects_tmp_files() {
    local _fail=0
    local _proj
    _proj="$(_make_proj "idtest6")"
    # Write a .tmp file.
    touch "${_proj}/bootstrap/build.request.5.json.tmp"

    local out rc=0
    out="$(_coord_helper "
        validate_request '${_proj}' '${_proj}/bootstrap/build.request.5.json.tmp' || echo REJECTED
    ")" || rc=$?
    assert_contains "REJECTED" "$out" ".tmp file should be rejected" || _fail=1
    return $_fail
}

test_validate_request_accepts_valid_request() {
    local _fail=0
    local _proj
    _proj="$(_make_proj "idtest7")"
    mkdir -p "${_proj}/image"
    touch "${_proj}/image/Containerfile"
    _write_request "$_proj" 1

    local out rc=0
    out="$(_coord_helper "
        validate_request '${_proj}' '${_proj}/bootstrap/build.request.1.json' && echo ACCEPTED || echo REJECTED
    ")" || rc=$?
    assert_contains "ACCEPTED" "$out" "valid request should be accepted" || _fail=1
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "next_request_id starts at 1 for empty dir"           test_next_id_starts_at_one_for_empty_dir
run_test "next_request_id increments beyond existing requests"  test_next_id_increments_beyond_existing_requests
run_test "next_request_id increments beyond existing results"   test_next_id_increments_beyond_existing_results
run_test "next_request_id uses session.json last_request_id"   test_next_id_uses_session_json_last_request_id
run_test "validate_request rejects stale id (≤ last completed)" test_validate_request_rejects_stale_id
run_test "validate_request rejects .tmp files"                 test_validate_request_rejects_tmp_files
run_test "validate_request accepts valid request"              test_validate_request_accepts_valid_request

print_summary "test_coordination_ids"
