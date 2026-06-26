#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# 2026 - Anthony Burow - https://github.com/aburow
# Shared test harness for container-builder integration tests.
# Source this file in every test script; do not execute directly.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN_DIR="${REPO_ROOT}/bin"
LIB_DIR="${REPO_ROOT}/lib"
PROFILES_SRC="${REPO_ROOT}/profiles"
STUBS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/stubs" && pwd)"

# ── Colour output ─────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    _C_PASS='\033[0;32m'; _C_FAIL='\033[0;31m'
    _C_SKIP='\033[0;33m'; _C_RESET='\033[0m'
else
    _C_PASS=''; _C_FAIL=''; _C_SKIP=''; _C_RESET=''
fi

# ── Per-run counters (updated by run_test) ────────────────────────────────────
_PASS=0; _FAIL=0; _SKIP=0

# ── Assertion helpers — return 1 on failure so callers can: assert... || fail=1
assert_eq() {
    local expected="$1" actual="$2" msg="${3:-}"
    [[ "$expected" == "$actual" ]] && return 0
    printf '    ASSERT_EQ fail%s\n      expected: %q\n      actual:   %q\n' \
        "${msg:+: $msg}" "$expected" "$actual" >&2
    return 1
}

assert_contains() {
    local needle="$1" haystack="$2" msg="${3:-}"
    [[ "$haystack" == *"$needle"* ]] && return 0
    printf '    ASSERT_CONTAINS fail%s: %q not found in output\n' \
        "${msg:+: $msg}" "$needle" >&2
    return 1
}

assert_not_contains() {
    local needle="$1" haystack="$2" msg="${3:-}"
    [[ "$haystack" != *"$needle"* ]] && return 0
    printf '    ASSERT_NOT_CONTAINS fail%s: %q should NOT be in output\n' \
        "${msg:+: $msg}" "$needle" >&2
    return 1
}

assert_success() {
    local code="$1" msg="${2:-}"
    [[ "$code" -eq 0 ]] && return 0
    printf '    ASSERT_SUCCESS fail%s: exit %d (expected 0)\n' \
        "${msg:+: $msg}" "$code" >&2
    return 1
}

assert_failure() {
    local code="$1" msg="${2:-}"
    [[ "$code" -ne 0 ]] && return 0
    printf '    ASSERT_FAILURE fail%s: exit 0 (expected non-zero)\n' \
        "${msg:+: $msg}" >&2
    return 1
}

# ── Skip helpers ──────────────────────────────────────────────────────────────
_SKIP_REASON=""

# Sets _SKIP_REASON and returns 0 (meaning "please skip") when live tests are
# not enabled or podman is unavailable.  Returns 1 when tests should proceed.
skip_unless_live() {
    if [[ "${PODMAN_LIVE:-0}" != "1" ]]; then
        _SKIP_REASON="Tier B — set PODMAN_LIVE=1 to enable live Podman tests"
        return 0
    fi
    if ! command -v podman >/dev/null 2>&1; then
        _SKIP_REASON="podman not found in PATH"
        return 0
    fi
    if ! podman info --format '{{.Host.Security.Rootless}}' 2>/dev/null | grep -q 'true'; then
        _SKIP_REASON="podman is not running rootless"
        return 0
    fi
    return 1  # do not skip — proceed with live test
}

# ── Temp environment setup ────────────────────────────────────────────────────
_TMPDIR=""

setup_test_env() {
    _TMPDIR="$(mktemp -d)"
    export AI_PODMAN_JAILS_DIR="$_TMPDIR"
    mkdir -p "${_TMPDIR}/profiles"

    # Seed reference profiles (expand AI_PODMAN_JAILS_DIR in example files)
    local f
    for f in "${PROFILES_SRC}"/*.env.example; do
        [[ -f "$f" ]] || continue
        local base
        base="$(basename "$f" .example)"
        sed "s|\${AI_PODMAN_JAILS_DIR}|${_TMPDIR}|g" \
            "$f" > "${_TMPDIR}/profiles/${base}"
    done

    # Ensure stubs directory precedes real commands so podman stub is found
    export PATH="${STUBS_DIR}:${PATH}"
}

teardown_test_env() {
    if [[ -n "${_TMPDIR:-}" && -d "${_TMPDIR}" ]]; then
        rm -rf "$_TMPDIR"
        _TMPDIR=""
    fi
}

# ── Test runner ───────────────────────────────────────────────────────────────
# run_test <display-name> <function-name>
run_test() {
    local name="$1" fn="$2"
    _SKIP_REASON=""

    setup_test_env
    local _rc=0
    "$fn" || _rc=$?
    teardown_test_env

    if [[ -n "$_SKIP_REASON" ]]; then
        printf "${_C_SKIP}  SKIP${_C_RESET}  %s — %s\n" "$name" "$_SKIP_REASON"
        (( _SKIP++ )) || true
    elif [[ $_rc -eq 0 ]]; then
        printf "${_C_PASS}  PASS${_C_RESET}  %s\n" "$name"
        (( _PASS++ )) || true
    else
        printf "${_C_FAIL}  FAIL${_C_RESET}  %s\n" "$name"
        (( _FAIL++ )) || true
    fi
}

# print_summary — call at end of each test file
print_summary() {
    local label="${1:-}"
    printf '\n  ── %s%d passed  %d failed  %d skipped\n\n' \
        "${label:+$label: }" "$_PASS" "$_FAIL" "$_SKIP"
    [[ $_FAIL -eq 0 ]]  # exit code: 0 = all ok
}
