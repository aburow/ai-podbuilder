---
title: Reliable release process that publishes and verifies the install.sh asset — Backend Plan
type: plan-backend
status: draft
lineage: release-installer-asset-missing
parent: lifecycle/requirements/release-installer-asset-missing-2.md
---

# Backend Plan — Reliable, Self-Verifying Release Flow

This is a **process/tooling** change, not a change to `install.sh` behaviour
(that script's content is owned by the `curl-install-script` lineage and is a
Non-goal here). The backend deliverables are:

1. A `VERSION` file at the repo root as the single source of truth for the
   release version (Q4).
2. A repeatable, idempotent release script `devops/release.sh` that encodes the
   ordered flow tag → release → upload → verify-asset → verify-public-URL with
   fail-closed ordering (R1–R6).
3. A GitHub Actions workflow `.github/workflows/release.yml`, triggered on tag
   push (Q1), that invokes the same script so the enforced steps run in CI.
4. A follow-up artifact capturing the deferred checksum/signature work (Q5
   answered "yes", but Non-goal for this lineage).

The advertised entry point stays exactly as documented:
`https://github.com/aburow/ai-podbuilder/releases/latest/download/install.sh`
(`REPO="aburow/ai-podbuilder"` in `install.sh:42`). Only `install.sh` is
uploaded as an asset (Q2).

---

## Milestone 1 — `VERSION` file as source of truth

**Description.** Introduce `VERSION` at the repo root holding the bare version
string (e.g. `0.52`). The release flow derives the tag and the
version-pinned URL from this file, and refuses to proceed if the file and the
git tag disagree (Q4 — "validate that the tag and asset content agree").

**Files to change.**
- `VERSION` (new): single line, no leading `v`, no trailing newline-noise
  (e.g. `0.52`).
- `devops/release.sh` (consumes it — see M2): `VERSION="$(<VERSION)"`; reject an
  empty/whitespace value with a step-named `die`.

**Acceptance criteria.**
- `VERSION` exists at the repo root and contains a single non-empty version
  token matching a sane pattern (e.g. `^[0-9]+\.[0-9]+(\.[0-9]+)?$`).
- The release flow reads the version from `VERSION` and uses it verbatim for the
  tag and `gh release` calls — no hard-coded version anywhere in the flow.
- When the requested/pushed tag does not equal the `VERSION` contents, the flow
  exits non-zero naming the mismatch before any release is created (Q4).

## Milestone 2 — `devops/release.sh`: ordered, idempotent release flow

**Description.** One script that performs, **in order** (R5): tag creation →
release creation → `install.sh` asset upload → asset verification → public-URL
verification. Strict mode, step-named failures, and idempotent on re-run so a
partially-failed release is repaired by re-running the same command (R5, R6).

**Files to change.**
- `devops/release.sh` (new):
  - `#!/usr/bin/env bash` + `set -euo pipefail`; `die()`/`info()` helpers in the
    style of `install.sh` (step name + message to stderr, non-zero exit).
  - `VERSION="$(<"${REPO_ROOT}/VERSION")"`; validate (M1).
  - **Tag** (`create_tag`): create the annotated tag `"$VERSION"` if absent and
    push it; if the tag already exists pointing at the same commit, continue
    (idempotent); if it exists pointing elsewhere, `die`.
  - **Release** (`create_release`): `gh release create "$VERSION" …` if the
    release does not exist; if it exists, skip creation and continue (idempotent
    repair path).
  - **Upload** (`upload_asset`, R1): `gh release upload "$VERSION" install.sh
    --clobber` so re-runs replace rather than fail.
  - Each function called in the fixed order; the script never reaches a later
    step if an earlier one failed (strict mode + explicit checks).

**Acceptance criteria.**
- `devops/release.sh` run for a fresh version creates the tag, the release, and
  uploads `install.sh` exactly once, in that order.
- Re-running against an already-published version re-uploads via `--clobber`,
  re-runs every verification, and exits 0 (idempotent — AC5, R5).
- Any step failure exits non-zero with a message naming the failing step (R6).
- `shellcheck devops/release.sh` passes with no new warnings.

## Milestone 3 — Asset verification gate (R2)

**Description.** After upload, assert the asset is actually present and fully
uploaded before the flow may continue. An empty `assets` array — the exact
`0.51` failure mode — must be treated as failure.

**Files to change.**
- `devops/release.sh`: `verify_asset()`:
  - `gh release view "$VERSION" --json assets` parsed with `jq` (or `--jq`).
  - Assert an asset named `install.sh` exists with `state == "uploaded"` and
    `size > 0`.
  - Empty/missing `assets` → `die "verify_asset" "no install.sh asset on
    release $VERSION"` (R2).

**Acceptance criteria.**
- With `install.sh` uploaded, the gate passes and reports the asset name/size.
- With the asset removed (or never uploaded), the gate exits non-zero and the
  message names the missing asset (AC4, R2).
- An asset present but in a non-`uploaded` state, or zero size, also fails.

## Milestone 4 — Public latest-URL + content smoke check (R3, R4)

**Description.** Verify the **public, unauthenticated** `latest/download` URL —
the documented entry point — returns 200 and serves the real script, following
redirects, without executing it. This is the check that would have caught
`0.51`. Q3: these run for real over the network as part of the local release at
this stage; the script honours a documented skip flag but defaults to running.

**Files to change.**
- `devops/release.sh`:
  - `verify_public_url()` (R3): `curl -I -L
    "https://github.com/${REPO}/releases/latest/download/install.sh"`; assert a
    final `HTTP …/2 200`. Exercise the `/releases/latest/download/` path (not the
    version-pinned `/download/<version>/` path) so "latest" actually resolves.
    Non-200 → `die` naming the 404/URL.
  - `verify_content()` (R4): `curl -fsSL <latest-url>` into a temp file (never
    piped to `bash`); assert first line is `#!/usr/bin/env bash` and the body
    contains a stable marker (`REPO="aburow/ai-podbuilder"`); print the first
    lines with `head`.
  - `REPO="aburow/ai-podbuilder"` defined once and shared.
  - A `--skip-network` flag (or `RELEASE_SKIP_NETWORK=1`) bypasses R3/R4 for
    offline runs; when used, the flow logs loudly that public verification was
    skipped so it is never silently considered "verified" (Q3).

**Acceptance criteria.**
- `curl -I -L` against the latest URL returns HTTP 200 immediately after a
  successful flow (AC2); a 404 fails the flow naming the unreachable URL (AC4).
- The content check confirms a valid shebang + known marker and does **not**
  pipe the script into `bash` (R4, AC3).
- When network verification is skipped, the run prints an explicit
  "verification skipped" warning and does not report a fully-verified release.

## Milestone 5 — Fail-closed ordering & exit contract (R6)

**Description.** Tie the steps together so a release is never reported
successful, marked done, or announced until R2 **and** R3 have passed. Failure
messages distinguish a missing asset from a non-200 URL.

**Files to change.**
- `devops/release.sh`:
  - `main()` runs the steps in order; only after `verify_asset`,
    `verify_public_url`, and `verify_content` all pass does it print the final
    success summary (version, asset name/size, verified URL).
  - Distinct, identifiable failure messages: "missing/!uploaded asset" vs
    "public URL returned <code>".
  - Exit 0 only on full success; non-zero otherwise.

**Acceptance criteria.**
- No "success"/"done" output appears on any path where R2 or R3 failed (R6).
- The final non-zero message unambiguously identifies whether the asset or the
  public URL was the failure (R6).
- The success summary prints only after every verification passed.

## Milestone 6 — GitHub Actions release workflow (Q1)

**Description.** Add the repo's first workflow, triggered on tag push, that runs
the same `devops/release.sh` so the enforced upload+verification cannot be
bypassed by CI. `.github/` does not exist yet; this creates it.

**Files to change.**
- `.github/workflows/release.yml` (new):
  - `on: push: tags: ['*']` (Q1 — tag-push trigger).
  - A single job: checkout, ensure `gh`/`jq`/`curl` available, set
    `GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}`, then run `devops/release.sh`.
  - Job fails (non-zero) when the script fails, so a release that does not pass
    R2/R3 surfaces as a red build (R6).

**Acceptance criteria.**
- Pushing a tag that equals `VERSION` triggers the workflow, which uploads
  `install.sh` and runs all verifications via `devops/release.sh`.
- A verification failure makes the workflow job fail (red), never green-on-
  broken (R6, AC4).
- The workflow calls the **same** script as the local flow (no divergent inline
  logic), keeping local and CI behaviour identical.

## Milestone 7 — Deferred checksum/signature follow-up (Q5)

**Description.** Q5 answered "yes" to publishing a checksum/signature, but it is
an explicit Non-goal of this lineage. Capture it so it is not lost, without
implementing it here.

**Files to change.**
- `lifecycle/ideas/release-asset-integrity.md` (new): idea artifact (own
  lineage) describing publishing a `install.sh.sha256` and/or signature as
  additional release assets and a `curl | sha256sum -c` verification step, with
  `parent:` pointing at this requirement for traceability.

**Acceptance criteria.**
- A new idea artifact exists describing the checksum/signature follow-up and
  references this requirement.
- No checksum/signature code is added to `devops/release.sh` in this lineage
  (stays within Non-goals).
