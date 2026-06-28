---
title: 'hadolint installed to lib/ but not symlinked into bin/, absent from PATH'
type: defect
status: done
lineage: hadolint-not-in-bin
created: "2026-06-28T00:00:00+10:00"
priority: normal
labels:
    - defect
    - install
---

# hadolint installed to lib/ but not symlinked into bin/, absent from PATH

## Summary

`install.sh` downloaded the hadolint binary to `lib/hadolint-linux-<arch>` and
created `lib/hadolint` as a symlink, but did not create a corresponding symlink
in `bin/`.  Since `bin/` is the only directory added to `$PATH` by the installer,
`hadolint` was not directly invocable by users or scripts that rely on PATH
resolution.

The `quality_gate.sh` static-check fallback (`${_QUALITY_GATE_LIB_DIR}/hadolint`)
continued to work, but `command -v hadolint` returned nothing, and users could
not run it directly.

## Fix

Added `ln -sf "${INSTALL_ROOT}/lib/hadolint" "${INSTALL_ROOT}/bin/hadolint"` to
`fetch_hadolint()` in `install.sh`.

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
