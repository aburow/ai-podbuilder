#!/usr/bin/env bash
# T6c — SELinux mode selection (AC9). Tier A (DRY_RUN).
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

_dry_run_selinux() {
    local mode="$1"
    local prof="${_TMPDIR}/profiles/selinux_${mode}.env"
    cat > "$prof" <<EOF
PROFILE_NAME="selinux_${mode}"
CONTAINER_NAME="test-selinux-$$"
IMAGE_NAME="test-selinux-img"
IMAGE_DIR="${_TMPDIR}/selinux-image"
WORKSPACE="${_TMPDIR}/selinux-ws"
CONTAINER_HOME="${_TMPDIR}/selinux-home"
BASHRC="${_TMPDIR}/.bashrc"
WORKDIR="/workspace"
BUILD_ARGS=""
SELINUX_MODE="${mode}"
EOF
    DRY_RUN=1 CODEX_JAILS_DIR="$_TMPDIR" PATH="${STUBS_DIR}:${PATH}" \
        "${BIN_DIR}/ai-launch" "selinux_${mode}" shell 2>/dev/null
}

_dry_run_default() {
    # Profile with no SELINUX_MODE set
    local prof="${_TMPDIR}/profiles/selinux_default.env"
    cat > "$prof" <<EOF
PROFILE_NAME="selinux_default"
CONTAINER_NAME="test-selinux-def-$$"
IMAGE_NAME="test-selinux-def-img"
IMAGE_DIR="${_TMPDIR}/selinux-image"
WORKSPACE="${_TMPDIR}/selinux-ws"
CONTAINER_HOME="${_TMPDIR}/selinux-home"
BASHRC="${_TMPDIR}/.bashrc"
WORKDIR="/workspace"
BUILD_ARGS=""
EOF
    DRY_RUN=1 CODEX_JAILS_DIR="$_TMPDIR" PATH="${STUBS_DIR}:${PATH}" \
        "${BIN_DIR}/ai-launch" selinux_default shell 2>/dev/null
}

test_enforce_mode_omits_label_disable() {
    local _fail=0
    local out; out="$(_dry_run_selinux enforce)"
    assert_not_contains "label=disable" "$out" \
        "enforce mode must not include label=disable" || _fail=1
    return $_fail
}

test_default_mode_includes_label_disable() {
    local _fail=0
    local out; out="$(_dry_run_default)"
    assert_contains "label=disable" "$out" \
        "default (disable) SELinux mode must include label=disable" || _fail=1
    return $_fail
}

test_disable_mode_includes_label_disable() {
    local _fail=0
    local out; out="$(_dry_run_selinux disable)"
    assert_contains "label=disable" "$out" \
        "SELINUX_MODE=disable must include label=disable" || _fail=1
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "SELINUX_MODE=enforce omits label=disable"          test_enforce_mode_omits_label_disable
run_test "no SELINUX_MODE (default) includes label=disable"  test_default_mode_includes_label_disable
run_test "SELINUX_MODE=disable includes label=disable"       test_disable_mode_includes_label_disable

print_summary "52_selinux"
