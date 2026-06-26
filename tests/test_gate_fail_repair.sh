#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# 2026 - Anthony Burow - https://github.com/aburow
# T9 — Broken Containerfile fails gate; repair cap honoured (AC12, AI_NEW_MAX_REPAIR_ATTEMPTS).
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

# ── Helpers ───────────────────────────────────────────────────────────────────

_make_proj() {
    local _name="$1"
    local _root="${_TMPDIR}/projects/${_name}"
    mkdir -p "${_root}/bootstrap" "${_root}/image"
    cat > "${_root}/bootstrap/session.json" <<EOF
{
  "project_name": "${_name}",
  "selected_agent": "codex",
  "status": "started",
  "last_updated": "2026-01-01T00:00:00Z",
  "generated_files": [],
  "containerfile_path": "",
  "quality_gate_status": "",
  "last_error": "",
  "resume_command": "ai-new ${_name} --resume",
  "build_log_path": "",
  "trial_image_tag": "",
  "static_check_status": "",
  "pinned_agent_env": "",
  "pinned_agent_hash": ""
}
EOF
    echo "$_root"
}

# ── Tests — repair cap (fast, no real build) ────────────────────────────────

test_check_repair_cap_fails_when_at_limit() {
    local _fail=0
    local _proj
    _proj="$(_make_proj "repair1")"

    cat > "${_TMPDIR}/repair_cap_helper.sh" <<SCRIPT
#!/usr/bin/env bash
set -uo pipefail
export AI_PODMAN_JAILS_DIR='${_TMPDIR}'
export AI_NEW_MAX_REPAIR_ATTEMPTS=3
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/session.sh'
source '${LIB_DIR}/reconcile.sh'
# Run in subshell so _die/exit doesn't bypass remaining script output,
# but propagate the exit code so the caller can detect failure.
(check_repair_cap '${_proj}' 3) 2>&1
SCRIPT
    local out rc=0
    out="$(bash "${_TMPDIR}/repair_cap_helper.sh" 2>&1)" || rc=$?
    assert_failure $rc "repair cap at limit should fail" || _fail=1
    assert_contains "Repair cap" "$out" "error should mention repair cap" || _fail=1
    return $_fail
}

test_check_repair_cap_below_limit_passes() {
    local _fail=0
    local _proj
    _proj="$(_make_proj "repair2")"

    cat > "${_TMPDIR}/repair_ok_helper.sh" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
export AI_PODMAN_JAILS_DIR='${_TMPDIR}'
export AI_NEW_MAX_REPAIR_ATTEMPTS=3
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/session.sh'
source '${LIB_DIR}/reconcile.sh'
check_repair_cap '${_proj}' 2
echo OK
SCRIPT
    local out rc=0
    out="$(bash "${_TMPDIR}/repair_ok_helper.sh" 2>&1)" || rc=$?
    assert_success $rc "repair cap below limit should pass" || _fail=1
    assert_contains "OK" "$out" || _fail=1
    return $_fail
}

test_repair_cap_sets_quality_gate_failed_status() {
    local _fail=0
    local _proj
    _proj="$(_make_proj "repair3")"

    cat > "${_TMPDIR}/repair_status_helper.sh" <<SCRIPT
#!/usr/bin/env bash
set -uo pipefail
export AI_PODMAN_JAILS_DIR='${_TMPDIR}'
export AI_NEW_MAX_REPAIR_ATTEMPTS=2
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/session.sh'
source '${LIB_DIR}/reconcile.sh'
(check_repair_cap '${_proj}' 2) 2>&1 || true
SCRIPT
    bash "${_TMPDIR}/repair_status_helper.sh" >/dev/null 2>&1 || true

    local _status
    _status="$(grep -oP '"status"\s*:\s*"\K[^"]+' "${_proj}/bootstrap/session.json" 2>/dev/null || true)"
    assert_eq "quality-gate-failed" "$_status" \
        "repair cap exhausted should set quality-gate-failed status" || _fail=1
    return $_fail
}

test_env_var_max_repair_attempts_respected() {
    local _fail=0
    local _proj
    _proj="$(_make_proj "repair4")"

    cat > "${_TMPDIR}/repair_env_helper.sh" <<SCRIPT
#!/usr/bin/env bash
set -uo pipefail
export AI_PODMAN_JAILS_DIR='${_TMPDIR}'
export AI_NEW_MAX_REPAIR_ATTEMPTS=5
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/session.sh'
source '${LIB_DIR}/reconcile.sh'
# iteration=4 < 5 → should pass
check_repair_cap '${_proj}' 4
echo PASS
# iteration=5 >= 5 → should fail (run in subshell so _die/exit doesn't kill script)
(check_repair_cap '${_proj}' 5) 2>&1 || echo CAPPED
SCRIPT
    local out rc=0
    out="$(bash "${_TMPDIR}/repair_env_helper.sh" 2>&1)" || rc=$?
    assert_contains "PASS" "$out" "iteration=4 < 5 should pass" || _fail=1
    assert_contains "CAPPED" "$out" "iteration=5 >= 5 should be capped" || _fail=1
    return $_fail
}

# Slow: actual broken build.
test_broken_containerfile_yields_quality_gate_failed() {
    if skip_unless_live; then return 0; fi
    local _fail=0
    local _slug="gate-fail-$(printf '%s' "$$" | sha256sum | cut -c1-6)"
    local _proj
    _proj="$(_make_proj "$_slug")"

    # Write an intentionally broken Containerfile.
    printf 'THIS IS NOT VALID CONTAINERFILE SYNTAX\n' > "${_proj}/image/Containerfile"

    cat > "${_TMPDIR}/gate_fail_helper.sh" <<SCRIPT
#!/usr/bin/env bash
set -uo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/session.sh'
source '${LIB_DIR}/quality_gate.sh'
export AI_PODMAN_JAILS_DIR='${_TMPDIR}'
export SLUG='${_slug}'
export SKIP_TRIAL_BUILD=0
run_quality_gate '${_proj}' 1 '${_proj}/image/Containerfile' '${_proj}/image' \
    "localhost/ai-new/${_slug}:trial" 'initial' 0 || true
SCRIPT
    bash "${_TMPDIR}/gate_fail_helper.sh" >/dev/null 2>&1 || true

    local _status
    _status="$(grep -oP '"status"\s*:\s*"\K[^"]+' "${_proj}/bootstrap/session.json" 2>/dev/null || true)"
    assert_eq "quality-gate-failed" "$_status" \
        "broken Containerfile should yield quality-gate-failed" || _fail=1

    # build.log should be preserved.
    [[ -f "${_proj}/bootstrap/build.log" ]] || {
        printf '    build.log not preserved on failure\n' >&2
        _fail=1
    }
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "check_repair_cap fails when iteration >= max"          test_check_repair_cap_fails_when_at_limit
run_test "check_repair_cap passes when iteration < max"          test_check_repair_cap_below_limit_passes
run_test "repair cap sets quality-gate-failed status"            test_repair_cap_sets_quality_gate_failed_status
run_test "AI_NEW_MAX_REPAIR_ATTEMPTS env var respected"          test_env_var_max_repair_attempts_respected
run_test "[slow] broken Containerfile → quality-gate-failed"    test_broken_containerfile_yields_quality_gate_failed

print_summary "test_gate_fail_repair"
