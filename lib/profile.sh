#!/usr/bin/env bash
# Profile sourcing and validation. Source this file; do not execute directly.
# Requires common.sh to be sourced first.
# shellcheck source=slug.sh
source "$(dirname "${BASH_SOURCE[0]}")/slug.sh"

# load_profile <name>
# Sources profiles/<name>.env, validates required fields, and normalises
# optional arrays to defined-but-possibly-empty arrays.
validate_loaded_profile() {
    local name="${1:-loaded-profile}"
    local profile_file="${2:-<loaded>}"

    local field
    for field in PROFILE_NAME CONTAINER_NAME IMAGE_NAME IMAGE_DIR \
                 WORKSPACE CONTAINER_HOME BASHRC WORKDIR; do
        [[ -n "${!field:-}" ]] \
            || _die "Profile '${name}' (${profile_file}): required field '${field}' is unset or empty"
    done
    [[ -v BUILD_ARGS ]] \
        || _die "Profile '${name}' (${profile_file}): required field 'BUILD_ARGS' is unset"

    EXTRA_ENV=("${EXTRA_ENV[@]+"${EXTRA_ENV[@]}"}")
    EXTRA_VOLUMES=("${EXTRA_VOLUMES[@]+"${EXTRA_VOLUMES[@]}"}")
    EXTRA_DEVICES=("${EXTRA_DEVICES[@]+"${EXTRA_DEVICES[@]}"}")
    EXTRA_HOSTS=("${EXTRA_HOSTS[@]+"${EXTRA_HOSTS[@]}"}")
    EXTRA_RUN_ARGS=("${EXTRA_RUN_ARGS[@]+"${EXTRA_RUN_ARGS[@]}"}")

    local i flag value
    i=0
    while [[ $i -lt ${#EXTRA_ENV[@]} ]]; do
        flag="${EXTRA_ENV[$i]}"
        value="${EXTRA_ENV[$((i + 1))]:-}"
        [[ "$flag" == "-e" || "$flag" == "--env" ]] \
            || _die "Profile '${name}' (${profile_file}): EXTRA_ENV entry ${i} must be -e/--env, got '${flag}'"
        [[ -n "$value" && "$value" == *=* ]] \
            || _die "Profile '${name}' (${profile_file}): EXTRA_ENV value after ${flag} must be KEY=VALUE"
        i=$((i + 2))
    done

    i=0
    while [[ $i -lt ${#EXTRA_VOLUMES[@]} ]]; do
        flag="${EXTRA_VOLUMES[$i]}"
        value="${EXTRA_VOLUMES[$((i + 1))]:-}"
        [[ "$flag" == "-v" || "$flag" == "--volume" ]] \
            || _die "Profile '${name}' (${profile_file}): EXTRA_VOLUMES entry ${i} must be -v/--volume, got '${flag}'"
        [[ -n "$value" && "$value" == *:* ]] \
            || _die "Profile '${name}' (${profile_file}): EXTRA_VOLUMES value after ${flag} must be HOST:CTR[:opts]"
        i=$((i + 2))
    done

    for value in "${EXTRA_RUN_ARGS[@]+"${EXTRA_RUN_ARGS[@]}"}"; do
        case "$value" in
            --group-add=keep-groups|--group-add|keep-groups)
                _die "Profile '${name}' (${profile_file}): EXTRA_RUN_ARGS must not restate framework-owned keep-groups behavior"
                ;;
        esac
    done
}

validate_profile_file() {
    local profile_file="$1"
    [[ -f "$profile_file" ]] || _die "Profile not found: ${profile_file}"
    # shellcheck source=/dev/null
    source "$profile_file"
    local name
    name="$(basename "$profile_file" .env)"
    validate_loaded_profile "$name" "$profile_file"
}

load_profile() {
    local name="$1"
    local project_profile="${AI_PODMAN_JAILS_DIR}/projects/${name}/profile.env"
    local legacy_profile
    legacy_profile="$(profiles_dir)/$(sanitize_slug "$name").env"
    local profile_file

    if [[ -f "$project_profile" ]]; then
        profile_file="$project_profile"
    elif [[ -f "$legacy_profile" ]]; then
        _info "Loaded legacy profile $(basename "${legacy_profile}") from profiles/; the canonical location is projects/${name}/profile.env. profiles/ is an optional compatibility area."
        profile_file="$legacy_profile"
    else
        _die "Profile not found for '${name}': tried ${project_profile} and ${legacy_profile}"
    fi

    # shellcheck source=/dev/null
    source "$profile_file"

    validate_loaded_profile "$name" "$profile_file"

    # Derive the container-visible rcfile path from the host-side workspace path.
    # Profiles keep BASHRC on the host so the launcher can create/touch it there.
    if [[ "$BASHRC" == "$WORKSPACE/"* ]]; then
        BASHRC_CONTAINER="${BASHRC/#$WORKSPACE/$WORKDIR}"
    else
        BASHRC_CONTAINER="$BASHRC"
    fi
    export BASHRC_CONTAINER
}
