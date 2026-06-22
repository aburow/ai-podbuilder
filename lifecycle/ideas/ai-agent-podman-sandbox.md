---
title: AI Agent Podman Sandbox
type: idea
status: draft
lineage: ai-agent-podman-sandbox
created: "2026-06-22T14:54:11+10:00"
priority: normal
---

# AI Agent Podman Sandbox

A reusable, profile-driven framework for running AI coding agents (Codex, Codex, Aider, OpenCode) on Bazzite with rootless Podman. Each project workspace is isolated under `~/codex-jails` with its own fake `$HOME` inside the container, and a small set of generic commands (`ai-build`, `ai-launch`, `ai-terminal`, `ai-list`) replaces a growing collection of per-project scripts that each hardcode slightly different launch parameters.

The framework introduces profile files (`profiles/<name>.env`) that declare the image name, container name, workspace path, container home, shell startup file, extra devices, extra volumes, extra environment variables, and build arguments for each project. Generic commands source the profile at runtime, eliminating drift between workspaces. Privileged builder mode is explicitly opt-in (`ai-launch uxplay builder`) so the higher-risk path is always visible and intentional, while normal sandbox mode uses `--userns=keep-id`, `--security-opt no-new-privileges`, and a narrow workspace-only volume mount.

Existing per-project script names are preserved as thin compatibility wrappers that delegate to `ai-launch`, keeping current muscle memory intact during migration. Planned enhancements include network policy levels (`NETWORK_MODE=none` for offline review), per-profile secret env files, desktop launcher generation for KDE and GNOME, an `ai-doctor` health-check command, and eventual packaging as a cloneable Git repository for reuse across Bazzite systems.

Each Container will be available and launchable from within podman as well as via the cli.

The user will be able to make a plain text request to build an environment for a specifc project type - ie "I want to build a rust program for an ubuntu release x.y.z amd64 and for raspbian x.y.z on the raspi5"

The appropriate container and base libraries will be made available. Clashes will need to be presented back to the user in the event that the request is not an optimal path or a highly costly path.
