---
title: Curl-Driven Install Script for ai-podbuilder
type: idea
status: done
lineage: curl-install-script
created: "2026-06-26T14:34:09+10:00"
priority: normal
parent: lifecycle/defects/release-installer-asset-missing.md
---

# Curl-Driven Install Script for ai-podbuilder

Provide a single shell script that users can bootstrap via `curl | bash` (or download and run manually) to install only the required components of the ai-podbuilder project. The script should accept an optional positional argument for the install root, defaulting to `~/podman-jails` when none is given.

The installer must handle initial installation and idempotent updates: fetching the latest required files from the repository, placing them under the chosen directory, and emitting the shell environment changes (e.g. `PATH`, any project-specific variables) needed for the tooling to work. Environment wiring should be written to a sourced file (e.g. `~/.bashrc.d/podbuilder.sh` or equivalent) rather than mutated inline, so users can review and opt out.

Success criteria: a user on a fresh system can run `curl -fsSL <url> | bash` and have a fully functional ai-podbuilder installation; a returning user running the same command gets an in-place update with no manual steps required.
