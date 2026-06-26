---
title: Project-Local Profile Canonicalization
type: requirement
status: abandoned
lineage: project-local-profile-canonicalization
parent: lifecycle/ideas/project-local-profile-canonicalization.md
assignees:
    - role: product-owner
      who: agent
---

# Project-Local Profile Canonicalization

## Problem

Durable sandbox configuration currently lives in two places. Each generated
project owns `projects/<name>/profile.env`, but the runtime treats the central
`$CODEX_JAILS_DIR/profiles/<name>.env` registry as canonical:

- `load_profile <name>` (`lib/profile.sh:69-98`) resolves
  `$(profiles_dir)/<name>.env` first and only falls back to the project-local
  file as a recovery copy — and that fallback **copies** the project file back
  into the central registry as a side effect.
- `ai-list` (`bin/ai-list:24-37`) requires `profiles/` to exist (`_die` if
  absent), mirrors every `projects/*/profile.env` into it via
  `install_generated_profile`, then lists `profiles/*.env`.
- `ai-new` (`bin/ai-new:151,195`), `reconcile.sh:133`, and
  `quality_gate.sh:187` all call `install_generated_profile`
  (`lib/scaffold.sh:115-130`), which copies the project-local file into the
  central registry.

This dual-mode layout creates configuration drift (edit the project file, the
stale central mirror keeps being used), split ownership, and incorrect
discovery semantics. The system has not been released externally and all
deployed environments already carry both copies, so no staged migration or
backward-compatibility shim is needed — the central registry should simply be
removed from the runtime model.

## Goals / Non-goals

**Goals**

- Make `projects/<name>/profile.env` the single source of truth for durable
  sandbox configuration.
- Resolve profiles directly from the project-local path in `ai-build`,
  `ai-launch`, `ai-terminal`, and `ai-list`.
- Stop `ai-new` (and `reconcile`, `quality_gate`) from creating or mirroring
  `profiles/<name>.env`.
- Make generated projects fully self-contained.
- Update documentation (`docs/profiles.md`, `README.md`) to describe only the
  project-local layout.

**Non-goals**

- No migration tooling, deprecation warnings, or read-from-old-location
  fallback for the central registry.
- No change to the profile **file format** or its required/optional fields.
- No change to project directory layout under `projects/<name>/`.

## Detailed Requirements

**R1 — Profile resolution by project name.**
`load_profile <name>` MUST resolve the profile at
`${CODEX_JAILS_DIR}/projects/<name>/profile.env`. The central
`$(profiles_dir)/<name>.env` lookup and the recovery-copy fallback
(`lib/profile.sh:72-83`) MUST be removed. When the project-local file is
absent, it MUST `_die` with a message naming the expected project-local path.

**R2 — Remove the central registry from the runtime.**
The `profiles_dir()` helper (`lib/common.sh:31-33`) and
`install_generated_profile()` (`lib/scaffold.sh:115-130`) MUST be removed (or
reduced to no dependence on a central directory), along with all call sites:
`ai-new:151,195`, `ai-list:31`, `reconcile.sh:133`, `quality_gate.sh:187`. No
runtime code path may create, write to, or read from
`$CODEX_JAILS_DIR/profiles/`.

**R3 — `ai-list` discovers projects directly.**
`ai-list` MUST enumerate profiles by iterating
`${CODEX_JAILS_DIR}/projects/*/profile.env` instead of `profiles/*.env`. It
MUST NOT require a `profiles/` directory and MUST NOT mirror project files. The
rendered table columns (name, image, workspace, container state) and
no-profiles-found behaviour MUST be preserved.

**R4 — `ai-new` produces self-contained projects.**
`ai-new` MUST write `projects/<name>/profile.env` as the only profile output
and MUST NOT create `profiles/<name>.env`. Validation of the generated profile
(via `validate_profile_file` / `validate_loaded_profile`) MUST still run
against the project-local file.

**R5 — Validation unchanged.**
The set of required fields and the array-normalisation / `EXTRA_*` validation
in `lib/profile.sh:8-67` MUST remain unchanged; only the file's location
changes.

**R6 — Documentation.**
`docs/profiles.md`, `README.md:18`, and `docs/ai-new.md` MUST describe profiles
as living at `projects/<name>/profile.env`. References to a `profiles/`
directory as the discovery location MUST be removed or corrected.

## Acceptance Criteria

1. With **no `profiles/` directory present**, `ai-build <name>`, `ai-launch
   <name>`, `ai-terminal <name>`, and `ai-list` all function correctly against
   projects that have only `projects/<name>/profile.env`.
2. After `ai-new <name>`, the project is self-contained: `projects/<name>/profile.env`
   exists and **no** `profiles/<name>.env` is created.
3. `ai-list` lists every project under `projects/*/profile.env` and creates no
   files under `profiles/`.
4. `grep -rn "profiles_dir\|install_generated_profile\|/profiles/" bin lib`
   returns no runtime references to the central registry.
5. `ai-build`/`ai-launch`/`ai-terminal` invoked with a name that has no
   `projects/<name>/profile.env` fail with a clear error naming the
   project-local path.
6. `shellcheck` / the repo's build+vet gate passes; `docs/profiles.md`,
   `README.md`, and `docs/ai-new.md` reference only the project-local path.

## answers

1. **Hand-authored / non-project profiles.** `profiles/esp32.env.example`
   (referenced in `docs/profiles.md:50,90`) is a hand-authored template not
   tied to a generated project. Once `profiles/` is no longer a discovery
   location, is this example relocated under a project, kept purely as
   documentation, or dropped?
2. **Cleanup of existing central files.** Deployed environments already contain
   `profiles/*.env`. Should this change leave those orphaned files in place
   (ignored by the runtime), or delete the directory? The idea implies no
   migration, suggesting "leave in place / ignore" — confirm.
3. **Name-to-project mapping.** Resolution now keys on project directory name.
   Is the profile name argument always identical to the `projects/<name>`
   directory name, or does `PROFILE_NAME` inside the file ever differ from the
   directory and need reconciling?
