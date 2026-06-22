#!/usr/bin/env bash
# T2 — list_registered_agents enumerates config/agents.d/ (AC2).
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

# ── Helpers ───────────────────────────────────────────────────────────────────

_list_helper() {
    local _agents_dir="$1"
    cat > "${_TMPDIR}/list_helper.sh" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/registry.sh'
export CODEX_JAILS_DIR='${_TMPDIR}'
export CODEX_AGENTS_DIR='${_agents_dir}'
list_registered_agents
SCRIPT
    bash "${_TMPDIR}/list_helper.sh" 2>&1
}

_setup_temp_agents() {
    local _dir="${_TMPDIR}/config/agents.d"
    mkdir -p "$_dir"
    for _name in codex codex gemini; do
        cat > "${_dir}/${_name}.env" <<AEOF
AGENT_REGISTRY_VERSION="1"
AGENT_NAME="${_name}"
AGENT_COMMAND="${_name}"
AGENT_INSTALL_ADAPTER="preinstalled"
AEOF
    done
    echo "$_dir"
}

# ── Tests ─────────────────────────────────────────────────────────────────────

test_default_agents_present() {
    local _fail=0
    local _dir
    _dir="$(_setup_temp_agents)"
    local out rc=0
    out="$(_list_helper "$_dir")" || rc=$?
    assert_success $rc "list_registered_agents should succeed" || _fail=1
    assert_contains "codex" "$out" "codex should be listed" || _fail=1
    assert_contains "codex"  "$out" "codex should be listed" || _fail=1
    assert_contains "gemini" "$out" "gemini should be listed" || _fail=1
    return $_fail
}

test_real_agents_dir_has_default_set() {
    local _fail=0
    # Also verify the repo's own agents.d has codex, codex, gemini.
    local _real_dir="${REPO_ROOT}/config/agents.d"
    if [[ ! -d "$_real_dir" ]]; then
        _SKIP_REASON="config/agents.d not found in repo"
        return 0
    fi
    local out rc=0
    out="$(_list_helper "$_real_dir")" || rc=$?
    assert_success $rc || _fail=1
    assert_contains "codex" "$out" || _fail=1
    assert_contains "codex"  "$out" || _fail=1
    assert_contains "gemini" "$out" || _fail=1
    return $_fail
}

test_empty_agents_dir_returns_nothing() {
    local _fail=0
    local _dir="${_TMPDIR}/empty_agents"
    mkdir -p "$_dir"
    local out rc=0
    out="$(_list_helper "$_dir")" || rc=$?
    assert_success $rc "empty agents dir should succeed (return empty)" || _fail=1
    [[ -z "$out" ]] || {
        printf '    Expected empty output, got: %s\n' "$out" >&2
        _fail=1
    }
    return $_fail
}

test_non_env_files_not_listed() {
    local _fail=0
    local _dir="${_TMPDIR}/mixed_agents"
    mkdir -p "$_dir"
    printf 'AGENT_NAME="myagent"\nAGENT_COMMAND="myagent"\nAGENT_INSTALL_ADAPTER="preinstalled"\n' \
        > "${_dir}/myagent.env"
    # These should NOT be listed.
    touch "${_dir}/README.md" "${_dir}/myagent.txt" "${_dir}/.hidden"
    local out rc=0
    out="$(_list_helper "$_dir")" || rc=$?
    assert_success $rc || _fail=1
    assert_contains "myagent" "$out" "myagent.env should be listed" || _fail=1
    assert_not_contains "README"  "$out" "README.md should not be listed" || _fail=1
    assert_not_contains ".hidden" "$out" ".hidden should not be listed" || _fail=1
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "codex, codex, gemini all appear in temp agents.d" test_default_agents_present
run_test "repo agents.d exposes codex, codex, gemini"        test_real_agents_dir_has_default_set
run_test "empty agents.d returns empty list"                  test_empty_agents_dir_returns_nothing
run_test "non-.env files are not listed"                      test_non_env_files_not_listed

print_summary "test_list_agents"
