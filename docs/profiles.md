# Profiles

A profile is a `.env` file that configures one sandbox environment. The
canonical, authoritative location is `projects/<name>/profile.env` — this is
where `ai-new` writes the profile and where `ai-build`, `ai-launch`,
`ai-terminal`, and `ai-list` look first.

The `profiles/` directory is an optional legacy/compatibility area. Files
placed there (`profiles/<slug>.env`) are still recognized as a fallback when
no project-local profile exists, but `ai-new` and normal resume flows never
write there. New profiles should be created under `projects/<name>/profile.env`.

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

Use `$AI_PODMAN_JAILS_DIR` for all paths — **no hard-coded usernames or
`/var/home/<user>` paths** (R12.2). `AI_PODMAN_JAILS_DIR` defaults to the
parent of the `bin/` directory if not set in the environment.

---

## Optional fields

| Field | Type | Description |
|-------|------|-------------|
| `SELINUX_MODE` | string | `disable` (default) or `enforce`. See [selinux.md](selinux.md). |
| `NETWORK_MODE` | string | Podman network mode (default: `slirp4netns`). |
| `ENV_FILE` | string | Path to a secrets env file (mode `600`). See [secrets-and-ssh.md](secrets-and-ssh.md). |
| `POST_BUILD_CHECK` | string | Shell command run inside the image after `ai-build` to verify installed tools. |
| `EXTRA_ENV` | array | Extra `podman run -e` flags. **Alternating flag + value pairs** — see format note below. |
| `EXTRA_VOLUMES` | array | Extra `-v` flags. **Alternating flag + value pairs** — see format note below. |
| `EXTRA_DEVICES` | array | Extra `--device` flags. Example: `("--device=/dev/ttyUSB0")`. |
| `EXTRA_HOSTS` | array | Extra `--add-host` values. Example: `("myhost:192.168.1.10")`. |
| `EXTRA_RUN_ARGS` | array | Arbitrary extra `podman run`/`podman create` arguments. |

### `EXTRA_ENV` and `EXTRA_VOLUMES` format

Both arrays use **alternating flag + value pairs**. The flag (`-e`/`--env` or
`-v`/`--volume`) must appear as a separate element before each value. The
profile validator rejects bare `KEY=VALUE` or `HOST:CTR` strings.

```bash
# Correct
EXTRA_ENV=(
  "-e" "GOTOOLCHAIN=auto"
  "-e" "PNPM_HOME=/home/developer/.local/share/pnpm"
)
EXTRA_VOLUMES=(
  "-v" "${HOME}/.codex:/home/developer/.codex:rw"
  "-v" "${HOME}/.claude:/home/developer/.claude:rw"
)

# Wrong — validator will reject these
EXTRA_ENV=("GOTOOLCHAIN=auto")           # missing -e flag
EXTRA_VOLUMES=("${HOME}/.codex:/…:rw")  # missing -v flag
```

---

## Example profile

```bash
# projects/esp32/profile.env  (canonical location)
PROFILE_NAME="esp32"
CONTAINER_NAME="codex-esp32"
IMAGE_NAME="codex-esp32-image"
IMAGE_DIR="${AI_PODMAN_JAILS_DIR}/esp32-image"
WORKSPACE="${AI_PODMAN_JAILS_DIR}/esp32-workspace"
CONTAINER_HOME="${AI_PODMAN_JAILS_DIR}/esp32-home"
BASHRC="${WORKSPACE}/.bashrc"
WORKDIR="/workspace"
BUILD_ARGS="--no-cache"

# Optional extras
SELINUX_MODE="disable"
ENV_FILE="${AI_PODMAN_JAILS_DIR}/esp32-secrets.env"
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
export AI_PODMAN_JAILS_DIR="${AI_PODMAN_JAILS_DIR:-$HOME/codex-jails}"
export PATH="${AI_PODMAN_JAILS_DIR}/bin:${PATH}"
```

If `AI_PODMAN_JAILS_DIR` is unset, each command falls back to deriving the base
directory from its own path (`BASH_SOURCE`), so the framework is self-hosting
from any location without requiring `AI_PODMAN_JAILS_DIR` to be set.

---

## Creating a new profile

The recommended way is `ai-new <name>`, which generates
`projects/<name>/profile.env` automatically.

To author one manually:

1. Create `projects/<name>/profile.env` (or copy
   `profiles/esp32.env.example` as a reference — see the header comment).
2. Set all required fields. Use `$AI_PODMAN_JAILS_DIR`-based paths throughout.
3. Create the `IMAGE_DIR` directory with a `Containerfile`.
4. Build the image: `ai-build <name>`.
5. Launch: `ai-launch <name>`.

Placing a file in `profiles/<slug>.env` instead is also supported as a
legacy/compatibility path. `ai-list` will find it, but project-local profiles
take precedence when both exist for the same slug.

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
