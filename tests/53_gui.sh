#!/usr/bin/env bash
# T6c — Optional GUI forwarding: X11 args appear only when requested and host
# display state is present.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

_dry_run() {
    local prof="$1"
    shift
    env "$@" DRY_RUN=1 CODEX_JAILS_DIR="$_TMPDIR" PATH="${STUBS_DIR}:${PATH}" \
        "${BIN_DIR}/ai-launch" "$prof" shell 2>&1
}

_make_profile_with_x11() {
    cat > "${_TMPDIR}/profiles/gui.env" <<EOF
PROFILE_NAME="gui"
CONTAINER_NAME="test-gui-$$"
IMAGE_NAME="test-gui-img"
IMAGE_DIR="${_TMPDIR}/gui-image"
WORKSPACE="${_TMPDIR}/gui-ws"
CONTAINER_HOME="${_TMPDIR}/gui-home"
BASHRC="${_TMPDIR}/.bashrc"
WORKDIR="/workspace"
BUILD_ARGS=""
GUI_FORWARD="x11"
GUI_X11_SOCKET_DIR="${_TMPDIR}/x11-sock"
GUI_XAUTHORITY_HOST="${_TMPDIR}/.Xauthority"
EOF
}

test_x11_forwarding_adds_display_and_mounts() {
    local _fail=0
    _make_profile_with_x11
    mkdir -p "${_TMPDIR}/x11-sock"
    : > "${_TMPDIR}/.Xauthority"
    local out
    out="$(_dry_run gui DISPLAY=:99)"
    assert_contains "DISPLAY=:99" "$out" "DISPLAY should be passed through" || _fail=1
    assert_contains "${_TMPDIR}/x11-sock:/tmp/.X11-unix:ro" "$out" "X11 socket mount should be added" || _fail=1
    assert_contains "${_TMPDIR}/.Xauthority:/tmp/.ai-launch.Xauthority:ro" "$out" "Xauthority mount should be added" || _fail=1
    assert_contains "XAUTHORITY=/tmp/.ai-launch.Xauthority" "$out" "container XAUTHORITY should be set" || _fail=1
    return $_fail
}

test_x11_forwarding_warns_without_display() {
    local _fail=0
    _make_profile_with_x11
    mkdir -p "${_TMPDIR}/x11-sock"
    : > "${_TMPDIR}/.Xauthority"
    local out
    out="$(_dry_run gui DISPLAY=)"
    assert_contains "DISPLAY is unset" "$out" "missing DISPLAY should warn" || _fail=1
    assert_not_contains "/tmp/.X11-unix:ro" "$out" "X11 mount should be omitted without DISPLAY" || _fail=1
    return $_fail
}

test_gui_forwarding_absent_by_default() {
    local _fail=0
    cat > "${_TMPDIR}/profiles/nogui.env" <<EOF
PROFILE_NAME="nogui"
CONTAINER_NAME="test-nogui-$$"
IMAGE_NAME="test-nogui-img"
IMAGE_DIR="${_TMPDIR}/nogui-image"
WORKSPACE="${_TMPDIR}/nogui-ws"
CONTAINER_HOME="${_TMPDIR}/nogui-home"
BASHRC="${_TMPDIR}/.bashrc"
WORKDIR="/workspace"
BUILD_ARGS=""
EOF
    mkdir -p "${_TMPDIR}/x11-sock"
    : > "${_TMPDIR}/.Xauthority"
    local out
    out="$(_dry_run nogui DISPLAY=:99)"
    assert_not_contains "DISPLAY=:99" "$out" "DISPLAY must not leak into non-GUI profiles" || _fail=1
    assert_not_contains "/tmp/.X11-unix:ro" "$out" "X11 mount must not leak into non-GUI profiles" || _fail=1
    return $_fail
}

run_test "GUI_FORWARD=x11 adds DISPLAY, socket, and Xauthority args" test_x11_forwarding_adds_display_and_mounts
run_test "GUI_FORWARD=x11 warns and skips when DISPLAY is missing"    test_x11_forwarding_warns_without_display
run_test "GUI forwarding is absent by default"                        test_gui_forwarding_absent_by_default

print_summary "53_gui"
