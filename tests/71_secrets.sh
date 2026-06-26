#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# 2026 - Anthony Burow - https://github.com/aburow
# T8b — ENV_FILE / secrets handling (AC13).
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

_make_secret_profile() {
    local env_file="${1:-}"
    local prof="${_TMPDIR}/profiles/secret.env"
    cat > "$prof" <<EOF
PROFILE_NAME="secret"
CONTAINER_NAME="test-secret-$$"
IMAGE_NAME="test-secret-img"
IMAGE_DIR="${_TMPDIR}/secret-image"
WORKSPACE="${_TMPDIR}/secret-ws"
CONTAINER_HOME="${_TMPDIR}/secret-home"
BASHRC="${_TMPDIR}/.bashrc"
WORKDIR="/workspace"
BUILD_ARGS=""
EOF
    if [[ -n "$env_file" ]]; then
        printf 'ENV_FILE="%s"\n' "$env_file" >> "$prof"
    fi
}

test_env_file_present_adds_env_file_arg() {
    # ENV_FILE set and file exists → --env-file in assembled args
    local _fail=0
    local secret_file="${_TMPDIR}/secret.env"
    printf 'MY_SECRET=hello\n' > "$secret_file"
    chmod 600 "$secret_file"
    _make_secret_profile "$secret_file"

    local out rc=0
    out="$(DRY_RUN=1 AI_PODMAN_JAILS_DIR="$_TMPDIR" PATH="${STUBS_DIR}:${PATH}" \
        "${BIN_DIR}/ai-launch" secret shell 2>/dev/null)" || rc=$?
    assert_success $rc "launch with present ENV_FILE should succeed" || _fail=1
    assert_contains "--env-file" "$out" "--env-file added when ENV_FILE present" || _fail=1
    return $_fail
}

test_env_file_missing_warns_and_continues() {
    # ENV_FILE set but file does not exist → warning emitted, launch proceeds
    local _fail=0
    local missing="${_TMPDIR}/does-not-exist.env"
    _make_secret_profile "$missing"

    local out rc=0
    out="$(DRY_RUN=1 AI_PODMAN_JAILS_DIR="$_TMPDIR" PATH="${STUBS_DIR}:${PATH}" \
        "${BIN_DIR}/ai-launch" secret shell 2>&1)" || rc=$?
    assert_success $rc "launch with missing ENV_FILE should still succeed" || _fail=1
    assert_contains "WARN" "$out" "warning emitted when ENV_FILE missing" || _fail=1
    assert_not_contains "--env-file" "$out" "no --env-file when file missing" || _fail=1
    return $_fail
}

test_env_file_undefined_no_secret_mount() {
    # ENV_FILE not set → no --env-file in args
    local _fail=0
    _make_secret_profile   # no ENV_FILE arg

    local out
    out="$(DRY_RUN=1 AI_PODMAN_JAILS_DIR="$_TMPDIR" PATH="${STUBS_DIR}:${PATH}" \
        "${BIN_DIR}/ai-launch" secret shell 2>/dev/null)"
    assert_not_contains "--env-file" "$out" "no --env-file when ENV_FILE unset" || _fail=1
    return $_fail
}

test_env_file_vars_visible_in_container_live() {
    skip_unless_live && return 0
    local _fail=0

    local img="test-secret-img-$$"
    mkdir -p "${_TMPDIR}/secret-image"
    cat > "${_TMPDIR}/secret-image/Containerfile" <<'EOF'
FROM busybox:latest
EOF
    podman build -q -t "$img" "${_TMPDIR}/secret-image" >/dev/null 2>&1

    local secret_file="${_TMPDIR}/live_secret.env"
    printf 'MY_SECRET_VAR=supervalue\n' > "$secret_file"
    chmod 600 "$secret_file"

    local out
    out="$(podman run --rm --env-file "$secret_file" "$img" \
        sh -c 'echo "val=$MY_SECRET_VAR"' 2>/dev/null)"
    assert_contains "val=supervalue" "$out" "secret var visible in container" || _fail=1

    podman rmi "$img" 2>/dev/null || true
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "ENV_FILE present → --env-file in args"                 test_env_file_present_adds_env_file_arg
run_test "ENV_FILE missing → warn and continue (no --env-file)"  test_env_file_missing_warns_and_continues
run_test "ENV_FILE undefined → no --env-file in args"            test_env_file_undefined_no_secret_mount
run_test "secret vars visible inside container (Tier B)"          test_env_file_vars_visible_in_container_live

print_summary "71_secrets"
