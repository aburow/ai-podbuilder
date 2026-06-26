---
title: Project-Local Profile Canonicalization
type: requirement
status: blocked
lineage: project-local-profiles
parent: lifecycle/ideas/project-local-profiles.md
assignees:
    - role: product-owner
      who: agent
---

# Project-Local Profile Canonicalization

## Problem

Today the project tree is *not* the source of truth for durable sandbox
configuration even though it looks like it should be. `ai-new` generates
`projects/<name>/profile.env`, but every entry point then mirrors that file
into the central `profiles/<slug>.env` registry before anything can use it:

- `install_generated_profile()` (lib/scaffold.sh:115) copies
  `projects/<name>/profile.env` → `$(profiles_dir)/<slug>.env`. It is called
  from `ai-new` (bin/ai-new:151,195), `ai-list` (bin/ai-list:31),
  the quality gate (lib/quality_gate.sh:187), and reconcile
  (lib/reconcile.sh:133).
- `load_profile()` (lib/profile.sh:69) resolves `profiles/<name>.env` **first**
  and only falls back to the project tree if the central copy is missing — and
  when it does fall back, it *copies the project file back into `profiles/`*
  ("Recovered missing registered profile…").
- `ai-list` (bin/ai-list:24) hard-requires the `profiles/` directory to exist
  (`_die` if absent) and lists from `profiles/*.env`, not from the project tree.

The result is drift risk (two copies that can disagree), a split mental model
(which file is authoritative?), and a project layout that is less
self-contained than it appears. The runtime already supports reading a
project-local profile; the remaining work is **discovery semantics**,
**compatibility handling**, and **removal of the central-registry assumption**.

A second, pre-existing wrinkle this change must respect: the central registry
is keyed by **slug** (`sanitize_slug`), while the project tree is keyed by the
raw project **name** (`projects/<name>/profile.env`). `load_profile()`'s
current fallback uses the raw arg as both the registry key and the project
directory name, so name↔slug divergence is already a latent bug. Canonicalizing
on the project tree must define the resolution key explicitly.

## Goals / Non-goals

**Goals**

- Make `projects/<name>/profile.env` the canonical, authoritative source for
  durable profile configuration.
- `load_profile()` resolves the project-local profile **first**, falling back
  to `profiles/<slug>.env` only for hand-authored legacy profiles.
- `ai-list` enumerates `projects/*/profile.env` directly and functions when
  `profiles/` does not exist.
- `ai-new` (and the quality gate / reconcile paths) stop mirroring generated
  profiles into `profiles/`.
- Legacy `profiles/<slug>.env` profiles with no corresponding project tree keep
  working throughout the transition via a phased compatibility strategy.

**Non-goals**

- No change to profile **file format** or to the fields validated by
  `validate_loaded_profile()`.
- No migration tool that bulk-rewrites or deletes existing `profiles/*.env`
  files (deletion is a later, separately-approved phase).
- No change to container build/launch/runtime behaviour beyond where the
  profile is read from.
- No redesign of the name↔slug scheme — this requirement only pins down which
  key project-local resolution uses (see Open Questions).

## Detailed Requirements

The idea specifies a three-phase compatibility strategy. Each phase is a
self-contained, shippable increment.

### Phase 1 — Dual-read (project-local preferred)

- **R1.1** `load_profile(name)` MUST resolve in this order:
  1. `$CODEX_JAILS_DIR/projects/<name>/profile.env` (project-local, canonical)
  2. `$(profiles_dir)/<slug>.env` (legacy fallback)
  and `_die` only if neither exists, with a message naming both paths searched.
- **R1.2** When `load_profile` reads the project-local file it MUST NOT copy it
  into `profiles/`. The current "Recovered missing registered profile" copy-back
  (lib/profile.sh:77-79) MUST be removed.
- **R1.3** The resolution key used for the project directory and for the legacy
  registry filename MUST be explicit and consistent (see Open Questions Q1).
  Until resolved, treat the project directory as keyed by name and the legacy
  file as keyed by `sanitize_slug(name)`.
- **R1.4** `validate_loaded_profile()` and `BASHRC_CONTAINER` derivation MUST
  behave identically regardless of which path the profile was loaded from.

### Phase 2 — Dual-discovery (list both, registry optional)

- **R2.1** `ai-list` MUST enumerate `projects/*/profile.env` directly as the
  primary source and MUST NOT call `install_generated_profile` (remove
  bin/ai-list:28-33's mirror loop).
- **R2.2** `ai-list` MUST also include legacy `profiles/*.env` entries that have
  **no** corresponding `projects/<name>/profile.env`, de-duplicated by profile
  identity, so legacy-only profiles remain visible.
- **R2.3** `ai-list` MUST NOT `_die` when `profiles/` is absent (remove the
  guard at bin/ai-list:24-25). An empty result set prints the existing
  "No profiles found" message.
- **R2.4** `install_generated_profile()` MUST no longer be invoked from `ai-new`
  (bin/ai-new:151,195), the quality gate (lib/quality_gate.sh:187), or reconcile
  (lib/reconcile.sh:133). The generated `projects/<name>/profile.env` is the only
  artifact written.

### Phase 3 — Deprecation (compatibility-only registry)

- **R3.1** `profiles/` is reframed in docs and code comments as an **optional
  compatibility area** for hand-authored legacy profiles, not required runtime
  state. No code path may assume it exists or write to it as part of normal
  operation.
- **R3.2** A legacy profile loaded from `profiles/<slug>.env` SHOULD emit a
  one-line deprecation `_info` pointing the user at the project-local layout.
- **R3.3** `install_generated_profile()` becomes dead code; it MUST be removed
  along with any now-unused helpers, with the deletion noted in the relevant
  commit.

### Cross-cutting

- **R4.1** Documentation (README.md, docs/**) MUST describe
  `projects/<name>/profile.env` as canonical and `profiles/` as legacy/optional.
- **R4.2** Existing tests that assert mirroring behaviour
  (e.g. tests/10_profile.sh, tests/61_list.sh, tests/test_scaffold_layout.sh,
  tests/test_generated_scaffold.sh) MUST be updated to the new semantics rather
  than left asserting the removed copy-back.

## Acceptance Criteria

- **AC1** With only `projects/<name>/profile.env` present (no
  `profiles/<slug>.env`), `ai-build`, `ai-launch`, and `ai-terminal` all load
  the profile and operate normally.
- **AC2** `ai-list` runs successfully and lists the project when `profiles/`
  does not exist.
- **AC3** `ai-list` shows both project-local profiles and legacy-only
  `profiles/*.env` profiles, with no duplicate row when both exist for the same
  identity.
- **AC4** After `ai-new` completes, **no** mirrored copy exists under
  `profiles/` for that project.
- **AC5** A hand-authored legacy `profiles/<slug>.env` with no project tree
  still loads and runs via `ai-build`/`ai-launch`/`ai-terminal` (with the
  deprecation notice from R3.2 once Phase 3 lands).
- **AC6** `load_profile` no longer writes into `profiles/` under any code path.
- **AC7** The quality gate and reconcile paths complete without creating or
  refreshing any `profiles/*.env` file.
- **AC8** The full test suite passes after test updates (R4.2); no test still
  asserts the removed mirror/copy-back behaviour.

## Open Questions

- **Q1 (resolution key).** The project tree is keyed by raw `<name>` while the
  legacy registry is keyed by `sanitize_slug(<name>)`. Should project-local
  resolution look up `projects/<name>/` by the raw name, by the slug, or should
  project directories be standardized on the slug? This must be pinned before
  R1.1 to avoid resurfacing the latent name↔slug bug.
- **Q2 (phasing vs. single PR).** The idea frames three phases as a
  *compatibility timeline*. Should they ship as three separate releases (with a
  deprecation window between Phase 2 and Phase 3), or land together since the
  fallback in R1.1 already preserves legacy support? Phase 3's `_info`
  deprecation notice (R3.2) only matters if there is a real window.
- **Q3 (dedup identity).** For R2.2, what defines "the same profile" when
  de-duplicating list rows — `PROFILE_NAME`, the slug/basename, or
  `CONTAINER_NAME`? Sourcing every legacy `.env` to compare `PROFILE_NAME` is
  heavier than matching on filename.
- **Q4 (legacy authoring).** Is hand-authoring new `profiles/<slug>.env` files
  still a supported workflow going forward, or is the registry strictly a
  read-only compatibility shim for files that already exist?
