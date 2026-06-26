#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# 2026 - Anthony Burow - https://github.com/aburow
# Regression: launch_bootstrap must return to ai-new so EXIT cleanup can remove
# the session lock after the disposable container exits.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SELF_DIR}/helpers/setup.bash"

test_launch_does_not_replace_supervisor() {
    local src
    src="$(cat "${REPO_ROOT}/lib/launch.sh")"
    assert_not_contains "exec podman" "$src" \
        "exec would bypass heartbeat and lock cleanup"
}

test_ai_new_cleanup_stops_heartbeat_and_releases_lock() {
    local src
    src="$(cat "${REPO_ROOT}/bin/ai-new")"
    assert_contains "kill \"\$_HEARTBEAT_PID\"" "$src" || return 1
    assert_contains "wait \"\$_HEARTBEAT_PID\"" "$src" || return 1
    assert_contains 'release_lock "$PROJECT_ROOT"' "$src" || return 1
    assert_contains "trap _cleanup_session EXIT" "$src"
}

test_cleanup_runs_after_stubbed_container_exit() {
    local _project="${_TMPDIR}/projects/cleanup"
    mkdir -p "${_project}/bootstrap/session.lock"

    local _helper="${_TMPDIR}/cleanup-helper.sh"
    cat > "$_helper" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/lock.sh'
source '${LIB_DIR}/launch.sh'
export AI_PODMAN_JAILS_DIR='${_TMPDIR}'
export PROJECT_ROOT='${_project}'
export SLUG='cleanup'
export BOOTSTRAP_IMAGE_TAG='localhost/test/cleanup:latest'
_HEARTBEAT_PID=''
_cleanup_session() {
    if [[ -n "\${_HEARTBEAT_PID:-}" ]]; then
        kill "\$_HEARTBEAT_PID" 2>/dev/null || true
        wait "\$_HEARTBEAT_PID" 2>/dev/null || true
    fi
    release_lock "\$PROJECT_ROOT"
}
trap _cleanup_session EXIT
launch_bootstrap "\$PROJECT_ROOT" 0
SCRIPT

    local rc=0
    bash "$_helper" >/dev/null 2>&1 || rc=$?
    assert_success "$rc" || return 1
    [[ ! -d "${_project}/bootstrap/session.lock" ]]
}

test_cleanup_runs_after_failed_container_exit() {
    local _project="${_TMPDIR}/projects/cleanup-failed"
    local _fakebin="${_TMPDIR}/fakebin"
    mkdir -p "${_project}/bootstrap/session.lock" "$_fakebin"
    cat > "${_fakebin}/podman" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == "rm" ]] && exit 0
exit 23
EOF
    chmod +x "${_fakebin}/podman"

    local _helper="${_TMPDIR}/cleanup-failed-helper.sh"
    cat > "$_helper" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
export PATH='${_fakebin}':"\$PATH"
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/lock.sh'
source '${LIB_DIR}/launch.sh'
export AI_PODMAN_JAILS_DIR='${_TMPDIR}'
export PROJECT_ROOT='${_project}'
export SLUG='cleanup-failed'
export BOOTSTRAP_IMAGE_TAG='localhost/test/cleanup:latest'
_HEARTBEAT_PID=''
_cleanup_session() { release_lock "\$PROJECT_ROOT"; }
trap _cleanup_session EXIT
launch_bootstrap "\$PROJECT_ROOT" 0
SCRIPT

    local rc=0
    bash "$_helper" >/dev/null 2>&1 || rc=$?
    assert_failure "$rc" || return 1
    [[ ! -d "${_project}/bootstrap/session.lock" ]]
}

test_launch_reports_container_exit_status() {
    local src
    src="$(cat "${REPO_ROOT}/lib/launch.sh")"
    assert_contains "Bootstrap container exited with status" "$src" || return 1
    assert_contains "Bootstrap container session ended normally" "$src"
}

test_ai_new_starts_host_coordination_worker() {
    local src
    src="$(cat "${REPO_ROOT}/bin/ai-new")"
    assert_contains 'poll_requests "$PROJECT_ROOT" &' "$src" || return 1
    assert_contains '_COORDINATION_PID=$!' "$src" || return 1
    assert_contains 'pkill -TERM -P "$_COORDINATION_PID"' "$src"
}

run_test "launcher returns instead of replacing supervisor"       test_launch_does_not_replace_supervisor
run_test "ai-new EXIT cleanup stops heartbeat and releases lock"   test_ai_new_cleanup_stops_heartbeat_and_releases_lock
run_test "stubbed container exit removes session lock"             test_cleanup_runs_after_stubbed_container_exit
run_test "failed container exit also removes session lock"         test_cleanup_runs_after_failed_container_exit
run_test "launcher reports normal and failed container exits"       test_launch_reports_container_exit_status
run_test "ai-new starts and cleans host coordination worker"        test_ai_new_starts_host_coordination_worker

print_summary "test_supervisor_cleanup"
