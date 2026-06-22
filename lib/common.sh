#!/usr/bin/env bash
# Shared library sourced by every ai-* command. Do not execute directly.

_die()  { echo "[ERROR] $*" >&2; exit 1; }
_warn() { echo "[WARN]  $*" >&2; }
_info() { echo "[INFO]  $*" >&2; }

# Sets CODEX_JAILS_DIR: honours the env var if already set, otherwise derives
# from this file's location so the repo is self-hosting from any workspace.
resolve_base_dir() {
    if [[ -n "${CODEX_JAILS_DIR:-}" ]]; then
        export CODEX_JAILS_DIR
        return 0
    fi
    local _src_dir
    _src_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    CODEX_JAILS_DIR="$(cd "${_src_dir}/.." && pwd)"
    export CODEX_JAILS_DIR
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
    echo "${CODEX_JAILS_DIR}/profiles"
}
