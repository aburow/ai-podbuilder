---
title: 'Bootstrap prompt prescribes obsolete CODEX_BIN launcher derivation'
type: defect
status: done
lineage: bootstrap-prompt-obsolete-codex-bin-launcher
created: "2026-06-27T00:00:00+10:00"
priority: normal
labels:
    - defect
---

# Bootstrap prompt prescribes obsolete CODEX_BIN launcher derivation

## Summary

The bootstrap prompt requires launcher delegation through `${CODEX_BIN}/ai-launch`, but the current scaffold and framework use `AI_PODMAN_BIN` rooted under `AI_PODMAN_JAILS_DIR`. A prompt-compliant launcher is therefore wrong even when the rest of the scaffold is correct.

## Reproduction Steps

1. Generate a launcher directly from the bootstrap prompt on a current installation without local overrides.
2. Inspect the generated launcher for `CODEX_BIN` references.

## Expected Behaviour

Launcher instructions in the bootstrap prompt match the current `AI_PODMAN_BIN` convention so a generated launcher works without manual correction.

## Actual Behaviour

The prompt prescribes `CODEX_BIN` derivation. The kaos-control run generated a correct launcher only because the convention was manually corrected:
- `AI_PODMAN_JAILS_DIR="${AI_PODMAN_JAILS_DIR:-${HOME}/ai-podman-jails}"`
- `AI_PODMAN_BIN="${AI_PODMAN_BIN:-${AI_PODMAN_JAILS_DIR}/bin}"`

## Logs / Output

Source: `imported_defect_data/DEFECTS.md` D-002, kaos-control bootstrap run 2026-06-27.
Evidence: generated `launchers/kaos-control` uses `AI_PODMAN_BIN`; prompt text still prescribes `CODEX_BIN` derivation.

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
