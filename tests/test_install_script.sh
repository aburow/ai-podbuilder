#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# 2026 - Anthony Burow - https://github.com/aburow
# Integration tests for install.sh — offline via AI_PODMAN_INSTALL_TARBALL fixture.
# Covers test plan milestones 1–6 (M7 static lint is in 00_static.sh).
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

INSTALL_SH="${REPO_ROOT}/install.sh"

# ── Module-level fixture: tarball built once ───────────────────────────────────
_MOD_TMP="$(mktemp -d)"
FIXTURE_TARBALL="${_MOD_TMP}/fixture.tar.gz"
tar -czf "$FIXTURE_TARBALL" \
    --exclude='./.git' \
    -C "$REPO_ROOT" \
    --transform 's|^\./|ai-podbuilder-test/|' \
    . 2>/dev/null
trap 'rm -rf "$_MOD_TMP"' EXIT

# ── Helpers ────────────────────────────────────────────────────────────────────

# _run_install <sandbox_home> [install.sh args...]
# Runs install.sh with sandboxed HOME and offline tarball fixture.
_run_install() {
    local home="$1"; shift
    env -u AI_PODMAN_JAILS_DIR -u AI_PODMAN_JAILS_DIR \
        HOME="$home" \
        AI_PODMAN_INSTALL_TARBALL="$FIXTURE_TARBALL" \
        bash "$INSTALL_SH" "$@"
}

# ── M1: Harness & baseline ────────────────────────────────────────────────────

test_fixture_baseline_install() {
    local h="${_TMPDIR}/home"
    mkdir -p "$h"
    local root="${h}/ai-podman-jails"
    local rc=0
    _run_install "$h" "$root" >/dev/null 2>&1 || rc=$?
    assert_success "$rc" "baseline install should exit 0 offline" || return 1
    [[ -d "$root/bin" ]] || { printf '    bin/ not created\n' >&2; return 1; }
}

# ── M2: Fresh install & managed-set selection ─────────────────────────────────

test_default_install_root() {
    local h="${_TMPDIR}/home"
    mkdir -p "$h"
    local rc=0
    _run_install "$h" >/dev/null 2>&1 || rc=$?
    assert_success "$rc" "default root install" || return 1
    [[ -d "${h}/ai-podman-jails/bin" ]] || {
        printf '    default root %s/ai-podman-jails not created\n' "$h" >&2
        return 1
    }
}

test_custom_install_root() {
    local h="${_TMPDIR}/home"
    mkdir -p "$h"
    local root="${h}/my-custom-root"
    local rc=0
    _run_install "$h" "$root" >/dev/null 2>&1 || rc=$?
    assert_success "$rc" "custom root install" || return 1
    [[ -d "$root/bin" ]] || { printf '    custom root not created\n' >&2; return 1; }
    [[ ! -d "${h}/ai-podman-jails" ]] || {
        printf '    default root created despite positional override\n' >&2; return 1
    }
}

test_managed_set_present() {
    local h="${_TMPDIR}/home"
    mkdir -p "$h"
    local root="${h}/install"
    _run_install "$h" "$root" >/dev/null 2>&1 || true
    local _fail=0
    local item
    for item in bin lib config templates prompts profiles; do
        [[ -e "$root/$item" ]] || {
            printf '    managed item absent: %s\n' "$item" >&2; _fail=1
        }
    done
    # profiles/*.example must exist
    local ex_count
    ex_count="$(find "$root/profiles" -maxdepth 1 -name '*.example' 2>/dev/null | wc -l)"
    [[ "$ex_count" -gt 0 ]] || {
        printf '    no profiles/*.example installed\n' >&2; _fail=1
    }
    return $_fail
}

test_excluded_dirs_absent() {
    local h="${_TMPDIR}/home"
    mkdir -p "$h"
    local root="${h}/install"
    _run_install "$h" "$root" >/dev/null 2>&1 || true
    local _fail=0
    local dir
    for dir in lifecycle tests doc docs; do
        [[ ! -e "$root/$dir" ]] || {
            printf '    excluded dir present: %s\n' "$dir" >&2; _fail=1
        }
    done
    return $_fail
}

test_executables() {
    local h="${_TMPDIR}/home"
    mkdir -p "$h"
    local root="${h}/install"
    _run_install "$h" "$root" >/dev/null 2>&1 || true
    local _fail=0
    local f
    for f in "$root"/bin/*; do
        [[ -f "$f" ]] || continue
        [[ -x "$f" ]] || {
            printf '    not executable: %s\n' "$(basename "$f")" >&2; _fail=1
        }
    done
    [[ -x "$root/lib/start-here.sh" ]] || {
        printf '    start-here.sh not executable\n' >&2; _fail=1
    }
    return $_fail
}

test_commands_on_path() {
    local h="${_TMPDIR}/home"
    mkdir -p "$h"
    local root="${h}/install"
    local rc=0
    _run_install "$h" "$root" >/dev/null 2>&1 || rc=$?
    assert_success "$rc" "install for path test" || return 1
    local env_file="${h}/.bashrc.d/podbuilder.sh"
    [[ -f "$env_file" ]] || { printf '    env file absent\n' >&2; return 1; }
    rc=0
    bash -c "
        source '$env_file'
        command -v ai-build >/dev/null &&
        command -v ai-launch >/dev/null &&
        command -v ai-list >/dev/null &&
        command -v ai-new >/dev/null &&
        command -v ai-terminal >/dev/null
    " || rc=$?
    assert_success "$rc" "five commands should resolve on PATH after source" || return 1
}

# ── M3: Env file & bashrc guard idempotency ───────────────────────────────────

test_env_file_content() {
    local h="${_TMPDIR}/home"
    mkdir -p "$h"
    local root="${h}/install"
    _run_install "$h" "$root" >/dev/null 2>&1 || true
    local ef="${h}/.bashrc.d/podbuilder.sh"
    [[ -f "$ef" ]] || { printf '    env file not created\n' >&2; return 1; }
    local _fail=0
    grep -q "AI_PODMAN_JAILS_DIR" "$ef" || {
        printf '    AI_PODMAN_JAILS_DIR not exported\n' >&2; _fail=1
    }
    grep -q 'PATH' "$ef" || {
        printf '    PATH not set in env file\n' >&2; _fail=1
    }
    return $_fail
}

test_env_file_idempotent() {
    local h="${_TMPDIR}/home"
    mkdir -p "$h"
    local root="${h}/install"
    _run_install "$h" "$root" >/dev/null 2>&1 || true
    local ef="${h}/.bashrc.d/podbuilder.sh"
    local before after
    before="$(cat "$ef" 2>/dev/null)"
    _run_install "$h" "$root" >/dev/null 2>&1 || true
    after="$(cat "$ef" 2>/dev/null)"
    assert_eq "$before" "$after" "env file should be identical after second run" || return 1
}

test_bashrc_guard_idempotent() {
    local h="${_TMPDIR}/home"
    mkdir -p "$h"
    local root="${h}/install"
    _run_install "$h" "$root" >/dev/null 2>&1 || true
    _run_install "$h" "$root" >/dev/null 2>&1 || true
    local bashrc="${h}/.bashrc"
    local marker_count
    marker_count="$(grep -c 'ai-podbuilder' "$bashrc" 2>/dev/null || true)"
    [[ "$marker_count" -le 2 ]] || {
        printf '    bashrc marker duplicated: %d occurrences\n' "$marker_count" >&2; return 1
    }
    # ~/.profile and ~/.zshrc must not be written
    [[ ! -f "${h}/.profile" && ! -f "${h}/.zshrc" ]] || {
        printf '    ~/.profile or ~/.zshrc was written by installer\n' >&2; return 1
    }
}

# ── M4: Idempotent update & user-data preservation ───────────────────────────

test_update_preserves_user_data() {
    local h="${_TMPDIR}/home"
    mkdir -p "$h"
    local root="${h}/install"
    local rc=0
    _run_install "$h" "$root" >/dev/null 2>&1 || rc=$?
    assert_success "$rc" "first install" || return 1
    # Pre-seed user data that the installer must not touch
    mkdir -p "$root/projects/demo"
    printf 'user-data\n' > "$root/projects/demo/README.md"
    printf 'mine-profile\n' > "$root/profiles/mine.env"
    rc=0
    _run_install "$h" "$root" >/dev/null 2>&1 || rc=$?
    assert_success "$rc" "second install (update)" || return 1
    [[ -f "$root/projects/demo/README.md" ]] || {
        printf '    projects/demo/ was removed on update\n' >&2; return 1
    }
    [[ -f "$root/profiles/mine.env" ]] || {
        printf '    profiles/mine.env was removed on update\n' >&2; return 1
    }
    grep -q 'mine-profile' "$root/profiles/mine.env" || {
        printf '    profiles/mine.env content corrupted\n' >&2; return 1
    }
}

# ── M5: Prerequisite & failure safety ────────────────────────────────────────

test_missing_podman_exits_nonzero() {
    local h="${_TMPDIR}/home"
    mkdir -p "$h"
    local root="${h}/install"
    # Shadow podman with a stub that always exits 1 so check_prereqs fails
    local fakebin="${_TMPDIR}/fakebin-nopodman"
    mkdir -p "$fakebin"
    printf '#!/usr/bin/env bash\nexit 1\n' > "$fakebin/podman"
    chmod +x "$fakebin/podman"
    local out rc=0
    out="$(env -u AI_PODMAN_JAILS_DIR -u AI_PODMAN_JAILS_DIR \
        HOME="$h" AI_PODMAN_INSTALL_TARBALL="$FIXTURE_TARBALL" \
        PATH="$fakebin:${PATH}" \
        bash "$INSTALL_SH" "$root" 2>&1)" || rc=$?
    assert_failure "$rc" "broken podman should exit non-zero" || return 1
    assert_contains "podman" "$out" "error message should mention podman" || return 1
    [[ ! -d "$root/bin" ]] || {
        printf '    install root was partially written despite prereq failure\n' >&2; return 1
    }
}

test_corrupt_tarball_fresh_install() {
    local h="${_TMPDIR}/home"
    mkdir -p "$h"
    local root="${h}/install"
    local corrupt="${_TMPDIR}/corrupt.tar.gz"
    printf 'NOT A VALID TARBALL\n' > "$corrupt"
    local rc=0
    env -u AI_PODMAN_JAILS_DIR -u AI_PODMAN_JAILS_DIR \
        HOME="$h" AI_PODMAN_INSTALL_TARBALL="$corrupt" \
        bash "$INSTALL_SH" "$root" >/dev/null 2>&1 || rc=$?
    assert_failure "$rc" "corrupt tarball should exit non-zero" || return 1
    # Fresh install: root must not look complete (no bin/)
    [[ ! -d "$root/bin" ]] || {
        printf '    install root/bin created from corrupt tarball\n' >&2; return 1
    }
}

test_corrupt_tarball_leaves_prior_install_intact() {
    local h="${_TMPDIR}/home"
    mkdir -p "$h"
    local root="${h}/install"
    local rc=0
    _run_install "$h" "$root" >/dev/null 2>&1 || rc=$?
    assert_success "$rc" "first install must succeed" || return 1
    # Count files in bin/ before corrupt run
    local before_count
    before_count="$(find "$root/bin" -type f | wc -l)"
    local corrupt="${_TMPDIR}/corrupt2.tar.gz"
    printf 'GARBAGE\n' > "$corrupt"
    rc=0
    env -u AI_PODMAN_JAILS_DIR -u AI_PODMAN_JAILS_DIR \
        HOME="$h" AI_PODMAN_INSTALL_TARBALL="$corrupt" \
        bash "$INSTALL_SH" "$root" >/dev/null 2>&1 || rc=$?
    assert_failure "$rc" "corrupt tarball update should exit non-zero" || return 1
    local after_count
    after_count="$(find "$root/bin" -type f | wc -l)"
    assert_eq "$before_count" "$after_count" "managed files should be intact after failed update" || return 1
}

# ── M6: Invocation forms & legacy migration ───────────────────────────────────

test_pipe_invocation() {
    local h="${_TMPDIR}/home"
    mkdir -p "$h"
    local root="${h}/install"
    local rc=0
    # cat install.sh | bash -s -- <root>
    env -u AI_PODMAN_JAILS_DIR \
        HOME="$h" AI_PODMAN_INSTALL_TARBALL="$FIXTURE_TARBALL" \
        bash -s -- "$root" < "$INSTALL_SH" >/dev/null 2>&1 || rc=$?
    assert_success "$rc" "pipe invocation should exit 0" || return 1
    local _fail=0
    local item
    for item in bin lib config templates prompts profiles; do
        [[ -e "$root/$item" ]] || {
            printf '    pipe invocation: missing %s\n' "$item" >&2; _fail=1
        }
    done
    return $_fail
}

test_help_flag() {
    local h="${_TMPDIR}/home"
    mkdir -p "$h"
    local out rc=0
    # bash install.sh --help
    out="$(_run_install "$h" --help 2>&1)" || rc=$?
    assert_success "$rc" "bash install.sh --help should exit 0" || return 1
    assert_contains "Usage" "$out" "--help should print usage" || return 1
    rc=0
    # cat install.sh | bash -s -- --help
    out="$(env -u AI_PODMAN_JAILS_DIR \
        HOME="$h" AI_PODMAN_INSTALL_TARBALL="$FIXTURE_TARBALL" \
        bash -s -- --help < "$INSTALL_SH" 2>&1)" || rc=$?
    assert_success "$rc" "piped --help should exit 0" || return 1
    assert_contains "Usage" "$out" "piped --help should print usage" || return 1
}


# ── Run ────────────────────────────────────────────────────────────────────────

run_test "M1: fixture build and baseline fresh install"            test_fixture_baseline_install
run_test "M2: default install root is \$HOME/ai-podman-jails"     test_default_install_root
run_test "M2: positional arg overrides install root"               test_custom_install_root
run_test "M2: managed set present (bin lib config etc)"            test_managed_set_present
run_test "M2: excluded dirs absent (lifecycle tests doc docs)"     test_excluded_dirs_absent
run_test "M2: all installed bin/* and start-here.sh are +x"       test_executables
run_test "M2: five commands resolve on PATH after source env-file" test_commands_on_path
run_test "M3: env file exports AI_PODMAN_JAILS_DIR"               test_env_file_content
run_test "M3: second run does not corrupt env file"               test_env_file_idempotent
run_test "M3: bashrc guard is idempotent; profile/zshrc unwritten" test_bashrc_guard_idempotent
run_test "M4: update preserves projects/ and user profiles/*.env"  test_update_preserves_user_data
run_test "M5: missing podman exits non-zero, no install root"      test_missing_podman_exits_nonzero
run_test "M5: corrupt tarball (fresh) exits non-zero, no bin/"    test_corrupt_tarball_fresh_install
run_test "M5: corrupt tarball (update) leaves prior install intact" test_corrupt_tarball_leaves_prior_install_intact
run_test "M6: pipe invocation produces same layout as file run"    test_pipe_invocation
run_test "M6: --help exits 0 with usage (both invocation forms)"  test_help_flag


print_summary "test_install_script"
