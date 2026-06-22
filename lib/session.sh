#!/usr/bin/env bash
# Session state read/write for ai-new (R11). Source this; do not execute directly.
# Requires common.sh.

# Valid status vocabulary (R11.4).
_VALID_STATUSES=(
    started interviewing generated quality-gate-running
    quality-gate-failed quality-gate-timeout generated-unvalidated
    interrupted complete
)

# _valid_status <status>
_valid_status() {
    local _s="$1"
    local _v
    for _v in "${_VALID_STATUSES[@]}"; do
        [[ "$_v" == "$_s" ]] && return 0
    done
    return 1
}

# _session_json <project_root>
_session_json() { echo "${1}/bootstrap/session.json"; }

# _session_md <project_root>
_session_md()   { echo "${1}/bootstrap/session.md"; }

# read_status <project_root>
# Echoes the current status field from session.json.
read_status() {
    local _proj="$1"
    local _json
    _json="$(_session_json "$_proj")"
    [[ -f "$_json" ]] || _die "session.json not found: ${_json}"
    # Extract "status": "value" without jq dependency.
    local _status
    _status="$(grep -oP '"status"\s*:\s*"\K[^"]+' "$_json" 2>/dev/null)" \
        || _die "Cannot read status from ${_json}"
    echo "$_status"
}

# init_session <project_root> <name> <agent>
# Writes the initial session.json (status: started) atomically.
init_session() {
    local _proj="$1"
    local _name="$2"
    local _agent="$3"
    local _json
    _json="$(_session_json "$_proj")"
    local _ts
    _ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    local _pinned_hash=""
    local _pinned="${_proj}/bootstrap/agent.env"
    if [[ -f "$_pinned" ]]; then
        _pinned_hash="$(grep -oP '(?<=# source_hash=)\S+' "$_pinned" 2>/dev/null || true)"
    fi
    local _resume_cmd="ai-new ${_name} --resume"

    cat > "${_json}.tmp" <<EOF
{
  "project_name": "${_name}",
  "selected_agent": "${_agent}",
  "status": "started",
  "last_updated": "${_ts}",
  "generated_files": [],
  "containerfile_path": "",
  "quality_gate_status": "",
  "last_error": "",
  "resume_command": "${_resume_cmd}",
  "build_log_path": "",
  "trial_image_tag": "",
  "static_check_status": "",
  "pinned_agent_env": "${_pinned}",
  "pinned_agent_hash": "${_pinned_hash}"
}
EOF
    mv "${_json}.tmp" "$_json"

    # Initialise session.md.
    local _md
    _md="$(_session_md "$_proj")"
    cat > "${_md}.tmp" <<'EOF'
# Session Log

## Interview Summary
_Not yet started._

## Decisions
_None recorded._

## Unresolved Questions
_None recorded._

## Generated Files
_None yet._

## Quality-Gate Result
_Not yet run._

## Next Recommended Action
_Run `start-here.sh` inside the bootstrap container._

## Reconciliation Notes
_None._
EOF
    mv "${_md}.tmp" "$_md"
}

# write_session_field <project_root> <key> <value>
# Atomically updates a single top-level string field in session.json.
write_session_field() {
    local _proj="$1"
    local _key="$2"
    local _val="$3"
    local _json
    _json="$(_session_json "$_proj")"
    [[ -f "$_json" ]] || _die "session.json not found: ${_json}"

    local _ts
    _ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    # Rewrite the field and update last_updated atomically via temp file.
    # Uses sed-style replacement without eval/shell interpolation of values.
    local _tmp="${_json}.tmp"
    python3 - "$_json" "$_key" "$_val" "$_ts" <<'PYEOF' > "$_tmp"
import json, sys
path, key, val, ts = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
with open(path) as f:
    d = json.load(f)
d[key] = val
d['last_updated'] = ts
print(json.dumps(d, indent=2))
PYEOF
    mv "$_tmp" "$_json"
}

# set_status <project_root> <status>
# Validates and sets the status field in session.json.
set_status() {
    local _proj="$1"
    local _status="$2"
    _valid_status "$_status" \
        || _die "Invalid session status '${_status}'. Valid: ${_VALID_STATUSES[*]}"
    write_session_field "$_proj" "status" "$_status"
}

# append_session_md <project_root> <section> <text>
# Appends text under the given section heading in session.md.
append_session_md() {
    local _proj="$1"
    local _section="$2"
    local _text="$3"
    local _md
    _md="$(_session_md "$_proj")"
    local _ts
    _ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    printf '\n### %s (%s)\n%s\n' "$_section" "$_ts" "$_text" >> "$_md"
}

# is_complete <project_root>
# Returns 0 (true) only when every R11.6 condition holds.
is_complete() {
    local _proj="$1"
    local _json
    _json="$(_session_json "$_proj")"
    [[ -f "$_json" ]] || return 1

    local _status
    _status="$(read_status "$_proj")"
    case "$_status" in
        complete|generated-unvalidated) ;;
        *) return 1 ;;
    esac

    # Real image/Containerfile must exist.
    [[ -f "${_proj}/image/Containerfile" ]] || return 1

    # Next-steps file.
    [[ -f "${_proj}/bootstrap/next-steps.md" ]] || return 1

    return 0
}

# resume_command_for <project_root>
# Echoes the resume command from session.json.
resume_command_for() {
    local _proj="$1"
    local _json
    _json="$(_session_json "$_proj")"
    grep -oP '"resume_command"\s*:\s*"\K[^"]+' "$_json" 2>/dev/null \
        || _die "Cannot read resume_command from ${_json}"
}
