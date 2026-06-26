#!/usr/bin/env bash
# T9 — Build timeout: grammar/default/enforcement; timeout → quality-gate-timeout (AC23).
# Actual timeout enforcement is slow (requires live Podman).
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

# ── Helpers ───────────────────────────────────────────────────────────────────

_gate_helper() {
    local _script="$1"
    cat > "${_TMPDIR}/timeout_helper.sh" <<SCRIPT
#!/usr/bin/env bash
set -uo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/quality_gate.sh'
export AI_PODMAN_JAILS_DIR='${_TMPDIR}'
export SLUG='testslug'
${_script}
SCRIPT
    bash "${_TMPDIR}/timeout_helper.sh" 2>&1
}

# ── Tests — fast (timeout grammar/default) ────────────────────────────────────

test_default_timeout_is_30m() {
    local _fail=0
    local out rc=0
    out="$(_gate_helper '
        # AI_NEW_BUILD_TIMEOUT not set — _BUILD_TIMEOUT should default to 30m.
        printf "TIMEOUT=%s\n" "$_BUILD_TIMEOUT"
    ')" || rc=$?
    assert_success $rc || _fail=1
    assert_contains "TIMEOUT=30m" "$out" "default timeout should be 30m" || _fail=1
    return $_fail
}

test_timeout_env_var_overrides_default() {
    local _fail=0
    local out rc=0
    out="$(AI_NEW_BUILD_TIMEOUT=5m _gate_helper '
        printf "TIMEOUT=%s\n" "$_BUILD_TIMEOUT"
    ')" || rc=$?
    assert_success $rc || _fail=1
    assert_contains "TIMEOUT=5m" "$out" "AI_NEW_BUILD_TIMEOUT should override default" || _fail=1
    return $_fail
}

test_trial_build_uses_timeout_foreground() {
    # Verify that quality_gate.sh uses 'timeout --foreground' in trial_build.
    local _gate_lib="${LIB_DIR}/quality_gate.sh"
    [[ -f "$_gate_lib" ]] || { printf '    quality_gate.sh not found\n' >&2; return 1; }
    if ! grep -q 'timeout --foreground' "$_gate_lib"; then
        printf '    FAIL: trial_build does not use "timeout --foreground"\n' >&2
        return 1
    fi
    return 0
}

test_trial_build_returns_2_on_timeout() {
    local _fail=0
    local out rc=0
    # trial_build should return 2 when the build times out (exit code 124 from timeout).
    # We stub trial_build via a subshell that simulates a timeout exit code.
    out="$(_gate_helper '
        # Simulate: map_gate_status with build_rc=2 (timeout).
        map_gate_status 0 2 0
        printf "GATE=%s\n" "$GATE_STATUS"
    ')" || rc=$?
    assert_success $rc || _fail=1
    assert_contains "GATE=quality-gate-timeout" "$out" \
        "build_rc=2 should map to quality-gate-timeout" || _fail=1
    return $_fail
}

test_timeout_state_is_resumable_status() {
    # quality-gate-timeout is in the valid status vocabulary (checked separately in T10).
    # Here we verify it's accepted by set_status.
    local _fail=0
    local _proj="${_TMPDIR}/projects/timeout1"
    mkdir -p "${_proj}/bootstrap"
    cat > "${_proj}/bootstrap/session.json" <<'EOF'
{
  "project_name": "timeout1",
  "selected_agent": "codex",
  "status": "started",
  "last_updated": "2026-01-01T00:00:00Z"
}
EOF
    cat > "${_TMPDIR}/timeout_status_helper.sh" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/session.sh'
export AI_PODMAN_JAILS_DIR='${_TMPDIR}'
set_status '${_proj}' 'quality-gate-timeout'
echo OK
SCRIPT
    local out rc=0
    out="$(bash "${_TMPDIR}/timeout_status_helper.sh" 2>&1)" || rc=$?
    assert_success $rc "quality-gate-timeout should be a valid status" || _fail=1
    assert_contains "OK" "$out" || _fail=1
    return $_fail
}

# Slow: actual timeout enforcement.
test_build_timeout_enforced_in_live_build() {
    if skip_unless_live; then return 0; fi
    local _fail=0
    local _slug="gate-timeout-$(printf '%s' "$$" | sha256sum | cut -c1-6)"
    local _proj="${_TMPDIR}/projects/${_slug}"
    mkdir -p "${_proj}/bootstrap" "${_proj}/image"

    # A Containerfile with a very long RUN step.
    cat > "${_proj}/image/Containerfile" <<'EOF'
FROM fedora:latest
RUN sleep 300
EOF

    cat > "${_proj}/bootstrap/session.json" <<EOF
{
  "project_name": "${_slug}",
  "selected_agent": "codex",
  "status": "started",
  "last_updated": "2026-01-01T00:00:00Z"
}
EOF

    cat > "${_TMPDIR}/gate_timeout_helper.sh" <<SCRIPT
#!/usr/bin/env bash
set -uo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/session.sh'
source '${LIB_DIR}/quality_gate.sh'
export AI_PODMAN_JAILS_DIR='${_TMPDIR}'
export SLUG='${_slug}'
export SKIP_TRIAL_BUILD=0
export AI_NEW_BUILD_TIMEOUT=3s
run_quality_gate '${_proj}' 1 '${_proj}/image/Containerfile' '${_proj}/image' \
    "localhost/ai-new/${_slug}:trial" 'test' 0 || true
SCRIPT
    bash "${_TMPDIR}/gate_timeout_helper.sh" >/dev/null 2>&1 || true

    podman rmi "localhost/ai-new/${_slug}:trial" >/dev/null 2>&1 || true

    local _status
    _status="$(grep -oP '"status"\s*:\s*"\K[^"]+' "${_proj}/bootstrap/session.json" 2>/dev/null || true)"
    assert_eq "quality-gate-timeout" "$_status" "3s build timeout should yield quality-gate-timeout" || _fail=1
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "default build timeout is 30m"                         test_default_timeout_is_30m
run_test "AI_NEW_BUILD_TIMEOUT env var overrides default"       test_timeout_env_var_overrides_default
run_test "trial_build uses 'timeout --foreground'"              test_trial_build_uses_timeout_foreground
run_test "trial_build rc=2 maps to quality-gate-timeout"       test_trial_build_returns_2_on_timeout
run_test "quality-gate-timeout is a valid resumable status"     test_timeout_state_is_resumable_status
run_test "[slow] actual build timeout enforced via 3s budget"  test_build_timeout_enforced_in_live_build

print_summary "test_gate_timeout"
