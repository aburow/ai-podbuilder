---
title: AI Agent Podman Sandbox Framework — v1 Requirement
type: requirement
status: in-development
lineage: ai-agent-podman-sandbox
created: "2026-06-22T00:00:00+10:00"
priority: normal
parent: lifecycle/requirements/ai-agent-podman-sandbox-4.md
assignees:
    - role: analyst
      who: agent
    - role: product-owner
      who: agent
---

# AI Agent Podman Sandbox Framework — v1 Requirement

This artifact finalises the consolidated requirement in
`ai-agent-podman-sandbox-4.md`. All clarifying rounds are closed: the parent's
ten original questions (OQ1–OQ10) were resolved into the consolidated cut, and
the four follow-up questions surfaced during consolidation (OQ-A image-staleness
tracking, OQ-B interactive detection, OQ-C builder persistence, OQ-D teardown
ergonomics) are now resolved and folded into normative requirements below. The
**Open Questions** section is therefore empty for v1.

The scope is unchanged: a safe, reusable replacement for the current
hand-written per-project launch scripts. Post-v1 vision is preserved verbatim
under **Deferred Requirements** so the lineage stays complete without enlarging
the v1 release gate.

## Problem

AI coding agents (Codex, Codex, Aider, OpenCode) are run against project
workspaces on a Bazzite/Fedora desktop using rootless Podman. Today each project
is launched by its own hand-written script — every script a copy of the same
sound pattern (rootless, `--userns=keep-id`, `--security-opt no-new-privileges`,
a narrow workspace-only mount, a fake in-container `$HOME`). Because the pattern
is duplicated per project, the safety policy has **drifted**: scripts hardcode
slightly different values, the privileged builder path is not cleanly separated
from the normal path, and there is no single authoritative definition of "what
is safe by default." Adding a project means cloning and editing several scripts.
There is no inventory, no health check, no desktop-integration story, and no
clean way to package the approach for reuse on another machine.

The core need driving v1: **the user must be able to stand up an isolated,
persistent dev container with the specific tools and libraries a project
requires, and use it with whatever agent they choose** — without per-project
script drift and without exposing the host.

## Goals / Non-goals

### Goals (v1)

- Replace per-project launch scripts with a small set of **generic commands**
  (`ai-build`, `ai-launch`, `ai-terminal`, `ai-list`) that source per-project
  **profile files** (`profiles/<name>.env`).
- Define the normal-mode safety policy in **one auditable place** so every
  normal-mode sandbox launches identically; eliminate drift.
- Make the higher-risk builder path **explicit and opt-in**: privileged builder
  mode only via `ai-launch <profile> builder`, never by default, and
  **ephemeral** (`--rm`) so an elevated container never lingers.
- Provide **persistent, named** normal-mode sandbox containers that survive
  exit, so ongoing dev and build state is retained and any compromise stays
  contained and inspectable.
- Keep each project **isolated** under `$CODEX_JAILS_DIR/<name>-workspace` with
  its own in-container `$HOME` under `/workspace`, mounting no host secrets, SSH,
  config, or the Podman/Docker socket in normal mode.
- Provide framework-managed teardown via `ai-launch <profile> --reset` and
  `--recreate`, so users do not hand-run raw Podman against safety-managed
  containers.
- **Preserve muscle memory**: retain current script names as thin compatibility
  wrappers delegating to the new commands.
- Include basic **network modes** (default outbound + `NETWORK_MODE=none`),
  optional per-profile **secret env files**, a documented **in-sandbox SSH-key
  strategy**, and **manual desktop / Podman Desktop launcher wrappers**.

### Non-goals (v1)

- Not maximum container security or a hardened multi-tenant boundary; the target
  is a practical dev sandbox **materially safer than running agents on the bare
  host**.
- No Kubernetes, no orchestration, no daemon beyond rootless Podman.
  Implementation stays POSIX/Bash with `set -euo pipefail`.
- Not a hosted/CI/remote service; scope is a single user's local desktop.
- Not responsible for agent image contents beyond building from a
  profile-declared image directory (Containerfiles are project inputs).
- Rootful Podman and non-Fedora/Bazzite hosts are out of scope for the first
  release (Bazzite/Fedora + rootless Podman is the supported target).

### Deferred (post-v1)

Captured in **Deferred Requirements** and not part of the v1 acceptance target:
`ai-doctor` health check (and its `--cleanup` teardown flow), `ai-new` project
generator, named policy levels, automatic `.desktop` entry generation, full
packaging/repo installer, the request-driven agent-delegated environment builder
(R16), and nested rootless Podman child-container launching.

## Detailed Requirements

### R1. Layout and installation

- **R1.1** Base directory defaults to `~/codex-jails`, overridable via
  `CODEX_JAILS_DIR`. All generated paths derive from `$HOME` /
  `$CODEX_JAILS_DIR`; no username is hardcoded.
- **R1.2** The base directory contains `bin/` (generic commands), `profiles/`
  (per-project `.env`), and `launchers/` (desktop / Podman-Desktop wrappers).
  Project workspaces and image dirs sit alongside as `<name>-workspace/` and
  `<name>-image/`.
- **R1.3** `bin/` is added to `PATH`; docs describe persisting this in the shell
  profile.

### R2. Profiles

- **R2.1** Each sandbox is described by exactly one sourced Bash fragment
  `profiles/<name>.env`.
- **R2.2** Required fields: `PROFILE_NAME`, `CONTAINER_NAME`, `IMAGE_NAME`,
  `IMAGE_DIR`, `WORKSPACE`, `CONTAINER_HOME`, `BASHRC`, `WORKDIR`, `BUILD_ARGS`.
- **R2.3** Optional arrays/values: `EXTRA_ENV`, `EXTRA_VOLUMES`,
  `EXTRA_DEVICES`, `EXTRA_HOSTS`, `EXTRA_RUN_ARGS`, `POST_BUILD_CHECK`,
  `PNPM_HOME`, `HISTFILE`.
- **R2.4** Optional `ENV_FILE` (secrets), `NETWORK_MODE`, and `SELINUX_MODE`
  (see R5.6).
- **R2.5** Profiles MUST NOT contain secrets; secret material lives in
  `ENV_FILE`-referenced files (R7).
- **R2.6** A missing or malformed profile (absent file, missing required field)
  fails with a clear, actionable message and non-zero exit.

### R3. `ai-build`

- **R3.1** `ai-build <profile>` sources the profile and runs `podman build` in
  `IMAGE_DIR` using `BUILD_ARGS`.
- **R3.2** On success, runs `POST_BUILD_CHECK` inside the new image to report
  installed tool/library versions (the "requested tools are present"
  confirmation).
- **R3.3** Errors (profile not found, image dir not found, build failure) exit
  non-zero with a clear message.
- **R3.4** `-h` / `--help` / no-arg prints usage.
- **R3.5** **`ai-build` never silently mutates or removes an existing persistent
  container.** It builds or rebuilds the image only and does not touch existing
  containers. Durable dependency changes are expected to be promoted into the
  profile's image definition (Containerfile or include fragments), not left only
  in the persistent workspace. Staleness is detected at launch time by comparing
  live image IDs (R4.9), so `ai-build` keeps no separate framework-maintained
  image-state file in v1.

### R4. `ai-launch`, launch modes, and persistence

- **R4.1** `ai-launch <profile> [mode]` sources the profile, ensures the
  workspace, container-home, pnpm, and `.bash_history` paths exist, then
  starts/attaches the sandbox container.
- **R4.2** **Persistence.** Normal-mode containers are **named and persistent**,
  not `--rm`. If a container for the profile already exists, `ai-launch` reuses
  it (start + attach / `exec`); otherwise it is created. Workspace state and the
  in-container `$HOME` persist across exits, and the container remains
  inspectable after exit. **Routine exit never destroys the container.**
- **R4.3** **Normal mode** (default `shell`/`bash`) applies the standard safety
  policy (R5): `-it`, `--userns=keep-id`, `--group-add keep-groups`,
  `--security-opt no-new-privileges`, SELinux per R5.6, `-e HOME=$CONTAINER_HOME`,
  the single workspace mount `-v $WORKSPACE:/workspace:Z`, and `-w $WORKDIR`.
- **R4.4** Supported modes: `shell`/`bash` (default), `codex`, `codex`, and
  `builder`. The mode set is extensible to additional agents (`aider`,
  `opencode`, `ollama-shell`, …) without changing the safety core.
- **R4.5** **Builder mode** is the only privileged path: `--privileged`, a
  distinct `-builder` container name, reachable only by explicitly passing
  `builder`, never default.
- **R4.6** Profile `EXTRA_*` arrays are appended in normal mode (hosts, devices,
  volumes, env, run args).
- **R4.7** An unknown mode exits non-zero and prints usage.
- **R4.8** Before launching/attaching, the command echoes a summary (profile,
  container, image, workspace, container `$HOME`, mode, network, SELinux mode,
  and whether it is reusing an existing container) so the active policy is
  visible.
- **R4.9** **Stale-image reconciliation.** Staleness is detected by comparing the
  existing persistent container's configured image ID with the current local
  image ID for `IMAGE_NAME` at launch time:
  - existing container image ID:
    `podman inspect --format '{{.Image}}' "$CONTAINER_NAME"`
  - current local image ID:
    `podman image inspect --format '{{.Id}}' "$IMAGE_NAME"`

  If both exist and differ, the container is considered stale. No separate
  `$CODEX_JAILS_DIR/state/<profile>.image` file is required in v1; launch
  correctness MUST NOT depend on framework-maintained image state when Podman
  already records the container's source image.

  When stale, an **interactive** `ai-launch` warns and offers three explicit
  choices: (1) continue using the existing container; (2) recreate from the new
  image while preserving the workspace-mounted state; (3) cancel and inspect
  manually. The **non-interactive default is warn-and-continue** — never
  auto-recreate.
- **R4.10** **Interactive detection and explicit flags.** Interactive mode is
  detected when both stdin and stdout are terminals (`[[ -t 0 && -t 1 ]]`).
  `ai-launch` also supports explicit control:
  - `--yes` / `--non-interactive`: never prompt; on detected staleness, warn and
    **continue** with the existing container. `--yes` MUST NOT mean "recreate" —
    the safe default is continue, not mutate/remove.
  - `--recreate`: remove and recreate the persistent container from the current
    image, preserving the workspace and container-home.
  - `--no-recreate`: explicitly continue using the existing container.

  Desktop / Podman Desktop launcher wrappers SHOULD default to
  `--non-interactive` so launchers never hang behind a hidden prompt.
- **R4.11** **Framework-managed teardown (`--reset`).**
  `ai-launch <profile> --reset` removes the persistent normal-mode container for
  that profile and recreates it from the current image (on next launch or
  immediately, per implementation choice). It MUST NOT delete the workspace,
  container-home directory, profile, image directory, or secret env file. If the
  container is running, `--reset` stops it first — after confirmation in
  interactive mode; in non-interactive mode reset requires an explicit
  `--yes --reset` combination. Raw Podman teardown commands MAY still be
  documented as an escape hatch, but the canonical v1 teardown path is
  framework-managed.
- **R4.12** **Builder-mode persistence.** Privileged builder containers are
  **ephemeral** in v1: launched with the distinct `-builder` name and `--rm` by
  default so an elevated container does not linger after exit. Build performance
  is preserved through explicit mounted cache/workspace directories, not by
  keeping the privileged container alive. Any future long-running/resumable
  builder must be a separate explicit mode (e.g. `builder-persistent`) with
  visible warnings.

### R5. Safety policy (normal mode)

- **R5.1** Normal-mode containers MUST use `--userns=keep-id`,
  `--group-add keep-groups`, and `--security-opt no-new-privileges`.
- **R5.2** Normal mode MUST mount only the project workspace
  (`-v $WORKSPACE:/workspace:Z`). It MUST NOT mount any of: host `$HOME`,
  `~/.ssh`, `~/.gnupg`, `~/.config`, `/`, the Docker socket, or the Podman
  socket.
- **R5.3** `--privileged` is forbidden in normal mode; permitted only in builder
  mode (R4.5).
- **R5.4** The container's `$HOME` is a directory inside the mounted workspace
  (`CONTAINER_HOME` under `/workspace`) — writable, persistent, contained.
- **R5.5** The rationale for relaxing SELinux labelling (labelling friction with
  mounted dev workspaces on Bazzite) MUST be documented; the workspace mount
  stays explicit and narrow.
- **R5.6** **SELinux mode.** `--security-opt label=disable` remains the default
  for friction-free dev, but the framework offers a stricter `:Z`-only variant: a
  per-profile `SELINUX_MODE` (e.g. `disable` | `enforce`) selects between
  `label=disable` and relying on the `:Z` relabel alone. The stricter option is
  documented and presented to the user as an available choice, not hidden.

### R6. Network policy

- **R6.1** `ai-launch` supports `NETWORK_MODE` (default `slirp4netns`) passed as
  `--network`. **Network is required by default** — normal sandboxes have
  outbound connectivity.
- **R6.2** `NETWORK_MODE=none` produces a fully offline container, intended for
  reviewing local code without giving the agent network access.
- **R6.3** Network mode is overridable per-invocation (env var) and settable per
  profile.

### R7. Secrets

- **R7.1** Default mounts no host secrets.
- **R7.2** If a profile defines `ENV_FILE`: when the file exists, add
  `--env-file <file>`; when defined but missing, **warn and continue** — do not
  hard-fail.
- **R7.3** Secret files are per-profile, expected mode `600`, and never committed
  to Git.

### R8. SSH strategy

- **R8.1** Host `~/.ssh` is never mounted by default.
- **R8.2** Docs describe generating a dedicated in-sandbox SSH key (e.g.
  `ed25519`) so the agent gets scoped Git access without exposing the host
  identity.

### R9. `ai-terminal`

- **R9.1** `ai-terminal <profile>` attaches an additional interactive shell to
  the running container for that profile via `podman exec -it`.
- **R9.2** If the container is not running, exits non-zero with a clear message
  (and may hint at `ai-launch` to start/resume the persistent container).

### R10. `ai-list`

- **R10.1** `ai-list` enumerates `profiles/*.env` and prints, per profile, name,
  image name, and workspace path in aligned columns. It SHOULD also indicate
  whether a persistent container currently exists and its state
  (running/stopped).
- **R10.2** A missing profile directory exits non-zero with a clear message.

### R11. Compatibility wrappers

- **R11.1** Existing script names (`launch-esp32-workspace`,
  `short-launch-esp32-workspace`, `launch-uxplay-workspace`,
  `launch-uxplay-builder`, `extra-terminal`, `update-codex-esp32-image`,
  `update-codex-uxplay-image`, and known variants) are retained as thin wrappers
  that `exec` the corresponding generic command with fixed arguments.
- **R11.2** Wrappers produce behaviour equivalent to the originals — adjusted
  only for the persistence change (R4.2), which they inherit.

### R12. Manual desktop / Podman Desktop integration (v1 subset)

- **R12.1** `launchers/<name>-<mode>` thin scripts call `ai-launch <name> <mode>`
  and are the recommended entry points for desktop menus and Podman Desktop.
- **R12.2** `.desktop` entries under `~/.local/share/applications/` launch the
  `launchers/` scripts in a terminal; docs cover KDE (`konsole`) and GNOME
  (`kgx`). Hand-authored entries derive paths from `$HOME` / `$CODEX_JAILS_DIR` —
  **no hardcoded `/var/home/<user>` paths**.
- **R12.3** Persistent containers started this way are visible and manageable in
  Podman Desktop (start/stop/inspect/remove).
- **R12.4** v1 ships the launcher wrappers and documented `.desktop` examples
  **manually**; automatic generation (`ai-desktop-install`) is deferred
  (Deferred D4).

### R13. Non-functional

- **R13.1** Commands are POSIX/Bash, `set -euo pipefail`, with no daemon beyond
  rootless Podman.
- **R13.2** All commands provide `-h` / `--help` and clear, non-zero-exit error
  messages.
- **R13.3** Targets Bazzite/Fedora with rootless Podman and Podman Desktop.
- **R13.4** **Framework self-hosting, not nested container execution.** The
  framework repository MUST be usable from inside an ordinary sandbox workspace,
  for example `$CODEX_JAILS_DIR/podman-plugin-workspace`, so the user can develop
  and maintain the framework without exposing the full host environment. This
  requirement only means the framework files can be edited, generated, linted,
  and reviewed from inside that sandbox; the framework MUST NOT assume hardcoded
  host paths, hardcoded usernames, or direct bare-host execution. It does not
  imply that the sandbox can launch child containers. Nested rootless Podman,
  host Podman socket access, and child-sandbox launching are out of scope for v1
  and tracked separately as Deferred D6/D7.

## Deferred Requirements (post-v1)

These remain part of the product vision and are recorded so the lineage is
complete, but they are explicitly **out of the v1 acceptance target**.

- **D1. `ai-doctor` health check + cleanup.** `ai-doctor <profile>` reports
  pass/fail per check (image exists, workspace exists, persistent container
  present + state, expected binaries present, declared serial/hardware devices
  exist, Podman is rootless, secret env files mode `600`, profile syntax valid).
  The canonical teardown flow is `ai-doctor <profile> --cleanup`: always
  user-initiated, never run by `ai-launch`; it reports
  container/workspace/image/git-safety state before offering removal. Cleanup
  MUST be gated by a git-protection check of the mounted workspace — detect
  whether it is a git repo, has uncommitted changes, and has ignored/untracked
  work; if not git-protected or work is uncommitted/untracked, cleanup requires
  explicit force confirmation. Age-based GC is advisory only — report stale
  stopped containers, never auto-remove.
- **D2. `ai-new` project generator.** `ai-new <name>` scaffolds
  `profiles/<name>.env`, `<name>-workspace/`, `<name>-image/`, and starter
  `launchers/<name>-*` files with portable derived paths.
- **D3. Named policy levels.** Auditable levels (`normal`, `no-network`,
  `builder`, `hardware`) bundle the corresponding run-time options so risk is
  explicit; `hardware` requires explicit user confirmation of device access.
- **D4. Automatic desktop-entry generation.** `ai-desktop-install <profile>`
  generates `.desktop` entries and launcher wrappers automatically.
- **D5. Packaging / repo installer.** Cloneable Git repo (`bin/`,
  `profiles.example/`, `launchers.example/`, `docs/` with security-model,
  Podman-Desktop, and Bazzite notes, plus `examples/`), reusable on other Bazzite
  systems, with secrets and real profiles kept out of version control.
- **D6. Request-driven environment builder (agent-delegated, R16).** Plain-text
  target description → external AI agent derives a minimum environment spec (base
  image + toolchains), surfacing conflicts/costly paths/multi-target
  choices/hardware confirmation back to the user. Agent selected by precedence:
  per-invocation flag → per-profile `REQUEST_BUILDER_AGENT` → global
  `$CODEX_JAILS_DIR/config/agents.env` → auto-detection of registered CLI agents.
  Adapter contract is prompt-in, structured-spec-out, returning at least base
  image, packages, toolchains, generated/modified files, risks/conflicts,
  hardware/network requirements, and whether approval is required. Generated build
  input MUST be reviewed before build: show a baseline-vs-proposed diff; nothing
  executable applied silently; high-risk changes (privileged, host mounts, device
  passthrough, host networking, socket exposure) are blocked or require separate
  elevated confirmation. Soft dependency: with no agent configured, the builder
  fails clearly and hand-authoring still works.
- **D7. Nested rootless Podman child-launching.** Not part of default product
  mode: default sandboxes may edit/build/test code and propose dependency changes
  via controlled Containerfile inputs, but MUST NOT launch child sandboxes. If
  added later as an explicit `nested-builder` policy, it MUST NOT use the host
  Podman/Docker socket, host network, host PID namespace, `--privileged`, or broad
  host mounts, and requires a dedicated profile granting only minimum tested
  requirements (e.g. `/dev/fuse`, subordinate uid/gid mappings, rootless storage,
  rootless user-mode networking).

## Acceptance Criteria

v1 acceptance criteria (AC1–AC15). Criteria for deferred features are listed
separately under **Deferred Acceptance** so the v1 release gate is unambiguous.

- **AC1.** With only `profiles/esp32.env` and `profiles/uxplay.env` present,
  `ai-build esp32` and `ai-build uxplay` each build the image from the profile's
  `IMAGE_DIR` and print tool/library versions from `POST_BUILD_CHECK`; a missing
  profile or image dir exits non-zero with a clear message.
- **AC2.** `ai-launch esp32` / `ai-launch uxplay` start a rootless container whose
  inspected config shows `--userns=keep-id`, `no-new-privileges`, `keep-groups`,
  the configured SELinux mode, `HOME` set to `CONTAINER_HOME`, and exactly one
  bind mount (`$WORKSPACE` → `/workspace`) — and none of host `$HOME`, `~/.ssh`,
  `~/.gnupg`, `~/.config`, `/`, Docker socket, or Podman socket.
- **AC3.** **Persistence.** After `ai-launch <profile>` exits, the named container
  still exists (not removed); a second `ai-launch <profile>` reuses it and the
  in-container `$HOME`/workspace state from the first session is present. A
  documented, user-initiated removal path destroys it on demand; routine exit
  never does.
- **AC4.** `ai-launch esp32 codex` and `ai-launch uxplay codex` start the
  respective agent inside the sandbox; `ai-launch <profile> bash` opens an
  interactive shell.
- **AC5.** `ai-launch uxplay builder` is the only invocation yielding a
  `--privileged` container, using the `-builder` container name; no default or
  normal-mode path is privileged.
- **AC6.** **Builder ephemerality.** A builder-mode container is launched with
  `--rm` and no longer exists after exit, while the normal-mode persistent
  container for the same profile is unaffected.
- **AC7.** `NETWORK_MODE=none ai-launch esp32 codex` produces a container with no
  outbound connectivity; the default launch has working network.
- **AC8.** A profile-declared device (e.g. `--device=/dev/ttyUSB0`) and
  `EXTRA_HOSTS`/`EXTRA_ENV` entries appear in the launched container exactly as
  declared, and only for the profile that declares them.
- **AC9.** **SELinux choice.** A profile with the stricter `:Z`-only
  `SELINUX_MODE` launches without `label=disable`; the default profile launches
  with `label=disable`. Both are documented and selectable.
- **AC10.** With a running container, `ai-terminal <profile>` attaches a second
  shell; with no running container it exits non-zero with a clear message.
- **AC11.** `ai-list` prints every profile with name, image, workspace (aligned)
  and the persistent-container state; an absent profile dir exits non-zero.
- **AC12.** Each retained legacy script name (e.g. `launch-esp32-workspace`,
  `update-codex-uxplay-image`) invokes the corresponding generic command and
  produces equivalent behaviour (inheriting persistence).
- **AC13.** When `ENV_FILE` is defined and present (mode `600`), its variables are
  available inside the container; when defined but missing, `ai-launch` warns and
  still launches; when undefined, no host secret files are mounted.
- **AC14.** **Stale-image reconciliation.** After `ai-build <profile>` rebuilds an
  image whose ID differs from the existing container's source image ID, an
  interactive `ai-launch <profile>` warns and offers
  continue/recreate(preserving workspace)/cancel; `ai-launch <profile> --yes`
  (or `--non-interactive`) warns and continues without recreating;
  `ai-launch <profile> --recreate` recreates from the current image while
  preserving the workspace and container-home.
- **AC15.** **Framework-managed teardown.** `ai-launch <profile> --reset` removes
  the persistent normal-mode container and leaves the workspace, container-home,
  profile, image directory, and secret env file intact; a subsequent
  `ai-launch <profile>` recreates the container from the current image. In
  non-interactive use, `--reset` without `--yes` does not silently stop a running
  container.

### Deferred Acceptance (post-v1)

- **DA1.** A hand-authored `.desktop` entry launches a sandbox via a `launchers/`
  wrapper on KDE with paths derived from `$HOME`/`$CODEX_JAILS_DIR` (no hardcoded
  username), and the running container appears in Podman Desktop. *(Manual
  launchers are v1; automatic generation is D4.)*
- **DA2.** `ai-doctor <profile>` reports per-check pass/fail covering at least
  image exists, workspace exists, Podman rootless, profile valid, container state,
  and secret-file permissions; `ai-doctor <profile> --cleanup` gates removal on
  the git-protection check. *(D1.)*
- **DA3.** **Agent-delegated builder.** A plain-text request naming a language +
  at least one OS/arch/device target invokes the configured AI agent and yields a
  derived minimum spec (base image + toolchains) as a selected/generated profile
  and image plan; conflicting/costly paths return the agent's assessment for a
  decision; multi-target requests surface the one-multi-arch-image vs
  multiple-profiles choice; hardware targets prompt for device confirmation; with
  no agent configured the builder fails clearly and hand-authoring still works.
  *(D6.)*
- **DA4.** **Cloneable + nested.** The framework can be cloned to a second Bazzite
  host and, after adding profiles, run `ai-build`/`ai-launch` successfully with no
  secrets in the repo; and it can itself be launched via Podman from
  `$CODEX_JAILS_DIR/podman-plugin-workspace` and operate from inside that sandbox.
  *(Nested-bootstrap R13.4 is v1; full packaging is D5.)*

## Resolved Questions

None. All clarifying questions from the parent lineage are resolved:

- OQ1–OQ10 (parent `ai-agent-podman-sandbox-3.md`) were resolved into the
  consolidated v1 cut.
- OQ-A (image-staleness tracking) → resolved into R3.5 / R4.9: compare live image
  IDs at launch; no framework-maintained image-state file in v1.
- OQ-B (interactive detection) → resolved into R4.10: `[[ -t 0 && -t 1 ]]`, with
  `--yes`/`--non-interactive`, `--recreate`, `--no-recreate`; `--yes` means
  continue, not recreate.
- OQ-C (builder-mode persistence) → resolved into R4.12: builder containers are
  ephemeral (`--rm`); caching via mounted directories, not a live privileged
  container.
- OQ-D (v1 teardown ergonomics) → resolved into R4.11: include
  `ai-launch <profile> --reset` (and `--recreate`) as the canonical
  framework-managed teardown, preserving workspace/home/profile/image/secrets.
