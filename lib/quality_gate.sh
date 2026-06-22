#!/usr/bin/env bash
# Host-side quality gate: static check, trial build, timeout (R8.1–R8.6, R18, R20).
# Source this file; do not execute directly. Requires common.sh, session.sh, slug.sh.

# Build timeout (GNU timeout syntax, default 30m).
_BUILD_TIMEOUT="${AI_NEW_BUILD_TIMEOUT:-30m}"

# static_check <containerfile> <log_file>
# Runs an advisory static check. Returns exit code; sets STATIC_CHECK_STATUS.
static_check() {
    local _cfile="$1"
    local _log="$2"
    STATIC_CHECK_STATUS="skipped"

    if podman manifest inspect --help >/dev/null 2>&1 && \
       podman build --dry-run -f "$_cfile" /dev/null >/dev/null 2>&1; then
        # Podman-native parse succeeded.
        STATIC_CHECK_STATUS="passed"
        return 0
    fi

    if command -v hadolint >/dev/null 2>&1; then
        if hadolint "$_cfile" > "$_log" 2>&1; then
            STATIC_CHECK_STATUS="passed"
        else
            STATIC_CHECK_STATUS="failed"
            return 1
        fi
        return 0
    fi

    # No tool available.
    STATIC_CHECK_STATUS="skipped"
    return 0
}

# trial_build <containerfile> <context_dir> <image_tag> <log_file>
# Runs podman build under timeout. Sets TRIAL_BUILD_STATUS.
# Returns 0 on success, 1 on failure, 2 on timeout.
trial_build() {
    local _cfile="$1"
    local _context="$2"
    local _tag="$3"
    local _log="$4"
    # shellcheck disable=SC2034
    TRIAL_BUILD_STATUS="unknown"

    local _timeout_cmd
    _timeout_cmd="timeout --foreground ${_BUILD_TIMEOUT}"

    local _rc=0
    # shellcheck disable=SC2086
    ${_timeout_cmd} podman build -f "$_cfile" -t "$_tag" "$_context" \
        > "$_log" 2>&1 || _rc=$?

    if [[ $_rc -eq 0 ]]; then
        # shellcheck disable=SC2034
        TRIAL_BUILD_STATUS="passed"
        return 0
    elif [[ $_rc -eq 124 ]]; then
        # shellcheck disable=SC2034
        TRIAL_BUILD_STATUS="timeout"
        return 2
    else
        # shellcheck disable=SC2034
        TRIAL_BUILD_STATUS="failed"
        return 1
    fi
}

# tag_trial_image <slug> <build_rc>
# Tags the trial image and records the tag. Sets TRIAL_IMAGE_TAG.
tag_trial_image() {
    local _slug="$1"
    local _build_rc="$2"
    TRIAL_IMAGE_TAG="localhost/ai-new/${_slug}:trial"
    if [[ "$_build_rc" -eq 0 ]]; then
        # Also tag as latest on success.
        podman tag "$TRIAL_IMAGE_TAG" "localhost/ai-project/${_slug}:latest" 2>/dev/null || true
    fi
}

# map_gate_status <static_rc> <build_rc> <skipped>
# Sets GATE_STATUS based on the gate outcome.
map_gate_status() {
    local _static_rc="$1"
    local _build_rc="$2"
    local _skipped="$3"
    if [[ "$_skipped" -eq 1 ]]; then
        GATE_STATUS="generated-unvalidated"
    elif [[ "$_build_rc" -eq 0 ]]; then
        GATE_STATUS="complete"
    elif [[ "$_build_rc" -eq 2 ]]; then
        GATE_STATUS="quality-gate-timeout"
    else
        GATE_STATUS="quality-gate-failed"
    fi
}

# run_quality_gate <project_root> <id> <containerfile> <context_dir> <image_tag> <reason> <repair_iter>
# Orchestrates the full gate flow and writes result + updates session.
run_quality_gate() {
    local _proj="$1"
    local _id="$2"
    local _cfile="$3"
    local _context="$4"
    local _image_tag="$5"
    local _reason="$6"
    local _repair_iter="$7"

    local _slug="${SLUG:-unknown}"
    local _log="${_proj}/bootstrap/build.log"
    local _static_log="${_proj}/bootstrap/static-check.log"
    local _trial_tag="localhost/ai-new/${_slug}:trial"

    # Static check (advisory).
    local _static_rc=0
    static_check "$_cfile" "$_static_log" || _static_rc=$?

    # Trial build.
    local _build_rc=0
    local _skip_build="${SKIP_TRIAL_BUILD:-0}"

    if [[ "$_skip_build" -eq 1 ]]; then
        _info "Trial build skipped (--skip-trial-build / AI_NEW_SKIP_TRIAL_BUILD=1)"
    else
        trial_build "$_cfile" "$_context" "$_trial_tag" "$_log" || _build_rc=$?
    fi

    # Map status.
    map_gate_status "$_static_rc" "$_build_rc" "$_skip_build"

    # Tag image if built successfully.
    if [[ "$_skip_build" -eq 0 && "$_build_rc" -eq 0 ]]; then
        tag_trial_image "$_slug" "$_build_rc"
        write_session_field "$_proj" "trial_image_tag" "$_trial_tag"
    fi

    # Derive error summary.
    local _error_summary=""
    if [[ "$_build_rc" -ne 0 ]]; then
        _error_summary="$(tail -5 "$_log" 2>/dev/null | tr '\n' ' ')"
    fi

    # Write result file.
    write_result "$_proj" "$_id" "$_build_rc" \
        "$GATE_STATUS" "$STATIC_CHECK_STATUS" \
        "$_log" "$_trial_tag" "${_error_summary}"

    # Update session.
    set_status "$_proj" "$GATE_STATUS"
    write_session_field "$_proj" "quality_gate_status" "$GATE_STATUS"
    write_session_field "$_proj" "static_check_status" "$STATIC_CHECK_STATUS"
    write_session_field "$_proj" "build_log_path" "$_log"
    [[ -n "$_error_summary" ]] && write_session_field "$_proj" "last_error" "$_error_summary"

    _info "Quality gate complete: ${GATE_STATUS} (static: ${STATIC_CHECK_STATUS}, build_rc: ${_build_rc})"
}
