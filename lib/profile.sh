#!/usr/bin/env bash
# Profile sourcing and validation. Source this file; do not execute directly.
# Requires common.sh to be sourced first.

# load_profile <name>
# Sources profiles/<name>.env, validates required fields, and normalises
# optional arrays to defined-but-possibly-empty arrays.
load_profile() {
    local name="$1"
    local profile_file
    profile_file="$(profiles_dir)/${name}.env"

    [[ -f "$profile_file" ]] \
        || _die "Profile not found: ${profile_file}"

    # shellcheck source=/dev/null
    source "$profile_file"

    local field
    for field in PROFILE_NAME CONTAINER_NAME IMAGE_NAME IMAGE_DIR \
                 WORKSPACE CONTAINER_HOME BASHRC WORKDIR BUILD_ARGS; do
        [[ -n "${!field:-}" ]] \
            || _die "Profile '${name}' (${profile_file}): required field '${field}' is unset or empty"
    done

    # Normalise optional arrays so they are always defined and usable under set -u.
    EXTRA_ENV=("${EXTRA_ENV[@]+"${EXTRA_ENV[@]}"}")
    EXTRA_VOLUMES=("${EXTRA_VOLUMES[@]+"${EXTRA_VOLUMES[@]}"}")
    EXTRA_DEVICES=("${EXTRA_DEVICES[@]+"${EXTRA_DEVICES[@]}"}")
    EXTRA_HOSTS=("${EXTRA_HOSTS[@]+"${EXTRA_HOSTS[@]}"}")
    EXTRA_RUN_ARGS=("${EXTRA_RUN_ARGS[@]+"${EXTRA_RUN_ARGS[@]}"}")
}
