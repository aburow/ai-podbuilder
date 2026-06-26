#!/usr/bin/env bash
# File-based host↔container coordination protocol (R8.7–R8.13). Source; no exec.
# Requires common.sh, session.sh.

# Poll interval (default 2s).
_COORD_POLL_INTERVAL="${AI_NEW_COORDINATION_POLL_INTERVAL:-2}"

# _request_dir <project_root>
_request_dir() { echo "${1}/bootstrap"; }

# next_request_id <project_root>
# Outputs the next monotonically increasing request id.
next_request_id() {
    local _proj="$1"
    local _dir
    _dir="$(_request_dir "$_proj")"
    local _max=0 _f _id
    # Find max existing id from request and result filenames.
    shopt -s nullglob
    for _f in "${_dir}"/build.request.*.json "${_dir}"/build.result.*.json; do
        _id="${_f%.json}"
        _id="${_id##*.}"
        if [[ "$_id" =~ ^[0-9]+$ ]] && [[ "$_id" -gt "$_max" ]]; then
            _max="$_id"
        fi
    done
    shopt -u nullglob
    # Also check session.json last_request_id if present.
    local _json="${_proj}/bootstrap/session.json"
    if [[ -f "$_json" ]]; then
        local _sid
        _sid="$(grep -oP '"last_request_id"\s*:\s*\K\d+' "$_json" 2>/dev/null || echo 0)"
        [[ "$_sid" -gt "$_max" ]] && _max="$_sid"
    fi
    echo $(( _max + 1 ))
}

# _parse_request_id <filename>
# Extracts the numeric id from build.request.<id>.json or build.result.<id>.json.
_parse_request_id() {
    local _f="${1%.json}"
    local _id="${_f##*.}"
    [[ "$_id" =~ ^[0-9]+$ ]] && echo "$_id" || echo ""
}

# _last_completed_id <project_root>
# Returns the highest id for which a result file exists.
_last_completed_id() {
    local _proj="$1"
    local _dir
    _dir="$(_request_dir "$_proj")"
    local _max=0 _f _id
    shopt -s nullglob
    for _f in "${_dir}"/build.result.*.json; do
        _id="$(_parse_request_id "$(basename "$_f")")"
        [[ -n "$_id" && "$_id" -gt "$_max" ]] && _max="$_id"
    done
    shopt -u nullglob
    echo "$_max"
}

# validate_request <project_root> <request_file>
# Returns 0 if the request is valid to process; non-zero otherwise.
# Sets REQ_ID, REQ_CONTAINERFILE, REQ_CONTEXT_DIR, REQ_IMAGE_TAG,
# REQ_REASON, REQ_REPAIR_ITERATION from the parsed file.
validate_request() {
    local _proj="$1"
    local _file="$2"

    # Reject .tmp files (partially written).
    [[ "$_file" == *.tmp ]] && return 1

    [[ -f "$_file" ]] || return 1

    # Parse fields.
    REQ_ID="$(           grep -oP '"request_id"\s*:\s*\K\d+' "$_file" 2>/dev/null || true)"
    REQ_CONTAINERFILE="$(grep -oP '"containerfile"\s*:\s*"\K[^"]+' "$_file" 2>/dev/null || true)"
    REQ_CONTEXT_DIR="$(  grep -oP '"context_dir"\s*:\s*"\K[^"]+' "$_file" 2>/dev/null || true)"
    REQ_IMAGE_TAG="$(    grep -oP '"image_tag"\s*:\s*"\K[^"]+' "$_file" 2>/dev/null || true)"
    REQ_REASON="$(       grep -oP '"reason"\s*:\s*"\K[^"]+' "$_file" 2>/dev/null || true)"
    REQ_REPAIR_ITERATION="$(grep -oP '"repair_iteration"\s*:\s*\K\d+' "$_file" 2>/dev/null || echo 0)"

    # All required fields must be present.
    if [[ -z "$REQ_ID" || -z "$REQ_CONTAINERFILE" || -z "$REQ_CONTEXT_DIR" || -z "$REQ_IMAGE_TAG" ]]; then
        _warn "Rejecting malformed request (missing fields): ${_file}"
        return 1
    fi

    # Agent-written requests use paths relative to /project. Resolve them
    # against the host project root and reject path traversal.
    local _project_real
    _project_real="$(realpath -m "$_proj")"
    if [[ "$REQ_CONTAINERFILE" != /* ]]; then
        REQ_CONTAINERFILE="${_proj}/${REQ_CONTAINERFILE}"
    fi
    if [[ "$REQ_CONTEXT_DIR" != /* ]]; then
        REQ_CONTEXT_DIR="${_proj}/${REQ_CONTEXT_DIR}"
    fi
    REQ_CONTAINERFILE="$(realpath -m "$REQ_CONTAINERFILE")"
    REQ_CONTEXT_DIR="$(realpath -m "$REQ_CONTEXT_DIR")"
    case "$REQ_CONTAINERFILE" in
        "${_project_real}"/*) ;;
        *) _warn "Rejecting request path outside project: ${REQ_CONTAINERFILE}"; return 1 ;;
    esac
    case "$REQ_CONTEXT_DIR" in
        "${_project_real}"/*) ;;
        *) _warn "Rejecting context outside project: ${REQ_CONTEXT_DIR}"; return 1 ;;
    esac
    [[ -f "$REQ_CONTAINERFILE" ]] \
        || { _warn "Rejecting missing Containerfile: ${REQ_CONTAINERFILE}"; return 1; }
    [[ -d "$REQ_CONTEXT_DIR" ]] \
        || { _warn "Rejecting missing build context: ${REQ_CONTEXT_DIR}"; return 1; }

    # ID must be integer.
    [[ "$REQ_ID" =~ ^[0-9]+$ ]] || { _warn "Rejecting non-integer request id: ${REQ_ID}"; return 1; }

    # ID must be greater than last completed.
    local _last
    _last="$(_last_completed_id "$_proj")"
    if [[ "$REQ_ID" -le "$_last" ]]; then
        _warn "Rejecting stale request id ${REQ_ID} (last completed: ${_last})"
        return 1
    fi

    return 0
}

# request_already_completed <project_root> <id>
# Returns 0 if a result file already exists for the given id.
request_already_completed() {
    local _proj="$1"
    local _id="$2"
    [[ -f "${_proj}/bootstrap/build.result.${_id}.json" ]]
}

# write_result <project_root> <id> <exit_code> <status> <static_check_status> <build_log_path> <image_tag> <error_summary>
# Atomically writes a build result file.
write_result() {
    local _proj="$1"
    local _id="$2"
    local _exit_code="$3"
    local _status="$4"
    local _static_status="$5"
    local _log_path="$6"
    local _image_tag="$7"
    local _error_summary="$8"
    local _ts_now
    _ts_now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    local _result_file="${_proj}/bootstrap/build.result.${_id}.json"

    # Sanitize error_summary for JSON (escape double quotes and backslashes).
    local _safe_error
    _safe_error="${_error_summary//\\/\\\\}"
    _safe_error="${_safe_error//\"/\\\"}"

    cat > "${_result_file}.tmp" <<EOF
{
  "request_id": ${_id},
  "started_at": "${_ts_now}",
  "finished_at": "${_ts_now}",
  "exit_code": ${_exit_code},
  "status": "${_status}",
  "static_check_status": "${_static_status}",
  "build_log_path": "${_log_path}",
  "image_tag": "${_image_tag}",
  "error_summary": "${_safe_error}"
}
EOF
    mv "${_result_file}.tmp" "$_result_file"
}

# poll_requests <project_root>
# Polls for new unprocessed build request files. When one is found, calls
# the quality gate and writes the result.  Runs until the session ends.
poll_requests() {
    local _proj="$1"
    local _dir
    _dir="$(_request_dir "$_proj")"
    _info "Supervisor: polling for build requests (interval: ${_COORD_POLL_INTERVAL}s)"
    while true; do
        local _f
        shopt -s nullglob
        for _f in "${_dir}"/build.request.*.json; do
            [[ -f "$_f" ]] || continue
            local _base
            _base="$(basename "$_f")"
            local _id
            _id="$(_parse_request_id "$_base")"
            [[ -n "$_id" ]] || continue
            request_already_completed "$_proj" "$_id" && continue
            if validate_request "$_proj" "$_f"; then
                set_status "$_proj" "quality-gate-running"
                run_quality_gate "$_proj" "$_id" \
                    "$REQ_CONTAINERFILE" "$REQ_CONTEXT_DIR" "$REQ_IMAGE_TAG" \
                    "$REQ_REASON" "$REQ_REPAIR_ITERATION"
            fi
        done
        shopt -u nullglob
        sleep "$_COORD_POLL_INTERVAL"
    done
}
