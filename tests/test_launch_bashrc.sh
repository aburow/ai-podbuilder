#!/usr/bin/env bash
# Normal and builder shell startup must source the project rcfile inside the container.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

_write_profile() {
    local _name="$1"
    local _img="$2"
    cat > "${_TMPDIR}/profiles/${_name}.env" <<EOF
PROFILE_NAME="${_name}"
CONTAINER_NAME="test-${_name}-$$"
IMAGE_NAME="${_img}"
IMAGE_DIR="${_TMPDIR}/${_name}-image"
WORKSPACE="${_TMPDIR}/${_name}-workspace"
CONTAINER_HOME="${_TMPDIR}/${_name}-home"
BASHRC="${_TMPDIR}/${_name}-workspace/.bashrc"
WORKDIR="/workspace"
BUILD_ARGS=""
EOF
    mkdir -p "${_TMPDIR}/${_name}-workspace" "${_TMPDIR}/${_name}-home"
    : > "${_TMPDIR}/${_name}-workspace/.bashrc"
}

test_normal_container_uses_workspace_rcfile() {
    local _fail=0
    _write_profile "shellrc" "test-shellrc-img"

    local out rc=0
    out="$(CODEX_JAILS_DIR="$_TMPDIR" PATH="${STUBS_DIR}:${PATH}" bash -c "
        source '${LIB_DIR}/common.sh'
        source '${LIB_DIR}/profile.sh'
        source '${LIB_DIR}/policy.sh'
        source '${LIB_DIR}/container.sh'
        resolve_base_dir
        load_profile shellrc
        create_normal_container
    " 2>&1)" || rc=$?

    assert_success "$rc" "normal container create should succeed with stub podman" || _fail=1
    assert_contains "bash --rcfile /workspace/.bashrc -i" "$out" \
        "normal shell must start with the project rcfile" || _fail=1
    return "$_fail"
}

test_builder_shell_uses_workspace_rcfile() {
    local _fail=0
    _write_profile "builderrc" "test-builderrc-img"

    local out rc=0
    out="$(CODEX_JAILS_DIR="$_TMPDIR" PATH="${STUBS_DIR}:${PATH}" bash -c "
        source '${LIB_DIR}/common.sh'
        source '${LIB_DIR}/profile.sh'
        source '${LIB_DIR}/policy.sh'
        source '${LIB_DIR}/container.sh'
        resolve_base_dir
        load_profile builderrc
        run_builder_ephemeral bash --rcfile \"\$BASHRC_CONTAINER\" -i
    " 2>&1)" || rc=$?

    assert_success "$rc" "builder shell should succeed with stub podman" || _fail=1
    assert_contains "bash --rcfile /workspace/.bashrc -i" "$out" \
        "builder shell must also start with the project rcfile" || _fail=1
    return "$_fail"
}

run_test "normal shell container uses workspace rcfile"  test_normal_container_uses_workspace_rcfile
run_test "builder shell uses workspace rcfile"          test_builder_shell_uses_workspace_rcfile

print_summary "test_launch_bashrc"
