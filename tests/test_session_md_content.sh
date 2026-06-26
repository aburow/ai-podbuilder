#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# 2026 - Anthony Burow - https://github.com/aburow
# T10 — session.md carries R11.2 content including reconciliation notes (AC9).
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

# ── Helpers ───────────────────────────────────────────────────────────────────

_session_md_helper() {
    local _script="$1"
    cat > "${_TMPDIR}/session_md_helper.sh" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/session.sh'
export AI_PODMAN_JAILS_DIR='${_TMPDIR}'
${_script}
SCRIPT
    bash "${_TMPDIR}/session_md_helper.sh" 2>&1
}

_make_proj_with_session_md() {
    local _name="$1"
    local _root="${_TMPDIR}/projects/${_name}"
    mkdir -p "${_root}/bootstrap"
    cat > "${_root}/bootstrap/agent.env" <<'AEOF'
# source_hash=abc
AGENT_NAME="codex"
AEOF

    cat > "${_TMPDIR}/init_md_helper.sh" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/session.sh'
export AI_PODMAN_JAILS_DIR='${_TMPDIR}'
init_session '${_root}' '${_name}' 'codex'
SCRIPT
    bash "${_TMPDIR}/init_md_helper.sh" >/dev/null 2>&1 || true
    echo "$_root"
}

# ── Tests ─────────────────────────────────────────────────────────────────────

test_session_md_created_on_init() {
    local _fail=0
    local _proj
    _proj="$(_make_proj_with_session_md "md1")"
    [[ -f "${_proj}/bootstrap/session.md" ]] || {
        printf '    session.md not created by init_session\n' >&2
        _fail=1
    }
    return $_fail
}

test_session_md_has_required_sections() {
    local _fail=0
    local _proj
    _proj="$(_make_proj_with_session_md "md2")"
    local _content
    _content="$(cat "${_proj}/bootstrap/session.md")"

    local _section
    for _section in "Interview Summary" "Decisions" "Generated Files" \
        "Quality-Gate Result" "Reconciliation Notes"; do
        assert_contains "$_section" "$_content" "session.md should have section: ${_section}" || _fail=1
    done
    return $_fail
}

test_append_session_md_adds_section() {
    local _fail=0
    local _proj
    _proj="$(_make_proj_with_session_md "md3")"

    local out rc=0
    out="$(_session_md_helper "
        append_session_md '${_proj}' 'Test Section' 'This is test content.'
        cat '${_proj}/bootstrap/session.md'
    ")" || rc=$?
    assert_success $rc || _fail=1
    assert_contains "Test Section" "$out" "appended section should appear in session.md" || _fail=1
    assert_contains "This is test content" "$out" || _fail=1
    return $_fail
}

test_append_session_md_includes_timestamp() {
    local _fail=0
    local _proj
    _proj="$(_make_proj_with_session_md "md4")"

    local out rc=0
    out="$(_session_md_helper "
        append_session_md '${_proj}' 'Timestamped Section' 'Content here.'
        cat '${_proj}/bootstrap/session.md'
    ")" || rc=$?
    assert_success $rc || _fail=1
    # Timestamp should look like an ISO-8601 string.
    if ! echo "$out" | grep -qE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}'; then
        printf '    session.md does not contain a timestamp\n' >&2
        _fail=1
    fi
    return $_fail
}

test_reconciliation_notes_section_present() {
    local _fail=0
    local _proj
    _proj="$(_make_proj_with_session_md "md5")"

    cat > "${_TMPDIR}/recon_md_helper.sh" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/session.sh'
export AI_PODMAN_JAILS_DIR='${_TMPDIR}'
append_session_md '${_proj}' 'Reconciliation' 'Status changed from interviewing to interrupted.'
cat '${_proj}/bootstrap/session.md'
SCRIPT
    local out rc=0
    out="$(bash "${_TMPDIR}/recon_md_helper.sh" 2>&1)" || rc=$?
    assert_success $rc "reconciliation note should be appended" || _fail=1
    assert_contains "interrupted" "$out" "reconciliation note should contain the reason" || _fail=1
    return $_fail
}

test_session_md_is_human_readable_markdown() {
    local _fail=0
    local _proj
    _proj="$(_make_proj_with_session_md "md6")"
    local _content
    _content="$(cat "${_proj}/bootstrap/session.md")"
    # Should have markdown headings.
    assert_contains "# Session Log" "$_content" "session.md should have main heading" || _fail=1
    assert_contains "##" "$_content" "session.md should have section headings" || _fail=1
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "session.md created on init_session"                   test_session_md_created_on_init
run_test "session.md has required R11.2 sections"               test_session_md_has_required_sections
run_test "append_session_md adds a new section"                 test_append_session_md_adds_section
run_test "append_session_md includes ISO-8601 timestamp"        test_append_session_md_includes_timestamp
run_test "reconciliation notes appended correctly"              test_reconciliation_notes_section_present
run_test "session.md is valid markdown with headings"           test_session_md_is_human_readable_markdown

print_summary "test_session_md_content"
