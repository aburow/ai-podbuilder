#!/usr/bin/env bash
# start-here.sh — Agent-primed bootstrap container entrypoint.
# Placed at /project/bootstrap/home/start-here.sh inside the bootstrap container by the ai-new launcher.
# Reads runtime metadata only from the pinned bootstrap/agent.env (never source/eval).
set -euo pipefail

BOOTSTRAP_DIR="/project/bootstrap"
AGENT_ENV="${BOOTSTRAP_DIR}/agent.env"

# ── Mounted helper libraries ───────────────────────────────────────────────────
# Guard against a missing /start-here-lib mount (older image or misconfigured launch).
if [[ ! -f "/start-here-lib/common.sh" ]]; then
    echo "[ERROR] Required mount is absent: /start-here-lib/common.sh" >&2
    echo "        Ensure the bootstrap container was started with a current version of ai-new." >&2
    exit 1
fi
if [[ ! -f "/start-here-lib/adapter.sh" ]]; then
    echo "[ERROR] Required mount is absent: /start-here-lib/adapter.sh" >&2
    echo "        Ensure the bootstrap container was started with a current version of ai-new." >&2
    exit 1
fi
# shellcheck source=/dev/null
. /start-here-lib/common.sh
# shellcheck source=/dev/null
. /start-here-lib/adapter.sh

# ── Usage ─────────────────────────────────────────────────────────────────────

_usage() {
    cat >&2 <<'USAGE_EOF'
Usage: ./start-here.sh [--agent <agent>] [--resume] [-h|--help]
   or: /project/bootstrap/home/start-here.sh [--agent <agent>] [--resume] [-h|--help]

Start the agent-primed bootstrap session inside the ai-new bootstrap container.
Reads runtime metadata from /project/bootstrap/agent.env (never source/eval).

The script is directly executable (no 'bash' prefix needed).  The container
drops into $HOME = /project/bootstrap/home, so from the shell prompt use:
  ./start-here.sh

Options:
  --agent <agent>   Override the pinned agent runtime.
                    Valid if multiple runtimes are installed and the default
                    is not what you want.
  --resume          Resume an interrupted bootstrap session.
                    Never re-prompts for the agent runtime.
  -h, --help        Show this help and exit (zero).

Environment:
  /project/bootstrap/agent.env        Pinned agent registry (required).
  /project/bootstrap/agent.env.local  Bootstrap-time API keys (optional, gitignored).
  /project/bootstrap/session.json     Session state (status, generated files).

This script is designed to be run inside the bootstrap container created by
'ai-new'.  It installs the pinned agent runtime, validates credentials, and
launches the agent with the bootstrap prompt.

If the bootstrap session was interrupted, re-enter the container with:
  ai-new <name> --resume
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

# ── Runtime install (R3.1, R3.3, AC3, AC5) ────────────────────────────────────

_install_runtime() {
    if command -v "$RESOLVED_COMMAND" >/dev/null 2>&1; then
        _info "Runtime '${RESOLVED_AGENT}' (${RESOLVED_COMMAND}) is already present; skipping install."
        return 0
    fi

    _info "Installing runtime '${RESOLVED_AGENT}' via adapter '${AGENT_INSTALL_ADAPTER}'…"
    run_install_adapter "$AGENT_INSTALL_ADAPTER" "$AGENT_INSTALL_PACKAGE" "$AGENT_INSTALL_VERSION"
    # Refresh the shell's command-hash table so the newly installed binary resolves.
    hash -r 2>/dev/null || true
}

# ── Authentication / runtime-presence validation (R4.4, R10, AC6) ─────────────

_validate_runtime() {
    local _cmd="$RESOLVED_COMMAND"

    # manual adapter — explicit fallback for agents that cannot self-install.
    # Shipped agents no longer use this adapter; it is reserved for future manual agents.
    if [[ "$AGENT_INSTALL_ADAPTER" == "manual" ]]; then
        if ! command -v "$_cmd" >/dev/null 2>&1; then
            echo "[ERROR] Agent runtime '${RESOLVED_AGENT}' (command: ${_cmd}) is not installed." >&2
            echo "        This runtime uses the 'manual' adapter and cannot be installed automatically." >&2
            echo "        Install '${_cmd}' and place it on PATH, then rerun start-here.sh." >&2
            echo "        Home-based bin directories already on PATH:" >&2
            echo "          \$HOME/.npm-global/bin   (npm-global packages)" >&2
            echo "          \$HOME/.local/bin        (pipx packages)" >&2
            exit 1
        fi
    fi

    # If no auth-check argv is defined, just verify the command is present post-install.
    if [[ -z "$AGENT_AUTH_CHECK_ARGV" ]]; then
        if ! command -v "$_cmd" >/dev/null 2>&1; then
            local _attempted_argv=()
            while IFS= read -r _word; do
                [[ -n "$_word" ]] && _attempted_argv+=("$_word")
            done < <(build_argv "$AGENT_INSTALL_ADAPTER" "$AGENT_INSTALL_PACKAGE" "$AGENT_INSTALL_VERSION")
            echo "[ERROR] Agent runtime '${RESOLVED_AGENT}' (command: ${_cmd}) is still missing after install." >&2
            echo "        Adapter used:    ${AGENT_INSTALL_ADAPTER}" >&2
            [[ "${#_attempted_argv[@]}" -gt 0 ]] && echo "        Install command: ${_attempted_argv[*]}" >&2
            echo "        Ensure the install succeeded and that '${_cmd}' is on PATH." >&2
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

if ! _install_runtime; then
    _INSTALL_FAIL_ARGV=()
    while IFS= read -r _word; do
        [[ -n "$_word" ]] && _INSTALL_FAIL_ARGV+=("$_word")
    done < <(build_argv "$AGENT_INSTALL_ADAPTER" "$AGENT_INSTALL_PACKAGE" "$AGENT_INSTALL_VERSION")
    echo "[ERROR] Install failed for runtime '${RESOLVED_AGENT}'." >&2
    echo "        Adapter:  ${AGENT_INSTALL_ADAPTER}" >&2
    echo "        Package:  ${AGENT_INSTALL_PACKAGE}${AGENT_INSTALL_VERSION:+@${AGENT_INSTALL_VERSION}}" >&2
    [[ "${#_INSTALL_FAIL_ARGV[@]}" -gt 0 ]] && echo "        Command:  ${_INSTALL_FAIL_ARGV[*]}" >&2
    echo "        Likely cause: network unreachable, registry down, or prefix not writable." >&2
    exit 1
fi
_validate_runtime

# ── Agent launch with bootstrap prompt (R4.5, R4.6, R15.2) ───────────────────

PROMPT_FILE="${BOOTSTRAP_DIR}/bootstrap-prompt.md"

_prepare_prompt() {
    # If the prompt hasn't been placed in bootstrap/ yet, nothing to do — the
    # launch.sh bind-mounts prompts/ as /start-here-prompts inside the container.
    local _src="/start-here-prompts/bootstrap-prompt.md"
    if [[ ! -f "$PROMPT_FILE" && -f "$_src" ]]; then
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
            # codex --print "<prompt>" --output-format text
            if [[ -n "$_prompt_text" ]]; then
                _LAUNCH_ARGV=("$RESOLVED_COMMAND" --print "$_prompt_text" --output-format text)
            else
                _LAUNCH_ARGV=("$RESOLVED_COMMAND")
            fi
            ;;
        codex)
            if [[ -n "$_prompt_text" ]]; then
                _LAUNCH_ARGV=("$RESOLVED_COMMAND" --full-auto -q "$_prompt_text")
            else
                _LAUNCH_ARGV=("$RESOLVED_COMMAND")
            fi
            ;;
        *)
            # Generic: pass prompt as first positional arg if it accepts one.
            if [[ -n "$_prompt_text" ]]; then
                _LAUNCH_ARGV=("$RESOLVED_COMMAND" "$_prompt_text")
            else
                _LAUNCH_ARGV=("$RESOLVED_COMMAND")
            fi
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
    exec "${_LAUNCH_ARGV[@]}"
}

_launch_agent

# exec replaces the shell; if we reach here exec failed — give the user direction.
echo ""
echo "[INFO]  The agent session ended.  Rerun 'ai-new <name> --resume' to re-enter."
