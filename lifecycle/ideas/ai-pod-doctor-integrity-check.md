---
title: 'ai-pod-doctor: System File Integrity Verification Command'
type: idea
status: clarifying
lineage: ai-pod-doctor-integrity-check
created: "2026-06-27T12:55:40+10:00"
priority: normal
labels:
    - integrity
    - installer
    - release
---

# ai-pod-doctor: System File Integrity Verification Command

Add a new `ai-pod-doctor` command that validates all installed system files in `bin` and `lib` against the SHA checksums bundled with the detected release version. The command auto-detects which release is currently installed and pulls the corresponding checksum manifest from that version's tarball, ensuring validation is always performed against the correct baseline rather than a mismatched release set.

By default the report is exception-only, listing only files whose calculated SHA differs from the expected value. When the `--verbose` flag is supplied, all files are shown in a tabular format with columns for filepath/filename, expected hash, and calculated hash. When the `--diff` flag is supplied, a diff of each changed file is rendered to support advanced troubleshooting and root-cause analysis.

When discrepancies are detected, the user is offered an interactive repair option that replaces the corrupted or modified file with the original from the same-version release tarball, restoring the installation to a known-good state without requiring a full reinstall.
