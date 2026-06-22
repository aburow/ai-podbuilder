#!/usr/bin/env bash
# T2 — Registry security: hostile values are never executed (R13, AC20).
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

# ── Tests ─────────────────────────────────────────────────────────────────────

test_command_substitution_not_executed() {
    local _fail=0
    local _sentinel="${_TMPDIR}/EXECUTED"
    local _reg="${_TMPDIR}/hostile.env"

    # Write a registry with a command-substitution payload in a string field.
    # If the parser ever eval/source's the file, the sentinel will be created.
    cat > "$_reg" <<REOF
AGENT_NAME="\$(touch '${_sentinel}')"
AGENT_COMMAND="\$(touch '${_sentinel}')"
AGENT_INSTALL_ADAPTER="preinstalled"
AGENT_CONFIG_DIRS="\$(touch '${_sentinel}')"
AGENT_ENV_VARS="\$(touch '${_sentinel}')"
REOF

    cat > "${_TMPDIR}/security_helper.sh" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/registry.sh'
export CODEX_JAILS_DIR='${_TMPDIR}'
parse_registry_file '${_reg}'
printf 'NAME=%s\n' "\$REG_AGENT_NAME"
SCRIPT
    local out rc=0
    out="$(bash "${_TMPDIR}/security_helper.sh" 2>&1)" || rc=$?
    assert_success $rc "parse should succeed without executing payload" || _fail=1

    if [[ -f "$_sentinel" ]]; then
        printf '    SECURITY FAIL: sentinel file was created — command was executed!\n' >&2
        _fail=1
    fi

    # The value should be stored as a literal string (containing the $() text).
    assert_contains '$(touch' "$out" "hostile value should be stored literally" || _fail=1
    return $_fail
}

test_backtick_substitution_not_executed() {
    local _fail=0
    local _sentinel="${_TMPDIR}/EXECUTED_BT"
    local _reg="${_TMPDIR}/hostile_bt.env"

    # Backtick substitution in a value.
    cat > "$_reg" <<REOF
AGENT_NAME="\`touch '${_sentinel}'\`"
AGENT_COMMAND="safe-command"
AGENT_INSTALL_ADAPTER="preinstalled"
REOF

    cat > "${_TMPDIR}/bt_helper.sh" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/registry.sh'
export CODEX_JAILS_DIR='${_TMPDIR}'
parse_registry_file '${_reg}'
echo "parsed"
SCRIPT
    local out rc=0
    out="$(bash "${_TMPDIR}/bt_helper.sh" 2>&1)" || rc=$?
    assert_success $rc "parse should succeed with backtick payload" || _fail=1

    if [[ -f "$_sentinel" ]]; then
        printf '    SECURITY FAIL: sentinel created via backtick — value was executed!\n' >&2
        _fail=1
    fi
    return $_fail
}

test_semicolon_injection_not_executed() {
    local _fail=0
    local _sentinel="${_TMPDIR}/EXECUTED_SEMI"
    local _reg="${_TMPDIR}/hostile_semi.env"

    cat > "$_reg" <<REOF
AGENT_NAME="safe-name; touch '${_sentinel}'"
AGENT_COMMAND="safe-cmd"
AGENT_INSTALL_ADAPTER="preinstalled"
REOF

    cat > "${_TMPDIR}/semi_helper.sh" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/registry.sh'
export CODEX_JAILS_DIR='${_TMPDIR}'
parse_registry_file '${_reg}'
echo "parsed"
SCRIPT
    local out rc=0
    out="$(bash "${_TMPDIR}/semi_helper.sh" 2>&1)" || rc=$?
    assert_success $rc || _fail=1

    if [[ -f "$_sentinel" ]]; then
        printf '    SECURITY FAIL: sentinel created via semicolon injection!\n' >&2
        _fail=1
    fi
    return $_fail
}

test_hostile_registry_in_start_here_parser() {
    local _fail=0
    local _sentinel="${_TMPDIR}/SH_EXECUTED"

    # Build a patched start-here.sh that reads from our temp dir.
    local _tmpbootstrap="${_TMPDIR}/project/bootstrap"
    mkdir -p "$_tmpbootstrap"

    cat > "${_tmpbootstrap}/agent.env" <<REOF
AGENT_NAME="\$(touch '${_sentinel}')"
AGENT_COMMAND="\$(touch '${_sentinel}')"
AGENT_INSTALL_ADAPTER="preinstalled"
REOF

    local _patched="${_TMPDIR}/sh-patched.sh"
    sed "s|BOOTSTRAP_DIR=\"/project/bootstrap\"|BOOTSTRAP_DIR=\"${_tmpbootstrap}\"|g" \
        "${REPO_ROOT}/start-here.sh" > "$_patched"

    # Run with -h so it exits immediately after parsing agent.env (which happens at top level).
    local out rc=0
    out="$(bash "$_patched" -h 2>&1)" || rc=$?
    # -h should exit 0 (help) even if agent.env is dodgy.
    # Main assertion: sentinel was NOT created.

    if [[ -f "$_sentinel" ]]; then
        printf '    SECURITY FAIL: sentinel created by start-here.sh parser!\n' >&2
        _fail=1
    fi
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "command substitution in registry value not executed" test_command_substitution_not_executed
run_test "backtick substitution in registry value not executed" test_backtick_substitution_not_executed
run_test "semicolon injection in registry value not executed"  test_semicolon_injection_not_executed
run_test "start-here.sh parser: hostile value not executed"    test_hostile_registry_in_start_here_parser

print_summary "test_registry_security"
