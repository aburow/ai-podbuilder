# ai-pod-doctor — Command Reference

## Synopsis

```
ai-pod-doctor integrity-check [--verbose] [--diff] [--repair]
```

## Description

`ai-pod-doctor integrity-check` verifies every regular file under the
`bin/` and `lib/` directories of your installation against the release
tarball for the auto-detected version. It downloads the tarball for that
version, computes SHA-256 hashes of the tarball's contents, and compares
them against the installed copies.

A **clean** installation is one where every file in `bin/` and `lib/`
matches the release baseline byte-for-byte. Use this command after an
upgrade to confirm the update applied cleanly, when debugging unexpected
behaviour that might indicate a corrupted install, or as a routine
tamper-detection check in security-sensitive environments.

## Options

| Flag | Behaviour |
|---|---|
| *(none)* | Exception-only output. Prints only discrepant files. Silent exit 0 if clean. |
| `--verbose` | Tabular output of every checked file with status, path, expected hash, and actual hash. Sorted by path. |
| `--diff` | Unified diff for each modified file. May be combined with `--verbose`. |
| `--repair` | Non-interactive restore of all missing and modified files from the release tarball. No prompt. |

## Environment

| Variable | Description |
|---|---|
| `AI_PODMAN_JAILS_DIR` | Installation root (required). Set automatically by the installer; export it manually if needed. |

## Exit Codes

| Code | Condition |
|------|-----------|
| 0 | All files match manifest |
| 0 | Repair completed successfully |
| 1 | One or more discrepancies found (repair declined or not attempted) |
| 2 | Manifest fetch or validation failure |
| 3 | Version detection failure |
| 4 | Any other unexpected error |

## Examples

**Clean installation — silent exit:**

```sh
ai-pod-doctor integrity-check
# (no output, exits 0)
```

**Mismatch detected — exception-only output:**

```sh
ai-pod-doctor integrity-check
# MODIFIED  bin/ai-launch  expected=a3f1...  actual=9b02...
# exits 1
```

**Verbose run showing all files:**

```sh
ai-pod-doctor integrity-check --verbose
# STATUS    PATH                EXPECTED              ACTUAL
# OK        bin/ai-build        a3f1c8...             a3f1c8...
# OK        bin/ai-launch       9b02e4...             9b02e4...
# OK        lib/common.sh       c7d391...             c7d391...
# ...
# exits 0
```

**Diff for a modified file:**

```sh
ai-pod-doctor integrity-check --diff
# --- bin/ai-launch (release)
# +++ bin/ai-launch (installed)
# @@ -12,7 +12,7 @@
# -AGENT_TIMEOUT=120
# +AGENT_TIMEOUT=30
# exits 1
```

**Non-interactive repair:**

```sh
ai-pod-doctor integrity-check --repair
# Restored: bin/ai-launch
# exits 0
```

## Notes

- Temporary files (tarball, extracted files for diff and repair) are created
  under a private temp directory and removed on exit via `trap`, regardless of
  whether the command succeeds or fails.
- Files present in the installation but absent from the manifest produce a
  **warning** only and do not cause a non-zero exit by themselves.
- The command requires network access to download the release tarball; it will
  exit 2 if the tarball URL is unreachable.
- Interactive repair (without `--repair`) prompts before restoring files;
  declining leaves the installation unchanged and exits 1.

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
