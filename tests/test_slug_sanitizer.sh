#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# 2026 - Anthony Burow - https://github.com/aburow
# T4 — Slug sanitizer: deterministic rules (R20.1, D2, AC27).
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

# ── Helpers ───────────────────────────────────────────────────────────────────

_slug_of() {
    local _name="$1"
    cat > "${_TMPDIR}/slug_helper.sh" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/slug.sh'
export AI_PODMAN_JAILS_DIR='${_TMPDIR}'
sanitize_slug '$( printf '%s' "$_name" | sed "s/'/'\'''/g" )'
SCRIPT
    bash "${_TMPDIR}/slug_helper.sh" 2>&1
}

_slug_of_raw() {
    # For names with single quotes — write name to a temp file and read it.
    local _name="$1"
    printf '%s' "$_name" > "${_TMPDIR}/slug_name.txt"
    cat > "${_TMPDIR}/slug_helper2.sh" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/slug.sh'
export AI_PODMAN_JAILS_DIR='${_TMPDIR}'
_name="\$(cat '${_TMPDIR}/slug_name.txt')"
sanitize_slug "\$_name"
SCRIPT
    bash "${_TMPDIR}/slug_helper2.sh" 2>&1
}

# ── Tests ─────────────────────────────────────────────────────────────────────

test_lowercase_preserved() {
    local _fail=0
    local out rc=0
    out="$(_slug_of "myproject")" || rc=$?
    assert_success $rc || _fail=1
    assert_eq "myproject" "$out" "all-lowercase name should be unchanged" || _fail=1
    return $_fail
}

test_uppercase_lowercased() {
    local _fail=0
    local out rc=0
    out="$(_slug_of "MyProject")" || rc=$?
    assert_success $rc || _fail=1
    assert_eq "myproject" "$out" "uppercase should be lowercased" || _fail=1
    return $_fail
}

test_spaces_replaced_with_dash() {
    local _fail=0
    local out rc=0
    out="$(_slug_of_raw "my project")" || rc=$?
    assert_success $rc || _fail=1
    assert_eq "my-project" "$out" "spaces should become dashes" || _fail=1
    return $_fail
}

test_underscores_kept() {
    local _fail=0
    local out rc=0
    out="$(_slug_of "my_project")" || rc=$?
    assert_success $rc || _fail=1
    assert_eq "my_project" "$out" "underscores are allowed and kept" || _fail=1
    return $_fail
}

# R20.1 (ai-new-9.md): trim leading/trailing [._-] after char substitution → "my-proj-ect" not "my-proj-ect-"
test_illegal_chars_become_dash() {
    local _fail=0
    local out rc=0
    out="$(_slug_of_raw "my@proj#ect!")" || rc=$?
    assert_success $rc || _fail=1
    assert_eq "my-proj-ect" "$out" "illegal chars replaced with dashes; trailing dash trimmed (R20.1)" || _fail=1
    # Verify the slug doesn't contain @ # !
    [[ "$out" != *"@"* && "$out" != *"#"* && "$out" != *"!"* ]] || {
        printf '    Illegal chars not replaced: %s\n' "$out" >&2
        _fail=1
    }
    return $_fail
}

test_repeated_dashes_collapsed() {
    local _fail=0
    local out rc=0
    out="$(_slug_of_raw "my--project")" || rc=$?
    assert_success $rc || _fail=1
    assert_eq "my-project" "$out" "repeated dashes should be collapsed" || _fail=1
    return $_fail
}

test_leading_dash_trimmed() {
    local _fail=0
    local out rc=0
    out="$(_slug_of_raw "--myproject")" || rc=$?
    assert_success $rc || _fail=1
    assert_eq "myproject" "$out" "leading dashes should be trimmed" || _fail=1
    return $_fail
}

test_trailing_dash_trimmed() {
    local _fail=0
    local out rc=0
    out="$(_slug_of_raw "myproject--")" || rc=$?
    assert_success $rc || _fail=1
    assert_eq "myproject" "$out" "trailing dashes should be trimmed" || _fail=1
    return $_fail
}

test_empty_name_fails() {
    local _fail=0
    local out rc=0
    out="$(_slug_of_raw "")" || rc=$?
    assert_failure $rc "empty name should fail" || _fail=1
    return $_fail
}

test_all_dashes_fails() {
    local _fail=0
    local out rc=0
    out="$(_slug_of_raw "---")" || rc=$?
    assert_failure $rc "name of only dashes should fail (empty after trim)" || _fail=1
    return $_fail
}

test_long_name_truncated_with_hash() {
    local _fail=0
    # A 70-char name should be truncated to 63 chars max.
    local _long="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"  # 72 chars
    local out rc=0
    out="$(_slug_of_raw "$_long")" || rc=$?
    assert_success $rc || _fail=1
    [[ "${#out}" -le 63 ]] || {
        printf '    Slug length %d > 63: %s\n' "${#out}" "$out" >&2
        _fail=1
    }
    # Should contain an 8-char hash suffix after the last -.
    [[ "$out" == *"-"* ]] || {
        printf '    Long slug should have a dash before the hash suffix: %s\n' "$out" >&2
        _fail=1
    }
    return $_fail
}

test_truncation_is_deterministic() {
    local _fail=0
    local _long="my-long-project-name-that-exceeds-the-sixty-three-character-limit-easily"
    local _h1 _h2
    _h1="$(_slug_of_raw "$_long")"
    _h2="$(_slug_of_raw "$_long")"
    assert_eq "$_h1" "$_h2" "truncated slug should be deterministic" || _fail=1
    return $_fail
}

test_slug_collision_fails_closed() {
    local _fail=0
    # Pre-seed the slug index with "myname" → "myname".
    mkdir -p "${_TMPDIR}/config"
    printf 'myname\tmyname\n' > "${_TMPDIR}/config/slug-index.tsv"
    # A different name that maps to the same slug should fail.
    local out rc=0
    out="$(_slug_of "MYNAME")" || rc=$?
    assert_failure $rc "slug collision should fail" || _fail=1
    assert_contains "collision" "$out" "error should mention collision" || _fail=1
    assert_contains "myname" "$out" "error should name the existing user" || _fail=1
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "lowercase name unchanged"                test_lowercase_preserved
run_test "uppercase letters are lowercased"        test_uppercase_lowercased
run_test "spaces replaced with dash"               test_spaces_replaced_with_dash
run_test "underscores are kept"                    test_underscores_kept
run_test "illegal chars replaced with dash"        test_illegal_chars_become_dash
run_test "repeated dashes collapsed"               test_repeated_dashes_collapsed
run_test "leading dashes trimmed"                  test_leading_dash_trimmed
run_test "trailing dashes trimmed"                 test_trailing_dash_trimmed
run_test "empty name fails"                        test_empty_name_fails
run_test "all-dash name fails (empty after trim)"  test_all_dashes_fails
run_test ">63 char name truncated with hash suffix" test_long_name_truncated_with_hash
run_test "truncation is deterministic"             test_truncation_is_deterministic
run_test "slug collision fails closed with details" test_slug_collision_fails_closed

print_summary "test_slug_sanitizer"
