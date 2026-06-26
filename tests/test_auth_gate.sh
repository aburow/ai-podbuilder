#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# 2026 - Anthony Burow - https://github.com/aburow
# T6 — Auth gate: fail → report + no interview; pass → agent launched (AC6, R10, D4).
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

# ── Helpers ───────────────────────────────────────────────────────────────────

_patch_start_here() {
    local _bootstrap_dir="$1"
    local _out="${_TMPDIR}/start-here-auth-patched.sh"
    sed "s|BOOTSTRAP_DIR=\"/project/bootstrap\"|BOOTSTRAP_DIR=\"${_bootstrap_dir}\"|g" \
        "${REPO_ROOT}/lib/start-here.sh" > "$_out"
    echo "$_out"
}

_run_patched() {
    local _bootstrap_dir="$1"
    shift
    local _patched
    _patched="$(_patch_start_here "$_bootstrap_dir")"
    PATH="${_TMPDIR}/stubs:${PATH}" bash "$_patched" "$@" 2>&1
}

_write_agent_env_with_auth() {
    local _dir="$1"
    local _cmd="$2"
    local _auth_argv="$3"
    local _env_vars="${4:-}"
    mkdir -p "$_dir"
    cat > "${_dir}/agent.env" <<AEOF
AGENT_REGISTRY_VERSION="1"
AGENT_NAME="testbot"
AGENT_COMMAND="${_cmd}"
AGENT_INSTALL_ADAPTER="preinstalled"
AGENT_CONFIG_DIRS=""
AGENT_ENV_VARS="${_env_vars}"
AGENT_PROMPT_MODE="default"
AGENT_AUTH_CHECK_ARGV="${_auth_argv}"
AEOF
}

_stub_cmd_passing() {
    local _name="$1"
    mkdir -p "${_TMPDIR}/stubs"
    cat > "${_TMPDIR}/stubs/${_name}" <<'SH'
#!/usr/bin/env bash
exit 0
SH
    chmod +x "${_TMPDIR}/stubs/${_name}"
}

_stub_cmd_failing() {
    local _name="$1"
    mkdir -p "${_TMPDIR}/stubs"
    cat > "${_TMPDIR}/stubs/${_name}" <<'SH'
#!/usr/bin/env bash
exit 1
SH
    chmod +x "${_TMPDIR}/stubs/${_name}"
}

# ── Tests ─────────────────────────────────────────────────────────────────────

test_auth_failure_exits_nonzero() {
    local _fail=0
    local _bd="${_TMPDIR}/auth_fail/bootstrap"
    # auth-check-argv that will fail: 'fail-bot|--version'
    _stub_cmd_failing "fail-bot"
    _write_agent_env_with_auth "$_bd" "fail-bot" "fail-bot|--version"

    local out rc=0
    out="$(_run_patched "$_bd")" || rc=$?
    assert_failure $rc "auth failure should exit non-zero" || _fail=1
    return $_fail
}

test_auth_failure_reports_error() {
    local _fail=0
    local _bd="${_TMPDIR}/auth_report/bootstrap"
    _stub_cmd_failing "fail-bot2"
    _write_agent_env_with_auth "$_bd" "fail-bot2" "fail-bot2|--version"

    local out rc=0
    out="$(_run_patched "$_bd")" || rc=$?
    assert_failure $rc || _fail=1
    assert_contains "authentication" "$out" "error should mention auth" || _fail=1
    assert_contains "fail-bot2" "$out" "error should name the runtime" || _fail=1
    return $_fail
}

test_auth_failure_reports_setup_path_with_env_vars() {
    local _fail=0
    local _bd="${_TMPDIR}/auth_env/bootstrap"
    _stub_cmd_failing "env-bot"
    _write_agent_env_with_auth "$_bd" "env-bot" "env-bot|--version" "MY_API_KEY"

    local out rc=0
    out="$(_run_patched "$_bd")" || rc=$?
    assert_failure $rc || _fail=1
    assert_contains "MY_API_KEY" "$out" "error should mention required API key var" || _fail=1
    assert_contains "agent.env.local" "$out" "error should mention agent.env.local path" || _fail=1
    return $_fail
}

test_auth_success_proceeds_to_launch() {
    local _fail=0
    local _bd="${_TMPDIR}/auth_pass/bootstrap"
    # Use 'true' as the auth command (always passes) and as the agent command.
    _write_agent_env_with_auth "$_bd" "true" "true|--version"

    local out rc=0
    # 'true --version' exits 0 (auth passes).
    # Then start-here tries to exec 'true' as the agent. This exits 0.
    out="$(_run_patched "$_bd")" || rc=$?
    # Should have logged INFO about auth passing.
    assert_contains "Auth check passed" "$out" "auth pass should be logged" || _fail=1
    return $_fail
}

test_no_auth_argv_just_checks_command_exists() {
    local _fail=0
    local _bd="${_TMPDIR}/auth_nocheck/bootstrap"
    mkdir -p "$_bd"
    cat > "${_bd}/agent.env" <<'AEOF'
AGENT_NAME="true"
AGENT_COMMAND="true"
AGENT_INSTALL_ADAPTER="preinstalled"
AGENT_AUTH_CHECK_ARGV=""
AEOF
    # No auth-check defined; command 'true' exists → should proceed.
    local out rc=0
    out="$(_run_patched "$_bd")" || rc=$?
    # The agent command ('true') will be exec'd; it exits 0.
    assert_success $rc "no auth-check with existing command should succeed" || _fail=1
    return $_fail
}

test_command_not_on_path_exits_nonzero() {
    local _fail=0
    local _bd="${_TMPDIR}/auth_missing/bootstrap"
    mkdir -p "$_bd"
    cat > "${_bd}/agent.env" <<'AEOF'
AGENT_NAME="ghost-cli"
AGENT_COMMAND="ghost-cli-does-not-exist"
AGENT_INSTALL_ADAPTER="preinstalled"
AGENT_AUTH_CHECK_ARGV=""
AEOF
    local out rc=0
    out="$(_run_patched "$_bd")" || rc=$?
    assert_failure $rc "missing command should fail" || _fail=1
    assert_contains "not installed" "$out" "error should mention not installed" || _fail=1
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "auth check failure exits non-zero"                   test_auth_failure_exits_nonzero
run_test "auth failure reports error with runtime name"        test_auth_failure_reports_error
run_test "auth failure reports API key var and setup path"     test_auth_failure_reports_setup_path_with_env_vars
run_test "auth success logs pass and proceeds to launch"       test_auth_success_proceeds_to_launch
run_test "no auth-check: just verify command exists"           test_no_auth_argv_just_checks_command_exists
run_test "command not on PATH → not installed error"           test_command_not_on_path_exits_nonzero

print_summary "test_auth_gate"
