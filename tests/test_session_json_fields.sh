#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# 2026 - Anthony Burow - https://github.com/aburow
# T10 — session.json carries all R11.3 fields with valid status (AC9).
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

# ── Helpers ───────────────────────────────────────────────────────────────────

_session_helper() {
    local _script="$1"
    cat > "${_TMPDIR}/session_helper.sh" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/session.sh'
export AI_PODMAN_JAILS_DIR='${_TMPDIR}'
${_script}
SCRIPT
    bash "${_TMPDIR}/session_helper.sh" 2>&1
}

_make_proj_with_session() {
    local _name="$1"
    local _root="${_TMPDIR}/projects/${_name}"
    mkdir -p "${_root}/bootstrap"
    # init_session needs registry.sh pinned file.
    mkdir -p "${_TMPDIR}/config/agents.d"
    cat > "${_TMPDIR}/config/agents.d/codex.env" <<'AEOF'
AGENT_REGISTRY_VERSION="1"
AGENT_NAME="codex"
AGENT_COMMAND="codex"
AGENT_INSTALL_ADAPTER="npm-global"
AGENT_AUTH_CHECK_ARGV="codex|--version"
AEOF
    # Create a dummy agent.env (pinned).
    cat > "${_root}/bootstrap/agent.env" <<'AEOF'
# source_hash=abc123def456
AGENT_NAME="codex"
AEOF

    cat > "${_TMPDIR}/init_session_helper.sh" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/session.sh'
export AI_PODMAN_JAILS_DIR='${_TMPDIR}'
init_session '${_root}' '${_name}' 'codex'
SCRIPT
    bash "${_TMPDIR}/init_session_helper.sh" >/dev/null 2>&1 || true
    echo "$_root"
}

# ── Tests ─────────────────────────────────────────────────────────────────────

test_session_json_has_required_r11_fields() {
    local _fail=0
    local _proj
    _proj="$(_make_proj_with_session "sjf1")"
    local _json="${_proj}/bootstrap/session.json"
    [[ -f "$_json" ]] || { printf '    session.json missing\n' >&2; return 1; }

    local _content
    _content="$(cat "$_json")"
    local _field
    for _field in \
        project_name selected_agent status last_updated generated_files \
        containerfile_path quality_gate_status last_error resume_command \
        build_log_path trial_image_tag static_check_status \
        final_runtime enabled_optional_features rejected_optional_features \
        durable_reconciliation_status durable_spec_path \
        pinned_agent_env pinned_agent_hash
    do
        assert_contains "\"${_field}\"" "$_content" "session.json should have field: ${_field}" || _fail=1
    done
    return $_fail
}

test_session_json_initial_status_is_started() {
    local _fail=0
    local _proj
    _proj="$(_make_proj_with_session "sjf2")"

    local out rc=0
    out="$(_session_helper "read_status '${_proj}'")" || rc=$?
    assert_success $rc || _fail=1
    assert_eq "started" "$out" "initial status should be 'started'" || _fail=1
    return $_fail
}

test_set_status_valid_values() {
    local _fail=0
    local _proj
    _proj="$(_make_proj_with_session "sjf3")"

    local _status
    for _status in started interviewing generated quality-gate-running \
        quality-gate-failed quality-gate-timeout quality-gate-inconsistent \
        generated-unvalidated interrupted complete; do

        local out rc=0
        out="$(_session_helper "
            set_status '${_proj}' '${_status}'
            read_status '${_proj}'
        ")" || rc=$?
        assert_success $rc "set_status '${_status}' should succeed" || _fail=1
        assert_eq "${_status}" "$out" "read_status should return ${_status}" || _fail=1
    done
    return $_fail
}

test_set_status_invalid_value_fails() {
    local _fail=0
    local _proj
    _proj="$(_make_proj_with_session "sjf4")"

    local out rc=0
    out="$(_session_helper "set_status '${_proj}' 'not-a-real-status'")" || rc=$?
    assert_failure $rc "invalid status should fail" || _fail=1
    assert_contains "Invalid session status" "$out" || _fail=1
    return $_fail
}

test_write_session_field_updates_atomically() {
    local _fail=0
    local _proj
    _proj="$(_make_proj_with_session "sjf5")"

    local out rc=0
    out="$(_session_helper "
        write_session_field '${_proj}' 'last_error' 'something went wrong'
        grep -oP '\"last_error\"\s*:\s*\"\K[^\"]+' '${_proj}/bootstrap/session.json'
    ")" || rc=$?
    assert_success $rc || _fail=1
    assert_eq "something went wrong" "$out" "write_session_field should update the field" || _fail=1

    # No .tmp file should remain.
    [[ ! -f "${_proj}/bootstrap/session.json.tmp" ]] || {
        printf '    .tmp file left behind after write_session_field\n' >&2
        _fail=1
    }
    return $_fail
}

test_pinned_agent_hash_in_session() {
    local _fail=0
    local _proj
    _proj="$(_make_proj_with_session "sjf6")"
    local _json="${_proj}/bootstrap/session.json"
    [[ -f "$_json" ]] || { printf '    session.json missing\n' >&2; return 1; }

    # pinned_agent_hash should be present (even if empty in the test).
    local _content
    _content="$(cat "$_json")"
    assert_contains "pinned_agent_hash" "$_content" "session.json should have pinned_agent_hash" || _fail=1
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "session.json has all R11.3 required fields"           test_session_json_has_required_r11_fields
run_test "initial status is 'started'"                          test_session_json_initial_status_is_started
run_test "set_status accepts all valid vocabulary values"        test_set_status_valid_values
run_test "set_status rejects invalid status value"              test_set_status_invalid_value_fails
run_test "write_session_field updates atomically (no .tmp)"     test_write_session_field_updates_atomically
run_test "session.json includes pinned_agent_hash field"        test_pinned_agent_hash_in_session

print_summary "test_session_json_fields"
