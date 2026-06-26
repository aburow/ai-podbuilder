#!/usr/bin/env bash
# Agent requests use /project-relative paths; the host must resolve them safely.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SELF_DIR}/helpers/setup.bash"

_validate() {
    local _project="$1" _request="$2"
    local _helper="${_TMPDIR}/relative-helper.sh"
    cat > "$_helper" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/session.sh'
source '${LIB_DIR}/coordination.sh'
validate_request '${_project}' '${_request}'
printf 'CF=%s\nCTX=%s\n' "\$REQ_CONTAINERFILE" "\$REQ_CONTEXT_DIR"
SCRIPT
    bash "$_helper" 2>&1
}

test_relative_paths_resolve_under_project() {
    local _project="${_TMPDIR}/projects/relative"
    mkdir -p "${_project}/bootstrap" "${_project}/image"
    printf 'FROM scratch\n' > "${_project}/image/Containerfile"
    cat > "${_project}/bootstrap/session.json" <<'EOF'
{"status":"generated"}
EOF
    cat > "${_project}/bootstrap/build.request.1.json" <<'EOF'
{"request_id":1,"containerfile":"image/Containerfile","context_dir":"image","image_tag":"test:trial"}
EOF
    local out
    out="$(_validate "$_project" "${_project}/bootstrap/build.request.1.json")"
    assert_contains "CF=${_project}/image/Containerfile" "$out" || return 1
    assert_contains "CTX=${_project}/image" "$out"
}

test_path_traversal_is_rejected() {
    local _project="${_TMPDIR}/projects/traversal"
    mkdir -p "${_project}/bootstrap"
    cat > "${_project}/bootstrap/session.json" <<'EOF'
{"status":"generated"}
EOF
    cat > "${_project}/bootstrap/build.request.1.json" <<'EOF'
{"request_id":1,"containerfile":"../../outside","context_dir":"../../","image_tag":"test:trial"}
EOF
    local rc=0
    _validate "$_project" "${_project}/bootstrap/build.request.1.json" >/dev/null 2>&1 || rc=$?
    assert_failure "$rc"
}

run_test "relative build request paths resolve under project" test_relative_paths_resolve_under_project
run_test "build request path traversal is rejected"          test_path_traversal_is_rejected

print_summary "test_coordination_relative_paths"
