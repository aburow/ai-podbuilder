# Teardown and Recreation

The canonical way to remove and rebuild a persistent container is through the
`ai-launch` flags. Raw Podman commands are documented at the end as an escape
hatch.

---

## `--reset` — stop and recreate in one step (R4.11)

`--reset` stops a running container, removes it, and recreates it from the
current image. The following are always **preserved**:

- Your **workspace** (the `WORKSPACE` directory and everything in it)
- The **container home directory** (`CONTAINER_HOME`)
- The **profile** (`.env` file) and its settings
- The **image** (the container image is not deleted or rebuilt)
- **Secrets** (`ENV_FILE`, if set)

Only the container itself — its writable layer and runtime state — is removed.

```bash
# Interactive (prompts for confirmation):
ai-launch esp32 --reset

# Non-interactive (skips the prompt, suitable for scripts and launchers):
ai-launch esp32 --reset --yes
```

---

## `--recreate` — recreate from a new image without stopping

When the local image has been rebuilt (`ai-build esp32`) but the persistent
container still runs the old image, use `--recreate` to rebuild the container
in-place:

```bash
ai-launch esp32 --recreate
```

This removes the existing container and creates a fresh one from the current
image. The workspace is preserved.

---

## Stale-image detection

On every launch `ai-launch` compares the image ID the container was created
from against the current local image ID. When they differ:

- **Interactive mode** — presents a three-way prompt: continue / recreate / cancel.
- **Non-interactive mode** (`--yes` or `--non-interactive`) — warns and continues
  with the existing container.

To force a specific behaviour without the prompt, pass `--recreate` or
`--no-recreate` explicitly.

---

## Escape hatch: raw Podman commands

If the framework flags are not sufficient (e.g. the container is in a broken
state the framework cannot handle), you can manage it directly:

```bash
# Stop a running container:
podman stop codex-esp32

# Remove the container (workspace is untouched — it lives on the host):
podman rm codex-esp32

# Rebuild the image:
ai-build esp32

# Recreate using the framework (preferred):
ai-launch esp32
```

Prefer the `ai-launch` flags over raw Podman commands so that safety policy
is applied consistently. Use raw commands only when the framework cannot
complete the operation.
