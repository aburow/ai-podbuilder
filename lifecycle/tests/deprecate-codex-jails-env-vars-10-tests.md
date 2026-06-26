---
title: 'Defect Fix Tests — test helpers use canonical AI_PODMAN_* vars'
type: test
status: done
lineage: deprecate-codex-jails-env-vars
parent: lifecycle/defects/deprecate-codex-jails-env-vars-7.md
created: "2026-06-26T00:00:00+10:00"
---

# Defect Fix Tests — test helpers use canonical AI_PODMAN_* vars

## What was fixed

Five tests in two files failed because the test fixtures passed `CODEX_JAILS_DIR` /
`CODEX_AGENTS_DIR` to configure their test-specific directories, but the migrated
implementation reads `AI_PODMAN_JAILS_DIR` / `AI_PODMAN_AGENTS_DIR`. Because
`setup_test_env` already exports `AI_PODMAN_JAILS_DIR="$_TMPDIR"`, `_prefer_canonical`
kept that value and ignored the inline `CODEX_*` override.

## Changes made

### `tests/61_list.sh` — 3 tests

Each of these tests supplies a custom root directory different from `$_TMPDIR`. The
inline env-var override now sets both canonical and legacy names so `_prefer_canonical`
sees the canonical var with the correct value:

| Test | Old override | New override |
|---|---|---|
| `test_ai_list_empty_state_exits_zero` | `CODEX_JAILS_DIR="$empty_dir"` | `AI_PODMAN_JAILS_DIR="$empty_dir" CODEX_JAILS_DIR="$empty_dir"` |
| `test_list_shows_legacy_only` | `CODEX_JAILS_DIR="$_empty"` | `AI_PODMAN_JAILS_DIR="$_empty" CODEX_JAILS_DIR="$_empty"` |
| `test_list_works_without_profiles_dir` | `CODEX_JAILS_DIR="$_noleg"` | `AI_PODMAN_JAILS_DIR="$_noleg" CODEX_JAILS_DIR="$_noleg"` |

### `tests/test_list_agents.sh` — 2 tests

`_list_helper` generated a subscript that exported `CODEX_JAILS_DIR` and
`CODEX_AGENTS_DIR`. Switched to `AI_PODMAN_JAILS_DIR` and `AI_PODMAN_AGENTS_DIR`,
which is what `list_registered_agents` (registry.sh:105) reads directly.

## Verification

```
bash tests/61_list.sh       → 11 passed  0 failed  0 skipped
bash tests/test_list_agents.sh → 4 passed  0 failed  0 skipped
```

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
