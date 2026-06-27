---
title: 'ai-pod-doctor: System File Integrity Verification Command — Frontend Plan'
type: plan-frontend
status: draft
lineage: ai-pod-doctor-integrity-check
parent: lifecycle/requirements/ai-pod-doctor-integrity-check-2.md
created: "2026-06-27T00:00:00+10:00"
priority: normal
assignees:
    - role: frontend-developer
      who: agent
---

# ai-pod-doctor: System File Integrity Verification Command — Frontend Plan

The user-facing surface for this feature is documentation only: a section in
`README.md` covering the new command and a reference page in `docs/`. No UI
components exist in this project. Two milestones, two files.

## Milestone 1 — README: add `ai-pod-doctor integrity-check` usage section

**Description.** Add a new subsection under the existing "Commands" or
"Usage" heading in `README.md` documenting the `ai-pod-doctor integrity-check`
command. The section must cover:

- Purpose (one-sentence summary: verify installed `bin/` and `lib/` files
  against the release baseline).
- Prerequisites: `AI_PODMAN_JAILS_DIR` must be set (set automatically by the
  installer; note the user can also export it manually).
- Quick-start examples:
  ```
  # Check integrity silently (prints nothing and exits 0 if all OK)
  ai-pod-doctor integrity-check

  # Show all checked files
  ai-pod-doctor integrity-check --verbose

  # Show a diff for any modified file
  ai-pod-doctor integrity-check --diff

  # Restore modified/missing files automatically (no prompt)
  ai-pod-doctor integrity-check --repair
  ```
- Exit-code table (matching R9): 0 clean/repaired, 1 discrepancies, 2 fetch
  failure, 3 version unknown, 4 unexpected error.

**Files to change.**
- `README.md`

**Acceptance criteria.**
- The README section is present, renders correctly as GitHub-flavoured Markdown
  (no broken headings, code fences close).
- All four example invocations are shown.
- The exit-code table lists all five codes with their meanings.
- No existing README section is removed or reorganised.

## Milestone 2 — docs/: add full reference page `docs/ai-pod-doctor.md`

**Description.** Create `docs/ai-pod-doctor.md` as the full command reference.
Sections:

### Synopsis
```
ai-pod-doctor integrity-check [--verbose] [--diff] [--repair]
```

### Description
One paragraph explaining what the command checks (installed `bin/` and `lib/`
against the release tarball for the auto-detected version), what "clean" means,
and when to use it (post-upgrade verification, tamper detection, debugging a
broken install).

### Options
Table or definition list:

| Flag | Behaviour |
|---|---|
| *(none)* | Exception-only output. Prints only discrepant files. Silent exit 0 if clean. |
| `--verbose` | Tabular output of every checked file with status, path, expected hash, and actual hash. Sorted by path. |
| `--diff` | Unified diff for each modified file. May be combined with `--verbose`. |
| `--repair` | Non-interactive restore of all missing and modified files from the release tarball. No prompt. |

### Environment
- `AI_PODMAN_JAILS_DIR` — installation root (required; set by the installer).

### Exit codes
Full table from R9.

### Examples
At least three worked examples: clean run, mismatch detected, repair applied.

### Notes
- Temporary files are created under a private temp directory and removed on
  exit (normal and error).
- Files not present in the manifest (unexpected files) produce a warning only
  and do not cause a non-zero exit by themselves.
- The command requires network access to download the release tarball; it will
  exit 2 if the tarball URL is unreachable.

**Files to change.**
- `docs/ai-pod-doctor.md` (new)

**Acceptance criteria.**
- All sections listed above are present.
- All flags from the backend plan are documented.
- Exit codes 0–4 are listed with meanings matching R9.
- The file renders without errors as Markdown.

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
