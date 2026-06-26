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

# ---------- milestone 2: prerequisite checks ----------
check_prereqs() {
  local cmd missing
  missing=""
  for cmd in bash curl podman; do
    command -v "${cmd}" >/dev/null 2>&1 || missing="${missing} ${cmd}"
  done
  [[ -z "${missing}" ]] || die "check_prereqs" "Missing prerequisites:${missing}"
  podman info >/dev/null 2>&1 \
    || die "check_prereqs" "Rootless podman not working — run: podman info"
}

# ---------- milestone 3: fetch latest release tarball ----------
REPO="aburow/ai-podbuilder"
STAGE=""   # set inside fetch_release; trap cleans it on EXIT
SRCROOT="" # top-level dir inside the extracted tarball

fetch_release() {
  STAGE="$(mktemp -d)"
  trap 'rm -rf "${STAGE}"' EXIT

  local ref="${AI_PODMAN_REF:-}"
  local url

  if [[ -n "${ref}" ]]; then
    url="https://github.com/${REPO}/tarball/${ref}"
  else
    local api
    api="https://api.github.com/repos/${REPO}/releases/latest"
    url="$(curl -fsSL "${api}" \
      | grep '"tarball_url"' \
      | head -1 \
      | sed 's/.*"tarball_url": *"\([^"]*\)".*/\1/')"
    [[ -n "${url}" ]] || die "fetch_release" "Could not parse tarball URL from ${api}"
  fi

  info "Fetching ${url}"
  curl -fsSL "${url}" -o "${STAGE}/src.tar.gz" \
    || die "fetch_release" "Download failed: ${url}"

  mkdir -p "${STAGE}/src"
  tar -xzf "${STAGE}/src.tar.gz" -C "${STAGE}/src" \
    || die "fetch_release" "Failed to extract tarball"

  local -a srcdirs
  # shellcheck disable=SC2206
  srcdirs=( "${STAGE}"/src/*/ )
  [[ ${#srcdirs[@]} -eq 1 && -d "${srcdirs[0]}" ]] \
    || die "fetch_release" "Unexpected tarball layout — expected one top-level dir"
  # shellcheck disable=SC2034
  SRCROOT="${srcdirs[0]}"
}

# ---------- main ----------
case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac
# shellcheck disable=SC2034
INSTALL_ROOT="${1:-${HOME}/ai-podman-jails}"

check_prereqs
fetch_release
