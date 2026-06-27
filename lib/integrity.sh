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
