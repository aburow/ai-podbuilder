#!/usr/bin/env bash
# T6b — Per-profile extras: devices, hosts, env appear verbatim for declaring
# profile only (AC8). All Tier A (DRY_RUN).
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

_dry_run() {
    local prof="$1"
    DRY_RUN=1 CODEX_JAILS_DIR="$_TMPDIR" PATH="${STUBS_DIR}:${PATH}" \
        "${BIN_DIR}/ai-launch" "$prof" shell 2>/dev/null
}

_make_profile_with_extras() {
    cat > "${_TMPDIR}/profiles/extras.env" <<EOF
PROFILE_NAME="extras"
CONTAINER_NAME="test-extras-$$"
IMAGE_NAME="test-extras-img"
IMAGE_DIR="${_TMPDIR}/extras-image"
WORKSPACE="${_TMPDIR}/extras-ws"
CONTAINER_HOME="${_TMPDIR}/extras-home"
BASHRC="${_TMPDIR}/.bashrc"
WORKDIR="/workspace"
BUILD_ARGS=""
EXTRA_DEVICES=("--device=/dev/ttyUSB0")
EXTRA_HOSTS=("idf-mirror.local:192.168.1.10")
EXTRA_ENV=("-e" "IDF_VERSION=5.2")
EOF
}

_make_profile_without_extras() {
    cat > "${_TMPDIR}/profiles/noextras.env" <<EOF
PROFILE_NAME="noextras"
CONTAINER_NAME="test-noextras-$$"
IMAGE_NAME="test-noextras-img"
IMAGE_DIR="${_TMPDIR}/noextras-image"
WORKSPACE="${_TMPDIR}/noextras-ws"
CONTAINER_HOME="${_TMPDIR}/noextras-home"
BASHRC="${_TMPDIR}/.bashrc"
WORKDIR="/workspace"
BUILD_ARGS=""
EOF
}

test_extra_device_appears_in_args() {
    local _fail=0
    _make_profile_with_extras
    local out; out="$(_dry_run extras)"
    assert_contains "--device=/dev/ttyUSB0" "$out" || _fail=1
    return $_fail
}

test_extra_host_appears_in_args() {
    local _fail=0
    _make_profile_with_extras
    local out; out="$(_dry_run extras)"
    assert_contains "idf-mirror.local" "$out" || _fail=1
    return $_fail
}

test_extra_env_appears_in_args() {
    local _fail=0
    _make_profile_with_extras
    local out; out="$(_dry_run extras)"
    assert_contains "IDF_VERSION=5.2" "$out" || _fail=1
    return $_fail
}

test_extras_absent_from_non_declaring_profile() {
    local _fail=0
    _make_profile_with_extras
    _make_profile_without_extras
    local out; out="$(_dry_run noextras)"
    assert_not_contains "--device=/dev/ttyUSB0"       "$out" "device must not leak" || _fail=1
    assert_not_contains "idf-mirror.local"             "$out" "host must not leak"   || _fail=1
    assert_not_contains "IDF_VERSION"                  "$out" "env must not leak"    || _fail=1
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "EXTRA_DEVICES appears verbatim in assembled args"       test_extra_device_appears_in_args
run_test "EXTRA_HOSTS appears verbatim in assembled args"         test_extra_host_appears_in_args
run_test "EXTRA_ENV appears verbatim in assembled args"           test_extra_env_appears_in_args
run_test "extras absent from non-declaring profile's args"        test_extras_absent_from_non_declaring_profile

print_summary "51_extras"
