#!/usr/bin/env bash
# Scaffold creation for ai-new projects (R2.2, R2.4). Source; do not execute.
# Requires common.sh, slug.sh, session.sh, registry.sh.

# create_scaffold <name>
# Creates the R2.2 project layout and places bootstrap files.
create_scaffold() {
    local _name="$1"
    local _slug
    _slug="$(sanitize_slug "$_name")"

    scaffold_layout "$PROJECT_ROOT"
    register_slug "$_name" "$_slug"

    refresh_bootstrap_entrypoint "$PROJECT_ROOT"

    # Write profile.env (minimal placeholder; agent-specific content from FE plan).
    cat > "${PROJECT_ROOT}/profile.env" <<EOF
# Project profile — ${_name}
PROJECT_NAME=${_name}
PROJECT_SLUG=${_slug}
EOF

    # Write README.md placeholder (content owned by FE plan).
    cat > "${PROJECT_ROOT}/README.md" <<EOF
# ${_name}

Bootstrap project created by ai-new.

See \`bootstrap/session.md\` for session continuity notes.
Run \`/project/bootstrap/home/start-here.sh\` inside the bootstrap container to begin.
EOF

    cat > "${PROJECT_ROOT}/.env.example" <<EOF
# .env.example — ${_name}
# Copy this file to .env and fill in real values.
# .env is gitignored — never commit real secrets.
#
# EXAMPLE_SECRET=<your-value-here>
EOF

    cat > "${PROJECT_ROOT}/.gitignore" <<'EOF'
bootstrap/agent.env.local
bootstrap/home/
state/
.env
*.env.local
.codex/
.openai/
.config/github-copilot/
.config/gemini/
.codex/
__pycache__/
node_modules/
target/
dist/
build/
EOF

    cat > "${PROJECT_ROOT}/PODMAN_BUILDER.md" <<EOF
# PODMAN_BUILDER — ${_name}

## Project purpose

Pending interview completion.

## Final durable agent runtime

unknown

## Base image

unknown

## Required packages and tools

Pending interview completion.

## Workdir

unknown

## Mounts and persistent state

Pending interview completion.

## Ports

Pending interview completion.

## Environment variables

Pending interview completion.

## Secrets policy

Use runtime-mounted secrets or .env. Do not bake secrets into layers.

## Enabled optional services

none

## Explicitly rejected features

none
EOF

    _info "Scaffold created at ${PROJECT_ROOT}"
}

# install_codex_auth_boost <source_auth_json>
# Copies a user-approved Codex auth.json into both the bootstrap container HOME
# and the durable container HOME. The file contents are never read.
install_codex_auth_boost() {
    local _src="$1"
    local _bootstrap_dest="${PROJECT_BOOTSTRAP_HOME}/.codex/auth.json"
    local _state_dest="${PROJECT_STATE_HOME}/.codex/auth.json"

    _src="$(normalize_boost_auth_source "$_src")"

    [[ -f "$_src" ]] || _die "--boost auth file not found: ${_src}"

    mkdir -p "$(dirname "$_bootstrap_dest")" "$(dirname "$_state_dest")"
    install -m 600 "$_src" "$_bootstrap_dest"
    install -m 600 "$_src" "$_state_dest"
    _info "Codex auth.json copied into bootstrap and durable container homes."
}

# refresh_bootstrap_entrypoint <project_root>
# start-here.sh is framework-owned, not agent-generated. Refresh it before every
# launch so resumed projects receive launcher and agent-argument fixes.
refresh_bootstrap_entrypoint() {
    local _project_root="$1"
    local _src_start_here="${AI_PODMAN_JAILS_DIR}/start-here.sh"
    local _dst_start_here="${_project_root}/bootstrap/home/start-here.sh"
    if [[ -f "$_src_start_here" ]]; then
        mkdir -p "${_project_root}/bootstrap/home"
        cp "$_src_start_here" "$_dst_start_here"
        chmod +x "$_dst_start_here"
    else
        _die "Cannot find start-here.sh at ${_src_start_here}"
    fi
}

# normalize_boost_auth_source <path>
# Expands a literal leading ~ and echoes the resulting path.
normalize_boost_auth_source() {
    local _src="$1"
    case "$_src" in
        \~) echo "${HOME}" ;;
        \~/*) echo "${HOME}/${_src#~/}" ;;
        *) echo "$_src" ;;
    esac
}

# scaffold_layout <project_root>
# Creates the canonical directory structure (R2.2).
scaffold_layout() {
    local _root="$1"
    local _d
    for _d in \
        "${_root}/workspace" \
        "${_root}/image" \
        "${_root}/launchers" \
        "${_root}/bootstrap" \
        "${_root}/bootstrap/home"; do
        mkdir -p "$_d"
    done
}
