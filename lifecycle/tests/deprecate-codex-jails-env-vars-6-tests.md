---
title: Deprecate CODEX_* Env Vars — Test Artifact
type: test
status: done
lineage: deprecate-codex-jails-env-vars
parent: lifecycle/test-plans/deprecate-codex-jails-env-vars-5-test.md
created: "2026-06-26T00:00:00+10:00"
---

# Deprecate CODEX_* Env Vars — Test Artifact

Documents the integration tests built for the env-var deprecation feature,
covering all four milestones from
`lifecycle/test-plans/deprecate-codex-jails-env-vars-5-test.md`.

## What was built

### Harness changes (M4)

| File | Change |
|------|--------|
| `tests/helpers/setup.bash` | Added `export AI_PODMAN_JAILS_DIR="$_TMPDIR"` alongside the existing `CODEX_JAILS_DIR` export so all test subprocesses inherit the canonical var and resolve without warnings. Extended the profile-seed `sed` to also substitute `${AI_PODMAN_JAILS_DIR}` in `.env.example` files. |

### Test files

| File | Milestones | Tests |
|------|-----------|-------|
| `tests/test_env_var_precedence.sh` | M1 – M3 | 16 |

### Test coverage by milestone

**M1 — Precedence matrix (13 tests):** For each of the three resolver
variables (`JAILS_DIR`, `BIN`, `AGENTS_DIR`) the four matrix cases are
exercised — both-set (canonical wins, no warning), legacy-only (value
propagates, one warning), canonical-only (no warning), neither (default
derivation, no warning). A 13th test proves independence: setting only
`CODEX_BIN` emits a warning for `CODEX_BIN` and nothing else.

**M2 — Warn-once + suppressor (2 tests):** The warn-once test calls
`resolve_jails_dir` twice in the same subprocess (resetting
`AI_PODMAN_JAILS_DIR` between calls to re-trigger the legacy path) and
asserts exactly one `deprecated` line on stderr, verifying
`_DEPRECATION_WARNED` prevents duplicate warnings. The suppressor test sets
`AI_PODMAN_NO_DEPRECATION_WARN=1` with all three legacy vars populated and
asserts zero warnings while resolved values are unchanged.

**M3 — Byte-identical compat (1 test):** With only `CODEX_JAILS_DIR=/tmp/x`
set, asserts all six derived paths match the expected pre-change values
(`/tmp/x`, `/tmp/x/bin`, `/tmp/x/config/agents.d`, and the three
`PROJECT_*` vars for project `testproj`), and that exactly one deprecation
warning fires.

**M4 — Suite isolation (harness only):** Covered by the `setup.bash` change
above; no dedicated test cases because the existing suite validates it
implicitly. The M3 compat test intentionally uses the legacy name inside its
own isolated subshell to prove `CODEX_*` remains honoured.

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
