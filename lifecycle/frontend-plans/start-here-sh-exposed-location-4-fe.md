---
title: Relocate start-here.sh out of the user-accessible host project tree — Frontend Plan
type: plan-frontend
status: done
lineage: start-here-sh-exposed-location
parent: lifecycle/backend-plans/start-here-sh-exposed-location-3-be.md
created: "2026-06-26T00:00:00+10:00"
priority: medium
assignees:
    - role: frontend-developer
      who: agent
---

# Relocate start-here.sh out of the user-accessible host project tree — Frontend Plan

This is a CLI tool: the "frontend" is operator-facing text — usage banners,
restart hints, launcher `_info` lines, and docs. R3.2 requires every printed
self-reference to match the new invocation path `/start-here/start-here.sh`
(chosen in the backend plan). All changes here are string edits; no logic.

## Milestone 1 — Update the in-script self-references (R3.2)

**Description.** `start-here.sh` prints its own path in three places that the
requirement names explicitly. Replace the old `/project/bootstrap/home/start-here.sh`
references with `/start-here/start-here.sh`.

- Placement comment (`start-here.sh:3`):
  `# Placed at /start-here/start-here.sh inside the bootstrap container by the ai-new launcher.`
- Usage banner (`start-here.sh:15`): the `or:` line →
  `   or: /start-here/start-here.sh [options]`
- "Restart the session with" hint (`start-here.sh:348`):
  `echo "  Then restart the session with:  /start-here/start-here.sh"`

Leave the `./start-here.sh` relative form (`start-here.sh:14`) and the
host-side `BOOTSTRAP_DIR` note alone — those remain valid for host execution.

**Files to change**
- `start-here.sh` — three string edits (lines 3, 15, 348).

**Acceptance criteria**
- `start-here.sh -h`/`--help` prints usage and exits 0 (AC5).
- The printed `or:` invocation path and the "restart with" hint both read
  `/start-here/start-here.sh` (AC5).
- No printed guidance still points at `/project/bootstrap/home/start-here.sh`.

## Milestone 2 — Update launcher operator messages (R3.1 surface)

**Description.** `launch_bootstrap()` prints an `Entrypoint:` line and carries a
placement comment, both naming the old path.

- `lib/launch.sh:24` → `_info "  Entrypoint:    /start-here/start-here.sh"`
- `lib/launch.sh:43-44` comment → describe the read-only `/start-here` mount
  instead of "delivered via the /project mount … no root bind mount".

**Files to change**
- `lib/launch.sh` — `_info` string + comment (backend plan owns the argv/mount
  logic on the same lines; coordinate so edits don't collide).

**Acceptance criteria**
- The launch banner's `Entrypoint:` line shows `/start-here/start-here.sh`.
- No operator-facing launcher text references the project-tree path.

## Milestone 3 — Reconcile docs and README (R3.2, B-consistency)

**Description.** Docs already describe `/start-here.sh` at the container root, an
older spec the code never matched; the relocation is the moment to make text and
behaviour agree on `/start-here/start-here.sh`.

- `README.md:66` ("`/start-here.sh` launches the …") — update path.
- `docs/ai-new.md` location/usage references — notably `:114`, `:167-174`
  ("lives at the filesystem root", usage block) — update to the mounted path and
  describe it as a **read-only, non-`/project` mount** delivered by the launcher.
- `docs/ai-new.md:836` `.gitignore` note and HOME references at `:276,:284,:532`
  are about `bootstrap/home/` as **HOME/data** — those stay (Answer 3); only the
  **script** path changes.

**Constraint.** `tests/test_spec_reconciled.sh` (T3c) flags doc lines that claim a
**root** location without a supersession note. Updating to `/start-here/start-here.sh`
(a subdir, not root) satisfies it; do not reintroduce root-location phrasing.

**Files to change**
- `README.md`, `docs/ai-new.md` — path strings; keep HOME/data references intact.

**Acceptance criteria**
- No doc/README line presents the entrypoint at `/project/bootstrap/home/` or at
  the container root as current behaviour.
- `tests/test_spec_reconciled.sh` still passes (no unannotated root-location claim).
- HOME-as-`bootstrap/home` documentation is unchanged.
