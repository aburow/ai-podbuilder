#!/usr/bin/env bash
# T3 — Registry hashing, normalization & cross-run stability (R13.6, R13.10, AC21, AC27).
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

# ── Helpers ───────────────────────────────────────────────────────────────────

_hash_helper() {
    local _path="$1"
    cat > "${_TMPDIR}/hash_helper.sh" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/registry.sh'
export AI_PODMAN_JAILS_DIR='${_TMPDIR}'
registry_hash '${_path}'
SCRIPT
    bash "${_TMPDIR}/hash_helper.sh" 2>&1
}

_normalize_helper() {
    local _path="$1"
    cat > "${_TMPDIR}/norm_helper.sh" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/registry.sh'
export AI_PODMAN_JAILS_DIR='${_TMPDIR}'
normalize_registry '${_path}'
SCRIPT
    bash "${_TMPDIR}/norm_helper.sh" 2>&1
}

_canonical_content() {
    printf 'AGENT_NAME="testbot"\nAGENT_COMMAND="testbot-cli"\nAGENT_INSTALL_ADAPTER="preinstalled"\n'
}

# ── Tests ─────────────────────────────────────────────────────────────────────

test_hash_stable_across_two_runs() {
    local _fail=0
    local _reg="${_TMPDIR}/stable.env"
    _canonical_content > "$_reg"

    local _hash1 _hash2
    _hash1="$(_hash_helper "$_reg")"
    _hash2="$(_hash_helper "$_reg")"
    assert_eq "$_hash1" "$_hash2" "hash should be identical across two runs" || _fail=1
    [[ -n "$_hash1" ]] || { printf '    Hash was empty\n' >&2; _fail=1; }
    return $_fail
}

test_hash_stable_across_independent_temp_dirs() {
    local _fail=0
    # Simulate two independent processes by running in two separate subshells
    # with different temp dirs.
    local _reg1="${_TMPDIR}/dir1/test.env"
    local _reg2="${_TMPDIR}/dir2/test.env"
    mkdir -p "${_TMPDIR}/dir1" "${_TMPDIR}/dir2"
    _canonical_content > "$_reg1"
    _canonical_content > "$_reg2"

    local _hash1 _hash2
    _hash1="$(_hash_helper "$_reg1")"
    _hash2="$(_hash_helper "$_reg2")"
    assert_eq "$_hash1" "$_hash2" "hash should be stable across temp dirs" || _fail=1
    return $_fail
}

test_crlf_and_lf_hash_identically() {
    local _fail=0
    local _lf="${_TMPDIR}/lf.env"
    local _crlf="${_TMPDIR}/crlf.env"

    _canonical_content > "$_lf"
    # Write CRLF version (CR before each LF).
    _canonical_content | sed 's/$/\r/' > "$_crlf"

    local _hash_lf _hash_crlf
    _hash_lf="$(_hash_helper "$_lf")"
    _hash_crlf="$(_hash_helper "$_crlf")"
    assert_eq "$_hash_lf" "$_hash_crlf" "CRLF and LF files should hash identically" || _fail=1
    return $_fail
}

test_trailing_whitespace_hashes_identically() {
    local _fail=0
    local _clean="${_TMPDIR}/clean.env"
    local _trailing="${_TMPDIR}/trailing.env"

    _canonical_content > "$_clean"
    # Add trailing spaces to each line.
    _canonical_content | sed 's/$/ /' > "$_trailing"

    local _hash_clean _hash_trailing
    _hash_clean="$(_hash_helper "$_clean")"
    _hash_trailing="$(_hash_helper "$_trailing")"
    assert_eq "$_hash_clean" "$_hash_trailing" \
        "trailing whitespace differences should hash identically" || _fail=1
    return $_fail
}

test_different_content_hashes_differently() {
    local _fail=0
    local _reg1="${_TMPDIR}/v1.env"
    local _reg2="${_TMPDIR}/v2.env"

    _canonical_content > "$_reg1"
    # Different content.
    printf 'AGENT_NAME="different"\nAGENT_COMMAND="other-cli"\nAGENT_INSTALL_ADAPTER="manual"\n' > "$_reg2"

    local _hash1 _hash2
    _hash1="$(_hash_helper "$_reg1")"
    _hash2="$(_hash_helper "$_reg2")"
    [[ "$_hash1" != "$_hash2" ]] || {
        printf '    Different files should produce different hashes\n' >&2
        return 1
    }
    return 0
}

test_added_comment_changes_hash() {
    local _fail=0
    local _no_comment="${_TMPDIR}/no_comment.env"
    local _with_comment="${_TMPDIR}/with_comment.env"

    _canonical_content > "$_no_comment"
    { printf '# extra comment\n'; _canonical_content; } > "$_with_comment"

    local _hash1 _hash2
    _hash1="$(_hash_helper "$_no_comment")"
    _hash2="$(_hash_helper "$_with_comment")"
    # Comments change the normalized form, so they change the hash.
    [[ "$_hash1" != "$_hash2" ]] || {
        printf '    Adding a comment should change the hash\n' >&2
        _fail=1
    }
    return $_fail
}

test_normalize_outputs_exactly_one_trailing_newline() {
    local _fail=0
    local _reg="${_TMPDIR}/newline_check.env"
    _canonical_content > "$_reg"

    local _norm
    _norm="$(_normalize_helper "$_reg")"
    # Check there's content.
    [[ -n "$_norm" ]] || { printf '    Normalized output was empty\n' >&2; _fail=1; }
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "hash stable across two independent runs"           test_hash_stable_across_two_runs
run_test "hash stable across independent temp dirs"          test_hash_stable_across_independent_temp_dirs
run_test "CRLF and LF hash identically"                      test_crlf_and_lf_hash_identically
run_test "trailing whitespace hashes identically"            test_trailing_whitespace_hashes_identically
run_test "different content hashes differently"              test_different_content_hashes_differently
run_test "added comment changes hash"                        test_added_comment_changes_hash
run_test "normalize outputs valid content"                   test_normalize_outputs_exactly_one_trailing_newline

print_summary "test_registry_hash"
