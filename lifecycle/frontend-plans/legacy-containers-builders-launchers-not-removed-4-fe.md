---
title: Remove Legacy Profile-Specific Containers, Builders, and Launchers — Frontend Plan
type: plan-frontend
status: abandoned
lineage: legacy-containers-builders-launchers-not-removed
parent: lifecycle/requirements/legacy-containers-builders-launchers-not-removed-2.md
---

# Frontend Plan — Docs & Desktop-Integration Cleanup

This project has **no web UI** (`web/src` does not exist), so there is no
component/styling work. The user-facing surface for a CLI + Podman-Desktop tool
is its **documentation and `.desktop` launcher entries**. This plan owns making
those accurate after the backend deletions — so no live doc or desktop entry
points at a removed script.

> Sequenced **after** backend M2/M3 (scripts + profiles removed). Pure
> documentation edits; no code, tests, or other lifecycle artifacts.

---

## Milestone F1 — Fix desktop-integration docs

**Description.** Remove the launcher table rows and `.desktop` `Exec=` examples
that point at deleted `launchers/*` scripts. Where a desktop entry is still
useful, rewrite it to call the generic command directly
(e.g. `ai-launch <profile> codex --non-interactive`) instead of a named
launcher, so the doc teaches the surviving entrypoint.

**Files to change.**
- `docs/desktop-integration.md` — drop the `launchers/esp32-codex`,
  `launchers/uxplay-codex`, `launchers/uxplay-builder` table rows (lines ~24–26)
  and the `Exec=…/launchers/esp32-codex` examples (lines ~48, ~61).

**Acceptance criteria.**
- [ ] `grep -nE 'launchers/(esp32-codex|uxplay-builder|uxplay-codex)|launch-esp32|launch-uxplay|short-launch|update-codex-.*-image|extra-terminal' docs/desktop-integration.md` returns nothing.
- [ ] Any remaining desktop `Exec=` example invokes a generic `ai-*` command.

## Milestone F2 — Fix the sandbox reference doc

**Description.** Remove the legacy-wrapper mapping table and the
`launchers/esp32-codex` desktop examples from the main reference doc.

**Files to change.**
- `docs/ai-agent-podman-sandbox.md` — delete the wrapper→generic mapping table
  rows (lines ~851–857: `launch-esp32-workspace`, `short-launch-esp32-workspace`,
  `launch-uxplay-workspace`, `launch-uxplay-builder`, `extra-terminal`,
  `update-codex-esp32-image`, `update-codex-uxplay-image`) and the
  `launchers/esp32-codex` `Exec=` examples (lines ~807, ~819).

**Acceptance criteria.**
- [ ] `grep -nE 'launch-esp32|launch-uxplay|short-launch|update-codex-.*-image|extra-terminal|launchers/esp32-codex' docs/ai-agent-podman-sandbox.md` returns nothing.

## Milestone F3 — Reconcile the product doc (`doc/`)

**Description.** `doc/ai-agent-podman-sandbox-product.md` is the heaviest
consumer (command tables, a `launchers/` tree diagram, and per-script `###`
sections at lines ~689–831). Remove every entry that names a deleted script.
This file is currently **untracked** (`?? doc/`) — if it is intended to ship,
fix it here; if it is scratch, note that in the PR and leave it. Default: fix it,
since the requirement's AC greps include `doc/`.

**Files to change.**
- `doc/ai-agent-podman-sandbox-product.md` — remove rows/sections/tree-diagram
  lines for all ten removed scripts (incl. the speculative
  `launch-uxplay-workspace.apb` entry at line ~48, which never existed as a
  tracked file).

**Acceptance criteria.**
- [ ] `grep -nE 'launch-esp32|launch-uxplay|short-launch|update-codex-.*-image|extra-terminal|launchers/(esp32-codex|uxplay-builder|uxplay-codex)' doc/ai-agent-podman-sandbox-product.md` returns nothing.

## Milestone F4 — Drop esp32/uxplay example-profile mentions

**Description.** Since the shipped `profiles/esp32.env.example` /
`profiles/uxplay.env.example` are removed (backend M3, req. Answer 1), update
docs that tell users to copy them. Replace the concrete esp32 example in
`docs/profiles.md` with a generic placeholder and point users at `ai-new` for
profile generation. README's generic `launchers/`/`profile.env` references
describe the *durable project* layout (not the removed top-level scripts) — leave
them unless they name a deleted path.

**Files to change.**
- `docs/profiles.md` — replace the `profiles/esp32.env` example block (lines
  ~50–65) and the "Copy `profiles/esp32.env.example`" instruction (line ~90)
  with a generic `<name>` example / `ai-new` reference.

**Acceptance criteria.**
- [ ] No doc instructs the reader to copy a now-deleted `*.env.example` file.
- [ ] `grep -rIn 'esp32\.env\.example\|uxplay\.env\.example' docs doc README.md` returns nothing.

## Milestone F5 — Final doc sweep

**Description.** Confirm the requirement's documentation AC holds across all live
docs.

**Files to change.** None (verification).

**Acceptance criteria.**
- [ ] `grep -rIl -e 'launchers/esp32-codex' -e 'launchers/uxplay-builder' -e 'launchers/uxplay-codex' -e 'launch-esp32-workspace' -e 'launch-uxplay-workspace' -e 'short-launch-esp32-workspace' -e 'launch-uxplay-builder' -e 'update-codex-esp32-image' -e 'update-codex-uxplay-image' -e 'extra-terminal' docs doc README.md` returns nothing.
- [ ] No source code, test, or non-doc artifact modified by this plan.
