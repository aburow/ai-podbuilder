#!/usr/bin/env bash
# T3b — bootstrap image carries home-based NPM_CONFIG_PREFIX, PIPX_*, and PATH (AC3, B2).
# Tagged slow: skipped unless PODMAN_LIVE=1 and rootless podman is available.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

_BOOTSTRAP_IMAGE="localhost/ai-new/bootstrap:latest"

# ── Helpers ───────────────────────────────────────────────────────────────────

_image_env_value() {
    local _key="$1"
    podman image inspect "$_BOOTSTRAP_IMAGE" \
        --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null \
        | grep "^${_key}=" | head -1 | cut -d= -f2-
}

_ensure_image_or_skip() {
    if ! podman image exists "$_BOOTSTRAP_IMAGE" 2>/dev/null; then
        _SKIP_REASON="bootstrap image not present — build with 'ai-new <name>' or run ensure_bootstrap_image"
        return 0
    fi
    return 1
}

# ── Tests ─────────────────────────────────────────────────────────────────────

test_image_has_npm_config_prefix() {
    if skip_unless_live; then return 0; fi
    if _ensure_image_or_skip; then return 0; fi

    local _fail=0
    local _val
    _val="$(_image_env_value NPM_CONFIG_PREFIX)"
    assert_contains "/project/bootstrap/home" "$_val" \
        "NPM_CONFIG_PREFIX must be under /project/bootstrap/home" || _fail=1
    [[ -n "$_val" ]] || {
        printf '    NPM_CONFIG_PREFIX not set in bootstrap image ENV\n' >&2
        _fail=1
    }
    return $_fail
}

test_image_has_pipx_home() {
    if skip_unless_live; then return 0; fi
    if _ensure_image_or_skip; then return 0; fi

    local _fail=0
    local _val
    _val="$(_image_env_value PIPX_HOME)"
    assert_contains "/project/bootstrap/home" "$_val" \
        "PIPX_HOME must be under /project/bootstrap/home" || _fail=1
    [[ -n "$_val" ]] || {
        printf '    PIPX_HOME not set in bootstrap image ENV\n' >&2
        _fail=1
    }
    return $_fail
}

test_image_has_pipx_bin_dir() {
    if skip_unless_live; then return 0; fi
    if _ensure_image_or_skip; then return 0; fi

    local _fail=0
    local _val
    _val="$(_image_env_value PIPX_BIN_DIR)"
    assert_contains "/project/bootstrap/home" "$_val" \
        "PIPX_BIN_DIR must be under /project/bootstrap/home" || _fail=1
    [[ -n "$_val" ]] || {
        printf '    PIPX_BIN_DIR not set in bootstrap image ENV\n' >&2
        _fail=1
    }
    return $_fail
}

test_image_path_includes_npm_global_bin() {
    if skip_unless_live; then return 0; fi
    if _ensure_image_or_skip; then return 0; fi

    local _fail=0
    local _path
    _path="$(_image_env_value PATH)"
    assert_contains ".npm-global/bin" "$_path" \
        "image PATH must include the npm-global bin dir" || _fail=1
    return $_fail
}

test_image_path_includes_local_bin() {
    if skip_unless_live; then return 0; fi
    if _ensure_image_or_skip; then return 0; fi

    local _fail=0
    local _path
    _path="$(_image_env_value PATH)"
    assert_contains ".local/bin" "$_path" \
        "image PATH must include the local bin dir (for pipx)" || _fail=1
    return $_fail
}

test_containerfile_uses_image_level_install_paths() {
    # Baked agent binaries must not live under /project, which is replaced by
    # the project bind mount when the container starts.
    local _fail=0
    cat > "${_TMPDIR}/cf_check.sh" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/bootstrap_image.sh'
export AI_PODMAN_JAILS_DIR='${_TMPDIR}'
_write_bootstrap_containerfile '${_TMPDIR}/Containerfile.bootstrap'
SCRIPT
    bash "${_TMPDIR}/cf_check.sh" 2>/dev/null
    local _cf="${_TMPDIR}/Containerfile.bootstrap"
    [[ -f "$_cf" ]] || { printf '    Containerfile not generated\n' >&2; return 1; }
    local _content
    _content="$(cat "$_cf")"
    assert_not_contains "NPM_CONFIG_PREFIX=/project" "$_content" \
        "npm packages must not be baked beneath the project mount" || _fail=1
    assert_not_contains "PIPX_HOME=/project" "$_content" \
        "pipx packages must not be baked beneath the project mount" || _fail=1
    assert_contains "ENV HOME=/project/bootstrap/home" "$_content" \
        "runtime HOME must remain the persisted project home" || _fail=1
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "Containerfile keeps baked installs outside project mount"  test_containerfile_uses_image_level_install_paths
run_test "[slow] image ENV has NPM_CONFIG_PREFIX under home"         test_image_has_npm_config_prefix
run_test "[slow] image ENV has PIPX_HOME under home"                 test_image_has_pipx_home
run_test "[slow] image ENV has PIPX_BIN_DIR under home"              test_image_has_pipx_bin_dir
run_test "[slow] image PATH includes .npm-global/bin"                test_image_path_includes_npm_global_bin
run_test "[slow] image PATH includes .local/bin"                     test_image_path_includes_local_bin

print_summary "test_bootstrap_image_prefixes"
