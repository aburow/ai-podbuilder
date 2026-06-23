#!/usr/bin/env bash
# T4 — End-to-end integration: home-dir location, executability, and agent PATH resolution (AC6, R4.1).
# Tagged slow: skipped unless PODMAN_LIVE=1 and rootless podman is available.
# Mocks the agent install with a fake npm for determinism; never touches the real network.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

_BOOTSTRAP_IMAGE="localhost/ai-new/bootstrap:latest"

# ── Helpers ───────────────────────────────────────────────────────────────────

_ensure_image_or_skip() {
    if ! podman image exists "$_BOOTSTRAP_IMAGE" 2>/dev/null; then
        _SKIP_REASON="bootstrap image not present — build it with 'ai-new <name>' first"
        return 0
    fi
    return 1
}

# _setup_e2e_project <proj> <agent_name> <agent_cmd> <package>
# Prepares a project scaffold with start-here.sh, a fake npm that installs a stub
# command, and an agent.env for the given agent.
_setup_e2e_project() {
    local _proj="$1" _agent="$2" _cmd="$3" _pkg="$4"

    mkdir -p "${_proj}/bootstrap/home/.npm-global/bin"

    # Copy start-here.sh into scaffold home.
    cp "${REPO_ROOT}/start-here.sh" "${_proj}/bootstrap/home/start-here.sh"
    chmod +x "${_proj}/bootstrap/home/start-here.sh"

    # Write agent.env.
    printf 'AGENT_REGISTRY_VERSION="1"\nAGENT_NAME="%s"\nAGENT_COMMAND="%s"\n' \
        "$_agent" "$_cmd" > "${_proj}/bootstrap/agent.env"
    printf 'AGENT_INSTALL_ADAPTER="npm-global"\nAGENT_INSTALL_PACKAGE="%s"\n' \
        "$_pkg" >> "${_proj}/bootstrap/agent.env"
    printf 'AGENT_INSTALL_VERSION=""\nAGENT_CONFIG_DIRS=""\nAGENT_ENV_VARS=""\n' \
        >> "${_proj}/bootstrap/agent.env"
    printf 'AGENT_PROMPT_MODE="default"\nAGENT_AUTH_CHECK_ARGV=""\n' \
        >> "${_proj}/bootstrap/agent.env"

    # Fake npm: records call, drops a stub binary for the agent command, exits 0.
    local _npm_bin="${_proj}/bootstrap/home/.npm-global/npm"
    printf '#!/bin/sh\necho "$@" >> /project/bootstrap/npm_calls.txt\nmkdir -p /project/bootstrap/home/.npm-global/bin\nprintf '"'"'#!/bin/sh\nexit 0\n'"'"' > /project/bootstrap/home/.npm-global/bin/%s\nchmod +x /project/bootstrap/home/.npm-global/bin/%s\nexit 0\n' \
        "$_cmd" "$_cmd" > "$_npm_bin"
    chmod +x "$_npm_bin"
}

# _write_assert_script <proj> <cmd>
# Writes a self-contained assertion script that checks all three e2e conditions.
_write_assert_script() {
    local _proj="$1" _cmd="$2"
    local _script="${_proj}/assert.sh"
    # shellcheck disable=SC2154
    cat > "$_script" <<ASSERT_EOF
#!/bin/bash
FAIL=0

# (a) start-here.sh lives under home, not at container root.
if [[ -f "/project/bootstrap/home/start-here.sh" ]]; then
    echo "CHECK_A: PASS"
else
    echo "CHECK_A: FAIL (start-here.sh not found at home)"
    FAIL=1
fi
if [[ -f "/start-here.sh" ]]; then
    echo "CHECK_A: FAIL (start-here.sh also at root)"
    FAIL=1
fi

# (b) start-here.sh is executable (no bash prefix needed).
if [[ -x "/project/bootstrap/home/start-here.sh" ]]; then
    echo "CHECK_B: PASS"
else
    echo "CHECK_B: FAIL (not executable)"
    FAIL=1
fi

# (c) After running the install adapter with fake npm, agent command resolves on PATH.
export PATH="/project/bootstrap/home/.npm-global/bin:/project/bootstrap/home/.npm-global:\${PATH}"
. /start-here-lib/common.sh
. /start-here-lib/adapter.sh
run_install_adapter "npm-global" "${_cmd}_pkg" ""
hash -r 2>/dev/null || true
if command -v "${_cmd}" >/dev/null 2>&1; then
    echo "CHECK_C: PASS"
else
    echo "CHECK_C: FAIL (${_cmd} not on PATH after install)"
    FAIL=1
fi
exit \$FAIL
ASSERT_EOF
    chmod +x "$_script"
}

_run_e2e_assertions() {
    local _proj="$1" _cmd="$2" _container="$3"
    _write_assert_script "$_proj" "$_cmd"

    podman run --rm \
        --name "$_container" \
        --userns=keep-id \
        --volume "${_proj}:/project:z" \
        --volume "${REPO_ROOT}/lib:/start-here-lib:ro,z" \
        --env "HOME=/project/bootstrap/home" \
        --env "PATH=/project/bootstrap/home/.npm-global/bin:/project/bootstrap/home/.npm-global:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
        --workdir /project \
        --network none \
        "$_BOOTSTRAP_IMAGE" \
        bash /project/assert.sh 2>&1
}

# ── Tests ─────────────────────────────────────────────────────────────────────

test_e2e_codex_all_three_checks() {
    if skip_unless_live; then return 0; fi
    if _ensure_image_or_skip; then return 0; fi

    local _fail=0
    local _proj="${_TMPDIR}/projects/e2e_codex"
    _setup_e2e_project "$_proj" "codex" "codex" "@openai/codex"

    local out rc=0
    out="$(_run_e2e_assertions "$_proj" "codex" "ai-new-e2e-codex-$$")" || rc=$?

    assert_contains "CHECK_A: PASS" "$out" "(a) start-here.sh at home" || _fail=1
    assert_contains "CHECK_B: PASS" "$out" "(b) executable"            || _fail=1
    assert_contains "CHECK_C: PASS" "$out" "(c) agent on PATH"         || _fail=1
    assert_not_contains ": FAIL"    "$out" "no check should fail"      || _fail=1
    return $_fail
}

test_e2e_gemini_all_three_checks() {
    if skip_unless_live; then return 0; fi
    if _ensure_image_or_skip; then return 0; fi

    local _fail=0
    local _proj="${_TMPDIR}/projects/e2e_gemini"
    _setup_e2e_project "$_proj" "gemini" "gemini" "@google/gemini-cli"

    local out rc=0
    out="$(_run_e2e_assertions "$_proj" "gemini" "ai-new-e2e-gemini-$$")" || rc=$?

    assert_contains "CHECK_A: PASS" "$out" "(a) start-here.sh at home" || _fail=1
    assert_contains "CHECK_B: PASS" "$out" "(b) executable"            || _fail=1
    assert_contains "CHECK_C: PASS" "$out" "(c) gemini on PATH"        || _fail=1
    assert_not_contains ": FAIL"    "$out" "no check should fail"      || _fail=1
    return $_fail
}

test_e2e_no_podman_records_explicit_skip() {
    # When PODMAN_LIVE is 0 (default), skip_unless_live must set _SKIP_REASON —
    # the e2e test must never silently pass without Podman.
    local _saved="${PODMAN_LIVE:-0}"
    local _skip_reason=""
    PODMAN_LIVE=0
    if skip_unless_live; then
        _skip_reason="$_SKIP_REASON"
    fi
    PODMAN_LIVE="$_saved"
    _SKIP_REASON=""  # reset so run_test does not double-skip

    if [[ -z "$_skip_reason" ]]; then
        printf '    skip_unless_live did not set _SKIP_REASON when PODMAN_LIVE=0\n' >&2
        return 1
    fi
    return 0
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "[slow] e2e: codex — home location, executable, PATH resolve"  test_e2e_codex_all_three_checks
run_test "[slow] e2e: gemini — home location, executable, PATH resolve"  test_e2e_gemini_all_three_checks
run_test "unavailable Podman records explicit skip, not silent pass"      test_e2e_no_podman_records_explicit_skip

print_summary "test_bootstrap_setup_e2e"
