---
title: 'ai-new: Interactive Agent-Primed Project Bootstrap Container'
type: requirement
status: done
lineage: ai-new
created: "2026-06-22T00:00:00+10:00"
priority: normal
parent: lifecycle/requirements/ai-new-2.md
assignees:
    - role: analyst
      who: agent
    - role: product-owner
      who: agent
---

# ai-new: Interactive Agent-Primed Project Bootstrap Container

This artifact refines the clarified requirement `ai-new-2.md` into a detailed,
build-ready specification. All ten clarifying questions on the parent are resolved;
their resolutions are promoted here into firm functional requirements rather than
open questions. Remaining uncertainty is captured in **Open Questions** at the end.

## Problem

Standing up a new AI-agent project container today forces the user to hand-author a
`Containerfile`, a launch/build/update script set, an agent configuration, and a
project layout *before* they understand what the project needs. That presupposes
up-front knowledge of every runtime dependency, OS package, build system, mount
strategy, and host-resource requirement — exactly the knowledge a newcomer to a stack
lacks. The barrier to a tailored, reproducible project environment is therefore high
and error-prone.

The companion `ai-agent-podman-sandbox` framework establishes the durable sandbox
model (rootless Podman, `--userns=keep-id`, narrow workspace-only mounts, an
in-workspace `$HOME`, per-project profiles, and — per its R14/R16 — an `ai-new <name>`
generator and a request-driven environment builder). What is missing is a
low-friction, **agent-led front door** that produces those durable artifacts from a
plain conversation instead of from hand-editing.

`ai-new` fills that gap. `ai-new <name> --agent <agent>` scaffolds a project under the
jails directory and launches a deliberately minimal, **disposable** bootstrap
container. Inside it, `/start-here.sh` validates the selected agent runtime can
authenticate, then primes that agent with a structured bootstrap prompt. The agent —
not a hardcoded shell questionnaire — interviews the user, designs the container, and
generates the real, durable project `Containerfile` plus a complete sandbox scaffold.
The bootstrap container is then thrown away; the user reviews, builds, and runs the
durable image it generated.

## Goals / Non-goals

### Goals

- Provide a single `ai-new <name> [--agent <agent>]` command that scaffolds a project
  and launches a tiny, disposable bootstrap container with the lowest possible barrier
  to entry. This is the **same** command reserved by `ai-agent-podman-sandbox` R14, not
  a separate one.
- Ship `/start-here.sh` at the bootstrap container root as an **agent-priming
  launcher** — not a questionnaire and not a generator. It validates/selects the agent
  runtime, confirms authentication, launches the agent in the workspace, and hands it a
  structured bootstrap prompt.
  > **Superseded (location).** The root placement (`/start-here.sh`) is superseded by
  > `ai-new-container-setup-failures-2.md` R1. The script is now delivered into the
  > project scaffold home at `/project/bootstrap/home/start-here.sh` (via the `/project`
  > bind mount), not bind-mounted at the container root.
- Make the **agent responsible** for interviewing the user, progressively narrowing
  requirements, designing the container, generating the durable project files, and
  running a quality gate over the generated `Containerfile`.
- Keep the bootstrap image **minimal and disposable**: only the tooling needed to run
  `start-here.sh`, install/launch the *selected* agent runtime, validate credentials,
  and write workspace files. Project dependencies belong in the generated image only.
- Generate a **complete, immediately buildable minimal sandbox scaffold** that follows
  `ai-agent-podman-sandbox` conventions so the output drops cleanly into that
  framework.
- Persist generated files, agent config, and session state in a host-mounted workspace
  so they survive container disposal and support **resumable** bootstrap sessions.
- Give the user clear, explicit next steps (review → exit → build → relaunch) that
  reference real generated paths and commands.
- Support multiple agent runtimes (Codex, Gemini, and other supported
  runtimes) as the priming target, with the runtime chosen at `ai-new` time.

### Non-goals

- The bootstrap container is **not** the final development environment and must not
  grow into a general-purpose dev image carrying the project's full stack.
- `start-here.sh` is **not** a static decision tree and must not generate the project
  by itself.
- Not responsible for *running* the generated project image; its job ends after
  artifacts are written, the quality gate is reported, and next steps are given. (Note:
  it *does* attempt a trial build of the generated image as a quality gate — see R8 —
  but does not stand up the durable project for the user.)
- Not a hosted/CI/remote service; scope is a single user's local desktop with rootless
  Podman, same target as `ai-agent-podman-sandbox`.
- Does not bundle or vendor every AI agent runtime; only the selected runtime is
  installed in the bootstrap image.
- Does not guarantee the generated project is buildable without review — the user is
  explicitly asked to review before building.
- Does not mount host secrets, host `~/.ssh`, host config directories, or host agent
  sockets by default.

## Detailed Requirements

### R1. `ai-new` command

- R1.1 `ai-new <name>` creates a project scaffold and launches a minimal, disposable
  bootstrap container, dropping the user into it.
- R1.2 `ai-new` is the same command reserved by `ai-agent-podman-sandbox` R14 — it
  supersedes the purely non-interactive generator description there; there is no
  separate command name. `ai-new <name> --agent <agent>` creates the scaffold
  (workspace, image directory, starter profile, launchers, bootstrap Containerfile,
  bootstrap `/start-here.sh`) and selects the agent runtime to install.
- R1.3 `--agent <agent>` selects the agent runtime (Codex, Gemini, or another
  supported runtime). It is the preferred v1 path and determines which runtime is
  installed/made available in the bootstrap environment.
- R1.4 The bootstrap container launches under the sandbox framework's safety posture:
  no host secrets/SSH/config mounted by default, `--userns=keep-id`, a narrow writable
  workspace, and a contained in-workspace `$HOME`.
- R1.5 The bootstrap container launches with **network enabled by default** (required
  for agent API calls, authentication, package metadata, and trial builds). This is
  independent of the durable project's `NETWORK_MODE`.
- R1.6 `ai-new` provides `-h`/`--help` and exits non-zero with a clear message on
  failure (e.g. Podman unavailable, image build/pull failure, unknown agent runtime).
- R1.7 The bootstrap container is disposable; only the host-persisted workspace, agent
  config, generated files, and session notes survive (see R6).

### R2. Project layout & collision handling

- R2.1 Generated project scaffolds live under a single project directory at
  `$CODEX_JAILS_DIR/projects/<name>/`, defaulting to `~/codex-jails/projects/<name>/`.
- R2.2 The default generated layout is:
  - `$CODEX_JAILS_DIR/projects/<name>/workspace/`
  - `$CODEX_JAILS_DIR/projects/<name>/image/`
  - `$CODEX_JAILS_DIR/projects/<name>/profile.env`
  - `$CODEX_JAILS_DIR/projects/<name>/launchers/`
  - `$CODEX_JAILS_DIR/projects/<name>/bootstrap/`
  - `$CODEX_JAILS_DIR/projects/<name>/README.md`
- R2.3 The framework may maintain global command binaries under `$CODEX_JAILS_DIR/bin`,
  but project-specific artifacts stay grouped under the project root.
- R2.4 If `$CODEX_JAILS_DIR/projects/<name>` already exists and contains a **complete**
  scaffold, `ai-new` aborts by default rather than merging or overwriting.
- R2.5 If `$CODEX_JAILS_DIR/projects/<name>` exists but the bootstrap session is
  **incomplete**, re-running `ai-new <name>` resumes the existing bootstrap workspace
  (see R9) rather than starting from scratch.
- R2.6 A future explicit `--resume` mode may continue an incomplete session, and a
  future `--force` mode may recreate a scaffold after confirmation. (Out of v1 scope as
  explicit flags, but the default resume-on-incomplete behaviour of R2.5 is in scope.)

### R3. Bootstrap image (minimal & disposable)

- R3.1 The bootstrap image carries only enough to run `/start-here.sh`, install or
  connect to the **selected** agent runtime, validate credentials, provide a writable
  workspace, and write generated files.
- R3.2 The bootstrap image MUST NOT carry the eventual project's language/runtime
  stack, OS packages, build systems, or developer tools — those belong in the generated
  durable image.
- R3.3 The v1 bootstrap base image is `fedora:latest`. The base and bootstrap tooling
  are documented and kept small; any addition must be justified against R3.2.
- R3.4 Only the agent runtime selected via `--agent` is installed — not every supported
  runtime.

### R4. `/start-here.sh` (agent-priming launcher)

- R4.1 `/start-here.sh` lives at the filesystem root of the bootstrap container and is
  the single primary entrypoint the user runs after entering.
  > **Superseded (location).** The root location is superseded by
  > `ai-new-container-setup-failures-2.md` R1 and implemented in
  > `ai-new-container-setup-failures-3-be.md` B1. The script now lives at
  > `/project/bootstrap/home/start-here.sh` (under `$HOME` on the `/project` mount).
  > The root bind mount (`:/start-here.sh:ro,z`) has been removed. All other R4
  > behaviour is unchanged.
- R4.2 It MUST NOT contain a hardcoded questionnaire and MUST NOT attempt to generate
  the final project itself.
- R4.3 It determines the agent runtime: it uses the runtime selected at `ai-new` time;
  if exactly one runtime is available and none was specified, it may use it; if zero are
  available it fails with setup instructions; if multiple are available and none was
  specified it prompts the user to choose.
- R4.4 It validates that the selected runtime is present and can **authenticate before
  starting the interview** (see R10). On missing/invalid credentials it reports the
  failure clearly and gives the required setup command or file path, exiting non-zero.
- R4.5 It launches the selected agent in the current project workspace.
- R4.6 It hands the agent a structured **project-bootstrap prompt** instructing it to
  interview the user, design the container, generate the final project files, and run
  the quality gate (R8).
- R4.7 It must not exit in a way that strands the user without guidance; final
  next-step instructions are delegated to the agent (R7) but the launcher guarantees the
  user is not left without direction.
- R4.8 `/start-here.sh -h`/`--help` prints usage; failure paths exit non-zero with a
  clear message.

### R5. Agent interview responsibilities

- R5.1 Once launched, the agent asks targeted questions to understand the desired
  project environment, progressively narrowing requirements without overwhelming the
  user, then produces a concrete result.
- R5.2 The agent determines at minimum: project purpose; preferred agent runtime;
  desired project role/profile; target language/runtime stack; required OS packages;
  required developer tools; required package managers; required build systems; expected
  source/project layout; workspace mount strategy; persistent state requirements;
  exposed ports; environment variables; secrets/credentials to be mounted rather than
  baked in; network assumptions; host-resource needs (GPU, audio, USB, display, etc.);
  rootless-friendliness; Podman/Docker/both support; whether update/build/launch helper
  scripts should be generated; whether README/onboarding docs should be generated.
- R5.3 The agent asks follow-ups where needed but avoids exhaustive interrogation.
- R5.4 The agent explicitly distinguishes secrets/credentials that should be **mounted
  at runtime** from values that may be baked into the image, steering secrets toward
  runtime mounting (consistent with the sandbox framework's secrets policy).
- R5.5 The user MUST NOT install project software manually during the `ai-new` phase.
  Additional requirements are expressed to the agent and captured in the generated
  `Containerfile`, include fragments, profile, or helper scripts.

### R6. Generated project output

- R6.1 After gathering enough information, the agent generates the project scaffold into
  the workspace. v1 produces a **complete minimal sandbox scaffold**, not only a
  `Containerfile`, and each generated project must be immediately buildable and
  launchable through the sandbox framework.
- R6.2 The **most important output is the real project `Containerfile`** defining the
  durable development image.
- R6.3 The v1 output includes at least: the project workspace; the image directory; the
  real project `Containerfile`; a profile file; a launch wrapper or launch path; a
  build/update helper; a README with next steps; `.env.example`; `.gitignore`.
- R6.4 Generated profile/launcher/config artifacts follow `ai-agent-podman-sandbox`
  conventions (profile `.env` shape, `launchers/` wrappers) and derive paths from
  `$HOME`/`CODEX_JAILS_DIR` rather than hardcoding usernames.
- R6.5 Generated artifacts keep real secrets out of version control (provide
  `.env.example`, not populated secret files) and out of the image.

### R7. Persistence & user instructions

- R7.1 Generated files are written into a host-mounted workspace that survives disposal
  of the bootstrap container, so the user retains the output after exiting.
- R7.2 When generation completes, the agent tells the user the bootstrap container has
  finished its job and reports the quality-gate result (R8).
- R7.3 The final instructions tell the user to: (1) review the generated files, (2) exit
  the bootstrap container, (3) build the real project image from the generated
  `Containerfile`, and (4) relaunch into the new project container.
- R7.4 Instructions reference the actual generated file paths/commands, not generic
  placeholders.

### R8. Quality gate on generated `Containerfile`

- R8.1 After generating the scaffold, the agent attempts at least: (1) a Containerfile
  syntax/static check where available; (2) a trial `podman build` of the generated
  durable image; (3) inspection of build failures and one or more repair attempts.
- R8.2 If the build still fails, the agent summarizes what failed, what was attempted,
  and what the user should decide next.
- R8.3 The bootstrap phase is not complete until the generated files are reviewed and
  the quality-gate result is reported.

### R9. Resumable sessions

- R9.1 The bootstrap container is disposable, but the bootstrap workspace, agent config
  directory, generated files, and session notes persist on the host.
- R9.2 Re-running `ai-new <name>` against an incomplete scaffold resumes the existing
  bootstrap workspace rather than restarting, unless the user explicitly requests a
  reset.
- R9.3 Agent configuration directories (e.g. `.codex` or runtime equivalent) are
  persisted in the bootstrap workspace/home so authentication and settings survive
  bootstrap image rebuilds and resumed sessions.

### R10. Agent authentication

- R10.1 `start-here.sh` verifies the selected runtime can authenticate before starting
  the interview.
- R10.2 Credential sources, in order: (1) persisted agent config inside the bootstrap
  workspace/home (e.g. `.codex`); (2) profile/bootstrap env-file values when the runtime
  uses API keys; (3) an interactive login/setup flow initiated by the agent CLI, if
  supported.
- R10.3 No host secrets, host `~/.ssh`, host config directories, or host agent sockets
  are mounted by default.
- R10.4 If credentials are missing or invalid, `start-here.sh` reports the failure
  clearly and gives the required setup command or file path.

### R11. Design principle (disposable vs durable)

- R11.1 The bootstrap container is disposable; the generated project container is
  durable. All meaningful project dependencies, tools, runtimes, and configuration are
  declared in the generated `Containerfile` and installed during the real image build —
  never in the bootstrap image.

### R12. Non-functional

- R12.1 Scripts are POSIX/Bash where applicable, fail fast (`set -euo pipefail`), and
  run with no daemon beyond rootless Podman.
- R12.2 `ai-new` and `start-here.sh` provide help text and clear non-zero-exit error
  messages.
- R12.3 Targets Bazzite/Fedora with rootless Podman, consistent with
  `ai-agent-podman-sandbox`.

## Acceptance Criteria

- AC1. `ai-new <name> --agent <agent>` creates the scaffold at
  `$CODEX_JAILS_DIR/projects/<name>/` with the R2.2 layout and launches a minimal
  bootstrap container, dropping the user in; inspecting the bootstrap image confirms it
  contains no project language stack, build systems, or OS packages, and only the
  selected agent runtime.
- AC2. If `$CODEX_JAILS_DIR/projects/<name>` already exists complete, `ai-new` aborts
  without overwriting; if it exists incomplete, re-running resumes the existing
  bootstrap workspace.
- AC3. Inside the bootstrap container, `/start-here.sh` exists at the filesystem root
  and, when run, resolves the agent runtime (selected/single/prompt-on-multiple/fail-on-
  zero), validates authentication before any interview, and launches the agent in the
  workspace — without a hardcoded questionnaire and without generating the project
  itself.
  > **Superseded (location).** The root path is superseded by
  > `ai-new-container-setup-failures-2.md` R1. The script is at
  > `/project/bootstrap/home/start-here.sh`; the functional behaviour described here
  > is unchanged.
- AC4. When agent credentials are missing or invalid, `start-here.sh` reports the
  failure and the required setup command/path, exiting non-zero, and does not start the
  interview.
- AC5. The launched agent conducts an interactive interview covering at least the R5.2
  minimum set, asking follow-ups as needed, and steers secrets toward runtime mounting.
- AC6. At the end of a session the agent has written a complete minimal scaffold into
  the workspace: real project `Containerfile`, image directory, profile, launch wrapper/
  path, build/update helper, README with next steps, `.env.example`, and `.gitignore`.
- AC7. Generated secret handling uses a `.env.example`/runtime-mount pattern; no
  populated secret files are baked into the image or committed to Git.
- AC8. Generated profile/launcher/config artifacts follow `ai-agent-podman-sandbox`
  conventions and derive paths from `$HOME`/`CODEX_JAILS_DIR` (no hardcoded usernames).
- AC9. The agent runs the quality gate (static check where available, trial
  `podman build`, repair attempts) and reports the result; on persistent failure it
  summarizes what failed, what was attempted, and the user's next decision.
- AC10. Generated files persist after the user exits and the bootstrap container is
  removed; agent config persists across bootstrap image rebuilds/resumed sessions.
- AC11. On completion the agent states the bootstrap is done and gives the four next
  steps (review, exit, build from the generated `Containerfile`, relaunch), referencing
  actual generated paths/commands.
- AC12. The bootstrap container is launched with network enabled by default; the
  generated durable profile may independently set `NETWORK_MODE` (including `none`).
- AC13. Building the durable image from the generated `Containerfile` and relaunching
  into it yields the user's intended working environment (manual acceptance).
- AC14. `ai-new -h` and `/start-here.sh -h` print usage; failure paths (no Podman,
  build/pull failure, unknown agent runtime) exit non-zero with a clear message.

## Questions

The parent's ten clarifying questions are resolved and promoted into the requirements
above. The following implementation-level questions remain for planning:

- OQ1. **Session-notes format.** What concrete form do the persisted "session notes"
  (R9.1) take — a structured file the agent reads back on resume (e.g.
  `bootstrap/session.md` / `session.json`), and what minimum fields must it carry to
  reliably resume an interview?

  Resolved: bootstrap session state is persisted in two files:

- `bootstrap/session.md` — human-readable notes for the user and agent.
- `bootstrap/session.json` — machine-readable resume state for `ai-new`.

`session.md` records the interview summary, decisions made, unresolved questions,
generated files, quality-gate result, and next recommended action.

`session.json` records at minimum:

- project name;
- selected agent;
- bootstrap status: `started`, `interviewing`, `generated`, `quality-gate-running`,
  `quality-gate-failed`, `complete`;
- timestamp of last update;
- generated file list;
- Containerfile path;
- quality-gate status;
- last error, if any;
- resume command.

`ai-new` uses `session.json` to determine resume state, while the agent and user use
`session.md` for continuity.

- OQ2. **Supported-runtime registry.** Where is the authoritative list of supported
  `--agent` values defined, and how is each runtime's install method, auth-check
  command, and config-dir path declared so new runtimes can be added without editing
  `start-here.sh`?

  Resolved: supported agent runtimes are declared in registry files under:

`$CODEX_JAILS_DIR/config/agents.d/<agent>.env`

Each registry file defines:

- `AGENT_NAME`
- `AGENT_COMMAND`
- `AGENT_INSTALL_COMMAND`
- `AGENT_AUTH_CHECK_COMMAND`
- `AGENT_CONFIG_DIRS`
- `AGENT_ENV_VARS`
- `AGENT_PROMPT_MODE`

`ai-new --agent <agent>` validates the selected name against this registry. 
`start-here.sh` reads the selected runtime metadata from the scaffolded bootstrap
config and does not contain per-agent install/auth logic beyond the generic adapter
contract.

The framework may ship defaults for `codex`, `codex`, and `gemini`; users may add
new runtimes by adding registry files rather than editing framework scripts.

- OQ3. **Trial-build cost & opt-out.** The quality-gate trial `podman build` (R8.1) can
  be slow or pull large layers. Should there be a documented way to skip or time-box the
  trial build for constrained environments, and does skipping it block "complete" status?

Resolved: the trial build is required by default but may be explicitly skipped or
time-boxed.

Supported controls:

- `AI_NEW_SKIP_TRIAL_BUILD=1`
- `AI_NEW_BUILD_TIMEOUT=<duration>`
- future CLI equivalent: `ai-new <name> --skip-trial-build`

If the trial build is skipped, the bootstrap result status is:

`generated-unvalidated`

not:

`complete`

The agent must clearly report that no build validation was performed and that the
user must run the build manually before trusting the scaffold.

If the trial build times out, the status is:

`quality-gate-timeout`

and the session remains resumable.
  
- OQ4. **`--resume`/`--force` flag surface.** R2.6 defers explicit flags to a future
  cut. Confirm v1 ships only the implicit resume-on-incomplete behaviour, and define how
  "complete vs incomplete" scaffold state is detected (sentinel file? presence of the
  generated `Containerfile`? quality-gate pass marker?).

Resolved: v1 ships explicit `--resume`; `--force` remains deferred.

`ai-new <name>` behavior:

- no project exists: create new scaffold;
- project exists and `bootstrap/session.json` status is not `complete`: refuse
  ambiguous action and suggest `ai-new <name> --resume`;
- project exists and status is `complete`: abort;
- `ai-new <name> --resume`: resume an incomplete scaffold;
- `ai-new <name> --force`: deferred beyond v1.

Completeness is determined by `bootstrap/session.json`, not by guessing from file
presence alone.

A scaffold is complete only when:

- the real project `image/Containerfile` exists;
- required v1 scaffold files exist;
- the quality gate has either passed or been explicitly skipped;
- final next-step instructions have been written;
- `session.json` status is `complete` or `generated-unvalidated`.
  
- OQ5. **Bootstrap workspace vs generated workspace.** R6/R7 write the durable scaffold
  into `projects/<name>/`, while R9 persists a *bootstrap* workspace/home. Confirm these
  are the same mounted tree (agent runs with CWD at the project root) or two distinct
  mounts, and document the mapping.

  Resolved: the bootstrap workspace and generated scaffold live in the same mounted
project tree.

The host path:

`$CODEX_JAILS_DIR/projects/<name>/`

is mounted into the bootstrap container as:

`/project`

The agent runs with CWD:

`/project`

The durable generated project files are written directly under `/project`:

- `/project/workspace/`
- `/project/image/Containerfile`
- `/project/profile.env`
- `/project/launchers/`
- `/project/bootstrap/session.md`
- `/project/bootstrap/session.json`

The bootstrap container's HOME is also inside the same mounted project tree:

`/project/bootstrap/home`

Agent config directories such as `.codex` or `.codex` persist under that bootstrap
home unless the selected runtime requires a different documented path.

This keeps all project-specific bootstrap state, generated files, session notes, and
agent config grouped under one project directory.

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
