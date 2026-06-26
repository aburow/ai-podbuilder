# AI Agent Podman Sandbox

A reusable, profile-driven development and launch environment for running AI coding agents on Bazzite with Podman, without exposing the full host machine.

This project turns a collection of simple per-project launcher scripts into a controlled product-style framework with explicit profiles, repeatable builds, predictable launch modes, and safer defaults.

---

## 1. Purpose

AI coding agents are powerful, but they should not get broad access to a workstation by default.

This framework provides a controlled sandbox model for tools such as:

- Codex
- Codex
- Aider
- OpenCode
- language-specific build tooling
- embedded development tooling
- Flatpak build environments
- project-specific agent workspaces

The intended host environment is:

- Bazzite or another Fedora-based Linux desktop
- rootless Podman
- Podman Desktop
- KDE, GNOME, or another desktop launcher environment

The design goal is not maximum container security. The design goal is a practical development sandbox that is much safer than running AI agents directly on the host.

---

## 2. Current Script Pattern

The current setup already has the right core ideas.

Existing script roles:

| Existing script | Role |
|---|---|
| `update-codex-esp32-image` | Build the ESP32 AI-agent image |
| `update-codex-uxplay-image` | Build the UXPlay AI-agent image |
| `launch-esp32-workspace` | Launch ESP32 workspace container |
| `short-launch-esp32-workspace` | Short/manual variant of ESP32 launcher |
| `launch-uxplay-workspace` | Launch UXPlay workspace container |
| `launch-uxplay-workspace.apb` | Alternate UXPlay launcher variant |
| `launch-uxplay-builder` | Launch privileged Flatpak builder container |
| `extra-terminal` | Attach another terminal to a running container |

The common pattern is good:

```bash
podman run --rm -it \
  --name codex-esp32 \
  --userns=keep-id \
  --group-add keep-groups \
  --security-opt no-new-privileges \
  --security-opt label=disable \
  -e HOME=/workspace/.home-codex-esp32 \
  -v "$HOME/codex-jails/esp32-workspace:/workspace:Z" \
  -w /workspace \
  codex-esp32-dev \
  bash --rcfile /workspace/.bashrc -i
```

The issue is not the model. The issue is drift.

Each project script hardcodes slightly different values, so over time it becomes harder to guarantee that all workspaces follow the same safety and launch policy.

---

## 3. Product Direction

The product should become a small local framework:

```text
codex-jails/
├── bin/
│   ├── ai-build
│   ├── ai-launch
│   ├── ai-terminal
│   └── ai-list
├── profiles/
│   ├── esp32.env
│   └── uxplay.env
├── launchers/
│   ├── esp32-shell
│   ├── esp32-codex
│   ├── uxplay-shell
│   └── uxplay-builder
├── codex-esp32-image/
├── codex-uxplay-image/
├── esp32-workspace/
└── uxplay-workspace/
```

The core idea:

- `bin/` contains generic product commands.
- `profiles/` contains per-project configuration.
- `launchers/` contains tiny wrappers for Podman Desktop and desktop menus.
- project workspaces stay isolated under `~/codex-jails`.
- each container gets its own fake `$HOME` inside `/workspace`.

---

## 4. Design Principles

### 4.1 Do not expose the full host

The container should not mount:

```text
$HOME
~/.ssh
~/.gnupg
~/.config
/
/var/run/docker.sock
/run/user/$UID/podman/podman.sock
```

The normal development mode should only mount the project workspace:

```bash
-v "$WORKSPACE:/workspace:Z"
```

### 4.2 Use explicit profiles

Every sandbox gets a profile file.

A profile defines:

- profile name
- image name
- container name
- image build directory
- workspace directory
- container home path
- shell startup file
- project-specific environment variables
- extra devices
- extra hosts
- extra volumes
- build arguments
- post-build checks

### 4.3 Make privileged mode explicit

Normal mode should not be privileged.

Builder mode may be privileged when necessary, for example Flatpak building, but it should be called explicitly:

```bash
ai-launch uxplay builder
```

This makes the higher-risk path visible and intentional.

### 4.4 Preserve user muscle memory

The existing script names can become compatibility wrappers.

For example:

```bash
launch-esp32-workspace
```

can simply call:

```bash
ai-launch esp32 shell
```

This allows the product to become more controlled without breaking existing workflows.

---

## 5. Installation Layout

Create the base directories:

```bash
mkdir -p \
  "$HOME/codex-jails/bin" \
  "$HOME/codex-jails/profiles" \
  "$HOME/codex-jails/launchers"
```

Add the command directory to the shell path:

```bash
export PATH="$HOME/codex-jails/bin:$PATH"
```

For persistence, add it to `~/.bashrc`, `~/.zshrc`, or the shell profile used on Bazzite.

---

## 6. Profile: ESP32

File:

```text
~/codex-jails/profiles/esp32.env
```

```bash
# shellcheck shell=bash

PROFILE_NAME="esp32"

CONTAINER_NAME="codex-esp32"
IMAGE_NAME="codex-esp32-dev"

IMAGE_DIR="$HOME/codex-jails/codex-esp32-image"
WORKSPACE="$HOME/codex-jails/esp32-workspace"

CONTAINER_HOME="/workspace/.home-codex-esp32"
BASHRC="/workspace/.bashrc"

WORKDIR="/workspace"

PNPM_HOME="$CONTAINER_HOME/.local/share/pnpm"
HISTFILE="$CONTAINER_HOME/.bash_history"

PLATFORMIO_CORE_DIR="/workspace/hagerbt2mqtt/.platformio"

EXTRA_ENV=(
  "-e" "PLATFORMIO_CORE_DIR=$PLATFORMIO_CORE_DIR"
)

EXTRA_VOLUMES=()

EXTRA_DEVICES=(
  "--device=/dev/ttyUSB0:/dev/ttyUSB0:rwm"
)

EXTRA_HOSTS=(
  "--add-host" "sin1.contabostorage.com:103.164.55.84"
)

EXTRA_RUN_ARGS=()

BUILD_ARGS=(
  "--no-cache"
  "--pull"
  "-t" "$IMAGE_NAME"
  "."
)

POST_BUILD_CHECK='
echo "codex: $(codex --version)"
echo "node:  $(node --version 2>/dev/null || true)"
echo "npm:   $(npm --version 2>/dev/null || true)"
'
```

---

## 7. Profile: UXPlay

File:

```text
~/codex-jails/profiles/uxplay.env
```

```bash
# shellcheck shell=bash

PROFILE_NAME="uxplay"

CONTAINER_NAME="codex-uxplay"
IMAGE_NAME="codex-uxplay-dev"

IMAGE_DIR="$HOME/codex-jails/codex-uxplay-image"
WORKSPACE="$HOME/codex-jails/uxplay-workspace"

CONTAINER_HOME="/workspace/.home-codex-uxplay"
BASHRC="/workspace/.home-codex-uxplay/.bashrc"

WORKDIR="/workspace"

PNPM_HOME="$CONTAINER_HOME/.local/share/pnpm"
HISTFILE="$CONTAINER_HOME/.bash_history"

EXTRA_ENV=()
EXTRA_VOLUMES=()
EXTRA_DEVICES=()

EXTRA_HOSTS=(
  "--add-host" "sin1.contabostorage.com:103.164.55.84"
)

EXTRA_RUN_ARGS=()

BUILD_ARGS=(
  "--no-cache"
  "--pull"
  "-f" "Containerfile"
  "-t" "$IMAGE_NAME"
  "."
)

POST_BUILD_CHECK='
echo "codex:           $(codex --version)"
echo "codex:          $(codex --version 2>/dev/null || true)"
echo "node:            $(node --version)"
echo "npm:             $(npm --version)"
echo "pnpm:            $(pnpm --version)"
echo "flatpak-builder: $(flatpak-builder --version 2>/dev/null || true)"
echo "flatpak:         $(flatpak --version 2>/dev/null || true)"
echo "cmake:           $(cmake --version 2>/dev/null | head -n1)"
echo "ninja:           $(ninja --version 2>/dev/null || true)"
'
```

---

## 8. Command: `ai-build`

File:

```text
~/codex-jails/bin/ai-build
```

```bash
#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  ai-build <profile>

Examples:
  ai-build esp32
  ai-build uxplay
USAGE
}

PROFILE="${1:-}"

if [[ -z "$PROFILE" || "$PROFILE" == "-h" || "$PROFILE" == "--help" ]]; then
  usage
  exit 0
fi

BASE_DIR="${CODEX_JAILS_DIR:-$HOME/codex-jails}"
PROFILE_FILE="$BASE_DIR/profiles/$PROFILE.env"

if [[ ! -f "$PROFILE_FILE" ]]; then
  echo "Profile not found: $PROFILE_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$PROFILE_FILE"

if [[ ! -d "$IMAGE_DIR" ]]; then
  echo "Image directory not found: $IMAGE_DIR" >&2
  exit 1
fi

cd "$IMAGE_DIR"

echo "Building image: $IMAGE_NAME"
echo "Image dir:      $IMAGE_DIR"
echo

podman build "${BUILD_ARGS[@]}"

echo
echo "Installed tool versions:"
podman run --rm "$IMAGE_NAME" bash -lc "$POST_BUILD_CHECK"

echo
echo "Done."
```

Make executable:

```bash
chmod +x ~/codex-jails/bin/ai-build
```

Usage:

```bash
ai-build esp32
ai-build uxplay
```

---

## 9. Command: `ai-launch`

File:

```text
~/codex-jails/bin/ai-launch
```

```bash
#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  ai-launch <profile> [mode]

Examples:
  ai-launch esp32
  ai-launch uxplay
  ai-launch uxplay builder
  ai-launch esp32 codex
  ai-launch uxplay codex
  ai-launch uxplay bash

Modes:
  shell       Start interactive bash shell. Default.
  bash        Same as shell.
  codex       Start Codex inside the sandbox.
  codex      Start Codex inside the sandbox.
  builder     Start privileged builder mode.
USAGE
}

PROFILE="${1:-}"
MODE="${2:-shell}"

if [[ -z "$PROFILE" || "$PROFILE" == "-h" || "$PROFILE" == "--help" ]]; then
  usage
  exit 0
fi

BASE_DIR="${CODEX_JAILS_DIR:-$HOME/codex-jails}"
PROFILE_FILE="$BASE_DIR/profiles/$PROFILE.env"

if [[ ! -f "$PROFILE_FILE" ]]; then
  echo "Profile not found: $PROFILE_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$PROFILE_FILE"

mkdir -p \
  "$WORKSPACE" \
  "$WORKSPACE/$(basename "$CONTAINER_HOME")" \
  "$WORKSPACE/$(basename "$CONTAINER_HOME")/.local/share/pnpm"

touch "$WORKSPACE/$(basename "$CONTAINER_HOME")/.bash_history"

RUN_ARGS=(
  "--rm"
  "-it"
  "--name" "$CONTAINER_NAME"
  "--userns=keep-id"
  "--group-add" "keep-groups"
  "--security-opt" "no-new-privileges"
  "--security-opt" "label=disable"
  "-e" "HOME=$CONTAINER_HOME"
  "-e" "PNPM_HOME=$PNPM_HOME"
  "-e" "HISTFILE=$HISTFILE"
  "-v" "$WORKSPACE:/workspace:Z"
  "-w" "$WORKDIR"
)

CMD=(bash --rcfile "$BASHRC" -i)

case "$MODE" in
  shell|bash)
    CMD=(bash --rcfile "$BASHRC" -i)
    ;;

  codex)
    CMD=(bash -lc "cd '$WORKDIR' && codex")
    ;;

  codex)
    CMD=(bash -lc "cd '$WORKDIR' && codex")
    ;;

  builder)
    RUN_ARGS=(
      "--rm"
      "-it"
      "--name" "$CONTAINER_NAME-builder"
      "--privileged"
      "--security-opt" "label=disable"
      "-e" "HOME=$CONTAINER_HOME"
      "-e" "PNPM_HOME=$PNPM_HOME"
      "-e" "HISTFILE=$HISTFILE"
      "-v" "$WORKSPACE:/workspace:Z"
      "-w" "$WORKDIR"
    )
    CMD=(bash --rcfile "$BASHRC" -i)
    ;;

  *)
    echo "Unknown mode: $MODE" >&2
    usage
    exit 1
    ;;
esac

echo "Profile:        $PROFILE_NAME"
echo "Container:      $CONTAINER_NAME"
echo "Image:          $IMAGE_NAME"
echo "Workspace:      $WORKSPACE"
echo "Container HOME: $CONTAINER_HOME"
echo "Mode:           $MODE"
echo

exec podman run \
  "${RUN_ARGS[@]}" \
  "${EXTRA_HOSTS[@]}" \
  "${EXTRA_DEVICES[@]}" \
  "${EXTRA_VOLUMES[@]}" \
  "${EXTRA_ENV[@]}" \
  "${EXTRA_RUN_ARGS[@]}" \
  "$IMAGE_NAME" \
  "${CMD[@]}"
```

Make executable:

```bash
chmod +x ~/codex-jails/bin/ai-launch
```

Usage:

```bash
ai-launch esp32
ai-launch uxplay
ai-launch uxplay builder
ai-launch esp32 codex
ai-launch uxplay codex
```

---

## 10. Command: `ai-terminal`

File:

```text
~/codex-jails/bin/ai-terminal
```

```bash
#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  ai-terminal <profile>

Examples:
  ai-terminal esp32
  ai-terminal uxplay
USAGE
}

PROFILE="${1:-}"

if [[ -z "$PROFILE" || "$PROFILE" == "-h" || "$PROFILE" == "--help" ]]; then
  usage
  exit 0
fi

BASE_DIR="${CODEX_JAILS_DIR:-$HOME/codex-jails}"
PROFILE_FILE="$BASE_DIR/profiles/$PROFILE.env"

if [[ ! -f "$PROFILE_FILE" ]]; then
  echo "Profile not found: $PROFILE_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$PROFILE_FILE"

if ! podman container exists "$CONTAINER_NAME"; then
  echo "Container is not running: $CONTAINER_NAME" >&2
  exit 1
fi

exec podman exec -it "$CONTAINER_NAME" bash
```

Make executable:

```bash
chmod +x ~/codex-jails/bin/ai-terminal
```

Usage:

```bash
ai-terminal esp32
ai-terminal uxplay
```

---

## 11. Command: `ai-list`

File:

```text
~/codex-jails/bin/ai-list
```

```bash
#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${CODEX_JAILS_DIR:-$HOME/codex-jails}"
PROFILE_DIR="$BASE_DIR/profiles"

if [[ ! -d "$PROFILE_DIR" ]]; then
  echo "No profile directory found: $PROFILE_DIR" >&2
  exit 1
fi

for file in "$PROFILE_DIR"/*.env; do
  [[ -e "$file" ]] || continue

  PROFILE_NAME=""
  IMAGE_NAME=""
  WORKSPACE=""

  # shellcheck disable=SC1090
  source "$file"

  name="$(basename "$file" .env)"
  printf '%-12s %-24s %s\n' "$name" "$IMAGE_NAME" "$WORKSPACE"
done
```

Make executable:

```bash
chmod +x ~/codex-jails/bin/ai-list
```

Usage:

```bash
ai-list
```

Example output:

```text
esp32        codex-esp32-dev          /var/home/mrnobody/codex-jails/esp32-workspace
uxplay       codex-uxplay-dev         /var/home/mrnobody/codex-jails/uxplay-workspace
```

---

## 12. Podman Desktop and Desktop Launcher Wrappers

Podman Desktop will see the running containers, but it is better to start containers through controlled wrapper scripts.

Create:

```bash
mkdir -p ~/codex-jails/launchers
```

### `~/codex-jails/launchers/esp32-shell`

```bash
#!/usr/bin/env bash
exec "$HOME/codex-jails/bin/ai-launch" esp32 shell
```

### `~/codex-jails/launchers/esp32-codex`

```bash
#!/usr/bin/env bash
exec "$HOME/codex-jails/bin/ai-launch" esp32 codex
```

### `~/codex-jails/launchers/uxplay-shell`

```bash
#!/usr/bin/env bash
exec "$HOME/codex-jails/bin/ai-launch" uxplay shell
```

### `~/codex-jails/launchers/uxplay-codex`

```bash
#!/usr/bin/env bash
exec "$HOME/codex-jails/bin/ai-launch" uxplay codex
```

### `~/codex-jails/launchers/uxplay-builder`

```bash
#!/usr/bin/env bash
exec "$HOME/codex-jails/bin/ai-launch" uxplay builder
```

Make them executable:

```bash
chmod +x ~/codex-jails/launchers/*
```

---

## 13. Bazzite Desktop Entries

Create application launcher entries under:

```text
~/.local/share/applications/
```

### ESP32 Codex Launcher

File:

```text
~/.local/share/applications/ai-esp32-codex.desktop
```

```ini
[Desktop Entry]
Type=Application
Name=AI ESP32 - Codex
Comment=Launch ESP32 Codex sandbox
Exec=konsole -e /var/home/mrnobody/codex-jails/launchers/esp32-codex
Terminal=false
Categories=Development;
```

### UXPlay Builder Launcher

File:

```text
~/.local/share/applications/ai-uxplay-builder.desktop
```

```ini
[Desktop Entry]
Type=Application
Name=AI UXPlay - Builder
Comment=Launch privileged UXPlay Flatpak builder sandbox
Exec=konsole -e /var/home/mrnobody/codex-jails/launchers/uxplay-builder
Terminal=false
Categories=Development;
```

Refresh the desktop database if available:

```bash
update-desktop-database ~/.local/share/applications 2>/dev/null || true
```

On GNOME, replace `konsole -e` with a terminal that exists on the system, for example:

```ini
Exec=kgx -- /var/home/mrnobody/codex-jails/launchers/esp32-codex
```

---

## 14. Compatibility Wrappers

The existing script names can be retained as thin wrappers.

This keeps muscle memory intact while centralising the logic.

### `launch-esp32-workspace`

```bash
#!/usr/bin/env bash
exec "$HOME/codex-jails/bin/ai-launch" esp32 shell
```

### `short-launch-esp32-workspace`

```bash
#!/usr/bin/env bash
exec "$HOME/codex-jails/bin/ai-launch" esp32 shell
```

### `launch-uxplay-workspace`

```bash
#!/usr/bin/env bash
exec "$HOME/codex-jails/bin/ai-launch" uxplay shell
```

### `launch-uxplay-builder`

```bash
#!/usr/bin/env bash
exec "$HOME/codex-jails/bin/ai-launch" uxplay builder
```

### `extra-terminal`

```bash
#!/usr/bin/env bash
exec "$HOME/codex-jails/bin/ai-terminal" esp32
```

### `update-codex-esp32-image`

```bash
#!/usr/bin/env bash
exec "$HOME/codex-jails/bin/ai-build" esp32
```

### `update-codex-uxplay-image`

```bash
#!/usr/bin/env bash
exec "$HOME/codex-jails/bin/ai-build" uxplay
```

---

## 15. Normal Safety Policy

Normal AI-agent containers should use:

```bash
--userns=keep-id
--group-add keep-groups
--security-opt no-new-privileges
--security-opt label=disable
```

Use `--security-opt label=disable` because Bazzite, SELinux labelling, and mounted development workspaces can otherwise become annoying in day-to-day development. The workspace mount still remains explicit and narrow.

Normal mode should avoid:

```bash
--privileged
-v "$HOME:/home/..."
-v /:/host
-v ~/.ssh:/home/agent/.ssh
-v ~/.gnupg:/home/agent/.gnupg
-v /run/user/$UID/podman/podman.sock:/run/user/$UID/podman/podman.sock
```

Privileged mode is allowed only as an explicit profile mode:

```bash
ai-launch uxplay builder
```

---

## 16. Optional Network Modes

A future product enhancement is network policy.

Add this to `ai-launch`:

```bash
NETWORK_MODE="${NETWORK_MODE:-slirp4netns}"
```

Then include:

```bash
"--network" "$NETWORK_MODE"
```

Normal use:

```bash
ai-launch esp32 codex
```

No-network review mode:

```bash
NETWORK_MODE=none ai-launch esp32 codex
```

This is useful when reviewing local code without allowing the agent to reach the network.

---

## 17. Optional Secret Handling

The safest default is not to mount host secrets.

For API keys, prefer a dedicated env file per sandbox or per profile.

Example future profile field:

```bash
ENV_FILE="$HOME/codex-jails/secrets/esp32.env"
```

Then add to `ai-launch` only when present:

```bash
if [[ -n "${ENV_FILE:-}" && -f "$ENV_FILE" ]]; then
  RUN_ARGS+=("--env-file" "$ENV_FILE")
fi
```

Example secret file:

```bash
OPENAI_API_KEY=
OPENAI_API_KEY=
OLLAMA_HOST=http://host.containers.internal:11434
```

Permissions:

```bash
chmod 600 ~/codex-jails/secrets/esp32.env
```

Do not put secrets into profile files if profiles will be committed to Git.

---

## 18. Optional SSH Strategy

Do not mount the host `~/.ssh` directory by default.

Instead, create a dedicated SSH key inside the sandbox home:

```bash
ai-launch esp32 shell
```

Inside the container:

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keygen -t ed25519 -C "ai-agent-esp32"
cat ~/.ssh/id_ed25519.pub
```

Add the public key to GitHub, GitLab, or the relevant Git host with limited scope.

This gives the AI-agent environment Git access without exposing the user's primary host SSH identity.

---

## 19. Future Product Enhancements

### 19.1 Project generator

Add:

```bash
ai-new <profile-name>
```

This could scaffold:

```text
profiles/<name>.env
<name>-workspace/
<name>-image/
launchers/<name>-shell
launchers/<name>-codex
```

### 19.2 Policy levels

Support policy levels such as:

```bash
AI_POLICY=normal
AI_POLICY=no-network
AI_POLICY=builder
AI_POLICY=hardware
```

This would make risk explicit and auditable.

### 19.3 Agent modes

Add modes for more agents:

```bash
ai-launch esp32 aider
ai-launch esp32 opencode
ai-launch esp32 ollama-shell
```

### 19.4 Health checks

Add:

```bash
ai-doctor esp32
```

Checks could include:

- image exists
- workspace exists
- container is running
- expected binaries are present
- serial devices exist
- Podman is rootless
- env files have safe permissions
- profile syntax is valid

### 19.5 Podman Desktop integration bundle

Add:

```bash
ai-desktop-install esp32
```

This could generate `.desktop` entries and Podman Desktop-friendly wrappers automatically.

### 19.6 Template repository

The product could become a Git repository with this structure:

```text
ai-agent-podman-sandbox/
├── README.md
├── LICENSE
├── bin/
├── profiles.example/
├── launchers.example/
├── docs/
│   ├── security-model.md
│   ├── podman-desktop.md
│   └── bazzite-notes.md
└── examples/
    ├── esp32/
    └── uxplay/
```

---

## 20. Recommended Migration Plan

### Phase 1: Centralise scripts

Create:

```text
~/codex-jails/bin/ai-build
~/codex-jails/bin/ai-launch
~/codex-jails/bin/ai-terminal
~/codex-jails/bin/ai-list
```

Create:

```text
~/codex-jails/profiles/esp32.env
~/codex-jails/profiles/uxplay.env
```

### Phase 2: Convert existing scripts to wrappers

Replace current per-project scripts with compatibility wrappers.

This preserves the current workflow while eliminating duplicated run logic.

### Phase 3: Add desktop launchers

Create controlled wrappers in:

```text
~/codex-jails/launchers/
```

Then create `.desktop` entries under:

```text
~/.local/share/applications/
```

### Phase 4: Add policy and secret handling

Add optional support for:

- no-network mode
- env files
- per-profile secrets
- explicit privileged builder mode

### Phase 5: Package as a reusable product

Turn the framework into a repository that can be cloned and reused on other Bazzite systems.

---

## 21. Core Workflow

Build an image:

```bash
ai-build esp32
```

Launch a workspace shell:

```bash
ai-launch esp32
```

Launch Codex directly:

```bash
ai-launch esp32 codex
```

Launch Codex directly:

```bash
ai-launch uxplay codex
```

Launch a privileged builder:

```bash
ai-launch uxplay builder
```

Attach another terminal:

```bash
ai-terminal esp32
```

List profiles:

```bash
ai-list
```

---

## 22. Product Summary

This framework turns one-off Podman launch scripts into a controlled AI-agent sandbox product.

It keeps the practical advantages of the current setup:

- simple Bash scripts
- no heavy orchestration
- no Kubernetes
- works naturally with Bazzite
- works naturally with Podman
- supports hardware access when explicitly requested
- supports privileged builder workflows when explicitly requested

It adds product-level structure:

- reusable command surface
- per-project profiles
- safer defaults
- lower script drift
- easier desktop integration
- clearer separation between normal, hardware, and builder modes

The result is a practical local AI-agent development environment that can grow from a personal script collection into a reusable tool.

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
