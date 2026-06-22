#!/usr/bin/env bash
# T4 — Collision and resume dispatch: status-driven create/refuse/abort (AC3, AC4).
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

# ── Helpers ───────────────────────────────────────────────────────────────────

_setup_agents() {
    mkdir -p "${_TMPDIR}/config/agents.d"
    cat > "${_TMPDIR}/config/agents.d/codex.env" <<'AEOF'
AGENT_REGISTRY_VERSION="1"
AGENT_NAME="codex"
AGENT_COMMAND="codex"
AGENT_INSTALL_ADAPTER="npm-global"
AGENT_INSTALL_PACKAGE="@openai/codex"
AGENT_CONFIG_DIRS=".codex"
AGENT_ENV_VARS=""
AGENT_PROMPT_MODE="default"
AGENT_AUTH_CHECK_ARGV="codex|--version"
AEOF
}

_ai_new() {
    CODEX_JAILS_DIR="${_TMPDIR}" bash "${BIN_DIR}/ai-new" "$@" 2>&1
}

_create_project_with_status() {
    local _name="$1"
    local _status="$2"
    local _root="${_TMPDIR}/projects/${_name}"

    mkdir -p "${_root}/bootstrap"
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
}

# ── Tests ─────────────────────────────────────────────────────────────────────

test_create_when_absent_succeeds() {
    local _fail=0
    _setup_agents
    # Run without $() — ai-new's heartbeat background job blocks command substitution.
    CODEX_JAILS_DIR="${_TMPDIR}" bash "${BIN_DIR}/ai-new" freshproject --agent codex >/dev/null 2>&1 || true
    [[ -d "${_TMPDIR}/projects/freshproject" ]] || {
        printf '    Project directory not created\n' >&2
        _fail=1
    }
    return $_fail
}

test_collision_non_terminal_suggests_resume() {
    local _fail=0
    _setup_agents
    _create_project_with_status "coltest" "interviewing"

    local out rc=0
    out="$(_ai_new coltest --agent codex 2>&1)" || rc=$?
    assert_failure $rc "collision with non-terminal status should fail" || _fail=1
    assert_contains "--resume" "$out" "error should suggest --resume" || _fail=1
    assert_contains "coltest" "$out" "error should name the project" || _fail=1
    return $_fail
}

test_collision_started_suggests_resume() {
    local _fail=0
    _setup_agents
    _create_project_with_status "startedtest" "started"

    local out rc=0
    out="$(_ai_new startedtest --agent codex 2>&1)" || rc=$?
    assert_failure $rc || _fail=1
    assert_contains "--resume" "$out" || _fail=1
    return $_fail
}

test_collision_generated_suggests_resume() {
    local _fail=0
    _setup_agents
    _create_project_with_status "gentest" "generated"

    local out rc=0
    out="$(_ai_new gentest --agent codex 2>&1)" || rc=$?
    assert_failure $rc || _fail=1
    assert_contains "--resume" "$out" || _fail=1
    return $_fail
}

test_collision_complete_aborts_without_overwrite() {
    local _fail=0
    _setup_agents
    _create_project_with_status "donetest" "complete"

    local out rc=0
    out="$(_ai_new donetest --agent codex 2>&1)" || rc=$?
    assert_failure $rc "collision with complete status should abort" || _fail=1
    # Should NOT suggest --resume for terminal states.
    # The session.json should still exist and be unchanged.
    local _status
    _status="$(grep -oP '"status"\s*:\s*"\K[^"]+' \
        "${_TMPDIR}/projects/donetest/bootstrap/session.json" 2>/dev/null || echo "")"
    assert_eq "complete" "$_status" "session.json should not be overwritten" || _fail=1
    return $_fail
}

test_collision_generated_unvalidated_aborts() {
    local _fail=0
    _setup_agents
    _create_project_with_status "unvaltest" "generated-unvalidated"

    local out rc=0
    out="$(_ai_new unvaltest --agent codex 2>&1)" || rc=$?
    assert_failure $rc "collision with generated-unvalidated should abort" || _fail=1
    return $_fail
}

test_collision_dir_without_session_fails_closed() {
    local _fail=0
    _setup_agents
    # Create directory but no session.json.
    mkdir -p "${_TMPDIR}/projects/nosession"

    local out rc=0
    out="$(_ai_new nosession --agent codex 2>&1)" || rc=$?
    assert_failure $rc "dir without session.json should fail" || _fail=1
    assert_contains "no session.json" "$out" "should mention missing session.json" || _fail=1
    return $_fail
}

test_new_project_requires_agent_flag() {
    local _fail=0
    _setup_agents
    local out rc=0
    out="$(_ai_new newagentless 2>&1)" || rc=$?
    assert_failure $rc "new project without --agent should fail" || _fail=1
    assert_contains "--agent" "$out" "error should mention --agent flag" || _fail=1
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "fresh project creates successfully"                  test_create_when_absent_succeeds
run_test "collision interviewing → refuse + suggest --resume"  test_collision_non_terminal_suggests_resume
run_test "collision started → refuse + suggest --resume"       test_collision_started_suggests_resume
run_test "collision generated → refuse + suggest --resume"     test_collision_generated_suggests_resume
run_test "collision complete → abort without overwrite"        test_collision_complete_aborts_without_overwrite
run_test "collision generated-unvalidated → abort"             test_collision_generated_unvalidated_aborts
run_test "dir without session.json fails clearly"              test_collision_dir_without_session_fails_closed
run_test "new project without --agent fails with message"      test_new_project_requires_agent_flag

print_summary "test_collision"
