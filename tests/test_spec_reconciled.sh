#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# 2026 - Anthony Burow - https://github.com/aburow
# T3c — ai-new-3.md no longer presents /start-here.sh at root as the current spec (AC4, B4).
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

_SPEC="lifecycle/requirements/ai-new-3.md"
_SPEC_PATH="${REPO_ROOT}/${_SPEC}"

# ── Tests ─────────────────────────────────────────────────────────────────────

test_spec_file_exists() {
    local _fail=0
    [[ -f "$_SPEC_PATH" ]] || {
        printf '    %s not found\n' "$_SPEC" >&2
        _fail=1
    }
    return $_fail
}

test_root_location_claims_have_supersession_note() {
    # Lines that *claim* start-here.sh lives at the container/filesystem root must be
    # accompanied by a supersession note. Lines that merely use the script name in
    # usage syntax (e.g. `/start-here.sh -h` or `run /start-here.sh`) do not need one.
    # We target lines that contain both /start-here.sh AND root-location language
    # ("at root", "at the", "filesystem root", "container root", "Ship").
    local _fail=0
    [[ -f "$_SPEC_PATH" ]] || { _SKIP_REASON="spec file missing"; return 0; }

    local _found_unannotated=0
    local _line_num _line_text _total
    _total="$(wc -l < "$_SPEC_PATH")"

    while IFS=: read -r _line_num _line_text; do
        # Only check lines that make a location claim (not just usage-syntax references).
        if ! echo "$_line_text" | grep -qi 'at root\|at the\|filesystem root\|container root\|Ship\|lives at\|bind.mount'; then
            continue
        fi
        local _ctx_start=$(( _line_num > 5 ? _line_num - 5 : 1 ))
        local _ctx_end=$(( _line_num + 5 < _total ? _line_num + 5 : _total ))
        local _ctx
        _ctx="$(sed -n "${_ctx_start},${_ctx_end}p" "$_SPEC_PATH")"
        if ! echo "$_ctx" | grep -qi 'supersed'; then
            printf '    Line %d: location claim lacks nearby supersession note:\n' "$_line_num" >&2
            printf '    %s\n' "$_line_text" >&2
            _found_unannotated=$(( _found_unannotated + 1 ))
        fi
    done < <(grep -n '/start-here.sh' "$_SPEC_PATH")

    if [[ "$_found_unannotated" -gt 0 ]]; then
        printf '    %d location claim(s) lack a supersession note\n' "$_found_unannotated" >&2
        _fail=1
    fi
    return $_fail
}

test_r4_1_has_supersession_note() {
    # R4.1 specifically must have a supersession note (B4, AC4).
    local _fail=0
    [[ -f "$_SPEC_PATH" ]] || { _SKIP_REASON="spec file missing"; return 0; }

    # Find the R4.1 block (within a few lines of "R4.1").
    local _r41_line
    _r41_line="$(grep -n 'R4\.1' "$_SPEC_PATH" | head -1 | cut -d: -f1)"
    if [[ -z "$_r41_line" ]]; then
        printf '    R4.1 not found in %s\n' "$_SPEC" >&2
        _fail=1
        return $_fail
    fi

    local _total
    _total="$(wc -l < "$_SPEC_PATH")"
    local _ctx_end=$(( _r41_line + 10 < _total ? _r41_line + 10 : _total ))
    local _ctx
    _ctx="$(sed -n "${_r41_line},${_ctx_end}p" "$_SPEC_PATH")"

    if ! echo "$_ctx" | grep -qi 'supersed'; then
        printf '    R4.1 block (line %d) has no supersession note within 10 lines\n' "$_r41_line" >&2
        _fail=1
    fi
    return $_fail
}

test_no_unannotated_root_mounts_in_spec() {
    # No line in ai-new-3.md should state :/start-here.sh as an active mount without annotation.
    local _fail=0
    [[ -f "$_SPEC_PATH" ]] || { _SKIP_REASON="spec file missing"; return 0; }

    local _mount_lines
    _mount_lines="$(grep -n ':/start-here\.sh' "$_SPEC_PATH" || true)"
    if [[ -n "$_mount_lines" ]]; then
        # Each matching line must have a supersession note somewhere in its context.
        local _line_num _ctx
        while IFS= read -r _line_num; do
            local _ctx_start=$(( _line_num > 3 ? _line_num - 3 : 1 ))
            local _total; _total="$(wc -l < "$_SPEC_PATH")"
            local _ctx_end=$(( _line_num + 3 < _total ? _line_num + 3 : _total ))
            _ctx="$(sed -n "${_ctx_start},${_ctx_end}p" "$_SPEC_PATH")"
            if ! echo "$_ctx" | grep -qi 'supersed\|removed\|obsolete'; then
                printf '    Line %d: active-looking bind mount in spec without supersession note\n' \
                    "$_line_num" >&2
                _fail=1
            fi
        done < <(echo "$_mount_lines" | cut -d: -f1)
    fi
    return $_fail
}

test_spec_supersession_references_home_path() {
    # The supersession note in ai-new-3.md must point to the home-directory placement.
    local _fail=0
    [[ -f "$_SPEC_PATH" ]] || { _SKIP_REASON="spec file missing"; return 0; }

    if ! grep -qi '/project/bootstrap/home' "$_SPEC_PATH" 2>/dev/null; then
        printf '    ai-new-3.md has no reference to /project/bootstrap/home\n' >&2
        printf '    Supersession note must state the correct home-dir path\n' >&2
        _fail=1
    fi
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "ai-new-3.md exists"                                              test_spec_file_exists
run_test "location claims for /start-here.sh at root have supersession note" test_root_location_claims_have_supersession_note
run_test "R4.1 has a supersession note"                                    test_r4_1_has_supersession_note
run_test "no active-looking :/start-here.sh bind mounts in spec"           test_no_unannotated_root_mounts_in_spec
run_test "supersession note references the home-dir path"                  test_spec_supersession_references_home_path

print_summary "test_spec_reconciled"
