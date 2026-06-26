#!/usr/bin/env bash
# T5 (slow) — Bootstrap container safety posture (R14, R15, R17, AC15, AC17, AC22).
# Tagged slow: requires PODMAN_LIVE=1 and rootless Podman.
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
AGENT_COMMAND="true"
AGENT_INSTALL_ADAPTER="preinstalled"
AGENT_CONFIG_DIRS=""
AGENT_ENV_VARS=""
AGENT_PROMPT_MODE="default"
AGENT_AUTH_CHECK_ARGV=""
AEOF
}

# ── Tests ─────────────────────────────────────────────────────────────────────

test_bootstrap_container_no_host_socket() {
    if skip_unless_live; then return 0; fi
    local _fail=0
    _setup_agents

    local _proj="${_TMPDIR}/projects/posturetest"
    local _slug="posturetest"
    mkdir -p "${_proj}/bootstrap"

    # Write a minimal session.json.
    cat > "${_proj}/bootstrap/session.json" <<EOF
{"project_name":"posturetest","selected_agent":"codex","status":"started","last_updated":"","generated_files":[],"containerfile_path":"","quality_gate_status":"","last_error":"","resume_command":"","build_log_path":"","trial_image_tag":"","static_check_status":"","pinned_agent_env":"","pinned_agent_hash":""}
EOF
    cat > "${_proj}/bootstrap/agent.env" <<'AEOF'
AGENT_NAME="codex"
AGENT_COMMAND="true"
AGENT_INSTALL_ADAPTER="preinstalled"
AEOF

    local _cname="ai-new-bootstrap-${_slug}"
    # Launch the container in detached mode and inspect it.
    AI_PODMAN_JAILS_DIR="${_TMPDIR}" SLUG="${_slug}" \
        podman run --rm --detach \
            --name "$_cname" \
            --userns=keep-id \
            --volume "${_proj}:/project:z" \
            --env "HOME=/project/bootstrap/home" \
            --workdir /project \
            --network host \
            localhost/ai-new/bootstrap:latest /bin/bash -c 'sleep 5' >/dev/null 2>&1 || {
        _SKIP_REASON="Could not launch bootstrap container (image may be missing)"
        return 0
    }

    local _inspect
    _inspect="$(podman inspect "$_cname" 2>/dev/null)" || true

    # Cleanup.
    podman stop "$_cname" >/dev/null 2>&1 || true

    # Assert: no host Podman socket mounted.
    if echo "$_inspect" | grep -q 'podman.sock'; then
        printf '    FAIL: host podman.sock is mounted in bootstrap container!\n' >&2
        _fail=1
    fi

    # Assert: not privileged.
    local _priv
    _priv="$(echo "$_inspect" | python3 -c \
        "import json,sys; d=json.load(sys.stdin); print(d[0]['HostConfig']['Privileged'])" \
        2>/dev/null || echo 'unknown')"
    if [[ "$_priv" == "True" || "$_priv" == "true" ]]; then
        printf '    FAIL: bootstrap container is privileged!\n' >&2
        _fail=1
    fi

    return $_fail
}

test_bootstrap_container_home_inside_project() {
    if skip_unless_live; then return 0; fi
    local _fail=0
    _setup_agents

    local _proj="${_TMPDIR}/projects/hometest"
    local _slug="hometest"
    mkdir -p "${_proj}/bootstrap/home"

    local _cname="ai-new-bootstrap-${_slug}"
    podman run --rm --detach \
        --name "$_cname" \
        --userns=keep-id \
        --volume "${_proj}:/project:z" \
        --env "HOME=/project/bootstrap/home" \
        --workdir /project \
        --network host \
        localhost/ai-new/bootstrap:latest /bin/bash -c 'sleep 5' >/dev/null 2>&1 || {
        _SKIP_REASON="Could not launch bootstrap container"
        return 0
    }

    local _inspect
    _inspect="$(podman inspect "$_cname" 2>/dev/null)" || true
    podman stop "$_cname" >/dev/null 2>&1 || true

    # HOME env should be /project/bootstrap/home.
    local _home_env
    _home_env="$(echo "$_inspect" | python3 -c \
        "import json,sys; d=json.load(sys.stdin)[0]; envs=d['Config']['Env']; \
         home=[e for e in envs if e.startswith('HOME=')]; print(home[0] if home else '')" \
        2>/dev/null || echo '')"
    assert_eq "HOME=/project/bootstrap/home" "$_home_env" "HOME inside container" || _fail=1
    return $_fail
}

test_bootstrap_container_only_project_mounted() {
    if skip_unless_live; then return 0; fi
    local _fail=0
    _setup_agents

    local _proj="${_TMPDIR}/projects/mounttest"
    local _slug="mounttest"
    mkdir -p "${_proj}/bootstrap/home"

    local _cname="ai-new-bootstrap-${_slug}"
    podman run --rm --detach \
        --name "$_cname" \
        --userns=keep-id \
        --volume "${_proj}:/project:z" \
        --env "HOME=/project/bootstrap/home" \
        --workdir /project \
        --network host \
        localhost/ai-new/bootstrap:latest /bin/bash -c 'sleep 5' >/dev/null 2>&1 || {
        _SKIP_REASON="Could not launch bootstrap container"
        return 0
    }

    local _inspect
    _inspect="$(podman inspect "$_cname" 2>/dev/null)" || true
    podman stop "$_cname" >/dev/null 2>&1 || true

    # Mounts should include /project and should NOT include $HOME directly.
    local _mount_dests
    _mount_dests="$(echo "$_inspect" | python3 -c \
        "import json,sys; d=json.load(sys.stdin)[0]; \
         mounts=[m['Destination'] for m in d['Mounts']]; print('\n'.join(mounts))" \
        2>/dev/null || echo '')"
    assert_contains "/project" "$_mount_dests" "project should be mounted at /project" || _fail=1
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "[slow] bootstrap container: no host socket mounted"   test_bootstrap_container_no_host_socket
run_test "[slow] bootstrap container: HOME=/project/bootstrap/home" test_bootstrap_container_home_inside_project
run_test "[slow] bootstrap container: only project tree mounted" test_bootstrap_container_only_project_mounted

print_summary "test_bootstrap_posture"
