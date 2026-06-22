#!/usr/bin/env bash
# T8 — Coordination atomicity: .tmp+rename, malformed requests rejected (AC27).
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

# ── Helpers ───────────────────────────────────────────────────────────────────

_coord_helper() {
    local _script="$1"
    cat > "${_TMPDIR}/atom_helper.sh" <<SCRIPT
#!/usr/bin/env bash
set -uo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/session.sh'
source '${LIB_DIR}/coordination.sh'
export CODEX_JAILS_DIR='${_TMPDIR}'
${_script}
SCRIPT
    bash "${_TMPDIR}/atom_helper.sh" 2>&1
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
  "last_updated": "2026-01-01T00:00:00Z"
}
EOF
    echo "$_root"
}

# ── Tests ─────────────────────────────────────────────────────────────────────

test_write_result_atomic_rename() {
    local _fail=0
    local _proj
    _proj="$(_make_proj "atom1")"
    local out rc=0
    out="$(_coord_helper "
        write_result '${_proj}' 1 0 'complete' 'passed' '${_proj}/bootstrap/build.log' \
            'localhost/ai-new/test:trial' ''
        echo DONE
    ")" || rc=$?
    assert_success $rc "write_result should succeed" || _fail=1
    assert_contains "DONE" "$out" || _fail=1

    # No .tmp file should remain.
    [[ ! -f "${_proj}/bootstrap/build.result.1.json.tmp" ]] || {
        printf '    .tmp file left behind after write_result\n' >&2
        _fail=1
    }
    # The final file should exist.
    [[ -f "${_proj}/bootstrap/build.result.1.json" ]] || {
        printf '    build.result.1.json not created\n' >&2
        _fail=1
    }
    return $_fail
}

test_validate_request_rejects_missing_containerfile_field() {
    local _fail=0
    local _proj
    _proj="$(_make_proj "atom2")"
    # Request missing required 'containerfile' field.
    cat > "${_proj}/bootstrap/build.request.1.json" <<'EOF'
{
  "request_id": 1,
  "context_dir": "/some/dir",
  "image_tag": "localhost/test:trial",
  "reason": "initial"
}
EOF
    local out rc=0
    out="$(_coord_helper "
        validate_request '${_proj}' '${_proj}/bootstrap/build.request.1.json' || echo REJECTED
    ")" || rc=$?
    assert_contains "REJECTED" "$out" "missing containerfile field should be rejected" || _fail=1
    return $_fail
}

test_validate_request_rejects_missing_image_tag_field() {
    local _fail=0
    local _proj
    _proj="$(_make_proj "atom3")"
    cat > "${_proj}/bootstrap/build.request.1.json" <<'EOF'
{
  "request_id": 1,
  "containerfile": "/some/Containerfile",
  "context_dir": "/some/dir",
  "reason": "initial"
}
EOF
    local out rc=0
    out="$(_coord_helper "
        validate_request '${_proj}' '${_proj}/bootstrap/build.request.1.json' || echo REJECTED
    ")" || rc=$?
    assert_contains "REJECTED" "$out" "missing image_tag should be rejected" || _fail=1
    return $_fail
}

test_validate_request_rejects_non_integer_id() {
    local _fail=0
    local _proj
    _proj="$(_make_proj "atom4")"
    cat > "${_proj}/bootstrap/build.request.abc.json" <<'EOF'
{
  "request_id": "not-a-number",
  "containerfile": "/some/Containerfile",
  "context_dir": "/some/dir",
  "image_tag": "localhost/test:trial"
}
EOF
    local out rc=0
    out="$(_coord_helper "
        validate_request '${_proj}' '${_proj}/bootstrap/build.request.abc.json' || echo REJECTED
    ")" || rc=$?
    # Either the parsing fails (non-integer id) or the file is rejected.
    assert_contains "REJECTED" "$out" "non-integer id should be rejected" || _fail=1
    return $_fail
}

test_validate_request_rejects_partial_json() {
    local _fail=0
    local _proj
    _proj="$(_make_proj "atom5")"
    # Partial/truncated JSON.
    printf '{"request_id": 1, "containe' > "${_proj}/bootstrap/build.request.1.json"
    local out rc=0
    out="$(_coord_helper "
        validate_request '${_proj}' '${_proj}/bootstrap/build.request.1.json' || echo REJECTED
    ")" || rc=$?
    # With grep-based parsing, partial JSON would result in missing fields → rejected.
    assert_contains "REJECTED" "$out" "partial JSON should be rejected" || _fail=1
    return $_fail
}

test_validate_request_rejects_nonexistent_file() {
    local _fail=0
    local _proj
    _proj="$(_make_proj "atom6")"
    local out rc=0
    out="$(_coord_helper "
        validate_request '${_proj}' '${_proj}/bootstrap/build.request.99.json' || echo REJECTED
    ")" || rc=$?
    assert_contains "REJECTED" "$out" "nonexistent file should be rejected" || _fail=1
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "write_result uses .tmp + rename (no leftover .tmp)"   test_write_result_atomic_rename
run_test "validate_request rejects missing containerfile field"  test_validate_request_rejects_missing_containerfile_field
run_test "validate_request rejects missing image_tag field"      test_validate_request_rejects_missing_image_tag_field
run_test "validate_request rejects non-integer request_id"       test_validate_request_rejects_non_integer_id
run_test "validate_request rejects partial/truncated JSON"        test_validate_request_rejects_partial_json
run_test "validate_request rejects nonexistent file"             test_validate_request_rejects_nonexistent_file

print_summary "test_coordination_atomicity"
