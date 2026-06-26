#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# 2026 - Anthony Burow - https://github.com/aburow
# T1a — start-here.sh lives under bootstrap/home, not at container root (AC1, B1).
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
AGENT_INSTALL_VERSION=""
AGENT_CONFIG_DIRS=".codex"
AGENT_ENV_VARS=""
AGENT_PROMPT_MODE="default"
AGENT_AUTH_CHECK_ARGV="codex|--version"
AEOF
    # create_scaffold looks for AI_PODMAN_JAILS_DIR/lib/start-here.sh and copies it.
    mkdir -p "${_TMPDIR}/lib"
    cp "${REPO_ROOT}/lib/start-here.sh" "${_TMPDIR}/lib/start-here.sh"
}

_run_create_scaffold() {
    local _name="$1"
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
project_paths '${_name}'
create_scaffold '${_name}'
SCRIPT
    bash "${_TMPDIR}/scaffold_helper.sh" 2>&1
}

# ── Tests ─────────────────────────────────────────────────────────────────────

test_scaffold_places_start_here_under_home() {
    local _fail=0
    _setup_agents
    local out rc=0
    out="$(_run_create_scaffold myproject)" || rc=$?
    assert_success $rc "create_scaffold should succeed" || _fail=1

    local _dst="${_TMPDIR}/projects/myproject/bootstrap/home/start-here.sh"
    [[ -f "$_dst" ]] || {
        printf '    start-here.sh not found at bootstrap/home/start-here.sh\n' >&2
        _fail=1
    }
    return $_fail
}

test_no_root_start_here_at_project_root() {
    local _fail=0
    _setup_agents
    _run_create_scaffold myproject2 >/dev/null 2>&1 || true

    local _root_copy="${_TMPDIR}/projects/myproject2/start-here.sh"
    [[ ! -f "$_root_copy" ]] || {
        printf '    start-here.sh found at project root (should only be under bootstrap/home/)\n' >&2
        _fail=1
    }
    return $_fail
}

test_no_root_bind_mount_in_launch_sh() {
    # B1: launch.sh must not contain the old root bind-mount for start-here.sh.
    local _fail=0
    local _launch="${REPO_ROOT}/lib/launch.sh"
    if grep -q ':/start-here.sh:ro' "$_launch" 2>/dev/null; then
        printf '    lib/launch.sh still contains root bind mount: :/start-here.sh:ro\n' >&2
        _fail=1
    fi
    if grep -q ':/start-here.sh:' "$_launch" 2>/dev/null; then
        printf '    lib/launch.sh still mounts start-here.sh at container root\n' >&2
        _fail=1
    fi
    return $_fail
}

test_launch_sh_banner_references_home_path() {
    # launch.sh info banner should tell users the home-dir path (B1).
    local _fail=0
    local _launch="${REPO_ROOT}/lib/launch.sh"
    if ! grep -q '/project/bootstrap/home/start-here.sh' "$_launch" 2>/dev/null; then
        printf '    lib/launch.sh banner does not reference home-dir start-here.sh path\n' >&2
        _fail=1
    fi
    return $_fail
}

test_lib_has_no_remaining_root_path_references() {
    # R1.3: no lib/ or bin/ file should reference /start-here.sh at root as an active mount.
    # We look for --volume patterns that reference the root path.
    local _fail=0
    local _found
    _found="$(grep -rn -- '--volume.*:/start-here.sh' "${REPO_ROOT}/lib/" "${REPO_ROOT}/bin/" 2>/dev/null || true)"
    if [[ -n "$_found" ]]; then
        printf '    root start-here.sh bind mount still referenced:\n%s\n' "$_found" >&2
        _fail=1
    fi
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "scaffold places start-here.sh under bootstrap/home"    test_scaffold_places_start_here_under_home
run_test "start-here.sh is NOT at project root"                  test_no_root_start_here_at_project_root
run_test "lib/launch.sh has no root bind mount for start-here.sh" test_no_root_bind_mount_in_launch_sh
run_test "lib/launch.sh banner references home-dir path"         test_launch_sh_banner_references_home_path
run_test "no --volume :/start-here.sh in lib/ or bin/"           test_lib_has_no_remaining_root_path_references

print_summary "test_start_here_location"
