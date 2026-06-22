---
title: 'ai-new: Interactive Agent-Primed Project Bootstrap Container'
type: requirement
status: blocked
lineage: ai-new
created: "2026-06-22T00:00:00+10:00"
priority: normal
parent: lifecycle/requirements/ai-new-3.md
assignees:
    - role: analyst
      who: agent
    - role: product-owner
      who: agent
---

# ai-new: Interactive Agent-Primed Project Bootstrap Container

This artifact refines `ai-new-3.md` into a build-ready specification. The five
implementation-level questions raised in the parent's **Questions** section (OQ1–OQ5)
are resolved there; their resolutions are **promoted into firm functional requirements**
here — concrete file formats, the runtime registry contract, trial-build controls,
explicit resume/force surface, and the single-mount layout. Requirements are renumbered
and expanded so each is independently testable. Remaining uncertainty — now strictly at
the planning/implementation level — is captured in **Open Questions**.

## Problem

Standing up a new AI-agent project container today forces the user to hand-author a
`Containerfile`, launch/build/update scripts, an agent configuration, and a project
layout *before* they understand what the project needs. That presupposes up-front
knowledge of every runtime dependency, OS package, build system, mount strategy, and
host-resource requirement — exactly the knowledge a newcomer to a stack lacks. The
barrier to a tailored, reproducible project environment is therefore high and
error-prone.

The companion `ai-agent-podman-sandbox` framework establishes the durable sandbox model
(rootless Podman, `--userns=keep-id`, narrow workspace-only mounts, an in-workspace
`$HOME`, per-project profiles, and — per its R14/R16 — an `ai-new <name>` generator and a
request-driven environment builder). What is missing is a low-friction, **agent-led
front door** that produces those durable artifacts from a plain conversation instead of
from hand-editing.

`ai-new` fills that gap. `ai-new <name> --agent <agent>` scaffolds a project under the
jails directory and launches a deliberately minimal, **disposable** bootstrap container.
Inside it, `/start-here.sh` validates the selected agent runtime can authenticate, then
primes that agent with a structured bootstrap prompt. The agent — not a hardcoded shell
questionnaire — interviews the user, designs the container, generates the real durable
project `Containerfile` plus a complete sandbox scaffold, and runs a build quality gate.
The bootstrap container is then thrown away; the user reviews, builds, and runs the
durable image it generated.

## Goals / Non-goals

### Goals

- Provide a single `ai-new <name> [--agent <agent>] [--resume] [--skip-trial-build]`
  command that scaffolds a project and launches a tiny, disposable bootstrap container
  with the lowest possible barrier to entry. This is the **same** command reserved by
  `ai-agent-podman-sandbox` R14, not a separate one.
- Ship `/start-here.sh` at the bootstrap container root as an **agent-priming launcher** —
  not a questionnaire and not a generator. It resolves/validates the agent runtime,
  confirms authentication, launches the agent in the project tree, and hands it a
  structured bootstrap prompt.
- Make the **agent responsible** for interviewing the user, progressively narrowing
  requirements, designing the container, generating the durable project files, and
  running a build quality gate over the generated `Containerfile`.
- Keep the bootstrap image **minimal and disposable**: only the tooling needed to run
  `start-here.sh`, install/launch the *selected* agent runtime, validate credentials, and
  write workspace files. Project dependencies belong in the generated image only.
- Generate a **complete, immediately buildable minimal sandbox scaffold** that follows
  `ai-agent-podman-sandbox` conventions so the output drops cleanly into that framework.
- Persist generated files, agent config, and session state under one host-mounted project
  tree so they survive container disposal and support **resumable** bootstrap sessions.
- Define an **extensible runtime registry** so new `--agent` values can be added by
  dropping a file in, not by editing framework scripts.
- Give the user clear, explicit next steps (review → exit → build → relaunch) that
  reference real generated paths and commands.

### Non-goals

- The bootstrap container is **not** the final development environment and must not grow
  into a general-purpose dev image carrying the project's full stack.
- `start-here.sh` is **not** a static decision tree and must not generate the project by
  itself, nor contain per-agent install/auth logic beyond the generic adapter contract.
- Not responsible for *running* the generated project image; its job ends after artifacts
  are written, the quality gate is reported, and next steps are given. (It *does* attempt
  a trial build as a quality gate — R8 — but does not stand up the durable project.)
- Not a hosted/CI/remote service; scope is a single user's local desktop with rootless
  Podman, same target as `ai-agent-podman-sandbox`.
- Does not bundle or vendor every AI agent runtime; only the selected runtime is installed
  in the bootstrap image.
- Does not guarantee the generated project is buildable without review — the user is
  explicitly asked to review before building.
- Does not mount host secrets, host `~/.ssh`, host config directories, or host agent
  sockets by default.
- `--force` (destructive recreate of an existing scaffold) is **out of v1 scope**.

## Detailed Requirements

### R1. `ai-new` command

- R1.1 `ai-new <name>` creates a project scaffold and launches a minimal, disposable
  bootstrap container, dropping the user into it.
- R1.2 `ai-new` is the same command reserved by `ai-agent-podman-sandbox` R14; it
  supersedes the purely non-interactive generator description there. There is no separate
  command name. It creates the scaffold (project tree, image directory, starter profile,
  launchers, bootstrap Containerfile, bootstrap `/start-here.sh`, `bootstrap/` state dir)
  and selects the agent runtime to install.
- R1.3 `--agent <agent>` selects the agent runtime and is validated against the runtime
  registry (R13). It is the preferred v1 path and determines which runtime is installed in
  the bootstrap environment. An unknown value exits non-zero with a clear message listing
  the registered agents.
- R1.4 The bootstrap container launches under the sandbox framework's safety posture: no
  host secrets/SSH/config mounted by default, `--userns=keep-id`, a narrow writable
  project mount, and a contained in-workspace `$HOME` (R14).
- R1.5 The bootstrap container launches with **network enabled by default** (required for
  agent API calls, authentication, package metadata, and trial builds). This is
  independent of the durable project's `NETWORK_MODE`.
- R1.6 `ai-new` accepts `--resume` and `--skip-trial-build` flags (R12, R8). `--force` is
  deferred beyond v1.
- R1.7 `ai-new` provides `-h`/`--help` and exits non-zero with a clear message on failure
  (Podman unavailable, image build/pull failure, unknown agent runtime, ambiguous resume
  state).
- R1.8 The bootstrap container is disposable; only the host-persisted project tree (agent
  config, generated files, session state) survives (R7, R9).

### R2. Project layout & collision handling

- R2.1 Generated project scaffolds live under a single project directory at
  `$CODEX_JAILS_DIR/projects/<name>/`, defaulting to `~/codex-jails/projects/<name>/`.
- R2.2 The default generated layout is:
  - `$CODEX_JAILS_DIR/projects/<name>/workspace/`
  - `$CODEX_JAILS_DIR/projects/<name>/image/` (contains the durable `Containerfile`)
  - `$CODEX_JAILS_DIR/projects/<name>/profile.env`
  - `$CODEX_JAILS_DIR/projects/<name>/launchers/`
  - `$CODEX_JAILS_DIR/projects/<name>/bootstrap/` (state dir: `session.md`, `session.json`,
    `home/`)
  - `$CODEX_JAILS_DIR/projects/<name>/README.md`
- R2.3 The framework may maintain global command binaries under `$CODEX_JAILS_DIR/bin` and
  global runtime registry files under `$CODEX_JAILS_DIR/config/agents.d/` (R13), but
  project-specific artifacts stay grouped under the project root.
- R2.4 Collision handling is decided **from `bootstrap/session.json` status** (R11), not by
  guessing from file presence:
  - no project directory exists → create a new scaffold;
  - project exists and `session.json` status is **not** `complete`/`generated-unvalidated`
    → refuse the ambiguous bare invocation and instruct the user to run
    `ai-new <name> --resume`;
  - project exists and status is terminal (`complete` or `generated-unvalidated`) → abort
    without overwriting.
- R2.5 `ai-new <name> --resume` continues an incomplete scaffold by re-entering the
  existing bootstrap workspace (R9) rather than restarting.
- R2.6 `--force` (recreate after confirmation) is deferred beyond v1 and is not shipped.

### R3. Bootstrap image (minimal & disposable)

- R3.1 The bootstrap image carries only enough to run `/start-here.sh`, install or connect
  to the **selected** agent runtime, validate credentials, provide a writable project
  mount, and write generated files.
- R3.2 The bootstrap image MUST NOT carry the eventual project's language/runtime stack, OS
  packages, build systems, or developer tools — those belong in the generated durable
  image.
- R3.3 The v1 bootstrap base image is `fedora:latest`. Base and bootstrap tooling are
  documented and kept small; any addition must be justified against R3.2.
- R3.4 Only the agent runtime selected via `--agent` is installed, using the registry's
  `AGENT_INSTALL_COMMAND` (R13) — not every supported runtime.

### R4. `/start-here.sh` (agent-priming launcher)

- R4.1 `/start-here.sh` lives at the filesystem root of the bootstrap container and is the
  single primary entrypoint the user runs after entering.
- R4.2 It MUST NOT contain a hardcoded questionnaire, MUST NOT generate the final project
  itself, and MUST NOT embed per-agent install/auth logic — it reads runtime metadata from
  the scaffolded registry entry and acts through the generic adapter contract (R13).
- R4.3 It determines the agent runtime: it uses the runtime selected at `ai-new` time; if
  exactly one runtime is available and none was specified, it may use it; if zero are
  available it fails with setup instructions; if multiple are available and none was
  specified it prompts the user to choose.
- R4.4 It validates that the selected runtime is present and can **authenticate before
  starting the interview** (R10), using the registry's `AGENT_AUTH_CHECK_COMMAND`. On
  missing/invalid credentials it reports the failure clearly, gives the required setup
  command or file path, and exits non-zero without starting the interview.
- R4.5 It launches the selected agent with CWD at `/project` (R15).
- R4.6 It hands the agent a structured **project-bootstrap prompt** instructing it to
  interview the user, design the container, generate the final project files, maintain
  session state (R11), and run the quality gate (R8).
- R4.7 It must not exit in a way that strands the user without guidance; final next-step
  instructions are delegated to the agent (R7) but the launcher guarantees the user is not
  left without direction.
- R4.8 `/start-here.sh -h`/`--help` prints usage; failure paths exit non-zero with a clear
  message.

### R5. Agent interview responsibilities

- R5.1 Once launched, the agent asks targeted questions to understand the desired project
  environment, progressively narrowing requirements without overwhelming the user, then
  produces a concrete result.
- R5.2 The agent determines at minimum: project purpose; preferred agent runtime; desired
  project role/profile; target language/runtime stack; required OS packages; required
  developer tools; required package managers; required build systems; expected
  source/project layout; workspace mount strategy; persistent state requirements; exposed
  ports; environment variables; secrets/credentials to be mounted rather than baked in;
  network assumptions; host-resource needs (GPU, audio, USB, display, etc.);
  rootless-friendliness; Podman/Docker/both support; whether update/build/launch helper
  scripts should be generated; whether README/onboarding docs should be generated.
- R5.3 The agent asks follow-ups where needed but avoids exhaustive interrogation.
- R5.4 The agent explicitly distinguishes secrets/credentials that should be **mounted at
  runtime** from values that may be baked into the image, steering secrets toward runtime
  mounting (consistent with the sandbox framework's secrets policy).
- R5.5 The user MUST NOT install project software manually during the `ai-new` phase.
  Additional requirements are expressed to the agent and captured in the generated
  `Containerfile`, include fragments, profile, or helper scripts.

### R6. Generated project output

- R6.1 After gathering enough information, the agent generates the project scaffold into
  the project tree. v1 produces a **complete minimal sandbox scaffold**, not only a
  `Containerfile`, and each generated project must be immediately buildable and launchable
  through the sandbox framework.
- R6.2 The **most important output is the real durable project `Containerfile`** at
  `image/Containerfile`, defining the durable development image.
- R6.3 The v1 output includes at least: the project workspace; the image directory; the
  real project `Containerfile`; a profile file (`profile.env`); a launch wrapper or launch
  path under `launchers/`; a build/update helper; a README with next steps;
  `.env.example`; `.gitignore`.
- R6.4 Generated profile/launcher/config artifacts follow `ai-agent-podman-sandbox`
  conventions (profile `.env` shape, `launchers/` wrappers) and derive paths from
  `$HOME`/`CODEX_JAILS_DIR` rather than hardcoding usernames.
- R6.5 Generated artifacts keep real secrets out of version control (provide
  `.env.example`, not populated secret files) and out of the image.

### R7. Persistence & user instructions

- R7.1 Generated files are written into the host-mounted project tree that survives
  disposal of the bootstrap container, so the user retains the output after exiting.
- R7.2 When generation completes, the agent tells the user the bootstrap container has
  finished its job and reports the quality-gate result (R8), including the resulting
  session status (R11).
- R7.3 The final instructions tell the user to: (1) review the generated files, (2) exit
  the bootstrap container, (3) build the real project image from the generated
  `Containerfile`, and (4) relaunch into the new project container.
- R7.4 Instructions reference the actual generated file paths/commands, not generic
  placeholders.

### R8. Quality gate on generated `Containerfile`

- R8.1 After generating the scaffold, the agent attempts at least: (1) a Containerfile
  syntax/static check where available; (2) a trial `podman build` of the generated durable
  image; (3) inspection of build failures and one or more repair attempts.
- R8.2 The trial build is **required by default** but may be skipped or time-boxed:
  - `AI_NEW_SKIP_TRIAL_BUILD=1` (or `ai-new <name> --skip-trial-build`) skips it;
  - `AI_NEW_BUILD_TIMEOUT=<duration>` time-boxes it.
- R8.3 Outcome maps to session status (R11):
  - build passes → eligible for `complete`;
  - build skipped → `generated-unvalidated` (never `complete`); the agent must clearly
    report that no build validation was performed and the user must build manually before
    trusting the scaffold;
  - build times out → `quality-gate-timeout`, and the session remains resumable;
  - build fails after repair attempts → the agent summarizes what failed, what was
    attempted, and the user's next decision.
- R8.4 The bootstrap phase is not complete until the generated files are reviewed and the
  quality-gate result (pass / skipped / timeout / fail) is reported.

### R9. Resumable sessions

- R9.1 The bootstrap container is disposable, but the bootstrap project tree — generated
  files, agent config directory, and session state (R11) — persists on the host.
- R9.2 `ai-new <name> --resume` against an incomplete scaffold re-enters the existing
  bootstrap workspace rather than restarting; the agent reads `session.md`/`session.json`
  to restore interview continuity.
- R9.3 Agent configuration directories (e.g. `.codex`, `.codex`, or runtime equivalent)
  are persisted under the bootstrap home (`/project/bootstrap/home`, R15) so
  authentication and settings survive bootstrap image rebuilds and resumed sessions.

### R10. Agent authentication

- R10.1 `start-here.sh` verifies the selected runtime can authenticate before starting the
  interview, via the registry `AGENT_AUTH_CHECK_COMMAND`.
- R10.2 Credential sources, in order: (1) persisted agent config inside the bootstrap home
  (`/project/bootstrap/home`); (2) profile/bootstrap env-file values when the runtime uses
  API keys (`AGENT_ENV_VARS`); (3) an interactive login/setup flow initiated by the agent
  CLI, if supported (`AGENT_PROMPT_MODE`).
- R10.3 No host secrets, host `~/.ssh`, host config directories, or host agent sockets are
  mounted by default.
- R10.4 If credentials are missing or invalid, `start-here.sh` reports the failure clearly
  and gives the required setup command or file path, exiting non-zero.

### R11. Session state files

- R11.1 Bootstrap session state is persisted in two files under `bootstrap/`:
  - `bootstrap/session.md` — human-readable notes for the user and agent;
  - `bootstrap/session.json` — machine-readable resume state for `ai-new`.
- R11.2 `session.md` records: the interview summary, decisions made, unresolved questions,
  generated files, quality-gate result, and the next recommended action.
- R11.3 `session.json` records at minimum: project name; selected agent; bootstrap status;
  timestamp of last update; generated file list; Containerfile path; quality-gate status;
  last error (if any); resume command.
- R11.4 The `status` field uses the controlled vocabulary: `started`, `interviewing`,
  `generated`, `quality-gate-running`, `quality-gate-failed`, `quality-gate-timeout`,
  `generated-unvalidated`, `complete`.
- R11.5 `ai-new` uses `session.json` to determine collision/resume behaviour (R2.4); the
  agent and user use `session.md` for continuity.
- R11.6 A scaffold is **complete** only when: the real `image/Containerfile` exists; the
  required v1 scaffold files (R6.3) exist; the quality gate has passed or been explicitly
  skipped; final next-step instructions have been written; and `session.json` status is
  `complete` or `generated-unvalidated`.

### R12. Flag surface (v1)

- R12.1 v1 ships explicit `--resume` and `--skip-trial-build`; `--force` is deferred.
- R12.2 `ai-new <name>` (no flag) on an incomplete scaffold refuses the ambiguous action
  and suggests `--resume` (R2.4); on a terminal scaffold it aborts.
- R12.3 `--resume` on a scaffold whose `session.json` is missing or unreadable fails with a
  clear message rather than silently restarting.

### R13. Supported-runtime registry

- R13.1 Supported agent runtimes are declared in registry files at
  `$CODEX_JAILS_DIR/config/agents.d/<agent>.env`. This is the authoritative source for
  valid `--agent` values.
- R13.2 Each registry file defines at minimum: `AGENT_NAME`, `AGENT_COMMAND`,
  `AGENT_INSTALL_COMMAND`, `AGENT_AUTH_CHECK_COMMAND`, `AGENT_CONFIG_DIRS`,
  `AGENT_ENV_VARS`, `AGENT_PROMPT_MODE`.
- R13.3 `ai-new --agent <agent>` validates the selected name against this registry (R1.3).
- R13.4 `start-here.sh` reads the selected runtime metadata from the scaffolded bootstrap
  config and contains no per-agent install/auth logic beyond the generic adapter contract
  (R4.2).
- R13.5 The framework may ship defaults for `codex`, `codex`, and `gemini`; users may add
  new runtimes by adding registry files rather than editing framework scripts.

### R14. Bootstrap safety posture

- R14.1 The bootstrap container runs rootless with `--userns=keep-id`.
- R14.2 The only writable host mount is the project tree (R15); no host secrets, `~/.ssh`,
  host config directories, or agent sockets are mounted by default.
- R14.3 `$HOME` inside the container is contained within the mounted project tree
  (`/project/bootstrap/home`), not the host home.

### R15. Single mounted project tree

- R15.1 The host path `$CODEX_JAILS_DIR/projects/<name>/` is mounted into the bootstrap
  container as `/project`; the bootstrap workspace and the generated durable scaffold are
  the **same** mounted tree.
- R15.2 The agent runs with CWD `/project`. Durable generated files are written directly
  under `/project` (`/project/workspace/`, `/project/image/Containerfile`,
  `/project/profile.env`, `/project/launchers/`, `/project/bootstrap/session.md`,
  `/project/bootstrap/session.json`).
- R15.3 The bootstrap container's `$HOME` is `/project/bootstrap/home`; agent config dirs
  (e.g. `.codex`, `.codex`) persist there unless the selected runtime requires a different
  documented path.

### R16. Non-functional

- R16.1 Scripts are POSIX/Bash where applicable, fail fast (`set -euo pipefail`), and run
  with no daemon beyond rootless Podman.
- R16.2 `ai-new` and `start-here.sh` provide help text and clear non-zero-exit error
  messages.
- R16.3 Targets Bazzite/Fedora with rootless Podman, consistent with
  `ai-agent-podman-sandbox`.

## Acceptance Criteria

- AC1. `ai-new <name> --agent <agent>` creates the scaffold at
  `$CODEX_JAILS_DIR/projects/<name>/` with the R2.2 layout and launches a minimal
  bootstrap container, dropping the user in; inspecting the bootstrap image confirms it
  contains no project language stack, build systems, or OS packages, and only the selected
  agent runtime.
- AC2. `ai-new <name> --agent <unknown>` exits non-zero, names the unknown agent, and lists
  registered agents from `config/agents.d/`.
- AC3. Collision handling matches `session.json` status: bare `ai-new <name>` creates when
  absent, refuses-and-suggests-`--resume` when incomplete, and aborts without overwriting
  when terminal.
- AC4. `ai-new <name> --resume` re-enters an incomplete scaffold; the agent reads
  `session.md`/`session.json` and continues rather than restarting. `--resume` with missing
  `session.json` fails clearly.
- AC5. Inside the bootstrap container, `/start-here.sh` exists at the filesystem root and,
  when run, resolves the agent runtime
  (selected/single/prompt-on-multiple/fail-on-zero), validates authentication before any
  interview, and launches the agent with CWD `/project` — without a hardcoded
  questionnaire, without generating the project itself, and without per-agent logic beyond
  the registry adapter contract.
- AC6. When agent credentials are missing or invalid, `start-here.sh` reports the failure
  and required setup command/path, exits non-zero, and does not start the interview.
- AC7. The launched agent conducts an interactive interview covering at least the R5.2
  minimum set, asking follow-ups as needed, and steers secrets toward runtime mounting.
- AC8. At the end of a session the agent has written a complete minimal scaffold into the
  project tree: real `image/Containerfile`, image directory, `profile.env`, launch
  wrapper/path, build/update helper, README with next steps, `.env.example`, `.gitignore`,
  plus `bootstrap/session.md` and `bootstrap/session.json`.
- AC9. `session.json` carries all R11.3 fields and a `status` from the R11.4 vocabulary;
  `session.md` carries the R11.2 content.
- AC10. Generated secret handling uses a `.env.example`/runtime-mount pattern; no populated
  secret files are baked into the image or committed to Git.
- AC11. Generated profile/launcher/config artifacts follow `ai-agent-podman-sandbox`
  conventions and derive paths from `$HOME`/`CODEX_JAILS_DIR` (no hardcoded usernames).
- AC12. The agent runs the quality gate (static check where available, trial `podman
  build`, repair attempts) and reports the result; the resulting status is `complete` on
  pass, `generated-unvalidated` when skipped, `quality-gate-timeout` on timeout, and a
  failure summary with next decision on persistent failure.
- AC13. `AI_NEW_SKIP_TRIAL_BUILD=1` / `--skip-trial-build` skips the build and yields
  `generated-unvalidated` with an explicit "build not validated" warning;
  `AI_NEW_BUILD_TIMEOUT=<duration>` time-boxes the build and yields `quality-gate-timeout`
  on expiry, leaving the session resumable.
- AC14. Generated files persist after the user exits and the bootstrap container is
  removed; agent config under `/project/bootstrap/home` persists across bootstrap image
  rebuilds and resumed sessions.
- AC15. The host path `$CODEX_JAILS_DIR/projects/<name>/` is the single tree mounted at
  `/project`; the durable scaffold and bootstrap state share it, and `$HOME` is
  `/project/bootstrap/home`.
- AC16. On completion the agent states the bootstrap is done and gives the four next steps
  (review, exit, build from the generated `Containerfile`, relaunch), referencing actual
  generated paths/commands.
- AC17. The bootstrap container is launched rootless with `--userns=keep-id`, network
  enabled, and only the project tree mounted; the generated durable profile may
  independently set `NETWORK_MODE` (including `none`).
- AC18. Building the durable image from the generated `Containerfile` and relaunching into
  it yields the user's intended working environment (manual acceptance).
- AC19. `ai-new -h` and `/start-here.sh -h` print usage; failure paths (no Podman,
  build/pull failure, unknown agent runtime, ambiguous resume state) exit non-zero with a
  clear message.

## Open Questions

The parent's OQ1–OQ5 are resolved and promoted into R8/R11/R12/R13/R15 above. The
following implementation-level questions remain for planning:

- OQ1. **Registry file format & sourcing.** `config/agents.d/<agent>.env` is described as an
  env-file of shell variables. Is it `source`d directly by `ai-new`/`start-here.sh` (which
  implies trusting arbitrary shell in `AGENT_INSTALL_COMMAND`/`AGENT_AUTH_CHECK_COMMAND`),
  or parsed in a restricted way? What is the validation/escaping contract, and how are
  multi-value fields (`AGENT_CONFIG_DIRS`, `AGENT_ENV_VARS`) encoded?

- OQ2. **Scaffolded vs global registry copy.** R13.4 says `start-here.sh` reads the selected
  runtime metadata "from the scaffolded bootstrap config." Is the chosen registry entry
  copied into `bootstrap/` at `ai-new` time (pinning the runtime definition for the life of
  the session), or read live from `$CODEX_JAILS_DIR/config/agents.d/`? Pinning aids
  reproducible resume; live reading picks up fixes — which wins for v1?

- OQ3. **Trial build & rootless nested Podman.** R8 runs `podman build` *inside* the
  bootstrap container. Does the trial build run nested (Podman-in-Podman, which is heavy
  under rootless + `--userns=keep-id`), or against the host Podman via a mounted
  socket/`podman --remote` (which conflicts with R10.3/R14.2's "no host sockets")? The
  resolution must reconcile the quality gate with the no-host-socket safety posture.

- OQ4. **`AI_NEW_BUILD_TIMEOUT` units & enforcement.** What duration grammar does
  `<duration>` accept (bare seconds? `timeout(1)` suffixes like `30m`?), and is enforcement
  via `timeout(1)` wrapping the build or via Podman's own controls? What is the default
  when unset?

- OQ5. **Image tag / naming for the trial build.** What tag is the durable image built under
  during the quality gate, how is it derived from `<name>`, and is the trial-built image
  pruned afterward or left as a warm cache for the user's first real build?

- OQ6. **Concurrent / stale-lock sessions.** If a bootstrap container is still running (or
  was killed uncleanly) and the user re-runs `ai-new <name> --resume`, how is a second
  concurrent session prevented — a lock file in `bootstrap/`, a status of
  `interviewing`/`quality-gate-running` treated as locked, and how is a stale lock cleared?

- OQ7. **Multi-runtime availability at resume.** R4.3 prompts when multiple runtimes are
  available and none was specified, but a resumed session already recorded
  `selected agent` in `session.json`. Confirm resume always honours the recorded agent and
  never re-prompts, and define behaviour if that recorded runtime is no longer in the
  registry.
