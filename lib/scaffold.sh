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

    # Copy start-here.sh into the scaffold home so it is available at
    # /project/bootstrap/home/start-here.sh inside the container (B1, R1.2, R2.2).
    # The execute bit is set here, independent of the host checkout's mode (R2.2).
    local _src_start_here="${CODEX_JAILS_DIR}/start-here.sh"
    local _dst_start_here="${PROJECT_ROOT}/bootstrap/home/start-here.sh"
    if [[ -f "$_src_start_here" ]]; then
        cp "$_src_start_here" "$_dst_start_here"
        chmod +x "$_dst_start_here"
    else
        _die "Cannot find start-here.sh at ${_src_start_here}"
    fi

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

    _info "Scaffold created at ${PROJECT_ROOT}"
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
