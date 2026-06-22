#!/usr/bin/env bash
# Atomic lock with host-owned heartbeat and stale-lock handling (R19, D3).
# Source this file; do not execute directly. Requires common.sh.

# Default stale threshold (GNU timeout syntax).
_LOCK_STALE_AFTER="${AI_NEW_LOCK_STALE_AFTER:-10m}"

# _lock_dir <project_root>
_lock_dir() { echo "${1}/bootstrap/session.lock"; }

# _lock_info <project_root>
_lock_info() { echo "${1}/bootstrap/session.lock/info.json"; }

# _stale_seconds
# Converts the stale threshold to seconds (handles m/s/h suffixes).
_stale_seconds() {
    local _val="${_LOCK_STALE_AFTER}"
    local _num="${_val%[mMhHsS]}"
    local _unit="${_val: -1}"
    case "${_unit}" in
        m|M) echo $(( _num * 60 )) ;;
        h|H) echo $(( _num * 3600 )) ;;
        s|S) echo "$_num" ;;
        *)   echo "$_val" ;;  # assume seconds if no unit
    esac
}

# _heartbeat_interval_seconds
# refresh interval = min(60, threshold/5), floor 10.
_heartbeat_interval_seconds() {
    local _stale
    _stale="$(_stale_seconds)"
    local _interval=$(( _stale / 5 ))
    [[ "$_interval" -gt 60 ]] && _interval=60
    [[ "$_interval" -lt 10 ]] && _interval=10
    echo "$_interval"
}

# acquire_lock <project_root>
# Atomically acquires the session lock via mkdir. Exits non-zero if locked.
acquire_lock() {
    local _proj="$1"
    local _lock
    _lock="$(_lock_dir "$_proj")"

    if ! mkdir "$_lock" 2>/dev/null; then
        local _info
        _info="$(_lock_info "$_proj")"
        if [[ -f "$_info" ]]; then
            local _pid _hostname _container _started _heartbeat
            _pid="$(      grep -oP '"pid"\s*:\s*\K\d+' "$_info" 2>/dev/null || echo unknown)"
            _hostname="$( grep -oP '"hostname"\s*:\s*"\K[^"]+' "$_info" 2>/dev/null || echo unknown)"
            _container="$(grep -oP '"container_name"\s*:\s*"\K[^"]+' "$_info" 2>/dev/null || echo unknown)"
            _started="$(  grep -oP '"started_at"\s*:\s*"\K[^"]+' "$_info" 2>/dev/null || echo unknown)"
            _heartbeat="$(grep -oP '"last_heartbeat"\s*:\s*"\K[^"]+' "$_info" 2>/dev/null || echo unknown)"

            if lock_is_stale "$_proj"; then
                report_stale_lock "$_proj" "$_pid" "$_hostname" "$_container" "$_started" "$_heartbeat"
                if is_interactive; then
                    printf 'Remove stale lock and continue? [y/N] ' >&2
                    local _ans
                    read -r _ans
                    if [[ "$_ans" =~ ^[Yy]$ ]]; then
                        rm -rf "$_lock"
                        mkdir "$_lock" || _die "Failed to acquire lock after stale removal."
                    else
                        _die "Aborting. Remove the lock manually and retry."
                    fi
                else
                    _die "Non-interactive mode: refusing to clear stale lock automatically."
                fi
            else
                _die "Project is locked by pid=${_pid} host=${_hostname} container=${_container} started=${_started}."
            fi
        else
            _die "Project is locked (no lock info available). Lock dir: ${_lock}"
        fi
    fi

    # Write lock metadata.
    local _ts _hostname
    _ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    _hostname="$(hostname -s 2>/dev/null || echo unknown)"
    local _container_name="ai-new-bootstrap-${SLUG:-unknown}"

    cat > "$(_lock_info "$_proj")" <<EOF
{
  "pid": ${BASHPID},
  "hostname": "${_hostname}",
  "container_name": "${_container_name}",
  "started_at": "${_ts}",
  "last_heartbeat": "${_ts}"
}
EOF
}

# release_lock <project_root>
# Removes the lock directory.
release_lock() {
    local _proj="$1"
    rm -rf "$(_lock_dir "$_proj")"
}

# lock_is_active <project_root>
# Returns 0 if the lock exists and appears live.
lock_is_active() {
    local _proj="$1"
    [[ -d "$(_lock_dir "$_proj")" ]] || return 1
    lock_is_stale "$_proj" && return 1
    return 0
}

# lock_is_stale <project_root>
# Returns 0 if the lock exists but is stale (dead pid + expired heartbeat).
lock_is_stale() {
    local _proj="$1"
    local _lock
    _lock="$(_lock_dir "$_proj")"
    [[ -d "$_lock" ]] || return 1

    local _info
    _info="$(_lock_info "$_proj")"
    [[ -f "$_info" ]] || return 0  # no info → treat as stale

    local _pid _heartbeat _container
    _pid="$(      grep -oP '"pid"\s*:\s*\K\d+' "$_info" 2>/dev/null || echo 0)"
    _heartbeat="$(grep -oP '"last_heartbeat"\s*:\s*"\K[^"]+' "$_info" 2>/dev/null || echo "")"
    _container="$(grep -oP '"container_name"\s*:\s*"\K[^"]+' "$_info" 2>/dev/null || echo "")"

    # Check if supervisor pid is alive.
    local _pid_alive=0
    if [[ "$_pid" -gt 0 ]] && kill -0 "$_pid" 2>/dev/null; then
        _pid_alive=1
    fi

    # Check if container is running.
    local _container_alive=0
    if [[ -n "$_container" ]] && podman inspect --format '{{.State.Running}}' "$_container" 2>/dev/null | grep -q 'true'; then
        _container_alive=1
    fi

    # If both alive → not stale.
    [[ "$_pid_alive" -eq 1 || "$_container_alive" -eq 1 ]] && return 1

    # Check heartbeat age.
    if [[ -n "$_heartbeat" ]]; then
        local _stale_secs
        _stale_secs="$(_stale_seconds)"
        local _hb_epoch _now_epoch _age
        _hb_epoch="$(date -u -d "$_heartbeat" +%s 2>/dev/null || echo 0)"
        _now_epoch="$(date -u +%s)"
        _age=$(( _now_epoch - _hb_epoch ))
        [[ "$_age" -le "$_stale_secs" ]] && return 1
    fi

    return 0  # stale
}

# report_stale_lock <project_root> <pid> <hostname> <container> <started> <heartbeat>
# Prints stale lock details and the manual clear command.
report_stale_lock() {
    local _proj="$1" _pid="$2" _host="$3" _container="$4" _started="$5" _hb="$6"
    local _lock
    _lock="$(_lock_dir "$_proj")"
    _warn "Stale lock detected at: ${_lock}"
    _warn "  pid:            ${_pid}"
    _warn "  hostname:       ${_host}"
    _warn "  container_name: ${_container}"
    _warn "  started_at:     ${_started}"
    _warn "  last_heartbeat: ${_hb}"
    _warn "  (pid is dead and/or heartbeat has expired)"
    _warn "To clear manually: rm -rf '${_lock}'"
}

# _heartbeat_loop <project_root>
# Background function: updates last_heartbeat in the lock info file on interval.
_heartbeat_loop() {
    local _proj="$1"
    local _interval
    _interval="$(_heartbeat_interval_seconds)"
    local _info
    _info="$(_lock_info "$_proj")"
    while true; do
        sleep "$_interval"
        [[ -f "$_info" ]] || break
        local _ts
        _ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        # Atomically update last_heartbeat.
        python3 - "$_info" "$_ts" <<'PYEOF' > "${_info}.tmp" 2>/dev/null && mv "${_info}.tmp" "$_info" || true
import json, sys
path, ts = sys.argv[1], sys.argv[2]
with open(path) as f:
    d = json.load(f)
d['last_heartbeat'] = ts
print(json.dumps(d, indent=2))
PYEOF
    done
}
