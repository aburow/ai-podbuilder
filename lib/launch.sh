#!/usr/bin/env bash
# Bootstrap container launch (R14, R15, R17). Source; do not execute.
# Requires common.sh.

_BOOTSTRAP_IMAGE_TAG_FALLBACK="localhost/ai-new/bootstrap:latest"

# launch_bootstrap <project_root> [resume] [shell_on_exit]
# Launches the disposable bootstrap container under the sandbox safety posture.
# The host Podman socket is NOT mounted; network is ON; $HOME = /project/bootstrap/home.
launch_bootstrap() {
    local _proj="$1"
    local _resume="${2:-0}"
    local _shell_on_exit="${3:-0}"
    local _slug="${SLUG:-$(basename "$_proj")}"
    local _container_name="ai-new-bootstrap-${_slug}"
    local _image_tag="${BOOTSTRAP_IMAGE_TAG:-${_BOOTSTRAP_IMAGE_TAG_FALLBACK}}"

    # Remove any existing (stopped) container with the same name.
    podman rm -f "$_container_name" >/dev/null 2>&1 || true

    _info "Launching bootstrap container: ${_container_name}"
    _info "  Project mount: ${_proj} → /project"
    _info "  HOME inside:   /project/bootstrap/home"
    _info "  Entrypoint:    /project/bootstrap/home/start-here.sh"
    _info "  Image:         ${_image_tag}"

    local _prompts_dir="${AI_PODMAN_JAILS_DIR}/prompts"

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

    # start-here.sh is delivered via the /project mount at
    # /project/bootstrap/home/start-here.sh (B1); no root bind mount.

    # Mount prompts/ read-only so start-here.sh can copy the bootstrap prompt.
    if [[ -d "$_prompts_dir" ]]; then
        _args+=(--volume "${_prompts_dir}:/start-here-prompts:ro,z")
    fi

    # Explicitly do NOT pass --privileged, --device /dev/fuse,
    # --volume /run/user/.../podman.sock, or any nested-Podman capability.

    local _entrypoint=(/project/bootstrap/home/start-here.sh)
    if [[ "$_resume" -eq 1 ]]; then
        _entrypoint+=(--resume)
    fi
    if [[ "$_shell_on_exit" -eq 1 ]]; then
        _entrypoint+=(--shell-on-exit)
        _info "  Shell fallback: enabled"
    fi

    # Keep the ai-new host supervisor alive while Podman runs. The caller owns
    # the session heartbeat and lock, and must regain control when the agent
    # exits so both can be cleaned up immediately.
    local _rc=0
    if podman "${_args[@]}" "$_image_tag" "${_entrypoint[@]}"; then
        _info "Bootstrap container session ended normally."
        return 0
    else
        _rc=$?
        _warn "Bootstrap container exited with status ${_rc}."
        _warn "Resume with: ai-new ${_slug} --resume"
        return "$_rc"
    fi
}
