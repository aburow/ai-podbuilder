---
title: Relocate start-here.sh out of the user-accessible host project tree
type: requirement
status: approved
lineage: start-here-sh-exposed-location
parent: lifecycle/defects/start-here-sh-exposed-location.md
assignees:
    - role: product-owner
      who: agent
---

# Relocate start-here.sh out of the user-accessible host project tree

## Problem

`start-here.sh` is the framework-owned entrypoint for the disposable bootstrap
container. It is internal tooling — it parses the pinned agent registry, runs
the auth gate, resolves the runtime, copies the bootstrap prompt, and launches
the selected agent. It is **not** intended to be read, edited, or run directly
by the user on the host.

Today the script is staged inside the user's project tree and delivered to the
container through the project bind mount:

- `refresh_bootstrap_entrypoint()` (`lib/scaffold.sh:132`) copies the framework
  copy from `${AI_PODMAN_JAILS_DIR}/start-here.sh` to
  `${project_root}/bootstrap/home/start-here.sh` and `chmod +x` it before every
  launch (the refresh exists so resumed projects pick up launcher/argument
  fixes — `lib/scaffold.sh:129-131`).
- `launch_bootstrap()` (`lib/launch.sh`) bind-mounts the whole project root at
  `/project` (`--volume "${_proj}:/project:z"`), sets
  `HOME=/project/bootstrap/home`, and invokes
  `/project/bootstrap/home/start-here.sh` as the entrypoint
  (`lib/launch.sh:53`). The launch comment notes the script is "delivered via
  the /project mount … no root bind mount" (`lib/launch.sh:43-44`).

Because `bootstrap/home/` lives inside the user's project directory — and is
simultaneously the container `HOME` — the script sits in a host-visible,
host-writable, and container-writable location. This exposes it to:

- **Tampering / corruption** — a host user, or an agent writing into its own
  `$HOME`, can edit or delete the entrypoint, breaking subsequent launches or
  silently altering the auth gate that protects credentials.
- **Confusion** — the file looks like a project artifact the user is meant to
  manage, when it is framework internals that are overwritten on every launch.

There is existing precedent for the correct pattern: other internal resources
are delivered via dedicated, read-only, non-`/project` mounts — the bootstrap
prompts at `/start-here-prompts` (`lib/launch.sh:46-49`) and, historically,
shared libraries at `/start-here-lib` (see [[start-here-lib-host-execution]]).
The entrypoint script is the one internal resource still routed through the
user-facing project tree.

## Goals / Non-goals

**Goals**

- Deliver `start-here.sh` to the bootstrap container from a location that is
  **not** part of the user-facing/user-writable host project tree.
- Make the in-container entrypoint **non-modifiable** by the container user and
  by the host user during normal operation.
- Preserve all current behaviour: flag handling (`--agent`, `--resume`,
  `--shell-on-exit`, `-h`/`--help`), the auth gate, runtime resolution, prompt
  copying, and reading of registry/state from `/project/bootstrap`
  (`agent.env`, `agent.env.local`, `session.json`, `bootstrap-prompt.md`).
- Guarantee each launch runs the **current framework version** of the script —
  the property `refresh_bootstrap_entrypoint()` exists to provide — with no
  stale per-project copy persisting or being served.
- Keep the script host-side testable, since the existing test harness executes
  a patched copy from the repo root with an overridden `BOOTSTRAP_DIR` (see
  `lifecycle/tests/ai-new-13-tests.md` and [[start-here-lib-host-execution]]).

**Non-goals**

- Relocating or hardening the `/project/bootstrap` **data** files (`agent.env`,
  `agent.env.local`, `session.json`, generated artifacts). Those legitimately
  live under the project; this change concerns the executable script only.
- Changing the container security posture (no Podman socket, `--network host`,
  `--userns=keep-id`, no `--privileged`/`--device /dev/fuse`).
- Redesigning `start-here.sh`'s internal logic beyond what the relocation
  requires (path self-references and entrypoint resolution).
- Changing where the framework itself is installed (the `install.sh` managed
  set — `install.sh:93,136`).

## Detailed Requirements

### R1 — Remove the script from the user-facing project tree

- **R1.1** `start-here.sh` MUST NOT be written into, or executed from,
  `${project_root}/bootstrap/home/` (or any other path under the bind-mounted
  `/project` tree that is user-visible/user-writable).
- **R1.2** `refresh_bootstrap_entrypoint()` (`lib/scaffold.sh:132`) MUST no
  longer copy the script into the project tree. The new flow MUST NOT depend on
  a per-project copy and SHOULD NOT leave an executable copy there.

### R2 — Deliver the script from a protected, internal location

The script MUST reach the container through one of the following mechanisms
(final choice deferred to planning; both must satisfy R3–R5):

- **R2.a (read-only mount).** Bind-mount the framework copy
  (`${AI_PODMAN_JAILS_DIR}/start-here.sh`) **read-only** to a dedicated,
  non-`/project` container path — consistent with the `/start-here-prompts` and
  prior `/start-here-lib` convention — and use that path as the entrypoint. The
  mount MUST be read-only so the container user cannot modify it.
- **R2.b (baked into image).** `COPY` the script into the bootstrap image at a
  protected, root-owned path (e.g. under `/usr/local/lib` or `/opt`) at build
  time and invoke it from there. If chosen, image build/caching MUST be
  invalidated when the framework `start-here.sh` content changes (see R4).

### R3 — Entrypoint resolution and invocation

- **R3.1** `launch_bootstrap()` MUST invoke the script from its new protected
  location, not from `/project/bootstrap/home/start-here.sh`
  (`lib/launch.sh:53`).
- **R3.2** The script's self-references in usage/help and operator-facing
  messages MUST be updated to the new invocation path, so printed guidance is
  correct — specifically the usage banner (`start-here.sh:15`) and the "restart
  the session with" hint (`start-here.sh:348`), plus the placement comment
  (`start-here.sh:3`).
- **R3.3** All current entrypoint arguments (`--resume`, `--shell-on-exit`, and
  the implicit default run constructed in `launch_bootstrap()`) MUST continue
  to be passed through unchanged.

### R4 — Always run the current framework version

- **R4.1** Each launch MUST execute the framework's current `start-here.sh`, not
  a stale per-project or cached copy. For R2.a this is inherent (the live
  framework file is mounted); for R2.b the image build MUST rebuild or
  cache-bust when the script content changes.

### R5 — Data access preserved

- **R5.1** The relocated script MUST retain read access to `/project/bootstrap`
  data: `agent.env`, `agent.env.local`, `session.json`, and
  `bootstrap-prompt.md`, plus the `/start-here-prompts` mount. The
  `BOOTSTRAP_DIR=/project/bootstrap` semantics (`start-here.sh:7`) MUST remain
  valid.
- **R5.2** Reading the registry MUST remain via the restricted parser (never
  `source`/`eval`), unchanged by this relocation.

### R6 — Host-side testability preserved

- **R6.1** The script MUST remain executable host-side for the existing test
  harness, which runs a patched copy from the repo root and overrides
  `BOOTSTRAP_DIR` via `sed` (see `lifecycle/tests/ai-new-13-tests.md` and
  [[start-here-lib-host-execution]]). The relocation MUST NOT introduce a hard
  mount/path dependency that blocks host execution before flag parsing.

### R7 — Installation footprint

- **R7.1** The framework install set MUST continue to ship `start-here.sh` as
  the single canonical source (`install.sh:93,136`). No additional user-facing
  copy may be introduced.

## Acceptance Criteria

- **AC1.** After a normal install and launch, inspecting the host project tree
  shows **no** executable `start-here.sh` under `bootstrap/home/` (or anywhere
  under `/project` the user can write).
- **AC2.** The bootstrap container starts successfully using the relocated
  entrypoint and completes the same flow as before (runtime resolution, auth
  gate, prompt copy, agent launch) for a representative agent registry.
- **AC3.** The in-container entrypoint is **not writable** by the container
  user: an attempt to modify it from inside the container fails (read-only
  mount or root-owned in-image path).
- **AC4.** Editing the framework `start-here.sh` and relaunching results in the
  launch using the **updated** version — no stale copy is served.
- **AC5.** `start-here.sh -h`/`--help` still prints usage and exits 0, and the
  printed invocation/"restart with" path matches the new protected location.
- **AC6.** `--resume` and `--shell-on-exit` behave exactly as before.
- **AC7.** The host-side test suite that executes a patched `start-here.sh` from
  the repo root continues to pass (no regression of the
  [[start-here-lib-host-execution]] class of failure).
- **AC8.** `agent.env`, `agent.env.local`, `session.json`, and the bootstrap
  prompt are still read correctly from `/project/bootstrap`.

## Answers

1. **Delivery mechanism (R2.a vs R2.b).** A read-only mount keeps the script
   outside the image and trivially current; baking it into the image removes
   any host bind for the script but adds cache-busting complexity. The existing
   `/start-here-prompts` / `/start-here-lib` convention favours R2.a — is that
   the project's preference?

Answer: Yes
   
2. **Pre-existing project copies.** Should the launcher actively remove a stale
   `${project_root}/bootstrap/home/start-here.sh` left by older versions, or
   simply stop creating/using it and leave existing files untouched?

Answer: Leave it untouched

3. **`HOME` overlap.** The container `HOME` is `/project/bootstrap/home`, which
   is itself user-facing. Does relocating only the script suffice, or is the
   home-in-project-tree concern worth a follow-up (out of scope here)?

Answer: this is fine, the concern was with it being available directly in the root of the tool on the HOST where users have tampered out of misunderstanding.

4. **Mount path name.** If R2.a is chosen, what is the canonical container path (e.g. `/start-here/start-here.sh`, or reuse an existing namespace)?

Answer: This is not an in container issue

5. **Permissions model.** Given `--userns=keep-id`, is a read-only mount alone sufficient, or is an explicit root-owned / non-`keep-id` ownership required to fully prevent in-container modification?

Answer: This is a HOST side issue with users changing a file that is visible in the root directory of the app and says "start-here.sh"... this is a human behaviour issue we are resolving in the HOST tool/directory structure.
