# AI Agent Podman Sandbox Framework — Reference Documentation

A rootless-Podman sandbox framework for running AI coding agents in isolated,
persistent containers on Bazzite / Fedora Atomic desktops.

**Version:** v1  
**Target platform:** Bazzite / Fedora Atomic with rootless Podman  
**Requirements artifact:** `lifecycle/requirements/ai-agent-podman-sandbox-5.md`

---

## Contents

1. [Overview](#1-overview)
2. [Prerequisites](#2-prerequisites)
3. [Installation](#3-installation)
4. [Quick Start](#4-quick-start)
5. [Profiles](#5-profiles)
6. [Command Reference](#6-command-reference)
   - [ai-build](#61-ai-build)
   - [ai-launch](#62-ai-launch)
   - [ai-terminal](#63-ai-terminal)
   - [ai-list](#64-ai-list)
7. [Launch Modes](#7-launch-modes)
8. [Persistence Model](#8-persistence-model)
9. [Stale-Image Reconciliation](#9-stale-image-reconciliation)
10. [Safety Policy](#10-safety-policy)
11. [Network Policy](#11-network-policy)
12. [SELinux Configuration](#12-selinux-configuration)
13. [Secrets and SSH](#13-secrets-and-ssh)
14. [Desktop Integration](#14-desktop-integration)
15. [Compatibility Wrappers](#15-compatibility-wrappers)
16. [Framework Self-Hosting](#16-framework-self-hosting)
17. [Deferred Features (Post-v1)](#17-deferred-features-post-v1)
18. [Acceptance Criteria Reference](#18-acceptance-criteria-reference)

---

## 1. Overview

### Problem

AI coding agents — Codex, Aider, OpenCode — run against project
workspaces on a Bazzite desktop using rootless Podman. The previous approach
used one hand-written launch script per project. Every script was a copy of the
same sound pattern (`--userns=keep-id`, `--security-opt no-new-privileges`, a
narrow workspace mount), but because the pattern was duplicated per project,
the safety policy had drifted: scripts hardcoded slightly different values, the
privileged builder path was not cleanly separated from the normal path, and
there was no single authoritative definition of what "safe by default" meant.
Adding a project meant cloning and editing multiple scripts.

### Solution

This framework replaces per-project scripts with a small set of **generic
commands** (`ai-build`, `ai-launch`, `ai-terminal`, `ai-list`) that source
per-project **profile files** (`profiles/<name>.env`). The safety policy is
defined once and applied consistently to every normal-mode sandbox. The higher-
risk builder path is explicit and opt-in. Persistent containers survive exit
so ongoing build state is retained.

### Design Goals

| Goal | v1 approach |
|------|-------------|
| Eliminate script drift | One authoritative safety policy; profiles declare only project-specific values |
| Persistent dev state | Named containers that survive `exit`; workspace persists |
| Explicit privilege escalation | `--privileged` only via `ai-launch <profile> builder`; ephemeral by default |
| Muscle-memory preservation | Existing script names become thin compatibility wrappers |
| Single host-user scope | Rootless Podman, no daemon, no Kubernetes |
| Framework self-hosting | Framework repo usable from inside a sandbox workspace |

### Non-Goals (v1)

- Maximum container security or multi-tenant hardened boundaries.
- Kubernetes, orchestration, or any daemon beyond rootless Podman.
- Remote or CI execution; scope is a single user's local desktop.
- Rootful Podman or non-Fedora/Bazzite hosts.
- Nested child-container launching from inside a sandbox (Deferred D7).

---

## 2. Prerequisites

- **OS:** Bazzite or another Fedora Atomic desktop
- **Container runtime:** rootless Podman (verify: `podman info | grep -i rootless`)
- **Optional:** Podman Desktop for container lifecycle management
- **Shell:** Bash 5+ (`set -euo pipefail` used throughout)
- **Network:** `slirp4netns` for container networking (default; typically installed with Podman)

---

## 3. Installation

### Directory layout

The framework lives under a single base directory. The default is
`~/codex-jails`; override by setting `AI_PODMAN_JAILS_DIR` before sourcing your
shell profile.

```
$AI_PODMAN_JAILS_DIR/
├── bin/                  Generic commands (ai-build, ai-launch, ai-terminal, ai-list)
├── lib/                  Shared sourced libraries (common.sh, profile.sh, policy.sh, …)
├── profiles/             Per-project profile files (<name>.env)
├── launchers/            Optional desktop / Podman Desktop launcher wrappers
├── <name>-workspace/     Project workspaces (one per profile)
├── <name>-image/         Containerfile directories (one per profile)
└── docs/                 This documentation
```

Project workspaces and image directories sit alongside the framework
directories, not inside them. The structure is flat by design so paths are
easy to derive and audit.

### Create the base directories

```bash
export AI_PODMAN_JAILS_DIR="${AI_PODMAN_JAILS_DIR:-$HOME/codex-jails}"

mkdir -p \
  "$AI_PODMAN_JAILS_DIR/bin" \
  "$AI_PODMAN_JAILS_DIR/profiles" \
  "$AI_PODMAN_JAILS_DIR/launchers"
```

### Add `bin/` to PATH

Add both lines to `~/.bashrc` (or `~/.zshrc`):

```bash
export AI_PODMAN_JAILS_DIR="${AI_PODMAN_JAILS_DIR:-$HOME/codex-jails}"
export PATH="${AI_PODMAN_JAILS_DIR}/bin:${PATH}"
```

If `AI_PODMAN_JAILS_DIR` is not set at all, each command falls back to deriving the
base directory from its own location (`BASH_SOURCE`), so the framework is
self-hosting from any path without requiring the variable to be set.

### Install the commands

Clone or copy the framework into `$AI_PODMAN_JAILS_DIR` and mark the commands
executable:

```bash
chmod +x "$AI_PODMAN_JAILS_DIR/bin/ai-build" \
         "$AI_PODMAN_JAILS_DIR/bin/ai-launch" \
         "$AI_PODMAN_JAILS_DIR/bin/ai-terminal" \
         "$AI_PODMAN_JAILS_DIR/bin/ai-list"
```

---

## 4. Quick Start

```bash
# 1. Create a profile for your project (see Section 5)
#    profiles/myproject.env

# 2. Create a Containerfile in the image directory
#    myproject-image/Containerfile

# 3. Build the container image
ai-build myproject

# 4. Launch a persistent interactive shell
ai-launch myproject

# (From a second terminal while the container is running)
ai-terminal myproject

# 5. List all profiles and container states
ai-list
```

---

## 5. Profiles

A profile is a Bash fragment (`.env` file) sourced by every framework command.
The filename, without `.env`, is the profile name passed to `ai-build`,
`ai-launch`, and `ai-terminal`.

Profiles live in `$AI_PODMAN_JAILS_DIR/profiles/`. A missing or malformed profile
— absent file or missing required field — exits non-zero with a clear,
actionable message.

**Important:** Profiles MUST NOT contain secrets. Secret material belongs in a
separate file referenced by `ENV_FILE`. See [Section 13](#13-secrets-and-ssh).

For full profile reference and examples, see [profiles.md](profiles.md).

### Required fields

| Field | Description |
|-------|-------------|
| `PROFILE_NAME` | Display name; should match the filename. |
| `CONTAINER_NAME` | Name of the persistent Podman container. |
| `IMAGE_NAME` | Name of the container image built by `ai-build`. |
| `IMAGE_DIR` | Directory containing the `Containerfile` / `Dockerfile`. |
| `WORKSPACE` | Host path to the project workspace; bind-mounted at `/workspace`. |
| `CONTAINER_HOME` | Host path used as the container's `HOME` directory. |
| `BASHRC` | Path to the `.bashrc` sourced inside the container. |
| `WORKDIR` | Working directory inside the container (typically `/workspace`). |
| `BUILD_ARGS` | Extra `podman build` arguments as a Bash array; use `()` for none. |

All paths MUST use `$AI_PODMAN_JAILS_DIR` or `$HOME` — never hard-coded usernames
or `/var/home/<user>` paths.

### Optional fields

| Field | Type | Description |
|-------|------|-------------|
| `SELINUX_MODE` | string | `disable` (default) or `enforce`. See [Section 12](#12-selinux-configuration). |
| `NETWORK_MODE` | string | Podman network mode. Default: `slirp4netns`. |
| `ENV_FILE` | string | Path to a secrets env file (must be mode `600`). |
| `POST_BUILD_CHECK` | string | Shell command run inside the image after `ai-build`. |
| `EXTRA_ENV` | array | Extra `-e KEY=VALUE` pairs, e.g. `("-e" "FOO=bar")`. |
| `EXTRA_VOLUMES` | array | Extra `-v` flags, e.g. `("-v" "$HOME/cache:/cache:Z")`. |
| `EXTRA_DEVICES` | array | Extra `--device` flags, e.g. `("--device=/dev/ttyUSB0")`. |
| `EXTRA_HOSTS` | array | Extra `--add-host` flags, e.g. `("--add-host" "host:1.2.3.4")`. |
| `EXTRA_RUN_ARGS` | array | Arbitrary extra arguments appended to `podman run`. |
| `PNPM_HOME` | string | Path for pnpm's home directory (created at launch if set). |
| `HISTFILE` | string | Path to the in-container bash history file. |

### Minimal profile example

```bash
# profiles/myproject.env
PROFILE_NAME="myproject"
CONTAINER_NAME="codex-myproject"
IMAGE_NAME="codex-myproject-image"
IMAGE_DIR="${AI_PODMAN_JAILS_DIR}/myproject-image"
WORKSPACE="${AI_PODMAN_JAILS_DIR}/myproject-workspace"
CONTAINER_HOME="${AI_PODMAN_JAILS_DIR}/myproject-home"
BASHRC="${WORKSPACE}/.bashrc"
WORKDIR="/workspace"
BUILD_ARGS=()
```

### Full profile example (ESP32 embedded development)

```bash
# profiles/esp32.env
PROFILE_NAME="esp32"
CONTAINER_NAME="codex-esp32"
IMAGE_NAME="codex-esp32-image"
IMAGE_DIR="${AI_PODMAN_JAILS_DIR}/esp32-image"
WORKSPACE="${AI_PODMAN_JAILS_DIR}/esp32-workspace"
CONTAINER_HOME="${AI_PODMAN_JAILS_DIR}/esp32-home"
BASHRC="${WORKSPACE}/.bashrc"
WORKDIR="/workspace"
BUILD_ARGS=("--no-cache" "--pull")

SELINUX_MODE="disable"
NETWORK_MODE="slirp4netns"
ENV_FILE="${AI_PODMAN_JAILS_DIR}/esp32-secrets.env"

EXTRA_DEVICES=("--device=/dev/ttyUSB0")
EXTRA_HOSTS=("--add-host" "registry.example.internal:192.168.1.10")
EXTRA_ENV=("-e" "PLATFORMIO_CORE_DIR=/workspace/.platformio")
EXTRA_VOLUMES=()
EXTRA_RUN_ARGS=()

POST_BUILD_CHECK='
echo "xtensa-esp32-elf-gcc: $(xtensa-esp32-elf-gcc --version | head -n1)"
echo "idf.py:               $(idf.py --version 2>/dev/null || echo "not found")"
echo "codex:                $(codex --version)"
'
```

### Creating a new profile

1. Copy an existing `.env.example` to `profiles/<name>.env`.
2. Set all required fields using `$AI_PODMAN_JAILS_DIR`-based paths.
3. Create `<name>-image/` with a `Containerfile`.
4. Build: `ai-build <name>`.
5. Launch: `ai-launch <name>`.

---

## 6. Command Reference

All commands:
- Run with POSIX/Bash and `set -euo pipefail`.
- Accept `-h` / `--help` (and print usage on no-argument invocation).
- Exit non-zero on error with a clear, actionable message.
- Derive the base directory from `$AI_PODMAN_JAILS_DIR`, falling back to the
  script's own location if the variable is unset.

### 6.1 `ai-build`

Build or rebuild the container image for a profile.

**Synopsis**

```
ai-build <profile>
ai-build -h | --help
```

**What it does**

1. Sources `profiles/<profile>.env` and validates required fields.
2. Verifies that `IMAGE_DIR` exists.
3. Changes to `IMAGE_DIR` and runs `podman build ${BUILD_ARGS[@]}`.
4. On success, runs `POST_BUILD_CHECK` inside the new image to print installed
   tool and library versions — confirming that the requested tools are present.

**Important constraints**

- `ai-build` NEVER touches, stops, or removes an existing persistent container.
  It builds or rebuilds the image only.
- Staleness of existing containers is detected at launch time (see
  [Section 9](#9-stale-image-reconciliation)), not by `ai-build`.
- Durable dependency changes must be promoted into the `Containerfile`. Work
  done only inside a running container is not preserved through a rebuild.

**Errors**

| Condition | Exit code | Message |
|-----------|-----------|---------|
| Profile not found | 1 | `Profile not found: $PROFILE_FILE` |
| `IMAGE_DIR` not found | 1 | `Image directory not found: $IMAGE_DIR` |
| `podman build` failure | non-zero | Podman's own error output |
| Missing required field | 1 | `Profile $PROFILE is missing required field: <FIELD>` |

**Examples**

```bash
ai-build esp32
ai-build uxplay
ai-build myproject --help
```

---

### 6.2 `ai-launch`

Start or reuse the persistent container for a profile, optionally specifying a
launch mode.

**Synopsis**

```
ai-launch <profile> [<mode>] [<flags>]
ai-launch -h | --help
```

**Positional arguments**

| Argument | Description |
|----------|-------------|
| `<profile>` | Name of the profile (filename without `.env`). Required. |
| `<mode>` | Launch mode. Default: `shell`. See [Section 7](#7-launch-modes). |

**Flags**

| Flag | Description |
|------|-------------|
| `--yes` / `--non-interactive` | Never prompt; on stale-image detection, warn and continue. Does **not** mean recreate. |
| `--recreate` | Remove and recreate the persistent container from the current image. Workspace and `CONTAINER_HOME` are preserved. |
| `--no-recreate` | Explicitly continue using the existing container, even if stale. |
| `--reset` | Stop (if running) and remove the persistent container; a subsequent `ai-launch` recreates it. Workspace, `CONTAINER_HOME`, profile, image directory, and secrets are untouched. |
| `-h` / `--help` | Print usage and exit. |

**What it does**

1. Sources and validates the profile.
2. Ensures workspace, `CONTAINER_HOME`, pnpm home (if `PNPM_HOME` is set), and
   `.bash_history` paths exist on the host.
3. Checks whether a persistent container for this profile already exists:
   - **Exists and running:** attaches via `podman exec`.
   - **Exists but stopped:** starts it, then attaches.
   - **Does not exist:** creates a new container.
4. Before attaching, prints a summary of the active policy (see below).
5. Applies the [safety policy](#10-safety-policy) for all normal modes.

**Pre-launch summary**

Every `ai-launch` invocation echoes the active configuration before entering the
container, so the policy in effect is always visible:

```
Profile:         esp32
Container:       codex-esp32
Image:           codex-esp32-image
Workspace:       /home/user/codex-jails/esp32-workspace
Container HOME:  /home/user/codex-jails/esp32-home
Mode:            codex
Network:         slirp4netns
SELinux mode:    disable
Status:          reusing existing container
```

**Errors**

| Condition | Exit code | Message |
|-----------|-----------|---------|
| Profile not found | 1 | `Profile not found: $PROFILE_FILE` |
| Missing required field | 1 | `Profile $PROFILE is missing required field: <FIELD>` |
| Unknown mode | 1 | `Unknown mode: <mode>` + usage |
| `--reset` without `--yes` (non-interactive, running container) | 1 | `Container is running. Pass --yes to confirm stop and reset.` |

**Examples**

```bash
# Interactive shell (default)
ai-launch esp32

# Named agent modes
ai-launch esp32 codex
ai-launch uxplay codex

# Privileged builder (ephemeral)
ai-launch uxplay builder

# Non-interactive (for launchers, cron, scripts)
ai-launch esp32 --non-interactive

# Recreate the container from the current image
ai-launch esp32 --recreate

# Reset (remove container; next launch recreates it)
ai-launch esp32 --reset
ai-launch esp32 --reset --yes   # non-interactive, running container

# Offline sandbox (no network access)
NETWORK_MODE=none ai-launch esp32 codex
```

---

### 6.3 `ai-terminal`

Attach an additional interactive shell to a running container.

**Synopsis**

```
ai-terminal <profile>
ai-terminal -h | --help
```

**What it does**

1. Sources and validates the profile.
2. Checks whether the container is running.
3. Runs `podman exec -it <CONTAINER_NAME> bash`.

**When to use**

Use `ai-terminal` when you already have a container running via `ai-launch`
and want a second terminal window — for example, to monitor logs, inspect the
filesystem, or run a parallel task alongside the agent.

**Errors**

| Condition | Exit code | Message |
|-----------|-----------|---------|
| Profile not found | 1 | `Profile not found: $PROFILE_FILE` |
| Container not running | 1 | `Container is not running: $CONTAINER_NAME` (hint: run `ai-launch <profile>` first) |

**Example**

```bash
# Terminal 1: launch the agent
ai-launch esp32 codex

# Terminal 2: attach a monitoring shell
ai-terminal esp32
```

---

### 6.4 `ai-list`

List all profiles and the state of their persistent containers.

**Synopsis**

```
ai-list
ai-list -h | --help
```

**What it does**

Reads `profiles/*.env` and prints, per profile, aligned columns showing:

- Profile name
- Image name
- Workspace path
- Persistent container state (`running`, `stopped`, `absent`)

**Example output**

```
PROFILE      IMAGE                     WORKSPACE                              CONTAINER STATE
esp32        codex-esp32-image         /home/user/codex-jails/esp32-workspace  running
uxplay       codex-uxplay-image        /home/user/codex-jails/uxplay-workspace stopped
```

**Errors**

| Condition | Exit code | Message |
|-----------|-----------|---------|
| Profile directory absent | 1 | `No profile directory found: $PROFILE_DIR` |

---

## 7. Launch Modes

The `<mode>` argument to `ai-launch` selects what runs inside the container.
All modes except `builder` use the standard [safety policy](#10-safety-policy).

| Mode | Alias | Command run inside container | Notes |
|------|-------|------------------------------|-------|
| `shell` | `bash` | `bash --rcfile $BASHRC -i` | Default interactive shell. |
| `codex` | — | `bash -lc "cd '$WORKDIR' && codex"` | Runs the Codex AI coding agent. |
| `codex` | — | `bash -lc "cd '$WORKDIR' && codex"` | Runs Codex. |
| `builder` | — | `bash --rcfile $BASHRC -i` | **Privileged, ephemeral.** See below. |

Additional agent modes (`aider`, `opencode`, `ollama-shell`, …) can be added
without changing the safety core.

### Builder mode

Builder mode is the single privileged path in the framework. Use it for
operations that require raw device access — firmware flashing, kernel modules,
Flatpak building.

Key differences from normal mode:

| Property | Normal mode | Builder mode |
|----------|-------------|--------------|
| Container name | `$CONTAINER_NAME` | `$CONTAINER_NAME-builder` |
| Privilege | — | `--privileged` |
| Persistence | Named, persistent (`--rm` never used) | **Ephemeral** (`--rm`); removed on exit |
| Activation | Default | Explicit: `ai-launch <profile> builder` |
| Safety flags | Full policy (R5) | `label=disable`; workspace mount retained |

Because builder containers are ephemeral, a compromised or broken builder
session cannot linger. Build artifacts persist through the workspace bind mount.

**Never rely on a builder container surviving across sessions.** If you need
a resumable build cache, store it in the mounted workspace directory.

---

## 8. Persistence Model

Normal-mode containers are **named and persistent** — they are not removed when
you exit the shell or agent session. This is the single most important
behavioural difference from the previous hand-written scripts (which used
`--rm`).

### What persists

| What | Where | Persists across |
|------|-------|-----------------|
| Project source files | `$WORKSPACE` (the bind mount) | Container exit, recreate, reset |
| In-container HOME (shell history, editor state, tool config) | `$CONTAINER_HOME` (bind-mounted into the container) | Container exit, recreate, reset |
| Installed packages, build caches in the image | The container image | Exit; **lost on image rebuild unless promoted into Containerfile** |
| Container writable layer (ad-hoc changes not in Containerfile) | The container itself | Exit; **lost on `--reset` or `--recreate`** |

### Container lifecycle

```
ai-build <profile>          → builds or rebuilds the image
ai-launch <profile>         → creates container (first time) or reuses it
                              exit the shell → container stops, is NOT removed
ai-launch <profile>         → starts and reattaches the existing container
ai-launch <profile> --reset → removes the container; next launch recreates it
                              (workspace and CONTAINER_HOME are always kept)
```

### Why persistence matters for AI agents

Persistent containers give AI agents a stable, reproducible environment:

- **Shell history** survives across sessions so the agent can learn from past
  commands.
- **Incremental build caches** (Rust's `target/`, Node's `node_modules/`, ESP-IDF
  components) survive across sessions, making repeated builds fast.
- **Containment** is preserved: if a session is compromised, the damage is
  limited to the container's writable layer and the workspace. Reset and recreate
  are always available.

---

## 9. Stale-Image Reconciliation

When `ai-build` rebuilds an image, existing persistent containers still run the
old image. `ai-launch` detects this automatically on every invocation.

### Detection

At launch time, `ai-launch` compares:

- **Container's source image ID** — the image ID the container was created from:
  ```bash
  podman inspect --format '{{.Image}}' "$CONTAINER_NAME"
  ```
- **Current local image ID** — the image ID now tagged as `$IMAGE_NAME`:
  ```bash
  podman image inspect --format '{{.Id}}' "$IMAGE_NAME"
  ```

If both exist and differ, the container is **stale**.

No framework-maintained state file is needed; Podman itself records the
container's source image.

### Interactive behaviour

| Situation | Behaviour |
|-----------|-----------|
| Stale + interactive (stdin and stdout are terminals) | Warns and offers three choices: continue / recreate / cancel |
| Stale + `--yes` or `--non-interactive` | Warns and **continues** with the existing container |
| Stale + `--recreate` | Recreates from the current image, preserving workspace and `CONTAINER_HOME` |
| Stale + `--no-recreate` | Continues with the existing container without prompting |
| Non-stale | Proceeds normally, no prompt |

**`--yes` means "continue safely" — it does not mean "recreate".** The safe
non-interactive default is always to keep the existing container. Mutation
requires an explicit flag.

### Applying a rebuilt image

```bash
# 1. Rebuild the image
ai-build esp32

# 2a. Interactive: ai-launch will prompt with continue/recreate/cancel
ai-launch esp32

# 2b. Scripted: recreate explicitly, preserving workspace
ai-launch esp32 --recreate

# 2c. Scripted: continue with existing container (defer migration)
ai-launch esp32 --yes
```

---

## 10. Safety Policy

The safety policy is defined once and applied to every normal-mode sandbox.
No profile and no caller can remove these flags.

For detailed rationale, see [security-model.md](security-model.md).

### Normal-mode flags (always applied)

| Flag | Effect |
|------|--------|
| `--userns=keep-id` | Maps host UID/GID into the container; no root inside |
| `--group-add keep-groups` | Preserves supplementary groups (e.g. `dialout` for USB) |
| `--security-opt no-new-privileges` | Prevents privilege escalation via setuid/setcap |
| `--network slirp4netns` (default) | User-space NAT; container cannot reach host services |
| `-v $WORKSPACE:/workspace:Z` | Exactly one bind mount — the project workspace |
| `-e HOME=$CONTAINER_HOME` | Container HOME is a contained directory, not the host HOME |

### What is never mounted in normal mode

- Host `$HOME`
- `~/.ssh`, `~/.gnupg`, `~/.config`
- `/` (the root filesystem)
- The Docker socket (`/var/run/docker.sock`)
- The Podman socket (`/run/user/$UID/podman/podman.sock`)
- Any device not listed in the profile's `EXTRA_DEVICES`

### Builder mode

`--privileged` is permitted only in builder mode, activated explicitly with
`ai-launch <profile> builder`. It is never the default for any profile or mode.

### Profile-level extensions (`EXTRA_*`)

Profiles may extend normal mode with:

- `EXTRA_DEVICES` — specific device nodes (e.g. `/dev/ttyUSB0` for a
  microcontroller programmer)
- `EXTRA_HOSTS` — additional `/etc/hosts` entries
- `EXTRA_ENV` — additional environment variables
- `EXTRA_VOLUMES` — additional bind mounts
- `EXTRA_RUN_ARGS` — any other `podman run` arguments

These extensions are applied after the fixed safety flags; they cannot override
the core policy.

---

## 11. Network Policy

| Mode | `--network` value | Container can reach internet? |
|------|-------------------|-------------------------------|
| Default | `slirp4netns` | Yes (user-space NAT) |
| Offline | `none` | No |

Set `NETWORK_MODE` in the profile for a persistent per-project default, or
override per-invocation:

```bash
# Offline sandbox for reviewing local code without network access
NETWORK_MODE=none ai-launch esp32 codex

# Explicit default (same as omitting the flag)
NETWORK_MODE=slirp4netns ai-launch esp32 codex
```

The active network mode is echoed in the pre-launch summary.

---

## 12. SELinux Configuration

The framework offers two SELinux modes, selectable per profile via
`SELINUX_MODE`. See [selinux.md](selinux.md) for full rationale.

| `SELINUX_MODE` | Flag added to `podman run` | Best for |
|----------------|--------------------------|---------|
| `disable` (default) | `--security-opt label=disable` | Large dev workspaces; Bazzite desktop use |
| `enforce` | *(none; relies on `:Z` relabelling)* | Stricter SELinux policy compliance |

The default (`disable`) is a deliberate trade-off: Bazzite dev workspaces
contain many files with mixed SELinux labels. Relabelling large trees via `:Z`
on every `podman run` can take minutes. `label=disable` preserves all other
safety controls while eliminating labelling friction.

Set `SELINUX_MODE=enforce` in a profile to opt into stricter label enforcement:

```bash
# In profiles/myproject.env
SELINUX_MODE=enforce
```

Both modes retain `--userns=keep-id`, `no-new-privileges`, user-space
networking, and the narrow workspace bind mount. The SELinux mode affects only
label enforcement.

---

## 13. Secrets and SSH

For full details and recipes, see [secrets-and-ssh.md](secrets-and-ssh.md).

### Secrets via `ENV_FILE`

Set `ENV_FILE` in a profile to inject secrets into the container at launch:

```bash
ENV_FILE="${AI_PODMAN_JAILS_DIR}/esp32-secrets.env"
```

Rules:
- The file must be mode `600` (`chmod 600 "$ENV_FILE"`).
- The file must never be committed to Git. Add `*-secrets.env` to `.gitignore`.
- If `ENV_FILE` is set but the file is absent, `ai-launch` **warns and
  continues** — the container launches without the secrets rather than aborting.
- Profiles themselves must not contain secrets.

### SSH strategy

Host `~/.ssh` is never mounted into any container. Instead, generate a
dedicated key **inside the container** for scoped Git access:

```bash
# Inside the container:
ssh-keygen -t ed25519 -C "ai-agent@$(hostname)" -f ~/.ssh/id_ed25519_agent
```

Add the public key to your Git hosting service as a **deploy key** scoped to
the specific repository. Because `CONTAINER_HOME` is a host directory, the key
persists across container recreations.

---

## 14. Desktop Integration

See [desktop-integration.md](desktop-integration.md) for full examples.

### Launcher scripts

`launchers/<name>-<mode>` scripts call `ai-launch` with `--non-interactive`,
so they never block behind a hidden prompt:

```bash
#!/usr/bin/env bash
exec "${AI_PODMAN_JAILS_DIR}/bin/ai-launch" esp32 codex --non-interactive
```

### `.desktop` entries

`.desktop` files go in `~/.local/share/applications/`. All paths must use
`$HOME` or `$AI_PODMAN_JAILS_DIR` — no hard-coded usernames or `/var/home/<user>`
paths.

**KDE (Konsole):**

```ini
[Desktop Entry]
Version=1.0
Type=Application
Name=ESP32 Codex Sandbox
Exec=konsole --noclose -e bash -c '${HOME}/codex-jails/launchers/esp32-codex'
Icon=utilities-terminal
Categories=Development;
```

**GNOME (kgx):**

```ini
[Desktop Entry]
Version=1.0
Type=Application
Name=ESP32 Codex Sandbox
Exec=kgx -- bash -c '${HOME}/codex-jails/launchers/esp32-codex'
Icon=utilities-terminal
Categories=Development;
```

After creating or editing `.desktop` files, refresh the database:

```bash
update-desktop-database ~/.local/share/applications 2>/dev/null || true
```

### Podman Desktop

Persistent containers launched by `ai-launch` appear in Podman Desktop under
**Containers**. From there you can start, stop, inspect, and remove them.

Builder-mode containers are ephemeral (`--rm`) and do not appear in Podman
Desktop after they exit.

Automatic `.desktop` generation from profiles is deferred (see
[Section 17](#17-deferred-features-post-v1), D4).

---

## 15. Compatibility Wrappers

Existing script names are retained as thin wrappers that delegate to the
new generic commands with fixed arguments. This preserves muscle memory while
centralising all launch logic.

| Legacy script | Delegates to |
|---------------|-------------|
| `launch-esp32-workspace` | `ai-launch esp32 shell` |
| `short-launch-esp32-workspace` | `ai-launch esp32 shell` |
| `launch-uxplay-workspace` | `ai-launch uxplay shell` |
| `launch-uxplay-builder` | `ai-launch uxplay builder` |
| `extra-terminal` | `ai-terminal esp32` |
| `update-codex-esp32-image` | `ai-build esp32` |
| `update-codex-uxplay-image` | `ai-build uxplay` |

Wrapper template:

```bash
#!/usr/bin/env bash
exec "${AI_PODMAN_JAILS_DIR:-$HOME/codex-jails}/bin/ai-launch" esp32 shell "$@"
```

Wrappers inherit the persistence change (R4.2): containers launched via
wrappers are now persistent. This is the only behavioural change from the
original scripts.

---

## 16. Framework Self-Hosting

The framework repository is designed to be usable from inside an ordinary
sandbox workspace. For example, `$AI_PODMAN_JAILS_DIR/podman-plugin-workspace`
can be used to develop, edit, lint, and review the framework itself without
exposing the full host environment.

This works because:

1. All paths are derived from `$AI_PODMAN_JAILS_DIR` or from `BASH_SOURCE` — no
   hardcoded host paths or usernames.
2. The framework files (Bash scripts, profiles, docs) are plain text; they can
   be read, edited, and reviewed inside any sandbox with a text editor.
3. The framework does not assume it is running on the bare host.

**What self-hosting does not mean:** sandboxes cannot launch child Podman
containers. Nested rootless Podman, Podman socket access, and child-sandbox
launching are out of scope for v1 (see D7 below).

---

## 17. Deferred Features (Post-v1)

These features are part of the product vision but are explicitly outside the
v1 acceptance gate. They are recorded here so the roadmap is visible.

### D1. `ai-doctor` health check

`ai-doctor <profile>` reports pass/fail per check:
- Image exists
- Workspace exists
- Persistent container present and in expected state
- Required binaries present in the image
- Declared serial/hardware devices exist on the host
- Podman is running rootless
- Secret env file mode is `600`
- Profile syntax is valid

`ai-doctor <profile> --cleanup` is the canonical teardown flow: always
user-initiated; gated by a git-protection check of the mounted workspace
(detects uncommitted or untracked changes before offering removal). Age-based
GC is advisory only — reports stale stopped containers; never auto-removes.

### D2. `ai-new` project generator

`ai-new <name>` scaffolds `profiles/<name>.env`, `<name>-workspace/`,
`<name>-image/`, and starter `launchers/<name>-*` files with portable
`$AI_PODMAN_JAILS_DIR`-derived paths.

### D3. Named policy levels

Auditable levels (`normal`, `no-network`, `builder`, `hardware`) bundle
corresponding run-time options. The `hardware` level requires explicit
user confirmation of device access.

### D4. Automatic desktop-entry generation

`ai-desktop-install <profile>` generates `.desktop` entries and launcher
wrappers automatically from the profile.

### D5. Packaging and repo installer

A cloneable Git repository (`bin/`, `profiles.example/`, `launchers.example/`,
`docs/`) reusable on other Bazzite systems, with secrets and real profiles
kept out of version control.

### D6. Request-driven environment builder (agent-delegated)

A plain-text target description → external AI agent derives a minimum
environment spec (base image + toolchains), surfaces conflicts and costly paths,
returns a structured spec for human review before anything executable is
applied. High-risk changes (privileged, host mounts, device passthrough) require
separate elevated confirmation. Falls back gracefully when no agent is
configured.

### D7. Nested rootless Podman child-launching

Explicitly not part of default product mode. If added later as a
`nested-builder` policy, it must not use the host Podman/Docker socket, host
network, host PID namespace, `--privileged`, or broad host mounts, and requires
a dedicated profile granting only minimum tested requirements.

---

## 18. Acceptance Criteria Reference

The following table maps v1 acceptance criteria to the sections of this
document that describe the corresponding behaviour.

| AC | Summary | Documented in |
|----|---------|---------------|
| AC1 | `ai-build` builds from profile's `IMAGE_DIR`; `POST_BUILD_CHECK` prints versions; error exits non-zero | [§6.1](#61-ai-build) |
| AC2 | Launched container config shows required safety flags and exactly one bind mount | [§10](#10-safety-policy) |
| AC3 | Container persists after exit; second launch reuses it; documented removal path | [§8](#8-persistence-model) |
| AC4 | Named agent modes (`codex`, `codex`, `bash`) start the respective agent | [§7](#7-launch-modes) |
| AC5 | Only `ai-launch <profile> builder` yields `--privileged`; no normal-mode path is privileged | [§7](#7-launch-modes), [§10](#10-safety-policy) |
| AC6 | Builder container launched with `--rm`; exits and is gone; normal container unaffected | [§7](#7-launch-modes) |
| AC7 | `NETWORK_MODE=none` produces offline container; default has working network | [§11](#11-network-policy) |
| AC8 | `EXTRA_DEVICES`, `EXTRA_HOSTS`, `EXTRA_ENV` entries appear only for declaring profile | [§5](#5-profiles), [§10](#10-safety-policy) |
| AC9 | Stricter `SELINUX_MODE=enforce` omits `label=disable`; default includes it; both documented | [§12](#12-selinux-configuration) |
| AC10 | `ai-terminal` attaches second shell to running container; exits non-zero if container not running | [§6.3](#63-ai-terminal) |
| AC11 | `ai-list` prints profile, image, workspace, container state; absent dir exits non-zero | [§6.4](#64-ai-list) |
| AC12 | Legacy script names invoke equivalent generic command and inherit persistence | [§15](#15-compatibility-wrappers) |
| AC13 | `ENV_FILE` present → injected; missing → warn and continue; undefined → no secrets mounted | [§13](#13-secrets-and-ssh) |
| AC14 | Stale-image detection: interactive prompt; `--yes` warns and continues; `--recreate` recreates | [§9](#9-stale-image-reconciliation) |
| AC15 | `--reset` removes container, preserves workspace/home/profile/image/secrets | [§6.2](#62-ai-launch) |

---

*Last updated: 2026-06-22*  
*Requirements source: `lifecycle/requirements/ai-agent-podman-sandbox-5.md`*

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
