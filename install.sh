#!/usr/bin/env bash
# Milestone 1 — Skeleton, strict mode, arg & help parsing
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  bash install.sh [INSTALL_ROOT]
  curl <url> | bash -s -- [INSTALL_ROOT]

  INSTALL_ROOT   Installation directory (default: $HOME/ai-podman-jails)

  Env file written to: $HOME/.bashrc.d/podbuilder.sh

Options:
  -h, --help   Print this message and exit
EOF
}

die() {
  # $1 = step name, $2 = message
  printf 'ERROR [%s]: %s\n' "${1}" "${2}" >&2
  exit 1
}

info() {
  printf '==> %s\n' "${*}"
}

# ---------- main ----------
case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac
# shellcheck disable=SC2034
INSTALL_ROOT="${1:-${HOME}/ai-podman-jails}"
