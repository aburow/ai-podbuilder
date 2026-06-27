---
title: Release asset integrity — checksum and signature publishing
type: idea
status: done
lineage: release-asset-integrity
parent: lifecycle/requirements/release-installer-asset-missing-2.md
---

# Release Asset Integrity

Publish a `install.sh.sha256` (and optionally a GPG/sigstore signature) alongside
`install.sh` as additional release assets, and extend `devops/release.sh` to
verify the checksum after upload.

## Motivation

Q5 in the `release-installer-asset-missing` requirements answered "yes" to
publishing a checksum/signature but deferred the work as a Non-goal of that
lineage. This idea captures it so it is not lost.

## Proposed scope

- `devops/release.sh`: after uploading `install.sh`, compute and upload
  `install.sh.sha256` (`sha256sum install.sh > install.sh.sha256`).
- `verify_asset()`: assert both assets are present with `state=uploaded`.
- `verify_content()`: after downloading, run `sha256sum -c` against the
  published checksum file before inspecting content.
- Optional: GPG-sign the checksum file or use sigstore/cosign for
  supply-chain transparency.
- `install.sh` (owned by the `curl-install-script` lineage): document a
  `curl … | sha256sum -c` one-liner in the README for users who want to
  verify before running.

## Out of scope here

Changing the install.sh behaviour itself (that belongs in `curl-install-script`).

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
