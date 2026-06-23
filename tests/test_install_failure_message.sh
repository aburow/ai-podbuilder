#!/usr/bin/env bash
# T2c — failed npm install produces an actionable error naming agent/adapter/package/command (R3.4).
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

# ── Helpers ───────────────────────────────────────────────────────────────────

_patch_start_here() {
    local _bootstrap_dir="$1"
    local _out="${_TMPDIR}/start-here-patched.sh"
    sed \
        -e "s|BOOTSTRAP_DIR=\"/project/bootstrap\"|BOOTSTRAP_DIR=\"${_bootstrap_dir}\"|g" \
        -e "s|/start-here-lib/|${LIB_DIR}/|g" \
        "${REPO_ROOT}/start-here.sh" > "$_out"
    chmod +x "$_out"
    echo "$_out"
}

_write_agent_env() {
    local _dir="$1" _agent="$2" _cmd="$3" _adapter="$4" _pkg="$5"
    mkdir -p "$_dir"
    cat > "${_dir}/agent.env" <<AEOF
AGENT_REGISTRY_VERSION="1"
AGENT_NAME="${_agent}"
AGENT_COMMAND="${_cmd}"
AGENT_INSTALL_ADAPTER="${_adapter}"
AGENT_INSTALL_PACKAGE="${_pkg}"
AGENT_INSTALL_VERSION=""
AGENT_CONFIG_DIRS=""
AGENT_ENV_VARS=""
AGENT_PROMPT_MODE="default"
AGENT_AUTH_CHECK_ARGV=""
AEOF
}

# _FAKE_CMD is a command name guaranteed not to exist on the host PATH.
# Using a name with underscores makes it unpublishable as a real binary.
_FAKE_CMD="_zz_noexist_testclient"

_setup_failing_npm() {
    mkdir -p "${_TMPDIR}/fakebin"
    printf '#!/bin/sh\nexit 1\n' > "${_TMPDIR}/fakebin/npm"
    chmod +x "${_TMPDIR}/fakebin/npm"
    export PATH="${_TMPDIR}/fakebin:${PATH}"
}

# ── Tests ─────────────────────────────────────────────────────────────────────

test_failed_npm_exits_nonzero() {
    # Use a command that doesn't exist on the host so the install step actually runs.
    local _fail=0
    local _bd="${_TMPDIR}/proj1/bootstrap"
    _write_agent_env "$_bd" "testagent" "$_FAKE_CMD" "npm-global" "@test/testagent-pkg"
    _setup_failing_npm

    local _patched rc=0
    _patched="$(_patch_start_here "$_bd")"
    bash "$_patched" >/dev/null 2>&1 || rc=$?
    assert_failure $rc "failed npm install must make start-here.sh exit non-zero" || _fail=1
    return $_fail
}

test_failed_npm_error_names_agent() {
    local _fail=0
    local _bd="${_TMPDIR}/proj2/bootstrap"
    _write_agent_env "$_bd" "testagent" "$_FAKE_CMD" "npm-global" "@test/testagent-pkg"
    _setup_failing_npm

    local _patched out rc=0
    _patched="$(_patch_start_here "$_bd")"
    out="$(bash "$_patched" 2>&1)" || rc=$?
    assert_failure $rc || _fail=1
    assert_contains "testagent" "$out" "error must name the agent runtime" || _fail=1
    return $_fail
}

test_failed_npm_error_names_adapter() {
    local _fail=0
    local _bd="${_TMPDIR}/proj3/bootstrap"
    _write_agent_env "$_bd" "testagent" "$_FAKE_CMD" "npm-global" "@test/testagent-pkg"
    _setup_failing_npm

    local _patched out rc=0
    _patched="$(_patch_start_here "$_bd")"
    out="$(bash "$_patched" 2>&1)" || rc=$?
    assert_failure $rc || _fail=1
    assert_contains "npm-global" "$out" "error must name the adapter" || _fail=1
    return $_fail
}

test_failed_npm_error_names_package() {
    local _fail=0
    local _bd="${_TMPDIR}/proj4/bootstrap"
    _write_agent_env "$_bd" "testagent" "$_FAKE_CMD" "npm-global" "@test/testagent-pkg"
    _setup_failing_npm

    local _patched out rc=0
    _patched="$(_patch_start_here "$_bd")"
    out="$(bash "$_patched" 2>&1)" || rc=$?
    assert_failure $rc || _fail=1
    assert_contains "@test/testagent-pkg" "$out" "error must name the package" || _fail=1
    return $_fail
}

test_failed_npm_error_names_install_command() {
    local _fail=0
    local _bd="${_TMPDIR}/proj5/bootstrap"
    _write_agent_env "$_bd" "testagent" "$_FAKE_CMD" "npm-global" "@test/testagent-pkg"
    _setup_failing_npm

    local _patched out rc=0
    _patched="$(_patch_start_here "$_bd")"
    out="$(bash "$_patched" 2>&1)" || rc=$?
    assert_failure $rc || _fail=1
    # The validate_runtime error block prints the attempted install command.
    assert_contains "npm" "$out" "error must reference the npm install command" || _fail=1
    return $_fail
}

test_failed_npm_not_a_downstream_auth_error() {
    # A failed install must surface before the auth-check step, so the error is about
    # install failure or missing command — not about missing credentials (R3.4).
    local _fail=0
    local _bd="${_TMPDIR}/proj6/bootstrap"
    _write_agent_env "$_bd" "testagent" "$_FAKE_CMD" "npm-global" "@test/testagent-pkg"
    _setup_failing_npm

    local _patched out rc=0
    _patched="$(_patch_start_here "$_bd")"
    out="$(bash "$_patched" 2>&1)" || rc=$?
    assert_failure $rc || _fail=1
    # Must NOT look like an auth failure from the auth-check step.
    assert_not_contains "failed authentication" "$out" \
        "install failure must not be misreported as an auth error" || _fail=1
    assert_not_contains "API key" "$out" \
        "install failure must not mention API keys (that is the auth-check message)" || _fail=1
    return $_fail
}

test_gemini_failed_install_error_names_agent_and_package() {
    # Same assertions for the gemini package name to ensure correctness regardless of agent.
    local _fail=0
    local _bd="${_TMPDIR}/proj7/bootstrap"
    # Use _FAKE_CMD so the install actually runs (no real gemini on host PATH).
    _write_agent_env "$_bd" "gemini" "$_FAKE_CMD" "npm-global" "@google/gemini-cli"
    _setup_failing_npm

    local _patched out rc=0
    _patched="$(_patch_start_here "$_bd")"
    out="$(bash "$_patched" 2>&1)" || rc=$?
    assert_failure $rc || _fail=1
    assert_contains "gemini" "$out" "error must name the agent (gemini)" || _fail=1
    assert_contains "@google/gemini-cli" "$out" "error must name the gemini package" || _fail=1
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "failed npm: exit non-zero"                               test_failed_npm_exits_nonzero
run_test "failed npm: error names the agent"                       test_failed_npm_error_names_agent
run_test "failed npm: error names the adapter"                     test_failed_npm_error_names_adapter
run_test "failed npm: error names the package"                     test_failed_npm_error_names_package
run_test "failed npm: error names the install command"             test_failed_npm_error_names_install_command
run_test "failed npm: not reported as an auth error"               test_failed_npm_not_a_downstream_auth_error
run_test "failed gemini install: names gemini and package"         test_gemini_failed_install_error_names_agent_and_package

print_summary "test_install_failure_message"
