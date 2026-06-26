---
title: 'test_no_dead_install_code.sh asserts deprecated CODEX_JAILS_DIR literal in bootstrap_image.sh'
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

# test_no_dead_install_code.sh asserts deprecated CODEX_JAILS_DIR literal in bootstrap_image.sh

## Summary

`test_build_context_excludes_project_secrets` in `tests/test_no_dead_install_code.sh`
checks that `lib/bootstrap_image.sh` contains the literal string
`local _build_context="${CODEX_JAILS_DIR}/config"`. The migration replaced that
variable with `AI_PODMAN_JAILS_DIR` (line 143 of `lib/bootstrap_image.sh`), but
the test assertion was not updated, causing it to fail.

## Reproduction Steps

1. Run `bash tests/test_no_dead_install_code.sh`.
2. Observe the failure `image build context excludes project secrets`.

## Expected Behaviour

The test should verify that `bootstrap_image.sh` constructs its build context from
the canonical `AI_PODMAN_JAILS_DIR` variable and does not fall back to a broader
path that might expose project secrets. The test should pass.

## Actual Behaviour

```
ASSERT_CONTAINS fail: local\ _build_context=\"\$\{CODEX_JAILS_DIR\}/config\" not found in output
FAIL  image build context excludes project secrets
```

`lib/bootstrap_image.sh` line 143 now reads:
```bash
local _build_context="${AI_PODMAN_JAILS_DIR}/config"
```

The test still searches for the old `CODEX_JAILS_DIR` variant, which no longer
exists in the file.

## Root Cause

`test_build_context_excludes_project_secrets` was not updated alongside the
`CODEX_JAILS_DIR` → `AI_PODMAN_JAILS_DIR` migration. The assertion literal must
be changed from `${CODEX_JAILS_DIR}` to `${AI_PODMAN_JAILS_DIR}`.

## Fix

In `tests/test_no_dead_install_code.sh`, update `test_build_context_excludes_project_secrets`:

```bash
assert_contains 'local _build_context="${AI_PODMAN_JAILS_DIR}/config"' "$src" || return 1
```

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
