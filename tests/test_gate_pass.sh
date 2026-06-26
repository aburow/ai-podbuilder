#!/usr/bin/env bash
# T9 (slow) — Valid Containerfile builds; status → complete; image tagged (AC12, AC25).
# Tagged slow: requires PODMAN_LIVE=1 and rootless Podman.
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

# ── Tests ─────────────────────────────────────────────────────────────────────

test_valid_containerfile_builds_and_sets_complete() {
    if skip_unless_live; then return 0; fi
    local _fail=0
    local _slug="gate-pass-$(printf '%s' "$$" | sha256sum | cut -c1-6)"
    local _proj
    _proj="$(_make_proj "$_slug")"

    # Write a minimal valid Containerfile (scratch with no commands — fast build).
    cat > "${_proj}/image/Containerfile" <<'EOF'
FROM scratch
LABEL test=true
EOF

    cat > "${_TMPDIR}/gate_pass_helper.sh" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/session.sh'
source '${LIB_DIR}/quality_gate.sh'
export CODEX_JAILS_DIR='${_TMPDIR}'
export SLUG='${_slug}'
export SKIP_TRIAL_BUILD=0
run_quality_gate '${_proj}' 1 '${_proj}/image/Containerfile' '${_proj}/image' \
    "localhost/ai-new/${_slug}:trial" 'test' 0
SCRIPT
    local out rc=0
    out="$(bash "${_TMPDIR}/gate_pass_helper.sh" 2>&1)" || rc=$?

    # Cleanup: remove trial image.
    podman rmi "localhost/ai-new/${_slug}:trial" >/dev/null 2>&1 || true
    podman rmi "localhost/ai-project/${_slug}:latest" >/dev/null 2>&1 || true

    local _status
    _status="$(grep -oP '"status"\s*:\s*"\K[^"]+' "${_proj}/bootstrap/session.json" 2>/dev/null || true)"
    assert_eq "complete" "$_status" "session status should be complete after build pass" || _fail=1

    # build.log should exist.
    [[ -f "${_proj}/bootstrap/build.log" ]] || {
        printf '    build.log not created\n' >&2
        _fail=1
    }
    return $_fail
}

test_build_log_captured() {
    if skip_unless_live; then return 0; fi
    local _fail=0
    local _slug="gate-log-$(printf '%s' "$$" | sha256sum | cut -c1-6)"
    local _proj
    _proj="$(_make_proj "$_slug")"

    cat > "${_proj}/image/Containerfile" <<'EOF'
FROM scratch
LABEL captured=true
EOF

    cat > "${_TMPDIR}/gate_log_helper.sh" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/session.sh'
source '${LIB_DIR}/quality_gate.sh'
export CODEX_JAILS_DIR='${_TMPDIR}'
export SLUG='${_slug}'
export SKIP_TRIAL_BUILD=0
run_quality_gate '${_proj}' 1 '${_proj}/image/Containerfile' '${_proj}/image' \
    "localhost/ai-new/${_slug}:trial" 'test' 0
SCRIPT
    bash "${_TMPDIR}/gate_log_helper.sh" >/dev/null 2>&1 || true

    podman rmi "localhost/ai-new/${_slug}:trial" >/dev/null 2>&1 || true

    local _log="${_proj}/bootstrap/build.log"
    [[ -f "$_log" ]] || {
        printf '    build.log missing after build\n' >&2
        _fail=1
    }
    return $_fail
}

test_trial_image_tag_recorded_in_session() {
    if skip_unless_live; then return 0; fi
    local _fail=0
    local _slug="gate-tag-$(printf '%s' "$$" | sha256sum | cut -c1-6)"
    local _proj
    _proj="$(_make_proj "$_slug")"

    cat > "${_proj}/image/Containerfile" <<'EOF'
FROM scratch
LABEL tagged=true
EOF

    cat > "${_TMPDIR}/gate_tag_helper.sh" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/session.sh'
source '${LIB_DIR}/quality_gate.sh'
export CODEX_JAILS_DIR='${_TMPDIR}'
export SLUG='${_slug}'
export SKIP_TRIAL_BUILD=0
run_quality_gate '${_proj}' 1 '${_proj}/image/Containerfile' '${_proj}/image' \
    "localhost/ai-new/${_slug}:trial" 'test' 0
SCRIPT
    bash "${_TMPDIR}/gate_tag_helper.sh" >/dev/null 2>&1 || true

    podman rmi "localhost/ai-new/${_slug}:trial" >/dev/null 2>&1 || true

    local _tag
    _tag="$(grep -oP '"trial_image_tag"\s*:\s*"\K[^"]+' "${_proj}/bootstrap/session.json" 2>/dev/null || true)"
    [[ -n "$_tag" ]] || {
        printf '    trial_image_tag not recorded in session.json\n' >&2
        _fail=1
    }
    assert_contains "${_slug}" "$_tag" "trial image tag should contain slug" || _fail=1
    return $_fail
}

test_gate_does_not_create_profile_mirror() {
    # AC7: quality-gate run must not write profiles/<slug>.env
    if skip_unless_live; then return 0; fi
    local _fail=0
    local _slug="gate-mirror-$(printf '%s' "$$" | sha256sum | cut -c1-6)"
    local _proj
    _proj="$(_make_proj "$_slug")"

    cat > "${_proj}/image/Containerfile" <<'EOF'
FROM scratch
LABEL mirror=false
EOF

    cat > "${_TMPDIR}/gate_mirror_helper.sh" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/session.sh'
source '${LIB_DIR}/quality_gate.sh'
export CODEX_JAILS_DIR='${_TMPDIR}'
export SLUG='${_slug}'
export SKIP_TRIAL_BUILD=0
run_quality_gate '${_proj}' 1 '${_proj}/image/Containerfile' '${_proj}/image' \
    "localhost/ai-new/${_slug}:trial" 'test' 0
SCRIPT
    bash "${_TMPDIR}/gate_mirror_helper.sh" >/dev/null 2>&1 || true
    podman rmi "localhost/ai-new/${_slug}:trial" >/dev/null 2>&1 || true

    [[ ! -f "${_TMPDIR}/profiles/${_slug}.env" ]] || {
        printf '    profiles/%s.env was created by quality gate (AC7)\n' "$_slug" >&2
        _fail=1
    }
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "[slow] valid Containerfile builds → status complete" test_valid_containerfile_builds_and_sets_complete
run_test "[slow] build.log captured after build"               test_build_log_captured
run_test "[slow] trial_image_tag recorded in session.json"     test_trial_image_tag_recorded_in_session
run_test "[slow] gate does not create profiles/ mirror (AC7)"  test_gate_does_not_create_profile_mirror

print_summary "test_gate_pass"
