---
title: 'ai-pod-doctor: System File Integrity Verification Command — Backend Plan'
type: plan-backend
status: draft
lineage: ai-pod-doctor-integrity-check
parent: lifecycle/requirements/ai-pod-doctor-integrity-check-2.md
created: "2026-06-27T00:00:00+10:00"
priority: normal
assignees:
    - role: backend-developer
      who: agent
---

# ai-pod-doctor: System File Integrity Verification Command — Backend Plan

Adds a new `bin/ai-pod-doctor` entry-point command and a supporting
`lib/integrity.sh` library. All integrity logic lives in `lib/integrity.sh`;
`bin/ai-pod-doctor` is a thin dispatcher that sources it. The installation
root is read from `${AI_PODMAN_JAILS_DIR}` (set by the installer and
re-exported by `lib/common.sh`). No changes to the release flow, tarball
format, or existing scripts.

## Milestone 1 — Entry point, version detection, and temp-dir hygiene (R1, R10)

**Description.** Create `bin/ai-pod-doctor` as the command entry point and
`lib/integrity.sh` as the shared library. `bin/ai-pod-doctor` sources
`lib/common.sh` and `lib/integrity.sh` then dispatches on `$1`; the only
subcommand in this lineage is `integrity-check` (or bare invocation with no
subcommand runs it directly as the primary action).

`lib/integrity.sh` opens with:

```bash
REPO="aburow/ai-podbuilder"

_ic_tmpdir=""
_ic_setup_tmpdir() {
    _ic_tmpdir="$(mktemp -d)"
    trap '_ic_cleanup' EXIT
}
_ic_cleanup() { [[ -n "${_ic_tmpdir}" ]] && rm -rf "${_ic_tmpdir}"; }
```

`detect_version()` reads `${AI_PODMAN_JAILS_DIR}/VERSION`. If the file is
absent or empty it prints a clear message and exits 3.

```bash
detect_version() {
    local vfile="${AI_PODMAN_JAILS_DIR}/VERSION"
    [[ -f "${vfile}" ]] || { echo "ERROR: no version marker at ${vfile}; reinstall required" >&2; exit 3; }
    VERSION="$(<"${vfile}")"
    [[ -n "${VERSION}" ]] || { echo "ERROR: VERSION file is empty; reinstall required" >&2; exit 3; }
}
```

**Files to change.**
- `bin/ai-pod-doctor` (new)
- `lib/integrity.sh` (new)

**Acceptance criteria.**
- `bin/ai-pod-doctor integrity-check --help` (or bare invocation) prints usage
  and exits 0.
- With `AI_PODMAN_JAILS_DIR` pointing at a directory that has a `VERSION`
  file, `detect_version` sets `VERSION` correctly.
- Removing `VERSION` causes exit 3 with a message containing "version" and
  "reinstall".
- `shellcheck -x bin/ai-pod-doctor lib/integrity.sh` passes with no errors.

## Milestone 2 — Tarball fetch and hash manifest construction (R2)

**Description.** `fetch_tarball()` downloads the release tarball for the
detected version into `${_ic_tmpdir}` and verifies it can be extracted.
`build_manifest()` then enumerates every regular file under `bin/` and `lib/`
inside the extracted tree and computes a SHA-256 for each, storing results in
the associative array `_ic_manifest` keyed by relative path (e.g.
`bin/ai-build`, `lib/common.sh`).

The tarball URL follows the GitHub archive convention:

```bash
TARBALL_URL="https://github.com/${REPO}/archive/refs/tags/v${VERSION}.tar.gz"
```

The leading directory component inside the archive (e.g.
`ai-podbuilder-${VERSION}/`) is detected dynamically — the same technique
used in `install.sh` — so the plan is resilient to minor naming variation:

```bash
INNER="$(tar tzf "${_ic_tmpdir}/release.tgz" | head -1 | cut -d/ -f1)"
tar xzf "${_ic_tmpdir}/release.tgz" -C "${_ic_tmpdir}"
```

Manifest construction iterates:

```bash
while IFS= read -r -d '' f; do
    rel="${f#"${_ic_tmpdir}/${INNER}/"}"
    _ic_manifest["${rel}"]="$(sha256sum "${f}" | awk '{print $1}')"
done < <(find "${_ic_tmpdir}/${INNER}/bin" "${_ic_tmpdir}/${INNER}/lib" \
             -type f -print0 2>/dev/null)
```

If `curl` fails (non-zero exit) the command prints the URL that failed and
exits 2.

**Files to change.**
- `lib/integrity.sh` — add `fetch_tarball()`, `build_manifest()`.

**Acceptance criteria.**
- With a reachable tarball URL, `build_manifest` populates `_ic_manifest`
  with at least one entry each for `bin/` and `lib/`.
- With an unreachable URL (DNS failure or HTTP 404), the command exits 2 and
  the message includes the attempted URL.
- After the command exits (any path), `${_ic_tmpdir}` is absent (trap fires).
- The tarball is never written under `${AI_PODMAN_JAILS_DIR}`.

## Milestone 3 — File enumeration and SHA comparison (R3, R4)

**Description.** `enumerate_installed()` walks `${AI_PODMAN_JAILS_DIR}/bin`
and `${AI_PODMAN_JAILS_DIR}/lib`, following symlinks (`-L` on `find`), and
collects all regular files as relative paths. `compare_files()` cross-
references against `_ic_manifest`:

- **Missing**: path in manifest but absent from installation → error bucket.
- **Unexpected**: path in installation but absent from manifest → warning bucket.
- **Mismatch**: path in both, but `sha256sum` of installed file differs from
  manifest value → discrepancy bucket.
- **OK**: path in both, hashes match.

All results are stored in associative arrays (`_ic_missing`, `_ic_unexpected`,
`_ic_mismatch`, `_ic_ok`) for use by the output and repair milestones.

**Files to change.**
- `lib/integrity.sh` — add `enumerate_installed()`, `compare_files()`.

**Acceptance criteria.**
- A file renamed out of `bin/` while it remains in the manifest is recorded in
  `_ic_missing`, not `_ic_mismatch`.
- A file added to `bin/` that is not in the manifest is recorded in
  `_ic_unexpected`, not `_ic_missing`.
- A file whose bytes are altered is recorded in `_ic_mismatch` with both the
  expected and actual hash stored.
- Symlinks to regular files are resolved; the resolved target's content is
  checked.

## Milestone 4 — Output modes: default, `--verbose`, `--diff` (R5, R6, R7)

**Description.** Three mutually-compatible output functions driven by flags
parsed in `bin/ai-pod-doctor`:

**Default (exception-only):** `print_exceptions()` iterates `_ic_missing`,
`_ic_unexpected`, `_ic_mismatch`. Each line format:

```
MISSING   lib/missing.sh
UNEXPECTED bin/extra-file
MODIFIED  bin/ai-new  expected=<hash>  actual=<hash>
```

If all three buckets are empty, prints `all files OK` and exits 0. Otherwise
exits 1.

**`--verbose`:** `print_verbose()` emits a tab-separated table for every file
in `_ic_ok` ∪ `_ic_mismatch` ∪ `_ic_missing` ∪ `_ic_unexpected`, sorted by
relative path, with columns: `STATUS`, `FILE`, `EXPECTED`, `ACTUAL`. Clean
files show the same hash in both hash columns and `OK` in STATUS.

**`--diff`:** `print_diffs()` iterates `_ic_mismatch`. For each entry it
extracts the original file from `${_ic_tmpdir}/${INNER}/<rel>` (already
present from M2) and runs:

```bash
diff -u "${_ic_tmpdir}/${INNER}/${rel}" "${AI_PODMAN_JAILS_DIR}/${rel}"
```

with the `---`/`+++` labels set to `a/${rel}` and `b/${rel}`. `--diff` may be
combined with `--verbose`.

**Files to change.**
- `lib/integrity.sh` — add `print_exceptions()`, `print_verbose()`,
  `print_diffs()`.
- `bin/ai-pod-doctor` — argument parsing for `--verbose` / `--diff`.

**Acceptance criteria.**
- Default mode on a clean installation: only `all files OK` on stdout, exit 0.
- Default mode with one mismatch: exactly one `MODIFIED` line with both hashes,
  exit 1.
- `--verbose` on a clean installation: one table row per `bin/` and `lib/`
  file, all with status `OK`, sorted by path, exit 0.
- `--diff` on a modified file: non-empty unified diff labelled with the
  relative path, exit 1.
- `--verbose --diff`: table plus diff both present in stdout.

## Milestone 5 — Interactive repair, `--repair` flag, and exit codes (R8, R9)

**Description.** `repair_files()` restores every file in `_ic_missing` and
`_ic_mismatch` from the extracted tarball tree (`${_ic_tmpdir}/${INNER}/`).
Restore procedure:

```bash
cp "${_ic_tmpdir}/${INNER}/${rel}" "${AI_PODMAN_JAILS_DIR}/${rel}"
# apply tarball permissions:
src_mode="$(stat -c '%a' "${_ic_tmpdir}/${INNER}/${rel}")"
chmod "${src_mode}" "${AI_PODMAN_JAILS_DIR}/${rel}"
```

Files in `_ic_ok` and `_ic_unexpected` are never modified.

Interactive path (default when discrepancies exist and `--repair` is not
passed): prompt on stderr:

```
Restore N file(s) from release v${VERSION}? [y/N] 
```

Accepting calls `repair_files()` and exits 0 on success. Declining exits 1
without touching any file.

`--repair` skips the prompt and calls `repair_files()` directly.

Exit-code wiring (all paths):

| Condition | Exit |
|---|---|
| All files match | 0 |
| Discrepancies, repair declined or not attempted | 1 |
| Repair completed successfully | 0 |
| Manifest fetch / tarball failure | 2 |
| Version detection failure | 3 |
| Unexpected error (`set -e` trap) | 4 |

**Files to change.**
- `lib/integrity.sh` — add `repair_files()`, `prompt_repair()`.
- `bin/ai-pod-doctor` — `--repair` flag, exit-code wiring.

**Acceptance criteria.**
- Accepting the interactive prompt restores the modified file to tarball
  content with tarball permissions; command exits 0 (AC5).
- Declining leaves the file unchanged; command exits 1 (AC6).
- `--repair` restores without prompting; command exits 0.
- Files that passed the integrity check are untouched after repair.
- Unexpected error in any subfunction exits 4 (via `trap ERR`).

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
