#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# 2026 - Anthony Burow - https://github.com/aburow
# T8a — Remaining compatibility wrappers delegate to the right generic command.
# All Tier A (DRY_RUN intercept).
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

test_legacy_project_wrappers_removed() {
    local _fail=0
    local wrapper
    for wrapper in \
        launch-esp32-workspace \
        short-launch-esp32-workspace \
        update-codex-esp32-image \
        launch-uxplay-workspace \
        launch-uxplay-builder \
        update-codex-uxplay-image
    do
        [[ ! -e "${BIN_DIR}/${wrapper}" ]] || {
            printf '    legacy wrapper still exists: %s\n' "$wrapper" >&2
            _fail=1
        }
    done
    return $_fail
}

test_extra_terminal_removed() {
    [[ ! -e "${BIN_DIR}/extra-terminal" ]] || {
        printf '    extra-terminal still exists in bin/\n' >&2
        return 1
    }
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "legacy project wrappers removed"                  test_legacy_project_wrappers_removed
run_test "extra-terminal removed from bin/"                 test_extra_terminal_removed

print_summary "70_wrappers"
