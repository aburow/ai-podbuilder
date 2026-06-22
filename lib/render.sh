#!/usr/bin/env bash
# User-surface rendering functions. Source this file; do not execute directly.
# Requires common.sh and a loaded profile to be in scope.

# _bold <text> — wraps text in bold ANSI when stderr is a TTY.
_bold() {
    if [[ -t 2 ]]; then
        printf '\033[1m%s\033[0m' "$1"
    else
        printf '%s' "$1"
    fi
}

# render_launch_summary <reuse:yes|no>
# Prints the pre-launch policy banner to stderr showing the active safety
# policy. Builder mode emits an explicit privileged/ephemeral warning line.
render_launch_summary() {
    local reusing="${1:-no}"
    local sep="─────────────────────────────────────────"
    {
        echo "$sep"
        printf '  %-12s: %s\n' "Profile"    "${PROFILE_NAME}"
        printf '  %-12s: %s\n' "Container"  "${CONTAINER_NAME}"
        printf '  %-12s: %s\n' "Image"      "${IMAGE_NAME}"
        printf '  %-12s: %s\n' "Workspace"  "${WORKSPACE}"
        printf '  %-12s: %s\n' "Home (ctr)" "${CONTAINER_HOME}"
        printf '  %-12s: %s\n' "Mode"       "${_LAUNCH_MODE}"
        printf '  %-12s: %s\n' "Network"    "${NETWORK_MODE:-slirp4netns}"
        printf '  %-12s: %s\n' "SELinux"    "${SELINUX_MODE:-disable}"
        printf '  %-12s: %s\n' "Reusing"    "${reusing}"
        if [[ "${_LAUNCH_MODE}" == "builder" ]]; then
            printf '\n  %s\n' \
                "$(_bold "WARNING: builder mode is PRIVILEGED and EPHEMERAL — container removed on exit.")"
        fi
        echo "$sep"
    } >&2
}

# prompt_stale_choice
# Presents the three-way interactive stale-image prompt and writes the user's
# choice to stdout: "continue", "recreate", or "cancel".
# Empty input selects "continue" (the safe default — never recreate silently).
prompt_stale_choice() {
    {
        echo ""
        _warn "Container '${CONTAINER_NAME}' was built from a different image than the current local image."
        echo ""
        printf '  [1] Continue  — use the existing container as-is (default)\n'
        printf '  [2] Recreate  — remove the container and recreate from the new image\n'
        printf '               (the container is rebuilt; your workspace is preserved)\n'
        printf '  [3] Cancel    — exit now and inspect manually\n'
        echo ""
    } >&2
    local choice
    while true; do
        printf 'Choice [1/2/3, Enter=1]: ' >&2
        read -r choice
        case "${choice:-1}" in
            1) echo "continue"; return ;;
            2) echo "recreate"; return ;;
            3) echo "cancel";   return ;;
            *) printf '  Please enter 1, 2, or 3.\n' >&2 ;;
        esac
    done
}

# warn_stale_noninteractive
# Prints a non-interactive staleness warning with no prompt.
warn_stale_noninteractive() {
    _warn "Container '${CONTAINER_NAME}' was built from a different image than the current local image."
    _warn "Non-interactive mode: continuing with existing container (use --recreate to update)."
}

# confirm_reset
# Interactive confirmation prompt for --reset. Explains what is preserved.
# Returns 0 if the user confirms, 1 if they decline or press Enter.
confirm_reset() {
    {
        echo ""
        printf '  --reset will stop and remove container '"'"'%s'"'"', then recreate it.\n' \
            "${CONTAINER_NAME}"
        printf '  Preserved: workspace, home directory, profile, image, and secrets.\n'
        printf '  Only the container itself is removed and rebuilt from the current image.\n'
        echo ""
    } >&2
    local choice
    printf 'Continue? [y/N]: ' >&2
    read -r choice
    [[ "${choice}" == [yY] ]]
}

# render_profile_table <"name\timage\tworkspace\tstate"> ...
# Prints a column-aligned profile table to stdout. Column widths adapt to the
# longest value in each column. No ANSI escapes are emitted (pure text).
render_profile_table() {
    local -a rows=("$@")
    local -a names images workspaces states
    local max_name=7    # length of "PROFILE"
    local max_image=5   # length of "IMAGE"
    local max_ws=9      # length of "WORKSPACE"

    local row name image ws state

    for row in "${rows[@]}"; do
        IFS=$'\t' read -r name image ws state <<< "$row"
        names+=("$name")
        images+=("$image")
        workspaces+=("$ws")
        states+=("$state")
        [[ ${#name}  -gt $max_name  ]] && max_name=${#name}
        [[ ${#image} -gt $max_image ]] && max_image=${#image}
        [[ ${#ws}    -gt $max_ws    ]] && max_ws=${#ws}
    done

    local dash_name dash_image dash_ws
    dash_name="$(  printf '%*s' "$max_name"  '' | tr ' ' '-')"
    dash_image="$( printf '%*s' "$max_image" '' | tr ' ' '-')"
    dash_ws="$(    printf '%*s' "$max_ws"    '' | tr ' ' '-')"

    printf "%-${max_name}s  %-${max_image}s  %-${max_ws}s  %s\n" \
        "PROFILE" "IMAGE" "WORKSPACE" "STATE"
    printf "%-${max_name}s  %-${max_image}s  %-${max_ws}s  %s\n" \
        "$dash_name" "$dash_image" "$dash_ws" "-----"

    local i
    for i in "${!names[@]}"; do
        printf "%-${max_name}s  %-${max_image}s  %-${max_ws}s  %s\n" \
            "${names[$i]}" "${images[$i]}" "${workspaces[$i]}" "${states[$i]}"
    done
}
