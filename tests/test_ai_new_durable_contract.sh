#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# 2026 - Anthony Burow - https://github.com/aburow
# ai-new durable contract tests for ai-new-9 / ai-new-10-be.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

_make_project_base() {
    local _name="$1"
    local _root="${_TMPDIR}/projects/${_name}"
    mkdir -p "${_root}/bootstrap" "${_root}/image" "${_root}/state/home" "${_root}/bootstrap/home" "${_root}/workspace"
    cat > "${_root}/bootstrap/session.json" <<EOF
{
  "project_name": "${_name}",
  "selected_agent": "codex",
  "status": "started",
  "last_updated": "2026-01-01T00:00:00Z",
  "generated_files": [],
  "containerfile_path": "",
  "quality_gate_status": "",
  "last_error": "",
  "resume_command": "ai-new ${_name} --resume",
  "build_log_path": "",
  "trial_image_tag": "",
  "static_check_status": "",
  "final_runtime": "none",
  "enabled_optional_features": [],
  "rejected_optional_features": [],
  "durable_reconciliation_status": "",
  "durable_spec_path": "",
  "pinned_agent_env": "",
  "pinned_agent_hash": ""
}
EOF
    cat > "${_root}/image/Containerfile" <<'EOF'
FROM scratch
LABEL test=true
EOF
    cat > "${_root}/profile.env" <<EOF
PROFILE_NAME="${_name}"
CONTAINER_NAME="${_name}"
IMAGE_NAME="localhost/${_name}:latest"
IMAGE_DIR="${_root}/image"
WORKSPACE="${_root}/workspace"
CONTAINER_HOME="${_root}/state/home"
BASHRC="${_root}/workspace/.bashrc"
WORKDIR="/workspace"
BUILD_ARGS=""
EXTRA_ENV=()
EXTRA_VOLUMES=()
EXTRA_DEVICES=()
EXTRA_HOSTS=()
EXTRA_RUN_ARGS=()
EOF
    cat > "${_root}/README.md" <<EOF
# ${_name}
EOF
    cat > "${_root}/.env.example" <<'EOF'
# placeholder
EOF
    echo "$_root"
}

test_reconcile_removes_durable_codex_when_final_runtime_none() {
    local _fail=0
    local _proj
    _proj="$(_make_project_base "recon-none")"
    mkdir -p "${_proj}/state/home/.codex" "${_proj}/bootstrap/home/.codex"
    printf 'durable\n' > "${_proj}/state/home/.codex/auth.json"
    printf 'bootstrap\n' > "${_proj}/bootstrap/home/.codex/auth.json"

    local helper="${_TMPDIR}/reconcile_none.sh"
    cat > "$helper" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/session.sh'
source '${LIB_DIR}/slug.sh'
source '${LIB_DIR}/profile.sh'
source '${LIB_DIR}/durable.sh'
export AI_PODMAN_JAILS_DIR='${_TMPDIR}'
reconcile_durable_project '${_proj}'
EOF
    local rc=0
    bash "$helper" >/dev/null 2>&1 || rc=$?
    assert_success "$rc" "reconcile should succeed" || _fail=1
    [[ ! -e "${_proj}/state/home/.codex" ]] || { printf '    durable .codex not removed\n' >&2; _fail=1; }
    [[ -e "${_proj}/bootstrap/home/.codex" ]] || { printf '    bootstrap .codex should remain\n' >&2; _fail=1; }
    [[ -f "${_proj}/PODMAN_BUILDER.md" ]] || { printf '    PODMAN_BUILDER.md missing\n' >&2; _fail=1; }
    return $_fail
}

test_quality_gate_fails_on_invalid_extra_env_contract() {
    local _fail=0
    local _proj
    _proj="$(_make_project_base "badenv")"
    python3 - "${_proj}/bootstrap/session.json" <<'PYEOF'
import json, sys
path = sys.argv[1]
with open(path) as f:
    data = json.load(f)
data["final_runtime"] = "none"
with open(path, "w") as f:
    json.dump(data, f, indent=2)
PYEOF
    python3 - "${_proj}/profile.env" <<'PYEOF'
from pathlib import Path
path = Path(__import__("sys").argv[1])
text = path.read_text()
text = text.replace("EXTRA_ENV=()", 'EXTRA_ENV=("ENABLE_SSHD=1")')
path.write_text(text)
PYEOF

    local helper="${_TMPDIR}/gate_badenv.sh"
    cat > "$helper" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/session.sh'
source '${LIB_DIR}/slug.sh'
source '${LIB_DIR}/quality_gate.sh'
export AI_PODMAN_JAILS_DIR='${_TMPDIR}'
export SLUG='badenv'
export SKIP_TRIAL_BUILD=0
run_quality_gate '${_proj}' 1 '${_proj}/image/Containerfile' '${_proj}/image' 'localhost/ai-new/badenv:trial' 'test' 0
EOF
    bash "$helper" >/dev/null 2>&1 || true
    local _status
    _status="$(grep -oP '"status"\s*:\s*"\K[^"]+' "${_proj}/bootstrap/session.json" 2>/dev/null || true)"
    # Build may succeed (FROM scratch) or fail depending on environment; either way
    # validation must block completion (quality-gate-failed or quality-gate-inconsistent).
    [[ "$_status" == "quality-gate-failed" || "$_status" == "quality-gate-inconsistent" ]] \
        || { printf '    ASSERT fail: expected gate-failed or gate-inconsistent, got: %s\n' "$_status" >&2; _fail=1; }
    return $_fail
}

test_quality_gate_fails_when_enabled_host_path_missing() {
    local _fail=0
    local _proj
    _proj="$(_make_project_base "misshost")"
    python3 - "${_proj}/bootstrap/session.json" <<'PYEOF'
import json, sys
path = sys.argv[1]
with open(path) as f:
    data = json.load(f)
data["final_runtime"] = "none"
data["enabled_optional_features"] = ["ssh"]
with open(path, "w") as f:
    json.dump(data, f, indent=2)
PYEOF
    python3 - "${_proj}/profile.env" <<'PYEOF'
from pathlib import Path
path = Path(__import__("sys").argv[1])
text = path.read_text()
text = text.replace("EXTRA_VOLUMES=()", 'EXTRA_VOLUMES=("-v" "/definitely/missing/id_ed25519.pub:/run/secrets/key:ro,z")')
path.write_text(text)
PYEOF

    local helper="${_TMPDIR}/gate_missing_host.sh"
    cat > "$helper" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/session.sh'
source '${LIB_DIR}/slug.sh'
source '${LIB_DIR}/quality_gate.sh'
export AI_PODMAN_JAILS_DIR='${_TMPDIR}'
export SLUG='misshost'
export SKIP_TRIAL_BUILD=0
run_quality_gate '${_proj}' 1 '${_proj}/image/Containerfile' '${_proj}/image' 'localhost/ai-new/misshost:trial' 'test' 0
EOF
    bash "$helper" >/dev/null 2>&1 || true
    local _status
    _status="$(grep -oP '"status"\s*:\s*"\K[^"]+' "${_proj}/bootstrap/session.json" 2>/dev/null || true)"
    [[ "$_status" == "quality-gate-failed" || "$_status" == "quality-gate-inconsistent" ]] \
        || { printf '    ASSERT fail: expected gate-failed or gate-inconsistent, got: %s\n' "$_status" >&2; _fail=1; }
    return $_fail
}

test_launchability_contract_allows_missing_optional_host_config_mounts() {
    local _fail=0
    local _proj
    _proj="$(_make_project_base "optional-config")"
    ln -s "${LIB_DIR}" "${_TMPDIR}/lib"
    mkdir -p "${_TMPDIR}/home/.codex"
    python3 - "${_proj}/profile.env" "${_TMPDIR}" <<'PYEOF'
from pathlib import Path
import sys
path = Path(sys.argv[1])
tmpdir = Path(sys.argv[2])
text = path.read_text()
text = text.replace(
    'EXTRA_VOLUMES=()',
    'EXTRA_VOLUMES=("-v" "{home}/home/.codex:/home/dev/.codex:rw" "-v" "{home}/home/.claude:/home/dev/.claude:rw" "-v" "{home}/home/.config/gh:/home/dev/.config/gh:rw")'.format(home=tmpdir)
)
path.write_text(text)
PYEOF

    local helper="${_TMPDIR}/launchability_optional_config.sh"
    cat > "$helper" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/session.sh'
source '${LIB_DIR}/slug.sh'
source '${LIB_DIR}/profile.sh'
source '${LIB_DIR}/policy.sh'
source '${LIB_DIR}/durable.sh'
export AI_PODMAN_JAILS_DIR='${_TMPDIR}'
export HOME='${_TMPDIR}/home'
reconcile_durable_project '${_proj}'
validate_launchability_contract '${_proj}'
EOF
    local rc=0
    bash "$helper" >/dev/null 2>&1 || rc=$?
    assert_success "$rc" "missing optional config mounts should not fail launchability validation" || _fail=1
    return $_fail
}

test_quality_gate_fails_on_cross_project_contamination() {
    local _fail=0
    local _proj
    _proj="$(_make_project_base "alex")"
    python3 - "${_proj}/bootstrap/session.json" <<'PYEOF'
import json, sys
path = sys.argv[1]
with open(path) as f:
    data = json.load(f)
data["final_runtime"] = "none"
with open(path, "w") as f:
    json.dump(data, f, indent=2)
PYEOF
    printf 'export DOTNET_NOLOGO=1\n' > "${_proj}/workspace/.bashrc"

    local helper="${_TMPDIR}/gate_contam.sh"
    cat > "$helper" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/session.sh'
source '${LIB_DIR}/slug.sh'
source '${LIB_DIR}/quality_gate.sh'
export AI_PODMAN_JAILS_DIR='${_TMPDIR}'
export SLUG='alex'
export SKIP_TRIAL_BUILD=0
run_quality_gate '${_proj}' 1 '${_proj}/image/Containerfile' '${_proj}/image' 'localhost/ai-new/alex:trial' 'test' 0
EOF
    bash "$helper" >/dev/null 2>&1 || true
    local _status
    _status="$(grep -oP '"status"\s*:\s*"\K[^"]+' "${_proj}/bootstrap/session.json" 2>/dev/null || true)"
    [[ "$_status" == "quality-gate-failed" || "$_status" == "quality-gate-inconsistent" ]] \
        || { printf '    ASSERT fail: expected gate-failed or gate-inconsistent, got: %s\n' "$_status" >&2; _fail=1; }
    return $_fail
}

run_test "reconcile removes durable codex state when final runtime is none" test_reconcile_removes_durable_codex_when_final_runtime_none
run_test "quality gate fails on invalid EXTRA_ENV contract"                 test_quality_gate_fails_on_invalid_extra_env_contract
run_test "quality gate fails when enabled host path is missing"             test_quality_gate_fails_when_enabled_host_path_missing
run_test "launchability allows missing optional host config mounts"         test_launchability_contract_allows_missing_optional_host_config_mounts
run_test "quality gate fails on cross-project contamination"                test_quality_gate_fails_on_cross_project_contamination

print_summary "test_ai_new_durable_contract"
