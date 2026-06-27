---
title: 'Local artifact inspection inside bootstrap container fails under Bubblewrap'
type: defect
status: abandoned
lineage: bootstrap-container-inspection-fails-under-bubblewrap
created: "2026-06-27T00:00:00+10:00"
priority: normal
labels:
    - defect
---

# Local artifact inspection inside bootstrap container fails under Bubblewrap

## Summary

Simple file inspection commands (`cat`, related reads) fail with a `bwrap: Can't mount devpts` permission error when run from inside the bootstrap container under nested Bubblewrap. Routine review and debugging are harder, especially when investigating Bubblewrap-sensitive scaffolds.

## Reproduction Steps

1. Enter the bootstrap container environment.
2. Run any ordinary local inspection command (e.g. `cat /project/Containerfile`).
3. When nested user namespaces are unavailable, the command fails with:
   `bwrap: Can't mount devpts on /newroot/dev/pts: Permission denied`

## Expected Behaviour

Simple local file inspection commands work inside the bootstrap container without requiring special handling or out-of-band execution paths.

## Actual Behaviour

Direct `cat` and related inspection commands fail until execution bypasses the intercepted path. Out-of-band execution was required for the kaos-control run.

## Resolution — Abandoned (architectural constraint)

Bubblewrap is a hard runtime dependency of Codex. Codex uses its vendored bubblewrap
to sandbox every command it executes. When the bootstrap container runs on a host
that does not support nested user namespaces (the common case under rootless Podman),
the bubblewrap sandbox cannot mount `devpts` and the intercepted command fails.

This is not fixable in `ai-new` source: removing or bypassing bubblewrap would break
Codex's own sandboxing model, which it requires to operate fully. The vendored version
covers Codex's own needs during bootstrap/consultation; the deployed durable image
requires a host-supported bubblewrap for full Codex functionality.

The expected mitigation is documented in the bootstrap prompt: agents must use
`/project/`-prefixed absolute paths for file reads during consultation, and instruct
users to perform visual review after exiting the bootstrap container on the host where
Bubblewrap constraints do not apply.

## Logs / Output

Source: `imported_defect_data/DEFECTS.md` D-008, kaos-control bootstrap run 2026-06-27.
Evidence: `bwrap: Can't mount devpts on /newroot/dev/pts: Permission denied` on direct file reads from bootstrap shell.

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
