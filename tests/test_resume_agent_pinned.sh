#!/usr/bin/env bash
# T11 — Resume honours selected_agent; fails clearly on absent agent; auth problems reported (AC26).
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
    AI_PODMAN_JAILS_DIR="${_TMPDIR}" bash "${BIN_DIR}/ai-new" "$@" 2>&1
}

_make_resumable_project() {
    local _name="$1"
    local _agent="${2:-codex}"
    local _root="${_TMPDIR}/projects/${_name}"
    mkdir -p "${_root}/bootstrap"

    cat > "${_root}/bootstrap/agent.env" <<AEOF
# source_hash=abc123
# agent_name=${_agent}
AGENT_NAME="${_agent}"
AGENT_COMMAND="${_agent}"
AGENT_INSTALL_ADAPTER="npm-global"
AEOF

    cat > "${_root}/bootstrap/session.json" <<EOF
{
  "project_name": "${_name}",
  "selected_agent": "${_agent}",
  "status": "interrupted",
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
  "pinned_agent_hash": "abc123"
}
EOF
    cat > "${_root}/bootstrap/session.md" <<'MDEOF'
# Session Log

## Reconciliation Notes
_None._
MDEOF
    echo "$_root"
}

# ── Tests ─────────────────────────────────────────────────────────────────────

test_resume_reads_selected_agent_from_session_json() {
    local _fail=0
    local _proj
    _proj="$(_make_resumable_project "pinned1" "codex")"

    # Run without $() — ai-new's heartbeat background job blocks command substitution.
    # Capture output via a temp file instead.
    local _outfile="${_TMPDIR}/resume_pinned1_out.txt"
    AI_PODMAN_JAILS_DIR="${_TMPDIR}" bash "${BIN_DIR}/ai-new" pinned1 --resume >"$_outfile" 2>&1 || true
    local out
    out="$(cat "$_outfile" 2>/dev/null || true)"
    # ai-new should attempt to resume (may fail at launch due to stub podman, which is ok).
    # The key: it should NOT prompt for --agent, and should NOT say "agent not found".
    assert_not_contains "requires --agent" "$out" "resume should not require --agent" || _fail=1
    return $_fail
}

test_reconcile_fails_if_pinned_agent_env_missing() {
    local _fail=0
    local _root="${_TMPDIR}/projects/missingpin"
    mkdir -p "${_root}/bootstrap"
    # No agent.env — reconcile should fail.
    cat > "${_root}/bootstrap/session.json" <<'EOF'
{
  "project_name": "missingpin",
  "selected_agent": "codex",
  "status": "interrupted"
}
EOF
    cat > "${_root}/bootstrap/session.md" <<'MDEOF'
# Session Log

## Reconciliation Notes
_None._
MDEOF

    local out rc=0
    out="$(_ai_new missingpin --resume 2>&1)" || rc=$?
    assert_failure $rc "--resume with missing agent.env should fail" || _fail=1
    assert_contains "agent.env" "$out" "error should mention agent.env" || _fail=1
    return $_fail
}

test_reconcile_fails_if_agent_mismatch_between_session_and_pinned() {
    local _fail=0
    local _proj
    _proj="$(_make_resumable_project "mismatch1" "codex")"
    # Overwrite agent.env with different agent_name.
    cat > "${_proj}/bootstrap/agent.env" <<'AEOF'
# agent_name=different-agent
AGENT_NAME="different-agent"
AGENT_COMMAND="different-agent"
AGENT_INSTALL_ADAPTER="preinstalled"
AEOF

    local out rc=0
    out="$(_ai_new mismatch1 --resume 2>&1)" || rc=$?
    assert_failure $rc "agent mismatch should fail" || _fail=1
    # Error says "declares 'X' but session.json records 'Y'" — not the word "mismatch".
    assert_contains "Cannot resume" "$out" "error should mention cannot resume" || _fail=1
    return $_fail
}

test_start_here_resume_uses_pinned_runtime() {
    # Test that start-here.sh --resume reads agent from agent.env without re-prompting.
    local _fail=0
    local _bd="${_TMPDIR}/pinned_sh/bootstrap"
    mkdir -p "$_bd"
    cat > "${_bd}/agent.env" <<'AEOF'
AGENT_NAME="true"
AGENT_COMMAND="true"
AGENT_INSTALL_ADAPTER="preinstalled"
AGENT_AUTH_CHECK_ARGV=""
AEOF

    local _patched="${_TMPDIR}/sh-pinned-patched.sh"
    sed "s|BOOTSTRAP_DIR=\"/project/bootstrap\"|BOOTSTRAP_DIR=\"${_bd}\"|g" \
        "${REPO_ROOT}/lib/start-here.sh" > "$_patched"

    local out rc=0
    out="$(bash "$_patched" --resume 2>&1)" || rc=$?
    # --resume uses pinned runtime ('true'); 'true' exits 0.
    assert_success $rc "--resume with pinned runtime should succeed" || _fail=1
    assert_contains "resolved runtime" "$out" "start-here.sh should log the resolved runtime" || _fail=1
    return $_fail
}

test_start_here_resume_does_not_prompt_for_agent() {
    local _fail=0
    local _bd="${_TMPDIR}/no_prompt/bootstrap"
    mkdir -p "$_bd"
    cat > "${_bd}/agent.env" <<'AEOF'
AGENT_NAME="true"
AGENT_COMMAND="true"
AGENT_INSTALL_ADAPTER="preinstalled"
AGENT_AUTH_CHECK_ARGV=""
AEOF

    local _patched="${_TMPDIR}/sh-noprompt-patched.sh"
    sed "s|BOOTSTRAP_DIR=\"/project/bootstrap\"|BOOTSTRAP_DIR=\"${_bd}\"|g" \
        "${REPO_ROOT}/lib/start-here.sh" > "$_patched"

    local out rc=0
    out="$(bash "$_patched" --resume 2>&1)" || rc=$?
    assert_success $rc || _fail=1
    assert_not_contains "Which agent" "$out" "resume should not prompt for agent choice" || _fail=1
    assert_not_contains "Select runtime" "$out" "resume should not show runtime selector" || _fail=1
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "resume does not re-prompt for --agent"                   test_resume_reads_selected_agent_from_session_json
run_test "resume fails clearly if agent.env is missing"            test_reconcile_fails_if_pinned_agent_env_missing
run_test "reconcile fails if session.json agent != pinned agent"   test_reconcile_fails_if_agent_mismatch_between_session_and_pinned
run_test "start-here.sh --resume uses pinned runtime"              test_start_here_resume_uses_pinned_runtime
run_test "start-here.sh --resume does not prompt for agent"        test_start_here_resume_does_not_prompt_for_agent

print_summary "test_resume_agent_pinned"
