#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# 2026 - Anthony Burow - https://github.com/aburow
# T5b — Builder privilege and ephemerality (AC5, AC6).
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

_dry_run_builder() {
    DRY_RUN=1 AI_PODMAN_JAILS_DIR="$_TMPDIR" PATH="${STUBS_DIR}:${PATH}" \
        "${BIN_DIR}/ai-launch" esp32 builder 2>/dev/null
}

_dry_run_normal() {
    DRY_RUN=1 AI_PODMAN_JAILS_DIR="$_TMPDIR" PATH="${STUBS_DIR}:${PATH}" \
        "${BIN_DIR}/ai-launch" esp32 shell 2>/dev/null
}

# ── Tier A checks ─────────────────────────────────────────────────────────────

test_builder_has_privileged() {
    local _fail=0
    local out; out="$(_dry_run_builder)"
    assert_contains "DRY_RUN:run"   "$out" "builder uses podman run (not create)" || _fail=1
    assert_contains "--privileged"  "$out"                                         || _fail=1
    return $_fail
}

test_builder_has_rm_flag() {
    local _fail=0
    local out; out="$(_dry_run_builder)"
    assert_contains "--rm" "$out" "builder must be ephemeral (--rm)" || _fail=1
    return $_fail
}

test_builder_uses_builder_name() {
    local _fail=0
    local out; out="$(_dry_run_builder)"
    assert_contains "-builder" "$out" "builder container name ends in -builder" || _fail=1
    return $_fail
}

test_normal_modes_never_privileged() {
    local _fail=0
    local out; out="$(_dry_run_normal)"
    assert_not_contains "--privileged" "$out" "normal mode must never be privileged" || _fail=1
    return $_fail
}

test_normal_mode_has_no_rm() {
    local _fail=0
    local out; out="$(_dry_run_normal)"
    # --rm should NOT appear in normal (persistent) mode
    assert_not_contains " --rm" "$out" "normal mode must not have --rm" || _fail=1
    return $_fail
}

# ── Tier B: builder container gone after exit; normal container intact ────────

test_builder_ephemeral_live() {
    skip_unless_live && return 0
    local _fail=0

    # Build a minimal image
    local img="test-builder-img-$$"
    mkdir -p "${_TMPDIR}/minimal-image"
    cat > "${_TMPDIR}/minimal-image/Containerfile" <<'EOF'
FROM busybox:latest
RUN adduser -D builder
EOF
    podman build -q -t "$img" "${_TMPDIR}/minimal-image" >/dev/null 2>&1

    # Write a profile pointing at the temp image
    cat > "${_TMPDIR}/profiles/bldr.env" <<EOF
PROFILE_NAME="bldr"
CONTAINER_NAME="test-bldr-normal-$$"
IMAGE_NAME="${img}"
IMAGE_DIR="${_TMPDIR}/minimal-image"
WORKSPACE="${_TMPDIR}/bldr-ws"
CONTAINER_HOME="${_TMPDIR}/bldr-home"
BASHRC="${_TMPDIR}/.bashrc"
WORKDIR="/workspace"
BUILD_ARGS=""
EOF
    mkdir -p "${_TMPDIR}/bldr-ws" "${_TMPDIR}/bldr-home"

    # Run the builder with a one-shot command (no interactive TTY)
    podman run --privileged --rm \
        --name "test-bldr-normal-$$-builder" \
        -v "${_TMPDIR}/bldr-ws:/workspace:Z" \
        -e HOME="${_TMPDIR}/bldr-home" \
        -w /workspace \
        "$img" sh -c "echo done" >/dev/null 2>&1

    # Builder container should be gone (--rm)
    local rc=0
    podman container exists "test-bldr-normal-$$-builder" 2>/dev/null || rc=$?
    assert_failure $rc "builder container must be gone after exit (--rm)" || _fail=1

    podman rmi "$img" 2>/dev/null || true
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "builder mode includes --privileged"             test_builder_has_privileged
run_test "builder mode includes --rm (ephemeral)"         test_builder_has_rm_flag
run_test "builder container name ends in -builder"        test_builder_uses_builder_name
run_test "normal modes never include --privileged"        test_normal_modes_never_privileged
run_test "normal mode does not include --rm"              test_normal_mode_has_no_rm
run_test "builder container removed after exit (Tier B)"  test_builder_ephemeral_live

print_summary "41_builder"
