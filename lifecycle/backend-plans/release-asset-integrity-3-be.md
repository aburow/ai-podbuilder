---
title: Publish and verify a SHA-256 checksum for the install.sh release asset — Backend Plan
type: plan-backend
status: draft
lineage: release-asset-integrity
parent: lifecycle/requirements/release-asset-integrity-2.md
created: "2026-06-26T00:00:00+10:00"
priority: medium
assignees:
    - role: backend-developer
      who: agent
---

# Publish and verify a SHA-256 checksum for the install.sh release asset — Backend Plan

Adds checksum generation, upload, and verification to `devops/release.sh`. All
changes live in that one file (README is the frontend plan). The flow already
has the right seams — `upload_asset`, `verify_asset`, `verify_content` — so each
milestone extends an existing function rather than adding new machinery.

## ⚠ Open question / blocker — checksum target (Q2)

Requirement body (R1–R7) and every acceptance criterion specify the checksum is
computed over **`install.sh`**. The Q2 answer instead says "calculated against
the tgz not install.sh". `devops/release.sh` uploads only `install.sh`; it
manages no tgz — the tarball `install.sh` consumes is GitHub's auto-generated
source archive (see `install.sh` `fetch_release`), whose bytes the releaser does
not control or upload.

This plan implements the **`install.sh`** interpretation (R1–R7, AC1–AC6) because
it is concrete and self-consistent. If the intent is to checksum a tarball, that
needs a prior decision the requirement does not contain: *which* tarball, and
whether `release.sh` must build/upload it. **Confirm before development starts.**
If the answer is the GitHub source tarball, that is a different (larger) lineage.

## Milestone 1 — Generate the checksum from the uploaded bytes (R1)

**Description.** In `upload_asset()`, before the `gh release upload` call, compute
the checksum from the exact `install.sh` being uploaded, into the repo root, on
every run (never reuse a prior file):

```bash
( cd "${REPO_ROOT}" && sha256sum install.sh > install.sh.sha256 )
```

Generate it inside `REPO_ROOT` so the recorded filename is the bare
`install.sh` (no path), matching the `sha256sum -c` expectation in M3.

**Files to change.** `devops/release.sh` — `upload_asset()`.

**Acceptance criteria.**
- After `upload_asset` runs, `${REPO_ROOT}/install.sh.sha256` exists and contains
  one line of the form `<64-hex>␠␠install.sh`.
- The hash equals `sha256sum < install.sh` for the file just uploaded
  (regenerated each run — deleting it before a run still yields a correct file).

## Milestone 2 — Upload the checksum as a release asset (R2)

**Description.** After uploading `install.sh`, upload `install.sh.sha256` with the
same idempotent `--clobber` pattern (same `gh release upload "${version}" … --repo
"${REPO}" --clobber` call, second asset). Re-running against an existing release
replaces it rather than failing.

**Files to change.** `devops/release.sh` — `upload_asset()`.

**Acceptance criteria.**
- A release run uploads both `install.sh` and `install.sh.sha256`.
- Re-running against an already-published version regenerates and re-uploads the
  checksum via `--clobber` without error (AC4).

## Milestone 3 — Verify the checksum asset is present (R3)

**Description.** Extend `verify_asset()` to apply its existing
name/`state == "uploaded"`/`size > 0` assertions to `install.sh.sha256` as well as
`install.sh`. Factor the three checks into a small local loop or helper over the
asset names so the logic is asserted once, not copy-pasted. A missing or
non-`uploaded`/zero-size checksum asset must `die` (non-zero exit) naming the
checksum asset specifically.

**Files to change.** `devops/release.sh` — `verify_asset()`.

**Acceptance criteria.**
- With both assets `uploaded`, `verify_asset` passes (AC1).
- Drop/withhold the `.sha256` asset → `verify_asset` exits non-zero with a message
  identifying `install.sh.sha256` (AC3, R6).

## Milestone 4 — Verify downloaded content against the published checksum (R4)

**Description.** In `verify_content()`, after the existing `install.sh` download
into `${tmp}` and **before** the shebang/marker inspection, download the published
`install.sh.sha256` from
`https://github.com/${REPO}/releases/latest/download/install.sh.sha256` and verify
the downloaded script against it. Because the published checksum records the
filename `install.sh` but the download lives at `${tmp}`, verify by **hash
comparison**, not by feeding the recorded path to `sha256sum -c`:

```bash
published="$(awk '{print $1}' "${tmp_sum}")"
actual="$(sha256sum "${tmp}" | awk '{print $1}')"
[[ "${published}" == "${actual}" ]] || die "verify_content" \
  "checksum mismatch: published ${published} != downloaded ${actual}"
```

Add `${tmp_sum}` to the existing `trap … RETURN` cleanup. The mismatch `die`
message must name it as a checksum mismatch (distinct from the M3 "missing asset"
failure, per R6).

**Files to change.** `devops/release.sh` — `verify_content()`.

**Acceptance criteria.**
- Matching asset → checksum check passes, then existing shebang/marker checks run
  (AC2).
- Tampered downloaded script (or wrong published hash) → non-zero exit, message
  naming the mismatch, and the run does **not** report `VERIFIED` (AC3, R6).
- Ordering: checksum verified before shebang/marker inspection.

## Milestone 5 — Offline bypass consistency & fail-closed reporting (R5, R6)

**Description.** The R4 download/compare sits inside `verify_content()`, which
already early-returns with the "NOT fully verified" warning when
`RELEASE_SKIP_NETWORK=1` — so generation (M1) and upload (M2) still run while the
network checksum check is skipped; no extra branch needed. Confirm `main()`'s
final summary still distinguishes skipped vs. fully-verified, and that no path
reports `VERIFIED` when M3 failed or (network-enabled) M4 failed. Update the
`main()` summary block to list `install.sh.sha256` alongside `install.sh`.

**Files to change.** `devops/release.sh` — `verify_content()` (confirm skip path),
`main()` (summary lists the checksum asset).

**Acceptance criteria.**
- `RELEASE_SKIP_NETWORK=1`: M1 + M2 still run; M4 skipped with the existing
  warning; summary reports NOT fully verified (AC5, R5).
- No failure path prints `VERIFIED`; every failure exits non-zero identifying
  which check failed — missing checksum asset (M3) vs. content/checksum mismatch
  (M4) (R6).
- `main()` success summary names both `install.sh` and `install.sh.sha256`.
