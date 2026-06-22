#!/usr/bin/env bash
# Shared user-facing message builders for ai-new and start-here.sh (R1.7, R16.2, F8).
# Source this file; do not execute directly.  Requires common.sh (for list_registered_agents
# via registry.sh).

# msg_unknown_agent <agent_name>
# Prints an actionable unknown-agent error, listing registered agents (AC2).
# Requires registry.sh to have been sourced (list_registered_agents).
msg_unknown_agent() {
    local _agent="$1"
    local _registered=""
    if declare -f list_registered_agents >/dev/null 2>&1; then
        _registered="$(list_registered_agents 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
    fi
    echo "[ERROR] Unknown agent runtime: '${_agent}'" >&2
    echo "        Registered agents: ${_registered:-none}" >&2
    echo "        Rerun with one of the registered agents, e.g.:" >&2
    if [[ -n "$_registered" ]]; then
        local _first
        _first="$(echo "$_registered" | awk '{print $1}')"
        echo "          ai-new <name> --agent ${_first}" >&2
    fi
}

# msg_podman_unavailable
# Prints a clear Podman-unavailable error (R1.7, AC19).
msg_podman_unavailable() {
    echo "[ERROR] 'podman' is not available on PATH." >&2
    echo "        Install Podman (https://podman.io/getting-started/installation)" >&2
    echo "        and ensure it is in your PATH before running ai-new." >&2
}

# msg_build_failure <project_name> <log_path>
# Prints a build/pull failure message (R1.7, AC19).
msg_build_failure() {
    local _project="$1"
    local _log="${2:-bootstrap/build.log}"
    echo "[ERROR] Bootstrap image build or pull failed for project '${_project}'." >&2
    echo "        Build log: ${_log}" >&2
    echo "        Fix the Containerfile, then resume with: ai-new ${_project} --resume" >&2
}

# msg_stale_lock <project_root> <lock_pid> <lock_host> <container_name> <started_at> <last_heartbeat> <stale_reason>
# Prints a detailed stale-lock report (D3, R19.4).
msg_stale_lock() {
    local _proj="$1"
    local _pid="$2"
    local _host="$3"
    local _container="$4"
    local _started="$5"
    local _heartbeat="$6"
    local _reason="$7"
    local _lock_path="${_proj}/bootstrap/session.lock"
    echo "[WARN]  Stale lock detected at: ${_lock_path}" >&2
    echo "        Recorded PID:        ${_pid}" >&2
    echo "        Recorded host:       ${_host}" >&2
    echo "        Container name:      ${_container}" >&2
    echo "        Started at:          ${_started}" >&2
    echo "        Last heartbeat:      ${_heartbeat}" >&2
    echo "        Stale reason:        ${_reason}" >&2
    echo "" >&2
    echo "        To manually clear the lock, run:" >&2
    echo "          rm -rf '${_lock_path}'" >&2
    echo "        Then resume with: ai-new $(basename "${_proj}") --resume" >&2
}

# msg_active_lock <project_root> <lock_pid> <lock_host> <container_name> <started_at>
# Prints an active-lock refusal message (R19.3, AC24).
msg_active_lock() {
    local _proj="$1"
    local _pid="$2"
    local _host="$3"
    local _container="$4"
    local _started="$5"
    local _lock_path="${_proj}/bootstrap/session.lock"
    echo "[ERROR] Project '$(basename "${_proj}")' is already active (lock held)." >&2
    echo "        Lock path:      ${_lock_path}" >&2
    echo "        Supervisor PID: ${_pid} on ${_host}" >&2
    echo "        Container:      ${_container}" >&2
    echo "        Started at:     ${_started}" >&2
    echo "        Wait for the active session to finish, or clear a stale lock with:" >&2
    echo "          rm -rf '${_lock_path}'" >&2
}

# msg_ambiguous_resume <project_name> <status>
# Prints a clear message when a resume cannot proceed due to ambiguous state (AC19).
msg_ambiguous_resume() {
    local _project="$1"
    local _status="$2"
    echo "[ERROR] Cannot resume project '${_project}': ambiguous session state '${_status}'." >&2
    echo "        Inspect bootstrap/session.json and bootstrap/session.md to determine" >&2
    echo "        the project state, then rerun: ai-new ${_project} --resume" >&2
}

# msg_start_here_help
# Prints start-here.sh help banner (AC19).
msg_start_here_help() {
    cat >&2 <<'HELP_EOF'
Usage: start-here.sh [--agent <agent>] [--resume] [-h|--help]

Start the agent-primed bootstrap session inside the ai-new bootstrap container.
Reads runtime metadata from /project/bootstrap/agent.env (never source/eval).

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
'ai-new'.  It validates the agent runtime, loads API keys, and launches the
agent with the bootstrap prompt.

If the bootstrap session was interrupted, re-enter the container with:
  ai-new <name> --resume
HELP_EOF
}
