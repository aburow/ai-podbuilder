---
title: Deprecate CODEX_* Env Vars in Favour of AI_PODMAN_* — Frontend Plan
type: plan-frontend
status: approved
lineage: deprecate-codex-jails-env-vars
parent: lifecycle/requirements/deprecate-codex-jails-env-vars-2.md
---

# Frontend Plan — Deprecate CODEX_* in Favour of AI_PODMAN_*

**No web/UI work.** This is a shell plugin; there is no `web/src` surface
(confirmed: directory does not exist). The only user-facing output is CLI text,
and that lives in `lib/usage.sh` + the stderr deprecation warning — both owned by
the **backend plan** (Milestones 1, 5). The interactive yes/no setup prompts
floated in the requirement's Q5 belong to the future installation system, which
is **explicitly out of scope** here.

This plan exists only to satisfy the `required_plans.ticket` contract. There is
nothing to build.

## Milestone 1 — Confirm no frontend surface (no-op)

**Description.** Verify there is no web/desktop UI that references the env vars,
so the rename has no frontend impact.

**Files to change.** None.

**Acceptance criteria.**
- `web/` / `web/src` absent or contains no reference to `CODEX_*`.
- `grep -rn 'CODEX_' web 2>/dev/null` returns nothing.
- All user-facing naming changes are delivered by the backend plan's help-text
  and warning milestones; no separate frontend change is required.
