#!/usr/bin/env bash
# T2b — install step is skipped when the agent command is already on PATH (R3.5, AC3).
# Uses a fake agent command + fake npm to verify the idempotency path without a network install.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

# ── Helpers ───────────────────────────────────────────────────────────────────

_patch_start_here() {
    local _bootstrap_dir="$1"
    local _out="${_TMPDIR}/start-here-patched.sh"
    # Replace BOOTSTRAP_DIR with the temp dir, and /start-here-lib with the real lib/.
    sed \
        -e "s|BOOTSTRAP_DIR=\"/project/bootstrap\"|BOOTSTRAP_DIR=\"${_bootstrap_dir}\"|g" \
        -e "s|/start-here-lib/|${LIB_DIR}/|g" \
        "${REPO_ROOT}/start-here.sh" > "$_out"
    chmod +x "$_out"
    echo "$_out"
}

_write_agent_env() {
    local _dir="$1" _agent="$2" _cmd="$3" _adapter="$4" _pkg="$5" _auth="${6:-}"
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
AGENT_AUTH_CHECK_ARGV="${_auth}"
AEOF
}

_setup_fake_agent_bin() {
    local _cmd="$1"
    mkdir -p "${_TMPDIR}/fakebin"
    printf '#!/bin/sh\nexit 0\n' > "${_TMPDIR}/fakebin/${_cmd}"
    chmod +x "${_TMPDIR}/fakebin/${_cmd}"
    export PATH="${_TMPDIR}/fakebin:${PATH}"
}

_setup_fake_npm() {
    local _log="$1"
    mkdir -p "${_TMPDIR}/fakebin"
    printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\n' "$_log" \
        > "${_TMPDIR}/fakebin/npm"
    chmod +x "${_TMPDIR}/fakebin/npm"
    export PATH="${_TMPDIR}/fakebin:${PATH}"
}

# ── Tests ─────────────────────────────────────────────────────────────────────

test_install_skipped_when_command_present() {
    # When the agent command is already on PATH, _install_runtime must skip install
    # and log "already present".
    local _fail=0
    local _bd="${_TMPDIR}/proj1/bootstrap"
    _write_agent_env "$_bd" "testbot" "testbot" "npm-global" "@test/testbot"
    _setup_fake_agent_bin "testbot"

    local _npm_log="${_TMPDIR}/npm_calls.txt"
    _setup_fake_npm "$_npm_log"

    local _patched out rc=0
    _patched="$(_patch_start_here "$_bd")"
    # Run the script; fake testbot exits 0 for auth-check and exec.
    out="$(bash "$_patched" 2>&1)" || rc=$?
    # Script may exit 0 (if fake testbot exits 0 on exec) or non-zero (if auth check name differs).
    # The key assertions are about install skipping, not overall exit code.
    assert_contains "already present" "$out" "install must log 'already present' when command on PATH" || _fail=1
    [[ ! -f "$_npm_log" ]] || {
        printf '    npm was called but should have been skipped:\n%s\n' "$(cat "$_npm_log")" >&2
        _fail=1
    }
    return $_fail
}

test_resume_does_not_call_npm_when_command_present() {
    local _fail=0
    local _bd="${_TMPDIR}/proj2/bootstrap"
    _write_agent_env "$_bd" "testbot" "testbot" "npm-global" "@test/testbot"
    _setup_fake_agent_bin "testbot"

    local _npm_log="${_TMPDIR}/npm_calls_resume.txt"
    _setup_fake_npm "$_npm_log"

    cat > "${_bd}/session.json" <<'EOF'
{"project_name":"p2","selected_agent":"testbot","status":"interrupted"}
EOF

    local _patched out rc=0
    _patched="$(_patch_start_here "$_bd")"
    out="$(bash "$_patched" --resume 2>&1)" || rc=$?
    assert_contains "already present" "$out" \
        "--resume must skip install and log 'already present' when command on PATH" || _fail=1
    [[ ! -f "$_npm_log" ]] || {
        printf '    npm called unexpectedly on --resume path\n' >&2
        _fail=1
    }
    return $_fail
}

test_install_already_present_log_is_at_info_level() {
    # When the command is on PATH, "already present" is logged at [INFO] not [WARN]/[ERROR].
    local _fail=0
    local _bd="${_TMPDIR}/proj3/bootstrap"
    _write_agent_env "$_bd" "testbot" "testbot" "npm-global" "@test/testbot"
    _setup_fake_agent_bin "testbot"

    local _patched out rc=0
    _patched="$(_patch_start_here "$_bd")"
    out="$(bash "$_patched" 2>&1)" || rc=$?
    assert_contains "[INFO]" "$out" "skip-install log must be at INFO level" || _fail=1
    assert_contains "already present" "$out" "must log 'already present' when command on PATH" || _fail=1
    assert_not_contains "[ERROR]" "$(echo "$out" | grep 'already present')" \
        "skip log must not be at ERROR level" || _fail=1
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "command on PATH: npm not called, install skipped"            test_install_skipped_when_command_present
run_test "--resume path: npm not called when command already on PATH"  test_resume_does_not_call_npm_when_command_present
run_test "skip-install log is at INFO level and says 'already present'" test_install_already_present_log_is_at_info_level

print_summary "test_install_idempotent_resume"
