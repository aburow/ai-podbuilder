#!/usr/bin/env bash
# Agent-specific bootstrap image management for ai-new. Source; do not execute.
# Requires common.sh and registry.sh.

_BOOTSTRAP_IMAGE_TAG_FALLBACK="localhost/ai-new/bootstrap:latest"
_BOOTSTRAP_CONTAINERFILE_NAME="Containerfile.bootstrap"

# _bootstrap_containerfile_path [project_root]
_bootstrap_containerfile_path() {
    local _project_root="${1:-}"
    if [[ -n "$_project_root" ]]; then
        echo "${_project_root}/bootstrap/${_BOOTSTRAP_CONTAINERFILE_NAME}"
    else
        echo "${AI_PODMAN_JAILS_DIR}/config/${_BOOTSTRAP_CONTAINERFILE_NAME}"
    fi
}

_validate_containerfile_value() {
    local _label="$1"
    local _value="$2"
    [[ "$_value" =~ ^[A-Za-z0-9@._/+:-]*$ ]] \
        || _die "Unsafe ${_label} value in pinned agent registry: ${_value}"
}

# _write_bootstrap_containerfile <path> [adapter package version command agent]
# Writes a minimal Fedora bootstrap Containerfile and, when runtime metadata is
# supplied, bakes the selected agent into the image at build time.
_write_bootstrap_containerfile() {
    local _path="$1"
    local _adapter="${2:-}"
    local _package="${3:-}"
    local _version="${4:-}"
    local _command="${5:-}"
    local _agent="${6:-}"

    _validate_containerfile_value "adapter" "$_adapter"
    _validate_containerfile_value "package" "$_package"
    _validate_containerfile_value "version" "$_version"
    _validate_containerfile_value "command" "$_command"
    _validate_containerfile_value "agent" "$_agent"

    mkdir -p "$(dirname "$_path")"
    {
        cat <<'EOF'
FROM fedora:latest
LABEL ai-new.role=bootstrap

RUN dnf install -y \
        bash \
        coreutils \
        curl \
        git \
        nodejs \
        npm \
        python3 \
        python3-pip \
        pipx \
        findutils \
        util-linux \
        --setopt=install_weak_deps=False \
    && dnf clean all
EOF

        case "$_adapter" in
            "")
                ;;
            npm-global)
                local _npm_package="$_package"
                [[ -n "$_version" ]] && _npm_package="${_package}@${_version}"
                printf '\n# Selected agent runtime: %s\n' "$_agent"
                printf 'RUN npm install --global %s \\\n' "$_npm_package"
                printf '    && command -v %s\n' "$_command"
                ;;
            pipx)
                local _pipx_package="$_package"
                [[ -n "$_version" ]] && _pipx_package="${_package}==${_version}"
                printf '\n# Selected agent runtime: %s\n' "$_agent"
                printf 'RUN PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx install %s \\\n' "$_pipx_package"
                printf '    && command -v %s\n' "$_command"
                ;;
            dnf-package)
                local _dnf_package="$_package"
                [[ -n "$_version" ]] && _dnf_package="${_package}-${_version}"
                printf '\n# Selected agent runtime: %s\n' "$_agent"
                printf 'RUN dnf install -y %s --setopt=install_weak_deps=False \\\n' "$_dnf_package"
                printf '    && dnf clean all \\\n'
                printf '    && command -v %s\n' "$_command"
                ;;
            preinstalled)
                printf '\n# Selected agent runtime is supplied by the base image: %s\n' "$_agent"
                printf 'RUN command -v %s\n' "$_command"
                ;;
            manual)
                _die "Agent '${_agent}' uses the manual adapter and cannot be built automatically. Configure an installable adapter in its registry entry."
                ;;
            *)
                _die "Unknown install adapter: ${_adapter}"
                ;;
        esac

        cat <<EOF

LABEL ai-new.agent="${_agent}"
ENV HOME=/project/bootstrap/home
WORKDIR /project
EOF
    } > "$_path"
}

# ensure_bootstrap_image <project_root>
# Parses the pinned registry, writes an agent-specific Containerfile, builds it,
# and exports the exact image tag consumed by launch_bootstrap.
ensure_bootstrap_image() {
    local _project_root="${1:-}"
    [[ -n "$_project_root" ]] || _die "ensure_bootstrap_image requires a project root"

    local _agent_env="${_project_root}/bootstrap/agent.env"
    parse_registry_file "$_agent_env"
    validate_adapters "$REG_AGENT_INSTALL_ADAPTER"

    [[ -n "$REG_AGENT_NAME" ]] || _die "Pinned agent registry has no AGENT_NAME: ${_agent_env}"
    [[ -n "$REG_AGENT_COMMAND" ]] || _die "Pinned agent registry has no AGENT_COMMAND: ${_agent_env}"

    local _hash _slug _cfile
    _hash="$(sha256sum "$_agent_env" | awk '{print substr($1,1,12)}')"
    _slug="${SLUG:-$(basename "$_project_root")}"
    export BOOTSTRAP_IMAGE_TAG="localhost/ai-new/bootstrap-${_slug}:${REG_AGENT_NAME}-${_hash}"
    _cfile="$(_bootstrap_containerfile_path "$_project_root")"

    _write_bootstrap_containerfile \
        "$_cfile" \
        "$REG_AGENT_INSTALL_ADAPTER" \
        "$REG_AGENT_INSTALL_PACKAGE" \
        "$REG_AGENT_INSTALL_VERSION" \
        "$REG_AGENT_COMMAND" \
        "$REG_AGENT_NAME"

    if podman image exists "$BOOTSTRAP_IMAGE_TAG" 2>/dev/null; then
        _info "Agent bootstrap image already exists: ${BOOTSTRAP_IMAGE_TAG}"
        return 0
    fi

    local _build_context="${AI_PODMAN_JAILS_DIR}/config"
    mkdir -p "$_build_context"

    _info "Building bootstrap image with '${REG_AGENT_NAME}' installed …"
    podman build \
        --pull=always \
        --no-cache \
        -f "$_cfile" \
        -t "$BOOTSTRAP_IMAGE_TAG" \
        "$_build_context" \
        || _die "Failed to build bootstrap image with agent '${REG_AGENT_NAME}'. Check ${_cfile} for errors."
    _info "Agent bootstrap image ready: ${BOOTSTRAP_IMAGE_TAG}"
}
