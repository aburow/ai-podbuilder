---
title: Project-Local Profile Canonicalization
type: idea
status: approved
lineage: project-local-profiles
created: "2026-06-26T13:04:14+10:00"
priority: normal
---

# Project-Local Profile Canonicalization

Move from a central `profiles/` registry to project-owned profiles at `projects/<name>/profile.env`, making the project tree the single source of truth for durable sandbox configuration. The repo already generates `projects/<name>/profile.env` via `ai-new` but then mirrors it into `profiles/` for discovery and command compatibility — creating drift risk, a split mental model, and a project layout that is less self-contained than it appears.

The target model resolves profile identity directly from the project tree: `load_profile()` prefers `projects/<name>/profile.env` first and falls back to `profiles/<name>.env` only for hand-authored legacy profiles; `ai-list` enumerates `projects/*/profile.env` directly; scaffold code stops copying generated profiles into `profiles/`; and docs reframe `profiles/` as an optional compatibility area rather than required runtime state. A three-phase compatibility strategy (dual-read → dual-discovery → deprecation) preserves support for existing users who rely on `profiles/<name>.env` without a corresponding project tree.

Acceptance criteria center on `ai-build`, `ai-launch`, and `ai-terminal` working with only the project-local profile present; `ai-list` functioning when `profiles/` does not exist; `ai-new` creating no mirrored copy; and legacy profiles continuing to work during transition. This is a cleanup and model-alignment change — the runtime already supports project-local profiles; the remaining work is discovery semantics, compatibility handling, and removal of central-registry assumptions.
