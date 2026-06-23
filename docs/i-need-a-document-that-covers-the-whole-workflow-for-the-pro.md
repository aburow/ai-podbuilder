# AI Agent Podman Sandbox — Complete Workflow Guide

This guide covers the end-to-end workflow for the AI Agent Podman Sandbox
framework: from installing the tools to running an AI agent inside a persistent,
isolated container. Read it top-to-bottom the first time; use the
[Quick-Start Deployment Checklist](#quick-start-deployment-checklist) at the
end when you need a fast reference.

---

## Contents

1. [What This Framework Does](#1-what-this-framework-does)
2. [Prerequisites](#2-prerequisites)
3. [Install the Framework](#3-install-the-framework)
4. [Choose Your Path](#4-choose-your-path)
5. [Path A — Agent-Designed Project (ai-new)](#5-path-a--agent-designed-project-ai-new)
6. [Path B — Manual Profile Setup](#6-path-b--manual-profile-setup)
7. [Build the Container Image (ai-build)](#7-build-the-container-image-ai-build)
8. [Launch the Container (ai-launch)](#8-launch-the-container-ai-launch)
9. [Attach a Second Terminal (ai-terminal)](#9-attach-a-second-terminal-ai-terminal)
10. [Inspect Running Containers (ai-list)](#10-inspect-running-containers-ai-list)
11. [Day-to-Day Operations](#11-day-to-day-operations)
12. [Desktop Integration](#12-desktop-integration)
13. [Quick-Start Deployment Checklist](#quick-start-deployment-checklist)

---

## 1. What This Framework Does

The AI Agent Podman Sandbox framework runs AI coding agents (Codex, Codex,
Aider, etc.) inside **rootless Podman containers**. Each container is:

- **Persistent** — shell history, build caches, and agent configuration survive
  across sessions.
- **Isolated** — only your project workspace is visible inside; host credentials
  and system files are never mounted.
- **Reproducible** — the container image is defined in a `Containerfile` you can
  rebuild at any time.

There are four commands you will use daily:

| Command | Purpose |
|---------|---------|
| `ai-new` | Bootstrap a brand-new project by interviewing an AI agent |
| `ai-build` | Build (or rebuild) a container image from a profile |
| `ai-launch` | Start or re-enter a persistent sandbox container |
| `ai-terminal` | Open an extra terminal tab into a running container |
| `ai-list` | Show all profiles and their container state |

---

## 2. Prerequisites

Before installing, verify the following are in place on your host:

| Requirement | How to check |
|-------------|-------------|
| Bazzite or Fedora Atomic desktop | `cat /etc/os-release` |
| Rootless Podman | `podman info \| grep -i rootless` (must say `true`) |
| Bash 5+ | `bash --version` |
| `slirp4netns` (container networking) | `slirp4netns --version` |
| Internet access for image pulls | `curl -I https://registry.fedoraproject.org` |

For the `ai-new` path, you also need at least one AI agent CLI installed or
installable — Codex (`codex`), Codex (`codex`), or Gemini (`gemini`).
The framework installs the chosen agent automatically unless you pick the
`manual` adapter (Gemini).

---

## 3. Install the Framework

### 3.1 Clone or place the repository

```bash
# Default location (recommended — matches all documentation examples):
git clone <repo-url> "$HOME/codex-jails"

# Or use a custom path:
git clone <repo-url> /opt/codex-jails
export CODEX_JAILS_DIR=/opt/codex-jails
```

If `CODEX_JAILS_DIR` is not set, every command derives its own location from
`BASH_SOURCE`, so the framework is self-hosting from any path — but setting the
variable explicitly avoids surprises.

### 3.2 Add `bin/` to your PATH

Add these two lines to `~/.bashrc` (or `~/.zshrc`):

```bash
export CODEX_JAILS_DIR="${CODEX_JAILS_DIR:-$HOME/codex-jails}"
export PATH="${CODEX_JAILS_DIR}/bin:${PATH}"
```

Reload your shell:

```bash
source ~/.bashrc   # or source ~/.zshrc
```

Verify the commands are on PATH:

```bash
which ai-new ai-build ai-launch ai-terminal ai-list
```

All five should resolve to `$CODEX_JAILS_DIR/bin/`.

---

## 4. Choose Your Path

There are two starting points depending on whether you want the agent to design
your container or whether you already have (or want to hand-write) a profile.

```
New to the stack, don't know what goes in the container?
  → Path A: Use ai-new — the agent interviews you and generates everything.

Already know your stack, have an existing Containerfile?
  → Path B: Write a profile manually, then ai-build and ai-launch.
```

Both paths converge at **[Section 7](#7-build-the-container-image-ai-build)**
once you have a profile and a `Containerfile`.

---

## 5. Path A — Agent-Designed Project (ai-new)

`ai-new` is the easiest starting point. It:

1. Creates a project directory under `$CODEX_JAILS_DIR/projects/<name>/`.
2. Launches a minimal **bootstrap container** with the chosen AI agent.
3. Lets the agent interview you and generate a complete `Containerfile`,
   profile, launcher, and README.
4. Runs a trial `podman build` on the host to validate the generated image.

### 5.1 Create the project

```bash
ai-new my-project --agent codex
```

Replace `my-project` with a short lowercase name (letters, digits, hyphens).
Replace `codex` with `codex` or `gemini` if you use a different runtime.

Available agents are the `.env` files in `$CODEX_JAILS_DIR/config/agents.d/`:

```bash
ls $CODEX_JAILS_DIR/config/agents.d/
# codex.env  codex.env  gemini.env
```

### 5.2 Provide API credentials

The bootstrap container needs to call the agent's API. There are two ways:

**Option 1 — Interactive login (recommended for Codex):**

Codex prompts you to log in the first time. No extra file is needed.

**Option 2 — API key file:**

Create `$CODEX_JAILS_DIR/projects/my-project/bootstrap/agent.env.local` with
your key:

```bash
echo 'OPENAI_API_KEY=sk-...' \
    > "$CODEX_JAILS_DIR/projects/my-project/bootstrap/agent.env.local"
chmod 600 "$CODEX_JAILS_DIR/projects/my-project/bootstrap/agent.env.local"
```

This file is gitignored automatically and never baked into any image.

### 5.3 Answer the agent's questions

The bootstrap container launches automatically. The agent will ask you about:

- What the project does
- Which language/runtime stack you need
- Which OS packages, tools, and build systems to include
- Workspace layout and persistent state requirements
- Ports, environment variables, secrets, and host-resource needs (USB, GPU, etc.)

Answer conversationally. Do not manually install anything during this phase —
express all requirements to the agent; it encodes them in the `Containerfile`.

### 5.4 Wait for the quality gate

When the agent finishes generating files, it signals the host-side `ai-new`
supervisor to run a trial `podman build`. You will see build output in the
terminal. The trial image tag is `localhost/ai-new/<slug>:trial`.

If the build fails, the agent reads the log, repairs the `Containerfile`, and
requests another build (up to 3 attempts by default). If all attempts fail, the
session status becomes `quality-gate-failed` and the agent explains what to do
next.

### 5.5 Review the generated files

When the build passes the session status is `complete`. The agent prints next
steps and exits. You can now examine the generated scaffold:

```
$CODEX_JAILS_DIR/projects/my-project/
├── workspace/            Your project files go here
├── image/
│   └── Containerfile    The durable development image definition
├── profile.env          Profile for ai-build / ai-launch
├── launchers/my-project  Desktop/terminal launcher script
├── build-update.sh      Helper to rebuild the image
├── README.md            Next steps and usage
└── .env.example         Placeholder for runtime secrets
```

Review `image/Containerfile` and `profile.env` before proceeding. The generated
`profile.env` is already wired to the right paths — copy or symlink it into
`$CODEX_JAILS_DIR/profiles/` so `ai-build` and `ai-launch` can find it:

```bash
cp "$CODEX_JAILS_DIR/projects/my-project/profile.env" \
   "$CODEX_JAILS_DIR/profiles/my-project.env"
```

### 5.6 Resuming an interrupted session

If the bootstrap session was interrupted (network drop, crash, Ctrl-C), resume
it with:

```bash
ai-new my-project --resume
```

The session picks up from where it left off. The agent reads `session.md` and
`session.json` for continuity; you do not start the interview again.

---

## 6. Path B — Manual Profile Setup

Use this path when you already have a `Containerfile` (or want to write one)
and just need to create the profile that wires everything together.

### 6.1 Prepare the image directory

Create a directory with your `Containerfile`:

```bash
mkdir -p "$CODEX_JAILS_DIR/my-image"
cat > "$CODEX_JAILS_DIR/my-image/Containerfile" <<'EOF'
FROM fedora:latest
RUN dnf install -y git vim python3 && dnf clean all
EOF
```

### 6.2 Create the profile

Copy the example profile and fill it in:

```bash
cp "$CODEX_JAILS_DIR/profiles/esp32.env.example" \
   "$CODEX_JAILS_DIR/profiles/my-project.env"
```

Edit `profiles/my-project.env`:

```bash
PROFILE_NAME="my-project"
CONTAINER_NAME="my-project-container"
IMAGE_NAME="my-project-image"
IMAGE_DIR="${CODEX_JAILS_DIR}/my-image"
WORKSPACE="${CODEX_JAILS_DIR}/my-workspace"
CONTAINER_HOME="${CODEX_JAILS_DIR}/my-home"
BASHRC="${WORKSPACE}/.bashrc"
WORKDIR="/workspace"
BUILD_ARGS=""
```

Required fields:

| Field | What it controls |
|-------|-----------------|
| `PROFILE_NAME` | The name you pass to `ai-build`, `ai-launch`, etc. — must match the filename without `.env`. |
| `CONTAINER_NAME` | The Podman container name. |
| `IMAGE_NAME` | The Podman image name. |
| `IMAGE_DIR` | Directory containing the `Containerfile`. |
| `WORKSPACE` | Host path bind-mounted at `/workspace` inside the container. |
| `CONTAINER_HOME` | Host path used as the container's `$HOME`. |
| `BASHRC` | `.bashrc` sourced inside the container. |
| `WORKDIR` | Working directory inside the container (typically `/workspace`). |
| `BUILD_ARGS` | Extra `podman build` flags (use `""` for none). |

All paths must use `$CODEX_JAILS_DIR` — **never hardcode usernames or
`/var/home/` paths**.

Optional extras (add to the profile as needed):

```bash
# Inject secrets at launch time (file must be mode 600):
ENV_FILE="${CODEX_JAILS_DIR}/my-project-secrets.env"

# Pass through a USB device:
EXTRA_DEVICES=("--device=/dev/ttyUSB0")

# Extra environment variables:
EXTRA_ENV=("-e" "FOO=bar")

# Run inside the image after build to verify tool versions:
POST_BUILD_CHECK="python3 --version && git --version"
```

---

## 7. Build the Container Image (ai-build)

Once you have a profile pointing to a `Containerfile` (whether generated by
`ai-new` or written by hand), build the image:

```bash
ai-build my-project
```

This runs `podman build` with the flags from your profile and tags the image as
`IMAGE_NAME`. If `POST_BUILD_CHECK` is set, it runs that command inside a
temporary container to verify the tools installed correctly.

**Rebuilding after changes:**

Any time you edit the `Containerfile`, rebuild:

```bash
ai-build my-project
```

The next `ai-launch` detects that the image changed and (in interactive mode)
offers to recreate the container. Pass `--recreate` to skip the prompt:

```bash
ai-launch my-project --recreate
```

---

## 8. Launch the Container (ai-launch)

### 8.1 Start an interactive shell

```bash
ai-launch my-project
```

This creates or reattaches to the persistent container and opens a Bash shell.
The container is rootless; your workspace is at `/workspace` inside it.

### 8.2 Launch an AI agent directly

Instead of a plain shell, pass the agent mode as the second argument:

```bash
ai-launch my-project codex    # Start Codex in the container
ai-launch my-project codex     # Start Codex
ai-launch my-project aider     # Start Aider
ai-launch my-project opencode  # Start OpenCode
```

The agent must be installed inside the container image for this to work.

### 8.3 Builder mode (privileged, ephemeral)

For operations that need raw device access (firmware flashing, kernel modules):

```bash
ai-launch my-project builder
```

This runs an ephemeral `--privileged` container that is removed when you exit.
Your workspace is still bind-mounted, so build artifacts persist.

### 8.4 Common ai-launch flags

| Flag | Effect |
|------|--------|
| `--recreate` | Remove and recreate the container from the current image. |
| `--no-recreate` | Keep the existing container even if the image has changed. |
| `--reset` | Stop, remove, and recreate the container (interactive confirmation). |
| `--reset --yes` | Same as `--reset` but skips the confirmation prompt. |
| `--non-interactive` | Never prompt for input; suitable for launcher scripts. |

---

## 9. Attach a Second Terminal (ai-terminal)

While a container is running, open an additional Bash shell into it:

```bash
ai-terminal my-project
```

This is equivalent to `podman exec -it <container> bash`. Use it to run
commands alongside an agent session without interrupting it.

---

## 10. Inspect Running Containers (ai-list)

```bash
ai-list
```

Prints a table of all profiles in `profiles/` and their current container
state (`running`, `exited`, `absent`, etc.):

```
Profile         Image                    Workspace                      State
my-project      my-project-image         /home/user/codex-jails/...    running
esp32           codex-esp32-image        /home/user/codex-jails/...    exited
```

---

## 11. Day-to-Day Operations

### Rebuild the image after Containerfile changes

```bash
ai-build my-project
ai-launch my-project --recreate   # or let the stale-image prompt guide you
```

### Reset a container (keep workspace and home)

Stops, removes, and recreates the container. The workspace and `CONTAINER_HOME`
are always preserved — only the container's writable layer is discarded.

```bash
ai-launch my-project --reset          # interactive confirmation
ai-launch my-project --reset --yes    # no prompt
```

### Add secrets

Create a secrets file (mode 600) and reference it in the profile:

```bash
# Create the secrets file:
echo 'OPENAI_API_KEY=sk-...' > "$CODEX_JAILS_DIR/my-secrets.env"
chmod 600 "$CODEX_JAILS_DIR/my-secrets.env"

# Add to the profile:
echo 'ENV_FILE="${CODEX_JAILS_DIR}/my-secrets.env"' >> \
    "$CODEX_JAILS_DIR/profiles/my-project.env"
```

The secrets file is injected at launch time via `--env-file` and is never
baked into the image.

### Add an in-container SSH key

The host `~/.ssh` is never mounted. Generate a scoped key inside the container:

```bash
# Inside the container (via ai-launch or ai-terminal):
ssh-keygen -t ed25519 -C "ai-agent@$(hostname)" -f ~/.ssh/id_ed25519_agent

# Configure the in-container SSH client:
cat >> ~/.ssh/config <<'EOF'
Host github.com
    IdentityFile ~/.ssh/id_ed25519_agent
    IdentitiesOnly yes
EOF
```

Add the public key to your Git host as a deploy key scoped to the target
repository. The key persists in `CONTAINER_HOME/.ssh/` across container
recreations.

---

## 12. Desktop Integration

### Launcher scripts

`launchers/` scripts are thin wrappers that call `ai-launch` with
`--non-interactive`, safe for desktop or Podman Desktop entry points:

```bash
#!/usr/bin/env bash
exec ai-launch my-project codex --non-interactive
```

Create one per profile/mode combination you want to launch from the desktop.

### `.desktop` files (KDE / GNOME)

Place the file in `~/.local/share/applications/`. Replace the path with your
actual expanded `CODEX_JAILS_DIR`:

**KDE (Konsole):**

```ini
[Desktop Entry]
Version=1.0
Type=Application
Name=My Project — Codex
Exec=konsole --noclose -e bash -c '$HOME/codex-jails/launchers/my-project'
Icon=utilities-terminal
Categories=Development;
```

**GNOME (kgx):**

```ini
[Desktop Entry]
Version=1.0
Type=Application
Name=My Project — Codex
Exec=kgx -- bash -c '$HOME/codex-jails/launchers/my-project'
Icon=utilities-terminal
Categories=Development;
```

### Podman Desktop

Persistent containers created by `ai-launch` appear in Podman Desktop under
the Containers list. You can start, stop, inspect, and remove them from there.
Ephemeral builder containers are not visible after they exit.

---

## Quick-Start Deployment Checklist

Use this section as a step-by-step reference when setting up a new machine or
a new project from scratch.

### Phase 1 — Install the framework (once per machine)

```bash
# 1. Clone the framework to ~/codex-jails (or your preferred location):
git clone <repo-url> "$HOME/codex-jails"

# 2. Add bin/ to PATH — append to ~/.bashrc:
echo 'export CODEX_JAILS_DIR="${CODEX_JAILS_DIR:-$HOME/codex-jails}"' >> ~/.bashrc
echo 'export PATH="${CODEX_JAILS_DIR}/bin:${PATH}"' >> ~/.bashrc
source ~/.bashrc

# 3. Confirm Podman is rootless:
podman info | grep -i rootless
# Expected: rootless: true

# 4. Confirm commands resolve:
which ai-new ai-build ai-launch ai-terminal ai-list
```

---

### Phase 2A — Create a new project with ai-new (agent-designed)

Run these commands **from your host terminal** (not inside any container):

```bash
# 5. Bootstrap the project — the agent designs the container for you:
ai-new my-project --agent codex

#    The bootstrap container starts automatically.
#    Answer the agent's interview questions.
#    Wait for the quality-gate build to complete.
#    The agent prints next steps when done.

# 6. Copy the generated profile into profiles/:
cp "$CODEX_JAILS_DIR/projects/my-project/profile.env" \
   "$CODEX_JAILS_DIR/profiles/my-project.env"

# → Skip to Phase 3.
```

---

### Phase 2B — Set up a project manually (existing Containerfile)

```bash
# 5. Place your Containerfile:
mkdir -p "$CODEX_JAILS_DIR/my-image"
# ... write or copy your Containerfile into that directory ...

# 6. Create the profile from the example:
cp "$CODEX_JAILS_DIR/profiles/esp32.env.example" \
   "$CODEX_JAILS_DIR/profiles/my-project.env"
# Edit profiles/my-project.env — set PROFILE_NAME, IMAGE_DIR, WORKSPACE, etc.
```

---

### Phase 3 — Build the image

```bash
# 7. Build the container image:
ai-build my-project
```

---

### Phase 4 — Launch and use the container

```bash
# 8. Open an interactive shell:
ai-launch my-project

# — OR — launch an AI agent directly:
ai-launch my-project codex

# 9. (Optional) Open a second terminal into the same running container:
ai-terminal my-project

# 10. Check the state of all your containers:
ai-list
```

---

### Phase 5 — Ongoing maintenance

```bash
# Rebuild the image after editing the Containerfile:
ai-build my-project
ai-launch my-project --recreate

# Reset a container (keeps workspace and home; removes only the writable layer):
ai-launch my-project --reset --yes

# Resume an interrupted ai-new bootstrap session:
ai-new my-project --resume
```

---

### Where to launch each tool

| Command | Launch from |
|---------|-------------|
| `ai-new` | **Host terminal** — never inside another container |
| `ai-build` | **Host terminal** — never inside a container |
| `ai-launch` | **Host terminal** — opens into the container for you |
| `ai-terminal` | **Host terminal** — attaches to an already-running container |
| `ai-list` | **Host terminal** |
| Agent CLIs (`codex`, `codex`, etc.) | **Inside the container** (via `ai-launch` or `ai-terminal`) |

All five framework commands (`ai-new`, `ai-build`, `ai-launch`, `ai-terminal`,
`ai-list`) are host-side tools. They manage containers; they do not run inside
them. Run them from any host terminal where `$CODEX_JAILS_DIR/bin` is on your
`PATH`.

---

## Further Reading

- [Profiles](profiles.md) — Full field reference, optional fields, and example profile.
- [ai-new reference](ai-new.md) — Session state, quality gate, coordination protocol, and all configuration variables.
- [Security model](security-model.md) — What is and is not mounted; builder-mode policy.
- [SELinux](selinux.md) — `SELINUX_MODE` options and trade-offs.
- [Secrets and SSH](secrets-and-ssh.md) — `ENV_FILE`, mode 600 rule, and in-sandbox SSH keys.
- [Teardown](teardown.md) — `--reset`, `--recreate`, and raw Podman escape hatch.
- [Desktop integration](desktop-integration.md) — Launcher scripts and `.desktop` file examples.
