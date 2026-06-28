---
title: 'Per-container hostname in shell prompt'
type: requirement
status: done
lineage: container-hostname-support
created: "2026-06-28T00:00:00+10:00"
priority: normal
labels:
    - ux
---

# Per-Container Hostname in Shell Prompt

## Problem

The PS1 in `bashrc.default` showed a hardcoded `ai-podbuilder` regardless of
which container was running.  Users could not tell which project container their
shell was in from the prompt alone.

## Requirements

- R1: PS1 uses `\h` so the prompt reflects the actual container hostname.
- R2: Bootstrap container launched with `--hostname "ai-new-<slug>"`.
- R3: Durable container launched with `--hostname "${CONTAINER_HOSTNAME:-${CONTAINER_NAME:-ai-podbuilder}}"`.
- R4: `CONTAINER_HOSTNAME` added as optional field in `profile.env` template; omitting it falls back to `CONTAINER_NAME`.
- R5: Bootstrap interview asks for a hostname and suggests the project slug as default.

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
