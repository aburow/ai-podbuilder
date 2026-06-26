#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# 2026 - Anthony Burow - https://github.com/aburow
# Resume reuses the exact agent-specific image when it already exists.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SELF_DIR}/helpers/setup.bash"

test_existing_agent_image_skips_build() {
    mkdir -p "${_TMPDIR}/project/bootstrap" "${_TMPDIR}/fakebin"
    cp "${REPO_ROOT}/config/agents.d/codex.env" "${_TMPDIR}/project/bootstrap/agent.env"
    cat > "${_TMPDIR}/fakebin/podman" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "image" && "$2" == "exists" ]]; then exit 0; fi
echo "UNEXPECTED_BUILD:$*" >&2
exit 1
EOF
    chmod +x "${_TMPDIR}/fakebin/podman"

    local _helper="${_TMPDIR}/helper.sh"
    cat > "$_helper" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
export PATH='${_TMPDIR}/fakebin':"\$PATH"
export AI_PODMAN_JAILS_DIR='${_TMPDIR}'
export SLUG='resume-test'
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/registry.sh'
source '${LIB_DIR}/bootstrap_image.sh'
ensure_bootstrap_image '${_TMPDIR}/project'
printf '%s\n' "\$BOOTSTRAP_IMAGE_TAG"
SCRIPT

    local out rc=0
    out="$(bash "$_helper" 2>&1)" || rc=$?
    assert_success "$rc" || return 1
    assert_contains "bootstrap-resume-test:codex-" "$out" || return 1
    assert_not_contains "UNEXPECTED_BUILD" "$out"
}

run_test "resume reuses existing agent-specific image" test_existing_agent_image_skips_build

print_summary "test_install_idempotent_resume"
