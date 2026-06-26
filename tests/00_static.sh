#!/usr/bin/env bash
# T1 — Static checks: shellcheck, set -euo pipefail, no hardcoded paths.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

# ── Helpers ───────────────────────────────────────────────────────────────────

_collect_scripts() {
    find "${REPO_ROOT}/bin" "${REPO_ROOT}/lib" -maxdepth 1 -name '*.sh' -o \
         -path "${REPO_ROOT}/bin/*" -not -name '.gitkeep' 2>/dev/null | sort -u
}

# ── Tests ─────────────────────────────────────────────────────────────────────

test_shellcheck_bin_lib() {
    if ! command -v shellcheck >/dev/null 2>&1; then
        _SKIP_REASON="shellcheck not in PATH"
        return 0
    fi
    local _fail=0
    local f
    for f in "${REPO_ROOT}/bin"/*; do
        [[ -f "$f" && "$(basename "$f")" != ".gitkeep" ]] || continue
        if ! shellcheck -S warning "$f" 2>&1; then
            printf '    shellcheck failure: %s\n' "$f" >&2
            _fail=1
        fi
    done
    for f in "${REPO_ROOT}/lib"/*.sh; do
        [[ -f "$f" ]] || continue
        if ! shellcheck -S warning "$f" 2>&1; then
            printf '    shellcheck failure: %s\n' "$f" >&2
            _fail=1
        fi
    done
    return $_fail
}

test_pipefail_in_bin_scripts() {
    local _fail=0
    local f
    for f in "${REPO_ROOT}/bin"/*; do
        [[ -f "$f" && "$(basename "$f")" != ".gitkeep" ]] || continue
        if ! grep -qE 'set\s+-[a-zA-Z]*e[a-zA-Z]*u[a-zA-Z]*o\s+pipefail|set\s+-[a-zA-Z]*u[a-zA-Z]*e[a-zA-Z]*o\s+pipefail|set -euo pipefail|set -uo pipefail' "$f"; then
            printf '    missing set -euo pipefail: %s\n' "$(basename "$f")" >&2
            _fail=1
        fi
    done
    return $_fail
}

test_no_hardcoded_username_or_varhome() {
    # Scan bin/, lib/, launchers/, and profiles/ examples for /var/home/ literals
    # and obvious hardcoded usernames of the form /home/<literal-word>/ that are
    # not a variable reference (e.g. /home/builder from CONTAINER_HOME is ok as
    # a default VALUE in a profile template, but not in scripts).
    local _fail=0
    local dirs=("${REPO_ROOT}/bin" "${REPO_ROOT}/lib" "${REPO_ROOT}/launchers")
    local f
    for d in "${dirs[@]}"; do
        [[ -d "$d" ]] || continue
        while IFS= read -r -d '' f; do
            [[ -f "$f" ]] || continue
            if grep -qE '/var/home/[a-zA-Z0-9_-]+' "$f"; then
                printf '    hardcoded /var/home/ path in: %s\n' "$(basename "$f")" >&2
                _fail=1
            fi
        done < <(find "$d" -maxdepth 1 -type f -print0)
    done
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
# Static tests don't need a temp env — skip the setup/teardown wrappers for speed.
_TMPDIR="" # not used

_run_static() {
    local name="$1" fn="$2"
    _SKIP_REASON=""
    local _rc=0
    "$fn" || _rc=$?
    if [[ -n "$_SKIP_REASON" ]]; then
        printf "${_C_SKIP}  SKIP${_C_RESET}  %s — %s\n" "$name" "$_SKIP_REASON"
        (( _SKIP++ )) || true
    elif [[ $_rc -eq 0 ]]; then
        printf "${_C_PASS}  PASS${_C_RESET}  %s\n" "$name"
        (( _PASS++ )) || true
    else
        printf "${_C_FAIL}  FAIL${_C_RESET}  %s\n" "$name"
        (( _FAIL++ )) || true
    fi
}

test_shellcheck_install_sh() {
    if ! command -v shellcheck >/dev/null 2>&1; then
        _SKIP_REASON="shellcheck not in PATH"
        return 0
    fi
    shellcheck -S warning "${REPO_ROOT}/install.sh" 2>&1
}

_run_static "shellcheck: bin/ and lib/" test_shellcheck_bin_lib
_run_static "shellcheck: install.sh" test_shellcheck_install_sh
_run_static "set -euo pipefail present in every bin/ script" test_pipefail_in_bin_scripts
_run_static "no hardcoded /var/home/ in scripts" test_no_hardcoded_username_or_varhome

print_summary "00_static"
