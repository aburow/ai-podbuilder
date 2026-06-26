---
title: Deprecate CODEX_* Env Vars in Favour of AI_PODMAN_*
type: requirement
status: done
lineage: deprecate-codex-jails-env-vars
parent: lifecycle/defects/deprecate-codex-jails-env-vars.md
assignees:
    - role: product-owner
      who: agent
---

# Deprecate CODEX_* Env Vars in Favour of AI_PODMAN_*

## Problem

The plugin reads its base directory and derived paths from `CODEX_*`
environment variables. These names reflect an older "codex-jails" identity that
no longer matches the project. They must be renamed to `AI_PODMAN_*` without
breaking existing users who already export the `CODEX_*` names.

The codebase reads three distinct variables, all in shell (no Go):

- `CODEX_JAILS_DIR` — base directory for projects, config, and binaries.
  Read in `lib/common.sh` (set/export/default to `${HOME}/codex-jails`) and
  interpolated across `lib/registry.sh`, `lib/profile.sh`, `lib/scaffold.sh`,
  `lib/launch.sh`, `lib/slug.sh`, `lib/bootstrap_image.sh`, `lib/durable.sh`,
  `lib/usage.sh`.
- `CODEX_BIN` — derived as `${CODEX_JAILS_DIR}/bin` in `lib/common.sh`.
- `CODEX_AGENTS_DIR` — derived as `${CODEX_JAILS_DIR}/config/agents.d` in
  `lib/common.sh`; `lib/registry.sh` already uses the
  `${CODEX_AGENTS_DIR:-${CODEX_JAILS_DIR}/config/agents.d}` fallback shape.

Today there is no precedence or fallback against `AI_PODMAN_*`; nothing reads
those names yet. Resolution happens in a small number of places in
`lib/common.sh`, so centralising the migration there is the root-cause fix —
the rest of the code consumes the already-resolved values.

## Goals / Non-goals

**Goals**

- `AI_PODMAN_*` becomes the canonical name for every `CODEX_*` variable in use.
- When both an `AI_PODMAN_*` var and its `CODEX_*` counterpart are set, the
  `AI_PODMAN_*` value wins.
- When only the legacy `CODEX_*` var is set, it is honoured as a fallback so
  existing setups keep working.
- A deprecation warning is emitted once when a `CODEX_*` fallback is exercised.
- Internal defaults (e.g. `${HOME}/codex-jails`) and derivation continue to work
  when neither name is set.

**Non-goals**

- Removing `CODEX_*` support entirely (that is a later breaking change; this is
  the transition period only).
- Renaming the default directory `${HOME}/codex-jails` on disk.
- Changing any path semantics, layout, or behaviour beyond variable naming.

## Detailed Requirements

1. **Canonical variables.** Introduce and prefer these names, mapping 1:1 to the
   existing ones:
   - `AI_PODMAN_JAILS_DIR` ← `CODEX_JAILS_DIR`
   - `AI_PODMAN_BIN` ← `CODEX_BIN`
   - `AI_PODMAN_AGENTS_DIR` ← `CODEX_AGENTS_DIR`

2. **Precedence per variable:** `AI_PODMAN_*` if set and non-empty → else
   `CODEX_*` if set and non-empty → else internal default/derivation. Apply this
   independently per variable (a user may migrate one but not another).

3. **Centralised resolution.** Resolve each variable once in `lib/common.sh`
   (the existing resolution point) into the canonical variable, and have all
   other `lib/*.sh` consumers read the resolved canonical value. Do not scatter
   precedence checks across consumers.

4. **Deprecation warning.** When a `CODEX_*` value is used because the
   `AI_PODMAN_*` equivalent is unset, print one warning to stderr naming the old
   and new variable, e.g.
   `warning: CODEX_JAILS_DIR is deprecated; use AI_PODMAN_JAILS_DIR`.
   Warn at most once per variable per process; do not warn when the canonical
   variable is used or when defaults apply.

5. **Backwards compatibility.** All current invocations that set only `CODEX_*`
   must continue to function with identical paths and behaviour (only the extra
   warning differs).

6. **Help/usage text.** `lib/usage.sh` and any help output must document the
   `AI_PODMAN_*` names as canonical and note `CODEX_*` as deprecated aliases.

7. **Documentation.** Update README and the relevant `docs/**` to use
   `AI_PODMAN_*`, mentioning `CODEX_*` as still-supported deprecated aliases.

8. **Tests.** Update the test suite to use `AI_PODMAN_JAILS_DIR` for isolation,
   and add coverage for the precedence matrix (see Acceptance Criteria). Existing
   tests that still set `CODEX_JAILS_DIR` must keep passing (compat path).

## Acceptance Criteria

- With `AI_PODMAN_JAILS_DIR=A` and `CODEX_JAILS_DIR=B` both set, the plugin uses
  `A`; no deprecation warning is emitted.
- With only `CODEX_JAILS_DIR=B` set, the plugin uses `B` and emits exactly one
  deprecation warning naming `CODEX_JAILS_DIR` → `AI_PODMAN_JAILS_DIR`.
- With only `AI_PODMAN_JAILS_DIR=A` set, the plugin uses `A`; no warning.
- With neither set, the plugin falls back to the existing default
  (`${HOME}/codex-jails` or the repo-relative derivation) with no warning.
- The same three behaviours hold independently for `*_BIN` and `*_AGENTS_DIR`.
- A run that sets only `CODEX_*` variables produces byte-identical resolved
  paths to the pre-change behaviour (aside from the warning).
- `build`/`vet` (shellcheck or project linter) and the full test suite pass.

## Answers

Q1. **Naming mismatch.** The parent defect refers to `CODEX_JAILS` / `AI_PODMAN_JAILS`, but the code only uses `CODEX_JAILS_DIR` (plus `CODEX_BIN`, `CODEX_AGENTS_DIR`). Confirm the canonical name is `AI_PODMAN_JAILS_DIR`, or whether a separate `AI_PODMAN_JAILS` variable is also intended.

Answer: correct - a quick check of a working environment shows that we are only using CODEX_JAILS_DIR... So we are only interested in changing this to AI_PODMAN_JAILS_DIR

Q2. **Warning channel & verbosity.** Is stderr acceptable, and should the warning be suppressible (e.g. `AI_PODMAN_NO_DEPRECATION_WARN=1`) to avoid noise in CI and scripted use?

Answer: Yes, have the option there in case this becomes an issue for a user that can't readilly migrate.

Q3. **Warning frequency.** Once-per-variable-per-process assumed — acceptable, or is once-per-invocation/once-globally preferred?

Answer: once globally

Q4. **Removal timeline.** Is there a target release at which `CODEX_*` support is dropped entirely, so the warning can name it?

Answer: No because I haven't started numbering releases yet

Q5. **Default directory rename.** Should the on-disk default eventually move from `${HOME}/codex-jails` to e.g. `${HOME}/ai-podman-jails`, or is that explicitly out of scope?

Answer: It should be set to ai-podman-jails for a new install. The user can define a different directory. We should have yes/no questions to allow the user to set in the setup interactively, using defaults, using existing environment... because the setup will have to run over the top of existing installs in order to do updates - this work is in preparation of the next stage of the project - creating an installion system. That part is out of scope but the environment vars are a critical roadblocker at the moment.
