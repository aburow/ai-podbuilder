---
title: Fix ai-new bootstrap container setup — start-here.sh location & permissions, and agent installation
type: requirement
status: clarifying
lineage: ai-new-container-setup-failures
parent: lifecycle/defects/ai-new-container-setup-failures.md
assignees:
    - role: product-owner
      who: agent
---

# Fix ai-new Bootstrap Container Setup

## Problem

The `ai-new` bootstrap container is unusable out of the box because of three
setup failures reported in the parent defect. Investigation of the build and
launch chain confirms all three and locates their root causes:

1. **`start-here.sh` is at the filesystem root, not the home directory.**
   The script is not baked into the image — it is bind-mounted at launch by
   `lib/launch.sh:41` as `--volume "${_start_here}:/start-here.sh:ro,z"`, i.e.
   onto `/start-here.sh`. The container's `HOME` is `/project/bootstrap/home`
   (`lib/launch.sh:34`, `lib/bootstrap_image.sh:38`) and `WORKDIR` is
   `/project`, so the entrypoint script does not live anywhere the user would
   naturally look or invoke it from. Note: the prior requirement
   `lifecycle/requirements/ai-new-3.md` (R4.1) *specifies* `/start-here.sh` at
   root, so there is a spec conflict that this requirement must resolve, not
   just a code bug.

2. **`start-here.sh` is not executable.** The host file
   `/workspace/podman-plugin/start-here.sh` has mode `-rw-r--r--` (no execute
   bit), and the bind mount is read-only (`:ro,z`), so the in-container file
   inherits the non-executable host mode. The container is launched into
   `/bin/bash` (`lib/launch.sh:52`), meaning the user must manually run
   `bash /start-here.sh`; running `./start-here.sh` fails with permission
   denied. There is no `chmod +x` anywhere in the build or launch path.

3. **No agent (codex / codex / gemini) is installed.** The generated bootstrap
   `Containerfile` (`lib/bootstrap_image.sh:18-40`) installs only base tooling
   (`bash coreutils curl git nodejs npm python3 python3-pip pipx …`) and no
   agent. Agent install machinery exists — `run_install_adapter()` in
   `lib/adapter.sh` knows how to `npm install -g` the packages declared in
   `config/agents.d/{codex,codex,gemini}.env` — but it is **dead code**: it is
   never called from `bin/` or `lib/` or `start-here.sh`. `start-here.sh`'s
   `_validate_runtime` (lines ~200-255) only *checks* for the agent command and
   exits non-zero when absent; it never installs it. Net effect: the pinned
   agent command is never present, and the container cannot perform its core
   function.

## Goals / Non-goals

**Goals**

- Place `start-here.sh` in the container user's home directory and make it
  executable, so the user can launch it directly.
- Ensure the pinned agent (per the registry in `config/agents.d/`) is actually
  installed and resolvable on `$PATH` inside the bootstrap container.
- Reconcile the `start-here.sh` location with the conflicting specification in
  `lifecycle/requirements/ai-new-3.md` (R4.1) so the codebase and requirements
  agree.
- Keep the fix consistent with the existing rootless / `--userns=keep-id`
  launch model.

**Non-goals**

- Redesigning the bootstrap launch flow, the agent registry format, or the
  durable project image (`templates/Containerfile.durable.tmpl`).
- Adding new agents beyond the three already defined in `config/agents.d/`.
- Changing how API keys / `agent.env` / `agent.env.local` are parsed or loaded.

## Detailed Requirements

### R1 — `start-here.sh` placed in the home directory

- **R1.1** `start-here.sh` MUST be available inside the bootstrap container at a
  path within the container user's home directory (`HOME=/project/bootstrap/home`),
  e.g. `/project/bootstrap/home/start-here.sh`, rather than at `/start-here.sh`.
- **R1.2** The chosen location MUST be consistent whether the script is
  bind-mounted (current approach in `lib/launch.sh`) or copied; if bind-mounting
  is retained, the `--volume` target in `lib/launch.sh:41` MUST be updated to the
  home-directory path.
- **R1.3** Any companion mounts that assume the root location (e.g. the prompts
  mount at `/start-here-prompts`, `lib/launch.sh:44-46`) and any path references
  inside `start-here.sh` itself MUST be updated to remain consistent with the new
  location.
- **R1.4** The conflicting specification in `lifecycle/requirements/ai-new-3.md`
  (R4.1, which states `/start-here.sh` at root) MUST be reconciled — either by
  updating that requirement or by an explicit note recording the supersession —
  so requirements and implementation no longer disagree.

### R2 — `start-here.sh` is executable

- **R2.1** Inside the running container, `start-here.sh` MUST have the execute
  bit set so it can be invoked as `./start-here.sh` (or by absolute path) without
  a `bash` prefix.
- **R2.2** The execute bit MUST NOT depend on the host file's mode. Because the
  current bind mount is read-only and inherits host permissions, the solution
  MUST guarantee the executable bit regardless of host file mode — e.g. by
  setting `+x` on the host file as part of the build/release, by copying the
  script into the image with `chmod +x`, or by another mechanism that does not
  rely on the user's host checkout permissions.
- **R2.3** If the container continues to launch into `/bin/bash`
  (`lib/launch.sh:52`), the means of running `start-here.sh` (path and how the
  user is told to invoke it) MUST be documented in the bootstrap prompt /
  start-here output.

### R3 — An agent is installed in the bootstrap container

- **R3.1** At least the pinned agent — the one selected via `--agent` and
  recorded in `bootstrap/agent.env` — MUST be installed and resolvable on
  `$PATH` inside the bootstrap container before `start-here.sh` reaches its
  `_validate_runtime` check.
- **R3.2** Installation MUST use the existing registry metadata in
  `config/agents.d/{codex,codex,gemini}.env`
  (`AGENT_INSTALL_ADAPTER`, `AGENT_INSTALL_PACKAGE`, command, args) rather than
  hard-coding package names.
- **R3.3** The existing `run_install_adapter()` in `lib/adapter.sh` (which
  already handles `npm-global`, `pipx`, `dnf-package`, and the no-op
  `preinstalled` / `manual` cases) MUST be wired into the live build/launch path
  so it is actually invoked, or an equivalent install step MUST be added to the
  generated bootstrap `Containerfile` (`lib/bootstrap_image.sh`).
- **R3.4** For adapters that cannot be fully automated (e.g. gemini's `manual`
  adapter), the behaviour MUST be explicit: either install successfully or
  produce a clear, actionable message — `start-here.sh` MUST NOT silently leave
  the user with a missing-command error and no guidance.
- **R3.5** `_validate_runtime` in `start-here.sh` SHOULD continue to verify
  presence after install, so a failed install surfaces as a clear error rather
  than a confusing downstream failure.

### R4 — Verification hooks

- **R4.1** The fix SHOULD be covered by an integration test (under `tests/`)
  that builds and runs the bootstrap container and asserts: (a) `start-here.sh`
  exists under `$HOME`, (b) it is executable, and (c) the pinned agent command
  resolves on `$PATH`.

## Acceptance Criteria

- **AC1** In a freshly built and launched bootstrap container,
  `find / -name start-here.sh` returns a path under `$HOME`
  (`/project/bootstrap/home/…`) and **not** `/start-here.sh`.
- **AC2** `ls -l "$HOME/start-here.sh"` (or its resolved path) shows the execute
  bit set, and invoking the script directly (`"$HOME/start-here.sh"`) runs
  without a permission-denied error and without needing a `bash` prefix.
- **AC3** For each supported agent selected via `--agent`, the corresponding
  command (`codex` / `codex` / `gemini`) is found by `command -v` / `which`
  inside the container, and `start-here.sh`'s `_validate_runtime` passes.
- **AC4** `lifecycle/requirements/ai-new-3.md` R4.1 (and any other artifact
  asserting the root location) is updated or annotated so it no longer
  contradicts the home-directory placement.
- **AC5** The build/launch path no longer contains dead install code: the agent
  install step is reachable and exercised on a normal `ai-new` run.
- **AC6** (If implemented) the integration test from R4.1 passes in CI.

## Resolved Questions

1. **Bind-mount vs. bake-in.** Should `start-here.sh` remain bind-mounted (and
   we relocate the mount target + force `+x` on the host file) or be `COPY`ed
   into the image with `chmod +x`? Baking in decouples the in-container mode
   from the host checkout but loses live-edit convenience during development.

copy the file into the image
   
2. **Where should the agent install run** — at image build time (in the
   generated bootstrap `Containerfile`, giving a cached, ready image) or at
   launch time (more flexible per selected agent, but slower every run)?

launch time as it will install the latest version

3. **gemini `manual` adapter** — what is the intended install path for gemini,
   given its adapter is `manual`? Is leaving it as a documented manual step
   acceptable, or must R3 fully automate it?

the "manual" status is a nonsense add it as we would codex or codex at launch time 
   
4. **Exact home path.** Is `/project/bootstrap/home/start-here.sh` the desired
   location, or should it sit at a conventional `~/start-here.sh` that the
   defect's examples (`/root/start-here.sh`, `/home/<user>/start-here.sh`)
   imply? This depends on the `--userns=keep-id` UID mapping in effect.

The ai-new container first opens in /project within the container. The same directory contains the following:

```
bash-5.3$ ls -la
total 8
drwxr-xr-x. 1 mrnobody mrnobody 104 Jun 23 04:46 .
dr-xr-xr-x. 1 root     root      88 Jun 23 04:46 ..
-rw-r--r--. 1 mrnobody mrnobody 167 Jun 23 04:46 README.md
drwxr-xr-x. 1 mrnobody mrnobody  94 Jun 23 04:46 bootstrap
drwxr-xr-x. 1 mrnobody mrnobody   0 Jun 23 04:46 image
drwxr-xr-x. 1 mrnobody mrnobody   0 Jun 23 04:46 launchers
-rw-r--r--. 1 mrnobody mrnobody  72 Jun 23 04:46 profile.env
drwxr-xr-x. 1 mrnobody mrnobody   0 Jun 23 04:46 workspace
bash-5.3$ pwd
/project
```
   
8. **Should all registry agents be pre-installed**, or only the single pinned
   agent for the current run? Pre-installing all three increases image size but
   removes per-run install latency.

Just the requested agent. codex, codex, or gemini at this stage
