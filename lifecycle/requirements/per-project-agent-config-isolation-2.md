---
title: 'Isolate agent config dirs per project via state/home/ seeding'
type: requirement
status: done
lineage: per-project-agent-config-isolation
created: "2026-06-28T00:00:00+10:00"
priority: normal
labels:
    - isolation
    - scaffold
---

# Per-Project Agent Config Isolation

## Problem

Agent config directories (`.codex`, `.claude`, `.gemini`, `.config/gh`) were
mounted from the host `$HOME` via `EXTRA_VOLUMES`, sharing credentials and
settings across all projects.  This meant one project could read or modify
another project's agent state, and a corrupted config in one project could
affect all others.

## Requirements

- R1: `scaffold_layout` creates `state/home/` as part of the canonical project
  directory structure.
- R2: At scaffold time, copy `.codex`, `.claude`, `.gemini`, `.config/gh` from
  the host `$HOME` into `state/home/` if they exist.  Use `cp -a` (preserve
  permissions and structure).  Skip silently if the source does not exist.
- R3: Each project gets its own isolated copy — not a symlink, not a shared
  mount.  Changes inside one project's container do not affect another.
- R4: The bootstrap prompt instructs the agent NOT to add these dirs to
  `EXTRA_VOLUMES` — they are pre-seeded and available via `CONTAINER_HOME`.
- R5: Existing projects with EXTRA_VOLUMES entries for these dirs continue to
  work via the `host_path_is_optional_config_mount` fallback in `profile.sh`.

## Notes

Seeding is a creation-time act.  If the user re-auths or updates a global
config after project creation, the project copy does not auto-update — this is
intentional isolation.  Manual `cp -a` from host to `state/home/` is the
supported update path.

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
