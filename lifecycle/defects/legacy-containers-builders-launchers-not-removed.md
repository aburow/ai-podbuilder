---
title: Legacy Containers, Builders, and Launchers Not Removed from Repo and GitHub
type: defect
status: abandoned
lineage: legacy-containers-builders-launchers-not-removed
created: "2026-06-26T12:30:35+10:00"
priority: normal
labels:
    - defect
---

# Legacy Containers, Builders, and Launchers Not Removed from Repo and GitHub

## Summary

Legacy container definitions, builder scripts, and launcher artifacts remain present both in the local repository and on GitHub. These obsolete components clutter the development environment and may conflict with current tooling or introduce confusion about which components are authoritative.

## Reproduction Steps

1. Clone or inspect the repository locally and on GitHub.
2. Observe the presence of legacy container definitions (e.g. old Dockerfiles, Containerfiles, or compose files), builder scripts, and launcher entry points that are no longer part of the active development workflow.
3. Attempt to set up or verify the development environment — legacy artifacts create ambiguity about which components to use.

## Expected Behaviour

The repository (both locally and on GitHub) should contain only the current, active containers, builders, and launchers required by the development environment. Legacy artifacts should be fully removed so that no stale or unused components remain.

## Actual Behaviour

Legacy containers, builders, and launchers are still present in the repository. They have not been removed locally or from GitHub, and it has not been verified that they are no longer needed by any part of the development environment.

## Logs / Output

Not provided
