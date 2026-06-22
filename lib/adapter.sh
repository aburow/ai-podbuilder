#!/usr/bin/env bash
# Install adapter contract for ai-new (R13.12, R3.4). Source; do not execute.
# Requires common.sh, registry.sh.

# build_argv <adapter> <package> <version>
# Outputs each element of the install argv on a separate line.
# No shell interpolation of registry strings (R13.4).
build_argv() {
    local _adapter="$1"
    local _package="$2"
    local _version="${3:-}"

    local _pkg_ver="${_package}"
    [[ -n "$_version" ]] && _pkg_ver="${_package}@${_version}"

    case "$_adapter" in
        npm-global)
            printf '%s\n' npm install -g "$_pkg_ver" ;;
        pipx)
            if [[ -n "$_version" ]]; then
                printf '%s\n' pipx install "${_package}==${_version}"
            else
                printf '%s\n' pipx install "$_package"
            fi
            ;;
        dnf-package)
            if [[ -n "$_version" ]]; then
                printf '%s\n' dnf install -y "${_package}-${_version}"
            else
                printf '%s\n' dnf install -y "$_package"
            fi
            ;;
        preinstalled|manual)
            # No install action.
            ;;
        *)
            _die "Unknown install adapter: ${_adapter}" ;;
    esac
}

# run_install_adapter <adapter> <package> <version>
# Executes the install command for the given adapter via an explicit argv array
# (never via shell -c or eval). preinstalled/manual are no-ops.
run_install_adapter() {
    local _adapter="$1"
    local _package="$2"
    local _version="${3:-}"

    case "$_adapter" in
        preinstalled|manual)
            _info "Adapter '${_adapter}': no install action required."
            return 0 ;;
    esac

    # Build the argv list.
    local _argv=()
    while IFS= read -r _word; do
        [[ -n "$_word" ]] && _argv+=("$_word")
    done < <(build_argv "$_adapter" "$_package" "$_version")

    [[ "${#_argv[@]}" -gt 0 ]] || _die "Empty install argv for adapter '${_adapter}'"

    _info "Installing via ${_adapter}: ${_argv[*]}"
    "${_argv[@]}"
}
