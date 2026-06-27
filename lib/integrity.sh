#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# 2026 - Anthony Burow - https://github.com/aburow
# Integrity-check library for ai-pod-doctor. Sourced, not executed directly.

# shellcheck disable=SC2034
REPO="aburow/ai-podbuilder"

_ic_tmpdir=""
_ic_setup_tmpdir() {
    _ic_tmpdir="$(mktemp -d)"
    trap '_ic_cleanup' EXIT
}
_ic_cleanup() { [[ -n "${_ic_tmpdir}" ]] && rm -rf "${_ic_tmpdir}"; }

# shellcheck disable=SC2034
VERSION=""

detect_version() {
    local vfile="${AI_PODMAN_JAILS_DIR}/VERSION"
    [[ -f "${vfile}" ]] || { echo "ERROR: no version marker at ${vfile}; reinstall required" >&2; exit 3; }
    VERSION="$(<"${vfile}")"
    [[ -n "${VERSION}" ]] || { echo "ERROR: VERSION file is empty; reinstall required" >&2; exit 3; }
}

# ---- M2: tarball fetch and manifest ----------------------------------------

# shellcheck disable=SC2034
TARBALL_URL=""
# shellcheck disable=SC2034
INNER=""
declare -A _ic_manifest=()

fetch_tarball() {
    TARBALL_URL="https://github.com/${REPO}/archive/refs/tags/v${VERSION}.tar.gz"
    if ! curl -fsSL "${TARBALL_URL}" -o "${_ic_tmpdir}/release.tgz"; then
        echo "ERROR: failed to fetch tarball from ${TARBALL_URL}" >&2
        exit 2
    fi
}

build_manifest() {
    INNER="$(tar tzf "${_ic_tmpdir}/release.tgz" | head -1 | cut -d/ -f1)"
    tar xzf "${_ic_tmpdir}/release.tgz" -C "${_ic_tmpdir}"
    while IFS= read -r -d '' f; do
        local rel
        rel="${f#"${_ic_tmpdir}/${INNER}/"}"
        _ic_manifest["${rel}"]="$(sha256sum "${f}" | awk '{print $1}')"
    done < <(find "${_ic_tmpdir}/${INNER}/bin" "${_ic_tmpdir}/${INNER}/lib" \
                 -type f -print0 2>/dev/null)
}
