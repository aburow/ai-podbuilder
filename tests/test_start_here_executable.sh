#!/usr/bin/env bash
# T1b — start-here.sh scaffold copy has execute bit regardless of host mode (AC2, B1, R2.2).
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

# ── Helpers ───────────────────────────────────────────────────────────────────

_run_create_scaffold_with_source_mode() {
    local _name="$1" _mode="$2"
    # Place a start-here.sh stub with the given mode into AI_PODMAN_JAILS_DIR.
    mkdir -p "${_TMPDIR}/lib"
    printf '#!/usr/bin/env bash\n# stub\n' > "${_TMPDIR}/lib/start-here.sh"
    chmod "$_mode" "${_TMPDIR}/lib/start-here.sh"

    mkdir -p "${_TMPDIR}/config/agents.d"

    cat > "${_TMPDIR}/scaffold_helper.sh" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
source '${LIB_DIR}/common.sh'
source '${LIB_DIR}/registry.sh'
source '${LIB_DIR}/slug.sh'
source '${LIB_DIR}/session.sh'
source '${LIB_DIR}/scaffold.sh'
export AI_PODMAN_JAILS_DIR='${_TMPDIR}'
export AI_PODMAN_AGENTS_DIR='${_TMPDIR}/config/agents.d'
project_paths '${_name}'
create_scaffold '${_name}'
SCRIPT
    bash "${_TMPDIR}/scaffold_helper.sh" 2>&1
}

# ── Tests ─────────────────────────────────────────────────────────────────────

test_execute_bit_set_when_source_is_readonly() {
    # Source mode 0644 (no execute bit) → copy must still be executable (R2.2).
    local _fail=0
    _run_create_scaffold_with_source_mode "proj_ro" "0644" >/dev/null 2>&1 || true

    local _copy="${_TMPDIR}/projects/proj_ro/bootstrap/home/start-here.sh"
    [[ -f "$_copy" ]] || {
        printf '    start-here.sh copy not found\n' >&2
        return 1
    }
    [[ -x "$_copy" ]] || {
        printf '    start-here.sh copy is NOT executable (mode 0644 host should not prevent +x)\n' >&2
        _fail=1
    }
    return $_fail
}

test_execute_bit_set_when_source_has_no_bits() {
    # Source mode 0444 → copy must still be executable.
    local _fail=0
    _run_create_scaffold_with_source_mode "proj_noexec" "0444" >/dev/null 2>&1 || true

    local _copy="${_TMPDIR}/projects/proj_noexec/bootstrap/home/start-here.sh"
    [[ -f "$_copy" ]] || {
        printf '    start-here.sh copy not found\n' >&2
        return 1
    }
    [[ -x "$_copy" ]] || {
        printf '    start-here.sh copy is NOT executable (host mode 0444 must not prevent +x)\n' >&2
        _fail=1
    }
    return $_fail
}

test_execute_bit_set_when_source_is_already_executable() {
    # Source mode 0755 → copy is also executable (trivial case — confirm no regression).
    local _fail=0
    _run_create_scaffold_with_source_mode "proj_exec" "0755" >/dev/null 2>&1 || true

    local _copy="${_TMPDIR}/projects/proj_exec/bootstrap/home/start-here.sh"
    [[ -f "$_copy" ]] || {
        printf '    start-here.sh copy not found\n' >&2
        return 1
    }
    [[ -x "$_copy" ]] || {
        printf '    start-here.sh copy is NOT executable\n' >&2
        _fail=1
    }
    return $_fail
}

test_scaffold_copy_is_distinct_from_source() {
    # The scaffold copy must be a copy, not a symlink back to the source.
    local _fail=0
    _run_create_scaffold_with_source_mode "proj_copy" "0644" >/dev/null 2>&1 || true

    local _copy="${_TMPDIR}/projects/proj_copy/bootstrap/home/start-here.sh"
    [[ -f "$_copy" ]] || {
        printf '    start-here.sh copy not found\n' >&2
        return 1
    }
    if [[ -L "$_copy" ]]; then
        printf '    start-here.sh is a symlink — must be a real copy so the execute bit can be set independently\n' >&2
        _fail=1
    fi
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "copy executable even when source mode is 0644"          test_execute_bit_set_when_source_is_readonly
run_test "copy executable even when source mode is 0444"          test_execute_bit_set_when_source_has_no_bits
run_test "copy executable when source already has execute bit"    test_execute_bit_set_when_source_is_already_executable
run_test "scaffold copy is a real file, not a symlink"            test_scaffold_copy_is_distinct_from_source

print_summary "test_start_here_executable"
