#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# 2026 - Anthony Burow - https://github.com/aburow
# T3 — Registry pinning: copies entry with provenance metadata; resume survives global removal (AC21).
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

_pin_helper() {
    local _agent="$1"
    local _proj="$2"
    cat > "${_TMPDIR}/pin_helper.sh" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/registry.sh'
export AI_PODMAN_JAILS_DIR='${_TMPDIR}'
export AI_PODMAN_AGENTS_DIR='${_TMPDIR}/config/agents.d'
pin_registry '${_agent}' '${_proj}'
SCRIPT
    bash "${_TMPDIR}/pin_helper.sh" 2>&1
}

# ── Tests ─────────────────────────────────────────────────────────────────────

test_pin_creates_agent_env_file() {
    local _fail=0
    _setup_agents
    local _proj="${_TMPDIR}/projects/myproject"
    mkdir -p "${_proj}/bootstrap"

    local out rc=0
    out="$(_pin_helper codex "$_proj")" || rc=$?
    assert_success $rc "pin_registry should succeed" || _fail=1
    [[ -f "${_proj}/bootstrap/agent.env" ]] || {
        printf '    bootstrap/agent.env not created\n' >&2
        _fail=1
    }
    return $_fail
}

test_pin_includes_source_path() {
    local _fail=0
    _setup_agents
    local _proj="${_TMPDIR}/projects/pintest"
    mkdir -p "${_proj}/bootstrap"

    _pin_helper codex "$_proj" >/dev/null 2>&1 || true
    local _dst="${_proj}/bootstrap/agent.env"
    [[ -f "$_dst" ]] || { printf '    agent.env missing\n' >&2; return 1; }

    local _content
    _content="$(cat "$_dst")"
    assert_contains "source_path=" "$_content" "should include source_path" || _fail=1
    assert_contains "agent_name=codex" "$_content" "should include agent_name" || _fail=1
    return $_fail
}

test_pin_includes_hash() {
    local _fail=0
    _setup_agents
    local _proj="${_TMPDIR}/projects/hashtest"
    mkdir -p "${_proj}/bootstrap"

    _pin_helper codex "$_proj" >/dev/null 2>&1 || true
    local _content
    _content="$(cat "${_proj}/bootstrap/agent.env")"
    assert_contains "source_hash=" "$_content" "should include source_hash" || _fail=1
    # Hash should look like a sha256 hex string (64 chars).
    local _hash
    _hash="$(grep "source_hash=" "${_proj}/bootstrap/agent.env" | cut -d= -f2)"
    [[ "${#_hash}" -eq 64 ]] || {
        printf '    source_hash length %d != 64 (not a sha256?): %s\n' "${#_hash}" "$_hash" >&2
        _fail=1
    }
    return $_fail
}

test_pin_includes_timestamp() {
    local _fail=0
    _setup_agents
    local _proj="${_TMPDIR}/projects/tstest"
    mkdir -p "${_proj}/bootstrap"

    _pin_helper codex "$_proj" >/dev/null 2>&1 || true
    local _content
    _content="$(cat "${_proj}/bootstrap/agent.env")"
    assert_contains "pinned_at=" "$_content" "should include pinned_at timestamp" || _fail=1
    return $_fail
}

test_pin_includes_original_registry_content() {
    local _fail=0
    _setup_agents
    local _proj="${_TMPDIR}/projects/contenttest"
    mkdir -p "${_proj}/bootstrap"

    _pin_helper codex "$_proj" >/dev/null 2>&1 || true
    local _content
    _content="$(cat "${_proj}/bootstrap/agent.env")"
    # The original registry content should be present.
    assert_contains "AGENT_NAME" "$_content" "original content should be in pinned file" || _fail=1
    assert_contains "AGENT_INSTALL_ADAPTER" "$_content" || _fail=1
    return $_fail
}

test_pin_uses_tmp_plus_rename_atomicity() {
    local _fail=0
    _setup_agents
    local _proj="${_TMPDIR}/projects/atomictest"
    mkdir -p "${_proj}/bootstrap"

    _pin_helper codex "$_proj" >/dev/null 2>&1 || true
    # No .tmp file should remain.
    [[ ! -f "${_proj}/bootstrap/agent.env.tmp" ]] || {
        printf '    .tmp file left behind after pin_registry\n' >&2
        _fail=1
    }
    return $_fail
}

test_resume_works_after_global_registry_removed() {
    local _fail=0
    _setup_agents
    local _proj="${_TMPDIR}/projects/resumepin"
    mkdir -p "${_proj}/bootstrap"

    # Pin the registry entry.
    _pin_helper codex "$_proj" >/dev/null 2>&1 || true

    # Remove the global registry entry.
    rm -f "${_TMPDIR}/config/agents.d/codex.env"

    # The pinned file should still be readable and contain the full content.
    local _pinned="${_proj}/bootstrap/agent.env"
    [[ -f "$_pinned" ]] || {
        printf '    Pinned agent.env is missing\n' >&2
        return 1
    }
    local _content
    _content="$(cat "$_pinned")"
    assert_contains "AGENT_NAME" "$_content" "pinned file should be self-contained" || _fail=1
    assert_contains "source_hash=" "$_content" "pinned file should have hash" || _fail=1
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "pin_registry creates bootstrap/agent.env"            test_pin_creates_agent_env_file
run_test "pinned file includes source_path and agent_name"     test_pin_includes_source_path
run_test "pinned file includes 64-char sha256 source_hash"     test_pin_includes_hash
run_test "pinned file includes pinned_at timestamp"            test_pin_includes_timestamp
run_test "pinned file includes original registry content"      test_pin_includes_original_registry_content
run_test "no .tmp file left after atomic rename"               test_pin_uses_tmp_plus_rename_atomicity
run_test "resume reads pinned file after global registry removed" test_resume_works_after_global_registry_removed

print_summary "test_pinning"
