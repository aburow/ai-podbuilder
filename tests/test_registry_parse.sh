#!/usr/bin/env bash
# T2 — Registry parsing: known keys, unknown keys ignored, multi-value decode (AC20).
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

# ── Helpers ───────────────────────────────────────────────────────────────────

_write_minimal_registry() {
    local _path="$1"
    cat > "$_path" <<'EOF'
AGENT_REGISTRY_VERSION="1"
AGENT_NAME="testbot"
AGENT_COMMAND="testbot-cli"
AGENT_INSTALL_ADAPTER="npm-global"
AGENT_INSTALL_PACKAGE="@test/testbot"
AGENT_CONFIG_DIRS=".testbot:.config/testbot"
AGENT_ENV_VARS="TESTBOT_API_KEY:TESTBOT_ORG"
AGENT_PROMPT_MODE="default"
AGENT_AUTH_CHECK_ARGV="testbot|--version"
EOF
}

_parse_helper() {
    local _path="$1"
    shift
    local _script="$1"
    cat > "${_TMPDIR}/parse_helper.sh" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/registry.sh'
export CODEX_JAILS_DIR='${_TMPDIR}'
parse_registry_file '${_path}'
${_script}
SCRIPT
    bash "${_TMPDIR}/parse_helper.sh" 2>&1
}

# ── Tests ─────────────────────────────────────────────────────────────────────

test_known_keys_parse_correctly() {
    local _fail=0
    local _reg="${_TMPDIR}/testbot.env"
    _write_minimal_registry "$_reg"
    local out rc=0
    out="$(_parse_helper "$_reg" 'printf "NAME=%s\nCOMMAND=%s\nADAPTER=%s\nVERSION=%s\n" \
        "$REG_AGENT_NAME" "$REG_AGENT_COMMAND" "$REG_AGENT_INSTALL_ADAPTER" "$REG_AGENT_REGISTRY_VERSION"')" || rc=$?
    assert_success $rc "parse_registry_file should succeed" || _fail=1
    assert_contains "NAME=testbot"     "$out" || _fail=1
    assert_contains "COMMAND=testbot-cli" "$out" || _fail=1
    assert_contains "ADAPTER=npm-global"  "$out" || _fail=1
    assert_contains "VERSION=1"        "$out" || _fail=1
    return $_fail
}

test_unknown_keys_are_ignored() {
    local _fail=0
    local _reg="${_TMPDIR}/extras.env"
    cat > "$_reg" <<'EOF'
AGENT_NAME="testbot"
AGENT_COMMAND="testbot-cli"
AGENT_INSTALL_ADAPTER="preinstalled"
TOTALLY_UNKNOWN_KEY="should-be-ignored"
ANOTHER_BOGUS_KEY="also-ignored"
EOF
    local out rc=0
    out="$(_parse_helper "$_reg" 'printf "NAME=%s\n" "$REG_AGENT_NAME"
        # REG_TOTALLY_UNKNOWN_KEY should not exist; checking REG_AGENT_NAME is sufficient.
        echo "done"')" || rc=$?
    assert_success $rc "parse should succeed despite unknown keys" || _fail=1
    assert_contains "NAME=testbot" "$out" || _fail=1
    assert_contains "done" "$out" || _fail=1
    return $_fail
}

test_multi_value_config_dirs_decode() {
    local _fail=0
    local _reg="${_TMPDIR}/multivalue.env"
    _write_minimal_registry "$_reg"
    local out rc=0
    out="$(_parse_helper "$_reg" '
        split_multi "$REG_AGENT_CONFIG_DIRS"
        printf "COUNT=%d\n" "${#_SPLIT_RESULT[@]}"
        printf "ELEM0=%s\n" "${_SPLIT_RESULT[0]}"
        printf "ELEM1=%s\n" "${_SPLIT_RESULT[1]}"
    ')" || rc=$?
    assert_success $rc "split_multi on config dirs" || _fail=1
    assert_contains "COUNT=2"           "$out" "should split into 2 elements" || _fail=1
    assert_contains "ELEM0=.testbot"    "$out" || _fail=1
    assert_contains "ELEM1=.config/testbot" "$out" || _fail=1
    return $_fail
}

test_multi_value_env_vars_decode() {
    local _fail=0
    local _reg="${_TMPDIR}/envvars.env"
    _write_minimal_registry "$_reg"
    local out rc=0
    out="$(_parse_helper "$_reg" '
        split_multi "$REG_AGENT_ENV_VARS"
        printf "COUNT=%d\n" "${#_SPLIT_RESULT[@]}"
        printf "ELEM0=%s\n" "${_SPLIT_RESULT[0]}"
        printf "ELEM1=%s\n" "${_SPLIT_RESULT[1]}"
    ')" || rc=$?
    assert_success $rc "split_multi on env vars" || _fail=1
    assert_contains "COUNT=2" "$out" "should split env vars into 2" || _fail=1
    assert_contains "ELEM0=TESTBOT_API_KEY" "$out" || _fail=1
    assert_contains "ELEM1=TESTBOT_ORG" "$out" || _fail=1
    return $_fail
}

test_comments_and_blank_lines_are_stripped() {
    local _fail=0
    local _reg="${_TMPDIR}/comments.env"
    cat > "$_reg" <<'EOF'
# This is a comment
AGENT_NAME="myagent"

# Another comment
AGENT_COMMAND="myagent-cli"
AGENT_INSTALL_ADAPTER="preinstalled"
EOF
    local out rc=0
    out="$(_parse_helper "$_reg" 'printf "NAME=%s\nCMD=%s\n" "$REG_AGENT_NAME" "$REG_AGENT_COMMAND"')" || rc=$?
    assert_success $rc "parse with comments should succeed" || _fail=1
    assert_contains "NAME=myagent" "$out" || _fail=1
    assert_contains "CMD=myagent-cli" "$out" || _fail=1
    return $_fail
}

test_quoted_values_unquoted() {
    local _fail=0
    local _reg="${_TMPDIR}/quoted.env"
    cat > "$_reg" <<'EOF'
AGENT_NAME='single-quoted'
AGENT_COMMAND="double-quoted"
AGENT_INSTALL_ADAPTER="preinstalled"
EOF
    local out rc=0
    out="$(_parse_helper "$_reg" 'printf "NAME=%s\nCMD=%s\n" "$REG_AGENT_NAME" "$REG_AGENT_COMMAND"')" || rc=$?
    assert_success $rc || _fail=1
    assert_contains "NAME=single-quoted" "$out" "single quotes should be stripped" || _fail=1
    assert_contains "CMD=double-quoted"  "$out" "double quotes should be stripped" || _fail=1
    return $_fail
}

test_missing_file_exits_nonzero() {
    local _fail=0
    local out rc=0
    out="$(_parse_helper "${_TMPDIR}/nonexistent.env" 'echo noop')" || rc=$?
    assert_failure $rc "parsing missing file should fail" || _fail=1
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "known registry keys parse correctly"        test_known_keys_parse_correctly
run_test "unknown registry keys are silently ignored" test_unknown_keys_are_ignored
run_test "AGENT_CONFIG_DIRS decodes colon-separated"  test_multi_value_config_dirs_decode
run_test "AGENT_ENV_VARS decodes colon-separated"     test_multi_value_env_vars_decode
run_test "comments and blank lines stripped"          test_comments_and_blank_lines_are_stripped
run_test "quoted values are unquoted"                 test_quoted_values_unquoted
run_test "missing registry file exits non-zero"       test_missing_file_exits_nonzero

print_summary "test_registry_parse"
