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
