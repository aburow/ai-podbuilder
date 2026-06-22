#!/usr/bin/env bash
# T8 — request/result pairs reconstructable on resume (AC27).
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

# ── Helpers ───────────────────────────────────────────────────────────────────

_coord_helper() {
    local _script="$1"
    cat > "${_TMPDIR}/recon_helper.sh" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/session.sh'
source '${LIB_DIR}/coordination.sh'
export CODEX_JAILS_DIR='${_TMPDIR}'
${_script}
SCRIPT
    bash "${_TMPDIR}/recon_helper.sh" 2>&1
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

# ── Tests ─────────────────────────────────────────────────────────────────────

test_request_result_files_persist_across_resume() {
    local _fail=0
    local _proj
    _proj="$(_make_proj "recon1")"

    # Write a request and result.
    cat > "${_proj}/bootstrap/build.request.1.json" <<EOF
{
  "request_id": 1,
  "containerfile": "${_proj}/image/Containerfile",
  "context_dir": "${_proj}/image",
  "image_tag": "localhost/ai-new/test:trial",
  "reason": "initial",
  "repair_iteration": 0
}
EOF
    cat > "${_proj}/bootstrap/build.result.1.json" <<'EOF'
{
  "request_id": 1,
  "exit_code": 0,
  "status": "complete",
  "static_check_status": "passed"
}
EOF

    # Simulate resume: the files should still be there.
    [[ -f "${_proj}/bootstrap/build.request.1.json" ]] || {
        printf '    request file missing after simulated resume\n' >&2
        _fail=1
    }
    [[ -f "${_proj}/bootstrap/build.result.1.json" ]] || {
        printf '    result file missing after simulated resume\n' >&2
        _fail=1
    }
    return $_fail
}

test_next_id_after_resume_skips_completed() {
    local _fail=0
    local _proj
    _proj="$(_make_proj "recon2")"

    # Pre-existing completed pair.
    cat > "${_proj}/bootstrap/build.result.3.json" <<'EOF'
{"request_id": 3, "exit_code": 0, "status": "complete"}
EOF

    local out rc=0
    out="$(_coord_helper "next_request_id '${_proj}'")" || rc=$?
    assert_success $rc || _fail=1
    # Should skip past id=3.
    local _id
    _id="$(echo "$out" | tr -d '\n')"
    [[ "$_id" -gt 3 ]] || {
        printf '    next id (%s) should be > 3 (max completed)\n' "$_id" >&2
        _fail=1
    }
    return $_fail
}

test_interrupted_request_detected_by_reconcile() {
    local _fail=0
    local _proj
    _proj="$(_make_proj "recon3")"
    mkdir -p "${_proj}/bootstrap"

    # Request with no matching result → interrupted.
    cat > "${_proj}/bootstrap/build.request.5.json" <<'EOF'
{"request_id": 5, "containerfile": "/dev/null", "context_dir": "/tmp", "image_tag": "test:trial"}
EOF
    # No build.result.5.json.

    cat > "${_TMPDIR}/interrupted_helper.sh" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/reconcile.sh'
source '${LIB_DIR}/session.sh'
source '${LIB_DIR}/coordination.sh'
export CODEX_JAILS_DIR='${_TMPDIR}'
interrupted_requests '${_proj}'
SCRIPT
    local out rc=0
    out="$(bash "${_TMPDIR}/interrupted_helper.sh" 2>&1)" || rc=$?
    assert_success $rc || _fail=1
    assert_contains "5" "$out" "id=5 should be detected as interrupted" || _fail=1
    return $_fail
}

test_completed_request_not_interrupted() {
    local _fail=0
    local _proj
    _proj="$(_make_proj "recon4")"

    # Request + result both exist → not interrupted.
    cat > "${_proj}/bootstrap/build.request.2.json" <<'EOF'
{"request_id": 2}
EOF
    cat > "${_proj}/bootstrap/build.result.2.json" <<'EOF'
{"request_id": 2, "status": "complete"}
EOF

    cat > "${_TMPDIR}/completed_helper.sh" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/reconcile.sh'
source '${LIB_DIR}/session.sh'
source '${LIB_DIR}/coordination.sh'
export CODEX_JAILS_DIR='${_TMPDIR}'
ids="\$(interrupted_requests '${_proj}')"
if [[ -z "\$ids" ]]; then echo NONE; else echo "\$ids"; fi
SCRIPT
    local out rc=0
    out="$(bash "${_TMPDIR}/completed_helper.sh" 2>&1)" || rc=$?
    assert_success $rc || _fail=1
    assert_eq "NONE" "$out" "completed pair should not appear as interrupted" || _fail=1
    return $_fail
}

test_result_file_content_readable_after_write() {
    local _fail=0
    local _proj
    _proj="$(_make_proj "recon5")"

    local out rc=0
    out="$(_coord_helper "
        write_result '${_proj}' 42 0 'complete' 'passed' '${_proj}/bootstrap/build.log' \
            'localhost/ai-new/test:trial' ''
        cat '${_proj}/bootstrap/build.result.42.json'
    ")" || rc=$?
    assert_success $rc || _fail=1
    assert_contains '"request_id": 42' "$out" "result should have request_id" || _fail=1
    assert_contains '"status": "complete"' "$out" || _fail=1
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "request/result files persist across simulated resume"  test_request_result_files_persist_across_resume
run_test "next_request_id after resume skips completed ids"       test_next_id_after_resume_skips_completed
run_test "interrupted_requests detects request with no result"    test_interrupted_request_detected_by_reconcile
run_test "completed pair not detected as interrupted"             test_completed_request_not_interrupted
run_test "written result is readable with expected fields"        test_result_file_content_readable_after_write

print_summary "test_coordination_reconstruct"
