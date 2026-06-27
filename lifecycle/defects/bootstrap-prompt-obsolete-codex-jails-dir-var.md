---
title: 'Bootstrap prompt uses obsolete CODEX_JAILS_DIR framework root variable'
type: defect
status: done
lineage: bootstrap-prompt-obsolete-codex-jails-dir-var
created: "2026-06-27T00:00:00+10:00"
priority: normal
labels:
    - defect
---

# Bootstrap prompt uses obsolete CODEX_JAILS_DIR framework root variable

## Summary

The bootstrap prompt and template guidance reference `CODEX_JAILS_DIR` as the framework root variable, but the current installation uses `AI_PODMAN_JAILS_DIR`. Generators following the prompt literally produce stale or broken paths unless the user manually intervenes.

## Reproduction Steps

1. Follow the bootstrap prompt literally on a current installation.
2. Generate profile/launcher paths without any user correction.
3. Observe that the generated output references `CODEX_JAILS_DIR` instead of `AI_PODMAN_JAILS_DIR`.

## Expected Behaviour

The bootstrap prompt, scaffolding templates, and validator logic reference `AI_PODMAN_JAILS_DIR` consistently with the current framework installation.

## Actual Behaviour

The prompt instructs generators to derive paths from `CODEX_JAILS_DIR`. The generated `profile.env` requires manual correction to `AI_PODMAN_JAILS_DIR`. The user identified and corrected this during the kaos-control bootstrap interview on 2026-06-27.

## Logs / Output

Source: `imported_defect_data/DEFECTS.md` D-001, kaos-control bootstrap run 2026-06-27.
Evidence: user corrected the prompt during interview; generated profile uses `AI_PODMAN_JAILS_DIR` only after intervention.

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
