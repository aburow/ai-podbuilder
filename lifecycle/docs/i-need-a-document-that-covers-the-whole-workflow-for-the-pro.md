---
title: I need a document that covers the whole workflow for the project from ai-new -> build -> launch -> etc
type: doc
status: approved
lineage: i-need-a-document-that-covers-the-whole-workflow-for-the-pro
created: "2026-06-23T12:53:40+10:00"
completed: "2026-06-23"
output: docs/i-need-a-document-that-covers-the-whole-workflow-for-the-pro.md
---

I need a document that covers the whole workflow for the project from ai-new -> build -> launch -> etc

This is needed so that a user can start at the beginning and quickly get an environment up and running.

At the end of the document we need an easy, step by step guide on how to deploy the tools into the users environment including knowledge of where the user needs to launch the tools from or specifics of how to launch.

## Produced

`docs/i-need-a-document-that-covers-the-whole-workflow-for-the-pro.md`

The document covers:

1. **What the framework does** — four commands, two container models.
2. **Prerequisites** — OS, rootless Podman, Bash 5+, network.
3. **Install the framework** — clone, PATH setup, verification.
4. **Two onboarding paths** — Path A (`ai-new`, agent-designed) and Path B (manual profile).
5. **Path A (`ai-new`)** — create, credential setup, agent interview, quality gate, review scaffold, resume.
6. **Path B (manual)** — Containerfile, profile fields, optional extras.
7. **`ai-build`** — build and rebuild workflow.
8. **`ai-launch`** — shell, agent, builder modes, all flags.
9. **`ai-terminal`** — second terminal attachment.
10. **`ai-list`** — inspect state.
11. **Day-to-day operations** — rebuild, reset, secrets, SSH keys.
12. **Desktop integration** — launcher scripts, `.desktop` files, Podman Desktop.
13. **Quick-Start Deployment Checklist** — five-phase numbered steps with exact commands; ends with a "where to launch each tool" table clarifying that all five framework commands are host-side only.

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
