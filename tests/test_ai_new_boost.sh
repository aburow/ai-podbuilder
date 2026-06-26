#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# 2026 - Anthony Burow - https://github.com/aburow
# T12 — ai-new --boost copies Codex auth.json into bootstrap and durable homes.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

# ── Helpers ───────────────────────────────────────────────────────────────────

_seed_runtime_registry() {
    mkdir -p "${_TMPDIR}/config/agents.d"
    cat > "${_TMPDIR}/config/agents.d/gemini.env" <<'EOF'
AGENT_REGISTRY_VERSION="1"
AGENT_NAME="gemini"
AGENT_COMMAND="gemini"
AGENT_CONFIG_DIRS=".gemini"
AGENT_ENV_VARS=""
AGENT_PROMPT_MODE="default"
AGENT_INSTALL_ADAPTER="preinstalled"
AGENT_AUTH_CHECK_ARGV="gemini|--version"
EOF
    cat > "${_TMPDIR}/config/agents.d/codex.env" <<'EOF'
AGENT_REGISTRY_VERSION="1"
AGENT_NAME="codex"
AGENT_COMMAND="codex"
AGENT_CONFIG_DIRS=".codex"
AGENT_ENV_VARS=""
AGENT_PROMPT_MODE="default"
AGENT_INSTALL_ADAPTER="preinstalled"
AGENT_AUTH_CHECK_ARGV="codex|--version"
EOF
}

_seed_start_here() {
    mkdir -p "${_TMPDIR}/lib"
    cat > "${_TMPDIR}/lib/start-here.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "${_TMPDIR}/lib/start-here.sh"
}

_seed_auth_file() {
    printf 'dummy-auth-for-tests\n' > "${_TMPDIR}/auth.json"
    chmod 600 "${_TMPDIR}/auth.json"
}

_run_ai_new() {
    PATH="${STUBS_DIR}:${PATH}" AI_PODMAN_JAILS_DIR="${_TMPDIR}" \
        bash "${BIN_DIR}/ai-new" "$@" 2>&1
}

# ── Tests ─────────────────────────────────────────────────────────────────────

test_boost_copies_auth_into_bootstrap_and_state() {
    local _fail=0
    _seed_runtime_registry
    _seed_start_here
    _seed_auth_file

    local out rc=0
    out="$(_run_ai_new codexproj --agent codex --boost "${_TMPDIR}/auth.json")" || rc=$?
    assert_success $rc "ai-new --boost should succeed for codex" || _fail=1
    assert_contains "Codex auth.json copied" "$out" || _fail=1

    local _bootstrap_auth="${_TMPDIR}/projects/codexproj/bootstrap/home/.codex/auth.json"
    local _state_auth="${_TMPDIR}/projects/codexproj/state/home/.codex/auth.json"
    [[ -f "$_bootstrap_auth" ]] || { printf '    bootstrap auth missing\n' >&2; _fail=1; }
    [[ -f "$_state_auth" ]] || { printf '    state auth missing\n' >&2; _fail=1; }

    local _src_size _bootstrap_size _state_size
    _src_size="$(stat -c '%s' "${_TMPDIR}/auth.json" 2>/dev/null || echo '')"
    _bootstrap_size="$(stat -c '%s' "$_bootstrap_auth" 2>/dev/null || echo '')"
    _state_size="$(stat -c '%s' "$_state_auth" 2>/dev/null || echo '')"
    assert_eq "$_src_size" "$_bootstrap_size" "bootstrap auth should match source size" || _fail=1
    assert_eq "$_src_size" "$_state_size" "state auth should match source size" || _fail=1

    local _mode
    _mode="$(stat -c '%a' "$_bootstrap_auth" 2>/dev/null || echo '')"
    assert_eq "600" "$_mode" "bootstrap auth should be mode 600" || _fail=1
    return $_fail
}

test_boost_rejected_for_non_codex_agent() {
    local _fail=0
    _seed_runtime_registry
    _seed_start_here
    _seed_auth_file

    local out rc=0
    out="$(_run_ai_new geminiproj --agent gemini --boost "${_TMPDIR}/auth.json")" || rc=$?
    assert_failure $rc "ai-new --boost should fail for non-Codex agents" || _fail=1
    assert_contains "codex" "$out" "error should mention codex restriction" || _fail=1
    return $_fail
}

test_boost_rejected_on_resume() {
    local _fail=0
    _seed_runtime_registry
    _seed_start_here
    _seed_auth_file

    mkdir -p "${_TMPDIR}/projects/existing/bootstrap"
    cat > "${_TMPDIR}/projects/existing/bootstrap/session.json" <<'EOF'
{"project_name":"existing","selected_agent":"codex","status":"interrupted"}
EOF

    local out rc=0
    out="$(_run_ai_new existing --resume --boost "${_TMPDIR}/auth.json")" || rc=$?
    assert_failure $rc "ai-new --boost should fail with --resume" || _fail=1
    assert_contains "resume" "$out" "error should mention resume restriction" || _fail=1
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "ai-new --boost copies auth into both homes"      test_boost_copies_auth_into_bootstrap_and_state
run_test "ai-new --boost rejected for non-Codex agent"      test_boost_rejected_for_non_codex_agent
run_test "ai-new --boost rejected with --resume"            test_boost_rejected_on_resume

print_summary "test_ai_new_boost"
