#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# 2026 - Anthony Burow - https://github.com/aburow
# T4 — Scaffold layout creation (R2.2, AC3).
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
    # Stub start-here.sh required by create_scaffold (B1).
    mkdir -p "${_TMPDIR}/lib"
    printf '#!/usr/bin/env bash\n# stub\n' > "${_TMPDIR}/lib/start-here.sh"
    chmod +x "${_TMPDIR}/lib/start-here.sh"
}

_run_ai_new_create() {
    local _name="$1"
    # Do NOT use command substitution ($()) here — the heartbeat background job in
    # ai-new keeps the process group alive indefinitely inside $().
    AI_PODMAN_JAILS_DIR="${_TMPDIR}" bash "${BIN_DIR}/ai-new" "$_name" --agent codex >/dev/null 2>&1 || true
}

_scaffold_layout_helper() {
    local _proj="$1"
    cat > "${_TMPDIR}/scaffold_helper.sh" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/registry.sh'
source '${LIB_DIR}/slug.sh'
source '${LIB_DIR}/session.sh'
source '${LIB_DIR}/scaffold.sh'
export AI_PODMAN_JAILS_DIR='${_TMPDIR}'
export AI_PODMAN_AGENTS_DIR='${_TMPDIR}/config/agents.d'
project_paths 'myproject'
create_scaffold 'myproject'
SCRIPT
    bash "${_TMPDIR}/scaffold_helper.sh" 2>&1
}

# ── Tests ─────────────────────────────────────────────────────────────────────

test_scaffold_directories_created() {
    local _fail=0
    _setup_agents
    local out rc=0
    out="$(_scaffold_layout_helper "${_TMPDIR}/projects/myproject")" || rc=$?
    assert_success $rc "create_scaffold should succeed" || _fail=1

    local _root="${_TMPDIR}/projects/myproject"
    local _d
    for _d in workspace image launchers bootstrap "bootstrap/home"; do
        [[ -d "${_root}/${_d}" ]] || {
            printf '    Missing directory: %s\n' "$_d" >&2
            _fail=1
        }
    done
    return $_fail
}

test_scaffold_profile_env_created() {
    local _fail=0
    _setup_agents
    _scaffold_layout_helper "${_TMPDIR}/projects/myproject" >/dev/null 2>&1 || true
    [[ -f "${_TMPDIR}/projects/myproject/profile.env" ]] || {
        printf '    profile.env not created\n' >&2
        _fail=1
    }
    return $_fail
}

test_scaffold_readme_created() {
    local _fail=0
    _setup_agents
    _scaffold_layout_helper "${_TMPDIR}/projects/myproject" >/dev/null 2>&1 || true
    [[ -f "${_TMPDIR}/projects/myproject/README.md" ]] || {
        printf '    README.md not created\n' >&2
        _fail=1
    }
    return $_fail
}

test_scaffold_layout_via_ai_new() {
    local _fail=0
    _setup_agents
    # Run the full ai-new command with stub podman; scaffold is created before exec.
    _run_ai_new_create "layouttest"

    local _root="${_TMPDIR}/projects/layouttest"
    local _d
    for _d in workspace image launchers bootstrap "bootstrap/home"; do
        [[ -d "${_root}/${_d}" ]] || {
            printf '    ai-new: Missing directory: %s\n' "$_d" >&2
            _fail=1
        }
    done
    return $_fail
}

test_scaffold_under_correct_jails_dir() {
    local _fail=0
    _setup_agents
    _run_ai_new_create "jailstest" >/dev/null 2>&1 || true
    # Project should be under $AI_PODMAN_JAILS_DIR/projects/
    [[ -d "${_TMPDIR}/projects/jailstest" ]] || {
        printf '    Project not found under AI_PODMAN_JAILS_DIR/projects/\n' >&2
        _fail=1
    }
    # Should NOT be under $HOME/ai-podman-jails (which is the default without AI_PODMAN_JAILS_DIR set).
    if [[ -d "${HOME}/ai-podman-jails/projects/jailstest" ]]; then
        printf '    WARN: project found under $HOME/ai-podman-jails — possible isolation issue\n' >&2
    fi
    return $_fail
}

test_scaffold_slug_index_registered() {
    local _fail=0
    _setup_agents
    _scaffold_layout_helper "${_TMPDIR}/projects/myproject" >/dev/null 2>&1 || true
    local _db="${_TMPDIR}/config/slug-index.tsv"
    [[ -f "$_db" ]] || {
        printf '    slug-index.tsv not created\n' >&2
        _fail=1
    }
    grep -q "myproject" "$_db" 2>/dev/null || {
        printf '    myproject not registered in slug-index.tsv\n' >&2
        _fail=1
    }
    return $_fail
}

test_scaffold_does_not_create_profiles_mirror() {
    local _fail=0
    _setup_agents
    _scaffold_layout_helper "${_TMPDIR}/projects/myproject" >/dev/null 2>&1 || true
    # Scaffold must not write a profiles/<slug>.env mirror (R2.4)
    local _mirror
    shopt -s nullglob
    for _mirror in "${_TMPDIR}/profiles"/*.env; do
        # Seed profiles are already in place from setup; only flag new ones.
        case "$(basename "$_mirror")" in
            esp32.env|uxplay.env) continue ;;
        esac
        printf '    Unexpected mirror created: %s\n' "$_mirror" >&2
        _fail=1
    done
    shopt -u nullglob
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "scaffold directories all created"              test_scaffold_directories_created
run_test "profile.env created by scaffold"               test_scaffold_profile_env_created
run_test "README.md created by scaffold"                 test_scaffold_readme_created
run_test "ai-new creates correct layout under AI_PODMAN_JAILS_DIR" test_scaffold_layout_via_ai_new
run_test "project placed under AI_PODMAN_JAILS_DIR/projects/" test_scaffold_under_correct_jails_dir
run_test "slug registered in slug-index.tsv"             test_scaffold_slug_index_registered
run_test "scaffold does not create profiles/ mirror (R2.4)" test_scaffold_does_not_create_profiles_mirror

print_summary "test_scaffold_layout"
