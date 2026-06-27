#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# 2026 - Anthony Burow - https://github.com/aburow
# T1–T4 — Verify slug-sanitizer fix: masking fallback removed, failures propagate.
# Covers AC1–AC5 from ai-new-slug-sanitizer-test-emits-failed-assertion-but-passes.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

_SUITE="${SELF_DIR}/test_slug_sanitizer.sh"

# ── T1 — Baseline run (AC1, AC2) ──────────────────────────────────────────────

test_t1_exit_zero_and_13_passed() {
    local _fail=0
    local out rc=0
    out="$(bash "$_SUITE" 2>&1)" || rc=$?
    assert_success $rc "suite must exit 0 (AC1)" || _fail=1
    assert_contains "13 passed  0 failed" "$out" "summary must show 13 passed 0 failed (AC1)" || _fail=1
    return $_fail
}

test_t1_no_assert_eq_fail_for_illegal_chars() {
    local _fail=0
    local out rc=0
    out="$(bash "$_SUITE" 2>&1)" || rc=$?
    # ASSERT_EQ fail lines go to stderr; captured via 2>&1
    if printf '%s\n' "$out" | grep -q 'ASSERT_EQ fail.*illegal chars'; then
        printf '    ASSERT_EQ fail emitted for illegal-chars case (AC2)\n' >&2
        _fail=1
    fi
    return $_fail
}

# ── T2 — Deliberate failure injection (AC3) ───────────────────────────────────

test_t2_failure_injection_propagates() {
    local _fail=0
    # Make a temp copy in tests/ so SELF_DIR inside the script resolves correctly
    local tmp_suite
    tmp_suite="$(mktemp "${SELF_DIR}/_t2_bogus_XXXXXX.sh")"
    cp "$_SUITE" "$tmp_suite"
    # Replace correct expected value with BOGUS to force assertion failure
    sed -i 's|assert_eq "my-proj-ect" "$out"|assert_eq "BOGUS" "$out"|' "$tmp_suite"

    local out rc=0
    out="$(bash "$tmp_suite" 2>&1)" || rc=$?
    rm -f "$tmp_suite"

    assert_failure $rc "BOGUS injection must cause non-zero exit (AC3)" || _fail=1
    assert_contains "1 failed" "$out" "summary must show 1 failed (AC3)" || _fail=1
    assert_contains "ASSERT_EQ fail" "$out" "ASSERT_EQ fail must appear in output (AC3)" || _fail=1
    assert_contains "illegal chars replaced with dash" "$out" "FAIL line must name the illegal-chars case (AC3)" || _fail=1
    return $_fail
}

# ── T3 — Structural checks (AC4, AC5) ─────────────────────────────────────────

test_t3_masking_fallback_absent() {
    local _fail=0
    # The old masking pattern appended || { ... } directly to the assert_eq line.
    # After B2 the line must end with || _fail=1, not || {.
    if grep -q 'assert_eq.*my-proj-ect.*|| {' "$_SUITE"; then
        printf '    Masking || { fallback still attached to assert_eq (AC5)\n' >&2
        _fail=1
    fi
    # Positive check: the corrected assertion is present
    if ! grep -q 'assert_eq "my-proj-ect" "\$out".*|| _fail=1' "$_SUITE"; then
        printf '    Corrected assert_eq "my-proj-ect" ... || _fail=1 not found (AC5)\n' >&2
        _fail=1
    fi
    return $_fail
}

test_t3_secondary_guard_sets_fail() {
    local _fail=0
    # R3: the [[ "$out" != *"@"* ... ]] || { ... _fail=1 } guard must be present
    local context
    context="$(grep -A6 'test_illegal_chars_become_dash' "$_SUITE" | grep '_fail=1')"
    if [[ -z "$context" ]]; then
        printf '    Secondary guard _fail=1 not found in test_illegal_chars_become_dash (R3)\n' >&2
        _fail=1
    fi
    return $_fail
}

test_t3_test_function_count_unchanged() {
    local _fail=0
    local count
    count="$(grep -c '^test_' "$_SUITE")"
    if [[ "$count" -ne 13 ]]; then
        printf '    Expected 13 test_ functions, found %s (AC4)\n' "$count" >&2
        _fail=1
    fi
    return $_fail
}

# ── T4 — Suite audit: no unguarded || { blocks (B2 audit) ────────────────────

test_t4_all_or_blocks_set_fail() {
    local _fail=0
    # Every || { block in test_slug_sanitizer.sh must set _fail=1 within 5 lines.
    # ponytail: awk line scan is the simplest way to check block content without a parser.
    local result
    result="$(awk '
        /\|\| \{/ { in_block=1; block_start=NR; block_fail=0 }
        in_block && /_fail=1/ { block_fail=1 }
        in_block && /^\s*\}/ {
            if (!block_fail) print "line " block_start ": || { block missing _fail=1"
            in_block=0
        }
    ' "$_SUITE")"
    if [[ -n "$result" ]]; then
        printf '    %s\n' "$result" >&2
        _fail=1
    fi
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "T1: suite exits 0, 13 passed 0 failed"           test_t1_exit_zero_and_13_passed
run_test "T1: no ASSERT_EQ fail for illegal-chars case"    test_t1_no_assert_eq_fail_for_illegal_chars
run_test "T2: failure injection causes non-zero exit"      test_t2_failure_injection_propagates
run_test "T3: masking || { fallback absent (AC5)"          test_t3_masking_fallback_absent
run_test "T3: secondary guard sets _fail=1 (R3)"           test_t3_secondary_guard_sets_fail
run_test "T3: test function count unchanged at 13 (AC4)"   test_t3_test_function_count_unchanged
run_test "T4: all || { blocks set _fail=1"                 test_t4_all_or_blocks_set_fail

print_summary "test_slug_sanitizer_fix"
