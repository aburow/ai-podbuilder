---
title: 'Bootstrap container missing bubblewrap and hadolint'
type: defect
status: done
lineage: bootstrap-missing-bubblewrap-hadolint
created: "2026-06-28T00:00:00+10:00"
priority: normal
labels:
    - defect
    - bootstrap
---

# Bootstrap container missing bubblewrap and hadolint

## Summary

The bootstrap container image (`lib/bootstrap_image.sh`) did not include
`bubblewrap` or `hadolint`, both of which agents inside the container need:

- `bubblewrap` — required for sandboxed execution and by some agent runtimes
  inside the container.
- `hadolint` — required for the agent to lint-check the Containerfile it
  generates before requesting a quality-gate build.

## Fix

`_write_bootstrap_containerfile` updated:

- `bubblewrap` added to the `dnf install` layer.
- `hadolint` staged from the host `lib/hadolint` into the build context in
  `ensure_bootstrap_image`, then `COPY`'d and `chmod +x`'d in the Containerfile.
  Uses the already-downloaded host binary rather than a second network fetch
  during image build.  Warns and continues if the host binary is absent.

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
