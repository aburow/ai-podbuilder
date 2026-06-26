---
title: Project-Local Profile Canonicalization — Backend Plan
type: plan-backend
status: approved
lineage: project-local-profiles
parent: lifecycle/requirements/project-local-profiles-2.md
---

# Project-Local Profile Canonicalization — Backend Plan

Implements R1–R3 control flow: make `projects/<name>/profile.env` canonical,
stop mirroring into `profiles/`, and remove the central-registry assumption.
Q1 is resolved as **raw name** for the project directory; the legacy registry
filename stays keyed by `sanitize_slug(name)`. All three phases land together
(Q2), so this is a single coherent change set, not a staged rollout.

## Milestone 1 — Dual-read resolution in `load_profile` (R1.1–R1.4)

Make the project tree the first lookup and remove the copy-back.

Files to change:
- `lib/profile.sh` — rewrite `load_profile()` (currently lines 69–98):
  1. Resolve `${CODEX_JAILS_DIR}/projects/<name>/profile.env` first (raw name).
  2. Fall back to `$(profiles_dir)/$(sanitize_slug <name>).env`. The legacy
     filename MUST be derived via `sanitize_slug`, not the raw arg — the current
     code uses the raw arg as the registry key, which is the latent name↔slug
     bug Q1 names.
  3. If neither exists, `_die` with a message naming **both** searched paths.
  4. Delete the `mkdir -p`/`cp`/"Recovered missing registered profile" block
     (lines 77–79) — no write-back under any path (R1.2, AC6).
  - `validate_loaded_profile` and the `BASHRC_CONTAINER` derivation already run
    after sourcing regardless of source path; leave them downstream of the
    resolution so behavior is path-independent (R1.4).
- `lib/profile.sh` requires `slug.sh` for `sanitize_slug`; confirm callers that
  source `profile.sh` also source `slug.sh` (ai-build, ai-launch, ai-terminal,
  durable preflight helper at `lib/durable.sh:388-389`). Add the `source` where
  missing.

Acceptance criteria:
- With only `projects/<name>/profile.env` present, `load_profile <name>`
  succeeds and exports all required fields (AC1).
- A hand-authored `profiles/<slug>.env` with no project tree still loads via the
  fallback (AC5).
- After any successful or failed `load_profile`, no file is created under
  `profiles/` (AC6).
- A truly-missing profile dies with both candidate paths in the message.

## Milestone 2 — Reconcile the slug-keyed caller (Q1, R1.3)

`lib/durable.sh:393` passes `sanitize_slug(basename "$_proj")` to `load_profile`.
With project-local resolution keyed by raw name, a project whose name ≠ slug
would miss its own profile.

Files to change:
- `lib/durable.sh` — in the `.launch-preflight.sh` heredoc, change the call to
  `load_profile '$(basename "$_proj")'` (raw project dir name). Projects are
  created under `projects/<raw-name>` (`project_paths`, `common.sh:47`), so
  `basename` is the correct key.

Acceptance criteria:
- Launchability preflight loads the profile for a project whose raw name differs
  from its slug (e.g. name `My Proj`, slug `my-proj`) using only the project
  tree.

## Milestone 3 — Stop mirroring generated profiles (R2.4, AC4/AC7)

Remove every `install_generated_profile` invocation. The generated
`projects/<name>/profile.env` becomes the only artifact written.

Files to change:
- `bin/ai-new` — remove the two calls at lines 151 and 195.
- `lib/quality_gate.sh` — remove the call at line 187.
- `lib/reconcile.sh` — remove the call at line 133.

Acceptance criteria:
- After `ai-new` completes, no `profiles/<slug>.env` exists for that project (AC4).
- Quality gate and reconcile complete without creating/refreshing any
  `profiles/*.env` (AC7).

## Milestone 4 — `ai-list` enumerates the project tree (R2.1–R2.3, AC2/AC3)

Rewrite `bin/ai-list` discovery so `projects/*/profile.env` is primary,
legacy-only `profiles/*.env` are merged in, and `profiles/` being absent is fine.

Files to change:
- `bin/ai-list`:
  - Remove the `[[ -d "$PDIR" ]] || _die` guard (lines 24–25) (R2.3).
  - Remove the mirror loop calling `install_generated_profile` (lines 28–33) (R2.1).
  - Build the row list from two sources, de-duplicated by **slug** (Q3):
    - For each `projects/*/profile.env`: slug = `sanitize_slug(basename dir)`.
    - For each `profiles/*.env` (nullglob; skip if dir absent): slug = basename
      without `.env`. Include only if that slug was not already seen from the
      project tree.
  - Source each chosen file in a subshell (as today, lines 47–59) to emit the
    `PROFILE_NAME\tIMAGE_NAME\tWORKSPACE\tstate` row.
  - Empty result set prints the existing "No profiles found" path (no `_die`).
- `bin/ai-list` already sources `slug.sh`; it can drop the `scaffold.sh` source
  if `install_generated_profile` is its only use (verify; see Milestone 5).

Acceptance criteria:
- `ai-list` exits 0 and lists the project when `profiles/` does not exist (AC2).
- `ai-list` shows both project-local and legacy-only profiles with no duplicate
  row when a slug exists in both (AC3).

## Milestone 5 — Remove dead `install_generated_profile` (R3.3)

After Milestones 3–4 there are no callers.

Files to change:
- `lib/scaffold.sh` — delete `install_generated_profile()` (lines 111–130).
  Note the removal in the commit message.
- Grep the tree for any remaining reference; remove now-unused sources/imports.

Acceptance criteria:
- `grep -rn install_generated_profile bin/ lib/` returns nothing.
- The full suite still sources `scaffold.sh` cleanly (no missing-function errors).

## Milestone 6 — Legacy deprecation notice (R3.1, R3.2)

Files to change:
- `lib/profile.sh` — when resolution falls through to the legacy
  `profiles/<slug>.env` branch, emit one `_info` line pointing at the
  project-local layout (exact wording owned by the frontend plan — coordinate on
  the string). Project-local loads stay silent.
- Code comments referencing `profiles/` as required state (e.g. `lib/profile.sh`
  header, `scaffold.sh`) reframed as optional compatibility area (R3.1). Prose
  in README/docs is the frontend plan's scope (R4.1).

Acceptance criteria:
- Loading a legacy-only profile prints exactly one deprecation `_info`; loading
  a project-local profile prints none.

## Out of scope

- No change to profile file format or `validate_loaded_profile` fields (per
  requirement Non-goals).
- No bulk migration or deletion of existing `profiles/*.env` files.
- No redesign of the name↔slug scheme beyond pinning the resolution key.
