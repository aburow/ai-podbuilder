#!/usr/bin/env bash
# T2a — Profile loading: required fields, missing profiles, optional arrays.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

# ── Tests ─────────────────────────────────────────────────────────────────────

test_valid_profile_loads() {
    local _fail=0
    # Use a helper script so load_profile runs in a fresh subshell that can
    # export its state; then capture and check stderr for errors only.
    local helper="${_TMPDIR}/check_load.sh"
    cat > "$helper" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/profile.sh'
export CODEX_JAILS_DIR='${_TMPDIR}'
resolve_base_dir
load_profile esp32
# Print required vars so we can verify them
printf 'PROFILE_NAME=%s\n' "\$PROFILE_NAME"
printf 'CONTAINER_NAME=%s\n' "\$CONTAINER_NAME"
printf 'IMAGE_NAME=%s\n' "\$IMAGE_NAME"
EOF
    local out rc=0
    out="$(bash "$helper" 2>&1)" || rc=$?
    assert_success $rc "load_profile esp32 should succeed" || _fail=1
    assert_contains "PROFILE_NAME=esp32"       "$out" || _fail=1
    assert_contains "CONTAINER_NAME=codex-esp32" "$out" || _fail=1
    assert_contains "IMAGE_NAME=codex-esp32-image" "$out" || _fail=1
    return $_fail
}

test_missing_required_field_exits_nonzero() {
    # Write a profile missing CONTAINER_NAME
    local _fail=0
    cat > "${_TMPDIR}/profiles/broken.env" <<'EOF'
PROFILE_NAME="broken"
IMAGE_NAME="broken-image"
IMAGE_DIR="/tmp/broken-image"
WORKSPACE="/tmp/broken-ws"
CONTAINER_HOME="/home/builder"
BASHRC="/tmp/.bashrc"
WORKDIR="/workspace"
BUILD_ARGS=""
EOF
    # Spin up a fresh shell to avoid contaminating current env
    local out rc=0
    out="$(CODEX_JAILS_DIR="$_TMPDIR" bash -c "
        source '${LIB_DIR}/common.sh'
        source '${LIB_DIR}/profile.sh'
        resolve_base_dir
        load_profile broken
    " 2>&1)" || rc=$?
    assert_failure $rc "missing CONTAINER_NAME should exit non-zero" || _fail=1
    assert_contains "CONTAINER_NAME" "$out" "error should name the missing field" || _fail=1
    return $_fail
}

test_nonexistent_profile_exits_nonzero() {
    local _fail=0
    local out rc=0
    out="$(CODEX_JAILS_DIR="$_TMPDIR" bash -c "
        source '${LIB_DIR}/common.sh'
        source '${LIB_DIR}/profile.sh'
        resolve_base_dir
        load_profile no_such_profile
    " 2>&1)" || rc=$?
    assert_failure $rc "nonexistent profile should exit non-zero" || _fail=1
    assert_contains "no_such_profile" "$out" "error should name the profile" || _fail=1
    return $_fail
}

test_optional_arrays_defined_under_set_u() {
    # Optional arrays must be usable (defined) even when not set in the profile.
    # We write a minimal profile with no EXTRA_* vars.
    local _fail=0
    cat > "${_TMPDIR}/profiles/minimal.env" <<EOF
PROFILE_NAME="minimal"
CONTAINER_NAME="minimal-ctr"
IMAGE_NAME="minimal-image"
IMAGE_DIR="${_TMPDIR}/minimal-image"
WORKSPACE="${_TMPDIR}/minimal-ws"
CONTAINER_HOME="/home/builder"
BASHRC="${_TMPDIR}/.bashrc"
WORKDIR="/workspace"
BUILD_ARGS=""
EOF
    local out rc=0
    out="$(CODEX_JAILS_DIR="$_TMPDIR" bash -c '
        set -u
        source '"'"'${LIB_DIR}/common.sh'"'"'
        source '"'"'${LIB_DIR}/profile.sh'"'"'
        resolve_base_dir
        load_profile minimal
        # Access optional arrays — must not trigger "unbound variable" under set -u
        echo "env=${#EXTRA_ENV[@]}"
        echo "vols=${#EXTRA_VOLUMES[@]}"
        echo "devs=${#EXTRA_DEVICES[@]}"
        echo "hosts=${#EXTRA_HOSTS[@]}"
    ' 2>&1)" || rc=$?
    # Replace single-quoted vars with actual values in the heredoc above is tricky;
    # write a helper script to a temp file instead.
    local helper="${_TMPDIR}/check_optional.sh"
    cat > "$helper" <<EOF
#!/usr/bin/env bash
set -u
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/profile.sh'
export CODEX_JAILS_DIR='${_TMPDIR}'
resolve_base_dir
load_profile minimal
echo "env=\${#EXTRA_ENV[@]}"
echo "vols=\${#EXTRA_VOLUMES[@]}"
echo "devs=\${#EXTRA_DEVICES[@]}"
echo "hosts=\${#EXTRA_HOSTS[@]}"
EOF
    rc=0
    out="$(bash "$helper" 2>&1)" || rc=$?
    assert_success $rc "optional arrays usable under set -u" || _fail=1
    assert_contains "env=" "$out" || _fail=1
    return $_fail
}

test_project_local_loads_without_mirror() {
    local _fail=0
    mkdir -p "${_TMPDIR}/projects/recoverme"
    cat > "${_TMPDIR}/projects/recoverme/profile.env" <<EOF
PROFILE_NAME="recoverme"
CONTAINER_NAME="recoverme-ctr"
IMAGE_NAME="recoverme-image"
IMAGE_DIR="${_TMPDIR}/projects/recoverme/image"
WORKSPACE="${_TMPDIR}/projects/recoverme/workspace"
CONTAINER_HOME="${_TMPDIR}/projects/recoverme/state/home"
BASHRC="${_TMPDIR}/projects/recoverme/workspace/.bashrc"
WORKDIR="/workspace"
BUILD_ARGS=""
EOF

    local out rc=0
    out="$(CODEX_JAILS_DIR="$_TMPDIR" bash -c "
        source '${LIB_DIR}/common.sh'
        source '${LIB_DIR}/profile.sh'
        resolve_base_dir
        load_profile recoverme
        printf 'PROFILE_NAME=%s\n' \"\$PROFILE_NAME\"
    " 2>&1)" || rc=$?
    assert_success $rc "load_profile should load a project-local profile from projects/" || _fail=1
    assert_contains "PROFILE_NAME=recoverme" "$out" || _fail=1
    # AC6: project-local load must NOT write a mirror to profiles/
    [[ ! -f "${_TMPDIR}/profiles/recoverme.env" ]] || {
        printf '    profiles/recoverme.env was created (copy-back must not happen)\n' >&2
        _fail=1
    }
    return $_fail
}

# ── Milestone 2: dual-read resolution ─────────────────────────────────────────

test_project_local_preferred_over_legacy() {
    local _fail=0
    mkdir -p "${_TMPDIR}/projects/p"
    cat > "${_TMPDIR}/projects/p/profile.env" <<EOF
PROFILE_NAME="from-project"
CONTAINER_NAME="p-ctr"
IMAGE_NAME="p-image"
IMAGE_DIR="${_TMPDIR}/projects/p/image"
WORKSPACE="${_TMPDIR}/projects/p/workspace"
CONTAINER_HOME="/home/builder"
BASHRC="${_TMPDIR}/projects/p/workspace/.bashrc"
WORKDIR="/workspace"
BUILD_ARGS=""
EOF
    cat > "${_TMPDIR}/profiles/p.env" <<EOF
PROFILE_NAME="from-legacy"
CONTAINER_NAME="p-legacy-ctr"
IMAGE_NAME="p-legacy-image"
IMAGE_DIR="${_TMPDIR}/image"
WORKSPACE="${_TMPDIR}/workspace"
CONTAINER_HOME="/home/builder"
BASHRC="${_TMPDIR}/workspace/.bashrc"
WORKDIR="/workspace"
BUILD_ARGS=""
EOF
    local helper="${_TMPDIR}/check_priority.sh"
    cat > "$helper" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/profile.sh'
export CODEX_JAILS_DIR='${_TMPDIR}'
resolve_base_dir
load_profile p
printf 'PROFILE_NAME=%s\n' "\$PROFILE_NAME"
SCRIPT
    local out rc=0
    out="$(bash "$helper" 2>&1)" || rc=$?
    assert_success $rc "load_profile p should succeed" || _fail=1
    assert_contains "PROFILE_NAME=from-project" "$out" "project-local should take precedence over legacy" || _fail=1
    return $_fail
}

test_legacy_fallback_loads() {
    local _fail=0
    # Only legacy file; no projects/ entry.
    cat > "${_TMPDIR}/profiles/legacyonly.env" <<EOF
PROFILE_NAME="legacyonly"
CONTAINER_NAME="legacyonly-ctr"
IMAGE_NAME="legacyonly-image"
IMAGE_DIR="${_TMPDIR}/image"
WORKSPACE="${_TMPDIR}/workspace"
CONTAINER_HOME="/home/builder"
BASHRC="${_TMPDIR}/workspace/.bashrc"
WORKDIR="/workspace"
BUILD_ARGS=""
EOF
    local helper="${_TMPDIR}/check_legacy.sh"
    cat > "$helper" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/profile.sh'
export CODEX_JAILS_DIR='${_TMPDIR}'
resolve_base_dir
load_profile legacyonly
printf 'PROFILE_NAME=%s\n' "\$PROFILE_NAME"
SCRIPT
    local out rc=0
    out="$(bash "$helper" 2>&1)" || rc=$?
    assert_success $rc "legacy-only load should succeed (AC5)" || _fail=1
    assert_contains "PROFILE_NAME=legacyonly" "$out" || _fail=1
    return $_fail
}

test_name_slug_divergence_resolves() {
    # Q1 regression: name with spaces; project dir uses raw name.
    local _fail=0
    mkdir -p "${_TMPDIR}/projects/My Proj"
    cat > "${_TMPDIR}/projects/My Proj/profile.env" <<EOF
PROFILE_NAME="My Proj"
CONTAINER_NAME="my-proj-ctr"
IMAGE_NAME="my-proj-image"
IMAGE_DIR="${_TMPDIR}/projects/my-proj/image"
WORKSPACE="${_TMPDIR}/projects/my-proj/workspace"
CONTAINER_HOME="/home/builder"
BASHRC="${_TMPDIR}/projects/my-proj/workspace/.bashrc"
WORKDIR="/workspace"
BUILD_ARGS=""
EOF
    local helper="${_TMPDIR}/check_diverge.sh"
    cat > "$helper" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/profile.sh'
export CODEX_JAILS_DIR='${_TMPDIR}'
resolve_base_dir
load_profile 'My Proj'
printf 'PROFILE_NAME=%s\n' "\$PROFILE_NAME"
SCRIPT
    local out rc=0
    out="$(bash "$helper" 2>&1)" || rc=$?
    assert_success $rc "load_profile with space-containing name should succeed" || _fail=1
    assert_contains "PROFILE_NAME=My Proj" "$out" || _fail=1
    return $_fail
}

test_missing_profile_names_both_paths() {
    local _fail=0
    local out rc=0
    out="$(CODEX_JAILS_DIR="$_TMPDIR" bash -c "
        source '${LIB_DIR}/common.sh'
        source '${LIB_DIR}/profile.sh'
        resolve_base_dir
        load_profile nope
    " 2>&1)" || rc=$?
    assert_failure $rc "missing profile should exit non-zero" || _fail=1
    assert_contains "projects/nope/profile.env" "$out" "error should name project-local candidate" || _fail=1
    assert_contains "profiles/" "$out" "error should name legacy candidate" || _fail=1
    return $_fail
}

test_no_writeback_on_project_local_load() {
    local _fail=0
    mkdir -p "${_TMPDIR}/projects/nowb"
    cat > "${_TMPDIR}/projects/nowb/profile.env" <<EOF
PROFILE_NAME="nowb"
CONTAINER_NAME="nowb-ctr"
IMAGE_NAME="nowb-image"
IMAGE_DIR="${_TMPDIR}/projects/nowb/image"
WORKSPACE="${_TMPDIR}/projects/nowb/workspace"
CONTAINER_HOME="/home/builder"
BASHRC="${_TMPDIR}/projects/nowb/workspace/.bashrc"
WORKDIR="/workspace"
BUILD_ARGS=""
EOF
    CODEX_JAILS_DIR="$_TMPDIR" bash -c "
        source '${LIB_DIR}/common.sh'
        source '${LIB_DIR}/profile.sh'
        resolve_base_dir
        load_profile nowb
    " >/dev/null 2>&1 || true
    # AC6: no file should appear under profiles/ after a project-local load
    local _new_files
    _new_files="$(find "${_TMPDIR}/profiles" -name 'nowb*.env' 2>/dev/null || true)"
    [[ -z "$_new_files" ]] || {
        printf '    profiles/ got a new file after project-local load: %s\n' "$_new_files" >&2
        _fail=1
    }
    return $_fail
}

# ── Milestone 5: deprecation notice ───────────────────────────────────────────

test_legacy_load_emits_deprecation_info() {
    local _fail=0
    # Legacy-only: only profiles/<slug>.env exists.
    cat > "${_TMPDIR}/profiles/depr.env" <<EOF
PROFILE_NAME="depr"
CONTAINER_NAME="depr-ctr"
IMAGE_NAME="depr-image"
IMAGE_DIR="${_TMPDIR}/image"
WORKSPACE="${_TMPDIR}/workspace"
CONTAINER_HOME="/home/builder"
BASHRC="${_TMPDIR}/workspace/.bashrc"
WORKDIR="/workspace"
BUILD_ARGS=""
EOF
    local helper="${_TMPDIR}/check_depr.sh"
    cat > "$helper" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/profile.sh'
export CODEX_JAILS_DIR='${_TMPDIR}'
resolve_base_dir
load_profile depr
SCRIPT
    local err rc=0
    err="$(bash "$helper" 2>&1 >/dev/null)" || rc=$?
    assert_success $rc "legacy load should still succeed" || _fail=1
    # Exactly one [INFO] deprecation line mentioning the canonical path
    local _info_count
    _info_count="$(echo "$err" | grep -c '^\[INFO\]' || true)"
    [[ "$_info_count" -ge 1 ]] || {
        printf '    Expected at least one [INFO] deprecation line, got %d\n' "$_info_count" >&2
        _fail=1
    }
    assert_contains "projects/depr/profile.env" "$err" "deprecation line should name canonical path" || _fail=1

    # Negative: project-local load must NOT emit a deprecation line
    mkdir -p "${_TMPDIR}/projects/nodepr"
    cat > "${_TMPDIR}/projects/nodepr/profile.env" <<EOF
PROFILE_NAME="nodepr"
CONTAINER_NAME="nodepr-ctr"
IMAGE_NAME="nodepr-image"
IMAGE_DIR="${_TMPDIR}/image"
WORKSPACE="${_TMPDIR}/workspace"
CONTAINER_HOME="/home/builder"
BASHRC="${_TMPDIR}/workspace/.bashrc"
WORKDIR="/workspace"
BUILD_ARGS=""
EOF
    local helper2="${_TMPDIR}/check_nodepr.sh"
    cat > "$helper2" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/profile.sh'
export CODEX_JAILS_DIR='${_TMPDIR}'
resolve_base_dir
load_profile nodepr
SCRIPT
    local err2
    err2="$(bash "$helper2" 2>&1 >/dev/null)"
    local _info2
    _info2="$(echo "$err2" | grep -c '^\[INFO\]' || true)"
    [[ "$_info2" -eq 0 ]] || {
        printf '    project-local load should emit no [INFO] lines, got %d\n' "$_info2" >&2
        _fail=1
    }
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "valid profile loads without error"            test_valid_profile_loads
run_test "missing required field → non-zero + field named" test_missing_required_field_exits_nonzero
run_test "nonexistent profile → non-zero + path named"  test_nonexistent_profile_exits_nonzero
run_test "optional arrays usable under set -u"          test_optional_arrays_defined_under_set_u
run_test "project-local loads, no mirror created (AC6)" test_project_local_loads_without_mirror
run_test "project-local preferred over legacy (R1.1)"   test_project_local_preferred_over_legacy
run_test "legacy fallback loads when no project tree (AC5)" test_legacy_fallback_loads
run_test "name/slug divergence resolves via raw name (Q1)" test_name_slug_divergence_resolves
run_test "missing profile names both candidate paths"   test_missing_profile_names_both_paths
run_test "no writeback after project-local load (AC6)"  test_no_writeback_on_project_local_load
run_test "legacy load emits deprecation [INFO] (R3.2)"  test_legacy_load_emits_deprecation_info

print_summary "10_profile"
