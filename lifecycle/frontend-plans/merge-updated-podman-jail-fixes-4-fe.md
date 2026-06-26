---
title: Merge Updated podman-jail Bug Fixes — Frontend Plan
type: plan-frontend
status: in-development
lineage: merge-updated-podman-jail-fixes
parent: lifecycle/requirements/merge-updated-podman-jail-fixes-2.md
---

# Merge Updated podman-jail Bug Fixes — Frontend Plan

There is **no web frontend** (`web/src` does not exist). `podman-jails` is a
Bash CLI package. The "frontend" here is the user-facing surface: CLI output /
help text, the README, the scaffolding templates, and the bootstrap prompt.
This plan covers reconciling that surface as part of the merge. Most of the
work is a straight copy (updated wins); the value-add is verifying the
user-facing text is coherent post-merge.

> Skipped: any web UI work — none exists. Add a real FE plan only if a web
> surface is introduced later.

## M1 — Merge user-facing templates and prompts

**Description:** Copy the updated user-facing assets. These drive what users
see when they scaffold a project or read generated output.

**Files to change (copy from updated tree):**
- `README.md`
- `prompts/bootstrap-prompt.md`
- `templates/README.tmpl`, `templates/launcher.tmpl`,
  `templates/profile.env.tmpl`

**Acceptance criteria:**
- [x] Each file byte-identical to the updated tree.
- [x] No keep-local template/launcher content lost (cross-check against
      `launchers/` which stays untouched).

## M2 — Verify rendered CLI output is coherent

**Description:** The updated `lib/scaffold.sh`/`templates/*` change what
generated projects contain (`.env.example`, `.gitignore`, refreshed entrypoint).
Render once and eyeball the result so the merged templates produce sane,
non-broken output — not just that files match.

**Files to change:** none (verification).

**Commands:**
```
tests/run_tests.sh tests/90_render.sh   # render path
tests/run_tests.sh tests/53_gui.sh      # GUI-forwarding user path
```

**Acceptance criteria:**
- [x] `90_render.sh` passes; generated scaffold contains the expected
      `.env.example` and `.gitignore`.
- [x] `--help` / usage output for `ai-new`, `ai-build`, `ai-launch`, `ai-list`
      runs without error and reflects merged flags (e.g. GUI forwarding).
- [x] README references no excluded runtime artifact (`projects/`, the three
      `profiles/*.env`, `slug-index.tsv`) as if it were shipped content.

## M3 — Documentation consistency pass

**Description:** Confirm README and bootstrap prompt describe the merged
behavior (durable projects, GUI forwarding) rather than the pre-fix state. Fix
only outright contradictions introduced by the merge; do not rewrite docs.

**Files to change:** `README.md`, `prompts/bootstrap-prompt.md` (only if a
contradiction is found).

**Acceptance criteria:**
- [ ] No stale instruction in README contradicts merged CLI behavior.
- [ ] Any doc edit is committed in the docs/templates focused commit (M5 of the
      backend plan).
