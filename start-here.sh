#!/usr/bin/env bash
# start-here.sh — Agent-primed bootstrap container entrypoint.
# Placed at /start-here.sh inside the bootstrap container by the ai-new launcher.
# Reads runtime metadata only from the pinned bootstrap/agent.env (never source/eval).
set -euo pipefail

BOOTSTRAP_DIR="/project/bootstrap"
AGENT_ENV="${BOOTSTRAP_DIR}/agent.env"

# ── Usage ─────────────────────────────────────────────────────────────────────

_usage() {
    cat >&2 <<'USAGE_EOF'
Usage: start-here.sh [--agent <agent>] [--resume] [-h|--help]

Start the agent-primed bootstrap session inside the bootstrap container.
Reads runtime metadata from /project/bootstrap/agent.env.

Options:
  --agent <agent>   Override the pinned agent runtime.
  --resume          Resume an interrupted session; never re-prompts for runtime.
  -h, --help        Show this help and exit.

This script is run inside the ai-new bootstrap container.  Do not execute it
on the host; it expects /project to be the mounted project directory.
USAGE_EOF
}

# ── Argument parsing ──────────────────────────────────────────────────────────

AGENT_OVERRIDE=""
RESUME=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            _usage; exit 0 ;;
        --agent)
            [[ $# -ge 2 ]] || { echo "[ERROR] --agent requires an argument" >&2; exit 1; }
            AGENT_OVERRIDE="$2"; shift 2 ;;
        --agent=*)
            AGENT_OVERRIDE="${1#--agent=}"; shift ;;
        --resume)
            RESUME=1; shift ;;
        -*)
            echo "[ERROR] Unknown flag: $1.  Try 'start-here.sh --help'." >&2; exit 1 ;;
        *)
            echo "[ERROR] Unexpected argument: $1.  Try 'start-here.sh --help'." >&2; exit 1 ;;
    esac
done

# ── Restricted agent.env parser (never source/eval) ──────────────────────────

export AGENT_NAME=""
export AGENT_COMMAND=""
export AGENT_CONFIG_DIRS=""
export AGENT_ENV_VARS=""
export AGENT_PROMPT_MODE=""
export AGENT_INSTALL_ADAPTER=""
export AGENT_INSTALL_PACKAGE=""
export AGENT_INSTALL_VERSION=""
export AGENT_AUTH_CHECK_ARGV=""

_parse_agent_env() {
    local _path="$1"
    if [[ ! -f "$_path" ]]; then
        echo "[ERROR] Missing pinned agent registry: ${_path}" >&2
        echo "        The bootstrap container requires a project created with 'ai-new <name> --agent <agent>'." >&2
        exit 1
    fi

    local _line _key _val
    while IFS= read -r _line || [[ -n "$_line" ]]; do
        _line="${_line%%#*}"
        # ltrim
        while [[ "${_line:0:1}" == ' ' || "${_line:0:1}" == $'\t' ]]; do
            _line="${_line:1}"
        done
        [[ -z "$_line" ]] && continue
        [[ "$_line" == *=* ]] || continue
        _key="${_line%%=*}"
        _val="${_line#*=}"
        # Strip surrounding quotes.
        if [[ "$_val" == '"'*'"' ]]; then
            _val="${_val#'"'}"; _val="${_val%'"'}"
        elif [[ "$_val" == "'"*"'" ]]; then
            _val="${_val#"'"}"; _val="${_val%"'"}"
        fi
        case "$_key" in
            AGENT_NAME)             AGENT_NAME="$_val" ;;
            AGENT_COMMAND)          AGENT_COMMAND="$_val" ;;
            AGENT_CONFIG_DIRS)      AGENT_CONFIG_DIRS="$_val" ;;
            AGENT_ENV_VARS)         AGENT_ENV_VARS="$_val" ;;
            AGENT_PROMPT_MODE)      AGENT_PROMPT_MODE="$_val" ;;
            AGENT_INSTALL_ADAPTER)  AGENT_INSTALL_ADAPTER="$_val" ;;
            AGENT_INSTALL_PACKAGE)  AGENT_INSTALL_PACKAGE="$_val" ;;
            AGENT_INSTALL_VERSION)  AGENT_INSTALL_VERSION="$_val" ;;
            AGENT_AUTH_CHECK_ARGV)  AGENT_AUTH_CHECK_ARGV="$_val" ;;
        esac
    done < "$_path"
}

_parse_agent_env "$AGENT_ENV"

# ── Runtime resolution ────────────────────────────────────────────────────────
# R4.3 / D4: selected > single > fail-on-zero > fail-on-multiple.
# On --resume never re-prompt.

RESOLVED_AGENT=""
RESOLVED_COMMAND=""

_resolve_runtime() {
    if [[ -n "$AGENT_OVERRIDE" ]]; then
        RESOLVED_AGENT="$AGENT_OVERRIDE"
        RESOLVED_COMMAND="$AGENT_COMMAND"
        return 0
    fi

    if [[ "$RESUME" -eq 1 ]]; then
        # Resume: use the pinned runtime; never re-prompt.
        if [[ -z "$AGENT_NAME" ]]; then
            echo "[ERROR] Cannot resume: no agent runtime in ${AGENT_ENV}." >&2
            exit 1
        fi
        RESOLVED_AGENT="$AGENT_NAME"
        RESOLVED_COMMAND="$AGENT_COMMAND"
        return 0
    fi

    # Zero runtimes configured.
    if [[ -z "$AGENT_NAME" ]]; then
        echo "[ERROR] No agent runtime is configured in ${AGENT_ENV}." >&2
        echo "        Create the project with 'ai-new <name> --agent <agent>'." >&2
        exit 1
    fi

    # Exactly one pinned runtime — use it.
    RESOLVED_AGENT="$AGENT_NAME"
    RESOLVED_COMMAND="$AGENT_COMMAND"
}

_resolve_runtime

[[ -n "$RESOLVED_AGENT" ]] || {
    echo "[ERROR] Could not resolve agent runtime.  Rerun with '--agent <agent>'." >&2
    exit 1
}

echo "[INFO]  Bootstrap: resolved runtime '${RESOLVED_AGENT}' (command: ${RESOLVED_COMMAND})"
