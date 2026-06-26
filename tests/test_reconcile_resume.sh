#!/usr/bin/env bash
# T11 — Reconciliation: running status → correct replacement per R19.8 (AC24).
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

# ── Helpers ───────────────────────────────────────────────────────────────────

_recon_helper() {
    local _script="$1"
    cat > "${_TMPDIR}/recon_resume_helper.sh" <<SCRIPT
#!/usr/bin/env bash
set -uo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/lock.sh'
source '${LIB_DIR}/session.sh'
source '${LIB_DIR}/coordination.sh'
source '${LIB_DIR}/reconcile.sh'
export AI_PODMAN_JAILS_DIR='${_TMPDIR}'
export AI_NEW_LOCK_STALE_AFTER=10s
${_script}
SCRIPT
    bash "${_TMPDIR}/recon_resume_helper.sh" 2>&1
}

_make_proj_with_status() {
    local _name="$1"
    local _status="$2"
    local _root="${_TMPDIR}/projects/${_name}"
    mkdir -p "${_root}/bootstrap"

    # Always need a valid agent.env for reconcile_on_resume.
    cat > "${_root}/bootstrap/agent.env" <<AEOF
# source_hash=abc
# agent_name=codex
AGENT_NAME="codex"
AGENT_COMMAND="codex"
AGENT_INSTALL_ADAPTER="npm-global"
AEOF

    cat > "${_root}/bootstrap/session.json" <<EOF
{
  "project_name": "${_name}",
  "selected_agent": "codex",
  "status": "${_status}",
  "last_updated": "2026-01-01T00:00:00Z",
  "generated_files": [],
  "containerfile_path": "",
  "quality_gate_status": "",
  "last_error": "",
  "resume_command": "ai-new ${_name} --resume",
  "build_log_path": "",
  "trial_image_tag": "",
  "static_check_status": "",
  "pinned_agent_env": "${_root}/bootstrap/agent.env",
  "pinned_agent_hash": ""
}
EOF
    echo "$_root"
}

# ── Tests ─────────────────────────────────────────────────────────────────────

test_interviewing_without_lock_becomes_interrupted() {
    local _fail=0
    local _proj
    _proj="$(_make_proj_with_status "recon1" "interviewing")"
    # No lock → lock_is_active returns false.

    local out rc=0
    out="$(_recon_helper "
        reconcile_on_resume '${_proj}' || true
    ")" || rc=$?

    local _status
    _status="$(grep -oP '"status"\s*:\s*"\K[^"]+' "${_proj}/bootstrap/session.json" 2>/dev/null || true)"
    assert_eq "interrupted" "$_status" \
        "interviewing + no lock → interrupted" || _fail=1

    # Reconciliation note should appear in session.md.
    assert_contains "interviewing" "$(cat "${_proj}/bootstrap/session.md" 2>/dev/null)" \
        "session.md should note the status transition" || _fail=1
    return $_fail
}

test_quality_gate_running_without_lock_no_log_becomes_interrupted() {
    local _fail=0
    local _proj
    _proj="$(_make_proj_with_status "recon2" "quality-gate-running")"
    # No lock, no build.log.

    _recon_helper "reconcile_on_resume '${_proj}' || true" >/dev/null 2>&1 || true

    local _status
    _status="$(grep -oP '"status"\s*:\s*"\K[^"]+' "${_proj}/bootstrap/session.json" 2>/dev/null || true)"
    assert_eq "interrupted" "$_status" \
        "quality-gate-running + no lock + no log → interrupted" || _fail=1
    return $_fail
}

test_quality_gate_running_with_success_marker_becomes_complete() {
    local _fail=0
    local _proj
    _proj="$(_make_proj_with_status "recon3" "quality-gate-running")"
    touch "${_proj}/bootstrap/.build-success"

    _recon_helper "reconcile_on_resume '${_proj}' || true" >/dev/null 2>&1 || true

    local _status
    _status="$(grep -oP '"status"\s*:\s*"\K[^"]+' "${_proj}/bootstrap/session.json" 2>/dev/null || true)"
    assert_eq "complete" "$_status" \
        "quality-gate-running + success marker → complete" || _fail=1
    return $_fail
}

test_quality_gate_running_with_log_and_no_timeout_becomes_failed() {
    local _fail=0
    local _proj
    _proj="$(_make_proj_with_status "recon4" "quality-gate-running")"
    # Write a recent build.log (not old enough to be a timeout).
    printf 'Build failed: error\n' > "${_proj}/bootstrap/build.log"

    _recon_helper "reconcile_on_resume '${_proj}' || true" >/dev/null 2>&1 || true

    local _status
    _status="$(grep -oP '"status"\s*:\s*"\K[^"]+' "${_proj}/bootstrap/session.json" 2>/dev/null || true)"
    # Recent log → quality-gate-failed.
    assert_eq "quality-gate-failed" "$_status" \
        "quality-gate-running + recent log → quality-gate-failed" || _fail=1
    return $_fail
}

test_reconcile_notes_appended_to_session_md() {
    local _fail=0
    local _proj
    _proj="$(_make_proj_with_status "recon5" "interviewing")"

    _recon_helper "reconcile_on_resume '${_proj}' || true" >/dev/null 2>&1 || true

    local _md
    _md="$(cat "${_proj}/bootstrap/session.md" 2>/dev/null || true)"
    assert_contains "Reconciliation" "$_md" "session.md should have reconciliation note" || _fail=1
    return $_fail
}

test_resumable_statuses_not_changed() {
    local _fail=0
    # interrupted, quality-gate-failed, quality-gate-timeout → no change needed.
    local _status
    for _status in interrupted quality-gate-failed quality-gate-timeout; do
        local _proj
        _proj="$(_make_proj_with_status "recon_pass_${_status//[^a-z]/_}" "$_status")"

        _recon_helper "reconcile_on_resume '${_proj}' || true" >/dev/null 2>&1 || true

        local _after
        _after="$(grep -oP '"status"\s*:\s*"\K[^"]+' "${_proj}/bootstrap/session.json" 2>/dev/null || true)"
        assert_eq "$_status" "$_after" \
            "resumable status ${_status} should not be changed by reconcile" || _fail=1
    done
    return $_fail
}

test_reconcile_does_not_create_profile_mirror() {
    # AC7: reconcile must not write profiles/<slug>.env
    local _fail=0
    local _proj
    _proj="$(_make_proj_with_status "reconmirror" "interviewing")"

    _recon_helper "reconcile_on_resume '${_proj}' || true" >/dev/null 2>&1 || true

    [[ ! -f "${_TMPDIR}/profiles/reconmirror.env" ]] || {
        printf '    profiles/reconmirror.env was created by reconcile (AC7)\n' >&2
        _fail=1
    }
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "interviewing + no lock → interrupted"                      test_interviewing_without_lock_becomes_interrupted
run_test "quality-gate-running + no lock + no log → interrupted"     test_quality_gate_running_without_lock_no_log_becomes_interrupted
run_test "quality-gate-running + success marker → complete"          test_quality_gate_running_with_success_marker_becomes_complete
run_test "quality-gate-running + recent log → quality-gate-failed"   test_quality_gate_running_with_log_and_no_timeout_becomes_failed
run_test "reconcile appends note to session.md"                      test_reconcile_notes_appended_to_session_md
run_test "resumable statuses not changed by reconcile"               test_resumable_statuses_not_changed
run_test "reconcile does not create profiles/ mirror (AC7)"          test_reconcile_does_not_create_profile_mirror

print_summary "test_reconcile_resume"
