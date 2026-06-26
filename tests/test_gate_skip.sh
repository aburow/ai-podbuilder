#!/usr/bin/env bash
# T9 — Skip trial build yields generated-unvalidated with warning (AC13).
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

# ── Helpers ───────────────────────────────────────────────────────────────────

_gate_helper() {
    local _script="$1"
    cat > "${_TMPDIR}/gate_helper.sh" <<SCRIPT
#!/usr/bin/env bash
set -uo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/session.sh'
source '${LIB_DIR}/coordination.sh'
source '${LIB_DIR}/quality_gate.sh'
export AI_PODMAN_JAILS_DIR='${_TMPDIR}'
export SLUG='testslug'
${_script}
SCRIPT
    bash "${_TMPDIR}/gate_helper.sh" 2>&1
}

_make_proj_with_containerfile() {
    local _name="$1"
    local _root="${_TMPDIR}/projects/${_name}"
    mkdir -p "${_root}/bootstrap" "${_root}/image"
    cat > "${_root}/bootstrap/session.json" <<EOF
{
  "project_name": "${_name}",
  "selected_agent": "codex",
  "status": "started",
  "last_updated": "2026-01-01T00:00:00Z",
  "generated_files": [],
  "containerfile_path": "",
  "quality_gate_status": "",
  "last_error": "",
  "resume_command": "ai-new ${_name} --resume",
  "build_log_path": "",
  "trial_image_tag": "",
  "static_check_status": "",
  "pinned_agent_env": "",
  "pinned_agent_hash": ""
}
EOF
    printf 'FROM scratch\n' > "${_root}/image/Containerfile"
    echo "$_root"
}

# ── Tests ─────────────────────────────────────────────────────────────────────

test_map_gate_status_skipped_yields_generated_unvalidated() {
    local _fail=0
    local out rc=0
    out="$(_gate_helper "
        map_gate_status 0 0 1
        printf '%s\n' \"\$GATE_STATUS\"
    ")" || rc=$?
    assert_success $rc || _fail=1
    assert_contains "generated-unvalidated" "$out" "skip=1 should map to generated-unvalidated" || _fail=1
    return $_fail
}

test_run_quality_gate_skip_sets_session_status() {
    local _fail=0
    local _proj
    _proj="$(_make_proj_with_containerfile "skip1")"

    cat > "${_TMPDIR}/gate_skip_helper.sh" <<SCRIPT
#!/usr/bin/env bash
set -uo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/session.sh'
source '${LIB_DIR}/coordination.sh'
source '${LIB_DIR}/quality_gate.sh'
export AI_PODMAN_JAILS_DIR='${_TMPDIR}'
export SLUG='testslug'
export SKIP_TRIAL_BUILD=1
run_quality_gate '${_proj}' 1 '${_proj}/image/Containerfile' '${_proj}/image' \
    'localhost/ai-new/testslug:trial' 'test' 0
SCRIPT
    local out rc=0
    out="$(bash "${_TMPDIR}/gate_skip_helper.sh" 2>&1)" || rc=$?
    assert_success $rc "run_quality_gate with skip should succeed" || _fail=1

    local _status
    _status="$(grep -oP '"status"\s*:\s*"\K[^"]+' "${_proj}/bootstrap/session.json" 2>/dev/null || true)"
    assert_eq "generated-unvalidated" "$_status" "session status should be generated-unvalidated" || _fail=1
    return $_fail
}

test_skip_trial_build_env_var() {
    local _fail=0
    local _proj
    _proj="$(_make_proj_with_containerfile "skip2")"

    cat > "${_TMPDIR}/gate_skip2_helper.sh" <<SCRIPT
#!/usr/bin/env bash
set -uo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/session.sh'
source '${LIB_DIR}/coordination.sh'
source '${LIB_DIR}/quality_gate.sh'
export AI_PODMAN_JAILS_DIR='${_TMPDIR}'
export SLUG='testslug'
export SKIP_TRIAL_BUILD=1
run_quality_gate '${_proj}' 1 '${_proj}/image/Containerfile' '${_proj}/image' \
    'localhost/ai-new/testslug:trial' 'test' 0
printf 'GATE=%s\n' "\$GATE_STATUS"
SCRIPT
    local out rc=0
    out="$(bash "${_TMPDIR}/gate_skip2_helper.sh" 2>&1)" || rc=$?
    assert_success $rc || _fail=1
    assert_contains "generated-unvalidated" "$out" || _fail=1

    # Verify that a warning is logged about skipping.
    assert_contains "skipped" "$out" "skip should produce a warning/info message" || _fail=1
    return $_fail
}

test_skip_writes_result_file() {
    local _fail=0
    local _proj
    _proj="$(_make_proj_with_containerfile "skip3")"

    cat > "${_TMPDIR}/gate_skip3_helper.sh" <<SCRIPT
#!/usr/bin/env bash
set -uo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/session.sh'
source '${LIB_DIR}/coordination.sh'
source '${LIB_DIR}/quality_gate.sh'
export AI_PODMAN_JAILS_DIR='${_TMPDIR}'
export SLUG='testslug'
export SKIP_TRIAL_BUILD=1
run_quality_gate '${_proj}' 1 '${_proj}/image/Containerfile' '${_proj}/image' \
    'localhost/ai-new/testslug:trial' 'test' 0
SCRIPT
    bash "${_TMPDIR}/gate_skip3_helper.sh" >/dev/null 2>&1 || true
    [[ -f "${_proj}/bootstrap/build.result.1.json" ]] || {
        printf '    build.result.1.json not written on skip\n' >&2
        _fail=1
    }
    local _content
    _content="$(cat "${_proj}/bootstrap/build.result.1.json" 2>/dev/null || true)"
    assert_contains '"status": "skipped"' "$_content" \
        "protocol result should use the agent-facing skipped status" || _fail=1
    return $_fail
}

test_ai_new_skip_trial_build_flag() {
    local _fail=0
    # Verify that --skip-trial-build sets SKIP_TRIAL_BUILD=1 via ai-new arg parsing.
    # We can check this by running ai-new -h and ensuring --skip-trial-build is in usage.
    local out rc=0
    out="$(AI_PODMAN_JAILS_DIR="${_TMPDIR}" bash "${BIN_DIR}/ai-new" -h 2>&1)" || rc=$?
    assert_success $rc || _fail=1
    assert_contains "skip-trial-build" "$out" "--skip-trial-build should appear in help" || _fail=1
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "map_gate_status: skip=1 → generated-unvalidated"   test_map_gate_status_skipped_yields_generated_unvalidated
run_test "run_quality_gate: skip sets session to generated-unvalidated" test_run_quality_gate_skip_sets_session_status
run_test "SKIP_TRIAL_BUILD=1 logs skip message"              test_skip_trial_build_env_var
run_test "skip writes result file with skip status"          test_skip_writes_result_file
run_test "--skip-trial-build appears in ai-new help"         test_ai_new_skip_trial_build_flag

print_summary "test_gate_skip"
