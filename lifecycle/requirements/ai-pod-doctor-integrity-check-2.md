---
title: 'ai-pod-doctor: System File Integrity Verification Command'
type: requirement
status: approved
lineage: ai-pod-doctor-integrity-check
created: "2026-06-27T00:00:00+10:00"
priority: normal
parent: lifecycle/ideas/ai-pod-doctor-integrity-check.md
labels:
    - integrity
    - installer
    - release
assignees:
    - role: product-owner
      who: agent
---

# ai-pod-doctor: System File Integrity Verification Command

## Problem

Once the plugin is installed, there is no supported way to verify that the
files in `bin/` and `lib/` still match what was shipped in the release. A
file can drift silently — due to manual edits, failed partial upgrades,
filesystem corruption, or tampered deployments — and the user has no tool
to detect or repair the drift.

The existing release flow publishes versioned tarballs with SHA checksums
(see `release-asset-integrity` lineage), giving a canonical integrity
baseline per release. Nothing at the installed-system end consumes that
baseline today.

## Goals / Non-goals

### Goals

- Add an `ai-pod-doctor` subcommand (or standalone command) that checks
  installed `bin/` and `lib/` files against the SHA manifest from the
  corresponding release tarball.
- Auto-detect the currently installed release version so no explicit
  `--version` flag is required for the common case.
- Default output: exception-only — list only files whose computed SHA
  differs from the expected value. Silent exit (zero) when everything is
  clean.
- `--verbose` flag: tabular output of all checked files, showing filepath,
  expected hash, and computed hash.
- `--diff` flag: render a diff of every modified file to stdout to support
  root-cause analysis.
- Interactive repair option when discrepancies are found: replace each
  affected file with the original from the same-version release tarball.
- Exit zero when all checks pass; exit non-zero when any discrepancy is
  found or when the manifest cannot be fetched/verified.

### Non-goals

- Checking files outside `bin/` and `lib/` (configs, user data, state
  directories).
- Modifying the release flow or tarball format (upstream of this lineage).
- GPG / sigstore signing of manifests (deferred to `release-asset-integrity`
  lineage).
- Automated / scheduled integrity polling; this is an on-demand command.
- Network-free / air-gapped operation; the manifest must be fetchable from
  the release tarball URL.

## Detailed Requirements

### R1 — Release version auto-detection

The command MUST determine the installed release version without user input.
The detection mechanism MUST read from the canonical version marker already
written by the installer (e.g. a version file, a tagged directory, or a
header in a known `bin/` entry point). If no version can be detected the
command MUST exit non-zero with a clear message indicating that the
installed version is unknown and suggesting a reinstall.

### R2 — Manifest acquisition

The command MUST download the release tarball for the detected version from
the published release URL and extract only the checksum manifest from it
(i.e. the same SHA file validated by the `release-asset-integrity` flow).
The tarball MUST NOT be written to the installation tree; a temporary
working directory MUST be used and cleaned up on exit (normal and error).

The manifest MUST be validated against its published `.sha256` asset before
its contents are trusted. A manifest that fails this check MUST cause the
command to abort with a non-zero exit and an explicit tamper-or-corruption
warning.

### R3 — File enumeration

The command MUST enumerate all regular files under `bin/` and `lib/` of
the installation root. Symlinks MUST be followed and the resolved target
checked. Files present in the installation but absent from the manifest
MUST be reported as unexpected (warning, not error). Files present in the
manifest but absent from the installation MUST be reported as missing
(error).

### R4 — SHA comparison

For each file present in both the manifest and the installation the command
MUST compute the SHA-256 of the installed file and compare it byte-for-byte
with the manifest value. A mismatch MUST be recorded as a discrepancy.

### R5 — Default (exception-only) output

When run with no flags, only files with a discrepancy (mismatch, missing,
unexpected) MUST be printed. Each line MUST show at minimum: status tag,
relative file path, and — for mismatches — both the expected and computed
hashes. If no discrepancies exist the command MUST print nothing (or a
single "all files OK" line) and exit zero.

### R6 — `--verbose` output

When `--verbose` is supplied, every checked file MUST be included in the
output in a tabular format with columns: status, relative path, expected
hash, computed hash. Clean files show the expected hash in both hash
columns and a `OK` status. The table MUST be sorted by relative path.

### R7 — `--diff` flag

When `--diff` is supplied, for each file with a mismatch the command MUST
render a unified diff between the original (extracted from the release
tarball) and the installed version. The diff MUST be labelled with the
relative file path. `--diff` MAY be combined with `--verbose`.

### R8 — Interactive repair

When discrepancies are detected (missing or modified files), the command
MUST offer an interactive prompt asking the user whether to restore all
affected files from the release tarball. Accepting MUST replace each
affected file in-place, preserving the original file permissions.
Declining MUST leave the installation unchanged and exit non-zero. The
repair MUST NOT modify files that passed the integrity check.

A `--repair` flag MAY be accepted to apply the repair non-interactively
(without the prompt), to support scripted remediation.

### R9 — Exit codes

| Condition | Exit code |
|---|---|
| All files match manifest | 0 |
| One or more discrepancies found (and repair declined or not attempted) | 1 |
| Repair completed successfully | 0 |
| Manifest fetch or validation failure | 2 |
| Version detection failure | 3 |
| Any other unexpected error | 4 |

### R10 — Temp-file hygiene

All temporary files (tarball, extracted manifest, extracted originals for
diff/repair) MUST be created under a single temp directory and removed via
a `trap` on EXIT, regardless of how the command terminates.

## Acceptance Criteria

1. Running the command on a clean installation prints nothing (or "all
   files OK") and exits 0.
2. Manually replacing the content of a tracked file in `bin/` or `lib/`
   causes the command to exit 1 and print that file's path and both hashes.
3. `--verbose` on a clean installation prints a table row for every file
   in `bin/` and `lib/` with status `OK`, and exits 0.
4. `--diff` on a modified file prints a non-empty unified diff for that
   file and exits 1.
5. Accepting the interactive repair prompt restores the modified file to
   its release-baseline content; the command exits 0.
6. Declining the repair prompt leaves the file unchanged; the command exits 1.
7. Pointing the command at an installation with no detectable version marker
   exits 3 with a clear message.
8. If the release tarball is unreachable (network error) the command exits 2
   with a message naming the URL that failed.
9. The temp directory created during the run is absent after the command
   exits (both success and failure paths).
10. A file present in the installation but absent from the manifest is
    reported as unexpected (warning); a file in the manifest but absent from
    the installation is reported as missing (error, exit 1).

## Answers

1. **Version marker location:** Where exactly does the installer record the
   installed version? (A version file path, a `VERSION=` line in a script
   header, a directory name?) The auto-detection in R1 must anchor to a
   specific, stable location — needs confirmation before implementation.

Answer: VERSION is in the VERSION file at the moment - it does not appear to be part of the install.sh script at the moment.

2. **Manifest format:** Does the release tarball already contain a
   `sha256sums.txt` (or equivalent) covering `bin/` and `lib/` files, or
   does the command need to compute hashes from the tarball contents itself?
   If the latter, R2 needs to describe the computation rather than manifest
   extraction.

Answer: The command will have to calculate the from the tarball itself

3. **Installation root:** Is the installation root always a fixed path (e.g.
   `~/.local/share/podman-plugin`) or is it configurable? The enumeration
   in R3 must know where to look.

Answer: The location is set in an env var

4. **Repair permissions:** Should the repair step preserve the installed
   file's existing permissions, or always apply the permissions from the
   tarball entry? (Relevant when an admin-owned install is repaired by a
   non-root user.)

Answer: apply the permissions

5. **Unexpected files:** Should files present in the installation but absent
   from the manifest be a warning (exit 0 if no other errors) or an error
   (exit 1)? The current spec says warning — confirm this is acceptable for
   the use case.

Answer: Warning
