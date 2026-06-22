# Profiles

A profile is a `.env` file in the `profiles/` directory that configures one
sandbox environment. The filename (without `.env`) is the profile name passed
to `ai-build`, `ai-launch`, `ai-terminal`, etc.

---

## Required fields (R1.3, R2)

Every profile must define these fields:

| Field | Description |
|-------|-------------|
| `PROFILE_NAME` | Display name (should match the filename). |
| `CONTAINER_NAME` | Name of the persistent Podman container. |
| `IMAGE_NAME` | Name of the container image (built by `ai-build`). |
| `IMAGE_DIR` | Path to the directory containing the `Containerfile`/`Dockerfile`. |
| `WORKSPACE` | Host path to the project workspace (bind-mounted at `/workspace`). |
| `CONTAINER_HOME` | Host path used as the container's `HOME` directory. |
| `BASHRC` | Path to the `.bashrc` sourced inside the container (typically `$WORKSPACE/.bashrc`). |
| `WORKDIR` | Working directory inside the container (typically `/workspace`). |
| `BUILD_ARGS` | Extra `podman build` arguments (use `""` for none). |

Use `$CODEX_JAILS_DIR` for all paths — **no hard-coded usernames or
`/var/home/<user>` paths** (R12.2). `CODEX_JAILS_DIR` defaults to the
parent of the `bin/` directory if not set in the environment.

---

## Optional fields

| Field | Type | Description |
|-------|------|-------------|
| `SELINUX_MODE` | string | `disable` (default) or `enforce`. See [selinux.md](selinux.md). |
| `NETWORK_MODE` | string | Podman network mode (default: `slirp4netns`). |
| `ENV_FILE` | string | Path to a secrets env file (mode `600`). See [secrets-and-ssh.md](secrets-and-ssh.md). |
| `POST_BUILD_CHECK` | string | Shell command run inside the image after `ai-build` to verify installed tools. |
| `EXTRA_ENV` | array | Extra `podman run -e` flags. Example: `("-e" "FOO=bar")`. |
| `EXTRA_VOLUMES` | array | Extra `-v` flags. Example: `("-v" "$HOME/cache:/cache:Z")`. |
| `EXTRA_DEVICES` | array | Extra `--device` flags. Example: `("--device=/dev/ttyUSB0")`. |
| `EXTRA_HOSTS` | array | Extra `--add-host` values. Example: `("myhost:192.168.1.10")`. |
| `EXTRA_RUN_ARGS` | array | Arbitrary extra `podman run`/`podman create` arguments. |

---

## Example profile

```bash
# profiles/esp32.env
PROFILE_NAME="esp32"
CONTAINER_NAME="codex-esp32"
IMAGE_NAME="codex-esp32-image"
IMAGE_DIR="${CODEX_JAILS_DIR}/esp32-image"
WORKSPACE="${CODEX_JAILS_DIR}/esp32-workspace"
CONTAINER_HOME="${CODEX_JAILS_DIR}/esp32-home"
BASHRC="${WORKSPACE}/.bashrc"
WORKDIR="/workspace"
BUILD_ARGS="--no-cache"

# Optional extras
SELINUX_MODE="disable"
ENV_FILE="${CODEX_JAILS_DIR}/esp32-secrets.env"
EXTRA_DEVICES=("--device=/dev/ttyUSB0")
POST_BUILD_CHECK="xtensa-esp32-elf-gcc --version && idf.py --version"
```

---

## Persisting `bin/` on PATH (R1.3)

Add the framework's `bin/` directory to your shell `PATH` so that
`ai-build`, `ai-launch`, `ai-terminal`, and `ai-list` are available
from any directory:

```bash
# Add to ~/.bashrc or ~/.zshrc:
export CODEX_JAILS_DIR="${CODEX_JAILS_DIR:-$HOME/codex-jails}"
export PATH="${CODEX_JAILS_DIR}/bin:${PATH}"
```

If `CODEX_JAILS_DIR` is unset, each command falls back to deriving the base
directory from its own path (`BASH_SOURCE`), so the framework is self-hosting
from any location without requiring `CODEX_JAILS_DIR` to be set.

---

## Creating a new profile

1. Copy `profiles/esp32.env.example` to `profiles/<name>.env`.
2. Set all required fields. Use `$CODEX_JAILS_DIR`-based paths throughout.
3. Create the `IMAGE_DIR` directory with a `Containerfile`.
4. Build the image: `ai-build <name>`.
5. Launch: `ai-launch <name>`.
