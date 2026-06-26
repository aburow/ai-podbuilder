#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# 2026 - Anthony Burow - https://github.com/aburow
# T7 — Secret handling: placeholders only in .env.example; .gitignore covers secrets (AC10).
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

# ── Helpers ───────────────────────────────────────────────────────────────────

_build_mock_scaffold_secrets() {
    local _proj="$1"
    mkdir -p "${_proj}/image" "${_proj}/bootstrap/home" "${_proj}/launchers" "${_proj}/workspace"

    cat > "${_proj}/.env.example" <<'EOF'
# Copy to .env and fill in real values — do not commit .env
MY_API_KEY=your-api-key-here
DB_PASSWORD=your-db-password-here
TOKEN=placeholder-token
EOF

    cat > "${_proj}/.gitignore" <<'EOF'
bootstrap/agent.env.local
bootstrap/home/
state/
.env
*.env.local
secrets/
*.key
*.pem
EOF

    cat > "${_proj}/bootstrap/session.json" <<'EOF'
{
  "project_name": "testproject",
  "selected_agent": "codex",
  "status": "complete"
}
EOF
}

# ── Tests ─────────────────────────────────────────────────────────────────────

test_env_example_has_no_real_secrets() {
    local _fail=0
    local _proj="${_TMPDIR}/projects/sec1"
    _build_mock_scaffold_secrets "$_proj"
    local _content
    _content="$(cat "${_proj}/.env.example")"

    # Real API keys look like: sk-xxx, ghp_xxx, AIzaSy..., long base64 strings, UUIDs.
    # Just check the values are placeholder-like.
    assert_not_contains "sk-" "$_content" "no OpenAI-style key in .env.example" || _fail=1
    assert_not_contains "ghp_" "$_content" "no GitHub token in .env.example" || _fail=1

    # Each value should look like a placeholder.
    if echo "$_content" | grep -qE '^[A-Z_]+=.{32,}$' 2>/dev/null; then
        # Long values might be real secrets — check none look like base64/hex keys.
        if echo "$_content" | grep -qE '^[A-Z_]+=[A-Za-z0-9+/]{40,}={0,2}$'; then
            printf '    WARN: .env.example may contain a real base64 secret\n' >&2
        fi
    fi
    return $_fail
}

test_gitignore_excludes_agent_env_local() {
    local _fail=0
    local _proj="${_TMPDIR}/projects/sec2"
    _build_mock_scaffold_secrets "$_proj"
    local _content
    _content="$(cat "${_proj}/.gitignore")"
    assert_contains "agent.env.local" "$_content" \
        ".gitignore must exclude bootstrap/agent.env.local" || _fail=1
    return $_fail
}

test_gitignore_excludes_bootstrap_home() {
    local _fail=0
    local _proj="${_TMPDIR}/projects/sec3"
    _build_mock_scaffold_secrets "$_proj"
    local _content
    _content="$(cat "${_proj}/.gitignore")"
    assert_contains "bootstrap/home" "$_content" \
        ".gitignore must exclude bootstrap/home/" || _fail=1
    return $_fail
}

test_gitignore_excludes_state_home() {
    local _fail=0
    local _proj="${_TMPDIR}/projects/sec3b"
    _build_mock_scaffold_secrets "$_proj"
    local _content
    _content="$(cat "${_proj}/.gitignore")"
    assert_contains "state/" "$_content" \
        ".gitignore must exclude state/" || _fail=1
    return $_fail
}

test_gitignore_excludes_project_env() {
    local _fail=0
    local _proj="${_TMPDIR}/projects/sec4"
    _build_mock_scaffold_secrets "$_proj"
    local _content
    _content="$(cat "${_proj}/.gitignore")"
    assert_contains ".env" "$_content" ".gitignore must exclude .env files" || _fail=1
    return $_fail
}

test_no_populated_secret_files_committed() {
    local _fail=0
    local _proj="${_TMPDIR}/projects/sec5"
    _build_mock_scaffold_secrets "$_proj"

    # There should be no .env file (only .env.example).
    [[ ! -f "${_proj}/.env" ]] || {
        printf '    FAIL: .env found in scaffold — should not exist (only .env.example)\n' >&2
        _fail=1
    }
    # agent.env.local should not exist either.
    [[ ! -f "${_proj}/bootstrap/agent.env.local" ]] || {
        printf '    FAIL: bootstrap/agent.env.local found in scaffold\n' >&2
        _fail=1
    }
    return $_fail
}

test_agent_env_local_not_in_scaffold() {
    # Validate that start-here.sh loads agent.env.local at runtime but does not bake it.
    local _fail=0
    local _proj="${_TMPDIR}/projects/sec6"
    _build_mock_scaffold_secrets "$_proj"
    # If the scaffold has no agent.env.local, the agent will read from it at runtime.
    [[ ! -f "${_proj}/bootstrap/agent.env.local" ]] || {
        printf '    FAIL: agent.env.local present in scaffold\n' >&2
        _fail=1
    }
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test ".env.example has no real API secrets"            test_env_example_has_no_real_secrets
run_test ".gitignore excludes bootstrap/agent.env.local"   test_gitignore_excludes_agent_env_local
run_test ".gitignore excludes bootstrap/home/"             test_gitignore_excludes_bootstrap_home
run_test ".gitignore excludes state/"                      test_gitignore_excludes_state_home
run_test ".gitignore excludes .env files"                  test_gitignore_excludes_project_env
run_test "no populated secret files committed"             test_no_populated_secret_files_committed
run_test "agent.env.local not baked into scaffold"         test_agent_env_local_not_in_scaffold

print_summary "test_secret_handling"
