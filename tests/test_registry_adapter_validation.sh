#!/usr/bin/env bash
# T2 — Adapter validation: v1 fixed set passes; unknown fails; ai-new --agent <unknown> (AC2, AC20).
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

# ── Helpers ───────────────────────────────────────────────────────────────────

_validate_adapter_helper() {
    local _adapter="$1"
    cat > "${_TMPDIR}/validate_helper.sh" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/registry.sh'
export CODEX_JAILS_DIR='${_TMPDIR}'
validate_adapters '${_adapter}'
SCRIPT
    bash "${_TMPDIR}/validate_helper.sh" 2>&1
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
    cat > "${_TMPDIR}/config/agents.d/mymanual.env" <<'AEOF'
AGENT_REGISTRY_VERSION="1"
AGENT_NAME="mymanual"
AGENT_COMMAND="mymanual"
AGENT_INSTALL_ADAPTER="bad-adapter"
AGENT_INSTALL_PACKAGE=""
AGENT_CONFIG_DIRS=""
AGENT_ENV_VARS=""
AGENT_PROMPT_MODE="default"
AGENT_AUTH_CHECK_ARGV=""
AEOF
}

# ── Tests ─────────────────────────────────────────────────────────────────────

test_npm_global_adapter_valid() {
    local out rc=0
    out="$(_validate_adapter_helper npm-global)" || rc=$?
    assert_success $rc "npm-global adapter should pass validation" || return 1
}

test_pipx_adapter_valid() {
    local out rc=0
    out="$(_validate_adapter_helper pipx)" || rc=$?
    assert_success $rc "pipx adapter should pass validation" || return 1
}

test_dnf_package_adapter_valid() {
    local out rc=0
    out="$(_validate_adapter_helper dnf-package)" || rc=$?
    assert_success $rc "dnf-package adapter should pass validation" || return 1
}

test_preinstalled_adapter_valid() {
    local out rc=0
    out="$(_validate_adapter_helper preinstalled)" || rc=$?
    assert_success $rc "preinstalled adapter should pass validation" || return 1
}

test_manual_adapter_valid() {
    local out rc=0
    out="$(_validate_adapter_helper manual)" || rc=$?
    assert_success $rc "manual adapter should pass validation" || return 1
}

test_unknown_adapter_fails_validation() {
    local _fail=0
    local out rc=0
    out="$(_validate_adapter_helper chocolate-thunder)" || rc=$?
    assert_failure $rc "unknown adapter should fail validation" || _fail=1
    assert_contains "Unknown install adapter" "$out" || _fail=1
    assert_contains "chocolate-thunder" "$out" "error should name the bad adapter" || _fail=1
    return $_fail
}

test_empty_adapter_fails_validation() {
    local _fail=0
    local out rc=0
    out="$(_validate_adapter_helper "")" || rc=$?
    assert_failure $rc "empty adapter should fail validation" || _fail=1
    return $_fail
}

test_ai_new_unknown_agent_exits_nonzero_and_lists_registered() {
    local _fail=0
    _setup_agents

    # mymanual has a bad-adapter so it can't be in agents.d for a clean list test.
    # Remove it and just use codex.
    rm -f "${_TMPDIR}/config/agents.d/mymanual.env"

    local out rc=0
    out="$(CODEX_JAILS_DIR="${_TMPDIR}" bash "${BIN_DIR}/ai-new" testproject \
        --agent not-a-real-agent 2>&1)" || rc=$?
    assert_failure $rc "--agent with unknown name should fail" || _fail=1
    assert_contains "not-a-real-agent" "$out" "error should name the bad agent" || _fail=1
    assert_contains "codex" "$out" "error should list registered agents" || _fail=1
    return $_fail
}

test_validate_agent_bad_adapter_fails() {
    local _fail=0
    # Agent file has a valid name but invalid adapter.
    _setup_agents  # sets up mymanual with bad-adapter

    cat > "${_TMPDIR}/validate_agent_helper.sh" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/registry.sh'
export CODEX_JAILS_DIR='${_TMPDIR}'
export CODEX_AGENTS_DIR='${_TMPDIR}/config/agents.d'
validate_agent 'mymanual'
SCRIPT
    local out rc=0
    out="$(bash "${_TMPDIR}/validate_agent_helper.sh" 2>&1)" || rc=$?
    assert_failure $rc "validate_agent with bad adapter should fail" || _fail=1
    assert_contains "Unknown install adapter" "$out" || _fail=1
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "npm-global adapter validates"                          test_npm_global_adapter_valid
run_test "pipx adapter validates"                               test_pipx_adapter_valid
run_test "dnf-package adapter validates"                        test_dnf_package_adapter_valid
run_test "preinstalled adapter validates"                        test_preinstalled_adapter_valid
run_test "manual adapter validates"                             test_manual_adapter_valid
run_test "unknown adapter fails validation with clear message"   test_unknown_adapter_fails_validation
run_test "empty adapter fails validation"                       test_empty_adapter_fails_validation
run_test "ai-new --agent <unknown> exits non-zero, lists agents" test_ai_new_unknown_agent_exits_nonzero_and_lists_registered
run_test "validate_agent with bad adapter fails"                 test_validate_agent_bad_adapter_fails

print_summary "test_registry_adapter_validation"
