#!/usr/bin/env bash
# T2b — ai-build: missing profile / missing IMAGE_DIR exit non-zero; no container created.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

# ── Tests ─────────────────────────────────────────────────────────────────────

test_missing_profile_exits_nonzero() {
    local _fail=0
    local out rc=0
    out="$(CODEX_JAILS_DIR="$_TMPDIR" PATH="${STUBS_DIR}:${PATH}" \
        "${BIN_DIR}/ai-build" no_such_profile 2>&1)" || rc=$?
    assert_failure $rc "missing profile → non-zero" || _fail=1
    assert_contains "no_such_profile" "$out" "error names the profile" || _fail=1
    return $_fail
}

test_missing_image_dir_exits_nonzero() {
    # esp32 profile sets IMAGE_DIR to a path that doesn't exist in the temp dir
    local _fail=0
    local out rc=0
    out="$(CODEX_JAILS_DIR="$_TMPDIR" PATH="${STUBS_DIR}:${PATH}" \
        "${BIN_DIR}/ai-build" esp32 2>&1)" || rc=$?
    assert_failure $rc "missing IMAGE_DIR → non-zero" || _fail=1
    assert_contains "IMAGE_DIR" "$out" "error mentions IMAGE_DIR" || _fail=1
    return $_fail
}

test_ai_build_creates_no_container_or_state_file() {
    # Even a failed ai-build must leave no container and no state/ dir.
    local _fail=0
    CODEX_JAILS_DIR="$_TMPDIR" PATH="${STUBS_DIR}:${PATH}" \
        "${BIN_DIR}/ai-build" esp32 2>/dev/null || true
    [[ ! -d "${_TMPDIR}/state" ]] \
        || { echo "    state/ directory was created" >&2; _fail=1; }
    return $_fail
}

test_ai_build_tier_b_esp32() {
    skip_unless_live && return 0
    local _fail=0
    mkdir -p "${_TMPDIR}/esp32-image"
    # Minimal Containerfile for a fast test build
    cat > "${_TMPDIR}/esp32-image/Containerfile" <<'EOF'
FROM busybox:latest
RUN echo "esp32 stub" > /etc/esp32-stub
EOF
    # Override image name to avoid conflicts
    sed -i 's/^IMAGE_NAME=.*/IMAGE_NAME="test-esp32-image-ci"/' "${_TMPDIR}/profiles/esp32.env"
    sed -i 's/^BUILD_ARGS=.*/BUILD_ARGS=""/' "${_TMPDIR}/profiles/esp32.env"
    sed -i '/^POST_BUILD_CHECK=/d' "${_TMPDIR}/profiles/esp32.env"

    local out rc=0
    out="$(CODEX_JAILS_DIR="$_TMPDIR" "${BIN_DIR}/ai-build" esp32 2>&1)" || rc=$?
    assert_success $rc "ai-build esp32 should succeed" || _fail=1
    assert_contains "Build complete" "$out" || _fail=1

    # Cleanup image
    podman rmi test-esp32-image-ci 2>/dev/null || true
    return $_fail
}

test_ai_build_edit_opens_containerfile_in_editor() {
    local _fail=0
    local _editor="${_TMPDIR}/fake-editor.sh"
    local _log="${_TMPDIR}/editor.log"
    cat > "$_editor" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$1" > "${_log}"
exit 0
EOF
    chmod +x "$_editor"

    mkdir -p "${_TMPDIR}/esp32-image"
    local out rc=0
    out="$(EDITOR="$_editor" CODEX_JAILS_DIR="$_TMPDIR" "${BIN_DIR}/ai-build" esp32 --edit 2>&1)" || rc=$?
    assert_success $rc "ai-build --edit should succeed" || _fail=1
    assert_contains "Opening Containerfile" "$out" || _fail=1
    [[ -f "${_TMPDIR}/esp32-image/Containerfile" ]] || { echo "    Containerfile was not created" >&2; _fail=1; }
    local _edited_path
    _edited_path="$(cat "${_log}" 2>/dev/null || true)"
    assert_eq "${_TMPDIR}/esp32-image/Containerfile" "$_edited_path" "editor should open the Containerfile path" || _fail=1
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "ai-build: missing profile → non-zero"        test_missing_profile_exits_nonzero
run_test "ai-build: missing IMAGE_DIR → non-zero"      test_missing_image_dir_exits_nonzero
run_test "ai-build: no container or state/ created"    test_ai_build_creates_no_container_or_state_file
run_test "ai-build esp32 (Tier B — live build)"        test_ai_build_tier_b_esp32
run_test "ai-build --edit opens Containerfile"         test_ai_build_edit_opens_containerfile_in_editor

print_summary "11_ai-build"
