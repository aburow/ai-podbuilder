---
title: Relocate start-here.sh out of the user-accessible host project tree — Backend Plan
type: plan-backend
status: draft
lineage: start-here-sh-exposed-location
parent: lifecycle/requirements/start-here-sh-exposed-location-2.md
created: "2026-06-26T00:00:00+10:00"
priority: medium
assignees:
    - role: backend-developer
      who: agent
---

# Relocate start-here.sh out of the user-accessible host project tree — Backend Plan

Answer 1 settles the design: **read-only mount (R2.a)**, no image bake. The
framework already mounts `prompts/` read-only at `/start-here-prompts`
(`lib/launch.sh:46-49`); this plan adds one sibling mount for the entrypoint and
deletes the project-tree copy path. Net effect: one mount added in `launch.sh`,
one function + one call removed in `scaffold.sh`. No new machinery.

## Chosen container path

`/start-here/start-here.sh` — a dedicated namespace consistent with the existing
`/start-here-prompts` / historical `/start-here-lib` convention (Q4 deferred this
to planning; it is operationally irrelevant per the requirement's own answer).

**Do not** reuse `/start-here.sh` at the container root: `tests/test_spec_reconciled.sh`
(T3c) actively guards the docs against re-presenting a root location as current
spec. A dedicated subdir avoids reopening that.

## Milestone 1 — Mount the framework script read-only and use it as the entrypoint (R2.a, R3.1, R3.3, R4.1)

**Description.** In `launch_bootstrap()`, add a read-only bind of the live
framework copy and point the entrypoint argv at it. Because the live framework
file is mounted, each launch runs the current version inherently (R4.1) and the
container user cannot modify it (read-only mount, AC3).

- Add to the `_args` array (next to the prompts mount, ~`lib/launch.sh:46-49`):
  ```bash
  # start-here.sh is delivered read-only from the framework dir (not /project),
  # so it is neither host-project-visible nor container-writable.
  _args+=(--volume "${AI_PODMAN_JAILS_DIR}/start-here.sh:/start-here/start-here.sh:ro,z")
  ```
- Change the entrypoint base (`lib/launch.sh:54`):
  ```bash
  local _entrypoint=(/start-here/start-here.sh)
  ```
- The existing `--resume` / `--shell-on-exit` append logic (`lib/launch.sh:55-61`)
  is unchanged — argument pass-through preserved (R3.3).

**Files to change**
- `lib/launch.sh` — add mount, change `_entrypoint` base path.

**Acceptance criteria**
- `_entrypoint` is `/start-here/start-here.sh` (+ any flags), never under `/project`.
- The `--volume …:ro,z` for the script is present and read-only.
- `--resume` and `--shell-on-exit` still append exactly as before.
- The `--volume "${_proj}:/project:z"` project mount and all safety-posture flags
  (`--userns=keep-id`, `--network host`, no socket, no `--privileged`) are untouched.

## Milestone 2 — Stop staging the script into the project tree (R1.1, R1.2)

**Description.** Remove the copy-into-project flow. `refresh_bootstrap_entrypoint()`
exists only to keep the per-project copy current (`lib/scaffold.sh:129-143`); with
the live file now mounted, the function's whole purpose is gone, so delete it and
its call rather than gutting it to a no-op (dead code is debt).

- Delete the call at `lib/scaffold.sh:15` (`refresh_bootstrap_entrypoint "$PROJECT_ROOT"`).
- Delete the `refresh_bootstrap_entrypoint()` definition (`lib/scaffold.sh:129-143`).
- Per Answer 2, **do not** add removal of pre-existing
  `${project_root}/bootstrap/home/start-here.sh` left by older versions — leave
  stale files untouched (no cleanup code).

**Caller audit (root-cause check).** `refresh_bootstrap_entrypoint` is referenced
only at `lib/scaffold.sh:15` and `bin/ai-new` (resume path — verify the line and
remove it there too). Grep both before deleting:
```bash
grep -rn 'refresh_bootstrap_entrypoint' bin/ lib/
```
Every non-test caller must be removed so nothing recreates the project-tree copy.

**Files to change**
- `lib/scaffold.sh` — remove call + function.
- `bin/ai-new` — remove the resume-path `refresh_bootstrap_entrypoint` call if present.

**Acceptance criteria**
- No non-test code writes `start-here.sh` under `${project_root}/bootstrap/home/`
  (or anywhere under `/project`).
- `grep -rn refresh_bootstrap_entrypoint bin/ lib/` returns nothing.
- `create_scaffold` and the resume path still run end-to-end (scaffold layout,
  slug registration, profile/README writes unaffected).

## Milestone 3 — Preserve data access and install footprint (R5, R7)

**Description.** Confirm — no code change expected — that the relocation leaves the
data contract and install set intact.

- `start-here.sh:7` keeps `BOOTSTRAP_DIR="/project/bootstrap"`; the project mount
  still delivers `agent.env`, `agent.env.local`, `session.json`,
  `bootstrap-prompt.md` (R5.1). The restricted registry parser is untouched (R5.2).
- `install.sh` managed set still lists `start-here.sh` as the single canonical
  source (`install.sh:93`) and `chmod +x`'s it (`install.sh:136`). No second
  user-facing copy is introduced (R7.1). No change required here — this milestone
  is a verification gate, not new code.

**Files to change**
- None expected. Flag for follow-up only if Milestone 1/2 forced a path constant
  out of `start-here.sh` or `install.sh`.

**Acceptance criteria**
- `BOOTSTRAP_DIR` semantics unchanged; registry still read via the restricted
  parser, never `source`/`eval`.
- `install.sh` ships exactly one `start-here.sh`.

## Out of scope (from requirement)

- Hardening `/project/bootstrap` **data** files (Non-goal).
- The `HOME`-in-project-tree concern (Answer 3: explicitly fine).
- Container security posture changes (Non-goal).
- Operator-facing string updates — owned by the **frontend plan** (R3.2).
- Test updates — owned by the **test plan** (R6).
