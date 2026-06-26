#!/usr/bin/env bash
# Shared library sourced by every ai-* command. Do not execute directly.

_die()  { echo "[ERROR] $*" >&2; exit 1; }
_warn() { echo "[WARN]  $*" >&2; }
_info() { echo "[INFO]  $*" >&2; }

# Sets AI_PODMAN_JAILS_DIR from this file's location so the repo is self-hosting
# from any workspace.
resolve_base_dir() {
    if [[ -z "${AI_PODMAN_JAILS_DIR:-}" ]]; then
        local _src_dir
        _src_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        AI_PODMAN_JAILS_DIR="$(cd "${_src_dir}/.." && pwd)"
    fi
    export AI_PODMAN_JAILS_DIR
}

# Returns true (0) when both stdin and stdout are TTYs.
is_interactive() {
    [[ -t 0 && -t 1 ]]
}

require_cmd() {
    local cmd="$1"
    command -v "$cmd" >/dev/null 2>&1 || _die "Required command not found: ${cmd}"
}

profiles_dir() {
    echo "${AI_PODMAN_JAILS_DIR}/profiles"
}

# Sets AI_PODMAN_JAILS_DIR for ai-new, defaults to $HOME/codex-jails (R2.1).
resolve_jails_dir() {
    AI_PODMAN_JAILS_DIR="${AI_PODMAN_JAILS_DIR:-${HOME}/codex-jails}"
    export AI_PODMAN_JAILS_DIR
}

# project_paths <name>
# Sets/exports all per-project path variables derived from AI_PODMAN_JAILS_DIR.
# resolve_jails_dir (or resolve_base_dir) must be called first (R2.2, R2.3).
project_paths() {
    local _name="$1"
    PROJECT_ROOT="${AI_PODMAN_JAILS_DIR}/projects/${_name}"
    PROJECT_WORKSPACE="${PROJECT_ROOT}/workspace"
    PROJECT_IMAGE_DIR="${PROJECT_ROOT}/image"
    PROJECT_LAUNCHERS="${PROJECT_ROOT}/launchers"
    PROJECT_BOOTSTRAP="${PROJECT_ROOT}/bootstrap"
    PROJECT_BOOTSTRAP_HOME="${PROJECT_ROOT}/bootstrap/home"
    PROJECT_STATE_HOME="${PROJECT_ROOT}/state/home"
    AI_PODMAN_BIN="${AI_PODMAN_BIN:-${AI_PODMAN_JAILS_DIR}/bin}"
    AI_PODMAN_AGENTS_DIR="${AI_PODMAN_AGENTS_DIR:-${AI_PODMAN_JAILS_DIR}/config/agents.d}"
    export PROJECT_ROOT PROJECT_WORKSPACE PROJECT_IMAGE_DIR PROJECT_LAUNCHERS
    export PROJECT_BOOTSTRAP PROJECT_BOOTSTRAP_HOME PROJECT_STATE_HOME
    export AI_PODMAN_BIN AI_PODMAN_AGENTS_DIR
}
