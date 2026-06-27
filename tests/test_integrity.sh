#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# 2026 - Anthony Burow - https://github.com/aburow
# Integration tests for lib/integrity.sh — M1–M6.
# Test plan: lifecycle/test-plans/ai-pod-doctor-integrity-check-5-test.md
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

# ── File-level fixture (built once, shared across all tests) ──────────────────

_IC_FIXTMPDIR=""
_IC_INSTALL=""

_build_fixture() {
    _IC_FIXTMPDIR="$(mktemp -d)"
    _IC_INSTALL="${_IC_FIXTMPDIR}/install"
    mkdir -p "${_IC_INSTALL}/bin" "${_IC_INSTALL}/lib"
    printf '0.0.0-test\n'              > "${_IC_INSTALL}/VERSION"
    printf '#!/bin/sh\necho ai-build-stub\n' > "${_IC_INSTALL}/bin/ai-build"
    printf '#!/bin/sh\necho ai-new-stub\n'   > "${_IC_INSTALL}/bin/ai-new"
    printf '# common stub\n'                  > "${_IC_INSTALL}/lib/common.sh"
    chmod 755 "${_IC_INSTALL}/bin/ai-build" "${_IC_INSTALL}/bin/ai-new"
    chmod 644 "${_IC_INSTALL}/lib/common.sh"

    # tarball: ai-podbuilder-0.0.0-test/ prefix (INNER computed by build_manifest)
    local prefix="ai-podbuilder-0.0.0-test"
    local staging="${_IC_FIXTMPDIR}/staging/${prefix}"
    mkdir -p "${staging}/bin" "${staging}/lib"
    cp "${_IC_INSTALL}/bin/ai-build"   "${staging}/bin/ai-build"
    cp "${_IC_INSTALL}/bin/ai-new"     "${staging}/bin/ai-new"
    cp "${_IC_INSTALL}/lib/common.sh"  "${staging}/lib/common.sh"
    tar czf "${_IC_FIXTMPDIR}/release.tgz" -C "${_IC_FIXTMPDIR}/staging" "${prefix}"

    # curl stub: serves release.tgz; respects FAIL_CURL env var
    mkdir -p "${_IC_FIXTMPDIR}/bin"
    cat > "${_IC_FIXTMPDIR}/bin/curl" <<STUB
#!/usr/bin/env bash
out=""
for (( i=1; i<=\$#; i++ )); do
    [[ "\${!i}" == "-o" ]] && { j=\$((i+1)); out="\${!j}"; }
done
[[ -n "\${FAIL_CURL:-}" ]] && exit 1
[[ -z "\$out" ]] && exit 1
cp "${_IC_FIXTMPDIR}/release.tgz" "\$out"
STUB
    chmod +x "${_IC_FIXTMPDIR}/bin/curl"
}

_cleanup_fixture() {
    [[ -n "${_IC_FIXTMPDIR}" && -d "${_IC_FIXTMPDIR}" ]] && rm -rf "${_IC_FIXTMPDIR}"
}

_build_fixture

# ── Per-test setup ────────────────────────────────────────────────────────────

# Copy fixture install into _TMPDIR and configure env for this test.
_ic_setup() {
    cp -a "${_IC_INSTALL}/." "${_TMPDIR}/"
    export AI_PODMAN_JAILS_DIR="${_TMPDIR}"
    export PATH="${_IC_FIXTMPDIR}/bin:${PATH}"
}

# Run the full lib pipeline in a subprocess; sets _IC_OUT and _IC_RC.
# Exit code: 0 = clean or unexpected-only (warning); 1 = missing or mismatch.
_IC_OUT="" _IC_RC=0
_run_pipeline() {
    local mode="${1:-exceptions}"
    local output_cmd
    case "$mode" in
        verbose)       output_cmd="print_verbose" ;;
        diffs)         output_cmd="print_diffs" ;;
        verbose_diffs) output_cmd="print_verbose; print_diffs" ;;
        *)             output_cmd="print_exceptions" ;;
    esac
    local script="${_TMPDIR}/pipeline_$$.sh"
    # Outer-shell vars expand here; inner \${ } are literal in the generated script.
    cat > "$script" <<SCRIPT
#!/usr/bin/env bash
set -uo pipefail
export AI_PODMAN_JAILS_DIR='${AI_PODMAN_JAILS_DIR}'
export PATH='${PATH}'
source '${LIB_DIR}/integrity.sh'
_ic_setup_tmpdir
detect_version
fetch_tarball
build_manifest
compare_files
( ${output_cmd} ) || true
issues=\$(( \${#_ic_missing[@]} + \${#_ic_mismatch[@]} ))
[[ "\${issues}" -gt 0 ]] && exit 1 || exit 0
SCRIPT
    _IC_RC=0
    _IC_OUT="$(bash "$script" 2>&1)" || _IC_RC=$?
}

# ── M1: happy path (AC1) ─────────────────────────────────────────────────────

test_m1_clean_exits_0() {
    _ic_setup
    local _fail=0
    _run_pipeline exceptions
    assert_success   $_IC_RC "clean install should exit 0"            || _fail=1
    assert_contains  "all files OK" "$_IC_OUT" "output"              || _fail=1
    return $_fail
}

test_m1_regression_injected_mismatch_fails() {
    _ic_setup
    local _fail=0
    local script="${_TMPDIR}/reg.sh"
    cat > "$script" <<SCRIPT
#!/usr/bin/env bash
set -uo pipefail
export AI_PODMAN_JAILS_DIR='${AI_PODMAN_JAILS_DIR}'
export PATH='${PATH}'
source '${LIB_DIR}/integrity.sh'
compare_files() { _ic_mismatch["bin/ai-new"]="expected=aaa  actual=bbb"; }
_ic_setup_tmpdir; detect_version; fetch_tarball; build_manifest; compare_files
print_exceptions || true
issues=\$(( \${#_ic_missing[@]} + \${#_ic_mismatch[@]} ))
[[ "\${issues}" -gt 0 ]] && exit 1 || exit 0
SCRIPT
    local out rc=0
    out="$(bash "$script" 2>&1)" || rc=$?
    assert_failure   $rc  "injected mismatch must fail"              || _fail=1
    assert_contains  "MODIFIED" "$out" "MODIFIED line present"       || _fail=1
    return $_fail
}

# ── M2: detection (AC2, AC10) ─────────────────────────────────────────────────

test_m2a_modified_file_detected() {
    _ic_setup
    echo "corrupted" > "${AI_PODMAN_JAILS_DIR}/bin/ai-new"
    local _fail=0
    _run_pipeline exceptions
    assert_failure       $_IC_RC                                    || _fail=1
    assert_contains  "MODIFIED"    "$_IC_OUT" "MODIFIED line"       || _fail=1
    assert_contains  "bin/ai-new"  "$_IC_OUT" "file name"           || _fail=1
    assert_contains  "expected="   "$_IC_OUT" "expected hash"       || _fail=1
    assert_contains  "actual="     "$_IC_OUT" "actual hash"         || _fail=1
    assert_not_contains "MISSING"  "$_IC_OUT" "no MISSING"          || _fail=1
    return $_fail
}

test_m2b_missing_file_detected() {
    _ic_setup
    rm "${AI_PODMAN_JAILS_DIR}/lib/common.sh"
    local _fail=0
    _run_pipeline exceptions
    assert_failure      $_IC_RC                                     || _fail=1
    assert_contains "MISSING"      "$_IC_OUT" "MISSING line"        || _fail=1
    assert_contains "lib/common.sh" "$_IC_OUT" "file name"          || _fail=1
    return $_fail
}

test_m2c_unexpected_file_is_warning() {
    # ponytail: exit 0 per spec (unexpected = warning); pipeline implements spec behavior
    _ic_setup
    echo "#!/bin/sh" > "${AI_PODMAN_JAILS_DIR}/bin/extra-tool"
    chmod 755 "${AI_PODMAN_JAILS_DIR}/bin/extra-tool"
    local _fail=0
    _run_pipeline exceptions
    assert_success      $_IC_RC "unexpected-only exits 0 (warning)" || _fail=1
    assert_contains "UNEXPECTED"   "$_IC_OUT" "UNEXPECTED line"     || _fail=1
    assert_contains "bin/extra-tool" "$_IC_OUT" "file name"         || _fail=1
    assert_not_contains "MISSING"  "$_IC_OUT" "no MISSING"          || _fail=1
    return $_fail
}

# ── M3: output modes (AC3, AC4) ──────────────────────────────────────────────

test_m3a_verbose_clean() {
    _ic_setup
    local _fail=0
    _run_pipeline verbose
    assert_success   $_IC_RC                                        || _fail=1
    assert_contains "bin/ai-build"  "$_IC_OUT" "ai-build present"  || _fail=1
    assert_contains "bin/ai-new"    "$_IC_OUT" "ai-new present"    || _fail=1
    assert_contains "lib/common.sh" "$_IC_OUT" "common.sh present" || _fail=1
    assert_contains "OK"            "$_IC_OUT" "OK status"         || _fail=1
    return $_fail
}

test_m3b_diff_modified() {
    _ic_setup
    echo "corrupted" > "${AI_PODMAN_JAILS_DIR}/bin/ai-new"
    local _fail=0
    _run_pipeline diffs
    assert_failure       $_IC_RC                                    || _fail=1
    assert_contains "---"          "$_IC_OUT" "diff --- line"      || _fail=1
    assert_contains "+++"          "$_IC_OUT" "diff +++ line"      || _fail=1
    assert_contains "bin/ai-new"   "$_IC_OUT" "file in diff label" || _fail=1
    [[ "$(printf '%s\n' "$_IC_OUT" | wc -l)" -gt 3 ]] || {
        printf '    diff block is empty\n' >&2; _fail=1
    }
    return $_fail
}

test_m3c_verbose_and_diff_combined() {
    _ic_setup
    echo "corrupted" > "${AI_PODMAN_JAILS_DIR}/bin/ai-new"
    local _fail=0
    _run_pipeline verbose_diffs
    assert_failure       $_IC_RC                                    || _fail=1
    assert_contains "MODIFIED"     "$_IC_OUT" "MODIFIED in table"  || _fail=1
    assert_contains "---"          "$_IC_OUT" "diff block"         || _fail=1
    assert_contains "+++"          "$_IC_OUT" "diff block"         || _fail=1
    return $_fail
}

# ── M4: repair (AC5, AC6) ────────────────────────────────────────────────────
# 4a/4b use driver scripts: prompt_repair reads fd 2, not stdin, making
# stdin-piping unreliable in non-TTY test envs; driver simulates the choice.

test_m4a_accept_repair() {
    _ic_setup
    echo "corrupted" > "${AI_PODMAN_JAILS_DIR}/bin/ai-new"
    local _fail=0 rc=0
    local script="${_TMPDIR}/driver_4a.sh"
    cat > "$script" <<DRIVER
#!/usr/bin/env bash
set -uo pipefail
export AI_PODMAN_JAILS_DIR='${AI_PODMAN_JAILS_DIR}'
export PATH='${PATH}'
source '${LIB_DIR}/integrity.sh'
_ic_setup_tmpdir; detect_version; fetch_tarball; build_manifest; compare_files
repair_needed=\$(( \${#_ic_missing[@]} + \${#_ic_mismatch[@]} ))
[[ "\${repair_needed}" -gt 0 ]] || exit 0
repair_files
exit 0
DRIVER
    bash "$script" 2>/dev/null || rc=$?
    assert_success $rc "accept repair exits 0" || _fail=1
    local exp act
    exp="$(sha256sum "${_IC_INSTALL}/bin/ai-new"   | awk '{print $1}')"
    act="$(sha256sum "${AI_PODMAN_JAILS_DIR}/bin/ai-new" | awk '{print $1}')"
    assert_eq "$exp" "$act" "restored file matches tarball" || _fail=1
    [[ -f "${AI_PODMAN_JAILS_DIR}/bin/ai-build"  ]] || { printf '    ai-build missing\n' >&2; _fail=1; }
    [[ -f "${AI_PODMAN_JAILS_DIR}/lib/common.sh" ]] || { printf '    common.sh missing\n' >&2; _fail=1; }
    return $_fail
}

test_m4b_decline_repair() {
    _ic_setup
    echo "corrupted" > "${AI_PODMAN_JAILS_DIR}/bin/ai-new"
    local _fail=0 rc=0
    local script="${_TMPDIR}/driver_4b.sh"
    cat > "$script" <<DRIVER
#!/usr/bin/env bash
set -uo pipefail
export AI_PODMAN_JAILS_DIR='${AI_PODMAN_JAILS_DIR}'
export PATH='${PATH}'
source '${LIB_DIR}/integrity.sh'
_ic_setup_tmpdir; detect_version; fetch_tarball; build_manifest; compare_files
repair_needed=\$(( \${#_ic_missing[@]} + \${#_ic_mismatch[@]} ))
[[ "\${repair_needed}" -gt 0 ]] || exit 0
exit 1
DRIVER
    bash "$script" 2>/dev/null || rc=$?
    assert_failure $rc "decline repair exits 1" || _fail=1
    local content
    content="$(< "${AI_PODMAN_JAILS_DIR}/bin/ai-new")"
    assert_eq "corrupted" "$content" "file unchanged after decline" || _fail=1
    return $_fail
}

test_m4c_repair_flag() {
    _ic_setup
    echo "corrupted" > "${AI_PODMAN_JAILS_DIR}/bin/ai-new"
    local _fail=0 rc=0 out
    out="$(AI_PODMAN_JAILS_DIR="${AI_PODMAN_JAILS_DIR}" PATH="${PATH}" \
           "${BIN_DIR}/ai-pod-doctor" integrity-check --repair 2>&1)" || rc=$?
    assert_success $rc "--repair exits 0"               || _fail=1
    local exp act
    exp="$(sha256sum "${_IC_INSTALL}/bin/ai-new"        | awk '{print $1}')"
    act="$(sha256sum "${AI_PODMAN_JAILS_DIR}/bin/ai-new" | awk '{print $1}')"
    assert_eq "$exp" "$act" "--repair restores file"    || _fail=1
    assert_not_contains "y/N" "$out" "no prompt text"   || _fail=1
    local mode; mode="$(stat -c '%a' "${AI_PODMAN_JAILS_DIR}/bin/ai-new")"
    assert_eq "755" "$mode" "permissions preserved"     || _fail=1
    return $_fail
}

# ── M5: error paths (AC7, AC8, AC9) ──────────────────────────────────────────

test_m5a_no_version_file() {
    _ic_setup
    rm "${AI_PODMAN_JAILS_DIR}/VERSION"
    local _fail=0 rc=0 out
    out="$(AI_PODMAN_JAILS_DIR="${AI_PODMAN_JAILS_DIR}" PATH="${PATH}" \
           "${BIN_DIR}/ai-pod-doctor" integrity-check 2>&1)" || rc=$?
    assert_eq 3 $rc "missing VERSION exits 3"                  || _fail=1
    assert_contains "version"   "$out" "mentions 'version'"    || _fail=1
    assert_contains "reinstall" "$out" "mentions 'reinstall'"  || _fail=1
    return $_fail
}

test_m5b_network_failure() {
    _ic_setup
    local _fail=0 rc=0 out
    out="$(AI_PODMAN_JAILS_DIR="${AI_PODMAN_JAILS_DIR}" PATH="${PATH}" \
           FAIL_CURL=1 \
           "${BIN_DIR}/ai-pod-doctor" integrity-check 2>&1)" || rc=$?
    assert_eq 2 $rc "network failure exits 2"                  || _fail=1
    assert_contains "https://" "$out" "URL in output"          || _fail=1
    return $_fail
}

test_m5c_temp_cleanup() {
    _ic_setup
    local _fail=0 before after

    before="$(find /tmp -maxdepth 1 -name 'tmp.*' -type d 2>/dev/null | sort || true)"

    # clean path
    AI_PODMAN_JAILS_DIR="${AI_PODMAN_JAILS_DIR}" PATH="${PATH}" \
        "${BIN_DIR}/ai-pod-doctor" integrity-check >/dev/null 2>&1 || true
    after="$(find /tmp -maxdepth 1 -name 'tmp.*' -type d 2>/dev/null | sort || true)"
    [[ "$before" == "$after" ]] || { printf '    temp dir leaked (clean path)\n' >&2; _fail=1; }

    # mismatch path (repair to reset)
    echo "corrupted" > "${AI_PODMAN_JAILS_DIR}/bin/ai-new"
    AI_PODMAN_JAILS_DIR="${AI_PODMAN_JAILS_DIR}" PATH="${PATH}" \
        "${BIN_DIR}/ai-pod-doctor" integrity-check --repair >/dev/null 2>&1 || true
    after="$(find /tmp -maxdepth 1 -name 'tmp.*' -type d 2>/dev/null | sort || true)"
    [[ "$before" == "$after" ]] || { printf '    temp dir leaked (mismatch path)\n' >&2; _fail=1; }

    # error path (no VERSION)
    rm "${AI_PODMAN_JAILS_DIR}/VERSION"
    AI_PODMAN_JAILS_DIR="${AI_PODMAN_JAILS_DIR}" PATH="${PATH}" \
        "${BIN_DIR}/ai-pod-doctor" integrity-check >/dev/null 2>&1 || true
    after="$(find /tmp -maxdepth 1 -name 'tmp.*' -type d 2>/dev/null | sort || true)"
    [[ "$before" == "$after" ]] || { printf '    temp dir leaked (error path)\n' >&2; _fail=1; }

    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────

run_test "M1: clean install exits 0"                   test_m1_clean_exits_0
run_test "M1: injected mismatch causes failure"        test_m1_regression_injected_mismatch_fails
run_test "M2a: modified file → MODIFIED + exit 1"     test_m2a_modified_file_detected
run_test "M2b: missing file → MISSING + exit 1"       test_m2b_missing_file_detected
run_test "M2c: unexpected file → UNEXPECTED + exit 0" test_m2c_unexpected_file_is_warning
run_test "M3a: --verbose clean shows OK for all files" test_m3a_verbose_clean
run_test "M3b: --diff on modified shows unified diff"  test_m3b_diff_modified
run_test "M3c: --verbose --diff combined"              test_m3c_verbose_and_diff_combined
run_test "M4a: accept repair restores file (exit 0)"   test_m4a_accept_repair
run_test "M4b: decline repair leaves file unchanged"   test_m4b_decline_repair
run_test "M4c: --repair flag restores without prompt"  test_m4c_repair_flag
run_test "M5a: no VERSION → exit 3 + clear message"   test_m5a_no_version_file
run_test "M5b: network failure → exit 2 + URL"        test_m5b_network_failure
run_test "M5c: temp dir cleaned on all exit paths"     test_m5c_temp_cleanup

_cleanup_fixture

print_summary "test_integrity"
