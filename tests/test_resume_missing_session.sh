#!/usr/bin/env bash
# T4 — --resume with missing/unreadable session.json fails clearly (AC4).
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

# ── Helpers ───────────────────────────────────────────────────────────────────

_ai_new() {
    AI_PODMAN_JAILS_DIR="${_TMPDIR}" bash "${BIN_DIR}/ai-new" "$@" 2>&1
}

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

# ── Tests ─────────────────────────────────────────────────────────────────────

test_resume_project_not_exist_fails() {
    local _fail=0
    local out rc=0
    out="$(_ai_new ghostproject --resume 2>&1)" || rc=$?
    assert_failure $rc "--resume on non-existent project should fail" || _fail=1
    assert_contains "ghostproject" "$out" "error should name the project" || _fail=1
    assert_not_contains "--resume" "$out" "should not loop-suggest --resume" || true
    return $_fail
}

test_resume_missing_session_json_fails_clearly() {
    local _fail=0
    # Create project directory but no session.json.
    mkdir -p "${_TMPDIR}/projects/no-session-proj"

    local out rc=0
    out="$(_ai_new no-session-proj --resume 2>&1)" || rc=$?
    assert_failure $rc "--resume with missing session.json should fail" || _fail=1
    # Error should mention session.json or the path.
    assert_contains "session.json" "$out" "error should mention session.json" || _fail=1
    return $_fail
}

test_resume_terminal_status_complete_fails() {
    local _fail=0
    local _root="${_TMPDIR}/projects/terminal-proj"
    mkdir -p "${_root}/bootstrap"
    # Set up a valid pinned agent.env so reconcile_on_resume doesn't die first.
    _setup_agents
    cat > "${_root}/bootstrap/agent.env" <<'AEOF'
# Pinned agent registry entry
# source_path=/tmp/test/config/agents.d/codex.env
# agent_name=codex
# registry_version=1
# source_hash=abc123
# pinned_at=2026-01-01T00:00:00Z
AGENT_NAME="codex"
AGENT_COMMAND="codex"
AGENT_INSTALL_ADAPTER="npm-global"
AEOF
    cat > "${_root}/bootstrap/session.json" <<'EOF'
{
  "project_name": "terminal-proj",
  "selected_agent": "codex",
  "status": "complete",
  "last_updated": "2026-01-01T00:00:00Z",
  "generated_files": [],
  "containerfile_path": "",
  "quality_gate_status": "",
  "last_error": "",
  "resume_command": "ai-new terminal-proj --resume",
  "build_log_path": "",
  "trial_image_tag": "",
  "static_check_status": "",
  "pinned_agent_env": "",
  "pinned_agent_hash": ""
}
EOF
    local out rc=0
    out="$(_ai_new terminal-proj --resume 2>&1)" || rc=$?
    assert_failure $rc "--resume on complete project should fail" || _fail=1
    assert_contains "complete" "$out" "error should name the terminal status" || _fail=1
    return $_fail
}

test_resume_terminal_status_generated_unvalidated_fails() {
    local _fail=0
    local _root="${_TMPDIR}/projects/unval-proj"
    mkdir -p "${_root}/bootstrap"
    _setup_agents
    cat > "${_root}/bootstrap/agent.env" <<'AEOF'
# agent_name=codex
AGENT_NAME="codex"
AGENT_COMMAND="codex"
AGENT_INSTALL_ADAPTER="npm-global"
AEOF
    cat > "${_root}/bootstrap/session.json" <<'EOF'
{
  "project_name": "unval-proj",
  "selected_agent": "codex",
  "status": "generated-unvalidated",
  "last_updated": "2026-01-01T00:00:00Z",
  "generated_files": [],
  "containerfile_path": "",
  "quality_gate_status": "",
  "last_error": "",
  "resume_command": "ai-new unval-proj --resume",
  "build_log_path": "",
  "trial_image_tag": "",
  "static_check_status": "",
  "pinned_agent_env": "",
  "pinned_agent_hash": ""
}
EOF
    local out rc=0
    out="$(_ai_new unval-proj --resume 2>&1)" || rc=$?
    assert_failure $rc "--resume on generated-unvalidated should fail" || _fail=1
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "--resume on non-existent project fails clearly"        test_resume_project_not_exist_fails
run_test "--resume with missing session.json fails clearly"       test_resume_missing_session_json_fails_clearly
run_test "--resume on complete status fails (terminal)"          test_resume_terminal_status_complete_fails
run_test "--resume on generated-unvalidated fails (terminal)"    test_resume_terminal_status_generated_unvalidated_fails

print_summary "test_resume_missing_session"
