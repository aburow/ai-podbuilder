---
title: 'Test helpers pass CODEX_* env vars but list functions read AI_PODMAN_*'
type: defect
status: done
lineage: deprecate-codex-jails-env-vars
parent: lifecycle/tests/deprecate-codex-jails-env-vars-6-tests.md
created: "2026-06-26T00:00:00+10:00"
priority: normal
labels:
    - defect
assignees:
    - role: test-developer
      who: agent
---

# Test helpers pass CODEX_* env vars but list functions read AI_PODMAN_*

## Summary

Five tests across two files fail because they pass `CODEX_JAILS_DIR` / `CODEX_AGENTS_DIR`
to configure test fixtures, but the migrated implementation now reads `AI_PODMAN_JAILS_DIR`
/ `AI_PODMAN_AGENTS_DIR`. Because `setup_test_env` pre-exports `AI_PODMAN_JAILS_DIR` to
`$_TMPDIR` and `_prefer_canonical` keeps the `AI_PODMAN_*` value over any inline
`CODEX_*` override, the tests observe the wrong directory.

Failing tests:
- `tests/61_list.sh`: `test_ai_list_empty_state_exits_zero`, `test_list_shows_legacy_only`, `test_list_works_without_profiles_dir`
- `tests/test_list_agents.sh`: `test_real_agents_dir_has_default_set`, `test_non_env_files_not_listed`

## Reproduction Steps

1. Run `bash tests/run_tests.sh`.
2. Observe failures in `61_list.sh` (3 failures) and `test_list_agents.sh` (2 failures).

## Expected Behaviour

- Tests that override the jails/agents directory should control which directory the
  implementation reads.
- All five tests should pass.

## Actual Behaviour

**61_list.sh — 3 failures:**

```
ASSERT_CONTAINS fail: empty-state message should be printed: No\ profiles\ found not found in output
FAIL  ai-list: no profiles anywhere → exit 0 with message

ASSERT_CONTAINS fail: legacy-only profile should appear: legacyonly not found in output
FAIL  ai-list shows legacy-only profile (AC3)

ASSERT_CONTAINS fail: project should be listed without profiles/ dir: onlyproj not found in output
FAIL  ai-list works without profiles/ dir (AC2)
```

**test_list_agents.sh — 2 failures:**

```
ASSERT_CONTAINS fail: codex not found in output
ASSERT_CONTAINS fail: codex not found in output
ASSERT_CONTAINS fail: gemini not found in output
FAIL  repo agents.d exposes codex, codex, gemini

ASSERT_CONTAINS fail: myagent.env should be listed: myagent not found in output
FAIL  non-.env files are not listed
```

## Root Cause

**61_list.sh:** `setup_test_env` (in `tests/helpers/setup.bash`) exports
`AI_PODMAN_JAILS_DIR="$_TMPDIR"`. Tests that need a different root pass only
`CODEX_JAILS_DIR=<other-dir>` as an inline override. `_prefer_canonical` in
`lib/common.sh` keeps the already-set `AI_PODMAN_JAILS_DIR`, so `ai-list` reads
from `$_TMPDIR` (seeded with profiles) rather than the test-specific directory.

**test_list_agents.sh:** `_list_helper` exports `CODEX_AGENTS_DIR=$agents_dir` and
`CODEX_JAILS_DIR=$_TMPDIR`, but `list_registered_agents` (in `lib/registry.sh`, line
105) reads `AI_PODMAN_AGENTS_DIR:-${AI_PODMAN_JAILS_DIR}/config/agents.d`. Neither
canonical variable is set by the helper, so the function falls back to
`${AI_PODMAN_JAILS_DIR}/config/agents.d` which is the TMPDIR default — not the
test-supplied agents directory.

**Fix:** Update the affected tests / helpers to export `AI_PODMAN_JAILS_DIR` and
`AI_PODMAN_AGENTS_DIR` instead of (or in addition to) their `CODEX_*` counterparts.
