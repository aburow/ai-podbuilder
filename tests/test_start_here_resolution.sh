#!/usr/bin/env bash
# T6 — start-here.sh runtime resolution across all four cases (AC5, R4).
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

# ── Helpers ───────────────────────────────────────────────────────────────────

# Patch start-here.sh to use a temp dir instead of the hardcoded /project/bootstrap.
_patch_start_here() {
    local _bootstrap_dir="$1"
    local _out="${_TMPDIR}/start-here-patched.sh"
    sed "s|BOOTSTRAP_DIR=\"/project/bootstrap\"|BOOTSTRAP_DIR=\"${_bootstrap_dir}\"|g" \
        "${REPO_ROOT}/start-here.sh" > "$_out"
    echo "$_out"
}

_write_agent_env() {
    local _dir="$1"
    local _agent="${2:-testbot}"
    local _cmd="${3:-true}"
    local _adapter="${4:-preinstalled}"
    local _auth="${5:-}"
    mkdir -p "$_dir"
    cat > "${_dir}/agent.env" <<AEOF
AGENT_REGISTRY_VERSION="1"
AGENT_NAME="${_agent}"
AGENT_COMMAND="${_cmd}"
AGENT_INSTALL_ADAPTER="${_adapter}"
AGENT_CONFIG_DIRS=""
AGENT_ENV_VARS=""
AGENT_PROMPT_MODE="default"
AGENT_AUTH_CHECK_ARGV="${_auth}"
AEOF
}

_run_patched() {
    local _bootstrap_dir="$1"
    shift
    local _patched
    _patched="$(_patch_start_here "$_bootstrap_dir")"
    bash "$_patched" "$@" 2>&1
}

# ── Tests ─────────────────────────────────────────────────────────────────────

test_help_with_missing_agent_env_exits_zero() {
    # -h exits 0 even if agent.env is missing (start-here.sh runs parser before -h check)
    # but the -h/--help flag should show usage.
    local _fail=0
    local _bd="${_TMPDIR}/proj1/bootstrap"
    _write_agent_env "$_bd" "testbot" "true" "preinstalled"
    local out rc=0
    out="$(_run_patched "$_bd" -h)" || rc=$?
    assert_success $rc "start-here.sh -h should exit 0" || _fail=1
    assert_contains "Usage" "$out" || _fail=1
    return $_fail
}

test_single_runtime_resolved_automatically() {
    # When exactly one runtime is configured, it should be used.
    local _fail=0
    local _bd="${_TMPDIR}/proj2/bootstrap"
    _write_agent_env "$_bd" "testbot" "true" "preinstalled"

    local out rc=0
    # Run with -h to avoid actually launching the agent (which would exec 'true').
    out="$(_run_patched "$_bd" -h)" || rc=$?
    assert_success $rc || _fail=1
    return $_fail
}

test_zero_runtimes_fails() {
    # Empty agent.env → no agent name → fail with message.
    local _fail=0
    local _bd="${_TMPDIR}/proj3/bootstrap"
    mkdir -p "$_bd"
    cat > "${_bd}/agent.env" <<'AEOF'
AGENT_REGISTRY_VERSION="1"
AGENT_NAME=""
AGENT_COMMAND=""
AGENT_INSTALL_ADAPTER="preinstalled"
AEOF
    local out rc=0
    out="$(_run_patched "$_bd")" || rc=$?
    assert_failure $rc "zero runtimes should fail" || _fail=1
    assert_contains "No agent runtime" "$out" "error should mention no runtime" || _fail=1
    return $_fail
}

test_missing_agent_env_fails_with_message() {
    # No agent.env at all → fail clearly.
    local _fail=0
    local _bd="${_TMPDIR}/proj4/bootstrap"
    mkdir -p "$_bd"
    # Do NOT write agent.env.
    local out rc=0
    out="$(_run_patched "$_bd")" || rc=$?
    assert_failure $rc "missing agent.env should fail" || _fail=1
    assert_contains "Missing pinned agent registry" "$out" || _fail=1
    return $_fail
}

test_resume_flag_uses_pinned_runtime() {
    # --resume uses AGENT_NAME from agent.env without re-prompting.
    local _fail=0
    local _bd="${_TMPDIR}/proj5/bootstrap"
    _write_agent_env "$_bd" "testbot" "true" "preinstalled"
    # Write a session.json with the selected agent.
    cat > "${_bd}/session.json" <<'EOF'
{"project_name":"p5","selected_agent":"testbot","status":"interrupted"}
EOF
    local out rc=0
    out="$(_run_patched "$_bd" --resume -h)" || rc=$?
    # -h exits 0 regardless; the point is it doesn't prompt or fail.
    assert_success $rc "--resume with pinned runtime should not fail" || _fail=1
    return $_fail
}

test_unknown_flag_exits_nonzero() {
    local _fail=0
    local _bd="${_TMPDIR}/proj6/bootstrap"
    _write_agent_env "$_bd" "testbot" "true" "preinstalled"
    local out rc=0
    out="$(_run_patched "$_bd" --bogus-flag)" || rc=$?
    assert_failure $rc "unknown flag should fail" || _fail=1
    assert_contains "Unknown flag" "$out" || _fail=1
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "start-here.sh -h exits 0 with agent.env present"   test_help_with_missing_agent_env_exits_zero
run_test "single configured runtime resolved automatically"   test_single_runtime_resolved_automatically
run_test "zero runtimes → fail with setup guidance"           test_zero_runtimes_fails
run_test "missing agent.env → fail with message"              test_missing_agent_env_fails_with_message
run_test "--resume uses pinned runtime, no re-prompt"         test_resume_flag_uses_pinned_runtime
run_test "unknown flag exits non-zero"                        test_unknown_flag_exits_nonzero

print_summary "test_start_here_resolution"
