#!/usr/bin/env bash
# T7 — Next-steps content references actual generated paths/commands (AC16).
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

# ── Helpers ───────────────────────────────────────────────────────────────────

_build_mock_scaffold_with_next_steps() {
    local _proj="$1"
    local _name="$2"
    mkdir -p "${_proj}/image" "${_proj}/launchers" "${_proj}/bootstrap"

    # Containerfile.
    printf 'FROM fedora:latest\nWORKDIR /workspace\n' > "${_proj}/image/Containerfile"

    # Launcher.
    printf '#!/usr/bin/env bash\nset -euo pipefail\npodman run --rm -it %s\n' "$_name" \
        > "${_proj}/launchers/launch-${_name}.sh"
    chmod +x "${_proj}/launchers/launch-${_name}.sh"

    # next-steps.md — must reference actual paths.
    cat > "${_proj}/bootstrap/next-steps.md" <<EOF
## Next Steps

The bootstrap is complete. Here are the four recommended next steps:

1. **Build the project image**
   \`\`\`
   ai-build ${_name}
   \`\`\`

2. **Launch the development container**
   \`\`\`
   ai-launch ${_name}
   \`\`\`

3. **Review the generated Containerfile**
   Path: ${_proj}/image/Containerfile

4. **Start working**
   \`\`\`
   ${_proj}/launchers/launch-${_name}.sh
   \`\`\`
EOF

    # session.json with complete status.
    cat > "${_proj}/bootstrap/session.json" <<EOF
{
  "project_name": "${_name}",
  "selected_agent": "codex",
  "status": "complete",
  "resume_command": "ai-new ${_name} --resume",
  "containerfile_path": "${_proj}/image/Containerfile"
}
EOF
}

# ── Tests ─────────────────────────────────────────────────────────────────────

test_next_steps_file_exists() {
    local _fail=0
    local _proj="${_TMPDIR}/projects/nextstep1"
    _build_mock_scaffold_with_next_steps "$_proj" "nextstep1"
    [[ -f "${_proj}/bootstrap/next-steps.md" ]] || {
        printf '    next-steps.md missing\n' >&2
        _fail=1
    }
    return $_fail
}

test_next_steps_references_project_name() {
    local _fail=0
    local _proj="${_TMPDIR}/projects/nextstep2"
    _build_mock_scaffold_with_next_steps "$_proj" "nextstep2"
    local _content
    _content="$(cat "${_proj}/bootstrap/next-steps.md")"
    assert_contains "nextstep2" "$_content" "next-steps.md should reference project name" || _fail=1
    return $_fail
}

test_next_steps_references_containerfile_path() {
    local _fail=0
    local _proj="${_TMPDIR}/projects/nextstep3"
    _build_mock_scaffold_with_next_steps "$_proj" "nextstep3"
    local _content
    _content="$(cat "${_proj}/bootstrap/next-steps.md")"
    assert_contains "Containerfile" "$_content" "next-steps.md should reference Containerfile" || _fail=1
    return $_fail
}

test_next_steps_references_launcher() {
    local _fail=0
    local _proj="${_TMPDIR}/projects/nextstep4"
    _build_mock_scaffold_with_next_steps "$_proj" "nextstep4"
    local _content
    _content="$(cat "${_proj}/bootstrap/next-steps.md")"
    assert_contains "launchers" "$_content" "next-steps.md should reference launchers" || _fail=1
    return $_fail
}

test_next_steps_has_four_steps() {
    local _fail=0
    local _proj="${_TMPDIR}/projects/nextstep5"
    _build_mock_scaffold_with_next_steps "$_proj" "nextstep5"
    local _content
    _content="$(cat "${_proj}/bootstrap/next-steps.md")"
    # Count numbered steps.
    local _count
    _count="$(echo "$_content" | grep -cE '^[[:space:]]*[0-9]+\.' || true)"
    [[ "$_count" -ge 4 ]] || {
        printf '    Expected at least 4 numbered steps, found %d\n' "$_count" >&2
        _fail=1
    }
    return $_fail
}

test_next_steps_bootstrap_done_message() {
    local _fail=0
    local _proj="${_TMPDIR}/projects/nextstep6"
    _build_mock_scaffold_with_next_steps "$_proj" "nextstep6"
    local _content
    _content="$(cat "${_proj}/bootstrap/next-steps.md")"
    assert_contains "complete" "$_content" "next-steps.md should indicate bootstrap is done" || _fail=1
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "next-steps.md exists in bootstrap/"                 test_next_steps_file_exists
run_test "next-steps.md references project name"              test_next_steps_references_project_name
run_test "next-steps.md references Containerfile path"        test_next_steps_references_containerfile_path
run_test "next-steps.md references launcher"                  test_next_steps_references_launcher
run_test "next-steps.md has at least four steps"              test_next_steps_has_four_steps
run_test "next-steps.md indicates bootstrap is complete"      test_next_steps_bootstrap_done_message

print_summary "test_next_steps"
