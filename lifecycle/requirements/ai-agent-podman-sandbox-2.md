---
title: AI Agent Podman Sandbox Framework
type: requirement
status: done
lineage: ai-agent-podman-sandbox
created: "2026-06-22T00:00:00+10:00"
priority: normal
parent: lifecycle/ideas/ai-agent-podman-sandbox.md
assignees:
    - role: product-owner
      who: agent
---

# AI Agent Podman Sandbox Framework

## Problem

AI coding agents (Codex, Codex, Aider, OpenCode) are run directly against
project workspaces on a Bazzite/Fedora desktop using rootless Podman. Today each
project is launched by its own hand-written script (`launch-esp32-workspace`,
`launch-uxplay-workspace`, `launch-uxplay-builder`, `extra-terminal`, the
`update-codex-*-image` builders, and assorted variants). The core launch pattern
is sound — rootless, `--userns=keep-id`, `no-new-privileges`, a narrow
workspace-only mount, and a fake `$HOME` inside the container — but it is copied
per project.

The result is **drift**: each script hardcodes slightly different values, so the
safety and launch policy is no longer guaranteed to be uniform across workspaces.
Adding a new project means cloning and editing several scripts. The riskier paths
(privileged Flatpak builder, hardware device passthrough) are not consistently
distinguished from the normal sandbox path, and there is no single place that
encodes "what is safe by default."

A secondary problem is discoverability and reuse: there is no inventory of
sandboxes, no health check, no desktop/Podman-Desktop integration story, and no
way to package the whole approach so it can be cloned onto another machine.

## Goals / Non-goals

### Goals

- Replace per-project launch scripts with a small set of **generic commands**
  (`ai-build`, `ai-launch`, `ai-terminal`, `ai-list`) that source per-project
  **profile files** (`profiles/<name>.env`) at runtime.
- Make a single, auditable place define the safety policy so every normal-mode
  sandbox is launched identically.
- Make the **higher-risk paths explicit and opt-in**: privileged builder mode is
  only reached via `ai-launch <profile> builder`; hardware device passthrough is
  declared per profile.
- **Preserve existing muscle memory**: keep current script names as thin
  compatibility wrappers that delegate to the new commands.
- Keep each project **isolated** under `~/codex-jails/<name>-workspace` with its
  own container `$HOME` inside `/workspace`, with no host secrets/SSH/config or
  the Podman socket mounted in normal mode.
- Support launching the sandboxes both from the **CLI** and from **Podman Desktop
  / KDE / GNOME** desktop entries.
- Be **packageable** as a cloneable Git repository for reuse across Bazzite
  systems.
- Provide planned enhancements: network policy levels (incl. `NETWORK_MODE=none`
  offline review), per-profile secret env files, an SSH-key-in-sandbox strategy,
  desktop launcher generation, and an `ai-doctor` health-check command.
- Provide a **request-driven environment builder**: the user describes a target
  in plain text (e.g. "build a Rust program for Ubuntu x.y.z amd64 and Raspbian
  x.y.z on the Pi 5") and the framework selects the appropriate base image and
  libraries, surfacing conflicts or costly/sub-optimal paths back to the user.

### Non-goals

- Not aiming for maximum container security or a hardened multi-tenant boundary.
  The target is a practical development sandbox that is materially safer than
  running agents on the bare host.
- No Kubernetes, no heavy orchestration, no daemon. Implementation stays as
  simple POSIX/Bash scripts driving rootless Podman.
- Not a hosted/CI/remote service; the scope is a single user's local desktop.
- Not responsible for the contents of the agent images themselves beyond building
  them from a profile-declared image directory (the Containerfiles are project
  inputs).
- Rootful Podman and non-Fedora/Bazzite hosts are out of scope for the first
  release (Bazzite/Fedora + rootless Podman is the supported target).

## Detailed Requirements

### R1. Layout and installation

- R1.1 The framework lives under a base directory, default `~/codex-jails`,
  overridable via `CODEX_JAILS_DIR`.
- R1.2 The base directory contains `bin/` (generic commands), `profiles/`
  (per-project `.env` files), and `launchers/` (thin desktop/Podman-Desktop
  wrappers). Project workspaces and image directories live alongside as
  `<name>-workspace/` and `<name>-image/`.
- R1.3 `bin/` is added to `PATH`; documentation describes persisting this in the
  user's shell profile.

### R2. Profiles

- R2.1 Each sandbox is described by exactly one profile file
  `profiles/<name>.env`, a sourced Bash fragment.
- R2.2 A profile declares at minimum: `PROFILE_NAME`, `CONTAINER_NAME`,
  `IMAGE_NAME`, `IMAGE_DIR`, `WORKSPACE`, `CONTAINER_HOME`, `BASHRC`, `WORKDIR`,
  and `BUILD_ARGS`.
- R2.3 A profile may declare optional arrays: `EXTRA_ENV`, `EXTRA_VOLUMES`,
  `EXTRA_DEVICES`, `EXTRA_HOSTS`, `EXTRA_RUN_ARGS`, plus `POST_BUILD_CHECK`,
  `PNPM_HOME`, and `HISTFILE`.
- R2.4 A profile may declare optional `ENV_FILE` (secrets) and `NETWORK_MODE`.
- R2.5 Profiles must not contain secrets; secret material lives in separate
  files referenced by `ENV_FILE` (see R7).
- R2.6 Missing or malformed profile (file absent, missing required fields) must
  fail with a clear, actionable error and a non-zero exit code.

### R3. `ai-build`

- R3.1 `ai-build <profile>` sources the profile and runs `podman build` in
  `IMAGE_DIR` using `BUILD_ARGS`.
- R3.2 After a successful build, it runs `POST_BUILD_CHECK` inside the new image
  to report installed tool versions.
- R3.3 Errors (profile not found, image dir not found, build failure) exit
  non-zero with a clear message.
- R3.4 `-h`/`--help`/no-arg prints usage.

### R4. `ai-launch` and launch modes

- R4.1 `ai-launch <profile> [mode]` sources the profile, ensures the workspace,
  container-home, pnpm, and `.bash_history` paths exist, then `exec`s
  `podman run`.
- R4.2 **Normal mode** (default `shell`/`bash`) launches with the standard safety
  policy (see R5): `--rm -it`, `--userns=keep-id`, `--group-add keep-groups`,
  `--security-opt no-new-privileges`, `--security-opt label=disable`,
  `-e HOME=$CONTAINER_HOME`, the workspace mount `-v $WORKSPACE:/workspace:Z`, and
  `-w $WORKDIR`.
- R4.3 Supported modes: `shell`/`bash` (interactive shell, default), `codex`
  (start Codex), `codex` (start Codex), and `builder` (privileged builder).
  The mode set must be extensible to additional agents (`aider`, `opencode`,
  `ollama-shell`) per §19.3 of the product doc.
- R4.4 **Builder mode** is the only privileged path. It runs `--privileged` with a
  distinct container name suffix (`-builder`) and is reachable only by explicitly
  passing `builder`. It is never the default.
- R4.5 Profile `EXTRA_*` arrays are appended to the run invocation in normal mode
  (hosts, devices, volumes, env, run args).
- R4.6 Unknown mode exits non-zero and prints usage.
- R4.7 Before launching, the command echoes a summary (profile, container, image,
  workspace, container HOME, mode) so the active policy is visible.

### R5. Safety policy (normal mode)

- R5.1 Normal-mode containers MUST use `--userns=keep-id`,
  `--group-add keep-groups`, `--security-opt no-new-privileges`, and
  `--security-opt label=disable`.
- R5.2 Normal mode MUST mount only the project workspace
  (`-v $WORKSPACE:/workspace:Z`). It MUST NOT mount any of: host `$HOME`,
  `~/.ssh`, `~/.gnupg`, `~/.config`, `/`, the Docker socket, or the Podman socket.
- R5.3 `--privileged` is forbidden in normal mode and permitted only in builder
  mode (R4.4).
- R5.4 The container's `$HOME` is a directory inside the mounted workspace
  (`CONTAINER_HOME` under `/workspace`), giving the agent a writable, persistent,
  but contained home.
- R5.5 The rationale for `label=disable` (SELinux labelling friction with mounted
  dev workspaces on Bazzite) must be documented; the workspace mount remains
  explicit and narrow.

### R6. Network policy

- R6.1 `ai-launch` supports a `NETWORK_MODE` (default `slirp4netns`) passed as
  `--network`.
- R6.2 `NETWORK_MODE=none` must produce a fully offline container, intended for
  reviewing local code without giving the agent network access.
- R6.3 Network mode is overridable per-invocation (env var) and settable per
  profile.

### R7. Secrets

- R7.1 Default behaviour mounts no host secrets.
- R7.2 If a profile defines `ENV_FILE` and the file exists, `ai-launch` adds
  `--env-file <file>`; if defined but missing it should warn but still launch (or
  fail — see Open Questions).
- R7.3 Secret files are per-profile, expected mode `600`, and must not be
  committed to Git.

### R8. SSH strategy

- R8.1 The host `~/.ssh` is never mounted by default.
- R8.2 Documentation must describe generating a dedicated in-sandbox SSH key
  (e.g. `ed25519`) so the agent gets scoped Git access without exposing the host
  identity.

### R9. `ai-terminal`

- R9.1 `ai-terminal <profile>` attaches an additional interactive shell to the
  already-running container for that profile via `podman exec -it`.
- R9.2 If the container is not running, it exits non-zero with a clear message.

### R10. `ai-list`

- R10.1 `ai-list` enumerates all `profiles/*.env` and prints, per profile, the
  name, image name, and workspace path in aligned columns.
- R10.2 Missing profile directory exits non-zero with a clear message.

### R11. Compatibility wrappers

- R11.1 Existing script names (`launch-esp32-workspace`,
  `short-launch-esp32-workspace`, `launch-uxplay-workspace`,
  `launch-uxplay-builder`, `extra-terminal`, `update-codex-esp32-image`,
  `update-codex-uxplay-image`, and known variants) are retained as thin wrappers
  that `exec` the corresponding generic command with fixed arguments.
- R11.2 Wrappers must produce behaviour equivalent to the original scripts they
  replace.

### R12. Desktop and Podman Desktop integration

- R12.1 `launchers/<name>-<mode>` thin scripts call `ai-launch <name> <mode>` and
  are the recommended entry points for desktop menus and Podman Desktop.
- R12.2 `.desktop` entries under `~/.local/share/applications/` launch the
  `launchers/` scripts in a terminal; documentation covers both KDE (`konsole`)
  and GNOME (`kgx`) terminals.
- R12.3 Containers started this way are visible and manageable in Podman Desktop.
- R12.4 (Planned) `ai-desktop-install <profile>` generates the `.desktop` entries
  and launcher wrappers automatically.

### R13. Health check (`ai-doctor`)

- R13.1 `ai-doctor <profile>` validates the sandbox and reports pass/fail per
  check: image exists, workspace exists, container running, expected binaries
  present, declared serial/hardware devices exist, Podman is rootless, secret env
  files have safe (`600`) permissions, and profile syntax is valid.

### R14. Project generator (`ai-new`)

- R14.1 (Planned) `ai-new <name>` scaffolds `profiles/<name>.env`,
  `<name>-workspace/`, `<name>-image/`, and starter `launchers/<name>-*` files.

### R15. Policy levels

- R15.1 (Planned) Support named, auditable policy levels (`normal`, `no-network`,
  `builder`, `hardware`) that bundle the corresponding run-time options so risk is
  explicit.

### R16. Request-driven environment builder

- R16.1 The user can make a plain-text request describing a build target,
  including language, target OS/distribution, version, architecture, and device
  (e.g. "Rust for Ubuntu x.y.z amd64 and Raspbian x.y.z on Raspberry Pi 5").
- R16.2 The framework maps the request to an appropriate base image and the
  required base libraries/toolchains, producing or selecting a profile and image
  definition.
- R16.3 When a request implies conflicts, a non-optimal path, or a high-cost path
  (e.g. cross-compilation vs emulation trade-offs, multi-target images), the
  framework must surface these back to the user for a decision rather than
  silently choosing.
- R16.4 Multiple targets in a single request are supported (the example names two
  distinct OS/arch targets).

### R17. Packaging

- R17.1 (Planned) The framework is packaged as a cloneable Git repository
  (`bin/`, `profiles.example/`, `launchers.example/`, `docs/` with security-model,
  Podman-Desktop, and Bazzite notes, plus `examples/`), reusable on other Bazzite
  systems, with secrets and real profiles kept out of version control.

### R18. Non-functional

- R18.1 Commands are POSIX/Bash, `set -euo pipefail`, runnable with no daemon
  beyond rootless Podman.
- R18.2 All commands provide `-h`/`--help` and clear, non-zero-exit error
  messages.
- R18.3 The framework targets Bazzite/Fedora with rootless Podman and Podman
  Desktop.

## Acceptance Criteria

- AC1. With only `profiles/esp32.env` and `profiles/uxplay.env` present,
  `ai-build esp32` and `ai-build uxplay` each build the image from the profile's
  `IMAGE_DIR` and print tool versions from `POST_BUILD_CHECK`; a missing profile or
  image dir exits non-zero with a clear message.
- AC2. `ai-launch esp32` and `ai-launch uxplay` start a rootless container whose
  inspected config shows `--userns=keep-id`, `no-new-privileges`,
  `label=disable`, `keep-groups`, `HOME` set to `CONTAINER_HOME`, and exactly one
  bind mount (`$WORKSPACE` → `/workspace`) — and none of host `$HOME`, `~/.ssh`,
  `~/.gnupg`, `~/.config`, `/`, Docker socket, or Podman socket.
- AC3. `ai-launch esp32 codex` and `ai-launch uxplay codex` start the respective
  agent inside the sandbox; `ai-launch <profile> bash` opens an interactive shell.
- AC4. `ai-launch uxplay builder` is the only invocation that yields a
  `--privileged` container, and it uses the `-builder` container name; no default
  or normal-mode path is privileged.
- AC5. `NETWORK_MODE=none ai-launch esp32 codex` produces a container with no
  network reachability (no outbound connectivity from inside).
- AC6. A profile-declared device (e.g. `--device=/dev/ttyUSB0`) and
  `EXTRA_HOSTS`/`EXTRA_ENV` entries appear in the launched container exactly as
  declared, and only for the profile that declares them.
- AC7. With a running container, `ai-terminal <profile>` attaches a second shell;
  with no running container it exits non-zero with a clear message.
- AC8. `ai-list` prints every profile in `profiles/` with name, image, and
  workspace, aligned; an absent profile dir exits non-zero.
- AC9. Each retained legacy script name (e.g. `launch-esp32-workspace`,
  `update-codex-uxplay-image`) invokes the corresponding generic command and
  produces equivalent behaviour to the original.
- AC10. A `.desktop` entry launches a sandbox via a `launchers/` wrapper on KDE,
  and the running container appears in Podman Desktop.
- AC11. When `ENV_FILE` is defined and present (mode `600`), its variables are
  available inside the container; when not defined, no host secret files are
  mounted.
- AC12. `ai-doctor <profile>` reports per-check pass/fail covering at least: image
  exists, workspace exists, Podman rootless, profile valid, and secret-file
  permissions.
- AC13. A plain-text build request naming a language + at least one OS/arch/device
  target yields a selected/generated profile and image plan; a request with a
  conflicting or costly path returns those conflicts to the user instead of
  proceeding silently.
- AC14. The framework can be cloned to a second Bazzite host from a repository
  and, after adding profiles, run `ai-build`/`ai-launch` successfully, with no
  secrets present in the repository.

## Resolved Questions

- OQ1. **Scope of first release.** Which capabilities are in the initial release
  versus deferred? The product doc marks network modes, secrets, `ai-doctor`,
  `ai-new`, policy levels, desktop-install, and packaging as "future." Confirm the
  MVP cut (suggest: `ai-build`/`ai-launch`/`ai-terminal`/`ai-list` + profiles +
  safety policy + compat wrappers).

**Response** The MVP is the abilty to build an isolated dev container and place the requested tools, libraries, etc in there for the user to make use of no matter the agent they have chosen.
  
- OQ2. **Request-driven builder (R16) ownership.** This is qualitatively larger
  than the launcher scripts (it implies a knowledge base of base images,
  toolchains, and cost/conflict heuristics, and likely an AI agent itself). Should
  it be split into its own lineage/epic rather than bundled here? What is the
  interface — a new `ai-` command, or an agent prompt?

**Response** The tool will need to make use of an AI agent such as codex/codex/gemini/chatgpt/google in order to obtain a minimum set of requirements including the base container - ie fedora/latest
  
- OQ3. **Conflict/cost detection (R16.3).** What defines "non-optimal" or "highly
  costly"? Is there a concrete rubric (e.g. native vs cross-compile vs QEMU
  emulation, image size, build time) the framework should encode?

**Response** Difficult - if the tool is, for instance, python then difficulty is relatively low for portability. The more platforms and low lever the language the higher the complexity gets. We will have to hand this assessment off to an agent to evaluate.
  
- OQ4. **Missing `ENV_FILE` behaviour (R7.2).** Warn-and-continue, or hard-fail?

**Response** Warn

- OQ5. **`label=disable` trade-off.** Is disabling SELinux labelling acceptable as
  the standing default, or should a stricter `:Z`-only profile variant be offered
  for users who want labelling enforced?

**Response** yes but make the offer
  
- OQ6. **Hardened/no-network as default for review.** Should an explicit
  `review`/`hardware` policy level (R15) ship in v1, or remain env-var driven?

**Response** network is required - user will need to be asked about hardware, such as USB access
  
- OQ7. **Multi-target images (R16.4).** For a request spanning two OS/arch
  targets, is the expectation one multi-arch image, two separate profiles, or a
  user choice surfaced at request time?

**Response** user choice surfaced at erquest time.
  
- OQ8. **Username / `mrnobody` hardcoding.** The product doc's `.desktop` examples
  hardcode `/var/home/mrnobody/...`. Should generated artifacts derive the path
  from `$HOME`/`CODEX_JAILS_DIR` to stay portable?

**Response** yes
  
- OQ9. **Container lifecycle.** Normal launches use `--rm`; is any persistent or
  named-but-stopped container workflow needed, or is workspace-persisted state
  sufficient?

**Response** Yes, persistence is required as these are ongoing dev and build environments provide safety from AI breaking out or supplychain compromise breakouts.
  
- OQ10. **Testing strategy.** How are these scripts verified in CI given they
  require rootless Podman and hardware devices? Mock Podman, a Podman-in-CI
  runner, or manual acceptance on a Bazzite host?

**Response** Manual acceptance - BUT we will import them and launch them with podman out of /home/mrnobody/codex-jails/podman-plugin-workspace - this gives the ability to move from one contained environment to another without needing to break out of any of the containers.
