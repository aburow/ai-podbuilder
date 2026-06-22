#!/usr/bin/env bash
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

# Emits extra args from optional profile arrays.
extra_args() {
    local item
    for item in "${EXTRA_HOSTS[@]+"${EXTRA_HOSTS[@]}"}"; do
        printf '%s\n' "--add-host=${item}"
    done
    for item in "${EXTRA_DEVICES[@]+"${EXTRA_DEVICES[@]}"}"; do
        printf '%s\n' "$item"
    done
    for item in "${EXTRA_VOLUMES[@]+"${EXTRA_VOLUMES[@]}"}"; do
        printf '%s\n' "$item"
    done
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
                       "--security-opt" "no-new-privileges")

    # SELinux (R5.6).
    while IFS= read -r arg; do
        _NORMAL_RUN_ARGS+=("$arg")
    done < <(selinux_args)

    # Workspace mount — exactly one bind mount (R5.2).
    _NORMAL_RUN_ARGS+=("-v" "${WORKSPACE}:/workspace:Z")

    # Container HOME override (R5.4).
    _NORMAL_RUN_ARGS+=("-e" "HOME=${CONTAINER_HOME}")

    # Working directory.
    _NORMAL_RUN_ARGS+=("-w" "$WORKDIR")

    # Network (R6.1).
    while IFS= read -r arg; do
        _NORMAL_RUN_ARGS+=("$arg")
    done < <(network_args)

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
    _BUILDER_RUN_ARGS+=("-e" "HOME=${CONTAINER_HOME}")
    _BUILDER_RUN_ARGS+=("-w" "$WORKDIR")

    # Profile EXTRA_VOLUMES only (caches, not extra devices/env in builder).
    local item
    for item in "${EXTRA_VOLUMES[@]+"${EXTRA_VOLUMES[@]}"}"; do
        _BUILDER_RUN_ARGS+=("$item")
    done
}
