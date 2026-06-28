---
title: 'Streamline bootstrap interview: reduce questions, infer tooling, add QoL baseline'
type: requirement
status: done
lineage: bootstrap-interview-streamlining
created: "2026-06-28T00:00:00+10:00"
priority: high
labels:
    - ux
    - bootstrap
    - prompt
---

# Streamline Bootstrap Interview

## Problem

The bootstrap interview checklist had grown to 21 questions, many of which were
redundant (purpose + role asked the same thing), implied by framework defaults
(rootless, Podman-only, helper scripts always generated), or created recurring
format errors (EXTRA_ENV/EXTRA_VOLUMES always asked even when empty arrays were
correct).  Users experienced unnecessary friction before getting a working
container.

## Requirements

### R1 — Reduce to 8 questions

Collapse the checklist from 21 to 8:

1. Purpose & role (combined)
2. Agent runtime (codex / claude / gemini / other / none)
3. Language & runtime stack
4. Base image & OS packages (default fedora:latest, only ask if user volunteers)
5. Extra host mounts (gated — default nothing)
6. Persistent state (gated — default nothing)
7. Ports (gated)
8. Network & host resources (gated)

Drop: role/profile (merged into 1), build systems (inferred), developer tools
(inferred), package managers (inferred from language), source layout (framework
default), rootless/Docker questions (framework always rootless Podman), helper
scripts (always generated), README (always generated), env vars (passive only).

### R2 — Repo-review shortcut

If Q1 involves coding or code review and the user has an existing repo, the
agent reads the repo and pre-fills Q3 and Q4 directly.  No separate tooling
questions asked.

### R3 — Standard QoL baseline always installed

Every generated Containerfile must include: `git`, `gh`, `nano`, `neovim`,
`ripgrep`, `fzf`, `lazygit`, `pnpm`, `uv`.  Install methods documented per
distro.  Not asked during interview; just done.

### R4 — Language tooling inferred automatically

Standard linters, formatters, and build tools included per detected language
without asking:

| Language | Linters/formatters | Build |
|----------|--------------------|-------|
| Python | ruff, black, mypy, pylint | make |
| Node/TS | eslint, prettier, tsc | make |
| Go | golangci-lint, gofmt | make |
| Rust | rustfmt, clippy | make |
| Ruby | rubocop | make, rake |
| Java | checkstyle, spotbugs | maven/gradle |
| Shell | shellcheck | make |
| C/C++ | clang-format, cppcheck | make, cmake, ninja |

### R5 — Env vars and secrets passive

`EXTRA_ENV=()` by default.  Only populated if the user volunteers env vars or
secrets during the interview.  Format rules and examples provided in the prompt
for when they are needed, but never asked proactively.

### R6 — EXTRA_ENV/EXTRA_VOLUMES format reinforcement

Gated questions for Q5/Q6 include inline correct-format examples and explicit
wrong-form callouts.  Profile.env template in the prompt shows empty defaults
with commented populated examples and ⛔ wrong-form examples.

## Acceptance Criteria

- AC1: Interview completes in 8 questions or fewer for a typical coding project.
- AC2: Repo-review shortcut pre-fills stack without asking Q3/Q4.
- AC3: Generated Containerfiles include the full QoL baseline without user input.
- AC4: Standard language linters appear in generated Containerfiles without being asked.
- AC5: `EXTRA_ENV=()` appears in generated profile.env for projects with no env vars.
- AC6: Bare `KEY=VALUE` in `EXTRA_ENV` is not generated (format guidance effective).

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
