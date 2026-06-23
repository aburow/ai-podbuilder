#!/usr/bin/env bash
# T2e — after start-here.sh install step, agent command resolves on $PATH inside the container (AC3).
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
    return 1
}

_setup_fake_npm_in_project() {
    # Place a fake npm into the project home's npm-global/bin so the install step
    # "succeeds": it records calls but also drops a stub binary onto PATH.
    local _proj="$1" _cmd="$2" _pkg="$3"
    local _npm_global="${_proj}/bootstrap/home/.npm-global"
    local _bin_dir="${_npm_global}/bin"
    mkdir -p "$_bin_dir"

    # Fake npm: writes argv to a log and creates a stub binary for the command.
    cat > "${_npm_global}/npm" <<FAKE_NPM
#!/bin/sh
echo "\$@" >> /project/bootstrap/npm_calls.txt
# On 'install -g <pkg>', drop a stub binary for the expected command.
mkdir -p /project/bootstrap/home/.npm-global/bin
printf '#!/bin/sh\nexit 0\n' > /project/bootstrap/home/.npm-global/bin/${_cmd}
chmod +x /project/bootstrap/home/.npm-global/bin/${_cmd}
exit 0
FAKE_NPM
    chmod +x "${_npm_global}/npm"

    # Write an agent.env for the project.
    mkdir -p "${_proj}/bootstrap"
    cat > "${_proj}/bootstrap/agent.env" <<AEOF
AGENT_REGISTRY_VERSION="1"
AGENT_NAME="${_cmd}"
AGENT_COMMAND="${_cmd}"
AGENT_INSTALL_ADAPTER="npm-global"
AGENT_INSTALL_PACKAGE="${_pkg}"
AGENT_INSTALL_VERSION=""
AGENT_CONFIG_DIRS=""
AGENT_ENV_VARS=""
AGENT_PROMPT_MODE="default"
AGENT_AUTH_CHECK_ARGV=""
AEOF

    # Copy start-here.sh into the project home.
    mkdir -p "${_proj}/bootstrap/home"
    cp "${REPO_ROOT}/start-here.sh" "${_proj}/bootstrap/home/start-here.sh"
    chmod +x "${_proj}/bootstrap/home/start-here.sh"
}

_run_install_step_in_container() {
    local _proj="$1" _cmd="$2" _container="$3"
    # Add our fake npm to PATH inside the container by prepending the mount path.
    podman run --rm \
        --name "$_container" \
        --userns=keep-id \
        --volume "${_proj}:/project:z" \
        --volume "${REPO_ROOT}/lib:/start-here-lib:ro,z" \
        --env "HOME=/project/bootstrap/home" \
        --env "PATH=/project/bootstrap/home/.npm-global/bin:/project/bootstrap/home/.npm-global:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
        --workdir /project \
        --network none \
        "$_BOOTSTRAP_IMAGE" \
        bash -c "
            /project/bootstrap/home/start-here.sh 2>&1 || true
            echo 'POST_INSTALL_RESOLVE:'
            command -v ${_cmd} 2>/dev/null && echo FOUND || echo NOT_FOUND
        " 2>&1
}

# ── Tests ─────────────────────────────────────────────────────────────────────

test_install_resolves_agent_in_container() {
    if skip_unless_live; then return 0; fi
    if _ensure_image_or_skip; then return 0; fi

    local _fail=0
    local _proj="${_TMPDIR}/projects/resolve_test"
    _setup_fake_npm_in_project "$_proj" "myagent" "@test/myagent"

    local out rc=0
    out="$(_run_install_step_in_container "$_proj" "myagent" "ai-new-resolve-$$")" || rc=$?

    # After the install step, command -v should resolve.
    assert_contains "FOUND" "$out" "agent command must resolve on PATH after install" || _fail=1
    assert_not_contains "NOT_FOUND" "$out" "agent command must not be missing post-install" || _fail=1
    return $_fail
}

test_install_records_npm_call_in_container() {
    if skip_unless_live; then return 0; fi
    if _ensure_image_or_skip; then return 0; fi

    local _fail=0
    local _proj="${_TMPDIR}/projects/npm_call_test"
    _setup_fake_npm_in_project "$_proj" "myagent2" "@test/myagent2"

    _run_install_step_in_container "$_proj" "myagent2" "ai-new-npm-$$" >/dev/null 2>&1 || true

    [[ -f "${_proj}/bootstrap/npm_calls.txt" ]] || {
        printf '    npm_calls.txt not written — fake npm was not invoked\n' >&2
        _fail=1
    }
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "[slow] agent command resolves on PATH after install in container"  test_install_resolves_agent_in_container
run_test "[slow] fake npm called for install step in container"              test_install_records_npm_call_in_container

print_summary "test_install_resolves_in_container"
