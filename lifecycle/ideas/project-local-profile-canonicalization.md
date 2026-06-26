---
title: Project-Local Profile Canonicalization
type: idea
status: clarifying
lineage: project-local-profile-canonicalization
created: "2026-06-26T13:33:08+10:00"
priority: normal
labels:
    - defect
---

# Project-Local Profile Canonicalization

Remove the legacy central `profiles/` registry from the runtime model and make each project's own `projects/<name>/profile.env` the single source of truth for durable sandbox configuration. The system currently mirrors project-local profiles into `profiles/<name>.env`, introducing configuration drift risk, split ownership, and incorrect discovery semantics.

Because this system has not been released externally and all deployed environments already operate in the dual-mode layout, no staged compatibility plan is required. The change should directly remove all central-registry assumptions from profile loading, project discovery (`ai-list`), project scaffolding (`ai-new`), and documentation.

Acceptance requires that `ai-build`, `ai-launch`, `ai-terminal`, and `ai-list` all function correctly with no `profiles/` directory present, that `ai-new` no longer creates or mirrors `profiles/<name>.env`, and that generated projects are fully self-contained with `projects/<name>/profile.env` as the only supported profile path.
