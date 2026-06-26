#!/usr/bin/env bash
# Milestone 2 — Ordered, idempotent release flow
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="aburow/ai-podbuilder"

# ---- helpers ----------------------------------------------------------------

die() {
  printf 'ERROR [%s]: %s\n' "${1}" "${2}" >&2
  exit 1
}

info() {
  printf '==> %s\n' "${*}"
}

# ---- version ----------------------------------------------------------------

load_version() {
  local v
  v="$(<"${REPO_ROOT}/VERSION")"
  v="${v//[[:space:]]/}"
  [[ -n "${v}" ]] || die "load_version" "VERSION file is empty"
  [[ "${v}" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] \
    || die "load_version" "VERSION '${v}' does not match expected pattern (e.g. 1.2 or 1.2.3)"
  printf '%s' "${v}"
}

# ---- step: create_tag -------------------------------------------------------

create_tag() {
  local version="${1}"
  local head_sha
  head_sha="$(git -C "${REPO_ROOT}" rev-parse HEAD)"

  if git -C "${REPO_ROOT}" rev-parse --verify --quiet "refs/tags/${version}" >/dev/null 2>&1; then
    local tag_sha
    tag_sha="$(git -C "${REPO_ROOT}" rev-list -n1 "refs/tags/${version}")"
    if [[ "${tag_sha}" == "${head_sha}" ]]; then
      info "create_tag: tag ${version} already exists at HEAD — continuing (idempotent)"
      return 0
    fi
    die "create_tag" \
      "tag ${version} exists but points to ${tag_sha}, not HEAD ${head_sha}"
  fi

  info "create_tag: creating annotated tag ${version}"
  git -C "${REPO_ROOT}" tag -a "${version}" -m "Release ${version}"
  git -C "${REPO_ROOT}" push origin "refs/tags/${version}"
}

# ---- step: create_release ---------------------------------------------------

create_release() {
  local version="${1}"

  if gh release view "${version}" --repo "${REPO}" >/dev/null 2>&1; then
    info "create_release: release ${version} already exists — skipping creation (idempotent)"
    return 0
  fi

  info "create_release: creating GitHub release ${version}"
  gh release create "${version}" \
    --repo "${REPO}" \
    --title "Release ${version}" \
    --notes "Release ${version}"
}

# ---- step: upload_asset -----------------------------------------------------

upload_asset() {
  local version="${1}"
  local asset="${REPO_ROOT}/install.sh"

  [[ -f "${asset}" ]] \
    || die "upload_asset" "install.sh not found at ${asset}"

  info "upload_asset: uploading install.sh to release ${version}"
  gh release upload "${version}" "${asset}" \
    --repo "${REPO}" \
    --clobber
}

# ---- main -------------------------------------------------------------------

main() {
  local version
  version="$(load_version)"

  if [[ -n "${GIT_TAG:-}" && "${GIT_TAG}" != "${version}" ]]; then
    die "main" "pushed tag '${GIT_TAG}' does not match VERSION '${version}'"
  fi

  info "Starting release flow for version ${version}"

  create_tag "${version}"
  create_release "${version}"
  upload_asset "${version}"

  info "Release ${version} created and asset uploaded"
}

main "$@"
