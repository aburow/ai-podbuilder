---
title: Reliable release process that publishes and verifies the install.sh asset — Frontend Plan
type: plan-frontend
status: done
lineage: release-installer-asset-missing
parent: lifecycle/requirements/release-installer-asset-missing-2.md
---

# Frontend Plan — Release Docs & Checklist

**No web/UI surface.** This is a shell plugin (`web/`/`web/src` do not exist).
The only user-facing surface for this requirement is **documentation**: the
release checklist/runbook a human follows, and the README's install one-liner,
which must stay the canonical, tested path (R7). This plan owns those docs and
reviews the backend script's operator-facing output for consistency.

## Milestone 1 — Release checklist / runbook (R7)

**Description.** Document the asset-upload and verification steps so the
requirement survives even if the scripted flow in `devops/release.sh` is
bypassed (R7). The checklist mirrors the script's ordered steps and the manual
`gh`/`curl` commands from the requirement.

**Files to change.**
- `docs/releasing.md` (new):
  - The canonical flow: bump `VERSION` → push the matching tag → the workflow /
    `devops/release.sh` runs upload + verifications.
  - The exact verification commands an operator can run by hand:
    - `gh release upload <version> install.sh --clobber` (R1).
    - `gh release view <version> --json assets` and what "good" looks like
      (`install.sh`, `state == "uploaded"`, non-zero `size`) (R2).
    - `curl -I -L https://github.com/aburow/ai-podbuilder/releases/latest/download/install.sh`
      expecting HTTP 200 (R3).
    - `curl -fsSL <latest-url> | head` to eyeball the script — explicitly
      **never** piped into `bash` during verification (R4).
  - A "release is NOT done until asset-verify and URL-verify pass" note (R6).
  - That `VERSION` is the single source of truth and the tag must match it (Q4).

**Acceptance criteria.**
- `docs/releasing.md` exists and lists the asset-upload and public-URL
  verification steps in order (R7, AC6).
- The documented manual commands match those the backend script runs (no drift).
- The doc states the fail-closed rule (no "done" before R2 + R3 pass).

## Milestone 2 — README install one-liner stays canonical (R7)

**Description.** Ensure the README continues to advertise the documented
one-liner as the supported, tested install path, and link to the new release
runbook so maintainers find it. No change to the URL or the one-liner itself
(Non-goal: changing the URL/repo name/one-liner).

**Files to change.**
- `README.md`:
  - Confirm/keep the
    `curl -fsSL https://github.com/aburow/ai-podbuilder/releases/latest/download/install.sh | bash`
    one-liner exactly as documented.
  - Add a short "Releasing" pointer linking to `docs/releasing.md` (for
    maintainers), without altering the user-facing install instructions.

**Acceptance criteria.**
- The README install one-liner is unchanged and still points at the
  `latest/download/install.sh` URL (Non-goal respected; canonical path — R7).
- A maintainer-facing link to `docs/releasing.md` is present.
- `grep` confirms the documented URL in README matches the URL the smoke checks
  (R3/R4) verify — the doc and the test target the same address.

## Milestone 3 — Operator-output consistency review (no separate code)

**Description.** Review the operator-facing strings the backend flow prints
(step names, the asset-verify result, the public-URL result, the final
success/failure summary) so they read consistently with `docs/releasing.md` and
correctly distinguish a missing asset from a 404 (R6). Review gate only;
corrections land in `devops/release.sh`.

**Files to change.** None (review only; fixes in `devops/release.sh`).

**Acceptance criteria.**
- The script's failure messages name the same checks the runbook describes, and
  clearly separate "missing asset" from "public URL non-200" (R6).
- The success summary names the version, asset, and verified URL consistently
  with `docs/releasing.md`.
- Any "verification skipped" message (offline mode, Q3) is unambiguous that the
  release was not fully verified.

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
