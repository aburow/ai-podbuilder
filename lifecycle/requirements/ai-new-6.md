---
title: 'ai-new: Agent-Primed Bootstrap Container — Build-Ready Requirement'
type: requirement
status: done
lineage: ai-new
created: "2026-06-22T00:00:00+10:00"
priority: normal
parent: lifecycle/requirements/ai-new-5.md
assignees:
    - role: analyst
      who: agent
    - role: product-owner
      who: agent
---

# ai-new: Agent-Primed Bootstrap Container — Build-Ready Requirement

This artifact consolidates `ai-new-5.md` into a single build-ready requirement. The seven
implementation questions resolved in the parent (OQ1–OQ7) and the five remaining planning
questions from the follow-up review are now treated as **settled and binding**, not as
rationale awaiting confirmation. The requirements below state each as a firm,
independently testable rule.

Nothing here weakens a parent requirement. Where the parent left a mechanism implied — for
example, how the host learns the agent has finished generating so it can run the trial
build — this revision states the mechanism explicitly: deterministic file-based
coordination through `bootstrap/`, host-owned locking/heartbeat, stable registry hashing,
explicit slug normalization, and a conservative v1 runtime adapter policy.

## Problem

Standing up a new AI-agent project container today forces the user to hand-author a
`Containerfile`, launch/build/update scripts, an agent configuration, and a project layout
*before* they understand what the project needs. That presupposes up-front knowledge of
every runtime dependency, OS package, build system, mount strategy, and host-resource
requirement — exactly the knowledge a newcomer to a stack lacks. The barrier to a tailored,
reproducible project environment is therefore high and error-prone.

The companion `ai-agent-podman-sandbox` framework establishes the durable sandbox model
(rootless Podman, `--userns=keep-id`, narrow workspace-only mounts, an in-workspace `$HOME`,
per-project profiles, and — per its R14/R16 — an `ai-new <name>` generator and a
request-driven environment builder). What is missing is a low-friction, **agent-led front
door** that produces those durable artifacts from a plain conversation instead of from
hand-editing.

`ai-new` fills that gap. `ai-new <name> --agent <agent>` scaffolds a project under the jails
directory and launches a deliberately minimal, **disposable** bootstrap container. Inside it,
`/start-here.sh` validates that the selected agent runtime can authenticate, then primes that
agent with a structured bootstrap prompt. The agent — not a hardcoded shell questionnaire —
interviews the user, designs the container, and generates the real durable project
`Containerfile` plus a complete sandbox scaffold. The host-side `ai-new` command then runs
the build quality gate and writes results back into the bootstrap state for agent repair. The
bootstrap container is then thrown away; the user reviews, builds, and runs the durable image
it generated.

The residual risk this revision closes is twofold. First, a careless implementation could
ship a registry that `eval`s untrusted shell, a trial build that requires a host Podman socket
inside the sandbox, or a resume path that silently restarts or re-prompts — all of which are
forbidden here as hard constraints. Second, the parent left the **host↔container coordination
protocol** implicit. This revision makes that protocol deterministic and file-based so resume,
locking, build requests, and repair loops can be inspected and reconstructed after crashes.

## Goals / Non-goals

### Goals

- Provide a single `ai-new <name> [--agent <agent>] [--resume] [--skip-trial-build]` command
  that scaffolds a project and launches a tiny, disposable bootstrap container with the
  lowest possible barrier to entry. This is the **same** command reserved by
  `ai-agent-podman-sandbox` R14, not a separate one.
- Ship `/start-here.sh` at the bootstrap container root as an **agent-priming launcher** —
  not a questionnaire and not a generator. It resolves/validates the agent runtime, confirms
  authentication, launches the agent in the project tree, and hands it a structured bootstrap
  prompt.
- Make the agent responsible for interviewing the user, progressively narrowing requirements,
  designing the container, generating the durable project files, and interpreting
  quality-gate results. The host-side `ai-new` command runs the actual trial `podman build`
  and writes logs back into the bootstrap state for agent repair.
- Keep the bootstrap image **minimal and disposable**: only the tooling needed to run
  `start-here.sh`, install/launch the *selected* agent runtime, validate credentials, and
  write workspace files. Project dependencies belong in the generated image only.
- Generate a **complete, immediately buildable minimal sandbox scaffold** that follows
  `ai-agent-podman-sandbox` conventions so the output drops cleanly into that framework.
- Persist generated files, agent config, and session state under one host-mounted project
  tree so they survive container disposal and support **resumable** bootstrap sessions.
- Define an **extensible, safely-parsed runtime registry** so new `--agent` values can be
  added by dropping a file in, never by editing framework scripts and never by trusting
  arbitrary shell from registry content.
- Make sessions **reproducible across resume** by pinning the selected runtime definition
  into the project at scaffold time, and **single-writer** via an atomic lock with a
  host-owned heartbeat.
- Run the trial build **on the host**, reconciling the quality gate with the no-host-socket
  safety posture, and define a **deterministic coordination protocol** by which the agent
  signals readiness and consumes results.
- Give the user clear, explicit next steps (review → exit → build → relaunch) that reference
  real generated paths and commands.

### Non-goals

- The bootstrap container is **not** the final development environment and must not grow into
  a general-purpose dev image carrying the project's full stack.
- `start-here.sh` is **not** a static decision tree and must not generate the project by
  itself, nor contain per-agent install/auth logic beyond the generic adapter contract.
- Not responsible for *running* the generated project image; its job ends after artifacts are
  written, the quality gate is reported, and next steps are given. The host-side `ai-new`
  command attempts a trial build as a quality gate (R8), but the bootstrap container does not
  run Podman or stand up the durable project.
- Not a hosted/CI/remote service; scope is a single user's local desktop with rootless
  Podman, same target as `ai-agent-podman-sandbox`.
- Does not bundle or vendor every AI agent runtime; only the selected runtime is installed in
  the bootstrap image.
- Does not guarantee the generated project is buildable without review — the user is
  explicitly asked to review before building.
- Does not mount host secrets, host `~/.ssh`, host config directories, or host agent sockets
  by default — and explicitly does not mount the host Podman socket for the trial build (R17).
- Does not run nested/privileged Podman inside the bootstrap container.
- `--force` (destructive recreate of an existing scaffold) and `--refresh-agent-registry`
  (re-pin the runtime definition) are **out of v1 scope** but are named here as reserved
  future flags.

## Detailed Requirements

### R1. `ai-new` command

- R1.1 `ai-new <name>` creates a project scaffold and launches a minimal, disposable
  bootstrap container, dropping the user into it.
- R1.2 `ai-new` is the same command reserved by `ai-agent-podman-sandbox` R14; it supersedes
  the purely non-interactive generator description there. There is no separate command name.
  It creates the scaffold (project tree, image directory, starter profile, launchers,
  bootstrap Containerfile, bootstrap `/start-here.sh`, `bootstrap/` state dir, pinned
  `bootstrap/agent.env`) and selects the agent runtime to install.
- R1.3 `--agent <agent>` selects the agent runtime and is validated against the runtime
  registry (R13). It is the preferred v1 path and determines which runtime is installed in the
  bootstrap environment. An unknown value exits non-zero with a clear message listing the
  registered agents.
- R1.4 The bootstrap container launches under the sandbox framework's safety posture: no host
  secrets/SSH/config mounted by default, `--userns=keep-id`, a narrow writable project mount,
  and a contained in-workspace `$HOME` (R14).
- R1.5 The bootstrap container launches with **network enabled by default** (required for
  agent API calls, authentication, package metadata). This is independent of the durable
  project's `NETWORK_MODE`.
- R1.6 `ai-new` accepts `--resume` and `--skip-trial-build` flags (R12, R8). `--force` and
  `--refresh-agent-registry` are deferred beyond v1.
- R1.7 `ai-new` provides `-h`/`--help` and exits non-zero with a clear message on failure
  (Podman unavailable, image build/pull failure, unknown agent runtime, ambiguous resume
  state, active or stale lock).
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
    `agent.env`, `agent.env.local` when present, `build.log` when present,
    `static-check.log` when present, `session.lock/` when held, `home/`)
  - `$CODEX_JAILS_DIR/projects/<name>/README.md`
- R2.3 The framework may maintain global command binaries under `$CODEX_JAILS_DIR/bin` and
  global runtime registry files under `$CODEX_JAILS_DIR/config/agents.d/` (R13), but
  project-specific artifacts stay grouped under the project root.
- R2.4 Collision handling is decided **from `bootstrap/session.json` status** (R11), not by
  guessing from file presence:
  - no project directory exists → create a new scaffold;
  - project exists and `session.json` status is **not** `complete`/`generated-unvalidated` →
    refuse the ambiguous bare invocation and instruct the user to run
    `ai-new <name> --resume`;
  - project exists and status is terminal (`complete` or `generated-unvalidated`) → abort
    without overwriting.
- R2.5 `ai-new <name> --resume` continues an incomplete scaffold by re-entering the existing
  bootstrap workspace (R9), subject to the concurrency lock (R19), rather than restarting.
- R2.6 `--force` (recreate after confirmation) is deferred beyond v1 and is not shipped.

### R3. Bootstrap image (minimal & disposable)

- R3.1 The bootstrap image carries only enough to run `/start-here.sh`, install or connect to
  the **selected** agent runtime, validate credentials, provide a writable project mount, and
  write generated files.
- R3.2 The bootstrap image MUST NOT carry the eventual project's language/runtime stack, OS
  packages, build systems, or developer tools — those belong in the generated durable image.
- R3.3 The v1 bootstrap base image is `fedora:latest`. Base and bootstrap tooling are
  documented and kept small; any addition must be justified against R3.2.
- R3.4 Only the agent runtime selected via `--agent` is installed, using the registry's
  install adapter (R13) — not every supported runtime.

### R4. `/start-here.sh` (agent-priming launcher)

- R4.1 `/start-here.sh` lives at the filesystem root of the bootstrap container and is the
  single primary entrypoint the user runs after entering.
- R4.2 It MUST NOT contain a hardcoded questionnaire, MUST NOT generate the final project
  itself, and MUST NOT embed per-agent install/auth logic — it reads runtime metadata from the
  pinned `bootstrap/agent.env` and acts through the generic adapter contract (R13).
- R4.3 It determines the agent runtime: it uses the runtime selected at `ai-new` time; if
  exactly one runtime is available and none was specified, it may use it; if zero are
  available it fails with setup instructions; if multiple are available and none was specified
  it prompts the user to choose. On `--resume` it never re-prompts (R20).
- R4.4 It validates that the selected runtime is present and can **authenticate before
  starting the interview** (R10), using the registry's auth-check adapter. On missing/invalid
  credentials it reports the failure clearly, gives the required setup command or file path,
  and exits non-zero without starting the interview.
- R4.5 It launches the selected agent with CWD at `/project` (R15).
- R4.6 It hands the agent a structured **project-bootstrap prompt** instructing it to
  interview the user, design the container, generate the final project files, maintain session
  state (R11), request the host-side quality gate via the coordination protocol (R8.7), and
  interpret any quality-gate logs/results for repair (R8).
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
  developer tools; required package managers; required build systems; expected source/project
  layout; workspace mount strategy; persistent state requirements; exposed ports; environment
  variables; secrets/credentials to be mounted rather than baked in; network assumptions;
  host-resource needs (GPU, audio, USB, display, etc.); rootless-friendliness;
  Podman/Docker/both support; whether update/build/launch helper scripts should be generated;
  whether README/onboarding docs should be generated.
- R5.3 The agent asks follow-ups where needed but avoids exhaustive interrogation.
- R5.4 The agent explicitly distinguishes secrets/credentials that should be **mounted at
  runtime** from values that may be baked into the image, steering secrets toward runtime
  mounting (consistent with the sandbox framework's secrets policy).
- R5.5 The user MUST NOT install project software manually during the `ai-new` phase.
  Additional requirements are expressed to the agent and captured in the generated
  `Containerfile`, include fragments, profile, or helper scripts.

### R6. Generated project output

- R6.1 After gathering enough information, the agent generates the project scaffold into the
  project tree. v1 produces a **complete minimal sandbox scaffold**, not only a
  `Containerfile`, and each generated project must be immediately buildable and launchable
  through the sandbox framework.
- R6.2 The **most important output is the real durable project `Containerfile`** at
  `image/Containerfile`, defining the durable development image.
- R6.3 The v1 output includes at least: the project workspace; the image directory; the real
  project `Containerfile`; a profile file (`profile.env`); a launch wrapper or launch path
  under `launchers/`; a build/update helper; a README with next steps; `.env.example`;
  `.gitignore`.
- R6.4 Generated profile/launcher/config artifacts follow `ai-agent-podman-sandbox` conventions
  (profile `.env` shape, `launchers/` wrappers) and derive paths from `$HOME`/`CODEX_JAILS_DIR`
  rather than hardcoding usernames.
- R6.5 Generated artifacts keep real secrets out of version control (provide `.env.example`,
  not populated secret files) and out of the image.

### R7. Persistence & user instructions

- R7.1 Generated files are written into the host-mounted project tree that survives disposal
  of the bootstrap container, so the user retains the output after exiting.
- R7.2 When generation completes, the agent tells the user the bootstrap container has finished
  its job and reports the quality-gate result (R8), including the resulting session status
  (R11).
- R7.3 The final instructions tell the user to: (1) review the generated files, (2) exit the
  bootstrap container, (3) build the real project image from the generated `Containerfile`, and
  (4) relaunch into the new project container.
- R7.4 Instructions reference the actual generated file paths/commands, not generic
  placeholders.

### R8. Host-side quality gate on generated `Containerfile`

- R8.1 After the agent generates the scaffold, the host-side `ai-new` command attempts at
  least: (1) a Containerfile syntax/static check where available; (2) a trial `podman build` of
  the generated durable image; and (3) build-log capture under `bootstrap/build.log`.
- R8.2 The trial build is **required by default** but may be skipped or time-boxed:
  - `AI_NEW_SKIP_TRIAL_BUILD=1` (or `ai-new <name> --skip-trial-build`) skips it;
  - `AI_NEW_BUILD_TIMEOUT=<duration>` time-boxes it (R18).
- R8.3 Outcome maps to session status (R11):
  - build passes → eligible for `complete`;
  - build skipped → `generated-unvalidated` (never `complete`); the agent must clearly report
    that no build validation was performed and the user must build manually before trusting
    the scaffold;
  - build times out → `quality-gate-timeout`, and the session remains resumable;
  - build fails after repair attempts → `quality-gate-failed`; the agent summarizes what
    failed, what was attempted, and the user's next decision.
- R8.4 If the trial build fails, `ai-new` writes the build log to `bootstrap/build.log`,
  updates `bootstrap/session.json`, and re-enters or instructs the user to resume the bootstrap
  agent so it can inspect the log and repair the generated files.
- R8.5 The bootstrap phase is not complete until the generated files are reviewed and the
  quality-gate result (pass / skipped / timeout / fail) is reported.
- R8.6 Static checking is advisory but reported. Preference order is: (1) Podman-native
  parse/check mode where available and reliable; (2) Buildah parse/check equivalent; (3)
  `hadolint` if installed; (4) no static check. If no tool is available, `ai-new` records
  `static_check=skipped` and proceeds to the trial build; it does not fail silently. A
  static-check failure records `static_check=failed` with details under
  `bootstrap/static-check.log` (or `build.log`) and does **not** by itself produce final
  `quality-gate-failed` status unless the trial build also fails or cannot start.
- R8.7 **Coordination protocol.** The host-side `ai-new` supervisor and the in-container agent
  coordinate the quality gate through files in `bootstrap/` only — never through a host socket
  or nested Podman. The agent requests a host-side quality gate by writing
  `bootstrap/build.request.json`; the host writes `bootstrap/build.result.json` and
  `bootstrap/build.log`.
- R8.8 Each build request uses a monotonically increasing integer `request_id`. The minimum
  `build.request.json` fields are: `request_id`, `requested_at`, `requested_by`,
  `containerfile`, `context_dir`, `image_tag`, `reason`, and `repair_iteration`. The minimum
  `build.result.json` fields are: `request_id`, `started_at`, `finished_at`, `exit_code`,
  `status`, `static_check_status`, `build_log_path`, `image_tag`, and `error_summary`.
- R8.9 The host supervisor detects a new build request, validates that no build is already
  running for the same project, changes `session.json` status to `quality-gate-running`, runs
  the host-side quality gate (R17), then writes the result files and updates `session.json`.
  Duplicate requests with a `request_id` that already has a matching result are ignored.
- R8.10 Repair attempts are capped at `3` by default and may be overridden with
  `AI_NEW_MAX_REPAIR_ATTEMPTS=<n>`. After the final failed repair/build cycle, status becomes
  `quality-gate-failed`; the user may later resume explicitly and request another repair/build
  cycle.
- R8.11 Crash/restart reconstruction is file-based: if `build.request.json` exists without a
  corresponding `build.result.json` and no active lock/build process exists, `ai-new --resume`
  treats the request as interrupted and reconciles state per R19.8. All reconciliation notes
  are appended to `bootstrap/session.md`.

### R9. Resumable sessions

- R9.1 The bootstrap container is disposable, but the bootstrap project tree — generated files,
  agent config directory, pinned `agent.env`, and session state (R11) — persists on the host.
- R9.2 `ai-new <name> --resume` against an incomplete scaffold re-enters the existing bootstrap
  workspace rather than restarting; the agent reads `session.md`/`session.json` to restore
  interview continuity, subject to the concurrency lock (R19).
- R9.3 Agent configuration directories (e.g. `.codex`, `.codex`, or runtime equivalent) are
  persisted under the bootstrap home (`/project/bootstrap/home`, R15) so authentication and
  settings survive bootstrap image rebuilds and resumed sessions.

### R10. Agent authentication

- R10.1 `start-here.sh` verifies the selected runtime can authenticate before starting the
  interview, via the registry auth-check adapter.
- R10.2 Credential sources, in order: (1) persisted agent config inside the bootstrap home
  (`/project/bootstrap/home`); (2) profile/bootstrap env-file values when the runtime uses API
  keys (`AGENT_ENV_VARS`, sourced from `bootstrap/agent.env.local`); (3) an interactive
  login/setup flow initiated by the agent CLI, if supported (`AGENT_PROMPT_MODE`).
- R10.3 No host secrets, host `~/.ssh`, host config directories, or host agent sockets are
  mounted by default.
- R10.4 If credentials are missing or invalid, `start-here.sh` reports the failure clearly and
  gives the required setup command or file path, exiting non-zero.
- R10.5 Bootstrap-time API-key credentials live in `bootstrap/agent.env.local`, which is
  gitignored, host-persisted, and loaded only for the bootstrap agent runtime. It is distinct
  from `bootstrap/agent.env`, which contains pinned non-secret registry metadata, and from the
  generated durable project's `.env.example`, which contains only placeholder variables.

### R11. Session state files

- R11.1 Bootstrap session state is persisted in two files under `bootstrap/`:
  - `bootstrap/session.md` — human-readable notes for the user and agent;
  - `bootstrap/session.json` — machine-readable resume state for `ai-new`.
- R11.2 `session.md` records: the interview summary, decisions made, unresolved questions,
  generated files, quality-gate result, the next recommended action, and any status
  reconciliation notes (R19.8).
- R11.3 `session.json` records at minimum: project name; selected agent; bootstrap status;
  timestamp of last update; generated file list; Containerfile path; quality-gate status; last
  error, if any; resume command; build log path, if any; trial-image tag, if any (R20);
  static-check status, if any; and a reference to the pinned `agent.env` including its computed
  source hash.
- R11.4 The `status` field uses the controlled vocabulary: `started`, `interviewing`,
  `generated`, `quality-gate-running`, `quality-gate-failed`, `quality-gate-timeout`,
  `generated-unvalidated`, `interrupted`, `complete`.
- R11.5 `ai-new` uses `session.json` to determine collision/resume behaviour (R2.4); the agent
  and user use `session.md` for continuity.
- R11.6 A scaffold is **complete** only when: the real `image/Containerfile` exists; the
  required v1 scaffold files (R6.3) exist; the quality gate has passed or been explicitly
  skipped; final next-step instructions have been written; and `session.json` status is
  `complete` or `generated-unvalidated`.
- R11.7 `bootstrap/build.log` records output from the most recent host-side trial build. It is
  preserved across resumes (and across timeouts, as a partial log) and referenced from
  `session.json` when present.

### R12. Flag surface (v1)

- R12.1 v1 ships explicit `--resume` and `--skip-trial-build`; `--force` and
  `--refresh-agent-registry` are deferred.
- R12.2 `ai-new <name>` (no flag) on an incomplete scaffold refuses the ambiguous action and
  suggests `--resume` (R2.4); on a terminal scaffold it aborts.
- R12.3 `--resume` on a scaffold whose `session.json` is missing or unreadable fails with a
  clear message rather than silently restarting.

### R13. Supported-runtime registry

- R13.1 Supported agent runtimes are declared in registry files at
  `$CODEX_JAILS_DIR/config/agents.d/<agent>.env`. This is the authoritative source for valid
  `--agent` values.
- R13.2 Registry files use a **restricted dotenv-style format** and MUST NOT be `source`d,
  `eval`'d, or executed via `sh -c`. `ai-new` and `start-here.sh` parse only known keys;
  unknown keys are ignored (and MAY be warned on). All values are loaded as strings and
  validated before use.
- R13.3 Each registry file defines at minimum: `AGENT_NAME`, `AGENT_COMMAND`,
  `AGENT_CONFIG_DIRS`, `AGENT_ENV_VARS`, `AGENT_PROMPT_MODE`, plus the install and auth-check
  adapter fields below. Multi-value fields are colon-separated quoted strings, e.g.
  `AGENT_CONFIG_DIRS=".codex"`, `AGENT_ENV_VARS="OPENAI_API_KEY"`.
- R13.4 Command behaviour is declared as **adapter name + arguments**, not as arbitrary shell
  fragments. v1 uses fields such as `AGENT_INSTALL_ADAPTER` (e.g. `npm-global`),
  `AGENT_INSTALL_PACKAGE` (e.g. `@openai/codex`), and a parsed argv-style
  auth-check (e.g. `AGENT_AUTH_CHECK_ARGV="codex|--version"`). The framework parses these into
  argv arrays and executes them through a controlled wrapper that performs no shell
  interpolation of registry content. Adapters are a fixed, framework-defined set; an unknown
  adapter name is a validation error.
- R13.5 `ai-new --agent <agent>` validates the selected name against this registry (R1.3).
- R13.6 **Pinning:** at `ai-new` time the selected registry entry is **copied** into the
  project at `bootstrap/agent.env`. This pinned copy is the authoritative runtime definition
  for the life of the session and for all resumes. `bootstrap/agent.env` additionally records:
  original registry path; selected agent name; optional `AGENT_REGISTRY_VERSION`; computed
  source hash; copy timestamp.
- R13.7 Normal resume uses the pinned `bootstrap/agent.env` and does **not** consult the global
  registry except for diagnostics. A future `--refresh-agent-registry` (deferred) may re-pin
  from the global registry, comparing the pinned hash against the current file's computed hash
  and confirming before replacing.
- R13.8 `start-here.sh` reads the selected runtime metadata only from `bootstrap/agent.env` and
  contains no per-agent install/auth logic beyond the generic adapter contract (R4.2).
- R13.9 The framework may ship defaults for `codex`, `codex`, and `gemini`; users may add new
  runtimes by adding registry files rather than editing framework scripts.
- R13.10 `ai-new` computes a SHA-256 hash over the **normalized** selected registry file when
  pinning it to `bootstrap/agent.env`. The optional `AGENT_REGISTRY_VERSION` is display
  metadata only; the computed hash is the authoritative drift detector. Registry normalization
  is: read as UTF-8 text; convert CRLF/CR line endings to LF; remove trailing whitespace from
  each line; preserve comments, key order, and interior blank lines; remove trailing blank
  lines at EOF; and ensure exactly one trailing newline. The resulting normalized text is
  hashed with SHA-256.
- R13.11 v1 install adapters are limited to `npm-global`, `pipx`, `dnf-package`, `preinstalled`,
  and `manual`. v1 auth checks use the `argv` adapter. Unknown adapter names fail validation.
- R13.12 **Adapter contracts (v1, fixed set):**
  - `npm-global` — requires `AGENT_INSTALL_PACKAGE`; runs `npm install -g <package>`; optional
    `AGENT_INSTALL_VERSION`.
  - `pipx` — requires `AGENT_INSTALL_PACKAGE`; runs `pipx install <package>`; optional
    `AGENT_INSTALL_VERSION`.
  - `dnf-package` — requires `AGENT_INSTALL_PACKAGE`; runs `dnf install -y <package>`; intended
    only for packages from configured Fedora repos.
  - `preinstalled` — no install action; runtime is already present in the bootstrap image or
    supplied by a framework-controlled mechanism.
  - `manual` — no install action; fails with user-facing setup instructions if the command is
    missing; used for runtimes v1 cannot install safely.
  - `argv` (auth check) — requires `AGENT_AUTH_CHECK_ARGV`, a pipe-delimited argv string (e.g.
    `"codex|--version"`); the framework splits into argv and executes directly without a shell.
  - No adapter executes registry content through `eval`, `source`, or `sh -c`; each receives
    validated string fields and constructs argv arrays internally.
- R13.13 Initial runtime mappings: `codex` → `npm-global`, package `@openai/codex`;
  `codex` → `npm-global`, package `@openai/codex`; `gemini` → `manual` for v1 unless a safe,
  official install path is deliberately selected before implementation. A manual runtime is a
  registered value, but if the command is missing `start-here.sh` reports setup instructions
  instead of attempting an automatic install.

### R14. Bootstrap safety posture

- R14.1 The bootstrap container runs rootless with `--userns=keep-id`.
- R14.2 The only writable host mount is the project tree (R15); no host secrets, `~/.ssh`, host
  config directories, agent sockets, or the host Podman socket are mounted by default.
- R14.3 `$HOME` inside the container is contained within the mounted project tree
  (`/project/bootstrap/home`), not the host home.

### R15. Single mounted project tree

- R15.1 The host path `$CODEX_JAILS_DIR/projects/<name>/` is mounted into the bootstrap
  container as `/project`; the bootstrap workspace and the generated durable scaffold are the
  **same** mounted tree.
- R15.2 The agent runs with CWD `/project`. Durable generated files are written directly under
  `/project` (`/project/workspace/`, `/project/image/Containerfile`, `/project/profile.env`,
  `/project/launchers/`, `/project/bootstrap/session.md`, `/project/bootstrap/session.json`).
- R15.3 The bootstrap container's `$HOME` is `/project/bootstrap/home`; agent config dirs (e.g.
  `.codex`, `.codex`) persist there unless the selected runtime requires a different documented
  path.

### R16. Non-functional

- R16.1 Scripts are POSIX/Bash where applicable, fail fast (`set -euo pipefail`), and run with
  no daemon beyond rootless Podman.
- R16.2 `ai-new` and `start-here.sh` provide help text and clear non-zero-exit error messages.
- R16.3 Targets Bazzite/Fedora with rootless Podman, consistent with `ai-agent-podman-sandbox`.

### R17. Trial-build execution model

- R17.1 The trial `podman build` runs in the **host-side `ai-new` process**, after the agent
  has signaled the scaffold is ready (R8.7). It MUST NOT run nested inside the bootstrap
  container.
- R17.2 The host Podman socket MUST NOT be mounted into the bootstrap container, and the
  bootstrap container MUST NOT receive nested-Podman privileges. The quality gate is reconciled
  with the no-host-socket posture (R14.2) by running entirely on the host.
- R17.3 The bootstrap container's responsibilities remain limited to interviewing, generating
  files, signaling readiness, reading quality-gate logs from `bootstrap/build.log`, and
  repairing the scaffold.
- R17.4 Build logs are written to `bootstrap/build.log` and the resulting status is written to
  `bootstrap/session.json` so the (possibly re-entered) agent can act on them.

### R18. Build timeout grammar & enforcement

- R18.1 `AI_NEW_BUILD_TIMEOUT` accepts GNU `timeout(1)` duration syntax (bare seconds or
  suffixed values, e.g. `300`, `10m`, `1h`).
- R18.2 When unset, the v1 default is `30m`.
- R18.3 Enforcement wraps the build command with `timeout --foreground "$AI_NEW_BUILD_TIMEOUT"`.
- R18.4 On expiry, `session.json` status becomes `quality-gate-timeout`, the partial build log
  is preserved at `bootstrap/build.log`, and the session remains resumable.

### R19. Concurrency & stale-lock handling

- R19.1 v1 prevents concurrent bootstrap sessions with an **atomic lock directory** at
  `bootstrap/session.lock/`, created before entering a session or running the host-side gate.
- R19.2 The lock records at minimum: `pid`, `hostname`, `container_name`, `started_at`,
  `last_heartbeat`.
- R19.3 `ai-new <name> --resume` (and any launch that would enter the bootstrap) refuses to
  start if the lock exists and appears **active**.
- R19.4 A lock is **stale** when the recorded bootstrap container no longer exists/runs **and**
  the recorded host-side supervisor process is no longer alive or `last_heartbeat` is older than
  the configured threshold. On stale-lock detection, `ai-new` reports the lock details and
  offers a safe clear path rather than silently overriding.
- R19.5 Status values such as `interviewing` and `quality-gate-running` are informative only;
  concurrency control is based on the lock directory, not on `session.json` status.
- R19.6 The **host-side `ai-new` supervisor owns the lock heartbeat** and remains alive for the
  duration of the session (while the bootstrap container runs, while the gate runs, and while
  it supervises a repair/resume loop). The bootstrap container and agent do not own the lock,
  are not trusted to clear it, and may read lock/session state for diagnostics only.
- R19.7 The default stale-lock threshold is `10m`, overridable with
  `AI_NEW_LOCK_STALE_AFTER=<duration>` using the same GNU `timeout(1)` duration syntax as
  `AI_NEW_BUILD_TIMEOUT`. The host supervisor refreshes `last_heartbeat` every `60s` by
  default. If the stale threshold is overridden, the refresh interval is
  `min(60s, stale_threshold / 5)` with a lower bound of `10s`.
- R19.8 On `--resume`, `ai-new` performs status reconciliation before entering the bootstrap
  container. If `session.json` holds a running status (`interviewing`, `quality-gate-running`)
  but no active lock exists (or the lock is stale and cleared), it rewrites the status to a
  recoverable state and records a note in `session.md` explaining the previous status, why it
  was stale, and the replacement. Reconciliation rules:
  - stale `interviewing` → `interrupted`;
  - stale `quality-gate-running` with no complete build log → `quality-gate-timeout` if the
    configured timeout was exceeded, otherwise `interrupted`;
  - stale `quality-gate-running` with a captured failure log → `quality-gate-failed`;
  - stale `quality-gate-running` with a captured success marker → `complete`.

### R20. Trial-image naming & runtime-at-resume

- R20.1 The trial build tags the durable image as `localhost/ai-new/<slug>:trial`, where
  `<slug>` is derived from `<name>` by a deterministic sanitizer: convert to lowercase ASCII
  where possible; replace any character outside `[a-z0-9._-]` with `-`; collapse repeated `-`;
  trim leading/trailing `.`, `_`, and `-`; fail clearly if the slug is empty; cap at 63
  characters; append `-<8-char-hash>` when truncation occurs; and fail if two distinct project
  names produce the same slug unless the user chooses a distinct name in a future flow.
- R20.2 On successful validation, the same image MAY also be tagged
  `localhost/ai-project/<name>:latest`.
- R20.3 The trial-built image is left in local Podman storage as a warm cache for the user's
  first real build; `ai-doctor` or future cleanup tooling MAY report and remove stale trial
  images later. The trial-image tag is recorded in `session.json` (R11.3).
- R20.4 Resume always honors the `selected_agent` recorded in `bootstrap/session.json` and the
  pinned `bootstrap/agent.env`; it NEVER re-prompts for agent selection.
- R20.5 If the recorded agent is no longer represented by the pinned `bootstrap/agent.env`,
  resume fails clearly.
- R20.6 If the pinned agent exists but its runtime is no longer installable/authenticated,
  `start-here.sh` reports the missing runtime/auth problem and gives setup instructions (rather
  than silently re-prompting or restarting).

## Acceptance Criteria

- AC1. `ai-new <name> --agent <agent>` creates the scaffold at
  `$CODEX_JAILS_DIR/projects/<name>/` with the R2.2 layout and launches a minimal bootstrap
  container, dropping the user in; inspecting the bootstrap image confirms it contains no
  project language stack, build systems, or OS packages, and only the selected agent runtime.
- AC2. `ai-new <name> --agent <unknown>` exits non-zero, names the unknown agent, and lists
  registered agents from `config/agents.d/`.
- AC3. Collision handling matches `session.json` status: bare `ai-new <name>` creates when
  absent, refuses-and-suggests-`--resume` when incomplete, and aborts without overwriting when
  terminal.
- AC4. `ai-new <name> --resume` re-enters an incomplete scaffold; the agent reads
  `session.md`/`session.json` and continues rather than restarting. `--resume` with missing
  `session.json` fails clearly.
- AC5. Inside the bootstrap container, `/start-here.sh` exists at the filesystem root and, when
  run, resolves the agent runtime (selected/single/prompt-on-multiple/fail-on-zero), validates
  authentication before any interview, and launches the agent with CWD `/project` — without a
  hardcoded questionnaire, without generating the project itself, and without per-agent logic
  beyond the registry adapter contract.
- AC6. When agent credentials are missing or invalid, `start-here.sh` reports the failure and
  required setup command/path, exits non-zero, and does not start the interview.
- AC7. The launched agent conducts an interactive interview covering at least the R5.2 minimum
  set, asking follow-ups as needed, and steers secrets toward runtime mounting.
- AC8. At the end of a session the agent has written a complete minimal scaffold into the
  project tree: real `image/Containerfile`, image directory, `profile.env`, launch
  wrapper/path, build/update helper, README with next steps, `.env.example`, `.gitignore`, plus
  `bootstrap/session.md` and `bootstrap/session.json`.
- AC9. `session.json` carries all R11.3 fields (including build log path and trial-image tag
  when present, and a reference to the pinned `agent.env`) and a `status` from the R11.4
  vocabulary; `session.md` carries the R11.2 content including any reconciliation notes.
- AC10. Generated secret handling uses a `.env.example`/runtime-mount pattern; no populated
  secret files are baked into the image or committed to Git, and `.gitignore` excludes
  `bootstrap/agent.env.local`, `bootstrap/home/`, any project `.env`, and runtime-specific
  secret/cache files.
- AC11. Generated profile/launcher/config artifacts follow `ai-agent-podman-sandbox` conventions
  and derive paths from `$HOME`/`CODEX_JAILS_DIR` (no hardcoded usernames).
- AC12. The host-side `ai-new` command runs the quality gate: static check where available,
  trial `podman build`, timeout handling, and build-log capture. The resulting status is
  `complete` on pass, `generated-unvalidated` when skipped, `quality-gate-timeout` on timeout,
  and `quality-gate-failed` on persistent failure. The agent reviews build logs and performs
  repair attempts when the session is resumed.
- AC13. `AI_NEW_SKIP_TRIAL_BUILD=1` / `--skip-trial-build` skips the build and yields
  `generated-unvalidated` with an explicit "build not validated" warning;
  `AI_NEW_BUILD_TIMEOUT=<duration>` time-boxes the build and yields `quality-gate-timeout` on
  expiry, leaving the session resumable.
- AC14. Generated files persist after the user exits and the bootstrap container is removed;
  agent config under `/project/bootstrap/home` persists across bootstrap image rebuilds and
  resumed sessions.
- AC15. The host path `$CODEX_JAILS_DIR/projects/<name>/` is the single tree mounted at
  `/project`; the durable scaffold and bootstrap state share it, and `$HOME` is
  `/project/bootstrap/home`.
- AC16. On completion the agent states the bootstrap is done and gives the four next steps
  (review, exit, build from the generated `Containerfile`, relaunch), referencing actual
  generated paths/commands.
- AC17. The bootstrap container is launched rootless with `--userns=keep-id`, network enabled,
  and only the project tree mounted (no host Podman socket); the generated durable profile may
  independently set `NETWORK_MODE` (including `none`).
- AC18. Building the durable image from the generated `Containerfile` and relaunching into it
  yields the user's intended working environment (manual acceptance).
- AC19. `ai-new -h` and `/start-here.sh -h` print usage; failure paths (no Podman, build/pull
  failure, unknown agent runtime, ambiguous resume state, active/stale lock) exit non-zero with
  a clear message.
- AC20. A registry file at `config/agents.d/<agent>.env` is parsed key-by-key, never
  `source`d/`eval`'d; an unknown adapter name fails validation; a file containing a hostile
  value (e.g. command substitution in a string field) does not result in that content being
  executed. Multi-value fields decode from the colon-separated form.
- AC21. `ai-new` copies the selected registry entry to `bootstrap/agent.env` with original
  path, agent name, version/hash if available, and timestamp; resume reads the pinned copy and
  continues to work unchanged even after the global registry file is edited or removed.
- AC22. The trial build runs in the host `ai-new` process; the host Podman socket is not present
  inside the bootstrap container and no nested-Podman privileges are granted; the bootstrap
  container can still read `bootstrap/build.log`.
- AC23. `AI_NEW_BUILD_TIMEOUT` accepts `timeout(1)` syntax, defaults to `30m` when unset, is
  enforced via `timeout --foreground`, and on expiry yields `quality-gate-timeout` with a
  preserved partial `build.log` and a resumable session.
- AC24. A second `ai-new <name> --resume` while a session is active is refused with lock
  details; an uncleanly killed session leaves a lock detectable as stale (dead container or
  expired heartbeat), and `ai-new` reports it and offers a safe clear path rather than starting
  concurrently. On the next resume, a running status with no live process is reconciled per
  R19.8 and the change is noted in `session.md`.
- AC25. The trial image is tagged `localhost/ai-new/<name>:trial` with a sanitized slug, is
  optionally also tagged `localhost/ai-project/<name>:latest` on success, is left in local
  storage as a warm cache, and its tag is recorded in `session.json`.
- AC26. Resume honors the recorded `selected_agent` and never re-prompts; resume fails clearly
  if the pinned agent is absent from `bootstrap/agent.env`; if the pinned agent exists but its
  runtime is uninstallable/unauthenticated, `start-here.sh` reports the runtime/auth problem
  with setup instructions.
- AC27. (R8.7–R8.11 / R13.10 / R20.1) The host↔container coordination is deterministic and
  file-based: a build request/result pair is reconstructable on resume; duplicate request ids
  do not trigger duplicate builds; the registry hash is stable for an unchanged normalized file
  across two independent runs and on two machines; and the image-slug sanitizer maps the same
  `<name>` to the same slug deterministically.

## Resolved Planning Questions

The parent (`ai-new-5.md`) closed OQ1–OQ7. The following planning questions were then
resolved and are reflected in the requirements above.

### OQ-A. Host↔container coordination protocol

**Question:** What is the concrete, file-based mechanism by which the in-container agent
signals "scaffold ready / please build" and consumes the result, given the host owns the build
and there is no host socket?

**Resolved:** host↔container coordination uses a file-based request/result protocol under
`bootstrap/`, plus status updates in `bootstrap/session.json`.

The agent requests a host-side quality gate by writing:

```text
bootstrap/build.request.json
```

The host-side `ai-new` supervisor detects this request, validates that no build is already
running for the same request id, changes `session.json` status to `quality-gate-running`, runs
the host-side quality gate, and writes:

```text
bootstrap/build.result.json
bootstrap/build.log
```

Each request has a monotonically increasing integer `request_id`.

Minimum `build.request.json` fields:

- `request_id`
- `requested_at`
- `requested_by`
- `containerfile`
- `context_dir`
- `image_tag`
- `reason`
- `repair_iteration`

Minimum `build.result.json` fields:

- `request_id`
- `started_at`
- `finished_at`
- `exit_code`
- `status`
- `static_check_status`
- `build_log_path`
- `image_tag`
- `error_summary`

The host MUST ignore duplicate requests with the same `request_id` if a matching result
already exists. If a build is already running, the host MUST refuse a second build request
until the first result is written or reconciled as stale.

Repair loop termination:

- default maximum repair attempts: `3`;
- override: `AI_NEW_MAX_REPAIR_ATTEMPTS=<n>`;
- after the final failed attempt, status becomes `quality-gate-failed`;
- the user may resume later and explicitly request another repair/build cycle.

Crash/restart reconstruction:

- if `build.request.json` exists without a corresponding `build.result.json`, and no active
  lock/build process exists, `ai-new --resume` treats the request as interrupted;
- if `session.json` says `quality-gate-running` but no active lock/build exists,
  reconciliation follows R19.8;
- all reconciliation notes are appended to `bootstrap/session.md`.

### OQ-B. Registry normalization and `<name>` slug sanitization

**Question:** What exactly is normalized before SHA-256 hashing, and what are the precise
rules turning `<name>` into a container-image-safe slug?

**Resolved:** registry hashing uses normalized file bytes, not semantic key sorting.

Registry normalization before SHA-256:

1. read the registry file as UTF-8 text;
2. convert CRLF/CR line endings to LF;
3. remove trailing whitespace from each line;
4. ensure exactly one trailing newline at EOF;
5. preserve comments;
6. preserve key order;
7. preserve blank lines except trailing blank lines at EOF.

The resulting normalized text is hashed with SHA-256.

This means comments and ordering are part of the pinned definition. That is intentional: the
pinned copy should reflect exactly what the user selected, while avoiding unstable hash changes
from line endings and editor trailing whitespace.

Project names are converted to image slugs with a deterministic sanitizer:

1. convert to lowercase ASCII where possible;
2. replace any character outside `[a-z0-9._-]` with `-`;
3. collapse repeated `-` into a single `-`;
4. trim leading/trailing `.`, `_`, and `-`;
5. if empty after sanitization, fail with a clear error;
6. cap at 63 characters;
7. if truncation occurs, append `-<8-char-hash>` using a hash of the original name;
8. if two project names produce the same slug, fail and ask the user to choose a distinct
   project name or explicit slug in a future flow.

The image tags are:

```text
localhost/ai-new/<slug>:trial
localhost/ai-project/<slug>:latest
```

### OQ-C. `gemini` install adapter

**Question:** Is the official Gemini CLI safely installable in v1 via `npm-global`, `pipx`, or
`dnf-package`, or must `gemini` ship as `manual` until a dedicated adapter is added?

**Resolved:** `gemini` ships as a registered but manual runtime in v1 unless a safe, official
install path is deliberately selected before implementation.

The v1 default registry entry for `gemini` uses:

```dotenv
AGENT_INSTALL_ADAPTER=manual
```

This means:

- `ai-new --agent gemini` is a known/registered value;
- the framework does not attempt to install Gemini automatically;
- if the `gemini` command is missing, `start-here.sh` reports setup instructions;
- Gemini can become a fully auto-installed runtime later by changing its registry entry to a
  supported adapter after the install path is validated.

`codex` and `codex` remain the initial auto-install candidates through `npm-global`, subject
to registry validation.

### OQ-D. Heartbeat refresh cadence

**Question:** The stale threshold is `10m`, but at what interval does the host supervisor
refresh `last_heartbeat`?

**Resolved:** the host supervisor refreshes `last_heartbeat` every 60 seconds by default.

Default values:

- `AI_NEW_LOCK_STALE_AFTER=10m`
- heartbeat refresh interval: `60s`

If `AI_NEW_LOCK_STALE_AFTER` is overridden, the refresh interval is:

```text
min(60s, stale_threshold / 5)
```

with a lower bound of `10s`.

This keeps the heartbeat comfortably fresher than the stale threshold without excessive
filesystem writes.

The host-side `ai-new` supervisor refreshes the heartbeat while:

- the bootstrap container is running;
- the host-side quality gate is running;
- the supervisor is waiting for build request/result transitions.

The bootstrap container and agent do not write the heartbeat.

### OQ-E. Bootstrap-container UX while the host runs the build

**Question:** During the host-side trial build, what does the user see inside the bootstrap
container — does the agent block waiting on `build.result`, stream `build.log`, or return
control with a "build running" message?

**Resolved:** during the host-side trial build, the agent enters a waiting state and reports
progress from the shared build state.

When the agent writes `bootstrap/build.request.json`, it tells the user that the host-side
`ai-new` supervisor is running the quality gate outside the bootstrap container.

The agent then waits for `bootstrap/build.result.json`.

While waiting, the agent should periodically show concise progress:

- current status from `session.json`;
- build log path: `bootstrap/build.log`;
- elapsed time;
- timeout setting.

If feasible, the agent may tail or summarize `bootstrap/build.log`, but it must not run
`podman build` itself and must not require host socket access.

When `build.result.json` appears:

- on success, the agent reports the successful quality gate and writes final next steps;
- on failure, the agent reads `bootstrap/build.log`, repairs generated files where
  appropriate, and may request another host-side build using the next `request_id`;
- on timeout, the agent reports the timeout and leaves the session resumable.
