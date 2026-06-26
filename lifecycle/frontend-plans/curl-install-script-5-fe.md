---
title: Curl-Driven Install Script for ai-podbuilder — Frontend Plan
type: plan-frontend
status: draft
lineage: curl-install-script
parent: lifecycle/requirements/curl-install-script-3.md
---

# Frontend Plan — Curl-Driven Install Script

**No web/UI surface.** This is a shell plugin (`web/`/`web/src` do not exist).
The only "frontend" is user-facing text: the installer's printed output (owned
by the **backend plan**, Milestones 1, 3, 7, 8) and the README. This plan owns
the README — replacing the manual "PATH Setup" instructions with the supported
curl one-liner — and reviews the backend's user-facing copy for consistency.

## Milestone 1 — README install section

**Description.** Replace README "PATH Setup" (`README.md:73-83`), which still
hand-exports the deprecated `CODEX_JAILS_DIR`, with the curl install path as the
supported method (Q5: latest GitHub release is the advertised URL).

**Files to change.**
- `README.md`:
  - New `## Install` section above current workflows: the
    `curl -fsSL <release-url> | bash` one-liner, the optional install-root arg
    and `~/ai-podman-jails` default, the env-file path
    (`~/.bashrc.d/podbuilder.sh`), and the exact `source …` activation line.
  - Note idempotent re-run = update, and how to uninstall (remove install root +
    env file) — the documented stand-in for a dedicated uninstaller (Non-goals).
  - Rewrite "PATH Setup" to reference `AI_PODMAN_JAILS_DIR` for the
    self-hosting-checkout case; drop the `CODEX_JAILS_DIR` export.

**Acceptance criteria.**
- README documents the curl one-liner as the supported install (AC1/AC2 path).
- README no longer instructs exporting `CODEX_JAILS_DIR` (AC10 consistency).
- The advertised URL points at the project's latest GitHub release (Q5).
- Uninstall (remove root + env file) is documented.

## Milestone 2 — User-facing copy review (no separate code)

**Description.** Confirm the installer's `--help`, prerequisite-error, migration
warning, and post-install messages (all in `install.sh`, backend plan) read
consistently with the README and name paths/variables correctly. No new files —
this is a review gate, fixes land in the backend script.

**Files to change.** None (review only; corrections in `install.sh`).

**Acceptance criteria.**
- `--help` text matches README wording for the default root and env-file path
  (R1.3).
- Error/warning/post-install strings name `AI_PODMAN_JAILS_DIR` (never instruct
  setting `CODEX_JAILS_DIR`) and give the exact `source` activation command
  (R5.5, R6.1).
- `grep -rn 'CODEX_' README.md install.sh` shows `CODEX_JAILS_DIR` only in the
  legacy-migration warning context, nowhere as guidance to set it.
