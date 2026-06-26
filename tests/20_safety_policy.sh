#!/usr/bin/env bash
# T3 — Normal-mode safety policy inspection via DRY_RUN (AC2).
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

_dry_run_esp32() {
    DRY_RUN=1 AI_PODMAN_JAILS_DIR="$_TMPDIR" PATH="${STUBS_DIR}:${PATH}" \
        "${BIN_DIR}/ai-launch" esp32 shell 2>/dev/null
}

# ── Required flags ────────────────────────────────────────────────────────────

test_userns_keep_id_present() {
    local _fail=0
    local out; out="$(_dry_run_esp32)"
    assert_contains "--userns=keep-id" "$out" || _fail=1
    return $_fail
}

test_group_add_keep_groups_present() {
    local _fail=0
    local out; out="$(_dry_run_esp32)"
    assert_contains "--group-add" "$out" || _fail=1
    assert_contains "keep-groups"  "$out" || _fail=1
    return $_fail
}

test_no_new_privileges_present() {
    local _fail=0
    local out; out="$(_dry_run_esp32)"
    assert_contains "no-new-privileges" "$out" || _fail=1
    return $_fail
}

test_selinux_default_label_disable_present() {
    local _fail=0
    local out; out="$(_dry_run_esp32)"
    assert_contains "label=disable" "$out" || _fail=1
    return $_fail
}

test_container_home_env_present() {
    local _fail=0
    local out; out="$(_dry_run_esp32)"
    # -e HOME=<something> must appear
    assert_contains "HOME=" "$out" || _fail=1
    return $_fail
}

test_workspace_and_home_bind_mounts_present() {
    local _fail=0
    local out; out="$(_dry_run_esp32)"
    local workspace_bind_count home_bind_count
    workspace_bind_count="$(printf '%s\n' "$out" | grep -cE ':/workspace' || true)"
    home_bind_count="$(printf '%s\n' "$out" | grep -cF '/home/builder:/home/builder:Z' || true)"
    [[ "$workspace_bind_count" -eq 1 ]] \
        || { printf '    expected exactly 1 workspace bind mount, got %d\n' "$workspace_bind_count" >&2; _fail=1; }
    [[ "$home_bind_count" -ge 1 ]] \
        || { printf '    expected container home bind mount to be present\n' >&2; _fail=1; }
    return $_fail
}

# ── Forbidden flags ───────────────────────────────────────────────────────────

test_no_privileged_in_normal_mode() {
    local _fail=0
    local out; out="$(_dry_run_esp32)"
    assert_not_contains "--privileged" "$out" || _fail=1
    return $_fail
}

test_no_host_home_mount() {
    local _fail=0
    local out; out="$(_dry_run_esp32)"
    # Host $HOME must not appear as a bind source
    local host_home="${HOME:-/root}"
    assert_not_contains "${host_home}:" "$out" "host HOME must not be mounted" || _fail=1
    return $_fail
}

test_no_docker_or_podman_socket() {
    local _fail=0
    local out; out="$(_dry_run_esp32)"
    assert_not_contains "docker.sock" "$out" || _fail=1
    assert_not_contains "podman.sock" "$out" || _fail=1
    assert_not_contains "/run/user"   "$out" || _fail=1
    return $_fail
}

test_no_ssh_gnupg_config_mounts() {
    local _fail=0
    local out; out="$(_dry_run_esp32)"
    assert_not_contains ".ssh"    "$out" || _fail=1
    assert_not_contains ".gnupg"  "$out" || _fail=1
    assert_not_contains ".config" "$out" || _fail=1
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "normal mode: --userns=keep-id present"        test_userns_keep_id_present
run_test "normal mode: --group-add keep-groups present" test_group_add_keep_groups_present
run_test "normal mode: no-new-privileges present"       test_no_new_privileges_present
run_test "normal mode: label=disable present by default" test_selinux_default_label_disable_present
run_test "normal mode: HOME env override present"       test_container_home_env_present
run_test "normal mode: workspace and home bind mounts present" test_workspace_and_home_bind_mounts_present
run_test "normal mode: no --privileged"                 test_no_privileged_in_normal_mode
run_test "normal mode: no host \$HOME mount"            test_no_host_home_mount
run_test "normal mode: no Docker/Podman socket"         test_no_docker_or_podman_socket
run_test "normal mode: no .ssh/.gnupg/.config mounts"  test_no_ssh_gnupg_config_mounts

print_summary "20_safety_policy"
