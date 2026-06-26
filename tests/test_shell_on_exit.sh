#!/usr/bin/env bash
# --shell-on-exit must retain the container after an agent/launcher failure.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SELF_DIR}/helpers/setup.bash"

_patched_start_here() {
    local _bootstrap="$1"
    local _out="${_TMPDIR}/start-here-patched.sh"
    sed "s|BOOTSTRAP_DIR=\"/project/bootstrap\"|BOOTSTRAP_DIR=\"${_bootstrap}\"|" \
        "${REPO_ROOT}/lib/start-here.sh" > "$_out"
    chmod +x "$_out"
    echo "$_out"
}

test_failure_opens_bash_with_exit_status() {
    local _bootstrap="${_TMPDIR}/project/bootstrap"
    local _fakebin="${_TMPDIR}/fakebin"
    mkdir -p "$_bootstrap" "$_fakebin"
    cat > "${_bootstrap}/agent.env" <<'EOF'
AGENT_NAME="testbot"
AGENT_COMMAND="testbot"
AGENT_INSTALL_ADAPTER="preinstalled"
AGENT_AUTH_CHECK_ARGV=""
EOF
    cat > "${_fakebin}/testbot" <<'EOF'
#!/usr/bin/env bash
exit 37
EOF
    cat > "${_TMPDIR}/fallback-shell" <<'EOF'
#!/bin/sh
printf 'FALLBACK_STATUS=%s\n' "${AI_NEW_AGENT_EXIT_STATUS:-missing}"
exit 0
EOF
    chmod +x "${_fakebin}/testbot" "${_TMPDIR}/fallback-shell"

    local _script out rc=0
    _script="$(_patched_start_here "$_bootstrap")"
    out="$(AI_NEW_FALLBACK_SHELL="${_TMPDIR}/fallback-shell" PATH="${_fakebin}:${PATH}" \
        "$_script" --shell-on-exit 2>&1)" || rc=$?

    assert_success "$rc" "fallback Bash stub should control final exit" || return 1
    assert_contains "Bootstrap process exited with status 37" "$out" || return 1
    assert_contains "FALLBACK_STATUS=37" "$out"
}

test_without_option_preserves_agent_failure() {
    local _bootstrap="${_TMPDIR}/project2/bootstrap"
    local _fakebin="${_TMPDIR}/fakebin2"
    mkdir -p "$_bootstrap" "$_fakebin"
    cat > "${_bootstrap}/agent.env" <<'EOF'
AGENT_NAME="testbot"
AGENT_COMMAND="testbot"
AGENT_INSTALL_ADAPTER="preinstalled"
AGENT_AUTH_CHECK_ARGV=""
EOF
    printf '#!/usr/bin/env bash\nexit 29\n' > "${_fakebin}/testbot"
    chmod +x "${_fakebin}/testbot"

    local _script rc=0
    _script="$(_patched_start_here "$_bootstrap")"
    PATH="${_fakebin}:${PATH}" "$_script" >/dev/null 2>&1 || rc=$?
    assert_eq "29" "$rc" "without fallback, agent status must leave the container"
}

run_test "agent failure opens Bash and exports original status" test_failure_opens_bash_with_exit_status
run_test "without option, agent failure remains container exit" test_without_option_preserves_agent_failure

print_summary "test_shell_on_exit"
