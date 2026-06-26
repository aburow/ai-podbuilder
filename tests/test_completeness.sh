#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# 2026 - Anthony Burow - https://github.com/aburow
# T10 — is_complete returns true only when all R11.6 conditions hold (AC9).
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

# ── Helpers ───────────────────────────────────────────────────────────────────

_completeness_helper() {
    local _script="$1"
    cat > "${_TMPDIR}/complete_helper.sh" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/session.sh'
export AI_PODMAN_JAILS_DIR='${_TMPDIR}'
${_script}
SCRIPT
    bash "${_TMPDIR}/complete_helper.sh" 2>&1
}

_make_complete_scaffold() {
    local _name="$1"
    local _root="${_TMPDIR}/projects/${_name}"
    mkdir -p "${_root}/bootstrap" "${_root}/image"
    cat > "${_root}/bootstrap/session.json" <<'EOF'
{
  "project_name": "test",
  "selected_agent": "codex",
  "status": "complete",
  "last_updated": "2026-01-01T00:00:00Z"
}
EOF
    printf 'FROM scratch\n' > "${_root}/image/Containerfile"
    printf '# Next steps\n' > "${_root}/bootstrap/next-steps.md"
    echo "$_root"
}

# ── Tests ─────────────────────────────────────────────────────────────────────

test_is_complete_true_when_all_conditions_hold() {
    local _fail=0
    local _proj
    _proj="$(_make_complete_scaffold "compl1")"

    local out rc=0
    out="$(_completeness_helper "
        is_complete '${_proj}' && echo YES || echo NO
    ")" || rc=$?
    assert_success $rc || _fail=1
    assert_contains "YES" "$out" "is_complete should return true when all conditions met" || _fail=1
    return $_fail
}

test_is_complete_false_without_containerfile() {
    local _fail=0
    local _proj
    _proj="$(_make_complete_scaffold "compl2")"
    rm -f "${_proj}/image/Containerfile"

    local out rc=0
    out="$(_completeness_helper "
        is_complete '${_proj}' && echo YES || echo NO
    ")" || rc=$?
    assert_success $rc || _fail=1
    assert_contains "NO" "$out" "is_complete should be false without Containerfile" || _fail=1
    return $_fail
}

test_is_complete_false_without_next_steps() {
    local _fail=0
    local _proj
    _proj="$(_make_complete_scaffold "compl3")"
    rm -f "${_proj}/bootstrap/next-steps.md"

    local out rc=0
    out="$(_completeness_helper "
        is_complete '${_proj}' && echo YES || echo NO
    ")" || rc=$?
    assert_success $rc || _fail=1
    assert_contains "NO" "$out" "is_complete should be false without next-steps.md" || _fail=1
    return $_fail
}

test_is_complete_false_with_non_terminal_status() {
    local _fail=0
    local _proj
    _proj="$(_make_complete_scaffold "compl4")"
    # Change status to non-terminal.
    python3 - "${_proj}/bootstrap/session.json" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
d['status'] = 'interviewing'
with open(sys.argv[1], 'w') as f:
    json.dump(d, f)
PYEOF

    local out rc=0
    out="$(_completeness_helper "
        is_complete '${_proj}' && echo YES || echo NO
    ")" || rc=$?
    assert_success $rc || _fail=1
    assert_contains "NO" "$out" "is_complete should be false with non-terminal status" || _fail=1
    return $_fail
}

test_is_complete_true_for_generated_unvalidated() {
    local _fail=0
    local _proj
    _proj="$(_make_complete_scaffold "compl5")"
    python3 - "${_proj}/bootstrap/session.json" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
d['status'] = 'generated-unvalidated'
with open(sys.argv[1], 'w') as f:
    json.dump(d, f)
PYEOF

    local out rc=0
    out="$(_completeness_helper "
        is_complete '${_proj}' && echo YES || echo NO
    ")" || rc=$?
    assert_success $rc || _fail=1
    assert_contains "YES" "$out" "is_complete should be true for generated-unvalidated" || _fail=1
    return $_fail
}

test_is_complete_false_without_session_json() {
    local _fail=0
    local _proj="${_TMPDIR}/projects/compl6"
    mkdir -p "${_proj}/bootstrap" "${_proj}/image"
    printf 'FROM scratch\n' > "${_proj}/image/Containerfile"
    printf '# next\n' > "${_proj}/bootstrap/next-steps.md"
    # No session.json.

    local out rc=0
    out="$(_completeness_helper "
        is_complete '${_proj}' && echo YES || echo NO
    ")" || rc=$?
    assert_success $rc || _fail=1
    assert_contains "NO" "$out" "is_complete should be false without session.json" || _fail=1
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "is_complete true when all R11.6 conditions met"         test_is_complete_true_when_all_conditions_hold
run_test "is_complete false without image/Containerfile"          test_is_complete_false_without_containerfile
run_test "is_complete false without bootstrap/next-steps.md"      test_is_complete_false_without_next_steps
run_test "is_complete false with non-terminal status"             test_is_complete_false_with_non_terminal_status
run_test "is_complete true for generated-unvalidated"             test_is_complete_true_for_generated_unvalidated
run_test "is_complete false without session.json"                 test_is_complete_false_without_session_json

print_summary "test_completeness"
