#!/usr/bin/env bash
# Top-level test runner. Executes each test file and reports overall results.
# Usage: ./tests/run_tests.sh [PODMAN_LIVE=1]
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

overall_pass=0; overall_fail=0; overall_skip=0
runner_fail=0

for f in "${TESTS_DIR}"/[0-9]*.sh; do
    [[ -f "$f" ]] || continue
    printf '\n=== %s ===\n' "$(basename "$f")"
    if bash "$f"; then
        : # file-level pass tracked inside each file
    else
        runner_fail=1
    fi
done

echo ""
if [[ $runner_fail -eq 0 ]]; then
    echo "All test files passed."
    exit 0
else
    echo "One or more test files reported failures." >&2
    exit 1
fi
