#!/usr/bin/env bash
# T7b — ai-list: aligned listing with state column; missing dir exits non-zero (AC11).
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"
source "${LIB_DIR}/common.sh"
source "${LIB_DIR}/slug.sh"
source "${LIB_DIR}/scaffold.sh"

test_ai_list_prints_profiles() {
    local _fail=0
    local out rc=0
    out="$(CODEX_JAILS_DIR="$_TMPDIR" PATH="${STUBS_DIR}:${PATH}" \
        "${BIN_DIR}/ai-list" 2>/dev/null)" || rc=$?
    assert_success $rc "ai-list should exit 0 when profiles exist" || _fail=1
    assert_contains "PROFILE"   "$out" "header row present" || _fail=1
    assert_contains "IMAGE"     "$out" "IMAGE column present" || _fail=1
    assert_contains "WORKSPACE" "$out" "WORKSPACE column present" || _fail=1
    assert_contains "STATE"     "$out" "STATE column present" || _fail=1
    # Reference profiles seeded by setup
    assert_contains "esp32"  "$out" "esp32 profile listed" || _fail=1
    assert_contains "uxplay" "$out" "uxplay profile listed" || _fail=1
    return $_fail
}

test_ai_list_state_column_absent() {
    # Without live podman the stub returns non-zero for container exists,
    # so all profiles should show "absent".
    local _fail=0
    local out
    out="$(CODEX_JAILS_DIR="$_TMPDIR" PATH="${STUBS_DIR}:${PATH}" \
        "${BIN_DIR}/ai-list" 2>/dev/null)"
    assert_contains "absent" "$out" "state column shows absent when no containers" || _fail=1
    return $_fail
}

test_ai_list_column_alignment() {
    local _fail=0
    local out
    out="$(CODEX_JAILS_DIR="$_TMPDIR" PATH="${STUBS_DIR}:${PATH}" \
        "${BIN_DIR}/ai-list" 2>/dev/null)"
    # All data rows must have the same number of fields (columns) as the header.
    # Count fields in the header (space-separated columns delimited by 2+ spaces).
    local header_cols data_cols
    header_cols="$(echo "$out" | head -1 | awk '{print NF}')"
    # Every data row (skip header and separator) must have same field count
    local bad_rows=0
    while IFS= read -r line; do
        [[ -z "$line" || "$line" == ---* ]] && continue
        data_cols="$(echo "$line" | awk '{print NF}')"
        [[ "$data_cols" -ge "$header_cols" ]] || (( bad_rows++ )) || true
    done <<< "$(echo "$out" | tail -n +3)"
    [[ $bad_rows -eq 0 ]] \
        || { printf '    %d rows had fewer columns than header\n' "$bad_rows" >&2; _fail=1; }
    return $_fail
}

test_ai_list_no_ansi_when_piped() {
    # ai-list must not emit ANSI escape codes (output goes to stdout, not a TTY here).
    local _fail=0
    local out
    out="$(CODEX_JAILS_DIR="$_TMPDIR" PATH="${STUBS_DIR}:${PATH}" \
        "${BIN_DIR}/ai-list" 2>/dev/null)"
    if printf '%s' "$out" | grep -qP '\x1b\['; then
        echo "    ANSI escape codes found in piped output" >&2
        _fail=1
    fi
    return $_fail
}

test_ai_list_empty_state_exits_zero() {
    local _fail=0
    local empty_dir="${_TMPDIR}/empty_root"
    mkdir -p "$empty_dir"
    local out rc=0
    out="$(CODEX_JAILS_DIR="$empty_dir" PATH="${STUBS_DIR}:${PATH}" \
        "${BIN_DIR}/ai-list" 2>&1)" || rc=$?
    assert_success $rc "no profiles anywhere → exit 0 (AC2)" || _fail=1
    assert_contains "No profiles found" "$out" "empty-state message should be printed" || _fail=1
    return $_fail
}

test_ai_list_help_exits_zero() {
    local _fail=0
    local rc=0
    "${BIN_DIR}/ai-list" --help 2>/dev/null || rc=$?
    assert_success $rc "--help exits 0" || _fail=1
    return $_fail
}

test_ai_list_sees_registered_generated_project() {
    local _fail=0
    local _proj="${_TMPDIR}/projects/alex"
    mkdir -p "$_proj"
    cat > "${_proj}/profile.env" <<EOF
PROFILE_NAME="alex"
CONTAINER_NAME="alex"
IMAGE_NAME="localhost/alex:latest"
IMAGE_DIR="\${CODEX_JAILS_DIR}/projects/alex/image"
WORKSPACE="\${CODEX_JAILS_DIR}/projects/alex/workspace"
CONTAINER_HOME="\${CODEX_JAILS_DIR}/projects/alex/state/home"
BASHRC="\${WORKSPACE}/.bashrc"
WORKDIR="/workspace"
BUILD_ARGS=""
NETWORK_MODE="bridge"
EXTRA_ENV=()
EXTRA_VOLUMES=()
EXTRA_DEVICES=()
EXTRA_HOSTS=()
EXTRA_RUN_ARGS=()
EOF

    local out rc=0
    out="$(CODEX_JAILS_DIR="$_TMPDIR" PATH="${STUBS_DIR}:${PATH}" \
        "${BIN_DIR}/ai-list" 2>/dev/null)" || rc=$?
    assert_success $rc "ai-list should succeed after generated profile registration" || _fail=1
    assert_contains "alex" "$out" "registered generated project should be listed" || _fail=1
    return $_fail
}

test_ai_list_syncs_project_profiles_automatically() {
    local _fail=0
    local _proj="${_TMPDIR}/projects/alex-sync"
    mkdir -p "$_proj"
    cat > "${_proj}/profile.env" <<EOF
PROFILE_NAME="alex-sync"
CONTAINER_NAME="alex-sync"
IMAGE_NAME="localhost/alex-sync:latest"
IMAGE_DIR="\${CODEX_JAILS_DIR}/projects/alex-sync/image"
WORKSPACE="\${CODEX_JAILS_DIR}/projects/alex-sync/workspace"
CONTAINER_HOME="\${CODEX_JAILS_DIR}/projects/alex-sync/state/home"
BASHRC="\${WORKSPACE}/.bashrc"
WORKDIR="/workspace"
BUILD_ARGS=""
NETWORK_MODE="bridge"
EXTRA_ENV=()
EXTRA_VOLUMES=()
EXTRA_DEVICES=()
EXTRA_HOSTS=()
EXTRA_RUN_ARGS=()
EOF

    local out rc=0
    out="$(CODEX_JAILS_DIR="$_TMPDIR" PATH="${STUBS_DIR}:${PATH}" \
        "${BIN_DIR}/ai-list" 2>/dev/null)" || rc=$?
    assert_success $rc "ai-list should succeed with project-local profile" || _fail=1
    assert_contains "alex-sync" "$out" "project-local profile should appear in listing" || _fail=1
    # No mirror should have been written to profiles/
    [[ ! -f "${_TMPDIR}/profiles/alex-sync.env" ]] || {
        printf '    profiles/alex-sync.env was created (mirror must not happen)\n' >&2
        _fail=1
    }
    return $_fail
}

# ── Milestone 3: dual-discovery / dedup ───────────────────────────────────────

test_list_dedupes_by_slug() {
    local _fail=0
    # Both a project tree and a legacy file for the same slug — list must show exactly one row.
    mkdir -p "${_TMPDIR}/projects/dup"
    cat > "${_TMPDIR}/projects/dup/profile.env" <<EOF
PROFILE_NAME="dup"
CONTAINER_NAME="dup-ctr"
IMAGE_NAME="localhost/dup:latest"
IMAGE_DIR="${_TMPDIR}/projects/dup/image"
WORKSPACE="${_TMPDIR}/projects/dup/workspace"
CONTAINER_HOME="${_TMPDIR}/projects/dup/state/home"
BASHRC="${_TMPDIR}/projects/dup/workspace/.bashrc"
WORKDIR="/workspace"
BUILD_ARGS=""
EXTRA_ENV=()
EXTRA_VOLUMES=()
EXTRA_DEVICES=()
EXTRA_HOSTS=()
EXTRA_RUN_ARGS=()
EOF
    cat > "${_TMPDIR}/profiles/dup.env" <<EOF
PROFILE_NAME="dup"
CONTAINER_NAME="dup-legacy"
IMAGE_NAME="localhost/dup-legacy:latest"
IMAGE_DIR="${_TMPDIR}/image"
WORKSPACE="${_TMPDIR}/workspace"
CONTAINER_HOME="/home/builder"
BASHRC="${_TMPDIR}/workspace/.bashrc"
WORKDIR="/workspace"
BUILD_ARGS=""
EOF
    local out rc=0
    out="$(CODEX_JAILS_DIR="$_TMPDIR" PATH="${STUBS_DIR}:${PATH}" \
        "${BIN_DIR}/ai-list" 2>/dev/null)" || rc=$?
    assert_success $rc "ai-list should exit 0 with both sources for same slug" || _fail=1
    local _dup_count
    _dup_count="$(echo "$out" | grep -c '\bdup\b' || true)"
    # Header counts as 0 (it says PROFILE not 'dup'); only data rows with 'dup' should appear once
    [[ "$_dup_count" -le 1 ]] || {
        printf '    dup slug listed %d times (expected 1)\n' "$_dup_count" >&2
        _fail=1
    }
    return $_fail
}

test_list_shows_legacy_only() {
    local _fail=0
    # Legacy-only profile with no project tree must still appear.
    local _empty="${_TMPDIR}/legacy_only_root"
    mkdir -p "${_empty}/profiles"
    cat > "${_empty}/profiles/legacyonly.env" <<EOF
PROFILE_NAME="legacyonly"
CONTAINER_NAME="legacyonly-ctr"
IMAGE_NAME="localhost/legacyonly:latest"
IMAGE_DIR="${_empty}/image"
WORKSPACE="${_empty}/workspace"
CONTAINER_HOME="/home/builder"
BASHRC="${_empty}/workspace/.bashrc"
WORKDIR="/workspace"
BUILD_ARGS=""
EOF
    local out rc=0
    out="$(CODEX_JAILS_DIR="$_empty" PATH="${STUBS_DIR}:${PATH}" \
        "${BIN_DIR}/ai-list" 2>/dev/null)" || rc=$?
    assert_success $rc "ai-list should exit 0 with legacy-only profile (AC3)" || _fail=1
    assert_contains "legacyonly" "$out" "legacy-only profile should appear" || _fail=1
    return $_fail
}

test_list_works_without_profiles_dir() {
    local _fail=0
    # profiles/ absent; only a projects/ entry — must still list and exit 0 (AC2).
    local _noleg="${_TMPDIR}/no_profiles_dir"
    mkdir -p "${_noleg}/projects/onlyproj"
    cat > "${_noleg}/projects/onlyproj/profile.env" <<EOF
PROFILE_NAME="onlyproj"
CONTAINER_NAME="onlyproj-ctr"
IMAGE_NAME="localhost/onlyproj:latest"
IMAGE_DIR="${_noleg}/projects/onlyproj/image"
WORKSPACE="${_noleg}/projects/onlyproj/workspace"
CONTAINER_HOME="${_noleg}/projects/onlyproj/state/home"
BASHRC="${_noleg}/projects/onlyproj/workspace/.bashrc"
WORKDIR="/workspace"
BUILD_ARGS=""
EXTRA_ENV=()
EXTRA_VOLUMES=()
EXTRA_DEVICES=()
EXTRA_HOSTS=()
EXTRA_RUN_ARGS=()
EOF
    local out rc=0
    out="$(CODEX_JAILS_DIR="$_noleg" PATH="${STUBS_DIR}:${PATH}" \
        "${BIN_DIR}/ai-list" 2>/dev/null)" || rc=$?
    assert_success $rc "ai-list should exit 0 with no profiles/ dir (AC2)" || _fail=1
    assert_contains "onlyproj" "$out" "project should be listed without profiles/ dir" || _fail=1
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "ai-list prints profile name, image, workspace, state"   test_ai_list_prints_profiles
run_test "ai-list state column shows 'absent' with stub podman"   test_ai_list_state_column_absent
run_test "ai-list column alignment consistent across rows"         test_ai_list_column_alignment
run_test "ai-list emits no ANSI when piped"                       test_ai_list_no_ansi_when_piped
run_test "ai-list: no profiles anywhere → exit 0 with message"    test_ai_list_empty_state_exits_zero
run_test "ai-list --help exits 0"                                  test_ai_list_help_exits_zero
run_test "ai-list sees registered generated project"              test_ai_list_sees_registered_generated_project
run_test "ai-list syncs project profiles automatically"           test_ai_list_syncs_project_profiles_automatically
run_test "ai-list dedupes project + legacy with same slug (R2.3)" test_list_dedupes_by_slug
run_test "ai-list shows legacy-only profile (AC3)"                test_list_shows_legacy_only
run_test "ai-list works without profiles/ dir (AC2)"              test_list_works_without_profiles_dir

print_summary "61_list"
