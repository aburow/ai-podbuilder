---
title: Project-Local Profile Canonicalization — Frontend Plan
type: plan-frontend
status: done
lineage: project-local-profiles
parent: lifecycle/backend-plans/project-local-profiles-3-be.md
---

# Project-Local Profile Canonicalization — Frontend Plan

This project has no GUI; the "frontend" surface is the CLI's user-facing output
(messages, `ai-list` table copy) and the documentation. Covers R3.2 wording,
R4.1 docs, and the `ai-list` empty-state message. Depends on the backend plan
having moved discovery onto the project tree.

## Milestone 1 — Deprecation notice wording (R3.2)

Backend emits the legacy `_info` from `load_profile`; this milestone owns the
exact string so it reads consistently with other framework messages.

Files to change:
- `lib/messages.sh` (or `lib/profile.sh` inline if no message helper fits) —
  define the one-line notice, e.g.:
  `[INFO] Loaded legacy profile <slug>.env from profiles/; the canonical location is projects/<name>/profile.env. profiles/ is an optional compatibility area.`
  Keep it a single `_info` line; do not repeat per field.

Acceptance criteria:
- The notice names both the legacy path it loaded from and the canonical
  project-local path.
- It appears once per legacy load and never for project-local loads (AC5).

## Milestone 2 — `ai-list` user-facing copy (R2.3, AC2)

Files to change:
- `bin/ai-list` — the "No profiles found" message must read sensibly when
  `profiles/` is absent (it should reference the project tree, not only
  `profiles/`). Suggested: `No profiles found (looked in projects/ and profiles/)`.
- Confirm the table header/columns (`PROFILE/IMAGE/WORKSPACE/STATE`) are
  unchanged — `render_profile_table` in `lib/render.sh` needs no edits; rows now
  originate from both sources but the row format is identical.

Acceptance criteria:
- Running `ai-list` with no profiles anywhere prints the empty-state line and
  exits 0 (AC2).
- Legacy-only and project-local profiles render in the same table with identical
  column formatting (AC3).

## Milestone 3 — Documentation (R4.1)

Files to change:
- `README.md` — describe `projects/<name>/profile.env` as the canonical,
  authoritative profile location; reframe `profiles/` as an optional,
  hand-authored legacy/compatibility area that the tooling no longer writes to.
- `doc/**` and any `lifecycle/docs/**` that describe the profile registry —
  update the same way. Note that hand-editing `profiles/<slug>.env` remains
  supported (Q4) but that normal `ai-new`/`ai-list`/resume flows manage the
  project-local file and never mirror into `profiles/`.
- Profile examples `profiles/esp32.env.example`, `profiles/uxplay.env.example` —
  add a short header comment marking them as legacy-compatibility examples and
  pointing at the project-local layout. Do not change their fields.

Acceptance criteria:
- No doc states or implies `profiles/` is required runtime state or that
  `ai-new` registers a copy there.
- Docs explicitly state project-local is canonical and `profiles/` is optional
  legacy.

## Out of scope

- Profile file format and validated fields (unchanged).
- The discovery/dedup logic and the decision to emit the notice (backend plan).
