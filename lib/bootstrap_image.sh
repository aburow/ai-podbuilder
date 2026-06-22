#!/usr/bin/env bash
# Bootstrap image management for ai-new (R3.1–R3.4). Source; do not execute.
# Requires common.sh.

_BOOTSTRAP_IMAGE_TAG="localhost/ai-new/bootstrap:latest"
_BOOTSTRAP_CONTAINERFILE_NAME="Containerfile.bootstrap"

# _bootstrap_containerfile_path
_bootstrap_containerfile_path() {
    echo "${CODEX_JAILS_DIR}/config/${_BOOTSTRAP_CONTAINERFILE_NAME}"
}

# _write_bootstrap_containerfile <path>
# Writes the minimal fedora-based bootstrap Containerfile.
_write_bootstrap_containerfile() {
    local _path="$1"
    mkdir -p "$(dirname "$_path")"
    cat > "$_path" <<'EOF'
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

# No project build tools, no language stacks — only runtime-install tooling.
ENV HOME=/project/bootstrap/home
WORKDIR /project
EOF
}

# ensure_bootstrap_image
# Builds the bootstrap image if it does not already exist.
ensure_bootstrap_image() {
    if podman image exists "$_BOOTSTRAP_IMAGE_TAG" 2>/dev/null; then
        _info "Bootstrap image already exists: ${_BOOTSTRAP_IMAGE_TAG}"
        return 0
    fi
    local _cfile
    _cfile="$(_bootstrap_containerfile_path)"
    if [[ ! -f "$_cfile" ]]; then
        _info "Writing bootstrap Containerfile to ${_cfile}"
        _write_bootstrap_containerfile "$_cfile"
    fi
    _info "Building bootstrap image ${_BOOTSTRAP_IMAGE_TAG} …"
    podman build -f "$_cfile" -t "$_BOOTSTRAP_IMAGE_TAG" "$(dirname "$_cfile")" \
        || _die "Failed to build bootstrap image. Check ${_cfile} for errors."
    _info "Bootstrap image ready: ${_BOOTSTRAP_IMAGE_TAG}"
}
