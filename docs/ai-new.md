# ai-new — Agent-Primed Bootstrap Container

Stand up a new AI-agent project container through conversation, not configuration.

**Version:** v1  
**Target platform:** Bazzite / Fedora Atomic with rootless Podman  
**Requirements artifact:** `lifecycle/requirements/ai-new-9.md`

---

## Contents

1. [Overview](#1-overview)
2. [Prerequisites](#2-prerequisites)
3. [Quick Start](#3-quick-start)
4. [Command Reference](#4-command-reference)
5. [Project Layout](#5-project-layout)
6. [Bootstrap Container](#6-bootstrap-container)
7. [Runtime Registry](#7-runtime-registry)
8. [Agent Interview & Project Generation](#8-agent-interview--project-generation)
9. [Session State & Resumability](#9-session-state--resumability)
10. [Host-Side Quality Gate](#10-host-side-quality-gate)
11. [Host↔Container Coordination Protocol](#11-hostcontainer-coordination-protocol)
12. [Concurrency & Lock Management](#12-concurrency--lock-management)
13. [Security & Safety Posture](#13-security--safety-posture)
14. [Generated Scaffold](#14-generated-scaffold)
15. [Secrets & Credentials](#15-secrets--credentials)
16. [Configuration Variables](#16-configuration-variables)
17. [Deferred Features (Post-v1)](#17-deferred-features-post-v1)

---

## 1. Overview

### Problem

Standing up a new AI-agent project container today means hand-authoring a
`Containerfile`, launch scripts, an agent configuration, and a project layout
*before* understanding what the project actually needs. This presupposes
up-front knowledge of every runtime dependency, OS package, build system, mount
strategy, and host-resource requirement — exactly the knowledge a newcomer to a
stack does not have. The barrier to a tailored, reproducible project environment
is high and error-prone.

The companion `ai-agent-podman-sandbox` framework already provides the durable
sandbox model: rootless Podman, `--userns=keep-id`, workspace-only mounts, an
in-workspace `$HOME`, and per-project profiles. What is missing is a
**low-friction front door** that produces those durable artifacts from a plain
conversation rather than from hand-editing.

### Solution

`ai-new` fills that gap. A single command scaffolds a project under the jails
directory and launches a deliberately minimal, **disposable** bootstrap
container. Inside it, `/start-here.sh` validates that the selected agent runtime
can authenticate, then hands that agent a structured bootstrap prompt.

The agent — not a hardcoded shell questionnaire — interviews the user, designs
the container, and generates the real durable project `Containerfile` plus a
complete sandbox scaffold. The host-side `ai-new` command then runs a quality
gate (static check and trial `podman build`) and writes results back into
bootstrap state for agent repair. Once generation is complete, the bootstrap
container is discarded; the user reviews, builds, and runs the durable image it
produced.

### Design Goals

| Goal | v1 approach |
|------|-------------|
| Single command, low barrier | `ai-new <name> --agent <agent>` is the complete entry point |
| Agent-led design | The agent interviews and designs; `ai-new` scaffolds and validates |
| Disposable bootstrap | Bootstrap image carries only the runtime, not the project stack |
| Durable output | Generated files persist on the host; the bootstrap container is throwaway |
| Resumable sessions | File-based session state survives container disposal and crashes |
| Safe-by-default | No host secrets, no host Podman socket, rootless, workspace-only mount |
| Deterministic coordination | File-based protocol; inspectable and reconstructable on resume |
| Extensible runtime registry | Add a new agent by dropping a file; no script editing required |

### Non-Goals (v1)

- The bootstrap container is **not** the final development environment. It must
  not grow into a general-purpose dev image carrying the project's full stack.
- `ai-new` is not responsible for *running* the generated project image; its job
  ends after artifacts are written and the quality gate is reported.
- Not a hosted, CI, or remote service; scope is a single user's local desktop
  with rootless Podman.
- Does not bundle or vendor every AI agent runtime; only the selected runtime is
  installed.
- Does not mount host secrets, host `~/.ssh`, host config directories, host
  agent sockets, or the host Podman socket.
- Does not run nested or privileged Podman inside the bootstrap container.
- Does not guarantee the generated project is buildable without review — the
  user is explicitly asked to review before building.

---

## 2. Prerequisites

- **OS:** Bazzite or another Fedora Atomic desktop
- **Container runtime:** rootless Podman (verify: `podman info | grep -i rootless`)
- **Shell:** Bash 5+ (`set -euo pipefail` used throughout)
- **Network:** `slirp4netns` for container networking (default with Podman)
- **At least one registered agent runtime:** see [Section 7](#7-runtime-registry)

---

## 3. Quick Start

```bash
# Create a new project and bootstrap it with Codex
ai-new my-project --agent codex

# Inside the bootstrap container, start the agent-led setup
/start-here.sh

# The agent interviews you, generates the scaffold, and runs the quality gate.
# When done, follow the agent's next-step instructions:
#   1. Review the generated files under ~/codex-jails/projects/my-project/
#   2. Exit the bootstrap container (exit or Ctrl-D)
#   3. Build the real project image from the generated Containerfile:
#      podman build -t my-project ~/codex-jails/projects/my-project/image/
#   4. Launch into the new project container using the generated launcher

# If a session was interrupted, resume it:
ai-new my-project --resume
```

---

## 4. Command Reference

### `ai-new`

```
ai-new <name> [--agent <agent>] [--resume] [--skip-trial-build] [-h|--help]
```

**Positional arguments**

| Argument | Description |
|----------|-------------|
| `<name>` | Project name. Used to derive the project directory and the sanitized image tag slug (see [Section 10](#10-host-side-quality-gate)). |

**Options**

| Option | Description |
|--------|-------------|
| `--agent <agent>` | Select the agent runtime. Validated against the runtime registry (`config/agents.d/`). Recommended for v1; required when multiple runtimes are registered. |
| `--resume` | Re-enter an incomplete bootstrap session rather than creating a new one. Reads the pinned `bootstrap/agent.env` and `bootstrap/session.json` to restore context. |
| `--skip-trial-build` | Skip the host-side trial `podman build`. Session status becomes `generated-unvalidated`. Equivalent to setting `AI_NEW_SKIP_TRIAL_BUILD=1`. |
| `-h`, `--help` | Print usage and exit zero. |

**Collision behaviour** (controlled by `bootstrap/session.json`)

| Situation | Behaviour |
|-----------|-----------|
| No project directory | Create a new scaffold. |
| Project exists, status is incomplete | Refuse the bare invocation; print: "Use `ai-new <name> --resume` to continue." |
| Project exists, status is terminal (`complete` / `generated-unvalidated`) | Abort without overwriting. |

**Exit codes**

`ai-new` exits zero only on clean entry into the bootstrap container. Any setup
failure (Podman unavailable, image build failure, unknown agent, ambiguous
resume state, active or stale lock) exits non-zero with a clear message.

### `/start-here.sh`

`/start-here.sh` lives at the filesystem root of the bootstrap container and is
the single primary entrypoint the user runs after entering the container. It is
**not** a questionnaire and does not generate the project itself.

```
/start-here.sh [-h|--help]
```

**What it does:**

1. Reads runtime metadata from the pinned `bootstrap/agent.env` (never `source`d
   or `eval`'d — key-by-key restricted parse only).
2. Resolves and validates the selected runtime.
3. Validates agent authentication before starting the interview (see
   [Section 15](#15-secrets--credentials)).
4. Launches the selected agent with CWD `/project`, handing it the structured
   bootstrap prompt.

**Runtime resolution rules:**

| State | Behaviour |
|-------|-----------|
| Runtime selected at `ai-new` time | Use it |
| Exactly one runtime registered and available | May use it |
| Zero runtimes available | Fail with setup instructions |
| Multiple runtimes available, none specified | Fail with guidance to rerun with `--agent <agent>` |
| `--resume` | Never re-prompt; use the agent recorded in `session.json` and pinned `agent.env` |

---

## 5. Project Layout

All project artifacts live under a single base directory.

```
$CODEX_JAILS_DIR/                         # Default: ~/codex-jails/
├── bin/
│   └── ai-new                            # The ai-new command
├── lib/
│   ├── common.sh                         # Shared helpers
│   └── registry.sh                       # Registry parser and adapter logic
└── config/
    └── agents.d/                         # Runtime registry files
        ├── codex.env
        ├── codex.env
        └── gemini.env
```

Each project gets its own isolated tree:

```
$CODEX_JAILS_DIR/projects/<name>/
├── workspace/                            # Project workspace (mounted at /project/workspace)
├── image/
│   └── Containerfile                     # Durable project image definition (generated)
├── profile.env                           # ai-agent-podman-sandbox profile (generated)
├── launchers/                            # Launch wrappers (generated)
├── README.md                             # Next steps and project summary (generated)
└── bootstrap/                            # Bootstrap session state (host-persisted)
    ├── session.md                        # Human-readable session notes
    ├── session.json                      # Machine-readable resume state
    ├── agent.env                         # Pinned runtime registry entry (copy at scaffold time)
    ├── agent.env.local                   # Bootstrap API keys (gitignored, never baked in)
    ├── build.log                         # Most recent trial build output (when present)
    ├── static-check.log                  # Static-check output (when present)
    ├── build.request.<id>.json           # Numbered build-request files
    ├── build.result.<id>.json            # Matching build-result files
    ├── session.lock/                     # Atomic concurrency lock directory (when held)
    └── home/                             # Bootstrap container's $HOME (agent config, etc.)
```

The host path `$CODEX_JAILS_DIR/projects/<name>/` is mounted into the bootstrap
container as `/project`. The bootstrap workspace and the generated durable
scaffold are the **same** mounted tree. Files written inside the container at
`/project/...` appear immediately on the host.

**Path derivation:** Every path is derived from `$HOME` or `$CODEX_JAILS_DIR`.
No usernames are hardcoded in any generated or framework file.

**`CODEX_JAILS_DIR`:** Defaults to `~/codex-jails`. Override by exporting the
variable before running `ai-new`.

---

## 6. Bootstrap Container

### Image

The bootstrap image is based on `fedora:latest` and carries only:

- The tooling needed to run `/start-here.sh`
- The selected agent runtime (installed at container build time via the registry
  install adapter)
- No project language/runtime stack, build systems, OS packages, or developer
  tools — those belong exclusively in the generated durable image

The image is **disposable**. Only the host-persisted project tree survives
container disposal.

### Container launch parameters

`ai-new` launches the bootstrap container with:

- `--userns=keep-id` — rootless UID mapping
- `--network` enabled — required for agent API calls, authentication, and
  package metadata
- A single writable bind mount: `$CODEX_JAILS_DIR/projects/<name>/` → `/project`
- `HOME=/project/bootstrap/home` — the bootstrap agent's config directories
  (`~/.codex`, `~/.codex`, etc.) persist there across bootstrap image rebuilds
  and resumes
- No host secrets, `~/.ssh`, host config directories, agent sockets, or host
  Podman socket mounted

### Container's `$HOME`

The bootstrap container's `$HOME` is `/project/bootstrap/home` — a directory
inside the mounted project tree. This means:

- Agent config directories (e.g. `.codex`, `.codex`) persist on the host after
  the bootstrap container is removed.
- Credentials stored by the agent CLI during an initial auth flow survive across
  bootstrap image rebuilds and resumed sessions.
- The host home directory is never exposed inside the container.

---

## 7. Runtime Registry

The runtime registry declares which AI agent runtimes `ai-new` supports. It is
**extensible without editing framework scripts**: drop a new file in
`$CODEX_JAILS_DIR/config/agents.d/` and it becomes a valid `--agent` value.

### Registry file format

Each file `config/agents.d/<agent>.env` uses a **restricted dotenv-style
format**. Registry files are **never `source`d, `eval`'d, or executed via
`sh -c`**. The parser reads only known keys; unknown keys are ignored. All
values are treated as strings and validated before use. A hostile value
containing command substitution or shell metacharacters is treated as a
literal string and is never executed.

**Required keys:**

| Key | Description |
|-----|-------------|
| `AGENT_NAME` | Display name for the runtime |
| `AGENT_COMMAND` | Binary name (e.g. `codex`, `codex`) |
| `AGENT_CONFIG_DIRS` | Colon-separated list of config dir names relative to `$HOME` (e.g. `".codex"`) |
| `AGENT_ENV_VARS` | Colon-separated API key variable names (e.g. `"OPENAI_API_KEY"`) |
| `AGENT_PROMPT_MODE` | Whether the runtime supports an interactive login/auth flow (`yes` / `no`) |
| `AGENT_INSTALL_ADAPTER` | Install method from the v1 fixed set (see below) |
| `AGENT_AUTH_CHECK_ARGV` | Pipe-delimited argv for the auth-check command (e.g. `"codex|--version"`) |

**Optional keys:**

| Key | Description |
|-----|-------------|
| `AGENT_INSTALL_PACKAGE` | Package identifier for the install adapter |
| `AGENT_INSTALL_VERSION` | Pinned version for the install adapter |
| `AGENT_REGISTRY_VERSION` | Display metadata; the SHA-256 hash is the authoritative drift detector |

**Multi-value fields** use colon-separated quoted strings:

```
AGENT_CONFIG_DIRS=".codex"
AGENT_ENV_VARS="OPENAI_API_KEY"
```

### v1 install adapters

| Adapter | Install action | Required keys |
|---------|---------------|---------------|
| `npm-global` | `npm install -g <package>` | `AGENT_INSTALL_PACKAGE` |
| `pipx` | `pipx install <package>` | `AGENT_INSTALL_PACKAGE` |
| `dnf-package` | `dnf install -y <package>` | `AGENT_INSTALL_PACKAGE` |
| `preinstalled` | No install; runtime already in the bootstrap image | — |
| `manual` | No install; fails with setup instructions if command is missing | — |

Auth-check adapter:

| Adapter | How it runs |
|---------|-------------|
| `argv` | Requires `AGENT_AUTH_CHECK_ARGV` (`"codex|--version"`). The framework splits on `|` and executes the resulting argv array directly — no shell involved. |

An unknown adapter name is a validation error and will cause `ai-new` to exit
non-zero.

### Shipped defaults

| `--agent` value | Install adapter | Package |
|-----------------|-----------------|---------|
| `codex` | `npm-global` | `@openai/codex` |
| `codex` | `npm-global` | `@openai/codex` |
| `gemini` | `manual` | — (see [Gemini note](#gemini-note) below) |

#### Gemini note

`gemini` ships as a `manual` runtime in v1. If the `gemini` command is present
and authenticates, it may be used. If the command is missing, `/start-here.sh`
reports setup instructions and exits non-zero; no automatic installation is
attempted. This is binding for v1 (see [Section 17](#17-deferred-features-post-v1)).

### Registry pinning

At `ai-new` time, the selected registry entry is **copied** into the project at
`bootstrap/agent.env`. This pinned copy records:

- The original registry file path
- The selected agent name
- An optional `AGENT_REGISTRY_VERSION`
- A SHA-256 hash of the normalized registry file
- The copy timestamp

The pinned copy is the **authoritative runtime definition** for the life of the
session and all resumes. Normal resume reads only `bootstrap/agent.env` and does
not consult the global registry. The session continues to work correctly even
if the global registry file is later edited or removed.

**Hash normalization** (for stable, machine-independent hashes): read as UTF-8;
convert CRLF/CR to LF; remove trailing whitespace from each line; preserve
comments, key order, and interior blank lines; remove trailing blank lines at
EOF; ensure exactly one trailing newline. The resulting text is hashed with
SHA-256. The same normalized file produces the same hash on any machine.

### Adding a new runtime

1. Create `$CODEX_JAILS_DIR/config/agents.d/myruntime.env` with the required
   keys (see above).
2. Run `ai-new myproject --agent myruntime`.

No framework scripts need to be edited.

---

## 8. Agent Interview & Project Generation

### What the agent does

Once `/start-here.sh` launches the agent with CWD `/project` and the structured
bootstrap prompt, the agent takes over:

1. **Interviews the user** — asks targeted questions to narrow down requirements
   without overwhelming the user.
2. **Designs the container** — determines the language/runtime stack, OS
   packages, developer tools, build systems, workspace layout, persistent state,
   exposed ports, environment variables, secret-mounting strategy, network
   assumptions, and host-resource needs (GPU, audio, USB, display, etc.).
3. **Generates the scaffold** — writes all required files into `/project` (which
   is the host-mounted project tree).
4. **Requests the quality gate** — signals readiness to the host-side supervisor
   via the coordination protocol (see [Section 11](#11-hostcontainer-coordination-protocol)).
5. **Inspects results and repairs** — reads `bootstrap/build.log` when the build
   fails and repairs the generated `Containerfile` and scaffold files.
6. **Reports next steps** — tells the user what was generated, the quality-gate
   result, and exactly how to proceed.

### Interview scope

The agent determines at minimum:

- Project purpose and desired role/profile
- Preferred agent runtime (if not already selected)
- Target language and runtime stack
- Required OS packages, developer tools, package managers, and build systems
- Source and project layout; workspace mount strategy
- Persistent state requirements
- Exposed ports
- Environment variables (runtime-mounted vs. baked-in)
- Secrets and credentials (always steered toward runtime mounting, never baked in)
- Network assumptions
- Host-resource needs (GPU, audio, USB, display)
- Rootless-friendliness; Podman/Docker/both support
- Whether helper scripts (update, build, launch) should be generated
- Whether README/onboarding docs should be generated

The agent asks follow-ups where needed but avoids exhaustive interrogation.

### User's role during bootstrap

The user answers the agent's questions. **Do not install project software
manually** during the `ai-new` phase. Express all requirements to the agent;
it captures them in the generated `Containerfile`, include fragments, profile,
or helper scripts.

---

## 9. Session State & Resumability

### Session files

Two files under `bootstrap/` persist session state across container disposal,
crashes, and resumes:

**`bootstrap/session.md`** (human-readable)

Written by the agent throughout the session. Contains:

- Interview summary and decisions made
- Unresolved questions
- List of generated files
- Quality-gate result
- Next recommended action
- Status reconciliation notes (when `--resume` detects stale state)

**`bootstrap/session.json`** (machine-readable)

Written by `ai-new` and the agent. Fields include:

| Field | Description |
|-------|-------------|
| `project_name` | Project name |
| `selected_agent` | Agent name as selected at scaffold time |
| `status` | Session status (controlled vocabulary below) |
| `last_updated` | ISO timestamp of last update |
| `generated_files` | List of generated file paths |
| `containerfile_path` | Path to the durable `Containerfile` |
| `quality_gate_status` | Last quality-gate outcome |
| `last_error` | Last error message (when present) |
| `resume_command` | Exact command to resume the session |
| `build_log_path` | Path to `build.log` (when present) |
| `trial_image_tag` | Image tag for the trial build (when present) |
| `static_check_status` | Static-check outcome (when applicable) |
| `pinned_agent_env` | Path and SHA-256 hash of `bootstrap/agent.env` |

### Session status vocabulary

| Status | Meaning |
|--------|---------|
| `started` | Scaffold created, bootstrap container not yet launched |
| `interviewing` | Agent interview in progress |
| `generated` | Scaffold files written; quality gate not yet complete |
| `quality-gate-running` | Host-side build gate is currently running |
| `quality-gate-failed` | Trial build failed after all repair attempts |
| `quality-gate-timeout` | Trial build exceeded the configured timeout |
| `generated-unvalidated` | Scaffold generated; trial build was skipped |
| `interrupted` | Session was interrupted (stale lock reconciled) |
| `complete` | Scaffold generated and trial build passed |

A scaffold is **complete** only when:
- `image/Containerfile` exists
- All required v1 scaffold files (see [Section 14](#14-generated-scaffold)) exist
- The quality gate has passed or been explicitly skipped
- Final next-step instructions have been written
- `session.json` status is `complete` or `generated-unvalidated`

### Resuming a session

```bash
ai-new my-project --resume
```

`--resume`:
1. Acquires the concurrency lock (see [Section 12](#12-concurrency--lock-management)).
2. Performs status reconciliation (see [Section 12.4](#124-stale-lock-reconciliation)).
3. Re-enters the bootstrap container; the agent reads `session.md` and
   `session.json` to restore interview continuity rather than restarting.
4. Reads runtime metadata from the pinned `bootstrap/agent.env` (never
   re-prompts for agent selection).

**Resume fails clearly** if `session.json` is missing or unreadable. It does
not silently restart the session.

**Agent config persistence:** The bootstrap container's `$HOME`
(`/project/bootstrap/home`) is host-persisted. Authentication tokens, agent
settings, and conversation context stored there survive bootstrap image rebuilds
and resumed sessions.

---

## 10. Host-Side Quality Gate

After the agent generates the scaffold, `ai-new` (running on the host) runs the
quality gate:

1. **Static check** (advisory) — checks the generated `Containerfile` for
   syntax errors. Tool preference order:
   1. Podman-native parse/check mode (when available and reliable)
   2. Buildah parse/check equivalent
   3. `hadolint` (when installed)
   4. None (recorded as `static_check=skipped`; does not fail the gate)
   
   A static-check failure records `static_check=failed` with details in
   `bootstrap/static-check.log` but does **not** by itself cause
   `quality-gate-failed` unless the trial build also fails.

2. **Trial `podman build`** — attempts to build the durable image from
   `image/Containerfile`. Runs in the host `ai-new` process; never inside the
   bootstrap container.

3. **Build-log capture** — full output written to `bootstrap/build.log`,
   preserved across resumes and timeouts (partial log on timeout).

### Trial-image naming

The durable image is tagged `localhost/ai-new/<slug>:trial`, where `<slug>` is
derived from `<name>` by a deterministic sanitizer:

1. Convert to lowercase ASCII where possible.
2. Replace any character outside `[a-z0-9._-]` with `-`.
3. Collapse repeated `-`.
4. Trim leading/trailing `.`, `_`, and `-`.
5. Fail clearly if the result is empty.
6. Cap at 63 characters; append `-<8-char-hash-of-original-name>` when
   truncation occurs.

On successful validation the image may also be tagged
`localhost/ai-project/<slug>:latest`. The trial image is left in local Podman
storage as a warm cache for the user's first real build. Its tag is recorded in
`session.json`.

**Slug collision:** If two distinct project names sanitize to the same slug,
`ai-new` fails closed — it reports the computed slug and the existing
project/image already using it, and tells you to choose a distinct name. It
does not silently disambiguate or append random suffixes.

### Quality-gate outcomes

| Outcome | `session.json` status | Notes |
|---------|----------------------|-------|
| Build passes | `complete` | Trial image left in local storage |
| Build skipped (`--skip-trial-build`) | `generated-unvalidated` | Agent explicitly warns: no build validation performed; user must build manually |
| Build timeout | `quality-gate-timeout` | Partial build log preserved; session remains resumable |
| Build fails after all repair attempts | `quality-gate-failed` | Agent summarizes what failed, what was attempted, and the user's next decision |

### Build timeout

| Variable / Flag | Description |
|-----------------|-------------|
| `AI_NEW_BUILD_TIMEOUT` | Duration (GNU `timeout(1)` syntax: bare seconds or suffixed, e.g. `300`, `10m`, `1h`). Default: `30m`. |
| `--skip-trial-build` | Skip entirely; results in `generated-unvalidated`. |

Enforcement wraps the build with `timeout --foreground "$AI_NEW_BUILD_TIMEOUT"`.

### Repair attempts

On build failure, `ai-new` writes the build log to `bootstrap/build.log`,
updates `session.json`, and signals the agent (or re-enters the bootstrap
container on resume) so it can inspect the log and repair the generated files.

Repair attempts are capped at **3** by default (overridable with
`AI_NEW_MAX_REPAIR_ATTEMPTS=<n>`). After the final failed repair cycle, status
becomes `quality-gate-failed`. The user may resume explicitly to trigger another
repair/build cycle.

---

## 11. Host↔Container Coordination Protocol

The host-side `ai-new` supervisor and the in-container agent coordinate through
files in `bootstrap/` only — never a host socket, FIFO, or nested Podman. This
makes the protocol inspectable and reconstructable after crashes.

### Build request flow

```
[Agent in container]                        [ai-new on host]
       │                                           │
       │  write build.request.<id>.json.tmp        │
       │  rename to build.request.<id>.json ──────►│
       │                                           │ detect (2s poll)
       │                                           │ validate request
       │                                           │ set session status: quality-gate-running
       │                                           │ run static check
       │                                           │ run podman build
       │                                           │ write build.log
       │◄── write build.result.<id>.json ──────────│
       │    update session.json                    │
       │  poll for result (2s interval)            │
       │  read build.log                           │
       │  repair or report                         │
```

### Request file format

**`bootstrap/build.request.<id>.json`** (written atomically by the agent):

| Field | Description |
|-------|-------------|
| `request_id` | Monotonically increasing integer |
| `requested_at` | ISO timestamp |
| `requested_by` | Identifier for the requesting entity |
| `containerfile` | Path to the `Containerfile` to build |
| `context_dir` | Build context directory |
| `image_tag` | Target image tag |
| `reason` | Human-readable reason for this build request |
| `repair_iteration` | Which repair attempt this is (0-indexed) |

**`bootstrap/build.result.<id>.json`** (written by the host supervisor):

| Field | Description |
|-------|-------------|
| `request_id` | Matches the request |
| `started_at` | ISO timestamp |
| `finished_at` | ISO timestamp |
| `exit_code` | Build process exit code |
| `status` | `passed` / `failed` / `timeout` |
| `static_check_status` | `passed` / `failed` / `skipped` |
| `build_log_path` | Path to `bootstrap/build.log` |
| `image_tag` | Image tag that was built |
| `error_summary` | Short summary of the failure (when applicable) |

### Atomicity and validation

- The agent writes `build.request.<id>.json.tmp`, closes it, then renames it to
  `build.request.<id>.json`. The host processes only final non-`.tmp` files.
- The host rejects: malformed files, missing required fields, non-integer request
  IDs, stale request IDs (less than or equal to the last completed request ID).
- Duplicate requests whose `request_id` already has a matching result file are
  silently ignored.
- The agent allocates the next `request_id` by reading the highest existing
  request/result file IDs and the value in `session.json`, then adding 1.

### Polling intervals

- Host supervisor polls for new request files: every **2 seconds** (overridable
  with `AI_NEW_COORDINATION_POLL_INTERVAL=<duration>`).
- In-container agent polls for the matching result file: every **2 seconds**.
- Polling is chosen over `inotify` for determinism across bind mounts, container
  disposal, and resume/crash recovery.

### In-container UX during the build

While waiting for `build.result.<id>.json`:

- The agent tells the user the host-side supervisor is running the quality gate
  outside the container.
- It periodically shows concise progress: current `session.json` status, build
  log path, elapsed time, timeout setting.
- It may tail or summarize `bootstrap/build.log`.
- It **must not** run `podman build` itself and **must not** require host socket
  access.

On result:
- **Pass** → report success; write final next steps.
- **Failure** → read `build.log`; repair files; optionally request another build
  with the next `request_id`.
- **Timeout** → report and leave the session resumable.

### Crash reconstruction

If `build.request.<id>.json` exists without a matching `build.result.<id>.json`
and no active lock or build process exists, `ai-new --resume` treats the request
as interrupted and reconciles per the stale-lock reconciliation rules (see
[Section 12.4](#124-stale-lock-reconciliation)). Reconciliation notes are
appended to `bootstrap/session.md`.

---

## 12. Concurrency & Lock Management

`ai-new` prevents concurrent bootstrap sessions for the same project using an
atomic lock directory.

### Lock mechanics

The lock is `bootstrap/session.lock/`, created via atomic `mkdir`:

- **Success** → the caller owns the lock.
- **Failure** (directory already exists) → the session is locked; `ai-new`
  inspects for active vs. stale state.

The lock records:

| Field | Description |
|-------|-------------|
| `pid` | Host supervisor process ID |
| `hostname` | Host machine name |
| `container_name` | Bootstrap container name |
| `started_at` | ISO timestamp when the lock was acquired |
| `last_heartbeat` | ISO timestamp of the most recent heartbeat write |

### Lock ownership

The **host-side `ai-new` supervisor owns the lock** for the duration of the
session: while the bootstrap container runs, while the quality gate runs, and
while it supervises a repair/resume loop.

- The bootstrap container and agent do **not** own the lock.
- They are not trusted to clear it.
- They may read lock/session state for diagnostics only.

### Heartbeat

The supervisor refreshes `last_heartbeat` every **60 seconds** by default. The
refresh interval adjusts when `AI_NEW_LOCK_STALE_AFTER` is overridden:
`min(60s, stale_threshold / 5)` with a lower bound of 10 seconds.

### 12.4 Stale-lock reconciliation

A lock is **stale** when:

- The recorded bootstrap container no longer exists or is not running, **and**
- The recorded host-side supervisor process is not alive, **or**
- `last_heartbeat` is older than the configured threshold (default: **10 minutes**,
  overridable with `AI_NEW_LOCK_STALE_AFTER=<duration>`).

**On stale-lock detection**, `ai-new` reports (it never silently removes the
lock):

- The lock path
- Recorded `pid`, `hostname`, `container_name`, `started_at`, `last_heartbeat`
- Why the lock is considered stale
- The exact manual clear command (e.g. `rm -rf ~/codex-jails/projects/my-project/bootstrap/session.lock`)

In interactive mode it may confirm and then remove. In non-interactive mode it
fails closed and prints the manual clear command.

**After clearing a stale lock**, `ai-new --resume` reconciles `session.json`
status before re-entering the bootstrap container:

| Stale status | Condition | Reconciled to |
|-------------|-----------|---------------|
| `interviewing` | Lock was stale | `interrupted` |
| `quality-gate-running` | No complete build log | `quality-gate-timeout` (if timeout exceeded), otherwise `interrupted` |
| `quality-gate-running` | Failure log captured | `quality-gate-failed` |
| `quality-gate-running` | Success marker captured | `complete` |

Reconciliation notes are appended to `bootstrap/session.md`.

---

## 13. Security & Safety Posture

### Container isolation

| Property | Value |
|----------|-------|
| User namespace | `--userns=keep-id` (rootless) |
| Mounted paths | `$CODEX_JAILS_DIR/projects/<name>/` → `/project` only |
| Host `~/.ssh` | Not mounted |
| Host config dirs | Not mounted |
| Host agent sockets | Not mounted |
| Host Podman socket | Not mounted |
| Nested Podman | Not allowed; no `--privileged` |
| Network | Enabled (required for agent API calls and auth) |

### Registry safety

Registry files are **never `source`d, `eval`'d, or run via `sh -c`**. A value
containing command substitution (e.g. `$(rm -rf /)`) is treated as a literal
string; it is never executed. All adapter execution constructs argv arrays from
validated string fields without any shell interpolation of registry content.

Unknown adapter names are a validation error; the command exits non-zero.

### Quality gate safety

The trial `podman build` runs entirely in the **host `ai-new` process**. The
host Podman socket is not present inside the bootstrap container. The bootstrap
container cannot initiate builds and cannot be granted nested-Podman privileges.

---

## 14. Generated Scaffold

When the agent finishes the interview and generation, the project tree contains
at minimum:

| Path | Description |
|------|-------------|
| `workspace/` | Project workspace directory |
| `image/Containerfile` | **The durable development image definition** |
| `profile.env` | `ai-agent-podman-sandbox`-compatible profile |
| `launchers/<name>` | Launch wrapper |
| `build-update.sh` | Helper script to rebuild and update the image |
| `README.md` | Next steps, project summary, and usage |
| `.env.example` | Placeholder environment variable file (no secrets) |
| `.gitignore` | Excludes `bootstrap/agent.env.local`, `bootstrap/home/`, project `.env`, and runtime secret/cache files |
| `bootstrap/session.md` | Session notes |
| `bootstrap/session.json` | Machine-readable resume state |

The most important generated file is `image/Containerfile`. It defines the real
durable development image and is immediately buildable:

```bash
podman build -t my-project ~/codex-jails/projects/my-project/image/
```

**Conventions all generated files follow:**

- Paths derived from `$HOME` / `$CODEX_JAILS_DIR`, never hardcoded usernames.
- Profile shape follows `ai-agent-podman-sandbox` conventions.
- Secrets are not baked into the image or committed to version control.
- `.env.example` provides placeholder variable names; the user populates a
  separate `.env` file that is gitignored.

---

## 15. Secrets & Credentials

### Credential source order (in-container, at `/start-here.sh` time)

1. **Persisted agent config** in the bootstrap home
   (`/project/bootstrap/home`) — credentials stored by the agent CLI during a
   previous auth flow.
2. **API key variables** in `bootstrap/agent.env.local` — a host-persisted,
   gitignored file sourced only for the bootstrap runtime. Declare API key
   variable names using `AGENT_ENV_VARS` in the registry file.
3. **Interactive login/setup** — initiated by the agent CLI itself, if the
   runtime supports it (`AGENT_PROMPT_MODE=yes`).

### `bootstrap/agent.env.local`

This file holds bootstrap-time API key credentials. It is:

- **Gitignored** — never committed.
- **Host-persisted** — lives in the project tree, survives container disposal.
- **Distinct** from `bootstrap/agent.env` (pinned non-secret registry metadata).
- **Distinct** from the generated project's `.env.example` (placeholder only).

Example:

```
OPENAI_API_KEY=sk-...
```

### Authentication validation

`/start-here.sh` validates authentication **before** starting the interview. If
credentials are missing or invalid, it:

- Reports the failure clearly.
- Gives the required setup command or file path (e.g. "Run `codex auth login`
  or add `OPENAI_API_KEY` to `bootstrap/agent.env.local`").
- Exits non-zero **without starting the interview**.

### Generated project credentials

The agent steers all secrets toward **runtime mounting** rather than baking them
into the image. The generated scaffold provides:

- `.env.example` with placeholder variable names.
- `.gitignore` entries excluding any populated `.env` files and secret material.
- Profile/launcher wrappers that source the runtime-mounted `.env`.

No populated secret files are baked into the image or committed to version control.

---

## 16. Configuration Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CODEX_JAILS_DIR` | `~/codex-jails` | Base directory for projects, bin, lib, and config |
| `AI_NEW_SKIP_TRIAL_BUILD` | `0` | Set to `1` to skip the trial build (equivalent to `--skip-trial-build`) |
| `AI_NEW_BUILD_TIMEOUT` | `30m` | Trial build timeout. GNU `timeout(1)` syntax: bare seconds or suffixed (`300`, `10m`, `1h`) |
| `AI_NEW_MAX_REPAIR_ATTEMPTS` | `3` | Maximum agent repair iterations before declaring `quality-gate-failed` |
| `AI_NEW_COORDINATION_POLL_INTERVAL` | `2s` | How often the host supervisor polls for new build-request files |
| `AI_NEW_LOCK_STALE_AFTER` | `10m` | Stale-lock threshold. Same syntax as `AI_NEW_BUILD_TIMEOUT` |

---

## 17. Deferred Features (Post-v1)

The following are **not implemented in v1** and are reserved as future enhancements.

| Feature | Status |
|---------|--------|
| `--force` | Destructive recreate after confirmation. Deferred; `ai-new` recognises the flag and prints a "deferred beyond v1" message. |
| `--refresh-agent-registry` | Re-pin a drifted runtime definition from the global registry, comparing the pinned hash against the current file and confirming before replacing. Deferred; similarly recognised and rejected. |
| Interactive multi-runtime chooser | When `--agent` is omitted and multiple runtimes are registered, v1 fails with guidance; an interactive chooser is post-v1. |
| Automatic Gemini installation | `gemini` is a `manual` runtime in v1. Automatic installation via a safe, official path requires a future requirement. |

---

## Appendix A: Acceptance Criteria Reference

The following maps documentation sections to the requirements that drove them.

| AC | Covered in section |
|----|-------------------|
| AC1 — Scaffold layout, minimal bootstrap image | §5, §6 |
| AC2 — Unknown agent exits non-zero, lists registered | §4, §7 |
| AC3 — Collision handling per `session.json` status | §4, §9 |
| AC4 — `--resume` re-enters; missing `session.json` fails clearly | §9 |
| AC5 — `/start-here.sh` at container root; no questionnaire | §4, §6 |
| AC6 — Missing credentials: clear failure, exit non-zero | §15 |
| AC7 — Agent interview covers R5.2 minimum set | §8 |
| AC8 — Complete minimal scaffold at session end | §14 |
| AC9 — `session.json` R11.3 fields; status vocabulary | §9 |
| AC10 — Secret handling: `.env.example`/runtime-mount; gitignore | §15, §14 |
| AC11 — No hardcoded usernames; paths from `$HOME`/`CODEX_JAILS_DIR` | §5, §14 |
| AC12 — Quality gate: static check, trial build, log capture, status | §10 |
| AC13 — `--skip-trial-build` and timeout handling | §10, §16 |
| AC14 — Generated files persist after bootstrap disposal | §6, §9 |
| AC15 — Single mounted project tree; `$HOME` at `bootstrap/home` | §5, §6 |
| AC16 — Four next-step instructions with actual paths/commands | §8 |
| AC17 — Rootless, `--userns=keep-id`, network enabled, no host socket | §13 |
| AC18 — Durable image usable as intended environment (manual) | §14 |
| AC19 — Help flags print usage; failure paths exit non-zero | §4 |
| AC20 — Registry never `source`d/`eval`'d; hostile values not executed | §7, §13 |
| AC21 — Pinned `agent.env` with hash and timestamp; resume reads pinned | §7 |
| AC22 — Trial build on host; no host socket in container | §10, §13 |
| AC23 — `AI_NEW_BUILD_TIMEOUT` syntax, default, enforcement, timeout status | §10, §16 |
| AC24 — Active lock refused; stale lock reported with clear path | §12 |
| AC25 — Trial image tagged `localhost/ai-new/<slug>:trial`; tag in `session.json` | §10 |
| AC26 — Resume honors recorded agent; fails clearly if absent or broken | §9, §15 |
| AC27 — File-based coordination; atomic writes; stable hash; deterministic slug | §11, §7, §10 |
| AC28 — In-container progress UX; no `podman build` from container | §11 |
