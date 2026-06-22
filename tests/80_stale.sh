#!/usr/bin/env bash
# T9a — Stale-image reconciliation (AC14). Tier A: flag handling. Tier B: live flow.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

# ── Tier A: --yes and --recreate flag behaviour via DRY_RUN ──────────────────
# The DRY_RUN path exits before container_exists is ever called, so we can
# test the assembled args for both flags independently of image staleness.

test_yes_flag_produces_normal_create() {
    # --yes means "continue with existing container", never force-recreate.
    # The DRY_RUN output for a normal mode should be a create (not run).
    local _fail=0
    local out rc=0
    out="$(DRY_RUN=1 CODEX_JAILS_DIR="$_TMPDIR" PATH="${STUBS_DIR}:${PATH}" \
        "${BIN_DIR}/ai-launch" esp32 --yes 2>/dev/null)" || rc=$?
    assert_success $rc "--yes with DRY_RUN should succeed" || _fail=1
    assert_contains "DRY_RUN:create" "$out" "--yes still uses normal (non-builder) create" || _fail=1
    assert_not_contains "--privileged" "$out" "--yes must never yield --privileged" || _fail=1
    return $_fail
}

test_non_interactive_flag_produces_normal_create() {
    local _fail=0
    local out
    out="$(DRY_RUN=1 CODEX_JAILS_DIR="$_TMPDIR" PATH="${STUBS_DIR}:${PATH}" \
        "${BIN_DIR}/ai-launch" esp32 --non-interactive 2>/dev/null)"
    assert_contains "DRY_RUN:create" "$out" || _fail=1
    return $_fail
}

test_recreate_flag_produces_normal_create() {
    # --recreate rebuilds the container (still a normal create, not builder).
    local _fail=0
    local out
    out="$(DRY_RUN=1 CODEX_JAILS_DIR="$_TMPDIR" PATH="${STUBS_DIR}:${PATH}" \
        "${BIN_DIR}/ai-launch" esp32 --recreate 2>/dev/null)"
    assert_contains "DRY_RUN:create" "$out" "--recreate still uses normal create" || _fail=1
    assert_not_contains "--privileged" "$out" || _fail=1
    return $_fail
}

# ── Tier B: live stale-image reconciliation ───────────────────────────────────

_build_image_v1() {
    local img="$1"
    mkdir -p "${_TMPDIR}/stale-image"
    cat > "${_TMPDIR}/stale-image/Containerfile" <<'EOF'
FROM busybox:latest
RUN echo "v1" > /etc/version
EOF
    podman build -q --no-cache -t "$img" "${_TMPDIR}/stale-image" >/dev/null 2>&1
}

_build_image_v2() {
    local img="$1"
    cat > "${_TMPDIR}/stale-image/Containerfile" <<'EOF'
FROM busybox:latest
RUN echo "v2" > /etc/version
EOF
    podman build -q --no-cache -t "$img" "${_TMPDIR}/stale-image" >/dev/null 2>&1
}

_stale_profile() {
    local img="$1"
    cat > "${_TMPDIR}/profiles/stale.env" <<EOF
PROFILE_NAME="stale"
CONTAINER_NAME="test-stale-$$"
IMAGE_NAME="${img}"
IMAGE_DIR="${_TMPDIR}/stale-image"
WORKSPACE="${_TMPDIR}/stale-ws"
CONTAINER_HOME="${_TMPDIR}/stale-home"
BASHRC="${_TMPDIR}/.bashrc"
WORKDIR="/workspace"
BUILD_ARGS="--no-cache"
EOF
}

test_recreate_preserves_workspace_live() {
    skip_unless_live && return 0
    local _fail=0

    local img="test-stale-img-$$"
    _build_image_v1 "$img"
    _stale_profile "$img"
    mkdir -p "${_TMPDIR}/stale-ws" "${_TMPDIR}/stale-home"

    # Create initial container from v1
    local ctr="test-stale-$$"
    podman create --name "$ctr" \
        --userns=keep-id --security-opt no-new-privileges \
        -v "${_TMPDIR}/stale-ws:/workspace:Z" \
        -e HOME="${_TMPDIR}/stale-home" \
        -w /workspace \
        --network slirp4netns \
        --security-opt label=disable \
        "$img" sleep 30 >/dev/null 2>&1

    # Write a marker file in the workspace (host-side)
    echo "my-workspace-marker" > "${_TMPDIR}/stale-ws/marker.txt"

    # Rebuild image to v2 (making container stale)
    _build_image_v2 "$img"

    # Simulate --recreate: remove and recreate
    CODEX_JAILS_DIR="$_TMPDIR" bash -c "
        source '${LIB_DIR}/common.sh'
        source '${LIB_DIR}/profile.sh'
        source '${LIB_DIR}/policy.sh'
        source '${LIB_DIR}/container.sh'
        resolve_base_dir
        load_profile stale
        recreate_preserving_workspace >/dev/null 2>&1
        create_normal_container >/dev/null 2>&1
    " 2>/dev/null

    # Workspace marker must still exist after recreate
    [[ -f "${_TMPDIR}/stale-ws/marker.txt" ]] \
        || { echo "    workspace marker lost after recreate" >&2; _fail=1; }

    # Check marker content
    local content
    content="$(cat "${_TMPDIR}/stale-ws/marker.txt")"
    assert_eq "my-workspace-marker" "$content" "workspace content preserved" || _fail=1

    # Cleanup
    podman rm -f "$ctr" 2>/dev/null || true
    podman rmi "$img" 2>/dev/null || true
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "--yes flag: still assembles normal create (not recreate)" test_yes_flag_produces_normal_create
run_test "--non-interactive flag: assembles normal create"          test_non_interactive_flag_produces_normal_create
run_test "--recreate flag: assembles normal create (not builder)"   test_recreate_flag_produces_normal_create
run_test "--recreate preserves workspace content (Tier B)"          test_recreate_preserves_workspace_live

print_summary "80_stale"
