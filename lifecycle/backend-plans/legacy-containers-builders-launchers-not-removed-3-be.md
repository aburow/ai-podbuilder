---
title: Remove Legacy Profile-Specific Containers, Builders, and Launchers — Backend Plan
type: plan-backend
status: abandoned
lineage: legacy-containers-builders-launchers-not-removed
parent: lifecycle/requirements/legacy-containers-builders-launchers-not-removed-2.md
---

# Backend Plan — Remove Legacy Launchers, Wrappers & Example Profiles

Scope: delete the source artifacts (scripts + shipped example profiles) and push
the deletions to `origin/main`. Documentation lives in the **frontend plan**;
the test-suite contract (AC12 retirement + profile-fixture decoupling) lives in
the **test plan**. Do **not** touch the generic `ai-*` commands, current `lib/`,
or `templates/Containerfile.durable.tmpl`.

> **Hard dependency / sequencing:** The test suite seeds its profile fixtures
> from `profiles/*.env.example` (`tests/helpers/setup.bash:94`). Removing the
> example profiles (Milestone 3) will break ~10 test files (`10_profile`,
> `20_safety_policy`, `40_modes`, `80_stale`, `81_reset`, `90_render`,
> `11_ai-build`, …) **unless** the test-plan fixture-decoupling milestone lands
> first or in the same change. **Land test-plan M-T2 before/with this plan's M3.**

---

## Milestone B1 — Inventory & verify-before-delete

**Description.** Produce the definitive removal list and confirm nothing in an
active code path depends on each artifact before deleting. An artifact qualifies
as legacy when it is (a) hardcoded to esp32/uxplay AND (b) a pure pass-through to
a generic `ai-*` command.

Confirmed removal set (already classified during planning):

| Path | Forwards to | Verdict |
|------|-------------|---------|
| `launchers/esp32-codex` | `ai-launch esp32 codex --non-interactive` | remove |
| `launchers/uxplay-builder` | `ai-launch uxplay builder --non-interactive` | remove |
| `launchers/uxplay-codex` | `ai-launch uxplay codex --non-interactive` | remove |
| `bin/launch-esp32-workspace` | `ai-launch esp32 "$@"` | remove |
| `bin/launch-uxplay-workspace` | `ai-launch uxplay …` | remove |
| `bin/short-launch-esp32-workspace` | `ai-launch esp32 …` | remove |
| `bin/launch-uxplay-builder` | `ai-launch uxplay builder` | remove |
| `bin/update-codex-esp32-image` | `ai-build esp32` | remove |
| `bin/update-codex-uxplay-image` | `ai-build uxplay` | remove |
| `bin/extra-terminal` | `ai-terminal "${1:-esp32}"` (self-labelled "Legacy wrapper") | remove |
| `profiles/esp32.env.example` | shipped example profile | remove (req. Answer 1) |
| `profiles/uxplay.env.example` | shipped example profile | remove (req. Answer 1) |

**Files to change.** None (read-only inventory step). Run:
`grep -rIn -e '<each-path>' bin lib tests docs doc templates README.md` and
record any live consumer per artifact in the PR/commit note.

**Acceptance criteria.**
- [ ] Each path above has a recorded grep result.
- [ ] The only references found are: `tests/70_wrappers.sh` (AC12 — test plan),
      `docs/`+`doc/` prose (frontend plan), and `tests/helpers/setup.bash`
      profile glob (test plan). No reference sits inside a generic `ai-*`
      command or in `lib/`.
- [ ] Any newly discovered legacy pass-through not in the table is added to it
      (and flagged) rather than silently deleted.

## Milestone B2 — Remove legacy launcher & wrapper scripts

**Description.** `git rm` the ten launcher/wrapper scripts. Keep
`launchers/.gitkeep` so the directory survives.

**Files to change.**
- `git rm launchers/esp32-codex launchers/uxplay-builder launchers/uxplay-codex`
- `git rm bin/launch-esp32-workspace bin/launch-uxplay-workspace bin/short-launch-esp32-workspace bin/launch-uxplay-builder bin/update-codex-esp32-image bin/update-codex-uxplay-image bin/extra-terminal`
- Leave `launchers/.gitkeep`, all `bin/ai-*` commands untouched.

**Acceptance criteria.**
- [ ] The ten script paths no longer exist in the working tree.
- [ ] `git ls-files bin launchers | grep -E 'esp32|uxplay|extra-terminal'`
      returns nothing.
- [ ] `bin/ai-build`, `bin/ai-launch`, `bin/ai-terminal`, `bin/ai-list`,
      `bin/ai-new` are byte-identical to pre-change (verify via `git diff`).

## Milestone B3 — Remove shipped example profiles

**Description.** `git rm` the two legacy example profiles (req. Answer 1 —
`ai-new` now generates profiles, so shipped esp32/uxplay examples are dead).
Keep `profiles/.gitkeep`.

> **Blocked by test-plan M-T2.** Verify `tests/helpers/setup.bash` no longer
> globs `profiles/*.env.example` for fixtures before deleting, or run the suite
> immediately after and expect the fixture decoupling to already be in place.

**Files to change.**
- `git rm profiles/esp32.env.example profiles/uxplay.env.example`
- Leave `profiles/.gitkeep`.

**Acceptance criteria.**
- [ ] `profiles/` contains no `*.env.example` files (only `.gitkeep`).
- [ ] `bash tests/run_tests.sh` still passes (relies on test-plan fixture work).

## Milestone B4 — Commit & push deletions to `main`

**Description.** Commit the removals with a note recording which artifacts went
and that AC12 is intentionally retired (cross-reference the test-plan change).
Push to `origin/main` so the artifacts are gone from GitHub, not just locally.
Use the project commit conventions (no skipped hooks, no signing bypass).

**Files to change.** Git history only.

**Acceptance criteria.**
- [ ] Commit message lists every removed artifact and states "AC12 retired —
      backwards-compat wrappers are dead (req. Answer 2)".
- [ ] `git fetch && git ls-tree -r origin/main --name-only` shows none of the
      removed paths.
- [ ] No changes to `templates/Containerfile.durable.tmpl` or `lib/` in the diff.
