#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# 2026 - Anthony Burow - https://github.com/aburow
# T2a — run_install_adapter uses the correct pinned package for each supported agent (AC3, R3.2).
# Uses a fake npm on PATH that records its argv; no network or real installs.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

# ── Helpers ───────────────────────────────────────────────────────────────────

# Writes a fake npm stub into _TMPDIR/fakebin/ that records its argv.
_setup_fake_npm() {
    local _log="$1"
    mkdir -p "${_TMPDIR}/fakebin"
    printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\n' "$_log" \
        > "${_TMPDIR}/fakebin/npm"
    chmod +x "${_TMPDIR}/fakebin/npm"
    export PATH="${_TMPDIR}/fakebin:${PATH}"
}

_run_install_adapter() {
    local _adapter="$1" _package="$2" _version="${3:-}"
    cat > "${_TMPDIR}/adapter_helper.sh" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/adapter.sh'
run_install_adapter '${_adapter}' '${_package}' '${_version}'
SCRIPT
    bash "${_TMPDIR}/adapter_helper.sh" 2>&1
}

# Reads the recorded npm call log.
_npm_call_log() { echo "${_TMPDIR}/npm_calls.txt"; }

# ── Tests ─────────────────────────────────────────────────────────────────────

test_codex_npm_package_called() {
    local _fail=0
    local _log; _log="$(_npm_call_log)"
    _setup_fake_npm "$_log"

    local rc=0
    _run_install_adapter "npm-global" "@openai/codex" "" >/dev/null 2>&1 || rc=$?
    assert_success $rc "run_install_adapter should exit 0 with fake npm" || _fail=1

    [[ -f "$_log" ]] || { printf '    npm was never called\n' >&2; return 1; }
    local _recorded
    _recorded="$(cat "$_log")"
    assert_contains "install" "$_recorded"  "npm must be called with 'install'" || _fail=1
    assert_contains "-g"     "$_recorded"  "npm must be called with '-g'"      || _fail=1
    assert_contains "@openai/codex" "$_recorded" \
        "npm must use the codex package name from registry" || _fail=1
    return $_fail
}

test_gemini_npm_package_called() {
    local _fail=0
    local _log; _log="$(_npm_call_log)"
    _setup_fake_npm "$_log"

    local rc=0
    _run_install_adapter "npm-global" "@google/gemini-cli" "" >/dev/null 2>&1 || rc=$?
    assert_success $rc "run_install_adapter should exit 0 with fake npm" || _fail=1

    [[ -f "$_log" ]] || { printf '    npm was never called\n' >&2; return 1; }
    local _recorded
    _recorded="$(cat "$_log")"
    assert_contains "@google/gemini-cli" "$_recorded" "npm must use the gemini-cli package name" || _fail=1
    return $_fail
}

test_packages_come_from_registry_not_literal() {
    # Confirm each agent's registry file names the expected package.
    # This guards against a hardcoded package string in lib/ diverging from registry (R3.2).
    local _fail=0
    local _agents_dir="${REPO_ROOT}/config/agents.d"

    local _codex_pkg
    _codex_pkg="$(grep 'AGENT_INSTALL_PACKAGE' "${_agents_dir}/codex.env" | cut -d= -f2 | tr -d '"')"
    assert_eq "@openai/codex" "$_codex_pkg" "codex.env package" || _fail=1

    local _gemini_pkg
    _gemini_pkg="$(grep 'AGENT_INSTALL_PACKAGE' "${_agents_dir}/gemini.env" | cut -d= -f2 | tr -d '"')"
    assert_eq "@google/gemini-cli" "$_gemini_pkg" "gemini.env package" || _fail=1

    return $_fail
}

test_preinstalled_adapter_is_noop() {
    # preinstalled → no npm call, exits 0.
    local _fail=0
    local _log; _log="$(_npm_call_log)"
    _setup_fake_npm "$_log"

    local rc=0
    _run_install_adapter "preinstalled" "" "" >/dev/null 2>&1 || rc=$?
    assert_success $rc "preinstalled adapter should be a no-op" || _fail=1
    [[ ! -f "$_log" ]] || {
        printf '    npm was unexpectedly called for preinstalled adapter\n' >&2
        _fail=1
    }
    return $_fail
}

test_dnf_package_adapter_exits_nonzero_with_message() {
    # dnf-package requires root at launch time; must fail with actionable message (R3.4, B2).
    local _fail=0
    local out rc=0
    out="$(_run_install_adapter "dnf-package" "somepkg" "" 2>&1)" || rc=$?
    assert_failure $rc "dnf-package adapter must exit non-zero at launch time" || _fail=1
    assert_contains "root" "$out" "error must explain root requirement" || _fail=1
    assert_contains "dnf-package" "$out" "error must name the adapter" || _fail=1
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "codex: npm called with @openai/codex"     test_codex_npm_package_called
run_test "gemini: npm called with @google/gemini-cli"            test_gemini_npm_package_called
run_test "package names come from registry, not lib/ literals"   test_packages_come_from_registry_not_literal
run_test "preinstalled adapter: npm not called, exits 0"         test_preinstalled_adapter_is_noop
run_test "dnf-package adapter: fails with actionable message"    test_dnf_package_adapter_exits_nonzero_with_message

print_summary "test_install_adapter_invoked"
