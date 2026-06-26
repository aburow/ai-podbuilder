#!/usr/bin/env bash
# T3a — gemini.env declares npm-global adapter; manual adapter remains valid (AC3, R3.2, R3.4).
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
export AI_PODMAN_JAILS_DIR='${_TMPDIR}'
validate_adapters '${_adapter}'
SCRIPT
    bash "${_TMPDIR}/validate_helper.sh" 2>&1
}

_pin_gemini_helper() {
    local _proj="$1"
    mkdir -p "${_TMPDIR}/config/agents.d"
    cp "${REPO_ROOT}/config/agents.d/gemini.env" "${_TMPDIR}/config/agents.d/gemini.env"
    mkdir -p "${_proj}/bootstrap"
    cat > "${_TMPDIR}/pin_helper.sh" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/registry.sh'
export AI_PODMAN_JAILS_DIR='${_TMPDIR}'
export AI_PODMAN_AGENTS_DIR='${_TMPDIR}/config/agents.d'
pin_registry 'gemini' '${_proj}'
SCRIPT
    bash "${_TMPDIR}/pin_helper.sh" 2>&1
}

# ── Tests ─────────────────────────────────────────────────────────────────────

test_gemini_env_adapter_is_npm_global() {
    # B3: gemini.env must use npm-global, not manual.
    local _fail=0
    local _gemini="${REPO_ROOT}/config/agents.d/gemini.env"
    local _adapter
    _adapter="$(grep '^AGENT_INSTALL_ADAPTER' "$_gemini" | cut -d= -f2 | tr -d '"')"
    assert_eq "npm-global" "$_adapter" "gemini.env AGENT_INSTALL_ADAPTER must be npm-global" || _fail=1
    return $_fail
}

test_gemini_env_package_is_gemini_cli() {
    # B3: gemini.env must name the @google/gemini-cli npm package.
    local _fail=0
    local _gemini="${REPO_ROOT}/config/agents.d/gemini.env"
    local _pkg
    _pkg="$(grep '^AGENT_INSTALL_PACKAGE' "$_gemini" | cut -d= -f2 | tr -d '"')"
    assert_eq "@google/gemini-cli" "$_pkg" "gemini.env AGENT_INSTALL_PACKAGE must be @google/gemini-cli" || _fail=1
    return $_fail
}

test_gemini_env_command_is_gemini() {
    local _fail=0
    local _gemini="${REPO_ROOT}/config/agents.d/gemini.env"
    local _cmd
    _cmd="$(grep '^AGENT_COMMAND' "$_gemini" | cut -d= -f2 | tr -d '"')"
    assert_eq "gemini" "$_cmd" "gemini.env AGENT_COMMAND must be 'gemini'" || _fail=1
    return $_fail
}

test_gemini_env_not_manual() {
    # Confirm the old manual adapter value is gone.
    local _fail=0
    local _gemini="${REPO_ROOT}/config/agents.d/gemini.env"
    local _adapter
    _adapter="$(grep '^AGENT_INSTALL_ADAPTER' "$_gemini" | cut -d= -f2 | tr -d '"')"
    if [[ "$_adapter" == "manual" ]]; then
        printf '    gemini.env still uses the manual adapter — must be npm-global\n' >&2
        _fail=1
    fi
    return $_fail
}

test_pinned_gemini_env_has_npm_global() {
    # After pin_registry gemini, the pinned agent.env must carry npm-global + @google/gemini-cli.
    local _fail=0
    local _proj="${_TMPDIR}/projects/gemini_pin_test"
    local out rc=0
    out="$(_pin_gemini_helper "$_proj")" || rc=$?
    assert_success $rc "pin_registry gemini should succeed" || _fail=1

    local _pinned="${_proj}/bootstrap/agent.env"
    [[ -f "$_pinned" ]] || {
        printf '    pinned agent.env not created for gemini\n' >&2
        return 1
    }
    local _content
    _content="$(cat "$_pinned")"
    assert_contains "npm-global" "$_content" "pinned gemini agent.env must have npm-global" || _fail=1
    assert_contains "@google/gemini-cli" "$_content" "pinned gemini agent.env must have @google/gemini-cli" || _fail=1
    return $_fail
}

test_manual_adapter_still_valid_in_parser() {
    # B3: manual remains a valid adapter value for forward-compatibility (R3.4).
    local out rc=0
    out="$(_validate_adapter_helper "manual")" || rc=$?
    assert_success $rc "manual adapter must still pass validation after gemini migration" || return 1
}

test_all_three_agents_use_real_adapters() {
    # None of the shipped agents should use the manual adapter.
    local _fail=0
    local _agents_dir="${REPO_ROOT}/config/agents.d"
    local _f _adapter
    for _f in "${_agents_dir}"/*.env; do
        [[ -f "$_f" ]] || continue
        _adapter="$(grep '^AGENT_INSTALL_ADAPTER' "$_f" | cut -d= -f2 | tr -d '"')"
        if [[ "$_adapter" == "manual" ]]; then
            printf '    %s still uses manual adapter — shipped agents must use a real adapter\n' \
                "$(basename "$_f")" >&2
            _fail=1
        fi
    done
    return $_fail
}

test_gemini_uses_explicit_interactive_prompt_mode() {
    local _src
    _src="$(cat "${REPO_ROOT}/lib/start-here.sh")"
    assert_contains "gemini)" "$_src" || return 1
    assert_contains '--prompt-interactive "$_prompt_text"' "$_src" \
        "Gemini must execute the bootstrap prompt and remain interactive"
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "gemini.env: AGENT_INSTALL_ADAPTER is npm-global"         test_gemini_env_adapter_is_npm_global
run_test "gemini.env: AGENT_INSTALL_PACKAGE is @google/gemini-cli" test_gemini_env_package_is_gemini_cli
run_test "gemini.env: AGENT_COMMAND is gemini"                     test_gemini_env_command_is_gemini
run_test "gemini.env: adapter is not manual"                       test_gemini_env_not_manual
run_test "pinned gemini agent.env carries npm-global + package"    test_pinned_gemini_env_has_npm_global
run_test "manual adapter still valid in parser/validator"          test_manual_adapter_still_valid_in_parser
run_test "all shipped agents use a real (non-manual) adapter"      test_all_three_agents_use_real_adapters
run_test "gemini uses explicit interactive prompt mode"            test_gemini_uses_explicit_interactive_prompt_mode

print_summary "test_gemini_adapter"
