#!/usr/bin/env bash
# T1c — start-here.sh location & executability verified inside the bootstrap container (AC1, AC2).
# Tagged slow: skipped unless PODMAN_LIVE=1 and rootless podman is available.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

_BOOTSTRAP_IMAGE="localhost/ai-new/bootstrap:latest"

# ── Helpers ───────────────────────────────────────────────────────────────────

_ensure_image_or_skip() {
    if ! podman image exists "$_BOOTSTRAP_IMAGE" 2>/dev/null; then
        _SKIP_REASON="bootstrap image not present — build it with 'ai-new <name>' first"
        return 0
    fi
    return 1  # do not skip
}

_setup_project_with_start_here() {
    local _proj="$1"
    mkdir -p "${_proj}/bootstrap/home"
    cp "${REPO_ROOT}/start-here.sh" "${_proj}/bootstrap/home/start-here.sh"
    chmod +x "${_proj}/bootstrap/home/start-here.sh"
    cat > "${_proj}/bootstrap/agent.env" <<'AEOF'
AGENT_REGISTRY_VERSION="1"
AGENT_NAME="codex"
AGENT_COMMAND="true"
AGENT_INSTALL_ADAPTER="preinstalled"
AGENT_INSTALL_PACKAGE=""
AGENT_INSTALL_VERSION=""
AGENT_CONFIG_DIRS=""
AGENT_ENV_VARS=""
AGENT_PROMPT_MODE="default"
AGENT_AUTH_CHECK_ARGV=""
AEOF
}

_run_in_container() {
    local _proj="$1" _container="$2"
    shift 2
    local _cmd=("$@")
    podman run --rm \
        --name "$_container" \
        --userns=keep-id \
        --volume "${_proj}:/project:z" \
        --env "HOME=/project/bootstrap/home" \
        --workdir /project \
        --network none \
        "$_BOOTSTRAP_IMAGE" \
        bash -c "${_cmd[*]}" 2>&1
}

# ── Tests ─────────────────────────────────────────────────────────────────────

test_container_start_here_at_home_path() {
    if skip_unless_live; then return 0; fi
    if _ensure_image_or_skip; then return 0; fi

    local _fail=0
    local _proj="${_TMPDIR}/projects/loc_test"
    _setup_project_with_start_here "$_proj"

    local out rc=0
    out="$(_run_in_container "$_proj" "ai-new-loc-$$" "find /project -name start-here.sh 2>/dev/null")" || rc=$?
    assert_success $rc "find in container should exit 0" || _fail=1
    assert_contains "/project/bootstrap/home/start-here.sh" "$out" "start-here.sh must be under home" || _fail=1
    assert_not_contains "/start-here.sh" "$(echo "$out" | grep -v '/project')" \
        "start-here.sh must NOT appear at container root" || _fail=1
    return $_fail
}

test_container_start_here_executable() {
    if skip_unless_live; then return 0; fi
    if _ensure_image_or_skip; then return 0; fi

    local _fail=0
    local _proj="${_TMPDIR}/projects/exec_test"
    _setup_project_with_start_here "$_proj"

    local rc=0
    _run_in_container "$_proj" "ai-new-exec-$$" \
        "test -x /project/bootstrap/home/start-here.sh" >/dev/null 2>&1 || rc=$?
    assert_success $rc "start-here.sh must be executable inside the container" || _fail=1
    return $_fail
}

test_container_start_here_runs_without_bash_prefix() {
    if skip_unless_live; then return 0; fi
    if _ensure_image_or_skip; then return 0; fi

    local _fail=0
    local _proj="${_TMPDIR}/projects/run_test"
    _setup_project_with_start_here "$_proj"

    # Run start-here.sh with --help — exits 0 and prints usage without needing 'bash' prefix.
    local out rc=0
    out="$(_run_in_container "$_proj" "ai-new-run-$$" \
        "/project/bootstrap/home/start-here.sh --help 2>&1")" || rc=$?
    # Note: --help may fail without the /start-here-lib mount, but the key test is the
    # execute permission (not EACCES / permission denied).
    if echo "$out" | grep -qi "permission denied"; then
        printf '    Got "permission denied" — execute bit not set in container\n' >&2
        _fail=1
    fi
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "[slow] start-here.sh found under home in container"          test_container_start_here_at_home_path
run_test "[slow] start-here.sh is executable inside container"         test_container_start_here_executable
run_test "[slow] start-here.sh runs without bash prefix in container"  test_container_start_here_runs_without_bash_prefix

print_summary "test_start_here_in_container"
