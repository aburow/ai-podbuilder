#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# 2026 - Anthony Burow - https://github.com/aburow
# Safety policy assembly. Source this file; do not execute directly.
# Requires common.sh and a loaded profile to be in scope.

# Emits SELinux security-opt args based on SELINUX_MODE (default: disable).
selinux_args() {
    local mode="${SELINUX_MODE:-disable}"
    if [[ "$mode" == "disable" ]]; then
        printf '%s\n' "--security-opt" "label=disable"
    fi
    # mode=enforce: omit label=disable; the :Z on the mount handles relabelling.
}

# Emits network arg based on NETWORK_MODE (default: slirp4netns).
network_args() {
    local net="${NETWORK_MODE:-slirp4netns}"
    printf '%s\n' "--network" "$net"
}

# Emits optional GUI/display forwarding args based on GUI_FORWARD.
# Supported values:
#   "" / "none"  -> disabled (default)
#   "x11"        -> pass DISPLAY and mount the X11 socket directory, plus an
#                   Xauthority file when available.
gui_args() {
    local mode="${GUI_FORWARD:-}"
    case "$mode" in
        ""|none)
            return 0
            ;;
        x11)
            if [[ -z "${DISPLAY:-}" ]]; then
                _warn "GUI_FORWARD=x11 requested but DISPLAY is unset; launching without GUI forwarding"
                return 0
            fi

            local socket_dir="${GUI_X11_SOCKET_DIR:-/tmp/.X11-unix}"
            if [[ -d "$socket_dir" ]]; then
                printf '%s\n' "-v" "${socket_dir}:/tmp/.X11-unix:ro"
            else
                _warn "GUI_FORWARD=x11 requested but X11 socket dir is missing: ${socket_dir}"
            fi

            printf '%s\n' "-e" "DISPLAY=${DISPLAY}"
            printf '%s\n' "-e" "QT_X11_NO_MITSHM=1"

            local xauth_host="${GUI_XAUTHORITY_HOST:-${XAUTHORITY:-${HOME}/.Xauthority}}"
            if [[ -f "$xauth_host" ]]; then
                printf '%s\n' "-v" "${xauth_host}:/tmp/.ai-launch.Xauthority:ro"
                printf '%s\n' "-e" "XAUTHORITY=/tmp/.ai-launch.Xauthority"
            else
                _warn "GUI_FORWARD=x11 requested but Xauthority file is missing: ${xauth_host}"
            fi
            ;;
        *)
            _warn "Unsupported GUI_FORWARD mode '${mode}'; launching without GUI forwarding"
            ;;
    esac
}

# Emits --env-file if ENV_FILE is set. Warns and skips if the file is missing.
secret_args() {
    if [[ -z "${ENV_FILE:-}" ]]; then
        return 0
    fi
    if [[ -f "$ENV_FILE" ]]; then
        printf '%s\n' "--env-file" "$ENV_FILE"
    else
        _warn "ENV_FILE is set but not found: ${ENV_FILE} — launching without secrets"
    fi
}

extra_volume_args() {
    local i=0
    local flag spec host_path
    while [[ $i -lt ${#EXTRA_VOLUMES[@]} ]]; do
        flag="${EXTRA_VOLUMES[$i]}"
        spec="${EXTRA_VOLUMES[$((i + 1))]:-}"
        if [[ "$flag" == "-v" || "$flag" == "--volume" ]]; then
            host_path="$(extra_volume_host_path "$spec")"
            if [[ -n "$host_path" && ! -e "$host_path" ]] && host_path_is_optional_config_mount "$host_path"; then
                _warn "Optional host config path missing; skipping volume mount: ${host_path}"
                i=$((i + 2))
                continue
            fi
            printf '%s\n' "$flag" "$spec"
            i=$((i + 2))
            continue
        fi
        printf '%s\n' "$flag"
        i=$((i + 1))
    done
}

# Emits extra args from optional profile arrays.
extra_args() {
    local item
    for item in "${EXTRA_HOSTS[@]+"${EXTRA_HOSTS[@]}"}"; do
        printf '%s\n' "--add-host=${item}"
    done
    for item in "${EXTRA_DEVICES[@]+"${EXTRA_DEVICES[@]}"}"; do
        printf '%s\n' "$item"
    done
    extra_volume_args
    for item in "${EXTRA_ENV[@]+"${EXTRA_ENV[@]}"}"; do
        printf '%s\n' "$item"
    done
    for item in "${EXTRA_RUN_ARGS[@]+"${EXTRA_RUN_ARGS[@]}"}"; do
        printf '%s\n' "$item"
    done
}

# Assembles the full normal-mode run-argument array into _NORMAL_RUN_ARGS.
# No caller may add --privileged, host-$HOME mounts, or socket mounts.
build_normal_run_args() {
    _NORMAL_RUN_ARGS=()

    # Core safety flags (R5.1).
    _NORMAL_RUN_ARGS+=("-it" "--userns=keep-id" "--group-add" "keep-groups"
                       "--security-opt" "no-new-privileges"
                       "--hostname" "${CONTAINER_HOSTNAME:-${CONTAINER_NAME:-ai-podbuilder}}")

    # SELinux (R5.6).
    while IFS= read -r arg; do
        _NORMAL_RUN_ARGS+=("$arg")
    done < <(selinux_args)

    # Workspace mount — exactly one bind mount (R5.2).
    _NORMAL_RUN_ARGS+=("-v" "${WORKSPACE}:/workspace:Z")

    # Persist container HOME state on the host, mounted at the same path
    # that HOME points to inside the container.
    _NORMAL_RUN_ARGS+=("-v" "${CONTAINER_HOME}:${CONTAINER_HOME}:Z")

    # Container HOME override (R5.4).
    _NORMAL_RUN_ARGS+=("-e" "HOME=${CONTAINER_HOME}")

    # Working directory.
    _NORMAL_RUN_ARGS+=("-w" "$WORKDIR")

    # Ensure the project rcfile exists before we create or start the container.
    mkdir -p "$(dirname "$BASHRC")"
    touch "$BASHRC"

    # Network (R6.1).
    while IFS= read -r arg; do
        _NORMAL_RUN_ARGS+=("$arg")
    done < <(network_args)

    # Optional GUI/display forwarding.
    while IFS= read -r arg; do
        _NORMAL_RUN_ARGS+=("$arg")
    done < <(gui_args)

    # Secrets (R7).
    while IFS= read -r arg; do
        _NORMAL_RUN_ARGS+=("$arg")
    done < <(secret_args)

    # Profile EXTRA_* arrays (R4.6).
    while IFS= read -r arg; do
        _NORMAL_RUN_ARGS+=("$arg")
    done < <(extra_args)
}

# Assembles the builder-mode run-argument array into _BUILDER_RUN_ARGS.
# Builder is the ONLY privileged path (R4.5, R4.12).
build_builder_run_args() {
    _BUILDER_RUN_ARGS=()

    _BUILDER_RUN_ARGS+=("--privileged" "--rm" "-it")
    _BUILDER_RUN_ARGS+=("--name" "${CONTAINER_NAME}-builder")

    # Workspace mount for build artifacts.
    _BUILDER_RUN_ARGS+=("-v" "${WORKSPACE}:/workspace:Z")
    _BUILDER_RUN_ARGS+=("-v" "${CONTAINER_HOME}:${CONTAINER_HOME}:Z")
    _BUILDER_RUN_ARGS+=("-e" "HOME=${CONTAINER_HOME}")
    _BUILDER_RUN_ARGS+=("-w" "$WORKDIR")

    mkdir -p "$(dirname "$BASHRC")"
    touch "$BASHRC"

    # Profile EXTRA_VOLUMES only (caches, not extra devices/env in builder).
    local item
    while IFS= read -r item; do
        _BUILDER_RUN_ARGS+=("$item")
    done < <(extra_volume_args)
}
