#!/usr/bin/env bash
# T9 — Build runs host-side; bootstrap container neither builds nor accesses socket (AC22, AC28).
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

# ── Tests ─────────────────────────────────────────────────────────────────────

test_launch_bootstrap_does_not_pass_socket() {
    # Inspect the launch_bootstrap function source for absence of socket mount.
    local _fail=0
    local _launch_lib="${LIB_DIR}/launch.sh"
    [[ -f "$_launch_lib" ]] || { printf '    launch.sh not found\n' >&2; return 1; }

    # Should not have a bind-mount of the podman socket.
    if grep -vE '^\s*#' "$_launch_lib" | grep -qE 'podman\.sock|/run/user.*podman'; then
        printf '    FAIL: launch.sh mounts the podman socket!\n' >&2
        _fail=1
    fi
    # Should not pass --privileged (check non-comment lines only).
    if grep -vE '^\s*#' "$_launch_lib" | grep -qE -- '--privileged'; then
        printf '    FAIL: launch.sh passes --privileged!\n' >&2
        _fail=1
    fi
    return $_fail
}

test_launch_bootstrap_comment_confirms_no_socket() {
    # The launch.sh source should have a comment explicitly noting the socket is excluded.
    local _fail=0
    local _launch_lib="${LIB_DIR}/launch.sh"
    [[ -f "$_launch_lib" ]] || { printf '    launch.sh not found\n' >&2; return 1; }

    if ! grep -qiE 'NOT.*socket|socket.*NOT|NOT.*privileged|Explicitly' "$_launch_lib"; then
        printf '    WARN: launch.sh has no explicit comment about not mounting socket\n' >&2
        # Not a hard failure — just a documentation concern.
    fi
    return $_fail
}

test_launch_bootstrap_uses_userns_keep_id() {
    local _fail=0
    local _launch_lib="${LIB_DIR}/launch.sh"
    [[ -f "$_launch_lib" ]] || { printf '    launch.sh not found\n' >&2; return 1; }

    if ! grep -q 'userns=keep-id' "$_launch_lib"; then
        printf '    FAIL: launch.sh does not use --userns=keep-id\n' >&2
        _fail=1
    fi
    return $_fail
}

test_launch_bootstrap_mounts_project_not_host_home() {
    local _fail=0
    local _launch_lib="${LIB_DIR}/launch.sh"
    [[ -f "$_launch_lib" ]] || { printf '    launch.sh not found\n' >&2; return 1; }

    # Should mount the project dir at /project.
    if ! grep -q '/project' "$_launch_lib"; then
        printf '    FAIL: launch.sh does not mount at /project\n' >&2
        _fail=1
    fi

    # Should NOT mount $HOME directly.
    if grep -qE '\$HOME:/|"\$HOME":|"${HOME}"/' "$_launch_lib"; then
        printf '    FAIL: launch.sh mounts $HOME directly into container\n' >&2
        _fail=1
    fi
    return $_fail
}

test_build_log_written_to_project_bootstrap() {
    # Verify that quality_gate.sh writes build.log to the project bootstrap dir
    # (not inside the container), so the container can read it via the mount.
    local _fail=0
    local _gate_lib="${LIB_DIR}/quality_gate.sh"
    [[ -f "$_gate_lib" ]] || { printf '    quality_gate.sh not found\n' >&2; return 1; }

    if ! grep -q 'build.log' "$_gate_lib"; then
        printf '    FAIL: quality_gate.sh does not write build.log\n' >&2
        _fail=1
    fi
    # The log path should be under bootstrap (which is the /project/bootstrap mount point).
    if ! grep -qE 'bootstrap/build\.log' "$_gate_lib"; then
        printf '    FAIL: build.log not under bootstrap/\n' >&2
        _fail=1
    fi
    return $_fail
}

test_quality_gate_runs_on_host() {
    # Verify that run_quality_gate is called from the host process (in coordination.sh/launch.sh),
    # not from inside the container via podman exec.
    local _fail=0
    local _coord_lib="${LIB_DIR}/coordination.sh"
    [[ -f "$_coord_lib" ]] || { printf '    coordination.sh not found\n' >&2; return 1; }

    # The poll_requests function should call run_quality_gate directly.
    if ! grep -q 'run_quality_gate' "$_coord_lib"; then
        printf '    FAIL: coordination.sh does not call run_quality_gate\n' >&2
        _fail=1
    fi
    # Should not use podman exec to run the gate.
    if grep -qE 'podman exec.*quality_gate|podman exec.*build' "$_coord_lib"; then
        printf '    FAIL: quality gate is run via podman exec (should be host-side)\n' >&2
        _fail=1
    fi
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "launch.sh: no host socket mount"                    test_launch_bootstrap_does_not_pass_socket
run_test "launch.sh: has comment about socket exclusion"       test_launch_bootstrap_comment_confirms_no_socket
run_test "launch.sh: uses --userns=keep-id"                   test_launch_bootstrap_uses_userns_keep_id
run_test "launch.sh: mounts project, not \$HOME"              test_launch_bootstrap_mounts_project_not_host_home
run_test "quality_gate.sh: writes build.log under bootstrap/" test_build_log_written_to_project_bootstrap
run_test "coordination.sh: run_quality_gate called host-side" test_quality_gate_runs_on_host

print_summary "test_gate_no_nested_build"
