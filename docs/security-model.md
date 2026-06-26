# Security Model

This document describes the normal-mode security policy enforced by
`ai-launch` and what each control achieves.

---

## Normal-mode policy (R5)

Every persistent container launched by `ai-launch` (all modes except `builder`)
uses the following fixed flags. No caller — not even the profile — can remove
these:

| Flag | Effect |
|------|--------|
| `--userns=keep-id` | Maps your host UID/GID into the container; no root inside. |
| `--group-add keep-groups` | Preserves supplementary groups (e.g. `dialout` for USB). |
| `--security-opt no-new-privileges` | Prevents privilege escalation via setuid/setcap binaries. |
| `--network slirp4netns` (default) | User-space NAT; container cannot reach host services. |
| `-v WORKSPACE:/workspace:Z` | **Exactly one bind mount** — the project workspace. |

### What is NOT mounted (R5.2)

- Host `$HOME` — never mounted. The container has its own home directory
  (`CONTAINER_HOME`) on the host filesystem.
- `/tmp`, `/var/run`, system sockets (Docker/Podman socket, D-Bus, etc.).
- `~/.ssh` — never mounted; see [secrets-and-ssh.md](secrets-and-ssh.md).
- Any device node not listed in `EXTRA_DEVICES` in the profile.

### Container HOME (R5.4)

The container's `HOME` is set to `CONTAINER_HOME` (e.g. `$AI_PODMAN_JAILS_DIR/esp32-home`).
This directory lives on the host and is bind-mounted into the container so
that shell history, editor state, and tool configuration persist across
container recreations, but remain fully separate from the host `$HOME`.

---

## Builder mode — the only `--privileged` path (R5.3, R4.5)

`ai-launch <profile> builder` runs an ephemeral privileged container (`--privileged --rm`).
It is the **only** path in the framework that uses `--privileged`. Builder mode is
intended for firmware flashing, kernel module compilation, and other operations
that require raw device access.

Because the container is ephemeral (`--rm`), it is removed automatically when
the session ends. The workspace bind mount is still present so build artifacts
persist. There is no persistent builder container to reuse or compromise.

---

## Persistence and containment rationale (R4.2)

Persistent containers give AI agents a stable, reproducible environment —
shell history, installed tools, and incremental build caches survive across
sessions. Containment is preserved because:

1. The container is rootless (no host root is ever involved).
2. The only host path visible inside is the workspace (plus `CONTAINER_HOME`).
3. Network access uses user-space NAT; the host network stack is not shared.
4. No host credentials, sockets, or devices are exposed by default.

A persistent container that is compromised by a runaway AI agent can be
removed with `ai-launch <profile> --reset --yes` and recreated from the
original image — the workspace and home directory are untouched.

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
