---
title: CODEX_JAILS Env Vars Must Be Deprecated in Favour of AI_PODMAN_*
type: defect
status: draft
lineage: deprecate-codex-jails-env-vars
created: "2026-06-26T14:51:42+10:00"
priority: normal
labels:
    - defect
---

# CODEX_JAILS Env Vars Must Be Deprecated in Favour of AI_PODMAN_*

## Summary

The codebase contains references to `CODEX_JAILS` and related environment variables (e.g. `CODEX_JAILS_DIR`) that reflect an older approach. These must be deprecated and replaced with the `AI_PODMAN_JAILS`, `AI_PODMAN_JAILS_DIR`, and related `AI_PODMAN_*` variables. Both naming schemes must be supported during the transition period, but `AI_PODMAN_*` variables must take precedence when both are present.

## Reproduction Steps

1. Inspect the codebase for all references to `CODEX_JAILS`, `CODEX_JAILS_DIR`, and any other `CODEX_*` environment variables.
2. Set both `CODEX_JAILS` and `AI_PODMAN_JAILS` to different values in the environment.
3. Observe which variable the code honours — currently `CODEX_JAILS` is used unconditionally.

## Expected Behaviour

- All logic reads from `AI_PODMAN_JAILS`, `AI_PODMAN_JAILS_DIR`, etc. as the canonical variables.
- If an `AI_PODMAN_*` variable is set, it wins over its `CODEX_*` counterpart.
- If only the legacy `CODEX_*` variable is set, it is used as a fallback to preserve backwards compatibility.
- A deprecation warning is emitted when a `CODEX_*` fallback is exercised.

## Actual Behaviour

`CODEX_JAILS` and related variables are used directly with no fallback logic and no migration path to `AI_PODMAN_*` equivalents.

## Logs / Output

Not provided
