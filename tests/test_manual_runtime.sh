#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# 2026 - Anthony Burow - https://github.com/aburow
# T6 — manual adapter with missing command reports setup instructions, not install (AC26, D1).
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

# ── Helpers ───────────────────────────────────────────────────────────────────

_patch_start_here() {
    local _bootstrap_dir="$1"
    local _out="${_TMPDIR}/sh-manual-patched.sh"
    sed "s|BOOTSTRAP_DIR=\"/project/bootstrap\"|BOOTSTRAP_DIR=\"${_bootstrap_dir}\"|g" \
        "${REPO_ROOT}/lib/start-here.sh" > "$_out"
    echo "$_out"
}

_run_patched() {
    local _bootstrap_dir="$1"
    shift
    local _patched
    _patched="$(_patch_start_here "$_bootstrap_dir")"
    bash "$_patched" "$@" 2>&1
}

# ── Tests ─────────────────────────────────────────────────────────────────────

test_manual_missing_command_exits_nonzero() {
    local _fail=0
    local _bd="${_TMPDIR}/manual1/bootstrap"
    mkdir -p "$_bd"
    cat > "${_bd}/agent.env" <<'AEOF'
AGENT_REGISTRY_VERSION="1"
AGENT_NAME="gemini"
AGENT_COMMAND="gemini-does-not-exist-on-path"
AGENT_INSTALL_ADAPTER="manual"
AGENT_CONFIG_DIRS=""
AGENT_ENV_VARS=""
AGENT_PROMPT_MODE="default"
AGENT_AUTH_CHECK_ARGV=""
AEOF
    local out rc=0
    out="$(_run_patched "$_bd")" || rc=$?
    assert_failure $rc "manual adapter with missing command should fail" || _fail=1
    return $_fail
}

test_manual_missing_command_reports_manual_setup() {
    local _fail=0
    local _bd="${_TMPDIR}/manual2/bootstrap"
    mkdir -p "$_bd"
    cat > "${_bd}/agent.env" <<'AEOF'
AGENT_NAME="gemini"
AGENT_COMMAND="gemini-cli-missing"
AGENT_INSTALL_ADAPTER="manual"
AGENT_AUTH_CHECK_ARGV=""
AEOF
    local out rc=0
    out="$(_run_patched "$_bd")" || rc=$?
    assert_failure $rc || _fail=1
    assert_contains "not installed in the bootstrap image" "$out" \
        "error should identify the broken image invariant" || _fail=1
    assert_contains "Containerfile.bootstrap" "$out" \
        "error should identify where installation belongs" || _fail=1
    assert_not_contains "npm" "$out" "should not suggest auto-install" || _fail=1
    assert_not_contains "pip" "$out" "should not suggest pip install" || _fail=1
    return $_fail
}

test_manual_present_command_proceeds() {
    local _fail=0
    local _bd="${_TMPDIR}/manual3/bootstrap"
    mkdir -p "$_bd"
    # 'true' is always on PATH — manual + present command should proceed to launch.
    cat > "${_bd}/agent.env" <<'AEOF'
AGENT_NAME="manual-ok"
AGENT_COMMAND="true"
AGENT_INSTALL_ADAPTER="manual"
AGENT_AUTH_CHECK_ARGV=""
AEOF
    local out rc=0
    out="$(_run_patched "$_bd")" || rc=$?
    # 'true' executes and exits 0 — no setup instructions needed.
    assert_success $rc "manual + present command should succeed" || _fail=1
    assert_not_contains "manually" "$out" "no setup instructions when command present" || _fail=1
    return $_fail
}

test_manual_names_the_missing_command() {
    local _fail=0
    local _bd="${_TMPDIR}/manual4/bootstrap"
    mkdir -p "$_bd"
    cat > "${_bd}/agent.env" <<'AEOF'
AGENT_NAME="gemini"
AGENT_COMMAND="gemini-cli-really-missing"
AGENT_INSTALL_ADAPTER="manual"
AGENT_AUTH_CHECK_ARGV=""
AEOF
    local out rc=0
    out="$(_run_patched "$_bd")" || rc=$?
    assert_failure $rc || _fail=1
    assert_contains "gemini-cli-really-missing" "$out" "error should name the missing command" || _fail=1
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "manual adapter + missing command → non-zero exit"         test_manual_missing_command_exits_nonzero
run_test "manual adapter + missing command → reports manual setup"  test_manual_missing_command_reports_manual_setup
run_test "manual adapter + present command → proceeds normally"     test_manual_present_command_proceeds
run_test "manual adapter error names the missing command"           test_manual_names_the_missing_command

print_summary "test_manual_runtime"
