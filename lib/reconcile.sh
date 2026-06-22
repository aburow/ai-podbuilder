#!/usr/bin/env bash
# Resume reconciliation and crash recovery (R8.12, R8.13, R19.8, R20.4–R20.6).
# Source this file; do not execute directly. Requires common.sh, session.sh, lock.sh.

# Max repair attempts (default 3).
_MAX_REPAIR_ATTEMPTS="${AI_NEW_MAX_REPAIR_ATTEMPTS:-3}"

# interrupted_requests <project_root>
# Echoes the ids of build.request files with no matching result and no active lock.
interrupted_requests() {
    local _proj="$1"
    local _dir="${_proj}/bootstrap"
    local _f _id
    shopt -s nullglob
    for _f in "${_dir}"/build.request.*.json; do
        _id="${_f%.json}"
        _id="${_id##*.}"
        [[ "$_id" =~ ^[0-9]+$ ]] || continue
        [[ -f "${_dir}/build.result.${_id}.json" ]] && continue
        echo "$_id"
    done
    shopt -u nullglob
}

# apply_status_replacement <project_root> <old_status> <new_status> <reason>
# Updates session status and appends a reconciliation note to session.md.
apply_status_replacement() {
    local _proj="$1"
    local _old="$2"
    local _new="$3"
    local _reason="$4"
    set_status "$_proj" "$_new"
    append_session_md "$_proj" "Reconciliation" \
        "Previous status '${_old}' → '${_new}'. Reason: ${_reason}"
}

# reconcile_on_resume <project_root>
# Performs full status reconciliation before re-entering the container (R19.8).
reconcile_on_resume() {
    local _proj="$1"
    local _status
    _status="$(read_status "$_proj")"
    local _ts_now
    _ts_now="$(date -u +%s)"

    # Verify pinned agent file integrity.
    local _pinned="${_proj}/bootstrap/agent.env"
    if [[ ! -f "$_pinned" ]]; then
        _die "Cannot resume: pinned agent.env is missing (${_pinned})."
    fi

    case "$_status" in
        interviewing)
            # Stale interviewing → interrupted.
            if ! lock_is_active "$_proj"; then
                apply_status_replacement "$_proj" "interviewing" "interrupted" \
                    "No active lock found during resume; previous session was interrupted."
            fi
            ;;
        quality-gate-running)
            # Stale gate → reconcile based on artifacts.
            if ! lock_is_active "$_proj"; then
                local _log="${_proj}/bootstrap/build.log"
                local _success_marker="${_proj}/bootstrap/.build-success"
                if [[ -f "$_success_marker" ]]; then
                    apply_status_replacement "$_proj" "quality-gate-running" "complete" \
                        "Build success marker found; gate completed successfully before crash."
                elif [[ -f "$_log" && -s "$_log" ]]; then
                    # Check if the build timeout was exceeded.
                    local _build_timeout_secs
                    _build_timeout_secs="$(
                        local _val="${AI_NEW_BUILD_TIMEOUT:-30m}"
                        local _num="${_val%[mMhHsS]}"
                        local _unit="${_val: -1}"
                        case "$_unit" in
                            m|M) echo $(( _num * 60 )) ;;
                            h|H) echo $(( _num * 3600 )) ;;
                            *) echo "$_num" ;;
                        esac
                    )"
                    local _log_mtime _age
                    _log_mtime="$(stat -c %Y "$_log" 2>/dev/null || echo 0)"
                    _age=$(( _ts_now - _log_mtime ))
                    if [[ "$_age" -ge "$_build_timeout_secs" ]]; then
                        apply_status_replacement "$_proj" "quality-gate-running" "quality-gate-timeout" \
                            "Build log is older than configured timeout (${AI_NEW_BUILD_TIMEOUT:-30m}); gate timed out."
                    else
                        apply_status_replacement "$_proj" "quality-gate-running" "quality-gate-failed" \
                            "Captured failure log found; gate failed before crash."
                    fi
                else
                    apply_status_replacement "$_proj" "quality-gate-running" "interrupted" \
                        "No build log found; gate was interrupted before it could run."
                fi
            fi
            ;;
        interrupted|quality-gate-failed|quality-gate-timeout)
            # Resumable — no change needed.
            ;;
    esac

    # Reconcile any interrupted build requests.
    local _int_id
    for _int_id in $(interrupted_requests "$_proj"); do
        _warn "Interrupted build request id=${_int_id} found with no result — marking as interrupted."
        local _req_file="${_proj}/bootstrap/build.request.${_int_id}.json"
        write_result "$_proj" "$_int_id" "1" "interrupted" "skipped" \
            "" "" "Reconciled on resume: no result found, no active lock."
        append_session_md "$_proj" "Reconciliation" \
            "Build request id=${_int_id} (${_req_file}) had no result; reconciled as interrupted."
    done

    # Verify selected_agent matches pinned agent.env.
    local _json="${_proj}/bootstrap/session.json"
    local _selected_agent
    _selected_agent="$(grep -oP '"selected_agent"\s*:\s*"\K[^"]+' "$_json" 2>/dev/null || true)"
    if [[ -z "$_selected_agent" ]]; then
        _die "Cannot resume: selected_agent is missing from session.json."
    fi
    local _pinned_agent
    _pinned_agent="$(grep -oP '(?<=# agent_name=)\S+' "$_pinned" 2>/dev/null || true)"
    if [[ -n "$_pinned_agent" && "$_pinned_agent" != "$_selected_agent" ]]; then
        _die "Cannot resume: pinned agent.env declares '${_pinned_agent}' but session.json records '${_selected_agent}'."
    fi

    _info "Reconciliation complete. Current status: $(read_status "$_proj")"
}

# check_repair_cap <project_root> <repair_iteration>
# Fails if repair_iteration >= max attempts.
check_repair_cap() {
    local _proj="$1"
    local _iter="$2"
    local _max="${_MAX_REPAIR_ATTEMPTS}"
    if [[ "$_iter" -ge "$_max" ]]; then
        set_status "$_proj" "quality-gate-failed"
        _die "Repair cap reached (${_iter}/${_max}). Status set to quality-gate-failed.
  Use 'ai-new <name> --resume' to attempt another repair cycle."
    fi
}
