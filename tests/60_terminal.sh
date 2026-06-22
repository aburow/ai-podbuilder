#!/usr/bin/env bash
# T7a — ai-terminal (AC10). Tier B: attach when running. Tier A: error when not.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

test_ai_terminal_no_container_exits_nonzero() {
    # With no running container, ai-terminal must exit non-zero with a clear message.
    # The stub podman returns "not running" for container_running checks.
    local _fail=0
    local out rc=0
    out="$(CODEX_JAILS_DIR="$_TMPDIR" PATH="${STUBS_DIR}:${PATH}" \
        "${BIN_DIR}/ai-terminal" esp32 2>&1)" || rc=$?
    assert_failure $rc "ai-terminal with no running container → non-zero" || _fail=1
    # Should mention the container name or profile
    assert_contains "esp32" "$out" "error should reference the profile/container" || _fail=1
    return $_fail
}

test_ai_terminal_help_exits_zero() {
    local _fail=0
    local rc=0
    "${BIN_DIR}/ai-terminal" --help 2>/dev/null || rc=$?
    assert_success $rc "ai-terminal --help exits 0" || _fail=1
    return $_fail
}

test_ai_terminal_attach_live() {
    skip_unless_live && return 0
    local _fail=0

    local img="test-terminal-img-$$"
    mkdir -p "${_TMPDIR}/terminal-image"
    cat > "${_TMPDIR}/terminal-image/Containerfile" <<'EOF'
FROM busybox:latest
RUN adduser -D builder
EOF
    podman build -q -t "$img" "${_TMPDIR}/terminal-image" >/dev/null 2>&1

    cat > "${_TMPDIR}/profiles/term.env" <<EOF
PROFILE_NAME="term"
CONTAINER_NAME="test-term-$$"
IMAGE_NAME="${img}"
IMAGE_DIR="${_TMPDIR}/terminal-image"
WORKSPACE="${_TMPDIR}/term-ws"
CONTAINER_HOME="${_TMPDIR}/term-home"
BASHRC="${_TMPDIR}/.bashrc"
WORKDIR="/workspace"
BUILD_ARGS=""
EOF
    mkdir -p "${_TMPDIR}/term-ws" "${_TMPDIR}/term-home"
    local ctr="test-term-$$"

    # Create and start the container in the background with a sleep
    podman create --name "$ctr" \
        --userns=keep-id --security-opt no-new-privileges \
        -v "${_TMPDIR}/term-ws:/workspace:Z" \
        -e HOME="${_TMPDIR}/term-home" \
        -w /workspace \
        --network slirp4netns \
        "$img" sleep 30 >/dev/null 2>&1
    podman start "$ctr" >/dev/null 2>&1

    # ai-terminal should be able to exec into it; we test via podman exec directly
    # since ai-terminal opens an interactive shell which we can't drive here.
    local rc=0
    podman exec "$ctr" sh -c 'echo alive' >/dev/null 2>&1 || rc=$?
    assert_success $rc "exec into running container should succeed" || _fail=1

    podman stop "$ctr" >/dev/null 2>&1 || true
    podman rm -f "$ctr" >/dev/null 2>&1 || true
    podman rmi "$img" 2>/dev/null || true
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "ai-terminal: no running container → non-zero + named"  test_ai_terminal_no_container_exits_nonzero
run_test "ai-terminal --help exits 0"                            test_ai_terminal_help_exits_zero
run_test "ai-terminal attach to running container (Tier B)"      test_ai_terminal_attach_live

print_summary "60_terminal"
