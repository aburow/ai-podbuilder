#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# 2026 - Anthony Burow - https://github.com/aburow
# Container lifecycle helpers. Source this file; do not execute directly.
# Requires common.sh, profile.sh, and policy.sh to be sourced first.

container_exists() {
    podman container exists "$1" 2>/dev/null
}

container_running() {
    [[ "$(podman inspect --format '{{.State.Status}}' "$1" 2>/dev/null)" == "running" ]]
}

container_image_id() {
    podman inspect --format '{{.Image}}' "$1" 2>/dev/null
}

current_image_id() {
    podman image inspect --format '{{.Id}}' "$1" 2>/dev/null
}

# Returns true (0) when the persistent container's image differs from the
# current local image. Exits non-zero if either ID cannot be resolved.
image_is_stale() {
    local container_img current_img
    container_img="$(container_image_id "$CONTAINER_NAME")"
    current_img="$(current_image_id "$IMAGE_NAME")"
    [[ -n "$container_img" && -n "$current_img" && "$container_img" != "$current_img" ]]
}

# Remove the persistent container; the workspace and container-home bind-mount
# dirs are never deleted — they live on the host filesystem.
recreate_preserving_workspace() {
    podman rm -f "$CONTAINER_NAME"
    _info "Container '${CONTAINER_NAME}' removed; workspace preserved."
}

create_normal_container() {
    _info "Creating container '${CONTAINER_NAME}' …"
    build_normal_run_args
    # Prefer the framework bashrc baked into the image; fall back to the
    # project workspace rcfile for images that predate this feature.
    local _rcfile="/etc/ai-podbuilder/bashrc"
    [[ -n "$BASHRC_CONTAINER" && "$BASHRC_CONTAINER" != "/workspace/.bashrc" ]] && _rcfile="$BASHRC_CONTAINER"
    local _shell_cmd=(bash --rcfile "$_rcfile" -i)
    podman create --name "$CONTAINER_NAME" "${_NORMAL_RUN_ARGS[@]}" "$IMAGE_NAME" "${_shell_cmd[@]}"
}

start_and_attach() {
    if ! container_running "$CONTAINER_NAME"; then
        _info "Starting container '${CONTAINER_NAME}' …"
        podman start "$CONTAINER_NAME"
    fi
    _info "Attaching to '${CONTAINER_NAME}' …"
    podman attach "$CONTAINER_NAME"
}

exec_mode_command() {
    local container="$1"
    shift
    podman exec -it "$container" "$@"
}

run_builder_ephemeral() {
    local mode_cmd=("$@")
    _info "Starting ephemeral privileged builder '${CONTAINER_NAME}-builder' …"
    build_builder_run_args
    podman run "${_BUILDER_RUN_ARGS[@]}" "$IMAGE_NAME" "${mode_cmd[@]}"
}

reset_container() {
    local force="$1"   # "yes" to stop a running container without prompting

    if container_running "$CONTAINER_NAME"; then
        if [[ "$force" == "yes" ]]; then
            _info "Stopping running container '${CONTAINER_NAME}' …"
            podman stop "$CONTAINER_NAME"
        else
            _die "--reset requires --yes to stop a running container '${CONTAINER_NAME}'"
        fi
    fi

    if container_exists "$CONTAINER_NAME"; then
        podman rm "$CONTAINER_NAME"
        _info "Container '${CONTAINER_NAME}' removed."
    fi

    _info "Recreating container '${CONTAINER_NAME}' from current image …"
    create_normal_container
    _info "Container '${CONTAINER_NAME}' recreated."
}
