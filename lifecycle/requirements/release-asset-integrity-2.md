---
title: Publish and verify a SHA-256 checksum for the install.sh release asset
type: requirement
status: blocked
lineage: release-asset-integrity
created: "2026-06-26T00:00:00+10:00"
priority: medium
parent: lifecycle/ideas/release-asset-integrity.md
labels:
    - release
    - installer
    - integrity
assignees:
    - role: product-owner
      who: agent
---

# Publish and verify a SHA-256 checksum for the install.sh release asset

## Problem

The release flow (`devops/release.sh`) uploads `install.sh` as a release asset
and verifies it is reachable over the public latest URL, but it publishes no
integrity material. A user running the documented one-liner —
`curl -fsSL .../releases/latest/download/install.sh | bash` — has no offered way
to confirm the script they fetched is the one that was released. A
man-in-the-middle, a corrupted CDN object, or a clobbered asset would not be
detected by either the releaser or the installing user.

Q5 of the `release-installer-asset-missing` requirement answered "yes" to
publishing a checksum/signature but deferred it as a Non-goal of that lineage.
This requirement captures that follow-up so it is not lost.

## Goals / Non-goals

### Goals

- Publish `install.sh.sha256` as a release asset alongside `install.sh` on every
  release, computed from the exact bytes that are uploaded.
- Extend the existing release verification so the checksum file is confirmed
  present (`state == "uploaded"`) and the downloaded `install.sh` validates
  against the published checksum before the release is declared verified.
- Document a copy-paste verification one-liner in the README so users can check
  `install.sh` before executing it.
- Keep the existing offline bypass (`RELEASE_SKIP_NETWORK=1`) behaviour
  consistent — network-dependent checksum verification is skipped, but the local
  checksum generation and upload still run.

### Non-goals

- GPG / sigstore / cosign signing of the checksum or asset. Raised as an Open
  Question; deferred to a possible follow-up lineage, not required here.
- Changing the content or behaviour of `install.sh` itself (owned by the
  `curl-install-script` lineage).
- Adding any new required release asset beyond `install.sh.sha256`.
- Changing the install URL, repository name, or the documented install one-liner.

## Detailed Requirements

### R1 — Generate the checksum from the uploaded bytes
`upload_asset()` (or an adjacent step) MUST compute the checksum from the same
`install.sh` file that is uploaded, in the repo root, before/alongside upload:

```bash
sha256sum install.sh > install.sh.sha256
```

The checksum file MUST be generated fresh on each run (never reused from a prior
build) so it always matches the asset actually published.

### R2 — Upload the checksum as a release asset
The flow MUST upload `install.sh.sha256` as a release asset using the same
idempotent `--clobber` pattern as `install.sh`, so re-running against an existing
release replaces it rather than failing.

### R3 — Verify the checksum asset is present
`verify_asset()` MUST assert that `install.sh.sha256` exists on the release with
`state == "uploaded"` and non-zero `size`, applying the same checks it already
applies to `install.sh`. A missing or non-`uploaded` checksum asset MUST fail the
release.

### R4 — Verify the downloaded content against the published checksum
`verify_content()` MUST, after downloading `install.sh` from the public URL,
download the published `install.sh.sha256` and confirm the downloaded script
matches it (`sha256sum -c`) **before** the existing shebang/marker inspection.
A checksum mismatch MUST fail the release with a message naming the mismatch.

Note: the `sha256sum` line records the filename; verification MUST run against the
locally downloaded file regardless of the recorded path (e.g. by checking the
hash, or normalising the filename) so a temp-file name does not cause a spurious
failure.

### R5 — Offline bypass consistency
When `RELEASE_SKIP_NETWORK=1`, the network-dependent checksum verification in R4
MUST be skipped with the same "NOT fully verified" warning the script already
emits, while local generation (R1) and upload (R2) still run. The skip path MUST
NOT silently pass off a release as fully verified.

### R6 — Fail-closed ordering
A release MUST NOT be reported as `VERIFIED` until R3 and (when network is
enabled) R4 have passed. Failures MUST exit non-zero identifying which check
failed (missing checksum asset vs. content/checksum mismatch).

### R7 — User-facing verification documentation
The README MUST document a verify-before-run one-liner for users, e.g.:

```bash
curl -fsSL .../releases/latest/download/install.sh -o install.sh
curl -fsSL .../releases/latest/download/install.sh.sha256 | sha256sum -c -
```

The documented unverified one-liner MAY remain as the quick path, but the
verified variant MUST be shown alongside it.

## Acceptance Criteria

1. After a release run, `gh release view <version> --json assets` shows both
   `install.sh` and `install.sh.sha256` with `state == "uploaded"` and non-zero
   size.
2. The published `install.sh.sha256` matches the published `install.sh`:
   downloading both and running `sha256sum -c` succeeds.
3. If the checksum asset is missing or does not match the uploaded `install.sh`,
   the release flow exits non-zero and reports the failure — it does NOT report
   `VERIFIED`.
4. Re-running the release flow against an already-published version is idempotent
   (checksum regenerated and re-uploaded via `--clobber`, re-verified).
5. With `RELEASE_SKIP_NETWORK=1`, generation and upload still occur, the
   network checksum check is skipped, and the run is reported as NOT fully
   verified.
6. The README shows a working verify-before-run one-liner using the published
   `.sha256` asset.

## Open Questions

1. **Signing:** Should we additionally GPG-sign or sigstore/cosign-sign the
   checksum file for supply-chain transparency, or is a published SHA-256
   sufficient for now? (Drives whether a follow-up lineage is needed.)
2. **Checksum format:** Single-file `sha256sum` output (`<hash>  install.sh`) vs.
   a bare hash — does any planned consumer need a specific format?
3. **Regression test:** Should a test in `tests/` assert the release flow fails
   on a tampered/mismatched checksum (mirroring the empty-assets regression test
   from the parent lineage)?
