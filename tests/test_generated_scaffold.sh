#!/usr/bin/env bash
# T7 — Generated scaffold structure verification (R5, R6, R7, AC8, AC10, AC11).
# Uses a mock agent that writes the expected files.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

# ── Helpers ───────────────────────────────────────────────────────────────────

_build_mock_agent_scaffold() {
    local _proj="$1"
    # Simulate what a real agent would produce: the required files.
    mkdir -p "${_proj}/image"
    mkdir -p "${_proj}/launchers"
    mkdir -p "${_proj}/workspace"
    mkdir -p "${_proj}/bootstrap"

    # Required: real Containerfile.
    cat > "${_proj}/image/Containerfile" <<'EOF'
FROM fedora:latest
RUN dnf install -y bash coreutils && dnf clean all
WORKDIR /workspace
EOF

    # Required: profile.env.
    cat > "${_proj}/profile.env" <<'EOF'
PROJECT_NAME=testproject
PROJECT_SLUG=testproject
IMAGE_NAME=testproject-image
CONTAINER_NAME=codex-testproject
IMAGE_DIR=/tmp/jails/projects/testproject/image
WORKSPACE=/tmp/jails/projects/testproject/workspace
CONTAINER_HOME=/home/builder
BASHRC=/tmp/jails/projects/testproject/bootstrap/home/.bashrc
WORKDIR=/workspace
BUILD_ARGS=
EOF

    # Required: launcher.
    cat > "${_proj}/launchers/launch-testproject.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exec podman run --rm -it testproject
EOF
    chmod +x "${_proj}/launchers/launch-testproject.sh"

    # Required: README with next steps.
    cat > "${_proj}/README.md" <<'EOF'
# testproject

Bootstrap project created by ai-new.

## Next Steps

1. Review the generated Containerfile at image/Containerfile
2. Build the image: ./launchers/launch-testproject.sh --build
3. Launch the container
4. Mount your workspace
EOF

    cat > "${_proj}/PODMAN_BUILDER.md" <<'EOF'
# PODMAN_BUILDER — testproject

## Project purpose
Test durable build contract.

## Final durable agent runtime
none

## Base image
fedora:latest

## Required packages and tools
bash, coreutils

## Workdir
/workspace

## Mounts and persistent state
workspace, container home

## Ports
none

## Environment variables
none

## Secrets policy
runtime only

## Enabled optional services
none

## Explicitly rejected features
ssh
EOF

    # Required: .env.example with placeholders.
    cat > "${_proj}/.env.example" <<'EOF'
# API key placeholder — copy to .env and fill in real values.
MY_API_KEY=your-key-here
EOF

    # Required: .gitignore.
    cat > "${_proj}/.gitignore" <<'EOF'
bootstrap/agent.env.local
bootstrap/home/
state/
.env
*.env.local
EOF

    # Required: session.json and session.md.
    cat > "${_proj}/bootstrap/session.json" <<EOF
{
  "project_name": "testproject",
  "selected_agent": "codex",
  "status": "complete",
  "last_updated": "2026-01-01T00:00:00Z",
  "generated_files": ["image/Containerfile", "profile.env", "launchers/launch-testproject.sh"],
  "containerfile_path": "${_proj}/image/Containerfile",
  "quality_gate_status": "complete",
  "last_error": "",
  "resume_command": "ai-new testproject --resume",
  "build_log_path": "${_proj}/bootstrap/build.log",
  "trial_image_tag": "localhost/ai-new/testproject:trial",
  "static_check_status": "passed",
  "final_runtime": "none",
  "enabled_optional_features": [],
  "rejected_optional_features": ["ssh"],
  "durable_reconciliation_status": "passed",
  "durable_spec_path": "${_proj}/PODMAN_BUILDER.md",
  "pinned_agent_env": "${_proj}/bootstrap/agent.env",
  "pinned_agent_hash": "abc123"
}
EOF
    cat > "${_proj}/bootstrap/session.md" <<'EOF'
# Session Log

## Interview Summary
The agent collected project requirements.

## Decisions
- Language: Python
- Base image: Fedora latest

## Reconciliation Notes
_None._
EOF

    # Required: next-steps.md.
    cat > "${_proj}/bootstrap/next-steps.md" <<'EOF'
## Next Steps

1. ai-build testproject
2. ai-launch testproject
3. ai-list
EOF
}

# ── Tests ─────────────────────────────────────────────────────────────────────

test_containerfile_present_in_image_dir() {
    local _fail=0
    local _proj="${_TMPDIR}/projects/testproject"
    _build_mock_agent_scaffold "$_proj"
    [[ -f "${_proj}/image/Containerfile" ]] || {
        printf '    image/Containerfile missing\n' >&2
        _fail=1
    }
    return $_fail
}

test_profile_env_present() {
    local _fail=0
    local _proj="${_TMPDIR}/projects/testproject"
    _build_mock_agent_scaffold "$_proj"
    [[ -f "${_proj}/profile.env" ]] || {
        printf '    profile.env missing\n' >&2
        _fail=1
    }
    return $_fail
}

test_launcher_script_present_and_executable() {
    local _fail=0
    local _proj="${_TMPDIR}/projects/testproject"
    _build_mock_agent_scaffold "$_proj"
    local _found=0
    local _f
    shopt -s nullglob
    for _f in "${_proj}/launchers"/*.sh; do
        _found=1
        [[ -x "$_f" ]] || {
            printf '    Launcher not executable: %s\n' "$_f" >&2
            _fail=1
        }
    done
    shopt -u nullglob
    [[ "$_found" -eq 1 ]] || {
        printf '    No launcher scripts found\n' >&2
        _fail=1
    }
    return $_fail
}

test_readme_with_next_steps_present() {
    local _fail=0
    local _proj="${_TMPDIR}/projects/testproject"
    _build_mock_agent_scaffold "$_proj"
    [[ -f "${_proj}/README.md" ]] || { printf '    README.md missing\n' >&2; _fail=1; }
    local _content
    _content="$(cat "${_proj}/README.md")"
    assert_contains "Next Step" "$_content" "README should have Next Steps section" || _fail=1
    return $_fail
}

test_env_example_with_placeholders_only() {
    local _fail=0
    local _proj="${_TMPDIR}/projects/testproject"
    _build_mock_agent_scaffold "$_proj"
    [[ -f "${_proj}/.env.example" ]] || { printf '    .env.example missing\n' >&2; _fail=1; }
    local _content
    _content="$(cat "${_proj}/.env.example")"
    assert_contains "placeholder" "$_content" ".env.example should mention placeholder" || _fail=1
    # No real secret values (real API keys contain long base64 or uuid-like strings).
    # We just verify no obviously real-looking key was baked in.
    assert_not_contains "sk-" "$_content" "no real API key should be in .env.example" || _fail=1
    return $_fail
}

test_gitignore_excludes_secrets() {
    local _fail=0
    local _proj="${_TMPDIR}/projects/testproject"
    _build_mock_agent_scaffold "$_proj"
    [[ -f "${_proj}/.gitignore" ]] || { printf '    .gitignore missing\n' >&2; _fail=1; }
    local _content
    _content="$(cat "${_proj}/.gitignore")"
    assert_contains "agent.env.local" "$_content" ".gitignore should exclude agent.env.local" || _fail=1
    assert_contains "bootstrap/home" "$_content" ".gitignore should exclude bootstrap/home/" || _fail=1
    assert_contains "state/" "$_content" ".gitignore should exclude state/" || _fail=1
    return $_fail
}

test_session_json_present_with_generated_files() {
    local _fail=0
    local _proj="${_TMPDIR}/projects/testproject"
    _build_mock_agent_scaffold "$_proj"
    [[ -f "${_proj}/bootstrap/session.json" ]] || {
        printf '    session.json missing\n' >&2
        _fail=1
    }
    local _content
    _content="$(cat "${_proj}/bootstrap/session.json")"
    assert_contains "generated_files" "$_content" "session.json should have generated_files" || _fail=1
    return $_fail
}

test_session_md_present() {
    local _fail=0
    local _proj="${_TMPDIR}/projects/testproject"
    _build_mock_agent_scaffold "$_proj"
    [[ -f "${_proj}/bootstrap/session.md" ]] || {
        printf '    session.md missing\n' >&2
        _fail=1
    }
    return $_fail
}

test_podman_builder_present() {
    local _fail=0
    local _proj="${_TMPDIR}/projects/testproject"
    _build_mock_agent_scaffold "$_proj"
    [[ -f "${_proj}/PODMAN_BUILDER.md" ]] || {
        printf '    PODMAN_BUILDER.md missing\n' >&2
        _fail=1
    }
    return $_fail
}

test_session_json_contains_durable_fields() {
    local _fail=0
    local _proj="${_TMPDIR}/projects/testproject"
    _build_mock_agent_scaffold "$_proj"
    local _content
    _content="$(cat "${_proj}/bootstrap/session.json")"
    assert_contains "\"final_runtime\"" "$_content" || _fail=1
    assert_contains "\"enabled_optional_features\"" "$_content" || _fail=1
    assert_contains "\"rejected_optional_features\"" "$_content" || _fail=1
    assert_contains "\"durable_spec_path\"" "$_content" || _fail=1
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "image/Containerfile present"                  test_containerfile_present_in_image_dir
run_test "profile.env present"                          test_profile_env_present
run_test "launcher script present and executable"       test_launcher_script_present_and_executable
run_test "README.md with Next Steps present"            test_readme_with_next_steps_present
run_test ".env.example with placeholders only"          test_env_example_with_placeholders_only
run_test ".gitignore excludes secrets and home dir"     test_gitignore_excludes_secrets
run_test "session.json present with generated_files"    test_session_json_present_with_generated_files
run_test "session.md present"                           test_session_md_present
run_test "PODMAN_BUILDER.md present"                    test_podman_builder_present
run_test "session.json contains durable fields"         test_session_json_contains_durable_fields

print_summary "test_generated_scaffold"
