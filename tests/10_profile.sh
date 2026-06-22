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

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "valid profile loads without error"            test_valid_profile_loads
run_test "missing required field → non-zero + field named" test_missing_required_field_exits_nonzero
run_test "nonexistent profile → non-zero + path named"  test_nonexistent_profile_exits_nonzero
run_test "optional arrays usable under set -u"          test_optional_arrays_defined_under_set_u

print_summary "10_profile"
