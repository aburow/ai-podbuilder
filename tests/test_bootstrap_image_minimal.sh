#!/usr/bin/env bash
# T5 (slow) — Bootstrap image minimality: no project stack, only runtime tooling (AC1, AC15).
# Tagged slow: requires PODMAN_LIVE=1 and rootless Podman.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/setup.bash
source "${SELF_DIR}/helpers/setup.bash"

_BOOTSTRAP_TAG="localhost/ai-new/bootstrap:latest"

# ── Tests ─────────────────────────────────────────────────────────────────────

test_bootstrap_image_exists_or_skip() {
    if skip_unless_live; then return 0; fi
    local _fail=0
    if ! podman image exists "$_BOOTSTRAP_TAG" 2>/dev/null; then
        _SKIP_REASON="Bootstrap image ${_BOOTSTRAP_TAG} not present — run ai-new first"
        return 0
    fi
    local _id
    _id="$(podman image inspect --format '{{.Id}}' "$_BOOTSTRAP_TAG" 2>/dev/null || true)"
    [[ -n "$_id" ]] || {
        printf '    Could not inspect bootstrap image\n' >&2
        _fail=1
    }
    return $_fail
}

test_bootstrap_image_has_label() {
    if skip_unless_live; then return 0; fi
    if ! podman image exists "$_BOOTSTRAP_TAG" 2>/dev/null; then
        _SKIP_REASON="Bootstrap image not present"
        return 0
    fi
    local _label
    _label="$(podman image inspect --format '{{index .Labels "ai-new.role"}}' \
        "$_BOOTSTRAP_TAG" 2>/dev/null || true)"
    assert_eq "bootstrap" "$_label" "ai-new.role label should be 'bootstrap'" || return 1
}

test_bootstrap_image_no_project_stack() {
    if skip_unless_live; then return 0; fi
    if ! podman image exists "$_BOOTSTRAP_TAG" 2>/dev/null; then
        _SKIP_REASON="Bootstrap image not present"
        return 0
    fi
    local _fail=0
    # Check that typical project build tools are absent.
    local _pkg
    for _pkg in make cmake gcc g++ rustc cargo mvn gradle; do
        if podman run --rm "$_BOOTSTRAP_TAG" command -v "$_pkg" >/dev/null 2>&1; then
            printf '    FAIL: project stack tool present in bootstrap image: %s\n' "$_pkg" >&2
            _fail=1
        fi
    done
    return $_fail
}

test_bootstrap_image_has_runtime_tooling() {
    if skip_unless_live; then return 0; fi
    if ! podman image exists "$_BOOTSTRAP_TAG" 2>/dev/null; then
        _SKIP_REASON="Bootstrap image not present"
        return 0
    fi
    local _fail=0
    # Runtime-install tools should be present.
    local _tool
    for _tool in bash curl git node npm python3 pipx; do
        if ! podman run --rm "$_BOOTSTRAP_TAG" command -v "$_tool" >/dev/null 2>&1; then
            printf '    FAIL: expected runtime tool missing from bootstrap image: %s\n' "$_tool" >&2
            _fail=1
        fi
    done
    return $_fail
}

# ── Run ───────────────────────────────────────────────────────────────────────
run_test "[slow] bootstrap image exists and is inspectable"      test_bootstrap_image_exists_or_skip
run_test "[slow] bootstrap image has ai-new.role=bootstrap label" test_bootstrap_image_has_label
run_test "[slow] bootstrap image has no project build stack"      test_bootstrap_image_no_project_stack
run_test "[slow] bootstrap image has runtime tooling (npm, pipx, etc.)" test_bootstrap_image_has_runtime_tooling

print_summary "test_bootstrap_image_minimal"
