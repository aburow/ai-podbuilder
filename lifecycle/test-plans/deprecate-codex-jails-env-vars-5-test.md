---
title: Deprecate CODEX_* Env Vars in Favour of AI_PODMAN_* — Test Plan
type: plan-test
status: approved
lineage: deprecate-codex-jails-env-vars
parent: lifecycle/requirements/deprecate-codex-jails-env-vars-2.md
---

# Test Plan — Deprecate CODEX_* in Favour of AI_PODMAN_*

Integration tests live in `tests/` (bash). The core is the precedence matrix
(canonical wins, legacy fallback warns, default applies) verified per variable,
plus a compat guard that legacy-only setups stay byte-identical.

## Milestone 1 — New precedence-matrix test

**Description.** Add one test driving the resolver in `lib/common.sh` across the
matrix for `JAILS_DIR`, `BIN`, and `AGENTS_DIR`. Source `lib/common.sh`, call
`resolve_jails_dir` / `resolve_base_dir` + `project_paths foo` under controlled
env, assert resolved values and warning behaviour (capture stderr).

**Files to change.**
- `tests/test_env_var_precedence.sh` (new).

**Acceptance criteria (per variable: JAILS_DIR, BIN, AGENTS_DIR).**
- both `AI_PODMAN_*=A` and `CODEX_*=B` set → resolved `A`, **no** warning on stderr.
- only `CODEX_*=B` set → resolved `B`, **exactly one** warning naming
  `CODEX_<X>` → `AI_PODMAN_<X>`.
- only `AI_PODMAN_*=A` set → resolved `A`, no warning.
- neither set → existing default/derivation (JAILS_DIR → `${HOME}/codex-jails`
  or repo-relative; BIN → `<jails>/bin`; AGENTS_DIR → `<jails>/config/agents.d`),
  no warning.
- variables are independent: setting only `CODEX_BIN` warns for `CODEX_BIN` only.

## Milestone 2 — Once-global + suppression test

**Description.** Verify warn-once-globally and the suppressor.

**Files to change.**
- `tests/test_env_var_precedence.sh` (same file).

**Acceptance criteria.**
- Resolving a legacy var twice in one process emits the warning only once.
- `AI_PODMAN_NO_DEPRECATION_WARN=1` suppresses all deprecation warnings while
  resolved paths are unchanged.

## Milestone 3 — Byte-identical compat assertion

**Description.** Prove a legacy-only run yields the same resolved paths as the
pre-change behaviour (aside from the warning).

**Files to change.**
- `tests/test_env_var_precedence.sh` (same file).

**Acceptance criteria.**
- With only `CODEX_JAILS_DIR=/tmp/x` set, `AI_PODMAN_JAILS_DIR`, `*_BIN`,
  `*_AGENTS_DIR`, and `PROJECT_*` resolve to exactly the paths produced before
  the change (`/tmp/x`, `/tmp/x/bin`, `/tmp/x/config/agents.d`, …).

## Milestone 4 — Migrate suite isolation + keep compat coverage

**Description.** Move the test harness to set `AI_PODMAN_JAILS_DIR` for
isolation, keeping at least one legacy-only case to exercise the compat path.

**Files to change.**
- `tests/helpers/setup.bash` — `export AI_PODMAN_JAILS_DIR="$_TMPDIR"` and the
  profile-seed `sed` substitution (`${CODEX_JAILS_DIR}` → also accept
  `${AI_PODMAN_JAILS_DIR}` / resolved value).
- Other `tests/*.sh` that hard-set `CODEX_JAILS_DIR` for isolation: switch to
  `AI_PODMAN_JAILS_DIR`, leaving the dedicated compat test (Milestone 3) using
  the legacy name.

**Acceptance criteria.**
- The full suite passes with isolation via `AI_PODMAN_JAILS_DIR`.
- The legacy-only compat test still passes (and warns once), proving `CODEX_*`
  remains honoured.
- `build`/`vet` (shellcheck or project linter) passes.
