---
title: 'ai-new: Interactive Agent-Primed Project Bootstrap Container'
type: requirement
status: draft
lineage: ai-new
created: "2026-06-22T00:00:00+10:00"
priority: normal
parent: lifecycle/ideas/ai-new.md
assignees:
    - role: product-owner
      who: agent
---

# ai-new: Interactive Agent-Primed Project Bootstrap Container

## Problem

Creating a new AI-agent project container today requires the user to hand-author a
`Containerfile`, a launch/build/update script set, an agent configuration, and a
project layout — before they know what the project actually needs. This presupposes
that the user already understands every runtime dependency, OS package, build
system, mount strategy, and host-resource requirement up front. That is exactly the
knowledge a newcomer to a stack lacks, so the barrier to starting a tailored,
reproducible project environment is high and error-prone.

The companion `ai-agent-podman-sandbox` framework (lineage
`ai-agent-podman-sandbox`, see R14 "Project generator" and R16 "Request-driven
environment builder") establishes the durable sandbox model — rootless Podman,
`--userns=keep-id`, narrow workspace-only mounts, a contained in-workspace `$HOME`,
and per-project profiles. What is missing is a **low-friction, agent-led front door**
that produces those durable artifacts from a plain conversation instead of from
hand-editing.

`ai-new` fills that gap. It launches a deliberately minimal, **disposable** bootstrap
container whose only job is to start an AI agent with a strong bootstrap prompt. The
agent — not a hardcoded shell questionnaire — interviews the user, reasons about the
required container design, and emits the real project `Containerfile` and supporting
files. The bootstrap container is then thrown away and the user builds and runs the
durable image it generated.

## Goals / Non-goals

### Goals

- Provide an `ai-new` command that creates and launches a **tiny temporary bootstrap
  container** for starting a new AI-agent project, with the lowest possible barrier
  to entry.
- Ship a single root entrypoint `/start-here.sh` that acts as an **agent-priming
  launcher**, not a questionnaire: it detects/asks the agent runtime, launches it in
  the workspace, and hands it a structured bootstrap prompt.
- Make the **AI agent responsible** for interviewing the user, narrowing
  requirements progressively, designing the container, and generating the real
  project files (most importantly the project `Containerfile`).
- Keep the bootstrap image **minimal and disposable** — only enough tooling to run
  `start-here.sh`, launch/connect the agent runtime, and write generated files into a
  workspace. Real project dependencies belong in the generated image, never baked
  into the bootstrap image.
- Generate a **durable, reproducible project scaffold** (Containerfile plus helper
  scripts/config) that aligns with the `ai-agent-podman-sandbox` sandbox conventions
  so the output drops cleanly into that framework.
- Give the user **clear, explicit next steps** at the end: review files, exit the
  bootstrap container, build the real image, relaunch into it.
- Support multiple agent runtimes (Codex, Codex, Gemini, and other supported
  runtimes) as the priming target.

### Non-goals

- The bootstrap container is **not** the final development environment and must not
  grow into a general-purpose dev image carrying the eventual project's full stack.
- `start-here.sh` is **not** a static decision tree; it must not attempt to encode
  every possible project option or generate the project by itself.
- Not responsible for *building or running* the generated project image — its job
  ends when the artifacts are written and the user is told what to do next.
- Not a hosted/CI/remote service; scope is a single user's local desktop with
  rootless Podman (the same target as `ai-agent-podman-sandbox`).
- Does not bundle or vendor the AI agent runtimes themselves; it launches or connects
  to a runtime the user supplies or selects.
- Does not guarantee the generated project is buildable without review — the user is
  explicitly asked to review generated files before building.

## Detailed Requirements

### R1. `ai-new` command

- R1.1 `ai-new` creates and launches a minimal temporary bootstrap container and
  drops the user into it.
- R1.2 The bootstrap container is launched under the same rootless-Podman safety
  posture as the sandbox framework: no host secrets/SSH/config mounted by default, a
  narrow writable workspace, and a contained in-workspace `$HOME`.
- R1.3 The command provides `-h`/`--help` and exits non-zero with a clear message on
  failure (e.g. Podman unavailable, image build/pull failure).
- R1.4 The bootstrap container is treated as disposable; its lifecycle does not need
  to persist beyond the generation session (workspace-persisted output is what
  survives — see R6).

### R2. Bootstrap image (minimal & disposable)

- R2.1 The bootstrap image carries only enough to: run `/start-here.sh`, launch or
  connect to the selected AI agent runtime, provide a writable workspace, and write
  the generated project files.
- R2.2 The bootstrap image MUST NOT carry the eventual project's language/runtime
  stack, OS packages, build systems, or developer tools — those belong in the
  generated image.
- R2.3 The base image and bootstrap tooling are documented and kept small;
  additions to the bootstrap image must be justified against R2.2.

### R3. `/start-here.sh` (agent-priming launcher)

- R3.1 `/start-here.sh` lives at the filesystem root of the bootstrap container and
  is the single primary entrypoint a user runs after entering.
- R3.2 It MUST NOT contain a hardcoded questionnaire and MUST NOT attempt to generate
  the final project itself.
- R3.3 It detects or asks which AI agent runtime to use (e.g. Codex, Codex, Gemini,
  or another supported runtime).
- R3.4 It launches the selected agent in the current project workspace.
- R3.5 It provides the agent with a structured **project-bootstrap prompt** that
  instructs the agent to interview the user, design the container, and generate the
  final project files.
- R3.6 It ensures the user ultimately receives clear next-step instructions
  (delegated to the agent per R7, but the launcher must not exit in a way that
  strands the user without guidance).
- R3.7 The launcher's value is reliable priming: correct mission and constraints
  handed to the agent, not encoding project options itself.

### R4. Agent interview responsibilities

- R4.1 Once launched, the agent asks targeted questions to understand the desired
  project environment, progressively narrowing requirements without overwhelming the
  user, then produces a concrete result.
- R4.2 The agent should determine at minimum: project purpose; preferred AI agent
  runtime; desired project role/profile; target language/runtime stack; required OS
  packages; required developer tools; required package managers; required build
  systems; expected source/project layout; workspace mount strategy; persistent state
  requirements; exposed ports; environment variables; secrets/credentials to be
  mounted rather than baked in; network assumptions; host-resource needs (GPU, audio,
  USB, display, etc.); rootless-friendliness; Podman/Docker/both support; whether
  update/build/launch helper scripts should be generated; whether README/onboarding
  docs should be generated.
- R4.3 The agent must ask follow-up questions where needed but avoid an exhaustive
  interrogation.
- R4.4 The agent must explicitly distinguish secrets/credentials that should be
  **mounted at runtime** from values that may be baked into the image, and steer
  secrets toward runtime mounting (consistent with the sandbox framework's secrets
  policy).

### R5. Generated project output

- R5.1 After gathering enough information, the agent generates the real project
  scaffold into the workspace.
- R5.2 The **most important output is the real project `Containerfile`**, which
  defines the durable development image for the user's actual project.
- R5.3 Generated output may also include, as appropriate: `README.md`, a launch
  script, an update/build script, agent configuration, role/profile file(s),
  `.env.example`, `.gitignore`, a workspace directory structure, and optional helper
  scripts.
- R5.4 Generated profile/launcher/config artifacts should follow the
  `ai-agent-podman-sandbox` conventions (profile `.env` shape, `launchers/` wrappers,
  derive paths from `$HOME`/`CODEX_JAILS_DIR` rather than hardcoding usernames) so the
  output integrates with that framework.
- R5.5 Generated artifacts must keep real secrets out of version control (provide
  `.env.example`, not populated secret files) and out of the image.

### R6. Persistence of generated files

- R6.1 Generated files are written into a workspace that survives the disposal of the
  bootstrap container (e.g. a mounted host workspace directory), so the user retains
  the output after exiting.
- R6.2 The location of generated files is communicated to the user as part of the
  next-step instructions.

### R7. User instructions after generation

- R7.1 When generation completes, the agent clearly tells the user the bootstrap
  container has finished its job.
- R7.2 The final instructions tell the user to: (1) review the generated files,
  (2) exit the bootstrap container, (3) build the real project image from the
  generated `Containerfile`, and (4) relaunch into the new project container.
- R7.3 Instructions must reference the actual generated file paths/commands, not
  generic placeholders.

### R8. Design principle (disposable vs durable)

- R8.1 The bootstrap container is disposable; the generated project container is
  durable. All meaningful project dependencies, tools, runtimes, and configuration
  are declared in the generated `Containerfile` and installed during the real image
  build — never in the bootstrap image.

### R9. Non-functional

- R9.1 Scripts are POSIX/Bash where applicable, fail fast (`set -euo pipefail`), and
  run with no daemon beyond rootless Podman.
- R9.2 `ai-new` and `start-here.sh` provide help text and clear, non-zero-exit error
  messages.
- R9.3 Targets Bazzite/Fedora with rootless Podman, consistent with the
  `ai-agent-podman-sandbox` framework.

## Acceptance Criteria

- AC1. Running `ai-new` creates and launches a minimal bootstrap container and drops
  the user into it; the bootstrap image does not contain the eventual project's
  language stack, build systems, or OS packages (verifiable by inspecting the image).
- AC2. Inside the bootstrap container, `/start-here.sh` exists at the filesystem root
  and, when run, detects or asks for the agent runtime and launches the selected
  agent in the workspace — without presenting a hardcoded questionnaire and without
  generating the project itself.
- AC3. The launched agent conducts an interactive interview that covers at least the
  R4.2 minimum set (purpose, runtime, stack, OS packages, tools, build system,
  layout, mounts, persistence, ports, env vars, secrets, network, host resources,
  rootless/Podman-Docker support, helper scripts, docs), asking follow-ups as needed.
- AC4. At the end of a session, the agent has written a real project `Containerfile`
  into the workspace, plus any agreed helper files (README, launch/build scripts,
  agent config, role/profile, `.env.example`, `.gitignore`, layout).
- AC5. Generated secret handling: secrets appear as a `.env.example`/runtime-mount
  pattern, not as populated secret files baked into the image or committed to Git.
- AC6. Generated profile/launcher/config artifacts follow `ai-agent-podman-sandbox`
  conventions and derive paths from `$HOME`/`CODEX_JAILS_DIR` (no hardcoded
  usernames).
- AC7. The generated files persist after the user exits and the bootstrap container
  is removed (the workspace output survives disposal).
- AC8. On completion the agent tells the user the bootstrap is done and gives the
  four next steps (review, exit, build from the generated `Containerfile`, relaunch),
  referencing the actual generated paths/commands.
- AC9. Building the durable image from the generated `Containerfile` and relaunching
  into it yields the user's intended working environment (manual acceptance).
- AC10. `ai-new -h` and `/start-here.sh -h` print usage; failure paths (no Podman,
  build/pull failure, unknown agent runtime) exit non-zero with a clear message.

## Resolved Questions

- OQ1. **Relationship to `ai-agent-podman-sandbox` R14 (`ai-new` generator).** That
  lineage already reserves an `ai-new <name>` command that *scaffolds* a profile,
  workspace, image dir, and launchers non-interactively. Is this agent-led bootstrap
  the same command (superseding R14), a `--interactive` mode of it, or a distinct
  command name? They must not collide.

Resolved: this is the same `ai-new <name>` command, not a separate command.

`ai-new <name> --agent <agent>` creates the project scaffold: workspace,
image directory, starter profile, launchers, bootstrap Containerfile, and the
bootstrap `/start-here.sh` entrypoint.

After the scaffold exists, the bootstrap container runs `/start-here.sh`, which
primes the selected agent to interview the user and complete the real project
`Containerfile` and supporting project files.
  
- OQ2. **Agent runtime availability inside the bootstrap container.** Are agent
  runtimes (Codex, Codex, Gemini, etc.) baked into the bootstrap image, mounted in,
  or connected to from the host? Baking them in tensions with the "minimal/disposable"
  principle (R2); mounting/connecting needs a defined mechanism and auth strategy.

Resolved: the selected agent runtime is installed into the bootstrap image or
bootstrap scaffold based on the `ai-new --agent <agent>` selection.

The bootstrap image remains minimal by installing only the selected agent runtime,
not every supported runtime and not the eventual project stack.

Agent configuration directories, such as `.codex` or equivalent runtime config,
are persisted in the bootstrap workspace/home so authentication and settings
survive bootstrap image rebuilds and resumed sessions.
  
- OQ3. **Agent authentication/credentials.** The agent needs API keys or a login to
  operate inside the bootstrap container, yet the safety posture mounts no host
  secrets by default. What is the sanctioned way to supply agent credentials to the
  bootstrap container (one-off env-file mount, prompt, host agent socket)?

Resolved: `start-here.sh` must verify the selected agent runtime can authenticate
before starting the project interview.

Credential sources are, in order:

1. persisted agent config inside the bootstrap workspace/home, such as `.codex`;
2. profile/bootstrap env file values, when the selected agent uses API keys;
3. an interactive login/setup flow initiated by the agent CLI, if supported.

No host secrets, host `~/.ssh`, host config directories, or host agent sockets are
mounted by default. If credentials are missing or invalid, `start-here.sh` reports
the failure clearly and gives the user the required setup command or file path.
  
- OQ4. **Default vs prompted agent runtime.** Should `start-here.sh` auto-detect a
  single available runtime and proceed, always prompt, or honour an `AI_AGENT`-style
  env/flag? Behaviour when zero or multiple runtimes are available?

Resolved: the agent runtime is selected at `ai-new` time.

`ai-new <name> --agent <agent>` is the preferred v1 path. The selected runtime is
installed or made available in the bootstrap environment.

`start-here.sh` then validates that runtime is present and authenticated. If exactly
one runtime is available and no agent was specified, it may use it. If zero runtimes
are available, it fails with setup instructions. If multiple runtimes are available
and no agent was specified, it prompts the user to choose.
  
- OQ5. **Bootstrap base image & "minimal" budget.** What concrete base
  (e.g. `fedora:latest` vs a smaller base) and what tooling set count as the
  acceptable minimal bootstrap image?

Resolved: `fedora:latest` is acceptable as the v1 bootstrap base image.

The bootstrap image may include only the tooling required to run `/start-here.sh`,
install or launch the selected agent runtime, validate credentials, and write files
into the workspace. Project language stacks, build systems, OS packages, and
developer tools belong in the generated durable project image, not the bootstrap
image.
  
- OQ6. **Workspace location & collision handling.** Where is the generated-files
  workspace mounted from on the host (e.g. under `~/codex-jails/...`), and what
  happens if the target project directory already exists or is non-empty?

Resolved: generated project scaffolds live under a single project directory inside
`$CODEX_JAILS_DIR/projects`, defaulting to `~/codex-jails/projects`.

For `ai-new <name>`, the generated project root is:

`$CODEX_JAILS_DIR/projects/<name>/`

The default generated layout is:

- `$CODEX_JAILS_DIR/projects/<name>/workspace/`
- `$CODEX_JAILS_DIR/projects/<name>/image/`
- `$CODEX_JAILS_DIR/projects/<name>/profile.env`
- `$CODEX_JAILS_DIR/projects/<name>/launchers/`
- `$CODEX_JAILS_DIR/projects/<name>/bootstrap/`
- `$CODEX_JAILS_DIR/projects/<name>/README.md`

The framework may still maintain global command binaries under
`$CODEX_JAILS_DIR/bin`, but project-specific artifacts stay grouped under the
project root.

If `$CODEX_JAILS_DIR/projects/<name>` already exists, `ai-new` aborts by default
rather than merging into or overwriting the existing project. A future explicit
`--resume` mode may continue an incomplete bootstrap session, and a future
`--force` mode may recreate a scaffold after confirmation.
  
- OQ7. **Scope of generated artifacts in v1.** Is the MVP just `Containerfile` +
  README + a launch script, with profile/launcher generation and full sandbox
  integration deferred? Confirm the initial cut.

Resolved: v1 generates a complete minimal sandbox scaffold, not only a
`Containerfile`.

The v1 output includes at least:

- project workspace;
- image directory;
- real project `Containerfile`;
- profile file;
- launch wrapper or launch path;
- build/update helper;
- README with next steps;
- `.env.example`;
- `.gitignore`.

Full advanced integration can be improved later, but each generated project must be
immediately buildable and launchable through the sandbox framework.
  
- OQ8. **Quality gate on generated `Containerfile`.** Should `ai-new` (or the agent)
  attempt a trial build/lint of the generated `Containerfile` before handing off, or
  is review-then-build strictly the user's responsibility?

Resolved: a quality gate is required before handoff.

After generating the project scaffold, the agent must attempt at least:

1. a Containerfile syntax/static check where available;
2. a trial `podman build` of the generated durable image;
3. inspection of build failures and one or more repair attempts.

If the build still fails, the agent must summarize what failed, what was attempted,
and what the user should decide next. The bootstrap phase is not considered complete
until the generated files are reviewed and the quality-gate result is reported.
  
- OQ9. **Non-interactive / re-run mode.** Is there a need to re-prime the agent or
  resume a partial session within the same bootstrap container, or is each run a
  fresh disposable session?

Resolved: bootstrap sessions are resumable.

The bootstrap container itself may remain disposable, but the bootstrap workspace,
agent config directory, generated files, and session notes persist. Re-running
`ai-new <name>` against an incomplete scaffold resumes the existing bootstrap
workspace rather than starting from scratch, unless the user explicitly requests a
reset.

The user must not install project software manually during the `ai-new` phase.
Additional requirements should be expressed to the agent and captured in the
generated `Containerfile`, include fragments, profile, or helper scripts.
  
- OQ10. **Network requirement.** The agent almost certainly needs network access
  (API calls, package metadata) during the interview/generation. Is the bootstrap
  container always launched with network enabled, and how does that reconcile with
  the sandbox framework's optional `NETWORK_MODE=none`?

Resolved: the bootstrap container uses network access by default.

The bootstrap phase requires network access for agent API calls, authentication,
package metadata lookup, and optional trial builds. Therefore `ai-new` launches the
bootstrap container with network enabled by default.

The generated durable project profile may still set its own `NETWORK_MODE`, including
`NETWORK_MODE=none`, after the bootstrap phase is complete. Bootstrap networking and
final project sandbox networking are separate decisions.
