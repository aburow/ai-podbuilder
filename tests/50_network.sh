#!/usr/bin/env bash
# T6a — Network policy (AC7). Tier A: arg inspection. Tier B: connectivity check.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

_dry_run_with_net() {
    local net_mode="$1"
    # Write a profile with the requested NETWORK_MODE
    local prof="${_TMPDIR}/profiles/nettest.env"
    sed "s|^|# |" /dev/null > "$prof"  # clear
    cat > "$prof" <<EOF
PROFILE_NAME="nettest"
CONTAINER_NAME="test-net-ctr-$$"
IMAGE_NAME="test-net-img"
IMAGE_DIR="${_TMPDIR}/net-image"
WORKSPACE="${_TMPDIR}/net-ws"
CONTAINER_HOME="${_TMPDIR}/net-home"
BASHRC="${_TMPDIR}/.bashrc"
WORKDIR="/workspace"
BUILD_ARGS=""
NETWORK_MODE="${net_mode}"
EOF
    DRY_RUN=1 CODEX_JAILS_DIR="$_TMPDIR" PATH="${STUBS_DIR}:${PATH}" \
        "${BIN_DIR}/ai-launch" nettest shell 2>/dev/null
}

_dry_run_default_net() {
    local prof="${_TMPDIR}/profiles/netdef.env"
    cat > "$prof" <<EOF
PROFILE_NAME="netdef"
CONTAINER_NAME="test-netdef-ctr-$$"
IMAGE_NAME="test-netdef-img"
IMAGE_DIR="${_TMPDIR}/netdef-image"
WORKSPACE="${_TMPDIR}/netdef-ws"
CONTAINER_HOME="${_TMPDIR}/netdef-home"
BASHRC="${_TMPDIR}/.bashrc"
WORKDIR="/workspace"
BUILD_ARGS=""
EOF
    DRY_RUN=1 CODEX_JAILS_DIR="$_TMPDIR" PATH="${STUBS_DIR}:${PATH}" \
        "${BIN_DIR}/ai-launch" netdef shell 2>/dev/null
}

# ── Tier A ────────────────────────────────────────────────────────────────────

test_network_none_produces_none_flag() {
    local _fail=0
    local out; out="$(_dry_run_with_net none)"
    assert_contains "--network" "$out" || _fail=1
    assert_contains "none"      "$out" || _fail=1
    return $_fail
}

test_default_network_uses_slirp4netns() {
    local _fail=0
    local out; out="$(_dry_run_default_net)"
    assert_contains "--network"     "$out" || _fail=1
    assert_contains "slirp4netns"  "$out" || _fail=1
    return $_fail
}

# ── Tier B ────────────────────────────────────────────────────────────────────

test_network_none_is_offline_live() {
    skip_unless_live && return 0
    local _fail=0

    local img="test-net-img-$$"
    mkdir -p "${_TMPDIR}/net-image"
    cat > "${_TMPDIR}/net-image/Containerfile" <<'EOF'
FROM busybox:latest
EOF
    podman build -q -t "$img" "${_TMPDIR}/net-image" >/dev/null 2>&1

    # Try to reach an external host; must fail in --network none
    local out rc=0
    out="$(podman run --rm --network none "$img" \
        sh -c 'wget -q --timeout=3 http://1.1.1.1 -O /dev/null 2>&1' 2>&1)" || rc=$?
    assert_failure $rc "container with --network none must be offline" || _fail=1

    podman rmi "$img" 2>/dev/null || true
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "NETWORK_MODE=none → --network none in args"        test_network_none_produces_none_flag
run_test "default NETWORK_MODE → --network slirp4netns"      test_default_network_uses_slirp4netns
run_test "network none container is offline (Tier B)"        test_network_none_is_offline_live

print_summary "50_network"
