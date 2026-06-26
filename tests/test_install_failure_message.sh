#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# 2026 - Anthony Burow - https://github.com/aburow
# Build-time install failures stop ai-new before container launch.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SELF_DIR}/helpers/setup.bash"

test_build_failure_names_agent_and_containerfile() {
    mkdir -p "${_TMPDIR}/project/bootstrap" "${_TMPDIR}/fakebin"
    cp "${REPO_ROOT}/config/agents.d/gemini.env" "${_TMPDIR}/project/bootstrap/agent.env"
    cat > "${_TMPDIR}/fakebin/podman" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "image" && "$2" == "exists" ]]; then exit 1; fi
if [[ "$1" == "build" ]]; then exit 42; fi
exit 1
EOF
    chmod +x "${_TMPDIR}/fakebin/podman"

    local _helper="${_TMPDIR}/helper.sh"
    cat > "$_helper" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
export PATH='${_TMPDIR}/fakebin':"\$PATH"
export AI_PODMAN_JAILS_DIR='${_TMPDIR}'
export SLUG='failure-test'
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/registry.sh'
source '${LIB_DIR}/bootstrap_image.sh'
ensure_bootstrap_image '${_TMPDIR}/project'
SCRIPT

    local out rc=0
    out="$(bash "$_helper" 2>&1)" || rc=$?
    assert_failure "$rc" || return 1
    assert_contains "gemini" "$out" || return 1
    assert_contains "Containerfile.bootstrap" "$out"
}

test_generated_step_contains_registry_package() {
    local _helper="${_TMPDIR}/render.sh"
    cat > "$_helper" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/registry.sh'
source '${LIB_DIR}/bootstrap_image.sh'
_write_bootstrap_containerfile '${_TMPDIR}/Containerfile.bootstrap' npm-global @google/gemini-cli '' gemini gemini
SCRIPT
    bash "$_helper"
    assert_contains "@google/gemini-cli" "$(cat "${_TMPDIR}/Containerfile.bootstrap")"
}

run_test "build failure names selected agent and Containerfile" test_build_failure_names_agent_and_containerfile
run_test "generated install step contains registry package"      test_generated_step_contains_registry_package

print_summary "test_install_failure_message"
