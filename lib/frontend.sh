#!/usr/bin/env bash
# Frontend rendering stubs. The full implementation is owned by the frontend
# plan (ai-agent-podman-sandbox-7-fe.md). These stubs provide the hooks that
# the backend calls so ai-launch is functional before the frontend is delivered.

# render_launch_summary <reuse:yes|no>
# Prints a pre-launch summary (R4.8). Fields come from the loaded profile and
# surrounding shell variables.
render_launch_summary() {
    local reusing="${1:-no}"
    cat >&2 <<EOF
─────────────────────────────────────────
  Profile    : ${PROFILE_NAME}
  Container  : ${CONTAINER_NAME}
  Image      : ${IMAGE_NAME}
  Workspace  : ${WORKSPACE}
  Home (ctr) : ${CONTAINER_HOME}
  Mode       : ${_LAUNCH_MODE}
  Network    : ${NETWORK_MODE:-slirp4netns}
  SELinux    : ${SELINUX_MODE:-disable}
  Reusing    : ${reusing}
─────────────────────────────────────────
EOF
}

# prompt_stale_choice
# Presents the three-way interactive stale-image prompt and writes the user's
# choice to stdout: "continue", "recreate", or "cancel".
prompt_stale_choice() {
    echo "" >&2
    _warn "Container '${CONTAINER_NAME}' was built from a different image than the current local image."
    cat >&2 <<'EOF'
  [1] Continue  — use the existing container as-is
  [2] Recreate  — remove and recreate from the new image (workspace preserved)
  [3] Cancel    — exit now and inspect manually
EOF
    local choice
    while true; do
        printf 'Choice [1/2/3]: ' >&2
        read -r choice
        case "$choice" in
            1) echo "continue"; return ;;
            2) echo "recreate"; return ;;
            3) echo "cancel";   return ;;
            *) echo "Please enter 1, 2, or 3." >&2 ;;
        esac
    done
}
