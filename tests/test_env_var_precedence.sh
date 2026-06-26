#!/usr/bin/env bash
# T_ENV_VAR_PRECEDENCE — Resolver precedence matrix, warn-once, suppressor, compat.
# Milestones 1-3 from lifecycle/test-plans/deprecate-codex-jails-env-vars-5-test.md
# shellcheck disable=SC2016  # single-quoted $VARs are intentional — passed to eval in subshell
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

# ── Runner ─────────────────────────────────────────────────────────────────────
# _run SETUP BODY — isolated subshell; sets _OUT (stdout) and _ERR (stderr).
_OUT="" _ERR=""
_run() {
    local _ef
    _ef="$(mktemp)"
    _OUT="$(
        (
            unset AI_PODMAN_JAILS_DIR CODEX_JAILS_DIR \
                  AI_PODMAN_BIN CODEX_BIN \
                  AI_PODMAN_AGENTS_DIR CODEX_AGENTS_DIR \
                  AI_PODMAN_NO_DEPRECATION_WARN
            eval "${1:-}"
            # shellcheck source=/dev/null
            source "${LIB_DIR}/common.sh"
            eval "${2:-}"
        ) 2>"$_ef"
    )"
    _ERR="$(cat "$_ef")"
    rm -f "$_ef"
}

# ── M1: Precedence matrix — JAILS_DIR ─────────────────────────────────────────

test_jails_both_canonical_wins() {
    _run 'export AI_PODMAN_JAILS_DIR=/canonical CODEX_JAILS_DIR=/legacy' \
         'resolve_jails_dir; printf "%s" "$AI_PODMAN_JAILS_DIR"'
    local _fail=0
    assert_eq "/canonical" "$_OUT" "canonical should win over legacy" || _fail=1
    assert_not_contains "deprecated" "$_ERR" "no warning when canonical is set" || _fail=1
    return $_fail
}

test_jails_only_legacy_warns() {
    _run 'export CODEX_JAILS_DIR=/legacy' \
         'resolve_jails_dir; printf "%s" "$AI_PODMAN_JAILS_DIR"'
    local _fail=0
    assert_eq "/legacy" "$_OUT" "legacy value should propagate" || _fail=1
    assert_contains "CODEX_JAILS_DIR" "$_ERR" "warning must name old var" || _fail=1
    assert_contains "AI_PODMAN_JAILS_DIR" "$_ERR" "warning must name new var" || _fail=1
    return $_fail
}

test_jails_only_canonical_no_warn() {
    _run 'export AI_PODMAN_JAILS_DIR=/canonical' \
         'resolve_jails_dir; printf "%s" "$AI_PODMAN_JAILS_DIR"'
    local _fail=0
    assert_eq "/canonical" "$_OUT" || _fail=1
    assert_not_contains "deprecated" "$_ERR" "no warning when only canonical set" || _fail=1
    return $_fail
}

test_jails_neither_defaults_home() {
    _run '' 'resolve_jails_dir; printf "%s" "$AI_PODMAN_JAILS_DIR"'
    local _fail=0
    assert_eq "${HOME}/codex-jails" "$_OUT" "default must be HOME/codex-jails" || _fail=1
    assert_not_contains "deprecated" "$_ERR" "no warning for default" || _fail=1
    return $_fail
}

# ── M1: Precedence matrix — BIN ───────────────────────────────────────────────

test_bin_both_canonical_wins() {
    _run 'export AI_PODMAN_JAILS_DIR=/j AI_PODMAN_BIN=/can/bin CODEX_BIN=/leg/bin' \
         'resolve_jails_dir; project_paths p; printf "%s" "$AI_PODMAN_BIN"'
    local _fail=0
    assert_eq "/can/bin" "$_OUT" || _fail=1
    assert_not_contains "CODEX_BIN" "$_ERR" "no CODEX_BIN warning when canonical set" || _fail=1
    return $_fail
}

test_bin_only_legacy_warns() {
    _run 'export AI_PODMAN_JAILS_DIR=/j CODEX_BIN=/leg/bin' \
         'resolve_jails_dir; project_paths p; printf "%s" "$AI_PODMAN_BIN"'
    local _fail=0
    assert_eq "/leg/bin" "$_OUT" || _fail=1
    assert_contains "CODEX_BIN" "$_ERR" "warning must name CODEX_BIN" || _fail=1
    return $_fail
}

test_bin_only_canonical_no_warn() {
    _run 'export AI_PODMAN_JAILS_DIR=/j AI_PODMAN_BIN=/can/bin' \
         'resolve_jails_dir; project_paths p; printf "%s" "$AI_PODMAN_BIN"'
    local _fail=0
    assert_eq "/can/bin" "$_OUT" || _fail=1
    assert_not_contains "deprecated" "$_ERR" || _fail=1
    return $_fail
}

test_bin_neither_derives_from_jails() {
    _run 'export AI_PODMAN_JAILS_DIR=/j' \
         'resolve_jails_dir; project_paths p; printf "%s" "$AI_PODMAN_BIN"'
    local _fail=0
    assert_eq "/j/bin" "$_OUT" "BIN should default to JAILS_DIR/bin" || _fail=1
    assert_not_contains "deprecated" "$_ERR" || _fail=1
    return $_fail
}

# ── M1: Precedence matrix — AGENTS_DIR ────────────────────────────────────────

test_agents_both_canonical_wins() {
    _run 'export AI_PODMAN_JAILS_DIR=/j AI_PODMAN_AGENTS_DIR=/can/ag CODEX_AGENTS_DIR=/leg/ag' \
         'resolve_jails_dir; project_paths p; printf "%s" "$AI_PODMAN_AGENTS_DIR"'
    local _fail=0
    assert_eq "/can/ag" "$_OUT" || _fail=1
    assert_not_contains "CODEX_AGENTS_DIR" "$_ERR" || _fail=1
    return $_fail
}

test_agents_only_legacy_warns() {
    _run 'export AI_PODMAN_JAILS_DIR=/j CODEX_AGENTS_DIR=/leg/ag' \
         'resolve_jails_dir; project_paths p; printf "%s" "$AI_PODMAN_AGENTS_DIR"'
    local _fail=0
    assert_eq "/leg/ag" "$_OUT" || _fail=1
    assert_contains "CODEX_AGENTS_DIR" "$_ERR" || _fail=1
    return $_fail
}

test_agents_only_canonical_no_warn() {
    _run 'export AI_PODMAN_JAILS_DIR=/j AI_PODMAN_AGENTS_DIR=/can/ag' \
         'resolve_jails_dir; project_paths p; printf "%s" "$AI_PODMAN_AGENTS_DIR"'
    local _fail=0
    assert_eq "/can/ag" "$_OUT" || _fail=1
    assert_not_contains "deprecated" "$_ERR" || _fail=1
    return $_fail
}

test_agents_neither_derives_from_jails() {
    _run 'export AI_PODMAN_JAILS_DIR=/j' \
         'resolve_jails_dir; project_paths p; printf "%s" "$AI_PODMAN_AGENTS_DIR"'
    local _fail=0
    assert_eq "/j/config/agents.d" "$_OUT" "AGENTS_DIR should default to JAILS_DIR/config/agents.d" || _fail=1
    assert_not_contains "deprecated" "$_ERR" || _fail=1
    return $_fail
}

# ── M1: Var independence ──────────────────────────────────────────────────────

test_independence_only_codex_bin_warns_only_bin() {
    _run 'export AI_PODMAN_JAILS_DIR=/j CODEX_BIN=/leg/bin' \
         'resolve_jails_dir; project_paths p'
    local _fail=0
    assert_contains     "CODEX_BIN"        "$_ERR" "should warn for CODEX_BIN"        || _fail=1
    assert_not_contains "CODEX_JAILS_DIR"  "$_ERR" "must not warn for CODEX_JAILS_DIR" || _fail=1
    assert_not_contains "CODEX_AGENTS_DIR" "$_ERR" "must not warn for CODEX_AGENTS_DIR" || _fail=1
    return $_fail
}

# ── M2: Warn-once globally ─────────────────────────────────────────────────────

test_warn_once_global() {
    # Two resolver calls in the same process; _DEPRECATION_WARNED suppresses the second.
    _run 'export CODEX_JAILS_DIR=/legacy' \
         'resolve_jails_dir; unset AI_PODMAN_JAILS_DIR; resolve_jails_dir'
    local _count
    _count="$(printf '%s\n' "$_ERR" | grep -c "deprecated" || true)"
    local _fail=0
    [[ "$_count" -eq 1 ]] || {
        printf '    Expected 1 deprecation warning, got %d\n    stderr: %s\n' "$_count" "$_ERR" >&2
        _fail=1
    }
    return $_fail
}

# ── M2: Suppressor ─────────────────────────────────────────────────────────────

test_suppressor_silences_all_warnings() {
    _run 'export AI_PODMAN_NO_DEPRECATION_WARN=1 CODEX_JAILS_DIR=/legacy CODEX_BIN=/leg/bin CODEX_AGENTS_DIR=/leg/ag' \
         'resolve_jails_dir; project_paths p; printf "%s" "$AI_PODMAN_JAILS_DIR"'
    local _fail=0
    assert_eq "/legacy" "$_OUT" "suppressor must not change resolved value" || _fail=1
    assert_not_contains "deprecated" "$_ERR" "suppressor must silence all warnings" || _fail=1
    return $_fail
}

# ── M3: Byte-identical compat assertion ────────────────────────────────────────

test_compat_byte_identical() {
    # Legacy-only setup: only CODEX_JAILS_DIR=/tmp/x — verify derived paths match
    # expected pre-change values and exactly one deprecation warning fires.
    local _ef _out _err _wcount
    _ef="$(mktemp)"
    _out="$(
        (
            unset AI_PODMAN_JAILS_DIR CODEX_JAILS_DIR \
                  AI_PODMAN_BIN CODEX_BIN \
                  AI_PODMAN_AGENTS_DIR CODEX_AGENTS_DIR \
                  AI_PODMAN_NO_DEPRECATION_WARN
            export CODEX_JAILS_DIR=/tmp/x
            # shellcheck source=/dev/null
            source "${LIB_DIR}/common.sh"
            resolve_jails_dir
            project_paths testproj
            printf "JAILS=%s\n"  "$AI_PODMAN_JAILS_DIR"
            printf "BIN=%s\n"    "$AI_PODMAN_BIN"
            printf "AGENTS=%s\n" "$AI_PODMAN_AGENTS_DIR"
            printf "PROOT=%s\n"  "$PROJECT_ROOT"
            printf "PWS=%s\n"    "$PROJECT_WORKSPACE"
            printf "PIMG=%s\n"   "$PROJECT_IMAGE_DIR"
        ) 2>"$_ef"
    )"
    _err="$(cat "$_ef")"
    rm -f "$_ef"

    local _fail=0
    assert_contains "JAILS=/tmp/x"                                "$_out" || _fail=1
    assert_contains "BIN=/tmp/x/bin"                              "$_out" || _fail=1
    assert_contains "AGENTS=/tmp/x/config/agents.d"               "$_out" || _fail=1
    assert_contains "PROOT=/tmp/x/projects/testproj"              "$_out" || _fail=1
    assert_contains "PWS=/tmp/x/projects/testproj/workspace"      "$_out" || _fail=1
    assert_contains "PIMG=/tmp/x/projects/testproj/image"         "$_out" || _fail=1
    _wcount="$(printf '%s\n' "$_err" | grep -c "deprecated" || true)"
    [[ "$_wcount" -eq 1 ]] || {
        printf '    Expected 1 compat warning, got %d\n    stderr: %s\n' "$_wcount" "$_err" >&2
        _fail=1
    }
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
# M1 — precedence matrix
run_test "JAILS_DIR: canonical wins when both set"               test_jails_both_canonical_wins
run_test "JAILS_DIR: legacy propagates and warns"                test_jails_only_legacy_warns
run_test "JAILS_DIR: canonical only — no warning"                test_jails_only_canonical_no_warn
run_test "JAILS_DIR: neither set — default HOME/codex-jails"    test_jails_neither_defaults_home
run_test "BIN: canonical wins when both set"                     test_bin_both_canonical_wins
run_test "BIN: legacy propagates and warns"                      test_bin_only_legacy_warns
run_test "BIN: canonical only — no warning"                      test_bin_only_canonical_no_warn
run_test "BIN: neither set — derives from JAILS_DIR"            test_bin_neither_derives_from_jails
run_test "AGENTS_DIR: canonical wins when both set"              test_agents_both_canonical_wins
run_test "AGENTS_DIR: legacy propagates and warns"               test_agents_only_legacy_warns
run_test "AGENTS_DIR: canonical only — no warning"               test_agents_only_canonical_no_warn
run_test "AGENTS_DIR: neither set — derives from JAILS_DIR"     test_agents_neither_derives_from_jails
run_test "Independence: CODEX_BIN only warns for BIN"           test_independence_only_codex_bin_warns_only_bin
# M2 — warn-once + suppressor
run_test "Warn-once: second resolver call emits no duplicate"    test_warn_once_global
run_test "Suppressor: AI_PODMAN_NO_DEPRECATION_WARN silences"   test_suppressor_silences_all_warnings
# M3 — compat
run_test "Compat: legacy-only run yields byte-identical paths"  test_compat_byte_identical

print_summary "test_env_var_precedence"
