---
title: Deprecate CODEX_* Env Vars in Favour of AI_PODMAN_* — Backend Plan
type: plan-backend
status: done
lineage: deprecate-codex-jails-env-vars
parent: lifecycle/requirements/deprecate-codex-jails-env-vars-2.md
---

# Backend Plan — Deprecate CODEX_* in Favour of AI_PODMAN_*

All work is shell (no Go). Resolution is centralised in `lib/common.sh`; every
other `lib/*.sh` consumer reads the already-resolved canonical variables, so the
diff is concentrated in one file plus mechanical renames.

## Scope note — default directory

The Q5 answer mentions a future `${HOME}/ai-podman-jails` default. That is tied
to the out-of-scope installation system, and it conflicts with the Non-goals
("do not rename the on-disk default") and the byte-identical Acceptance
Criterion. **This plan keeps the `${HOME}/codex-jails` default unchanged.**
Changing it is deferred to the installation-system work.

---

## Milestone 1 — Central precedence + once-global warning helper

**Description.** Add one resolver in `lib/common.sh` that, per variable, prefers
the `AI_PODMAN_*` value, falls back to the legacy `CODEX_*` value (with a
deprecation warning), and otherwise leaves the canonical var unset for the
caller's default/derivation to apply. The warning fires **once globally** per
variable, is sent to stderr, and is suppressed when
`AI_PODMAN_NO_DEPRECATION_WARN` is set non-empty.

**Files to change.**
- `lib/common.sh` — add helper, e.g.:
  ```sh
  # _prefer_canonical NEW_VAR OLD_VAR
  # If NEW_VAR is already set+non-empty: keep it.
  # Else if OLD_VAR is set+non-empty: copy into NEW_VAR and warn once.
  # Else: leave NEW_VAR unset (caller applies default).
  _prefer_canonical() {
      local _new="$1" _old="$2"
      [[ -n "${!_new:-}" ]] && return 0
      [[ -z "${!_old:-}" ]] && return 0
      printf -v "$_new" '%s' "${!_old}"
      _deprecation_warn "$_old" "$_new"
  }
  ```
  and a once-global warn guard:
  ```sh
  _DEPRECATION_WARNED=""   # space-separated set of already-warned old names
  _deprecation_warn() {
      local _old="$1" _new="$2"
      [[ -n "${AI_PODMAN_NO_DEPRECATION_WARN:-}" ]] && return 0
      [[ " ${_DEPRECATION_WARNED} " == *" ${_old} "* ]] && return 0
      _DEPRECATION_WARNED="${_DEPRECATION_WARNED} ${_old}"
      _warn "${_old} is deprecated; use ${_new}"
  }
  ```
  Use direct `printf -v` assignment (no command substitution / subshell) so the
  warning reliably reaches stderr and the once-global flag persists in the
  sourcing shell.

**Acceptance criteria.**
- `_prefer_canonical AI_PODMAN_JAILS_DIR CODEX_JAILS_DIR` sets
  `AI_PODMAN_JAILS_DIR` from `CODEX_JAILS_DIR` only when the new var is unset.
- A second call for the same old var emits no second warning.
- `AI_PODMAN_NO_DEPRECATION_WARN=1` suppresses all deprecation output.
- Warning text matches `warning: CODEX_JAILS_DIR is deprecated; use AI_PODMAN_JAILS_DIR`
  semantics (old name → new name on stderr).

## Milestone 2 — Canonical base-dir resolution

**Description.** Rewrite `resolve_base_dir` and `resolve_jails_dir` to populate
the canonical `AI_PODMAN_JAILS_DIR`, applying precedence via Milestone 1 before
the existing self-hosting derivation / `${HOME}/codex-jails` default. Keep
`CODEX_JAILS_DIR` exported as an alias of the resolved value so any not-yet-migrated
reader (and the test seed in `tests/helpers/setup.bash`) still works.

**Files to change.**
- `lib/common.sh`:
  - `resolve_base_dir`: call `_prefer_canonical AI_PODMAN_JAILS_DIR CODEX_JAILS_DIR`
    first; if `AI_PODMAN_JAILS_DIR` still unset, derive repo-relative as today.
    Then `export AI_PODMAN_JAILS_DIR` and mirror `CODEX_JAILS_DIR="$AI_PODMAN_JAILS_DIR"`.
  - `resolve_jails_dir`: same precedence, default `${HOME}/codex-jails` when
    neither set. Export + mirror.
  - `profiles_dir`: read `AI_PODMAN_JAILS_DIR`.

**Acceptance criteria.**
- `AI_PODMAN_JAILS_DIR=A CODEX_JAILS_DIR=B` → resolved dir is `A`, no warning.
- only `CODEX_JAILS_DIR=B` → resolved dir is `B`, exactly one warning.
- only `AI_PODMAN_JAILS_DIR=A` → resolved dir is `A`, no warning.
- neither → existing default/derivation, no warning (byte-identical to today).

## Milestone 3 — Canonical BIN and AGENTS_DIR derivation

**Description.** In `project_paths`, apply the same precedence to `*_BIN` and
`*_AGENTS_DIR` before deriving from `AI_PODMAN_JAILS_DIR`. Each variable is
resolved independently (a user may migrate one but not another).

**Files to change.**
- `lib/common.sh` `project_paths`:
  - `_prefer_canonical AI_PODMAN_BIN CODEX_BIN`; default
    `${AI_PODMAN_JAILS_DIR}/bin` when unset.
  - `_prefer_canonical AI_PODMAN_AGENTS_DIR CODEX_AGENTS_DIR`; default
    `${AI_PODMAN_JAILS_DIR}/config/agents.d` when unset.
  - Export canonical names; mirror legacy `CODEX_BIN` / `CODEX_AGENTS_DIR` for
    compatibility.

**Acceptance criteria.**
- The three precedence behaviours from Milestone 2 hold independently for
  `*_BIN` and `*_AGENTS_DIR`.
- Setting only `CODEX_BIN` warns once for `CODEX_BIN` and not for the others.

## Milestone 4 — Migrate consumers to canonical names

**Description.** Replace `CODEX_*` interpolations in consumer libs with the
canonical `AI_PODMAN_*` values now exported by `common.sh`. No precedence logic
in consumers.

**Files to change.**
- `lib/registry.sh` — three sites:
  `${CODEX_AGENTS_DIR:-${CODEX_JAILS_DIR}/config/agents.d}` →
  `${AI_PODMAN_AGENTS_DIR:-${AI_PODMAN_JAILS_DIR}/config/agents.d}`.
- `lib/profile.sh`, `lib/scaffold.sh`, `lib/launch.sh`, `lib/slug.sh`,
  `lib/bootstrap_image.sh`, `lib/durable.sh` — `CODEX_JAILS_DIR` →
  `AI_PODMAN_JAILS_DIR` interpolations.

**Acceptance criteria.**
- `grep -rn 'CODEX_' lib/` returns only the compatibility mirrors in
  `common.sh` (and intentional alias comments) — no live consumer reads `CODEX_*`.
- Resolved paths are unchanged for every precedence case.

## Milestone 5 — Help/usage text

**Description.** Document `AI_PODMAN_*` as canonical and `CODEX_*` as deprecated
aliases.

**Files to change.**
- `lib/usage.sh` Environment section:
  - `AI_PODMAN_JAILS_DIR     Base directory for all projects (default: $HOME/codex-jails).`
  - `AI_PODMAN_BIN`, `AI_PODMAN_AGENTS_DIR` lines.
  - `CODEX_*  (deprecated alias of AI_PODMAN_*; still honoured)`.
  - mention `AI_PODMAN_NO_DEPRECATION_WARN` to silence the warning.
  - Update the `<name>` line that references `CODEX_JAILS_DIR/projects/`.

**Acceptance criteria.**
- `ai-new --help` lists the three `AI_PODMAN_*` vars and notes `CODEX_*` as
  deprecated and `AI_PODMAN_NO_DEPRECATION_WARN` as the suppressor.

## Milestone 6 — Build / vet

**Description.** Run shellcheck / project linter and the existing suite.

**Acceptance criteria.**
- `build`/`vet` (shellcheck or project linter) passes with no new warnings.
- The full existing test suite passes unchanged (compat path intact).
