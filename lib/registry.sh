#!/usr/bin/env bash
# Registry parser, validator, hasher, and pinner for ai-new.
# Source this file; do not execute directly. Requires common.sh.

# Known registry keys (all others are silently ignored).
_REGISTRY_KNOWN_KEYS=(
    AGENT_NAME AGENT_COMMAND AGENT_CONFIG_DIRS AGENT_ENV_VARS
    AGENT_PROMPT_MODE AGENT_INSTALL_ADAPTER AGENT_INSTALL_PACKAGE
    AGENT_INSTALL_VERSION AGENT_AUTH_CHECK_ARGV AGENT_REGISTRY_VERSION
)

# Valid install adapters (v1).
_VALID_INSTALL_ADAPTERS=(npm-global pipx dnf-package preinstalled manual)

# split_multi <value>
# Splits a colon-separated quoted string into an array named _SPLIT_RESULT.
split_multi() {
    local _raw="$1"
    IFS=':' read -r -a _SPLIT_RESULT <<< "$_raw"
}

# _is_known_key <key>
_is_known_key() {
    local _k="$1"
    local _known
    for _known in "${_REGISTRY_KNOWN_KEYS[@]}"; do
        [[ "$_known" == "$_k" ]] && return 0
    done
    return 1
}

# parse_registry_file <path>
# Parses a registry .env file key-by-key (never source/eval).
# Sets global variables: REG_AGENT_NAME, REG_AGENT_COMMAND, REG_AGENT_CONFIG_DIRS,
# REG_AGENT_ENV_VARS, REG_AGENT_PROMPT_MODE, REG_AGENT_INSTALL_ADAPTER,
# REG_AGENT_INSTALL_PACKAGE, REG_AGENT_INSTALL_VERSION,
# REG_AGENT_AUTH_CHECK_ARGV, REG_AGENT_REGISTRY_VERSION.
parse_registry_file() {
    local _path="$1"
    [[ -f "$_path" ]] || _die "Registry file not found: ${_path}"

    # Reset all registry globals (exported so callers that source this lib can read them).
    export REG_AGENT_NAME=""
    export REG_AGENT_COMMAND=""
    export REG_AGENT_CONFIG_DIRS=""
    export REG_AGENT_ENV_VARS=""
    export REG_AGENT_PROMPT_MODE=""
    export REG_AGENT_INSTALL_ADAPTER=""
    export REG_AGENT_INSTALL_PACKAGE=""
    export REG_AGENT_INSTALL_VERSION=""
    export REG_AGENT_AUTH_CHECK_ARGV=""
    export REG_AGENT_REGISTRY_VERSION=""

    local _line _key _val
    while IFS= read -r _line || [[ -n "$_line" ]]; do
        # Strip comments and blank lines.
        _line="${_line%%#*}"
        _line="${_line#"${_line%%[! ]*}"}"   # ltrim
        [[ -z "$_line" ]] && continue

        # Must be KEY=VALUE form; reject anything else.
        [[ "$_line" == *=* ]] || continue
        _key="${_line%%=*}"
        _val="${_line#*=}"

        # Strip surrounding quotes (single or double) from value.
        if [[ "$_val" == '"'*'"' ]]; then
            _val="${_val#'"'}"; _val="${_val%'"'}"
        elif [[ "$_val" == "'"*"'" ]]; then
            _val="${_val#"'"}"; _val="${_val%"'"}"
        fi

        _is_known_key "$_key" || continue

        # shellcheck disable=SC2034
        case "$_key" in
            AGENT_NAME)             REG_AGENT_NAME="$_val" ;;
            AGENT_COMMAND)          REG_AGENT_COMMAND="$_val" ;;
            AGENT_CONFIG_DIRS)      REG_AGENT_CONFIG_DIRS="$_val" ;;
            AGENT_ENV_VARS)         REG_AGENT_ENV_VARS="$_val" ;;
            AGENT_PROMPT_MODE)      REG_AGENT_PROMPT_MODE="$_val" ;;
            AGENT_INSTALL_ADAPTER)  REG_AGENT_INSTALL_ADAPTER="$_val" ;;
            AGENT_INSTALL_PACKAGE)  REG_AGENT_INSTALL_PACKAGE="$_val" ;;
            AGENT_INSTALL_VERSION)  REG_AGENT_INSTALL_VERSION="$_val" ;;
            AGENT_AUTH_CHECK_ARGV)  REG_AGENT_AUTH_CHECK_ARGV="$_val" ;;
            AGENT_REGISTRY_VERSION) REG_AGENT_REGISTRY_VERSION="$_val" ;;
        esac
    done < "$_path"
}

# validate_adapters
# Validates REG_AGENT_INSTALL_ADAPTER against the v1 fixed set.
validate_adapters() {
    local _adapter="$1"
    local _valid
    for _valid in "${_VALID_INSTALL_ADAPTERS[@]}"; do
        [[ "$_valid" == "$_adapter" ]] && return 0
    done
    _die "Unknown install adapter '${_adapter}'. Valid adapters: ${_VALID_INSTALL_ADAPTERS[*]}"
}

# list_registered_agents
# Enumerates config/agents.d/*.env and echoes each agent name (one per line).
list_registered_agents() {
    local _agents_dir="${CODEX_AGENTS_DIR:-${CODEX_JAILS_DIR}/config/agents.d}"
    local _f _base
    shopt -s nullglob
    local _found=0
    for _f in "${_agents_dir}"/*.env; do
        _base="$(basename "$_f" .env)"
        echo "$_base"
        _found=1
    done
    shopt -u nullglob
    return 0
}

# validate_agent <name>
# Validates that the named agent has a registry file and its adapter is valid.
validate_agent() {
    local _agent="$1"
    local _agents_dir="${CODEX_AGENTS_DIR:-${CODEX_JAILS_DIR}/config/agents.d}"
    local _reg_file="${_agents_dir}/${_agent}.env"
    if [[ ! -f "$_reg_file" ]]; then
        local _registered
        _registered="$(list_registered_agents | tr '\n' ' ')"
        _die "Unknown agent '${_agent}'. Registered agents: ${_registered:-none}"
    fi
    parse_registry_file "$_reg_file"
    validate_adapters "$REG_AGENT_INSTALL_ADAPTER"
}

# normalize_registry <path>
# Outputs the normalized registry text to stdout.
# Normalization: CRLF/CR→LF; strip trailing whitespace per line;
# preserve comments/key order/interior blank lines; remove trailing blank lines;
# ensure exactly one trailing newline.
normalize_registry() {
    local _path="$1"
    [[ -f "$_path" ]] || _die "Registry file not found: ${_path}"
    # Use awk for reliable normalization without subshell nesting issues.
    LC_ALL=C awk '
    BEGIN { trailing_blanks = 0 }
    {
        # Strip CR
        gsub(/\r/, "")
        # Strip trailing whitespace
        sub(/[[:space:]]+$/, "")
        if ($0 == "") {
            trailing_blanks++
        } else {
            for (i = 0; i < trailing_blanks; i++) print ""
            trailing_blanks = 0
            print
        }
    }
    END { print "" }
    ' "$_path"
}

# registry_hash <path>
# Outputs the SHA-256 hex digest of the normalized registry text.
registry_hash() {
    local _path="$1"
    normalize_registry "$_path" | sha256sum | awk '{print $1}'
}

# pin_registry <agent> <project_root>
# Copies the selected agent registry entry to <project_root>/bootstrap/agent.env,
# annotated with provenance metadata.
pin_registry() {
    local _agent="$1"
    local _project_root="$2"
    local _agents_dir="${CODEX_AGENTS_DIR:-${CODEX_JAILS_DIR}/config/agents.d}"
    local _src="${_agents_dir}/${_agent}.env"
    local _dst="${_project_root}/bootstrap/agent.env"
    local _bootstrap_dir="${_project_root}/bootstrap"

    [[ -f "$_src" ]] || _die "Registry file not found: ${_src}"
    mkdir -p "$_bootstrap_dir"

    local _hash _ts
    _hash="$(registry_hash "$_src")"
    _ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    parse_registry_file "$_src"

    {
        printf '# Pinned agent registry entry\n'
        printf '# source_path=%s\n' "$_src"
        printf '# agent_name=%s\n' "$_agent"
        printf '# registry_version=%s\n' "${REG_AGENT_REGISTRY_VERSION:-}"
        printf '# source_hash=%s\n' "$_hash"
        printf '# pinned_at=%s\n' "$_ts"
        cat "$_src"
    } > "${_dst}.tmp"
    mv "${_dst}.tmp" "$_dst"
}
