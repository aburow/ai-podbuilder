#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# 2026 - Anthony Burow - https://github.com/aburow
# Regression: ai-new must enter start-here.sh so the selected runtime installer runs.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

_run_launch() {
    local _resume="$1"
    local _shell_on_exit="${2:-0}"
    local _project="${_TMPDIR}/projects/entrypoint"
    mkdir -p "${_project}/bootstrap/home" "${_TMPDIR}/lib" "${_TMPDIR}/prompts"

    local _helper="${_TMPDIR}/launch-helper.sh"
    cat > "$_helper" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/launch.sh'
export AI_PODMAN_JAILS_DIR='${_TMPDIR}'
export SLUG='entrypoint'
launch_bootstrap '${_project}' '${_resume}' '${_shell_on_exit}'
SCRIPT
    bash "$_helper" 2>&1
}

test_create_launches_start_here_directly() {
    local _fail=0
    local out rc=0
    out="$(_run_launch 0)" || rc=$?

    assert_success "$rc" "stubbed bootstrap launch should succeed" || _fail=1
    assert_contains "localhost/ai-new/bootstrap:latest /project/bootstrap/home/start-here.sh" "$out" \
        "create must execute the installer/agent entrypoint" || _fail=1
    assert_not_contains "localhost/ai-new/bootstrap:latest /bin/bash" "$out" \
        "create must not stop at an unprimed shell" || _fail=1
    return "$_fail"
}

test_resume_passes_resume_to_start_here() {
    local _fail=0
    local out rc=0
    out="$(_run_launch 1)" || rc=$?

    assert_success "$rc" "stubbed resume launch should succeed" || _fail=1
    assert_contains "/project/bootstrap/home/start-here.sh --resume" "$out" \
        "resume must preserve the pinned runtime path" || _fail=1
    return "$_fail"
}

test_shell_on_exit_passed_to_start_here() {
    local out rc=0
    out="$(_run_launch 1 1)" || rc=$?

    assert_success "$rc" || return 1
    assert_contains "/project/bootstrap/home/start-here.sh --resume --shell-on-exit" "$out" \
        "shell fallback flag must reach the in-container entrypoint"
}

run_test "create launch reaches start-here installer entrypoint" test_create_launches_start_here_directly
run_test "resume launch passes --resume to start-here"          test_resume_passes_resume_to_start_here
run_test "launch passes --shell-on-exit to start-here"          test_shell_on_exit_passed_to_start_here

print_summary "test_launch_entrypoint"
