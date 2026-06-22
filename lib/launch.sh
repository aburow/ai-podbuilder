#!/usr/bin/env bash
# Bootstrap container launch (R14, R15, R17). Source; do not execute.
# Requires common.sh.

_BOOTSTRAP_IMAGE_TAG="localhost/ai-new/bootstrap:latest"

# launch_bootstrap <project_root>
# Launches the disposable bootstrap container under the sandbox safety posture.
# The host Podman socket is NOT mounted; network is ON; $HOME = /project/bootstrap/home.
launch_bootstrap() {
    local _proj="$1"
    local _slug="${SLUG:-$(basename "$_proj")}"
    local _container_name="ai-new-bootstrap-${_slug}"

    # Remove any existing (stopped) container with the same name.
    podman rm -f "$_container_name" >/dev/null 2>&1 || true

    _info "Launching bootstrap container: ${_container_name}"
    _info "  Project mount: ${_proj} → /project"
    _info "  HOME inside:   /project/bootstrap/home"

    local _start_here="${CODEX_JAILS_DIR}/start-here.sh"
    local _prompts_dir="${CODEX_JAILS_DIR}/prompts"

    # Build argv array — no shell interpolation of registry values.
    local _args=(
        run
        --rm
        --interactive
        --tty
        --name "$_container_name"
        --userns=keep-id
        --volume "${_proj}:/project:z"
        --env "HOME=/project/bootstrap/home"
        --workdir /project
        --network host
    )

    # Mount start-here.sh at container root if it exists in the plugin directory.
    if [[ -f "$_start_here" ]]; then
        _args+=(--volume "${_start_here}:/start-here.sh:ro,z")
    fi

    # Mount prompts/ read-only so start-here.sh can copy the bootstrap prompt.
    if [[ -d "$_prompts_dir" ]]; then
        _args+=(--volume "${_prompts_dir}:/start-here-prompts:ro,z")
    fi

    # Explicitly do NOT pass --privileged, --device /dev/fuse,
    # --volume /run/user/.../podman.sock, or any nested-Podman capability.

    exec podman "${_args[@]}" "$_BOOTSTRAP_IMAGE_TAG" /bin/bash
}
