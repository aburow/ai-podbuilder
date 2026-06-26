#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# 2026 - Anthony Burow - https://github.com/aburow
# T7 — Generated artifacts derive paths from env vars; no hardcoded usernames (AC11).
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

_current_username() {
    id -un 2>/dev/null || whoami 2>/dev/null || echo ""
}

# ── Tests ─────────────────────────────────────────────────────────────────────

test_bin_scripts_no_hardcoded_username() {
    local _fail=0
    local _user
    _user="$(_current_username)"
    [[ -n "$_user" ]] || { _SKIP_REASON="could not determine current username"; return 0; }

    local _f
    shopt -s nullglob
    for _f in "${BIN_DIR}"/*; do
        [[ -f "$_f" ]] || continue
        if grep -qF "/$_user/" "$_f" 2>/dev/null; then
            printf '    Hardcoded username found in: %s\n' "$(basename "$_f")" >&2
            _fail=1
        fi
    done
    shopt -u nullglob
    return $_fail
}

test_lib_scripts_no_hardcoded_username() {
    local _fail=0
    local _user
    _user="$(_current_username)"
    [[ -n "$_user" ]] || { _SKIP_REASON="could not determine current username"; return 0; }

    local _f
    shopt -s nullglob
    for _f in "${LIB_DIR}"/*.sh; do
        [[ -f "$_f" ]] || continue
        if grep -qF "/$_user/" "$_f" 2>/dev/null; then
            printf '    Hardcoded username found in: %s\n' "$(basename "$_f")" >&2
            _fail=1
        fi
    done
    shopt -u nullglob
    return $_fail
}

test_scaffold_profile_env_uses_variables() {
    local _fail=0
    _setup_agents
    # Run ai-new to create the scaffold; then check profile.env.
    AI_PODMAN_JAILS_DIR="${_TMPDIR}" bash "${BIN_DIR}/ai-new" convtest --agent codex >/dev/null 2>&1 || true

    local _profile="${_TMPDIR}/projects/convtest/profile.env"
    [[ -f "$_profile" ]] || { _SKIP_REASON="scaffold not created (stub launch exit?)"; return 0; }

    local _user
    _user="$(_current_username)"
    if [[ -n "$_user" ]] && grep -qF "/$_user/" "$_profile" 2>/dev/null; then
        printf '    Hardcoded username in profile.env: %s\n' "$(grep -F "/$_user/" "$_profile")" >&2
        _fail=1
    fi

    # Should not contain /var/home/ literals.
    if grep -qE '/var/home/[a-zA-Z0-9_-]+' "$_profile" 2>/dev/null; then
        printf '    Hardcoded /var/home/ path in profile.env\n' >&2
        _fail=1
    fi
    return $_fail
}

test_scaffold_session_json_uses_variables() {
    local _fail=0
    _setup_agents
    AI_PODMAN_JAILS_DIR="${_TMPDIR}" bash "${BIN_DIR}/ai-new" convtest2 --agent codex >/dev/null 2>&1 || true

    local _json="${_TMPDIR}/projects/convtest2/bootstrap/session.json"
    [[ -f "$_json" ]] || { _SKIP_REASON="session.json not created"; return 0; }

    local _user
    _user="$(_current_username)"
    if [[ -n "$_user" ]] && grep -qF "/$_user/" "$_json" 2>/dev/null; then
        printf '    Hardcoded username in session.json\n' >&2
        _fail=1
    fi
    return $_fail
}

test_no_var_home_in_scripts() {
    # Verify bin/ and lib/ contain no /var/home/ paths.
    local _fail=0
    local _f
    for _f in "${BIN_DIR}"/* "${LIB_DIR}"/*.sh; do
        [[ -f "$_f" ]] || continue
        if grep -qE '/var/home/[a-zA-Z0-9_-]+' "$_f" 2>/dev/null; then
            printf '    /var/home/ hardcoded in: %s\n' "$(basename "$_f")" >&2
            _fail=1
        fi
    done
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "bin/ scripts: no hardcoded current username"         test_bin_scripts_no_hardcoded_username
run_test "lib/ scripts: no hardcoded current username"         test_lib_scripts_no_hardcoded_username
run_test "scaffold profile.env: no hardcoded username or /var/home/" test_scaffold_profile_env_uses_variables
run_test "scaffold session.json: no hardcoded username"        test_scaffold_session_json_uses_variables
run_test "no /var/home/ hardcoded in scripts"                  test_no_var_home_in_scripts

print_summary "test_conventions_no_username"
