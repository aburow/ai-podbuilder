#!/usr/bin/env bash
# Codex must use the supported interactive CLI shape.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SELF_DIR}/helpers/setup.bash"

test_codex_uses_positional_interactive_prompt() {
    local src
    src="$(cat "${REPO_ROOT}/lib/start-here.sh")"
    assert_contains "codex)" "$src" || return 1
    assert_contains '_LAUNCH_ARGV=("$RESOLVED_COMMAND" "$_prompt_text")' "$src" || return 1
}

test_codex_uses_no_removed_flags() {
    local src
    src="$(cat "${REPO_ROOT}/lib/start-here.sh")"
    assert_not_contains '("$RESOLVED_COMMAND" --full-auto' "$src" || return 1
    assert_not_contains ' --full-auto -q ' "$src"
}

run_test "codex uses positional prompt for interactive TUI" test_codex_uses_positional_interactive_prompt
run_test "codex launch contains no removed full-auto flags"  test_codex_uses_no_removed_flags

print_summary "test_codex_adapter"
