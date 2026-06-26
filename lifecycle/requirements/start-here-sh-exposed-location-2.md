---
title: Relocate start-here.sh out of the user-accessible host project tree
type: requirement
status: blocked
lineage: start-here-sh-exposed-location
parent: lifecycle/defects/start-here-sh-exposed-location.md
assignees:
    - role: product-owner
      who: agent
---

# Relocate start-here.sh out of the user-accessible host project tree

## Problem

`start-here.sh` is the framework-owned entrypoint for the disposable bootstrap
container. It is internal tooling: it parses the pinned agent registry, runs the
auth gate, and launches the selected runtime. It is **not** meant to be read,
edited, or run directly by the user on the host.

Today the script is copied into the host project tree and delivered to the
container through the project bind mount:

- `refresh_bootstrap_entrypoint()` (`lib/scaffold.sh:132`) copies the framework
  copy from `${AI_PODMAN_JAILS_DIR}/start-here.sh` to
  `${project_root}/bootstrap/home/start-here.sh` before every launch and
  `chmod +x` it.
- `launch_bootstrap()` (`lib/launch.sh`) mounts the whole project root at
  `/project` (`--volume "${_proj}:/project:z"`), sets
  `HOME=/project/bootstrap/home`, and invokes
  `/project/bootstrap/home/start-here.sh` as the entrypoint. The launch comment
  states the script is "delivered via the /project mount … no root bind mount"
  (`lib/launch.sh:43-44`).

Because `bootstrap/home/` lives inside the user's project directory, the script
sits in a user-facing, user-writable host location. That exposes it to:

- **Tampering / corruption** — a user (or an agent writing into its own `$HOME`,
  since `bootstrap/home` is also the container `HOME`) can edit or delete the
  entrypoint, breaking subsequent launches or altering the auth gate.
- **Confusion** — the file looks like a project artifact the user is expected to
  manage, when it is framework internals refreshed on every launch.

Note the existing precedent: other internal resources are already delivered via
dedicated, read-only, non-`/project` mount points — prompts at
`/start-here-prompts` (`lib/launch.sh:46-49`) and, historically, libraries at
`/start-here-lib` (see [[start-here-lib-host-execution]]). The entrypoint is the
one internal resource still routed through the user-facing project tree.

## Goals / Non-goals

**Goals**

- Deliver `start-here.sh` to the bootstrap container from a location that is
  **not** part of the user-facing/user-writable host project tree.
- Make the in-container entrypoint **non-modifiable** by the container user and
  by the host user during normal use.
- Preserve all current behaviour: argument handling (`--agent`, `--resume`,
  `--shell-on-exit`, `-h`), the auth gate, runtime resolution, prompt copying,
  and reading registry/state from `/project/bootstrap` (`agent.env`,
  `agent.env.local`, `session.json`, `bootstrap-prompt.md`).
- Guarantee each launch runs the **current framework version** of the script
  (the property `refresh_bootstrap_entrypoint()` exists to provide), with no
  stale per-project copy persisting.
- Keep the script host-side testable (tests execute a patched copy from the repo
  root — see [[start-here-lib-host-execution]] and the hardcoded-`BOOTSTRAP_DIR`
  note in `lifecycle/tests/ai-new-13-tests.md`).

**Non-goals**

- Relocating or hardening the `/project/bootstrap` **data** files (`agent.env`,
  `agent.env.local`, `session.json`, generated artifacts). Those legitimately
  live under the project and are out of scope; this change concerns the
  executable script's location only.
- Changing the container security posture (no Podman socket, `--network host`,
  `--userns=keep-id`, etc.).
- Redesigning `start-here.sh`'s internal logic beyond what the relocation
  requires.
- Changing where the framework itself is installed (`install.sh` managed set).

## Detailed Requirements

### R1 — Remove the script from the user-facing project tree

- **R1.1** `start-here.sh` MUST NOT be written into, or executed from,
  `${project_root}/bootstrap/home/` (or any other path under the bind-mounted
  `/project` tree that is user-visible/user-writable).
- **R1.2** `refresh_bootstrap_entrypoint()` MUST no longer copy the script into
  the project tree. If a per-project copy currently exists from prior launches,
  the new flow MUST NOT depend on it and SHOULD avoid leaving an executable copy
  there. (How to treat pre-existing copies on resume is an open question — see
  Open Questions.)

### R2 — Deliver the script from a protected, internal location

The script MUST reach the container through one of the following acceptable
mechanisms (final choice deferred to planning; both must satisfy R3–R5):

- **R2.a (read-only mount)** Bind-mount the framework copy
  (`${AI_PODMAN_JAILS_DIR}/start-here.sh`) read-only to a dedicated,
  non-`/project` container path (consistent with `/start-here-prompts` and the
  prior `/start-here-lib` convention), and use that path as the entrypoint. The
  mount MUST be read-only so the container user cannot modify it.
- **R2.b (baked into image)** `COPY` the script into the bootstrap image at a
  protected, root-owned path (e.g. under `/usr/local/lib` or `/opt`) during
  image build, and invoke it from there. If chosen, image caching MUST be
  invalidated when the framework `start-here.sh` content changes, so launches
  always run the current version (see R4).

### R3 — Entrypoint resolution and invocation

- **R3.1** `launch_bootstrap()` MUST invoke the script from its new protected
  location, not from `/project/bootstrap/home/start-here.sh`.
- **R3.2** The script's self-references in usage/help and operator-facing
  messages (currently `/project/bootstrap/home/start-here.sh`, e.g.
  `start-here.sh:15,348`) MUST be updated to the new invocation path so the
  printed "restart with" guidance is correct.
- **R3.3** All current entrypoint arguments (`--resume`, `--shell-on-exit`, and
  the implicit default run) MUST continue to be passed through unchanged.

### R4 — Always run the current framework version

- **R4.1** Each launch MUST execute the framework's current `start-here.sh`, not
  a stale per-project or cached copy. For R2.a this is inherent (the live
  framework file is mounted); for R2.b the image build MUST rebuild or
  cache-bust when the script content changes.

### R5 — Data access preserved

- **R5.1** The relocated script MUST retain read access to `/project/bootstrap`
  data: `agent.env`, `agent.env.local`, `session.json`, and
  `bootstrap-prompt.md`, plus the `/start-here-prompts` mount. `BOOTSTRAP_DIR`
  semantics (`/project/bootstrap`) MUST remain valid.
- **R5.2** Reading the registry MUST remain via the restricted parser (never
  `source`/`eval`), unchanged by this relocation.

### R6 — Host-side testability preserved

- **R6.1** The script MUST remain executable host-side for the existing test
  harness, which runs a patched copy from the repo root and overrides
  `BOOTSTRAP_DIR` via `sed` (see `lifecycle/tests/ai-new-13-tests.md` and
  [[start-here-lib-host-execution]]). The relocation MUST NOT reintroduce a
  hard mount dependency that blocks host execution before flag parsing.

### R7 — Installation footprint

- **R7.1** The framework install set MUST continue to ship `start-here.sh`
  (`install.sh` managed set, `install.sh:93,136`) as the single canonical
  source of the script. No additional user-facing copy is introduced.

## Acceptance Criteria

- **AC1.** After a normal install and launch, inspecting the host project tree
  shows **no** executable `start-here.sh` under `bootstrap/home/` (or anywhere
  under `/project` that the user can write).
- **AC2.** The bootstrap container starts successfully using the relocated
  entrypoint and completes the same flow as before (runtime resolution, auth
  gate, prompt copy, agent launch) for a representative agent registry.
- **AC3.** The in-container entrypoint is **not writable** by the container
  user: an attempt to modify it from inside the container fails (read-only mount
  or root-owned in-image path).
- **AC4.** Editing or deleting the framework `start-here.sh` and relaunching
  results in the launch using the **updated** framework version (no stale copy
  served).
- **AC5.** `start-here.sh -h`/`--help` still prints usage and exits 0, and the
  printed invocation/"restart with" path matches the new protected location.
- **AC6.** `--resume` and `--shell-on-exit` behave exactly as before.
- **AC7.** The host-side test suite that executes a patched `start-here.sh` from
  the repo root continues to pass (no regression of the
  [[start-here-lib-host-execution]] class of failure).
- **AC8.** `agent.env`, `agent.env.local`, `session.json`, and the bootstrap
  prompt are still read correctly from `/project/bootstrap`.

## Open Questions

1. **Delivery mechanism (R2.a vs R2.b).** Read-only mount keeps the script
   outside the image and trivially current; baked-into-image fully removes any
   host bind for the script but adds cache-busting complexity. Which does the
   project prefer? (The existing `/start-here-prompts` / `/start-here-lib`
   convention favours R2.a for consistency.)
2. **Pre-existing project copies.** Should the launcher actively remove a
   stale `${project_root}/bootstrap/home/start-here.sh` left by older versions,
   or simply stop creating/using it and leave existing files untouched?
3. **`HOME` overlap.** The container `HOME` is `/project/bootstrap/home`, which
   is user-facing. Does relocating only the script suffice, or is there a
   related concern that the home directory itself is in the project tree (out of
   scope here, but worth flagging)?
4. **Mount path name.** If R2.a is chosen, what is the canonical container path
   (e.g. `/start-here/start-here.sh` or reuse an existing namespace)?
5. **Permissions model.** Is read-only mounting sufficient, or is an explicit
   root-owned/non-`keep-id` ownership required given `--userns=keep-id`?
