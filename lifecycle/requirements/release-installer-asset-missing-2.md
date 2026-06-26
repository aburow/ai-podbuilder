---
title: Reliable release process that publishes and verifies the install.sh asset
type: requirement
status: approved
lineage: release-installer-asset-missing
created: "2026-06-26T18:30:00+10:00"
priority: high
parent: lifecycle/defects/release-installer-asset-missing.md
labels:
    - release
    - installer
    - process
assignees:
    - role: product-owner
      who: agent
---

# Reliable release process that publishes and verifies the install.sh asset

## Problem

The documented installation entry point is a one-line bootstrap:

```bash
curl -fsSL https://github.com/aburow/ai-podbuilder/releases/latest/download/install.sh | bash
```

This URL is only served by GitHub for files that have been **explicitly uploaded
as release assets**. A Git tag, the source tree, or the source tarball is not
enough: GitHub does not synthesize `/releases/latest/download/<asset>` from
repository contents.

Release `0.51` was tagged and marked as the latest GitHub Release, but no assets
were uploaded. Every user who followed the documented install command received
`curl: (22) The requested URL returned error: 404`. The release nonetheless
verified tests, tag creation, and release metadata, so the process reported
success while the product was uninstallable. The failure was discovered only by
manually running the public install command after the fact.

The bootstrap `install.sh` is also load-bearing beyond being a static file: it
is the script that subsequently downloads the source tarball (`REPO`,
`fetch_release` in `install.sh:42`). If the asset is missing, the entire install
flow is broken at step one, regardless of the rest of the release being correct.

The root cause is procedural, not a code bug: the release flow has no step that
uploads `install.sh` as an asset and no post-publish smoke check that the public
installer URL is actually reachable. There is currently no scripted/automated
release flow at all (no release workflow under `.github/`, no release script),
so the upload and verification depend on a human remembering to do them.

## Goals / Non-goals

### Goals

- Guarantee that every published, installable release includes `install.sh` as a
  GitHub release asset, so `/releases/latest/download/install.sh` returns HTTP
  200.
- Make asset upload and public-URL verification an enforced, repeatable part of
  the release process rather than a manual remember-to-do-it step.
- Fail the release process loudly **before** it is considered complete if the
  public installer URL is not reachable or does not serve the expected script.
- Provide a single repeatable release command/flow that performs tag creation,
  release creation, asset upload, and public verification as one operation.
- Add a smoke test that fetches the installer over the public URL and confirms it
  is the expected script, without executing it.

### Non-goals

- Changing the content or behaviour of `install.sh` itself (its tarball-fetch
  logic, idempotent update behaviour, env-file wiring) — that is owned by the
  `curl-install-script` lineage.
- Changing the install URL, repository name, or the documented one-liner.
- Migrating release publishing to a specific CI provider as a hard requirement;
  CI is one acceptable implementation, a local scripted flow is another.
- Signing, checksums, or supply-chain hardening of the asset (may be raised as a
  follow-up; see Open Questions).

## Detailed Requirements

### R1 — Mandatory asset upload
The release process MUST upload `install.sh` as a release asset for every
release that is intended to be installable. Implementation reference:

```bash
gh release upload <version> install.sh --clobber
```

`--clobber` (or equivalent) MUST be used so re-running the step on an existing
release replaces the asset rather than failing.

### R2 — Post-publish asset verification
After publishing, the process MUST confirm the asset is present and in the
`uploaded` state before declaring the release complete:

```bash
gh release view <version> --json assets
```

The check MUST assert that an asset named `install.sh` exists with
`state == "uploaded"` and non-zero `size`. An empty `assets` array MUST be
treated as a release failure.

### R3 — Public latest-URL smoke check
The process MUST verify the public, unauthenticated latest URL returns HTTP 200
and serves the expected script (following redirects):

```bash
curl -I -L https://github.com/aburow/ai-podbuilder/releases/latest/download/install.sh
```

A non-200 result MUST fail the release. The check MUST exercise the
`/releases/latest/download/` path (the documented entry point), not only the
version-pinned `/download/<version>/` path, so that "latest" actually resolves.

### R4 — Content smoke test (no execution)
There MUST be a smoke test that fetches the installer from the public URL and
confirms it is the real script — e.g. first line is a `#!/usr/bin/env bash`
shebang and it contains a known marker — and prints the first lines **without
executing them**:

```bash
curl -fsSL https://github.com/aburow/ai-podbuilder/releases/latest/download/install.sh | head
```

This test belongs alongside the existing install tests in `tests/` (see
`tests/test_install_script.sh`) and MUST NOT pipe the downloaded script into
`bash`.

### R5 — Repeatable, scripted release flow
The four steps above MUST be encoded in a single repeatable artifact (a release
script, a `Makefile`/`just` target, or a CI workflow) that performs, in order:
tag creation → release creation → `install.sh` asset upload (R1) → asset
verification (R2) → public URL verification (R3). The flow MUST be idempotent on
re-run against an already-published version (re-upload via `--clobber`,
re-verify) so a partially-failed release can be repaired by re-running it.

### R6 — Fail-closed ordering
A release MUST NOT be reported as successful, tagged as "done", or announced
until R2 and R3 have passed. If verification fails, the flow MUST exit non-zero
with a message identifying which check failed (missing asset vs. non-200 URL).

### R7 — Documentation / checklist
The release checklist/docs MUST list the asset-upload and verification steps so
the requirement survives even if the scripted flow is bypassed. The documented
install one-liner MUST remain the canonical, tested path.

## Acceptance Criteria

1. Running the release flow for a new version produces a GitHub Release whose
   `gh release view <version> --json assets` shows an `install.sh` asset with
   `state == "uploaded"` and non-zero size.
2. `curl -I -L https://github.com/aburow/ai-podbuilder/releases/latest/download/install.sh`
   returns HTTP 200 immediately after the flow completes.
3. The content smoke test (R4) passes: the fetched file is the expected
   `install.sh` (valid shebang + known marker) and the test does not execute it.
4. If `install.sh` is deliberately not uploaded (or the upload is removed), the
   release flow exits non-zero and clearly reports the missing asset / 404 — it
   does NOT report success.
5. Re-running the release flow against an already-published version succeeds
   (idempotent), re-uploading the asset via `--clobber` and re-passing all
   verifications.
6. The release checklist/docs reference the asset-upload and public-URL
   verification steps.
7. A regression test exists in `tests/` that would have caught the original
   `0.51` failure (empty assets → 404 on the public URL).

## Answers

1. **Automation surface:** Should the release flow be a GitHub Actions workflow triggered on tag push, a local script invoked by the releaser, or both? There is currently no `.github/` workflow directory in the repo.

Answer: Trigger a workflow based on a tag push

2. **Additional assets:** Besides `install.sh`, should the release also attach the source tarball or other artifacts as named assets, or is the bootstrap `install.sh` (which fetches the tarball itself) the only required asset?

Answer: install.sh is the only required asset

3. **Network-dependent test:** The R3/R4 smoke checks require public network access to github.com. Should these be gated/skippable in offline CI runs (consistent with the existing `AI_PODMAN_INSTALL_TARBALL` offline bypass in `install.sh`), and how do we still guarantee they run for real releases?

Answer: I will test locally as a part of the upgrade at this stage

4. **Versioning source of truth:** Where does `<version>` (`0.51`, etc.) come from — a VERSION file, the latest tag, or manual input — and should the flow validate that the tag and asset content agree?

Answer: We should store it in a version file

5. **Integrity:** Out of scope for now, but should we publish a checksum and/or signature for `install.sh` so a piped `curl | bash` can be verified? (Possible follow-up defect/idea.)

Answer: yes
