#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# 2026 - Anthony Burow - https://github.com/aburow
# A host build timeout is resumable, not successful completion.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SELF_DIR}/helpers/setup.bash"

test_prompt_uses_host_owned_timeout() {
    local prompt
    prompt="$(cat "${REPO_ROOT}/prompts/bootstrap-prompt.md")"
    assert_contains "Do NOT impose a separate in-container timeout" "$prompt" || return 1
    assert_contains "default 30 min" "$prompt"
}

test_prompt_forbids_completion_after_timeout() {
    local prompt
    prompt="$(cat "${REPO_ROOT}/prompts/bootstrap-prompt.md")"
    assert_contains "Do NOT claim the bootstrap is complete" "$prompt" || return 1
    assert_contains "Do not print Steps 2–4 for" "$prompt"
}

run_test "prompt delegates timeout to host supervisor"       test_prompt_uses_host_owned_timeout
run_test "prompt forbids build/launch steps after timeout"    test_prompt_forbids_completion_after_timeout

print_summary "test_prompt_timeout_semantics"
