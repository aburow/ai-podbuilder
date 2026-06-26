#!/usr/bin/env bash
# Milestone 2 — Ordered, idempotent release flow
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="aburow/ai-podbuilder"
SKIP_NETWORK="${RELEASE_SKIP_NETWORK:-0}"

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

# ---- step: verify_asset (Milestone 3) ---------------------------------------

verify_asset() {
  local version="${1}"
  local name size state

  info "verify_asset: checking install.sh asset on release ${version}"

  local assets_json
  assets_json="$(gh release view "${version}" --repo "${REPO}" --json assets --jq '.assets')"

  name="$(printf '%s' "${assets_json}" | jq -r '.[] | select(.name == "install.sh") | .name')"
  [[ "${name}" == "install.sh" ]] \
    || die "verify_asset" "no install.sh asset on release ${version}"

  state="$(printf '%s' "${assets_json}" | jq -r '.[] | select(.name == "install.sh") | .state')"
  [[ "${state}" == "uploaded" ]] \
    || die "verify_asset" "install.sh asset on release ${version} is in state '${state}', expected 'uploaded'"

  size="$(printf '%s' "${assets_json}" | jq -r '.[] | select(.name == "install.sh") | .size')"
  [[ "${size}" -gt 0 ]] \
    || die "verify_asset" "install.sh asset on release ${version} has size 0"

  info "verify_asset: OK — install.sh (${size} bytes, state=${state})"
}

# ---- step: verify_public_url (Milestone 4) ----------------------------------

verify_public_url() {
  local url="https://github.com/${REPO}/releases/latest/download/install.sh"

  if [[ "${SKIP_NETWORK}" == "1" ]]; then
    printf 'WARNING: public URL verification SKIPPED (RELEASE_SKIP_NETWORK=1) — release is NOT fully verified\n' >&2
    return 0
  fi

  info "verify_public_url: checking ${url}"

  local http_code
  http_code="$(curl -sI -L -o /dev/null -w '%{http_code}' "${url}")"

  [[ "${http_code}" == "200" ]] \
    || die "verify_public_url" "public URL returned HTTP ${http_code} for ${url}"

  info "verify_public_url: OK — ${url} returned HTTP 200"
}

# ---- step: verify_content (Milestone 4) -------------------------------------

verify_content() {
  local url="https://github.com/${REPO}/releases/latest/download/install.sh"

  if [[ "${SKIP_NETWORK}" == "1" ]]; then
    printf 'WARNING: content verification SKIPPED (RELEASE_SKIP_NETWORK=1) — release is NOT fully verified\n' >&2
    return 0
  fi

  info "verify_content: downloading and inspecting ${url}"

  local tmp
  tmp="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '${tmp}'" RETURN

  curl -fsSL "${url}" -o "${tmp}" \
    || die "verify_content" "failed to download ${url}"

  local first_line
  first_line="$(head -1 "${tmp}")"
  [[ "${first_line}" == "#!/usr/bin/env bash" ]] \
    || die "verify_content" "unexpected first line: ${first_line}"

  grep -q 'REPO="aburow/ai-podbuilder"' "${tmp}" \
    || die "verify_content" "stable marker REPO=\"aburow/ai-podbuilder\" not found in downloaded script"

  info "verify_content: OK — valid shebang and known marker present"
  info "verify_content: first 5 lines:"
  head -5 "${tmp}"
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
  verify_asset "${version}"
  verify_public_url
  verify_content

  info "Release ${version} created, asset uploaded and fully verified"
}

main "$@"
