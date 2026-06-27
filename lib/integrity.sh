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

# ---- M3: enumerate and compare ---------------------------------------------

declare -A _ic_missing=()
declare -A _ic_unexpected=()
declare -A _ic_mismatch=()
declare -A _ic_ok=()
# _ic_mismatch values: "expected=<hash>  actual=<hash>"

_ic_enumerate_installed() {
    local f rel
    while IFS= read -r -d '' f; do
        rel="${f#"${AI_PODMAN_JAILS_DIR}/"}"
        _ic_installed_files["${rel}"]=1
    done < <(find -L "${AI_PODMAN_JAILS_DIR}/bin" "${AI_PODMAN_JAILS_DIR}/lib" \
                 -type f -print0 2>/dev/null)
}

compare_files() {
    declare -gA _ic_installed_files=()
    _ic_enumerate_installed

    local rel exp_hash act_hash
    for rel in "${!_ic_manifest[@]}"; do
        exp_hash="${_ic_manifest[${rel}]}"
        if [[ -z "${_ic_installed_files[${rel}]+x}" ]]; then
            _ic_missing["${rel}"]="${exp_hash}"
        else
            act_hash="$(sha256sum "${AI_PODMAN_JAILS_DIR}/${rel}" | awk '{print $1}')"
            if [[ "${act_hash}" == "${exp_hash}" ]]; then
                _ic_ok["${rel}"]="${exp_hash}"
            else
                _ic_mismatch["${rel}"]="expected=${exp_hash}  actual=${act_hash}"
            fi
        fi
    done

    for rel in "${!_ic_installed_files[@]}"; do
        if [[ -z "${_ic_manifest[${rel}]+x}" ]]; then
            _ic_unexpected["${rel}"]=1
        fi
    done
}

# ---- M4: output modes -------------------------------------------------------

print_exceptions() {
    local rel found=0
    for rel in "${!_ic_missing[@]}"; do
        echo "MISSING   ${rel}"
        found=1
    done
    for rel in "${!_ic_unexpected[@]}"; do
        echo "UNEXPECTED ${rel}"
        found=1
    done
    for rel in "${!_ic_mismatch[@]}"; do
        echo "MODIFIED  ${rel}  ${_ic_mismatch[${rel}]}"
        found=1
    done
    if [[ "${found}" -eq 0 ]]; then
        echo "all files OK"
        return 0
    fi
    return 1
}

print_verbose() {
    local rel hash
    declare -A _all=()
    for rel in "${!_ic_ok[@]}"         ; do _all["${rel}"]=ok        ; done
    for rel in "${!_ic_mismatch[@]}"   ; do _all["${rel}"]=mismatch  ; done
    for rel in "${!_ic_missing[@]}"    ; do _all["${rel}"]=missing   ; done
    for rel in "${!_ic_unexpected[@]}" ; do _all["${rel}"]=unexpected ; done

    printf '%-12s\t%-40s\t%-64s\t%s\n' STATUS FILE EXPECTED ACTUAL
    while IFS= read -r rel; do
        case "${_all[${rel}]}" in
            ok)
                hash="${_ic_ok[${rel}]}"
                printf '%-12s\t%-40s\t%-64s\t%s\n' OK "${rel}" "${hash}" "${hash}"
                ;;
            mismatch)
                local exp act
                exp="${_ic_mismatch[${rel}]#expected=}"; exp="${exp%%  *}"
                act="${_ic_mismatch[${rel}]##*actual=}"
                printf '%-12s\t%-40s\t%-64s\t%s\n' MODIFIED "${rel}" "${exp}" "${act}"
                ;;
            missing)
                printf '%-12s\t%-40s\t%-64s\t%s\n' MISSING "${rel}" "${_ic_missing[${rel}]}" "-"
                ;;
            unexpected)
                printf '%-12s\t%-40s\t%-64s\t%s\n' UNEXPECTED "${rel}" "-" "-"
                ;;
        esac
    done < <(printf '%s\n' "${!_all[@]}" | sort)
}

print_diffs() {
    local rel
    for rel in "${!_ic_mismatch[@]}"; do
        diff -u \
            --label "a/${rel}" \
            --label "b/${rel}" \
            "${_ic_tmpdir}/${INNER}/${rel}" \
            "${AI_PODMAN_JAILS_DIR}/${rel}" || true
    done
}
