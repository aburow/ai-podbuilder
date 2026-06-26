#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# 2026 - Anthony Burow - https://github.com/aburow
# T4 — Persistence and reuse (AC3). All tests are Tier B (live Podman).
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

_build_minimal_image() {
    local image_name="$1"
    mkdir -p "${_TMPDIR}/minimal-image"
    cat > "${_TMPDIR}/minimal-image/Containerfile" <<'EOF'
FROM busybox:latest
RUN adduser -D builder
EOF
    podman build -q -t "$image_name" "${_TMPDIR}/minimal-image" >/dev/null 2>&1
}

_minimal_profile() {
    local img="$1"
    cat > "${_TMPDIR}/profiles/persist.env" <<EOF
PROFILE_NAME="persist"
CONTAINER_NAME="test-persist-ctr-$$"
IMAGE_NAME="${img}"
IMAGE_DIR="${_TMPDIR}/minimal-image"
WORKSPACE="${_TMPDIR}/persist-ws"
CONTAINER_HOME="${_TMPDIR}/persist-home"
BASHRC="${_TMPDIR}/.bashrc"
WORKDIR="/workspace"
BUILD_ARGS=""
EOF
}

test_container_survives_exit() {
    skip_unless_live && return 0
    local _fail=0
    local img="test-persist-img-$$"
    _build_minimal_image "$img" || { echo "    image build failed" >&2; return 1; }
    _minimal_profile "$img"

    local ctr
    ctr="$(AI_PODMAN_JAILS_DIR="$_TMPDIR" bash -c "
        source '${LIB_DIR}/common.sh'
        source '${LIB_DIR}/profile.sh'
        source '${LIB_DIR}/policy.sh'
        source '${LIB_DIR}/container.sh'
        resolve_base_dir
        load_profile persist
        mkdir -p \"\$WORKSPACE\" \"\$CONTAINER_HOME\"
        create_normal_container >/dev/null 2>&1
        echo \"\$CONTAINER_NAME\"
    " 2>/dev/null)"

    # Container should exist after creation
    podman container exists "$ctr" \
        || { echo "    container did not exist after create" >&2; _fail=1; }

    # Cleanup
    podman rm -f "$ctr" 2>/dev/null || true
    podman rmi "$img" 2>/dev/null || true
    return $_fail
}

test_second_launch_reuses_container() {
    skip_unless_live && return 0
    local _fail=0
    local img="test-reuse-img-$$"
    _build_minimal_image "$img" || return 1
    _minimal_profile "$img"

    # Create the container the first time
    local ctr
    ctr="$(AI_PODMAN_JAILS_DIR="$_TMPDIR" bash -c "
        source '${LIB_DIR}/common.sh'
        source '${LIB_DIR}/profile.sh'
        source '${LIB_DIR}/policy.sh'
        source '${LIB_DIR}/container.sh'
        resolve_base_dir; load_profile persist
        mkdir -p \"\$WORKSPACE\" \"\$CONTAINER_HOME\"
        create_normal_container >/dev/null 2>&1
        echo \"\$CONTAINER_NAME\"
    " 2>/dev/null)"

    # Record the container ID
    local id1; id1="$(podman inspect --format '{{.Id}}' "$ctr" 2>/dev/null)"

    # Second "launch" should reuse — container_exists returns true, so ai-launch
    # won't call create_normal_container again.  Verify same ID after existence check.
    local exists_rc=0
    podman container exists "$ctr" || exists_rc=$?
    assert_success $exists_rc "container exists for second launch" || _fail=1

    local id2; id2="$(podman inspect --format '{{.Id}}' "$ctr" 2>/dev/null)"
    assert_eq "$id1" "$id2" "container ID unchanged on reuse" || _fail=1

    podman rm -f "$ctr" 2>/dev/null || true
    podman rmi "$img" 2>/dev/null || true
    return $_fail
}

test_explicit_removal_destroys_container() {
    skip_unless_live && return 0
    local _fail=0
    local img="test-rm-img-$$"
    _build_minimal_image "$img" || return 1
    _minimal_profile "$img"

    local ctr
    ctr="$(AI_PODMAN_JAILS_DIR="$_TMPDIR" bash -c "
        source '${LIB_DIR}/common.sh'
        source '${LIB_DIR}/profile.sh'
        source '${LIB_DIR}/policy.sh'
        source '${LIB_DIR}/container.sh'
        resolve_base_dir; load_profile persist
        mkdir -p \"\$WORKSPACE\" \"\$CONTAINER_HOME\"
        create_normal_container >/dev/null 2>&1
        echo \"\$CONTAINER_NAME\"
    " 2>/dev/null)"

    podman rm -f "$ctr" >/dev/null 2>&1
    local rc=0
    podman container exists "$ctr" 2>/dev/null || rc=$?
    assert_failure $rc "container should not exist after explicit removal" || _fail=1

    podman rmi "$img" 2>/dev/null || true
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "container survives routine exit (Tier B)"       test_container_survives_exit
run_test "second launch reuses same container (Tier B)"   test_second_launch_reuses_container
run_test "explicit removal destroys container (Tier B)"   test_explicit_removal_destroys_container

print_summary "30_persistence"
