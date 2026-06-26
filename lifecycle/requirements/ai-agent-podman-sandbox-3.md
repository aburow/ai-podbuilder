---
title: AI Agent Podman Sandbox Framework — Detailed Requirements
type: requirement
status: done
lineage: ai-agent-podman-sandbox
created: "2026-06-22T00:00:00+10:00"
priority: normal
parent: lifecycle/requirements/ai-agent-podman-sandbox-2.md
assignees:
    - role: product-owner
      who: agent
---

# AI Agent Podman Sandbox Framework — Detailed Requirements

This artifact refines `ai-agent-podman-sandbox-2.md` after its clarifying round.
The resolved answers there change two prior assumptions materially and are folded
in here:

1. **Persistence replaces `--rm`** for normal-mode sandboxes — these are
   long-lived dev/build environments, and persistence is itself a safety property
   (a breakout or supply-chain compromise stays contained in a known, inspectable
   container rather than vanishing on exit). See R4 and R12.
2. **The request-driven builder (R16) is explicitly agent-delegated** — it calls an
   external AI agent to derive a minimum environment spec (base image + toolchains)
   and to assess portability cost/conflict, rather than encoding that knowledge in
   the framework. See R16.

## Problem

AI coding agents (Codex, Aider, OpenCode) are run against project
workspaces on a Bazzite/Fedora desktop using rootless Podman. Each project is
launched by its own hand-written script, all copies of the same sound pattern
(rootless, `--userns=keep-id`, `no-new-privileges`, a narrow workspace-only mount,
a fake in-container `$HOME`). Because the pattern is copied per project, the safety
policy has **drifted**: scripts hardcode slightly different values, the privileged
builder path is not cleanly separated from the normal path, and there is no single
authoritative definition of "what is safe by default." Adding a project means
cloning and editing several scripts. There is also no inventory, no health check,
no desktop integration story, and no clean way to package the approach for reuse on
another machine.

The core need driving the MVP: **the user must be able to stand up an isolated dev
container with the specific tools and libraries a project requires, and use it with
whatever agent they choose**, without per-project script drift and without exposing
the host.

## Goals / Non-goals

### Goals

- Replace per-project launch scripts with a small set of **generic commands**
  (`ai-build`, `ai-launch`, `ai-terminal`, `ai-list`) that source per-project
  **profile files** (`profiles/<name>.env`).
- Define the safety policy in **one auditable place** so every normal-mode sandbox
  launches identically.
- Make higher-risk paths **explicit and opt-in**: privileged builder mode only via
  `ai-launch <profile> builder`; hardware/device passthrough declared per profile
  and confirmed with the user.
- Provide **persistent, named** sandbox containers that survive exit, so ongoing dev
  and build state is retained and any compromise stays contained and inspectable.
- Keep each project **isolated** under `$CODEX_JAILS_DIR/<name>-workspace` with its
  own in-container `$HOME` under `/workspace`, mounting no host secrets, SSH, config,
  or the Podman socket in normal mode.
- **Preserve muscle memory**: retain current script names as thin compatibility
  wrappers delegating to the new commands.
- Launch sandboxes from both the **CLI** and **Podman Desktop / KDE / GNOME**.
- Be **packageable** as a cloneable Git repository, with paths derived from `$HOME`
  / `$CODEX_JAILS_DIR` (no hardcoded usernames) and no secrets in version control.
- Provide planned enhancements: network policy levels, per-profile secret env files,
  in-sandbox SSH-key strategy, desktop launcher generation, and an `ai-doctor`
  health check.
- Provide a **request-driven environment builder** (R16) that takes a plain-text
  target description and **delegates to an AI agent** to derive a minimum
  environment spec (base image such as `fedora:latest` + libraries/toolchains),
  surfacing conflicts, costly paths, and multi-target choices back to the user.

### Non-goals

- Not maximum container security or a hardened multi-tenant boundary; the target is
  a practical dev sandbox **materially safer than running agents on the bare host**.
- No Kubernetes, no orchestration, no daemon beyond rootless Podman. Implementation
  stays POSIX/Bash.
- Not a hosted/CI/remote service; scope is a single user's local desktop.
- Not responsible for agent image contents beyond building from a profile-declared
  image directory (Containerfiles are project inputs).
- Rootful Podman and non-Fedora/Bazzite hosts are out of scope for the first release
  (Bazzite/Fedora + rootless Podman is the supported target).

## Detailed Requirements

### R1. Layout and installation

- R1.1 Base directory defaults to `~/codex-jails`, overridable via
  `CODEX_JAILS_DIR`. All generated paths derive from `$HOME` / `$CODEX_JAILS_DIR`;
  no username is hardcoded.
- R1.2 The base directory contains `bin/` (generic commands), `profiles/`
  (per-project `.env`), and `launchers/` (desktop/Podman-Desktop wrappers). Project
  workspaces and image dirs sit alongside as `<name>-workspace/` and `<name>-image/`.
- R1.3 `bin/` is added to `PATH`; docs describe persisting this in the shell profile.

### R2. Profiles

- R2.1 Each sandbox is described by exactly one sourced Bash fragment
  `profiles/<name>.env`.
- R2.2 Required fields: `PROFILE_NAME`, `CONTAINER_NAME`, `IMAGE_NAME`, `IMAGE_DIR`,
  `WORKSPACE`, `CONTAINER_HOME`, `BASHRC`, `WORKDIR`, `BUILD_ARGS`.
- R2.3 Optional arrays/values: `EXTRA_ENV`, `EXTRA_VOLUMES`, `EXTRA_DEVICES`,
  `EXTRA_HOSTS`, `EXTRA_RUN_ARGS`, `POST_BUILD_CHECK`, `PNPM_HOME`, `HISTFILE`.
- R2.4 Optional `ENV_FILE` (secrets), `NETWORK_MODE`, and `SELINUX_MODE` (see R5.6).
- R2.5 Profiles must not contain secrets; secret material lives in `ENV_FILE`-referenced
  files (R7).
- R2.6 Missing or malformed profile (absent file, missing required field) fails with
  a clear, actionable message and non-zero exit.

### R3. `ai-build`

- R3.1 `ai-build <profile>` sources the profile and runs `podman build` in
  `IMAGE_DIR` using `BUILD_ARGS`.
- R3.2 On success, runs `POST_BUILD_CHECK` inside the new image to report installed
  tool/library versions (the MVP's "the requested tools are present" confirmation).
- R3.3 Errors (profile not found, image dir not found, build failure) exit non-zero
  with a clear message.
- R3.4 `-h`/`--help`/no-arg prints usage.

### R4. `ai-launch`, launch modes, and persistence

- R4.1 `ai-launch <profile> [mode]` sources the profile, ensures the workspace,
  container-home, pnpm, and `.bash_history` paths exist, then starts/attaches the
  sandbox container.
- R4.2 **Persistence (resolved OQ9).** Normal-mode containers are **named and
  persistent**, not `--rm`. If a container for the profile already exists, `ai-launch`
  reuses it (start + attach / `exec`); if not, it is created. Workspace state and
  in-container `$HOME` persist across exits, and the container itself remains
  inspectable after exit. A documented teardown path (e.g. `ai-launch <profile> --reset`
  or an `ai-rm`/`ai-doctor`-driven action) removes a sandbox deliberately; routine
  exit never destroys it.
- R4.3 **Normal mode** (default `shell`/`bash`) applies the standard safety policy
  (R5): `-it`, `--userns=keep-id`, `--group-add keep-groups`,
  `--security-opt no-new-privileges`, SELinux per R5.6, `-e HOME=$CONTAINER_HOME`,
  the single workspace mount `-v $WORKSPACE:/workspace:Z`, and `-w $WORKDIR`.
- R4.4 Supported modes: `shell`/`bash` (default), `codex`, `codex`, and `builder`.
  The mode set is extensible to additional agents (`aider`, `opencode`,
  `ollama-shell`, etc.) without changing the safety core.
- R4.5 **Builder mode** is the only privileged path: `--privileged`, a distinct
  `-builder` container name, reachable only by explicitly passing `builder`, never
  default.
- R4.6 Profile `EXTRA_*` arrays are appended in normal mode (hosts, devices, volumes,
  env, run args).
- R4.7 Unknown mode exits non-zero and prints usage.
- R4.8 Before launching/attaching, the command echoes a summary (profile, container,
  image, workspace, container `$HOME`, mode, network, SELinux mode, whether reusing
  an existing container) so the active policy is visible.

### R5. Safety policy (normal mode)

- R5.1 Normal-mode containers MUST use `--userns=keep-id`, `--group-add keep-groups`,
  and `--security-opt no-new-privileges`.
- R5.2 Normal mode MUST mount only the project workspace (`-v $WORKSPACE:/workspace:Z`).
  It MUST NOT mount any of: host `$HOME`, `~/.ssh`, `~/.gnupg`, `~/.config`, `/`, the
  Docker socket, or the Podman socket.
- R5.3 `--privileged` is forbidden in normal mode; permitted only in builder mode
  (R4.5).
- R5.4 The container's `$HOME` is a directory inside the mounted workspace
  (`CONTAINER_HOME` under `/workspace`) — writable, persistent, contained.
- R5.5 The rationale for relaxing SELinux labelling (labelling friction with mounted
  dev workspaces on Bazzite) must be documented; the workspace mount stays explicit
  and narrow.
- R5.6 **SELinux mode (resolved OQ5).** `--security-opt label=disable` remains the
  default for friction-free dev, **but the framework offers a stricter `:Z`-only
  variant**: a per-profile `SELINUX_MODE` (e.g. `disable` | `enforce`) selects between
  `label=disable` and relying on the `:Z` relabel alone. The stricter option is
  documented and presented to the user as an available choice, not hidden.

### R6. Network policy

- R6.1 `ai-launch` supports `NETWORK_MODE` (default `slirp4netns`) passed as
  `--network`. **Network is required by default** (resolved OQ6) — normal sandboxes
  have outbound connectivity.
- R6.2 `NETWORK_MODE=none` produces a fully offline container, intended for reviewing
  local code without giving the agent network access.
- R6.3 Network mode is overridable per-invocation (env var) and settable per profile.

### R7. Secrets

- R7.1 Default mounts no host secrets.
- R7.2 If a profile defines `ENV_FILE`: when the file exists, add `--env-file <file>`;
  when defined but missing, **warn and continue** (resolved OQ4) — do not hard-fail.
- R7.3 Secret files are per-profile, expected mode `600`, never committed to Git.

### R8. SSH strategy

- R8.1 Host `~/.ssh` is never mounted by default.
- R8.2 Docs describe generating a dedicated in-sandbox SSH key (e.g. `ed25519`) so the
  agent gets scoped Git access without exposing the host identity.

### R9. `ai-terminal`

- R9.1 `ai-terminal <profile>` attaches an additional interactive shell to the
  running container for that profile via `podman exec -it`.
- R9.2 If the container is not running, exits non-zero with a clear message (and may
  hint at `ai-launch` to start/resume the persistent container).

### R10. `ai-list`

- R10.1 `ai-list` enumerates `profiles/*.env` and prints, per profile, name, image
  name, and workspace path in aligned columns. It SHOULD also indicate whether a
  persistent container currently exists and its state (running/stopped).
- R10.2 Missing profile directory exits non-zero with a clear message.

### R11. Compatibility wrappers

- R11.1 Existing script names (`launch-esp32-workspace`,
  `short-launch-esp32-workspace`, `launch-uxplay-workspace`, `launch-uxplay-builder`,
  `extra-terminal`, `update-codex-esp32-image`, `update-codex-uxplay-image`, and known
  variants) are retained as thin wrappers that `exec` the corresponding generic command
  with fixed arguments.
- R11.2 Wrappers produce behaviour equivalent to the originals — adjusted only for the
  persistence change (R4.2), which they inherit.

### R12. Desktop and Podman Desktop integration

- R12.1 `launchers/<name>-<mode>` thin scripts call `ai-launch <name> <mode>` and are
  the recommended entry points for desktop menus and Podman Desktop.
- R12.2 `.desktop` entries under `~/.local/share/applications/` launch the
  `launchers/` scripts in a terminal; docs cover KDE (`konsole`) and GNOME (`kgx`).
  Generated entries derive paths from `$HOME` / `$CODEX_JAILS_DIR` — **no hardcoded
  `/var/home/<user>` paths** (resolved OQ8).
- R12.3 Persistent containers started this way are visible and manageable in Podman
  Desktop (start/stop/inspect/remove).
- R12.4 (Planned) `ai-desktop-install <profile>` generates `.desktop` entries and
  launcher wrappers automatically.

### R13. Health check (`ai-doctor`)

- R13.1 `ai-doctor <profile>` validates the sandbox and reports pass/fail per check:
  image exists, workspace exists, persistent container present and its state, expected
  binaries present, declared serial/hardware devices exist, Podman is rootless, secret
  env files have mode `600`, and profile syntax is valid.

### R14. Project generator (`ai-new`)

- R14.1 (Planned) `ai-new <name>` scaffolds `profiles/<name>.env`, `<name>-workspace/`,
  `<name>-image/`, and starter `launchers/<name>-*` files, with portable derived paths.

### R15. Policy levels

- R15.1 (Planned) Named, auditable policy levels (`normal`, `no-network`, `builder`,
  `hardware`) bundle the corresponding run-time options so risk is explicit. The
  `hardware` level requires explicit user confirmation of device access (R16.5).

### R16. Request-driven environment builder (agent-delegated)

- R16.1 The user makes a plain-text request describing a build target — language,
  target OS/distribution, version, architecture, and device (e.g. "Rust for Ubuntu
  x.y.z amd64 and Raspbian x.y.z on Raspberry Pi 5").
- R16.2 **Agent delegation (resolved OQ2).** The builder invokes an external AI agent
  (Codex / Codex / Gemini / ChatGPT / Google, per user configuration) to derive a
  **minimum environment specification**: a base container image (e.g. `fedora:latest`)
  plus the base libraries/toolchains required, producing or selecting a profile and
  image definition. The framework does **not** maintain its own image/toolchain
  knowledge base; that reasoning is delegated.
- R16.3 **Conflict/cost assessment (resolved OQ3).** Portability/cost judgement is
  handed to the agent. The agent assesses difficulty (low for portable languages like
  Python; higher for more platforms and lower-level languages) and trade-offs (native
  vs cross-compile vs QEMU emulation, image size, build time). When the request implies
  a conflict, non-optimal, or high-cost path, the builder **surfaces these back to the
  user for a decision** rather than proceeding silently.
- R16.4 **Multi-target (resolved OQ7).** Multiple targets in one request are supported.
  Whether they become one multi-arch image or multiple profiles/images is a **user
  choice surfaced at request time**, not auto-decided.
- R16.5 **Hardware access (resolved OQ6).** When a target implies hardware/device
  access (e.g. USB, serial), the builder explicitly asks the user to confirm and to
  declare the device, which is then recorded in the profile's `EXTRA_DEVICES`.
- R16.6 The agent dependency is a soft dependency: when no agent is configured/available,
  the builder fails clearly and the user can still author profiles by hand (MVP path).

### R17. Packaging

- R17.1 (Planned) Packaged as a cloneable Git repo (`bin/`, `profiles.example/`,
  `launchers.example/`, `docs/` with security-model, Podman-Desktop, and Bazzite notes,
  plus `examples/`), reusable on other Bazzite systems, with secrets and real profiles
  kept out of version control.

### R18. Non-functional

- R18.1 Commands are POSIX/Bash, `set -euo pipefail`, no daemon beyond rootless Podman.
- R18.2 All commands provide `-h`/`--help` and clear, non-zero-exit error messages.
- R18.3 Targets Bazzite/Fedora with rootless Podman and Podman Desktop.
- R18.4 **Nested-sandbox bootstrap (resolved OQ10).** The framework must be importable
  and runnable from inside its own sandbox — specifically launched via Podman from
  `$CODEX_JAILS_DIR/podman-plugin-workspace` — so the user can move from one contained
  environment to another without breaking out of any container. The design must not
  assume it only ever runs on the bare host.

## Acceptance Criteria

- AC1. With only `profiles/esp32.env` and `profiles/uxplay.env` present, `ai-build esp32`
  and `ai-build uxplay` each build the image from the profile's `IMAGE_DIR` and print
  tool/library versions from `POST_BUILD_CHECK`; a missing profile or image dir exits
  non-zero with a clear message.
- AC2. `ai-launch esp32` / `ai-launch uxplay` start a rootless container whose inspected
  config shows `--userns=keep-id`, `no-new-privileges`, `keep-groups`, the configured
  SELinux mode, `HOME` set to `CONTAINER_HOME`, and exactly one bind mount
  (`$WORKSPACE` → `/workspace`) — and none of host `$HOME`, `~/.ssh`, `~/.gnupg`,
  `~/.config`, `/`, Docker socket, or Podman socket.
- AC3. **Persistence.** After `ai-launch <profile>` exits, the named container still
  exists (not removed); a second `ai-launch <profile>` reuses it and the in-container
  `$HOME`/workspace state from the first session is present. A deliberate reset/removal
  path destroys it on demand.
- AC4. `ai-launch esp32 codex` and `ai-launch uxplay codex` start the respective agent
  inside the sandbox; `ai-launch <profile> bash` opens an interactive shell.
- AC5. `ai-launch uxplay builder` is the only invocation yielding a `--privileged`
  container, using the `-builder` container name; no default or normal-mode path is
  privileged.
- AC6. `NETWORK_MODE=none ai-launch esp32 codex` produces a container with no outbound
  connectivity; the default launch has working network.
- AC7. A profile-declared device (e.g. `--device=/dev/ttyUSB0`) and
  `EXTRA_HOSTS`/`EXTRA_ENV` entries appear in the launched container exactly as
  declared, and only for the profile that declares them.
- AC8. **SELinux choice.** A profile with the stricter `:Z`-only `SELINUX_MODE` launches
  without `label=disable`; the default profile launches with `label=disable`. Both are
  documented and selectable.
- AC9. With a running container, `ai-terminal <profile>` attaches a second shell; with
  no running container it exits non-zero with a clear message.
- AC10. `ai-list` prints every profile with name, image, workspace (aligned) and the
  persistent-container state; an absent profile dir exits non-zero.
- AC11. Each retained legacy script name (e.g. `launch-esp32-workspace`,
  `update-codex-uxplay-image`) invokes the corresponding generic command and produces
  equivalent behaviour (inheriting persistence).
- AC12. A `.desktop` entry launches a sandbox via a `launchers/` wrapper on KDE with
  paths derived from `$HOME`/`$CODEX_JAILS_DIR` (no hardcoded username), and the running
  container appears in Podman Desktop.
- AC13. When `ENV_FILE` is defined and present (mode `600`), its variables are available
  inside the container; when defined but missing, `ai-launch` warns and still launches;
  when undefined, no host secret files are mounted.
- AC14. `ai-doctor <profile>` reports per-check pass/fail covering at least: image
  exists, workspace exists, Podman rootless, profile valid, container state, and
  secret-file permissions.
- AC15. **Agent-delegated builder.** A plain-text request naming a language + at least
  one OS/arch/device target invokes the configured AI agent and yields a derived minimum
  spec (base image + toolchains) as a selected/generated profile and image plan. A
  request with a conflicting or costly path returns the agent's assessment to the user
  for a decision instead of proceeding; a multi-target request surfaces the
  one-multi-arch-image vs multiple-profiles choice to the user; a hardware target prompts
  for device confirmation. With no agent configured, the builder fails clearly and
  hand-authoring still works.
- AC16. **Cloneable + nested.** The framework can be cloned to a second Bazzite host and,
  after adding profiles, run `ai-build`/`ai-launch` successfully with no secrets in the
  repo; and it can itself be launched via Podman from
  `$CODEX_JAILS_DIR/podman-plugin-workspace` and operate from inside that sandbox.

## Resolved Questions

- OQ1. **Container teardown UX.** Persistence (R4.2) means containers accumulate. What
  is the canonical removal command/flag — `ai-launch --reset`, a dedicated `ai-rm`, or an
  `ai-doctor`-driven cleanup — and should there be any age/garbage-collection guidance?

Resolved: teardown is `ai-doctor` driven and always user initiated.

The canonical removal flow is `ai-doctor <profile> --cleanup`, which reports the
persistent container state, workspace state, image state, and git safety state before
offering removal actions. Routine `ai-launch` never removes containers.

Cleanup MUST be gated by a git protection check for the mounted workspace. At minimum,
the tool must detect whether the workspace is a git repository, whether it has
uncommitted changes, and whether those changes are ignored/untracked. If the workspace
is not git-protected or has uncommitted/untracked work, cleanup must require explicit
force confirmation.

Age-based garbage collection is advisory only. The tool may report stale stopped
containers, but it must not auto-remove them.

- OQ2. **Image rebuild vs persistent container.** When `ai-build` produces a new image,
  how is an existing persistent container reconciled (warn, auto-recreate on next launch,
  or require explicit reset)? State lives in the workspace mount, so recreation should be
  safe, but this needs a defined default.

Resolved: `ai-build` never silently mutates or removes an existing persistent
container.

When `ai-build <profile>` creates a new image, the framework records the newly built
image ID/digest for that profile. On the next `ai-launch <profile>`, if the existing
persistent container was created from an older image, `ai-launch` warns the user and
offers three explicit choices:

1. continue using the existing container;
2. recreate the container from the new image while preserving the workspace-mounted
   state; or
3. cancel and inspect manually.

The default non-interactive behavior is warn-and-continue, never auto-recreate.

Dependency changes should be made durable by editing the profile's image definition
directly, preferably the project Containerfile or explicit include fragments consumed
by that Containerfile. Helper scripts inside the persistent workspace are allowed for
experimentation, but durable requirements should be promoted into the image definition
before relying on rebuilds.
  
- OQ3. **Agent selection/config for R16.** How is the AI agent for the request-driven
  builder configured (env var, profile field, global config), and what is the minimum
  interface contract (prompt in → structured spec out) so different agents are
  interchangeable?

Resolved: agent configuration supports both registered CLI agents and API-key/env-file
agents.

The builder uses a configurable agent adapter selected by this precedence:

1. per-invocation flag, e.g. `ai-new --agent codex`;
2. per-profile field, e.g. `REQUEST_BUILDER_AGENT=codex`;
3. global config, e.g. `$CODEX_JAILS_DIR/config/agents.env`;
4. auto-detection of registered CLI agents.

Supported adapter types:

- CLI-registered agents, such as Codex or Codex, where auth/config lives inside
  the sandbox's persistent agent config directory, for example `.codex` or equivalent;
- env-file/API-key agents, where credentials are provided through profile/global
  `ENV_FILE` values.

The minimum interface contract is prompt-in, structured-spec-out. The adapter must
return a machine-readable environment plan containing at least: base image, packages,
toolchains, generated/modified files, risks/conflicts, hardware requirements, network
requirements, and whether user approval is required.
  
- OQ4. **Builder output trust.** The agent's derived base image/toolchain spec is
  effectively executable input to `podman build`. Should the user always review/approve
  the generated profile and Containerfile before a build runs, and how is that confirmation
  step presented?

Resolved: generated builder output must be reviewed before build.

The builder must show a baseline-vs-proposed diff before running `podman build`.
Changes to Containerfiles, include fragments, profile fields, package lists,
environment variables, device declarations, network policy, and secret-file references
must be highlighted.

In the Podman plugin UI, this should be presented as a review/approval screen or
dialog. In CLI mode, it must fall back to a terminal diff plus explicit confirmation.

No generated or modified executable build input is applied silently. The user must
approve the proposed changes before build. High-risk changes, such as privileged mode,
host mounts, device passthrough, host networking, or socket exposure, must be blocked
or require a separate elevated confirmation depending on policy.
  
- OQ5. **Nested-sandbox privileges (R18.4).** Running the framework from inside
  `podman-plugin-workspace` implies nested rootless Podman. What concretely must that
  inner sandbox be granted (e.g. `--device /dev/fuse`, specific subuid/subgid, network)
  to launch child sandboxes without weakening the host policy?

Resolved: nested child-container launching is not part of default product mode.

Default product mode allows AI-agent containers to edit, build, and test code, and to
propose dependency changes by editing controlled Containerfile inputs. It does not
allow those containers to launch child sandboxes.

The preferred dependency-editing model is controlled image input:

- the agent may edit project-owned Containerfile fragments or include files;
- the framework-owned safety launcher remains outside the agent's write scope;
- generated changes are shown as a diff and require user approval before build.

True nested rootless Podman may be added later as an explicit `nested-builder` policy,
not inherited by normal profiles. If added, it must not use the host Podman socket,
Docker socket, host network, host PID namespace, `--privileged`, or broad host mounts.
It may require a dedicated profile granting only the minimum tested requirements such
as `/dev/fuse`, subordinate uid/gid mappings inside the image, rootless container
storage, and rootless user-mode networking.
  
- OQ6. **MVP cut confirmation.** OQ1 resolved the MVP as "build an isolated dev container
  with the requested tools/libraries, usable by any agent." Confirm the v1 command set is
  `ai-build` + `ai-launch` (persistent) + `ai-terminal` + `ai-list` + profiles + safety
  policy + compat wrappers, with network modes, secrets, `ai-doctor`, `ai-new`, policy
  levels, desktop-install, packaging, and the R16 request-driven builder all deferred to
  later increments.

Resolved: v1 scope is limited to the core local sandbox framework.

The v1 command set is:

- `ai-build`
- `ai-launch`
- `ai-terminal`
- `ai-list`
- profile files
- normal-mode safety policy
- persistent named containers
- compatibility wrappers for existing scripts

Included in v1:

- basic network mode support: default outbound network and `NETWORK_MODE=none`;
- optional `ENV_FILE` support for per-profile secrets;
- documented in-sandbox SSH-key strategy;
- manual desktop/Podman Desktop launcher wrappers.

Deferred beyond v1:

- `ai-doctor`;
- `ai-new`;
- named policy levels;
- automatic desktop entry generation;
- full packaging/repo installer;
- request-driven environment builder R16;
- nested rootless Podman child-container launching.

The v1 acceptance target is a safe, reusable replacement for the current hand-written
project scripts, not the full product vision.

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
