#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# 2026 - Anthony Burow - https://github.com/aburow
# start-here.sh — Agent-primed bootstrap container entrypoint.
# Placed at /project/bootstrap/home/start-here.sh inside the bootstrap container by the ai-new launcher.
# Reads runtime metadata only from the pinned bootstrap/agent.env (never source/eval).
set -euo pipefail

BOOTSTRAP_DIR="/project/bootstrap"
AGENT_ENV="${BOOTSTRAP_DIR}/agent.env"

# ── Usage ─────────────────────────────────────────────────────────────────────

_usage() {
    cat >&2 <<'USAGE_EOF'
Usage: ./start-here.sh [--agent <agent>] [--resume] [--shell-on-exit] [-h|--help]
   or: /project/bootstrap/home/start-here.sh [options]

Start the agent-primed bootstrap session inside the ai-new bootstrap container.
Reads runtime metadata from /project/bootstrap/agent.env (never source/eval).

The script is directly executable (no 'bash' prefix needed). ai-new invokes it
automatically as the bootstrap container entrypoint.

Options:
  --agent <agent>   Override the pinned agent runtime.
                    Valid if multiple runtimes are installed and the default
                    is not what you want.
  --resume          Resume an interrupted bootstrap session.
                    Never re-prompts for the agent runtime.
  --shell-on-exit   Open interactive Bash in this container if the launcher or
                    selected agent exits. Type 'exit' to leave the container.
  -h, --help        Show this help and exit (zero).

Environment:
  /project/bootstrap/agent.env        Pinned agent registry (required).
  /project/bootstrap/agent.env.local  Bootstrap-time API keys (optional, gitignored).
  /project/bootstrap/session.json     Session state (status, generated files).

This script is designed to be run inside the bootstrap container created by
'ai-new'. The selected agent is installed while the Containerfile is built;
this script validates that baked runtime and launches it with the prompt.

If the bootstrap session was interrupted, re-enter the container with:
  ai-new <name> --resume
USAGE_EOF
}

# ── Argument parsing ──────────────────────────────────────────────────────────

AGENT_OVERRIDE=""
RESUME=0
SHELL_ON_EXIT=0

_shell_on_exit() {
    local _rc=$?
    local _fallback_shell="${AI_NEW_FALLBACK_SHELL:-/bin/bash}"
    trap - EXIT
    echo "" >&2
    echo "[WARN]  Bootstrap process exited with status ${_rc}." >&2
    echo "[INFO]  Opening interactive Bash inside the bootstrap container." >&2
    echo "[INFO]  Agent exit status is available as AI_NEW_AGENT_EXIT_STATUS." >&2
    echo "[INFO]  Type 'exit' to leave the container." >&2
    export AI_NEW_AGENT_EXIT_STATUS="$_rc"
    exec "$_fallback_shell" -i
}

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
        --shell-on-exit)
            SHELL_ON_EXIT=1
            trap _shell_on_exit EXIT
            shift ;;
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
export AGENT_MODEL=""
export AGENT_EFFORT=""
export AGENT_APPROVAL=""

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
            AGENT_MODEL)            AGENT_MODEL="$_val" ;;
            AGENT_EFFORT)           AGENT_EFFORT="$_val" ;;
            AGENT_APPROVAL)         AGENT_APPROVAL="$_val" ;;
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

# ── Credential loading (R10.2) ────────────────────────────────────────────────
# Source order: (1) persisted agent config dirs under bootstrap/home are on PATH
# already (agent-specific dotfiles); (2) agent.env.local for API-key env vars;
# (3) interactive CLI login if AGENT_PROMPT_MODE supports it.

AGENT_ENV_LOCAL="${BOOTSTRAP_DIR}/agent.env.local"

_load_env_local() {
    [[ -f "$AGENT_ENV_LOCAL" ]] || return 0
    [[ -z "$AGENT_ENV_VARS" ]] && return 0
    # Split AGENT_ENV_VARS (colon-separated) and load named vars from agent.env.local.
    local _var _val _line
    IFS=':' read -r -a _env_var_names <<< "$AGENT_ENV_VARS"
    for _var in "${_env_var_names[@]}"; do
        [[ -n "$_var" ]] || continue
        while IFS= read -r _line || [[ -n "$_line" ]]; do
            _line="${_line%%#*}"
            while [[ "${_line:0:1}" == ' ' || "${_line:0:1}" == $'\t' ]]; do
                _line="${_line:1}"
            done
            [[ "$_line" == "${_var}="* ]] || continue
            _val="${_line#*=}"
            if [[ "$_val" == '"'*'"' ]]; then
                _val="${_val#'"'}"; _val="${_val%'"'}"
            elif [[ "$_val" == "'"*"'" ]]; then
                _val="${_val#"'"}"; _val="${_val%"'"}"
            fi
            export "${_var}=${_val}"
            break
        done < "$AGENT_ENV_LOCAL"
    done
}

_load_env_local

# ── Authentication / runtime-presence validation (R4.4, R10, AC6) ─────────────

_validate_runtime() {
    local _cmd="$RESOLVED_COMMAND"

    # The image build must have installed the selected command.
    if [[ -z "$AGENT_AUTH_CHECK_ARGV" ]]; then
        if ! command -v "$_cmd" >/dev/null 2>&1; then
            echo "[ERROR] Agent runtime '${RESOLVED_AGENT}' (command: ${_cmd}) is not installed in the bootstrap image." >&2
            echo "        The selected agent must be installed by bootstrap/Containerfile.bootstrap." >&2
            echo "        Exit and rerun 'ai-new <name> --resume' to rebuild the image." >&2
            exit 1
        fi
        return 0
    fi

    # Split pipe-delimited auth-check argv into an array (no shell interpolation).
    local _auth_argv=()
    local _token
    IFS='|' read -r -a _auth_argv <<< "$AGENT_AUTH_CHECK_ARGV"

    if [[ "${#_auth_argv[@]}" -eq 0 ]]; then
        echo "[WARN]  Empty auth-check argv; skipping credential validation." >&2
        return 0
    fi

    # Run auth check via explicit argv (R13.12 — no shell interpolation).
    if ! "${_auth_argv[@]}" >/dev/null 2>&1; then
        echo "[ERROR] Agent runtime '${RESOLVED_AGENT}' failed authentication/version check." >&2
        echo "        Command attempted: ${_auth_argv[*]}" >&2
        if [[ -n "$AGENT_ENV_VARS" ]]; then
            echo "" >&2
            echo "        Required API key variable(s): ${AGENT_ENV_VARS//:/ }" >&2
            echo "        Add them to: ${AGENT_ENV_LOCAL}" >&2
            echo "        Example:" >&2
            local _first_var
            IFS=':' read -r _first_var _ <<< "$AGENT_ENV_VARS"
            echo "          echo '${_first_var}=<your-key>' >> ${AGENT_ENV_LOCAL}" >&2
        else
            echo "" >&2
            echo "        Run '${_auth_argv[0]}' authentication setup and retry." >&2
        fi
        exit 1
    fi

    echo "[INFO]  Auth check passed for runtime '${RESOLVED_AGENT}'."
}

_validate_runtime

# ── Agent launch with bootstrap prompt (R4.5, R4.6, R15.2) ───────────────────

PROMPT_FILE="${BOOTSTRAP_DIR}/bootstrap-prompt.md"

_prepare_prompt() {
    # The prompt is framework-owned. Refresh it on every launch so resumed
    # projects receive coordination and workflow corrections.
    local _src="/start-here-prompts/bootstrap-prompt.md"
    if [[ -f "$_src" ]]; then
        cp "$_src" "$PROMPT_FILE"
    fi
}

_build_launch_argv() {
    # Populate _LAUNCH_ARGV for exec.  Uses RESOLVED_COMMAND and PROMPT_FILE.
    _LAUNCH_ARGV=()
    local _prompt_text=""
    if [[ -f "$PROMPT_FILE" ]]; then
        _prompt_text="$(cat "$PROMPT_FILE")"
    fi

    case "$RESOLVED_AGENT" in
        codex)
            # Codex: -m/--model; approval via --ask-for-approval <value> or the bypass flag.
            # full-auto maps to --dangerously-bypass-approvals-and-sandbox (already containerised).
            _LAUNCH_ARGV=("$RESOLVED_COMMAND")
            if [[ -n "$AGENT_MODEL" ]]; then _LAUNCH_ARGV+=(--model "$AGENT_MODEL"); fi
            if [[ "$AGENT_APPROVAL" == "full-auto" ]]; then
                _LAUNCH_ARGV+=(--dangerously-bypass-approvals-and-sandbox)
            elif [[ -n "$AGENT_APPROVAL" ]]; then
                _LAUNCH_ARGV+=(--ask-for-approval "$AGENT_APPROVAL")
            fi
            if [[ -n "$_prompt_text" ]]; then _LAUNCH_ARGV+=("$_prompt_text"); fi
            ;;
        claude)
            # Claude Code: --model, --dangerously-skip-permissions (when approval=skip-permissions),
            # then prompt via -p for non-interactive seed; drops into interactive session.
            _LAUNCH_ARGV=("$RESOLVED_COMMAND")
            if [[ -n "$AGENT_MODEL"                          ]]; then _LAUNCH_ARGV+=(--model "$AGENT_MODEL"); fi
            if [[ "$AGENT_APPROVAL" == "skip-permissions"    ]]; then _LAUNCH_ARGV+=(--dangerously-skip-permissions); fi
            if [[ -n "$_prompt_text"                         ]]; then _LAUNCH_ARGV+=(-p "$_prompt_text"); fi
            ;;
        gemini)
            # Gemini: --prompt-interactive seeds the first message and stays interactive.
            _LAUNCH_ARGV=("$RESOLVED_COMMAND")
            if [[ -n "$AGENT_MODEL"  ]]; then _LAUNCH_ARGV+=(--model "$AGENT_MODEL"); fi
            if [[ -n "$_prompt_text" ]]; then _LAUNCH_ARGV+=(--prompt-interactive "$_prompt_text"); fi
            ;;
        *)
            # Generic: pass model if set, then prompt as first positional arg.
            _LAUNCH_ARGV=("$RESOLVED_COMMAND")
            if [[ -n "$AGENT_MODEL"  ]]; then _LAUNCH_ARGV+=(--model "$AGENT_MODEL"); fi
            if [[ -n "$_prompt_text" ]]; then _LAUNCH_ARGV+=("$_prompt_text"); fi
            ;;
    esac
}

_launch_agent() {
    if ! command -v "$RESOLVED_COMMAND" >/dev/null 2>&1; then
        echo "[ERROR] Agent command '${RESOLVED_COMMAND}' not found on PATH." >&2
        echo "        Ensure the runtime '${RESOLVED_AGENT}' is installed." >&2
        exit 1
    fi

    _prepare_prompt

    echo "[INFO]  Launching ${RESOLVED_AGENT} in /project …"
    [[ -f "$PROMPT_FILE" ]] && echo "[INFO]  Bootstrap prompt: ${PROMPT_FILE}"
    echo ""
    echo "────────────────────────────────────────────────────────────────────────────"
    echo "  The agent will interview you, design your container, and generate files."
    echo "  Follow the agent's next-step instructions when it finishes."
    echo "  If interrupted, re-enter the container with:  ai-new <name> --resume"
    echo "  Then restart the session with:  /project/bootstrap/home/start-here.sh"
    echo "────────────────────────────────────────────────────────────────────────────"
    echo ""

    _build_launch_argv
    if [[ "$SHELL_ON_EXIT" -eq 1 ]]; then
        local _agent_rc=0
        "${_LAUNCH_ARGV[@]}" || _agent_rc=$?
        return "$_agent_rc"
    fi
    exec "${_LAUNCH_ARGV[@]}"
}

_launch_agent

# exec replaces the shell; if we reach here exec failed — give the user direction.
echo ""
echo "[INFO]  The agent session ended.  Rerun 'ai-new <name> --resume' to re-enter."
