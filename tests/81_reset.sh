#!/usr/bin/env bash
# T9b — --reset teardown (AC15).
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

test_reset_without_yes_requires_confirmation() {
    # Non-interactive --reset without --yes must not silently stop a container.
    # With the stub podman, container_running returns false, so reset_container
    # goes straight to "remove if exists" (stub returns non-zero for exists too).
    # We assert the exit code is 0 in this non-running scenario
    # (no running container → nothing to stop, just recreate).
    local _fail=0
    local out rc=0
    out="$(DRY_RUN=1 AI_PODMAN_JAILS_DIR="$_TMPDIR" PATH="${STUBS_DIR}:${PATH}" \
        "${BIN_DIR}/ai-launch" esp32 --reset 2>&1)" || rc=$?
    # DRY_RUN exits before reset path — so we get normal DRY_RUN:create output.
    # This confirms --reset doesn't conflict with DRY_RUN mode.
    # The key AC15 assertion (no silent stop of running container) is verified
    # in the live test below.
    assert_success $rc "--reset with DRY_RUN exits 0 (DRY_RUN wins)" || _fail=1
    return $_fail
}

test_reset_noninteractive_no_yes_dies_if_running_live() {
    skip_unless_live && return 0
    local _fail=0

    local img="test-reset-img-$$"
    mkdir -p "${_TMPDIR}/reset-image"
    cat > "${_TMPDIR}/reset-image/Containerfile" <<'EOF'
FROM busybox:latest
RUN adduser -D builder
EOF
    podman build -q -t "$img" "${_TMPDIR}/reset-image" >/dev/null 2>&1

    local ctr="test-reset-$$"
    cat > "${_TMPDIR}/profiles/rst.env" <<EOF
PROFILE_NAME="rst"
CONTAINER_NAME="${ctr}"
IMAGE_NAME="${img}"
IMAGE_DIR="${_TMPDIR}/reset-image"
WORKSPACE="${_TMPDIR}/reset-ws"
CONTAINER_HOME="${_TMPDIR}/reset-home"
BASHRC="${_TMPDIR}/.bashrc"
WORKDIR="/workspace"
BUILD_ARGS=""
EOF
    mkdir -p "${_TMPDIR}/reset-ws" "${_TMPDIR}/reset-home"

    # Create and start the container
    podman create --name "$ctr" \
        --userns=keep-id --security-opt no-new-privileges \
        -v "${_TMPDIR}/reset-ws:/workspace:Z" \
        -e HOME="${_TMPDIR}/reset-home" \
        -w /workspace \
        --network slirp4netns \
        --security-opt label=disable \
        "$img" sleep 30 >/dev/null 2>&1
    podman start "$ctr" >/dev/null 2>&1

    # --reset without --yes when container is running → must exit non-zero
    local out rc=0
    out="$(AI_PODMAN_JAILS_DIR="$_TMPDIR" "${BIN_DIR}/ai-launch" rst --reset 2>&1)" || rc=$?
    assert_failure $rc "--reset without --yes on running container → non-zero" || _fail=1

    # Container must still be running (not silently stopped)
    local still_running=0
    podman inspect --format '{{.State.Status}}' "$ctr" 2>/dev/null | grep -q running \
        || still_running=1
    assert_success $still_running "container still running after rejected --reset" || _fail=1

    podman stop "$ctr" >/dev/null 2>&1 || true
    podman rm -f "$ctr" >/dev/null 2>&1 || true
    podman rmi "$img" 2>/dev/null || true
    return $_fail
}

test_reset_with_yes_preserves_workspace_live() {
    skip_unless_live && return 0
    local _fail=0

    local img="test-reset-ws-img-$$"
    mkdir -p "${_TMPDIR}/reset-ws-image"
    cat > "${_TMPDIR}/reset-ws-image/Containerfile" <<'EOF'
FROM busybox:latest
RUN adduser -D builder
EOF
    podman build -q -t "$img" "${_TMPDIR}/reset-ws-image" >/dev/null 2>&1

    local ctr="test-reset-ws-$$"
    cat > "${_TMPDIR}/profiles/rstwk.env" <<EOF
PROFILE_NAME="rstwk"
CONTAINER_NAME="${ctr}"
IMAGE_NAME="${img}"
IMAGE_DIR="${_TMPDIR}/reset-ws-image"
WORKSPACE="${_TMPDIR}/reset-ws2"
CONTAINER_HOME="${_TMPDIR}/reset-home2"
BASHRC="${_TMPDIR}/.bashrc"
WORKDIR="/workspace"
BUILD_ARGS=""
EOF
    mkdir -p "${_TMPDIR}/reset-ws2" "${_TMPDIR}/reset-home2"
    echo "my-workspace-file" > "${_TMPDIR}/reset-ws2/file.txt"

    # Create container
    podman create --name "$ctr" \
        --userns=keep-id --security-opt no-new-privileges \
        -v "${_TMPDIR}/reset-ws2:/workspace:Z" \
        -e HOME="${_TMPDIR}/reset-home2" \
        -w /workspace \
        --network slirp4netns \
        --security-opt label=disable \
        "$img" sleep 30 >/dev/null 2>&1

    # --reset --yes: should remove and recreate container, leave workspace intact
    local rc=0
    AI_PODMAN_JAILS_DIR="$_TMPDIR" "${BIN_DIR}/ai-launch" rstwk --reset --yes \
        >/dev/null 2>&1 || rc=$?
    assert_success $rc "--reset --yes should exit 0" || _fail=1

    # Workspace file must survive
    [[ -f "${_TMPDIR}/reset-ws2/file.txt" ]] \
        || { echo "    workspace file lost after --reset --yes" >&2; _fail=1; }

    # Profile must still exist
    [[ -f "${_TMPDIR}/profiles/rstwk.env" ]] \
        || { echo "    profile removed after --reset" >&2; _fail=1; }

    # Image must still exist
    podman image inspect "$img" >/dev/null 2>&1 \
        || { echo "    image removed after --reset" >&2; _fail=1; }

    podman rm -f "$ctr" 2>/dev/null || true
    podman rmi "$img" 2>/dev/null || true
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "--reset + DRY_RUN: exits 0 (DRY_RUN takes precedence)"        test_reset_without_yes_requires_confirmation
run_test "--reset without --yes refuses to stop running ctr (Tier B)"   test_reset_noninteractive_no_yes_dies_if_running_live
run_test "--reset --yes preserves workspace/profile/image (Tier B)"     test_reset_with_yes_preserves_workspace_live

print_summary "81_reset"
