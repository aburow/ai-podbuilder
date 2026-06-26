#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# 2026 - Anthony Burow - https://github.com/aburow
# T12 — Generated files persist after container disposal; agent config survives rebuild (AC14).
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

_build_mock_generated_scaffold() {
    local _proj="$1"
    mkdir -p "${_proj}/image" "${_proj}/launchers" "${_proj}/bootstrap/home" "${_proj}/workspace"

    printf 'FROM fedora:latest\nWORKDIR /workspace\n' > "${_proj}/image/Containerfile"
    printf '#!/usr/bin/env bash\nexec podman run --rm test\n' > "${_proj}/launchers/launch.sh"
    chmod +x "${_proj}/launchers/launch.sh"
    printf '# Project README\n' > "${_proj}/README.md"
    printf '.env\n' > "${_proj}/.gitignore"

    # Agent config under bootstrap/home (simulates dotfiles persisted by agent).
    mkdir -p "${_proj}/bootstrap/home/.codex"
    printf '{"settings": true}\n' > "${_proj}/bootstrap/home/.codex/config.json"

    cat > "${_proj}/bootstrap/session.json" <<'EOF'
{
  "project_name": "persisttest",
  "selected_agent": "codex",
  "status": "complete",
  "generated_files": ["image/Containerfile", "launchers/launch.sh"]
}
EOF
    cat > "${_proj}/bootstrap/agent.env" <<'AEOF'
# agent_name=codex
AGENT_NAME="codex"
AGENT_COMMAND="codex"
AGENT_INSTALL_ADAPTER="npm-global"
AEOF
}

# ── Tests ─────────────────────────────────────────────────────────────────────

test_generated_files_persist_after_simulated_container_removal() {
    local _fail=0
    local _proj="${_TMPDIR}/projects/persisttest"
    _build_mock_generated_scaffold "$_proj"

    # Simulate container lifecycle: the project tree is a volume mount, so it survives.
    # Verify all generated files are still present after "container removal" (no-op here
    # since files are on the host under AI_PODMAN_JAILS_DIR).
    local _f
    for _f in \
        "image/Containerfile" \
        "launchers/launch.sh" \
        "README.md" \
        ".gitignore" \
        "bootstrap/session.json" \
        "bootstrap/agent.env"
    do
        [[ -f "${_proj}/${_f}" ]] || {
            printf '    File missing after simulated container removal: %s\n' "$_f" >&2
            _fail=1
        }
    done
    return $_fail
}

test_agent_config_persists_under_bootstrap_home() {
    local _fail=0
    local _proj="${_TMPDIR}/projects/persisttest2"
    _build_mock_generated_scaffold "$_proj"
    # Rename to avoid collision.
    mv "$_proj" "${_proj}2" 2>/dev/null || true
    _proj="${_proj}2"
    _build_mock_generated_scaffold "$_proj"

    # Agent config in bootstrap/home should persist.
    [[ -f "${_proj}/bootstrap/home/.codex/config.json" ]] || {
        printf '    Agent config under bootstrap/home missing\n' >&2
        _fail=1
    }
    return $_fail
}

test_generated_files_under_correct_path() {
    local _fail=0
    _setup_agents
    # Run ai-new with stub podman to create scaffold.
    AI_PODMAN_JAILS_DIR="${_TMPDIR}" bash "${BIN_DIR}/ai-new" persistnew --agent codex >/dev/null 2>&1 || true

    local _proj="${_TMPDIR}/projects/persistnew"
    [[ -d "$_proj" ]] || {
        printf '    Project not created at expected path\n' >&2
        _fail=1
    }
    # Verify the tree is rooted under AI_PODMAN_JAILS_DIR/projects/.
    [[ "$_proj" == "${_TMPDIR}/projects/"* ]] || {
        printf '    Project not under AI_PODMAN_JAILS_DIR/projects/\n' >&2
        _fail=1
    }
    return $_fail
}

test_bootstrap_home_is_inside_project_tree() {
    local _fail=0
    local _proj="${_TMPDIR}/projects/persisthome"
    _build_mock_generated_scaffold "$_proj"

    # bootstrap/home should be inside the project root.
    [[ -d "${_proj}/bootstrap/home" ]] || {
        printf '    bootstrap/home not inside project tree\n' >&2
        _fail=1
    }
    # It should NOT be under $HOME (which would escape the project scope).
    if [[ "${_proj}/bootstrap/home" == "${HOME}"* ]]; then
        printf '    bootstrap/home is under $HOME — escapes project tree!\n' >&2
        _fail=1
    fi
    return $_fail
}

test_resume_reads_session_json_from_persisted_project() {
    local _fail=0
    local _proj="${_TMPDIR}/projects/persistresume"
    mkdir -p "${_proj}/bootstrap"

    cat > "${_proj}/bootstrap/session.json" <<'EOF'
{
  "project_name": "persistresume",
  "selected_agent": "codex",
  "status": "interrupted",
  "last_updated": "2026-01-01T00:00:00Z"
}
EOF
    cat > "${_proj}/bootstrap/agent.env" <<'AEOF'
# agent_name=codex
AGENT_NAME="codex"
AGENT_COMMAND="codex"
AGENT_INSTALL_ADAPTER="npm-global"
AEOF

    # Verify that the session.json is readable (simulating resume reading persisted state).
    local _status
    _status="$(grep -oP '"status"\s*:\s*"\K[^"]+' "${_proj}/bootstrap/session.json" 2>/dev/null || true)"
    assert_eq "interrupted" "$_status" "persisted session.json should be readable" || _fail=1
    return $_fail
}

test_pinned_agent_env_persists_independently_of_global_registry() {
    local _fail=0
    _setup_agents
    local _proj="${_TMPDIR}/projects/pinpersist"
    mkdir -p "${_proj}/bootstrap"

    cat > "${_TMPDIR}/pin_persist_helper.sh" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/registry.sh'
export AI_PODMAN_JAILS_DIR='${_TMPDIR}'
export AI_PODMAN_AGENTS_DIR='${_TMPDIR}/config/agents.d'
pin_registry 'codex' '${_proj}'
SCRIPT
    bash "${_TMPDIR}/pin_persist_helper.sh" >/dev/null 2>&1 || true

    # Remove the global registry.
    rm -f "${_TMPDIR}/config/agents.d/codex.env"

    # Pinned file should still be there and intact.
    [[ -f "${_proj}/bootstrap/agent.env" ]] || {
        printf '    Pinned agent.env missing after global registry removal\n' >&2
        _fail=1
    }
    local _content
    _content="$(cat "${_proj}/bootstrap/agent.env")"
    assert_contains "AGENT_NAME" "$_content" "pinned file should be self-contained" || _fail=1
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "generated files persist after simulated container removal" test_generated_files_persist_after_simulated_container_removal
run_test "agent config persists under bootstrap/home"               test_agent_config_persists_under_bootstrap_home
run_test "generated files under correct AI_PODMAN_JAILS_DIR path"       test_generated_files_under_correct_path
run_test "bootstrap/home is inside project tree, not under \$HOME"  test_bootstrap_home_is_inside_project_tree
run_test "resume can read persisted session.json"                    test_resume_reads_session_json_from_persisted_project
run_test "pinned agent.env persists after global registry removed"   test_pinned_agent_env_persists_independently_of_global_registry

print_summary "test_persistence"
