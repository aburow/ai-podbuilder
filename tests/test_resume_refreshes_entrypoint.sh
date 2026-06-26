#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# 2026 - Anthony Burow - https://github.com/aburow
# Existing projects must receive the current framework-owned start-here.sh.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SELF_DIR}/helpers/setup.bash"

test_refresh_replaces_stale_entrypoint() {
    local _project="${_TMPDIR}/projects/refresh"
    mkdir -p "${_project}/bootstrap/home"
    printf '#!/bin/sh\necho stale\n' > "${_project}/bootstrap/home/start-here.sh"
    mkdir -p "${_TMPDIR}/lib"
    cp "${REPO_ROOT}/lib/start-here.sh" "${_TMPDIR}/lib/start-here.sh"
    chmod 0644 "${_TMPDIR}/lib/start-here.sh"

    local _helper="${_TMPDIR}/refresh-helper.sh"
    cat > "$_helper" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
export AI_PODMAN_JAILS_DIR='${_TMPDIR}'
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/slug.sh'
source '${LIB_DIR}/scaffold.sh'
refresh_bootstrap_entrypoint '${_project}'
SCRIPT
    bash "$_helper"

    local out
    out="$(cat "${_project}/bootstrap/home/start-here.sh")"
    assert_contains "--prompt-interactive" "$out" || return 1
    [[ -x "${_project}/bootstrap/home/start-here.sh" ]]
}

test_resume_path_calls_refresh_before_build() {
    local src refresh_line build_line
    src="${REPO_ROOT}/bin/ai-new"
    refresh_line="$(grep -n 'refresh_bootstrap_entrypoint "$PROJECT_ROOT"' "$src" | head -1 | cut -d: -f1)"
    build_line="$(grep -n 'ensure_bootstrap_image "$PROJECT_ROOT"' "$src" | head -1 | cut -d: -f1)"
    [[ -n "$refresh_line" && -n "$build_line" && "$refresh_line" -lt "$build_line" ]]
}

run_test "refresh replaces stale entrypoint and restores execute bit" test_refresh_replaces_stale_entrypoint
run_test "resume refreshes entrypoint before image launch"            test_resume_path_calls_refresh_before_build

print_summary "test_resume_refreshes_entrypoint"
