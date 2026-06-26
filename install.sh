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

# ---------- milestone 4: select managed set & atomic swap ----------
WAS_UPDATE=0

install_files() {
  local managed item
  managed=(bin lib config templates prompts start-here.sh)

  # Stage final layout in $STAGE/out
  mkdir -p "${STAGE}/out"
  for item in "${managed[@]}"; do
    [[ -e "${SRCROOT}${item}" ]] || continue
    cp -a "${SRCROOT}${item}" "${STAGE}/out/${item}"
  done

  # profiles: only *.example files
  if [[ -d "${SRCROOT}profiles" ]]; then
    mkdir -p "${STAGE}/out/profiles"
    find "${SRCROOT}profiles" -maxdepth 1 -name '*.example' \
      -exec cp {} "${STAGE}/out/profiles/" \;
  fi

  # Detect update vs fresh install
  if [[ -d "${INSTALL_ROOT}/bin" ]]; then
    # shellcheck disable=SC2034
    WAS_UPDATE=1
  fi

  mkdir -p "${INSTALL_ROOT}"

  # Atomic per-dir swap: stage to <dir>.new, then mv -T
  for item in "${managed[@]}"; do
    [[ -e "${STAGE}/out/${item}" ]] || continue
    if [[ -d "${STAGE}/out/${item}" ]]; then
      rm -rf "${INSTALL_ROOT}/${item}.new"
      cp -a "${STAGE}/out/${item}" "${INSTALL_ROOT}/${item}.new"
      mv -T "${INSTALL_ROOT}/${item}.new" "${INSTALL_ROOT}/${item}"
    else
      cp -a "${STAGE}/out/${item}" "${INSTALL_ROOT}/${item}"
    fi
  done

  # profiles/*.example — cp -n to never overwrite hand-authored *.env
  if [[ -d "${STAGE}/out/profiles" ]]; then
    mkdir -p "${INSTALL_ROOT}/profiles"
    find "${STAGE}/out/profiles" -maxdepth 1 -name '*.example' \
      -exec cp -n {} "${INSTALL_ROOT}/profiles/" \;
  fi

  chmod +x "${INSTALL_ROOT}"/bin/* "${INSTALL_ROOT}/start-here.sh"
}

# ---------- milestone 5: owned, idempotent env file ----------
write_env_file() {
  local env_file="${HOME}/.bashrc.d/podbuilder.sh"
  mkdir -p "${HOME}/.bashrc.d"
  # Overwrite whole file each run — prevents duplicate blocks on re-runs (R5.3)
  cat >"${env_file}" <<EOF
# Managed by ai-podbuilder install.sh — safe to delete.
export AI_PODMAN_JAILS_DIR="${INSTALL_ROOT}"
export PATH="${INSTALL_ROOT}/bin:\${PATH}"
EOF
  info "Env file: ${env_file}"
}

# ---------- main ----------
case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac
INSTALL_ROOT="${1:-${HOME}/ai-podman-jails}"

check_prereqs
fetch_release
install_files
write_env_file
