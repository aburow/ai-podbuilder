#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# 2026 - Anthony Burow - https://github.com/aburow
# Durable project normalization, validation, and build-spec generation for ai-new.
# Source this file; do not execute directly.
# Requires common.sh, session.sh, slug.sh.

_KNOWN_AGENT_STATE_DIRS=(
    ".codex"
    ".codex"
    ".openai"
    ".config/github-copilot"
    ".config/gemini"
)

# read_session_field <project_root> <key>
# Echoes a top-level JSON field value. Arrays are emitted one item per line.
read_session_field() {
    local _proj="$1"
    local _key="$2"
    local _json="${_proj}/bootstrap/session.json"
    [[ -f "$_json" ]] || return 1
    python3 - "$_json" "$_key" <<'PYEOF'
import json, sys
path, key = sys.argv[1], sys.argv[2]
with open(path) as f:
    data = json.load(f)
val = data.get(key, "")
if isinstance(val, list):
    for item in val:
        print(item)
elif val is None:
    pass
else:
    print(val)
PYEOF
}

# write_session_json_field <project_root> <key> <json_literal>
# Writes a top-level field using a JSON literal (string/array/object/etc).
write_session_json_field() {
    local _proj="$1"
    local _key="$2"
    local _json_literal="$3"
    local _json="${_proj}/bootstrap/session.json"
    [[ -f "$_json" ]] || _die "session.json not found: ${_json}"
    local _tmp="${_json}.tmp"
    python3 - "$_json" "$_key" "$_json_literal" <<'PYEOF' > "$_tmp"
import json, sys
path, key, raw = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as f:
    data = json.load(f)
data[key] = json.loads(raw)
print(json.dumps(data, indent=2))
PYEOF
    mv "$_tmp" "$_json"
}

# infer_final_runtime <project_root>
# Echoes the authoritative durable runtime. Uses final_runtime when present,
# otherwise falls back to selected_agent for backward compatibility.
infer_final_runtime() {
    local _proj="$1"
    local _final
    _final="$(read_session_field "$_proj" "final_runtime" 2>/dev/null | head -n 1 || true)"
    if [[ -n "$_final" ]]; then
        printf '%s\n' "$_final"
        return 0
    fi
    read_session_field "$_proj" "selected_agent" 2>/dev/null | head -n 1 || true
}

_allowed_agent_state_dirs_for_runtime() {
    local _runtime="$1"
    case "$_runtime" in
        codex) printf '%s\n' ".codex" ;;
        codex) printf '%s\n' ".codex" ;;
        gemini) printf '%s\n' ".config/gemini" ;;
        github-copilot) printf '%s\n' ".config/github-copilot" ;;
        openai) printf '%s\n' ".openai" ;;
        none|"") ;;
        *) ;;
    esac
}

reconcile_agent_state_dirs() {
    local _state_home="$1"
    local _runtime="$2"
    local _keep
    _keep="$(_allowed_agent_state_dirs_for_runtime "$_runtime")"
    local _dir
    for _dir in "${_KNOWN_AGENT_STATE_DIRS[@]}"; do
        [[ -e "${_state_home}/${_dir}" ]] || continue
        if [[ -n "$_keep" && "$_dir" == "$_keep" ]]; then
            continue
        fi
        rm -rf "${_state_home:?}/${_dir}"
    done
}

profile_uses_ssh_markers() {
    local _proj="$1"
    local _files=(
        "${_proj}/profile.env"
        "${_proj}/README.md"
        "${_proj}/.env.example"
        "${_proj}/PODMAN_BUILDER.md"
        "${_proj}/image/Containerfile"
    )
    local _f
    for _f in "${_files[@]}"; do
        [[ -f "$_f" ]] || continue
        if rg -n "openssh|sshd|SSH_PUBLIC_KEY_FILE|ENABLE_SSHD|2222|id_ed25519\\.pub|authorized_keys" "$_f" >/dev/null 2>&1; then
            return 0
        fi
    done
    return 1
}

feature_list_contains() {
    local _proj="$1"
    local _field="$2"
    local _needle="$3"
    local _item
    while IFS= read -r _item; do
        [[ "$_item" == "$_needle" ]] && return 0
    done < <(read_session_field "$_proj" "$_field" 2>/dev/null || true)
    return 1
}

remove_ssh_outputs_if_rejected() {
    local _proj="$1"
    if ! feature_list_contains "$_proj" "rejected_optional_features" "ssh"; then
        return 0
    fi
    local _files=(
        "${_proj}/profile.env"
        "${_proj}/README.md"
        "${_proj}/.env.example"
        "${_proj}/PODMAN_BUILDER.md"
        "${_proj}/image/Containerfile"
    )
    local _f
    for _f in "${_files[@]}"; do
        [[ -f "$_f" ]] || continue
        python3 - "$_f" <<'PYEOF'
import re, sys
path = sys.argv[1]
with open(path) as f:
    lines = f.readlines()
patterns = [
    r'openssh',
    r'sshd',
    r'SSH_PUBLIC_KEY_FILE',
    r'ENABLE_SSHD',
    r'2222',
    r'id_ed25519\.pub',
    r'authorized_keys',
]
rx = re.compile("|".join(patterns), re.IGNORECASE)
out = [line for line in lines if not rx.search(line)]
with open(path, "w") as f:
    f.writelines(out)
PYEOF
    done
}

derive_enabled_optional_features() {
    local _proj="$1"
    if profile_uses_ssh_markers "$_proj"; then
        printf '%s\n' "ssh"
    fi
}

write_enabled_optional_features_if_missing() {
    local _proj="$1"
    local _existing
    _existing="$(read_session_field "$_proj" "enabled_optional_features" 2>/dev/null || true)"
    [[ -n "$_existing" ]] && return 0
    local _feature
    local _items=()
    while IFS= read -r _feature; do
        [[ -n "$_feature" ]] && _items+=("\"${_feature}\"")
    done < <(derive_enabled_optional_features "$_proj")
    local _json="[]"
    if [[ ${#_items[@]} -gt 0 ]]; then
        local _joined
        _joined="$(IFS=,; echo "${_items[*]}")"
        _json="[${_joined}]"
    fi
    write_session_json_field "$_proj" "enabled_optional_features" "$_json"
}

validate_extra_host_paths() {
    local _profile_file="$1"
    local _fail=0
    # shellcheck source=/dev/null
    source "$_profile_file"
    local _i=0
    local _flag _spec _host
    while [[ $_i -lt ${#EXTRA_VOLUMES[@]} ]]; do
        _flag="${EXTRA_VOLUMES[$_i]}"
        _spec="${EXTRA_VOLUMES[$((_i + 1))]:-}"
        if [[ "$_flag" == "-v" || "$_flag" == "--volume" ]]; then
            _host="${_spec%%:*}"
            if [[ -n "$_host" && ! -e "$_host" ]]; then
                _warn "Missing host path for EXTRA_VOLUMES entry: ${_host}"
                _fail=1
            fi
            _i=$((_i + 2))
        else
            _i=$((_i + 1))
        fi
    done
    return $_fail
}

generate_durable_build_spec() {
    local _proj="$1"
    local _name
    _name="$(basename "$_proj")"
    local _spec="${_proj}/PODMAN_BUILDER.md"
    local _cfile="${_proj}/image/Containerfile"
    local _profile="${_proj}/profile.env"
    local _runtime
    _runtime="$(infer_final_runtime "$_proj")"

    local _base_image="unknown"
    [[ -f "$_cfile" ]] && \
        _base_image="$(grep -m1 '^FROM ' "$_cfile" | awk '{print $2}')"

    local _workdir=""
    [[ -f "$_profile" ]] && \
        _workdir="$(grep -m1 '^WORKDIR=' "$_profile" | cut -d= -f2-)"
    if [[ -z "$_workdir" && -f "$_cfile" ]]; then
        _workdir="$(grep -m1 '^WORKDIR ' "$_cfile" | awk '{print $2}')"
    fi
    [[ -n "$_workdir" ]] || _workdir="unknown"

    # Packages — extract from apt/dnf/yum install lines in Containerfile.
    local _packages="See image/Containerfile."
    if [[ -f "$_cfile" ]]; then
        _packages="$(python3 - "$_cfile" <<'PYEOF'
import re, sys
with open(sys.argv[1]) as f:
    text = re.sub(r'\\\n', ' ', f.read())
skip = {'apt','apt-get','dnf','yum','install','update','upgrade',
        'reinstall','purge','remove','autoremove','clean'}
pkgs = set()
for line in text.splitlines():
    if re.search(r'(apt-get|apt|dnf|yum)\s+install', line):
        for tok in re.findall(r'\b([a-z][a-z0-9._+:-]{2,})\b', line):
            if tok not in skip:
                pkgs.add(tok)
print('\n'.join(f'- `{p}`' for p in sorted(pkgs)) or 'See image/Containerfile.')
PYEOF
)"
    fi

    # Ports — EXPOSE lines from Containerfile.
    local _ports="None exposed."
    if [[ -f "$_cfile" ]]; then
        local _expose
        _expose="$(grep '^EXPOSE ' "$_cfile" | awk '{for(i=2;i<=NF;i++) printf "- `%s`\n",$i}' || true)"
        [[ -n "$_expose" ]] && _ports="$_expose"
    fi

    # ENV vars — ENV lines from Containerfile.
    local _envvars="See image/Containerfile."
    if [[ -f "$_cfile" ]]; then
        local _env_lines
        _env_lines="$(grep '^ENV ' "$_cfile" | sed 's/^ENV /- /' || true)"
        [[ -n "$_env_lines" ]] && _envvars="$_env_lines"
    fi

    # Mounts — WORKSPACE and CONTAINER_HOME from profile.env.
    local _mounts="See profile.env."
    if [[ -f "$_profile" ]]; then
        local _ws _ch _ml=""
        _ws="$(grep -m1 '^WORKSPACE=' "$_profile" | cut -d= -f2-)"
        _ch="$(grep -m1 '^CONTAINER_HOME=' "$_profile" | cut -d= -f2-)"
        [[ -n "$_ws" ]] && _ml="- Workspace: \`${_ws}\` → \`/workspace\`"
        if [[ -n "$_ch" ]]; then
            [[ -n "$_ml" ]] && _ml+=$'\n'
            _ml+="- Persistent home: \`${_ch}\`"
        fi
        [[ -n "$_ml" ]] && _mounts="$_ml"
    fi

    local _enabled _rejected
    _enabled="$(read_session_field "$_proj" "enabled_optional_features" 2>/dev/null | paste -sd ', ' - || true)"
    _rejected="$(read_session_field "$_proj" "rejected_optional_features" 2>/dev/null | paste -sd ', ' - || true)"
    [[ -n "$_enabled" ]] || _enabled="none"
    [[ -n "$_rejected" ]] || _rejected="none"

    cat > "$_spec" <<EOF
# PODMAN_BUILDER — ${_name}

## Project purpose

See README.md and bootstrap/session.md for the interview summary.

## Final durable agent runtime

${_runtime:-unknown}

## Base image

${_base_image}

## Required packages and tools

${_packages}

## Workdir

${_workdir}

## Mounts and persistent state

${_mounts}

## Ports

${_ports}

## Environment variables

${_envvars}

## Secrets policy

Runtime secrets belong in .env or runtime-mounted files. Do not bake secrets into layers.

## Enabled optional services

${_enabled}

## Explicitly rejected features

${_rejected}
EOF
    write_session_field "$_proj" "durable_spec_path" "$_spec"
}

validate_durable_build_spec() {
    local _proj="$1"
    local _spec="${_proj}/PODMAN_BUILDER.md"
    [[ -f "$_spec" ]] || return 1
    local _needle
    for _needle in \
        "Project purpose" \
        "Final durable agent runtime" \
        "Base image" \
        "Required packages and tools" \
        "Workdir" \
        "Mounts and persistent state" \
        "Ports" \
        "Environment variables" \
        "Secrets policy" \
        "Enabled optional services" \
        "Explicitly rejected features"; do
        grep -q "$_needle" "$_spec" || return 1
    done
}

scan_for_cross_project_contamination() {
    local _proj="$1"
    local _name
    _name="$(basename "$_proj" | tr '[:upper:]' '[:lower:]')"
    local _files=(
        "${_proj}/workspace/.bashrc"
        "${_proj}/state/home/.bashrc"
        "${_proj}/README.md"
        "${_proj}/.env.example"
        "${_proj}/profile.env"
        "${_proj}/PODMAN_BUILDER.md"
    )
    local _f
    for _f in "${_files[@]}"; do
        [[ -f "$_f" ]] || continue
        if [[ "$_name" != *dotnet* ]] && rg -n "DOTNET_NOLOGO|DOTNET_CLI_TELEMETRY_OPTOUT" "$_f" >/dev/null 2>&1; then
            _warn "Cross-project contamination detected in ${_f}: unexpected .NET markers"
            return 1
        fi
        if [[ "$_name" != *esp32* && "$_name" != *idf* ]] && rg -n "PLATFORMIO_CORE_DIR|IDF_VERSION" "$_f" >/dev/null 2>&1; then
            _warn "Cross-project contamination detected in ${_f}: unexpected embedded markers"
            return 1
        fi
    done
    return 0
}

validate_durable_state_for_runtime() {
    local _proj="$1"
    local _runtime="$2"
    case "$_runtime" in
        none)
            local _dir
            for _dir in "${_KNOWN_AGENT_STATE_DIRS[@]}"; do
                [[ ! -e "${_proj}/state/home/${_dir}" ]] || return 1
            done
            ;;
        codex)
            [[ -e "${_proj}/state/home/.codex" ]] || return 1
            ;;
    esac
    return 0
}

reconcile_durable_project() {
    local _proj="$1"
    mkdir -p "${_proj}/state/home" "${_proj}/bootstrap/home"
    write_enabled_optional_features_if_missing "$_proj"
    local _runtime
    _runtime="$(infer_final_runtime "$_proj")"
    remove_ssh_outputs_if_rejected "$_proj"
    reconcile_agent_state_dirs "${_proj}/state/home" "$_runtime"
    generate_durable_build_spec "$_proj"
    if scan_for_cross_project_contamination "$_proj" && validate_durable_build_spec "$_proj"; then
        write_session_field "$_proj" "durable_reconciliation_status" "passed"
        return 0
    fi
    write_session_field "$_proj" "durable_reconciliation_status" "failed"
    return 1
}

validate_launchability_contract() {
    local _proj="$1"
    local _profile_file="${_proj}/profile.env"
    [[ -f "$_profile_file" ]] || {
        _warn "Launchability validation failed: profile.env missing"
        return 1
    }
    # Detect name mismatch: PROFILE_NAME must match the project directory basename.
    # A mismatch means the agent renamed the scaffold mid-session without the host
    # directory following. Emit a clear corrective command.
    local _dir_name _profile_name
    _dir_name="$(basename "$_proj")"
    _profile_name="$(grep -m1 '^PROFILE_NAME=' "$_profile_file" | cut -d= -f2- | tr -d '"' || true)"
    if [[ -n "$_profile_name" && "$_profile_name" != "$_dir_name" ]]; then
        _warn "Launchability validation failed: PROFILE_NAME '${_profile_name}' in profile.env does not match project directory '${_dir_name}'. The agent may have renamed the scaffold mid-session. To fix: mv '${_proj}' '$(dirname "$_proj")/${_profile_name}'"
        return 1
    fi

    if ! ( validate_profile_file "$_profile_file" ) >/dev/null 2>&1; then
        _warn "Launchability validation failed: profile.env contract is invalid"
        return 1
    fi
    validate_extra_host_paths "$_profile_file" || return 1

    local _helper="${_proj}/bootstrap/.launch-preflight.sh"
    cat > "$_helper" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source '${AI_PODMAN_JAILS_DIR}/lib/common.sh'
source '${AI_PODMAN_JAILS_DIR}/lib/profile.sh'
source '${AI_PODMAN_JAILS_DIR}/lib/policy.sh'
export AI_PODMAN_JAILS_DIR='${AI_PODMAN_JAILS_DIR}'
resolve_base_dir
load_profile '$(basename "$_proj")'
build_normal_run_args
printf '%s\n' "\${_NORMAL_RUN_ARGS[@]}"
EOF
    chmod +x "$_helper"
    bash "$_helper" >/dev/null 2>&1 || {
        _warn "Launchability validation failed: ai-launch argument assembly failed"
        return 1
    }
    local _runtime
    _runtime="$(infer_final_runtime "$_proj")"
    validate_durable_state_for_runtime "$_proj" "$_runtime" || {
        _warn "Launchability validation failed: durable runtime state does not match final runtime '${_runtime}'"
        return 1
    }
    scan_for_cross_project_contamination "$_proj" || return 1
    validate_durable_build_spec "$_proj" || return 1
    return 0
}
