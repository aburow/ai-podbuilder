#!/usr/bin/env bash
# Selected-agent installation belongs to the generated Containerfile.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SELF_DIR}/helpers/setup.bash"

_render_agent_containerfile() {
    local _helper="${_TMPDIR}/render.sh"
    cat > "$_helper" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/registry.sh'
source '${LIB_DIR}/bootstrap_image.sh'
_write_bootstrap_containerfile '${_TMPDIR}/Containerfile.bootstrap' npm-global @openai/codex '' codex codex
SCRIPT
    bash "$_helper"
    cat "${_TMPDIR}/Containerfile.bootstrap"
}

test_agent_is_installed_by_containerfile() {
    local out
    out="$(_render_agent_containerfile)"
    assert_contains "RUN npm install --global @openai/codex" "$out" || return 1
    assert_contains "command -v codex" "$out"
}

test_start_here_does_not_install_on_launch() {
    local src
    src="$(cat "${REPO_ROOT}/lib/start-here.sh")"
    assert_not_contains "run_install_adapter" "$src" || return 1
    assert_not_contains "npm install" "$src"
}

test_launch_does_not_mount_host_install_library() {
    local src
    src="$(cat "${REPO_ROOT}/lib/launch.sh")"
    assert_not_contains "/start-here-lib" "$src"
}

test_build_context_excludes_project_secrets() {
    local src
    src="$(cat "${REPO_ROOT}/lib/bootstrap_image.sh")"
    assert_contains 'local _build_context="${AI_PODMAN_JAILS_DIR}/config"' "$src" || return 1
    assert_not_contains '"$(dirname "$_cfile")"' "$src"
}

test_ai_new_builds_before_launch() {
    local build_line launch_line
    build_line="$(grep -n 'ensure_bootstrap_image "$PROJECT_ROOT"' "${REPO_ROOT}/bin/ai-new" | tail -1 | cut -d: -f1)"
    launch_line="$(grep -n 'launch_bootstrap "$PROJECT_ROOT" 0' "${REPO_ROOT}/bin/ai-new" | cut -d: -f1)"
    [[ -n "$build_line" && -n "$launch_line" && "$build_line" -lt "$launch_line" ]]
}

test_install_generated_profile_absent() {
    # R3.3: install_generated_profile must not exist in lib/ or bin/
    local _found
    _found="$(grep -rl 'install_generated_profile' "${REPO_ROOT}/lib" "${REPO_ROOT}/bin" 2>/dev/null || true)"
    [[ -z "$_found" ]] || {
        printf '    install_generated_profile still present in:\n%s\n' "$_found" >&2
        return 1
    }
}

run_test "Containerfile installs selected agent"                  test_agent_is_installed_by_containerfile
run_test "start-here performs no runtime installation"            test_start_here_does_not_install_on_launch
run_test "launch exposes no host-side install library"             test_launch_does_not_mount_host_install_library
run_test "image build context excludes project secrets"            test_build_context_excludes_project_secrets
run_test "ai-new builds agent image before launch"                 test_ai_new_builds_before_launch
run_test "install_generated_profile absent from lib/ and bin/ (R3.3)" test_install_generated_profile_absent

print_summary "test_no_dead_install_code"
