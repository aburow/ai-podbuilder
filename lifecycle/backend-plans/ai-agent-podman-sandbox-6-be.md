---
title: AI Agent Podman Sandbox Framework — Backend Plan
type: plan-backend
status: in-development
lineage: ai-agent-podman-sandbox
parent: lifecycle/requirements/ai-agent-podman-sandbox-5.md
created: "2026-06-22T00:00:00+10:00"
priority: normal
assignees:
    - role: backend-developer
      who: agent
---

# AI Agent Podman Sandbox Framework — Backend Plan

This plan covers the **core engine** of the framework: the generic command
binaries under `bin/`, the shared sourced library that holds the single
authoritative safety policy, profile loading/validation, the persistent
container lifecycle, stale-image reconciliation, framework-managed teardown,
network/secret/SELinux handling, and the legacy compatibility wrappers.

User-facing presentation concerns (summary banners, interactive prompts,
`ai-list` column formatting, desktop/Podman-Desktop integration, SSH and
security docs) are owned by the **frontend plan**
(`ai-agent-podman-sandbox-7-fe.md`). Where the two meet, this plan exposes the
hooks the frontend renders.

Implementation constraints (apply to every milestone, per R13.1):

- POSIX/Bash with `#!/usr/bin/env bash` and `set -euo pipefail`.
- No daemon beyond rootless Podman; no external runtime dependencies other than
  `podman` and coreutils.
- No hardcoded usernames or `/var/home/<user>` paths — every path derives from
  `$HOME` / `$CODEX_JAILS_DIR` (R1.1, R12.2).
- Every command supports `-h` / `--help` and exits non-zero with an actionable
  message on error (R13.2).
- Source files live under `bin/` and `lib/`; a `shellcheck` clean pass is a
  precondition for every milestone marked complete.

---

## Milestone B1 — Repository layout and shared library skeleton

**Description.** Establish the on-disk layout and the shared sourced library
that every command depends on. The library resolves the base directory,
exposes path helpers, a uniform logging/error surface, and an interactive
detection helper. Nothing privileged or container-touching yet.

Resolution rules:

- `CODEX_JAILS_DIR` defaults to `${CODEX_JAILS_DIR:-$HOME/codex-jails}` (R1.1).
- Derived dirs: `$CODEX_JAILS_DIR/bin`, `/profiles`, `/launchers` (R1.2).
- Project workspaces and image dirs are siblings: `<name>-workspace/`,
  `<name>-image/` (R1.2).
- `lib/common.sh` is sourced by every command; it must be locatable relative to
  the running script (`BASH_SOURCE` dirname), not via a hardcoded path, so the
  repo is self-hosting from a sandbox workspace (R13.4).

**Files to change / create.**

- `lib/common.sh` — `_die`, `_warn`, `_info` log helpers (stderr, non-zero exit
  on `_die`); `resolve_base_dir`; `is_interactive` (`[[ -t 0 && -t 1 ]]`, R4.10);
  `require_cmd podman`.
- `bin/.gitkeep`, `profiles/.gitkeep`, `launchers/.gitkeep` (or example dirs as
  the frontend plan finalises).
- `README.md` stub describing the layout and `PATH` setup (R1.3) — full docs are
  the frontend plan's responsibility; this is the skeleton only.

**Acceptance criteria.**

- Sourcing `lib/common.sh` from any directory resolves the correct base dir with
  and without `CODEX_JAILS_DIR` set; no username appears anywhere in the source.
- `is_interactive` returns true only when both stdin and stdout are TTYs.
- `_die "msg"` prints `msg` to stderr and exits non-zero; `_warn`/`_info` do not
  exit.
- `shellcheck lib/common.sh` is clean.

---

## Milestone B2 — Profile loading and validation

**Description.** Implement profile sourcing and validation as a library function
used by every command. A profile is exactly one sourced Bash fragment
`profiles/<name>.env` (R2.1).

- Required fields (R2.2): `PROFILE_NAME`, `CONTAINER_NAME`, `IMAGE_NAME`,
  `IMAGE_DIR`, `WORKSPACE`, `CONTAINER_HOME`, `BASHRC`, `WORKDIR`, `BUILD_ARGS`.
- Optional values/arrays (R2.3): `EXTRA_ENV`, `EXTRA_VOLUMES`, `EXTRA_DEVICES`,
  `EXTRA_HOSTS`, `EXTRA_RUN_ARGS`, `POST_BUILD_CHECK`, `PNPM_HOME`, `HISTFILE`.
- Optional control values (R2.4): `ENV_FILE`, `NETWORK_MODE`, `SELINUX_MODE`.
- A missing file or any missing required field fails with a clear, actionable
  message naming the file and the offending field, non-zero exit (R2.6).
- The loader must not require secrets in the profile and should not error if
  optional arrays are unset (treat as empty).

**Files to change / create.**

- `lib/profile.sh` — `load_profile <name>`: locate `profiles/<name>.env`, source
  it, assert required fields are non-empty, normalise optional arrays to defined-
  but-possibly-empty arrays.
- `lib/common.sh` — add `profiles_dir` helper.
- `profiles/esp32.env.example`, `profiles/uxplay.env.example` — reference
  profiles exercising required + a representative set of optional fields
  (uxplay declares a `builder` use and a device; esp32 declares `--device`,
  `EXTRA_HOSTS`, `EXTRA_ENV`). These double as fixtures for the test plan.

**Acceptance criteria.**

- `load_profile esp32` populates all required variables; a profile missing any
  required field exits non-zero naming that field (R2.6).
- `load_profile nonexistent` exits non-zero with a message naming the expected
  path.
- Optional arrays left unset are usable as empty arrays without `unbound
  variable` errors under `set -u`.
- `shellcheck lib/profile.sh` is clean.

---

## Milestone B3 — `ai-build`

**Description.** Implement image building from a profile (R3).

- `ai-build <profile>` sources the profile, runs `podman build` in `IMAGE_DIR`
  using `BUILD_ARGS` (R3.1).
- On success, run `POST_BUILD_CHECK` inside the freshly built image to print
  installed tool/library versions (R3.2). If `POST_BUILD_CHECK` is unset, skip
  cleanly with an informational note.
- Errors — profile not found, `IMAGE_DIR` missing, build failure — exit non-zero
  with a clear message (R3.3).
- `-h`/`--help`/no-arg prints usage (R3.4).
- **`ai-build` never touches existing containers** (R3.5). It builds/rebuilds the
  image only and maintains **no** framework image-state file; staleness is a
  launch-time concern (R4.9).

**Files to change / create.**

- `bin/ai-build` — argument parsing, profile load, build, post-build check.
- `lib/build.sh` (optional) — shared build helpers if reused by wrappers.

**Acceptance criteria.**

- With a valid profile and existing `IMAGE_DIR`, `ai-build <profile>` builds the
  image and prints `POST_BUILD_CHECK` output (AC1).
- Missing profile or missing `IMAGE_DIR` exits non-zero with a clear message
  (AC1, R3.3).
- After a successful build, no file under `$CODEX_JAILS_DIR/state/` is created
  and no container is created, started, stopped, or removed (R3.5).
- `ai-build` with no args / `-h` prints usage and exits zero.

---

## Milestone B4 — Safety policy assembly (single authoritative source)

**Description.** Centralise the normal-mode safety policy in one library
function so every launch is identical and drift is impossible (R5, project
goal). This function builds the run-argument array; no command constructs safety
flags inline.

Normal-mode policy (R4.3, R5):

- `-it`, `--userns=keep-id`, `--group-add keep-groups`,
  `--security-opt no-new-privileges` (R5.1).
- SELinux per `SELINUX_MODE` (R5.6): default `disable` →
  `--security-opt label=disable`; `enforce` → omit `label=disable` and rely on
  the `:Z` relabel on the mount alone.
- `-e HOME=$CONTAINER_HOME` (R5.4), the single mount `-v $WORKSPACE:/workspace:Z`
  (R5.2), `-w $WORKDIR`.
- **Forbidden in normal mode:** `--privileged` (R5.3) and any mount of host
  `$HOME`, `~/.ssh`, `~/.gnupg`, `~/.config`, `/`, the Docker socket, or the
  Podman socket (R5.2). The assembler must structurally make these impossible —
  it emits exactly one bind mount and never the socket.
- Append profile `EXTRA_*` arrays in normal mode (R4.6): hosts, devices,
  volumes, env, run args.
- Network via `--network ${NETWORK_MODE:-slirp4netns}` (R6.1); `none` →
  fully offline (R6.2); overridable per-invocation env var and per profile
  (R6.3).
- Secrets (R7): if `ENV_FILE` is set and the file exists, add
  `--env-file <file>`; if set but missing, **warn and continue** (R7.2); if
  unset, mount nothing (R7.1).

**Files to change / create.**

- `lib/policy.sh` — `build_normal_run_args` returning the assembled array;
  `selinux_args`; `network_args`; `secret_args`; `extra_args`.
- `lib/common.sh` — array-append helpers if needed.

**Acceptance criteria.**

- `build_normal_run_args` for a default profile yields exactly one bind mount
  (`$WORKSPACE:/workspace`), `--userns=keep-id`, `--group-add keep-groups`,
  `no-new-privileges`, `label=disable`, `HOME=$CONTAINER_HOME` — and none of the
  forbidden mounts or `--privileged` (AC2).
- A profile with `SELINUX_MODE=enforce` yields no `label=disable` while keeping
  the `:Z` mount (AC9).
- `NETWORK_MODE=none` yields `--network none`; default yields the configured
  default network (AC7).
- A declared `--device`, `EXTRA_HOSTS`, and `EXTRA_ENV` appear verbatim, and only
  when that profile declares them (AC8).
- `ENV_FILE` present → `--env-file` added; set-but-missing → warning emitted and
  launch proceeds without it; unset → no secret args (AC13).
- `shellcheck lib/policy.sh` is clean; grepping the assembler for `--privileged`,
  socket paths, or `$HOME` host mounts finds none in the normal path.

---

## Milestone B5 — `ai-launch` core: modes, persistence, and summary hook

**Description.** Implement the launch entry point with persistent normal-mode
containers and the privileged ephemeral builder path (R4).

- `ai-launch <profile> [mode]` sources the profile; ensures `WORKSPACE`,
  `CONTAINER_HOME`, `PNPM_HOME`, and `.bash_history`/`HISTFILE` paths exist
  before launch (R4.1).
- **Persistence (R4.2).** Normal-mode containers are **named and not `--rm`**. If
  a container named `$CONTAINER_NAME` already exists, reuse it: start if stopped,
  then attach / `exec` an interactive shell or the mode command. Otherwise create
  it. Routine exit never removes the container.
- **Modes (R4.4):** `shell`/`bash` (default), `codex`, `codex`, `builder`. Mode
  dispatch maps a mode to the in-container command; the set is extensible
  (`aider`, `opencode`, `ollama-shell`) without touching the safety core — add a
  mode-to-command table, not new launch logic.
- **Builder mode (R4.5, R4.12):** the only `--privileged` path; distinct
  `${CONTAINER_NAME}-builder` name; **ephemeral `--rm`**; reachable only by
  explicitly passing `builder`, never default. Build caching is via mounted
  cache/workspace dirs, not a lingering privileged container. Any
  `builder-persistent` variant is explicitly out of scope for v1.
- **Unknown mode** exits non-zero and prints usage (R4.7).
- Emit a **pre-launch summary** (R4.8) describing profile, container, image,
  workspace, container `$HOME`, mode, network, SELinux mode, and whether an
  existing container is being reused. The summary text/format is rendered by the
  frontend helper (`render_launch_summary`); this milestone calls it with a
  structured set of fields.

**Files to change / create.**

- `bin/ai-launch` — arg parsing (profile, mode, flags stubbed for B6/B7), path
  bootstrap, mode dispatch table, create-vs-reuse logic, builder branch.
- `lib/container.sh` — `container_exists`, `container_running`,
  `container_image_id`, `create_normal_container`, `start_and_attach`,
  `exec_mode_command`, `run_builder_ephemeral`.
- `lib/policy.sh` — `build_builder_run_args` (privileged + `--rm` + `-builder`
  name + mounted caches).

**Acceptance criteria.**

- First `ai-launch <profile>` creates a persistent named container with the B4
  normal policy; after exit the container still exists (AC2, AC3).
- A second `ai-launch <profile>` reuses the existing container; workspace and
  in-container `$HOME` state from the first session is present (AC3).
- `ai-launch <profile> codex` / `codex` / `bash` start the respective agent /
  shell inside the sandbox (AC4).
- `ai-launch <profile> builder` is the **only** invocation producing
  `--privileged`, uses the `-builder` name, and the builder container no longer
  exists after exit while the normal container is unaffected (AC5, AC6).
- An unknown mode exits non-zero and prints usage (R4.7).
- The pre-launch summary lists all R4.8 fields including the reuse flag.

---

## Milestone B6 — Stale-image reconciliation

**Description.** Detect and reconcile a persistent container whose source image
no longer matches the current local image (R4.9), comparing live image IDs only
— **no framework-maintained state file** (R3.5/R4.9).

- Existing container image ID:
  `podman inspect --format '{{.Image}}' "$CONTAINER_NAME"`.
- Current local image ID:
  `podman image inspect --format '{{.Id}}' "$IMAGE_NAME"`.
- If both exist and differ → stale.
- **Interactive (R4.9):** warn and offer three explicit choices — (1) continue
  with the existing container; (2) recreate from the new image preserving the
  workspace-mounted state and container-home; (3) cancel and inspect manually.
  The prompt rendering is a frontend helper (`prompt_stale_choice`); this
  milestone consumes its return value.
- **Non-interactive default (R4.9, R4.10):** warn-and-continue; never
  auto-recreate.
- Explicit flags (R4.10): `--yes`/`--non-interactive` → warn and continue (never
  recreate); `--recreate` → remove and recreate the persistent container from the
  current image, preserving workspace and container-home; `--no-recreate` →
  explicitly continue.

**Files to change / create.**

- `bin/ai-launch` — staleness check before attach; flag parsing for `--yes`,
  `--non-interactive`, `--recreate`, `--no-recreate`.
- `lib/container.sh` — `image_is_stale`, `recreate_preserving_workspace` (remove
  container only; workspace + container-home dirs are on the bind mount and are
  never deleted).

**Acceptance criteria.**

- After `ai-build` changes the image ID, an interactive `ai-launch <profile>`
  warns and offers continue / recreate(preserving workspace) / cancel (AC14).
- `ai-launch <profile> --yes` (or `--non-interactive`) warns and continues
  without recreating (AC14, R4.10 — `--yes` MUST NOT recreate).
- `ai-launch <profile> --recreate` recreates from the current image while
  workspace and container-home content survive (AC14).
- Launch correctness does not depend on any file under
  `$CODEX_JAILS_DIR/state/`; deleting such a path (if any) changes nothing
  (R4.9).

---

## Milestone B7 — Framework-managed teardown (`--reset`)

**Description.** Implement the canonical teardown path (R4.11).

- `ai-launch <profile> --reset` removes the persistent normal-mode container and
  recreates it from the current image (immediately or on next launch — choose
  one and document it).
- It MUST NOT delete the workspace, container-home directory, profile, image
  directory, or secret env file (R4.11, AC15).
- If the container is running: in interactive mode, stop it after confirmation;
  in non-interactive mode, `--reset` requires an explicit `--yes --reset`
  combination to stop a running container (R4.11, AC15) — `--reset` alone must
  not silently stop a running container.
- Raw Podman teardown remains a documented escape hatch (frontend docs), but
  `--reset` is the canonical v1 path.

**Files to change / create.**

- `bin/ai-launch` — `--reset` handling layered onto B6 flag parsing.
- `lib/container.sh` — `reset_container` (stop-if-allowed → remove → recreate),
  guarding the protected directories.

**Acceptance criteria.**

- `ai-launch <profile> --reset` removes the persistent container and leaves
  workspace, container-home, profile, image dir, and secret env file intact; a
  subsequent `ai-launch <profile>` recreates the container from the current
  image (AC15).
- In non-interactive use, `--reset` without `--yes` does not silently stop a
  running container (AC15).
- Builder containers are unaffected by `--reset`.

---

## Milestone B8 — `ai-terminal` and `ai-list`

**Description.** Implement the two remaining generic commands.

- **`ai-terminal <profile>` (R9):** attach an additional interactive shell to the
  running container via `podman exec -it`. If the container is not running, exit
  non-zero with a clear message hinting at `ai-launch` to start/resume (R9.2).
- **`ai-list` (R10):** enumerate `profiles/*.env` and print, per profile, name,
  image name, and workspace path in aligned columns (R10.1). Also indicate
  whether a persistent container exists and its state (running/stopped). A
  missing profile directory exits non-zero with a clear message (R10.2). Column
  alignment/formatting is a frontend concern; this milestone provides the data
  rows and calls the frontend formatter.

**Files to change / create.**

- `bin/ai-terminal` — running-check + `podman exec -it`.
- `bin/ai-list` — profile enumeration + per-profile state lookup.
- `lib/container.sh` — reuse `container_running` / state lookup.

**Acceptance criteria.**

- With a running container, `ai-terminal <profile>` attaches a second shell; with
  none, it exits non-zero with a clear message (AC10).
- `ai-list` prints every profile with name, image, workspace (aligned) plus the
  persistent-container state; an absent profile dir exits non-zero (AC11).

---

## Milestone B9 — Legacy compatibility wrappers

**Description.** Preserve muscle memory by retaining existing script names as
thin wrappers that `exec` the corresponding generic command with fixed arguments
(R11).

- Retain: `launch-esp32-workspace`, `short-launch-esp32-workspace`,
  `launch-uxplay-workspace`, `launch-uxplay-builder`, `extra-terminal`,
  `update-codex-esp32-image`, `update-codex-uxplay-image`, and known variants
  (R11.1).
- Each wrapper `exec`s the generic command (e.g. `update-codex-esp32-image` →
  `ai-build esp32`; `launch-uxplay-builder` → `ai-launch uxplay builder`;
  `extra-terminal` → `ai-terminal <profile>`).
- Behaviour is equivalent to the originals, adjusted only for the persistence
  change (R4.2), which wrappers inherit (R11.2).

**Files to change / create.**

- `bin/launch-esp32-workspace`, `bin/short-launch-esp32-workspace`,
  `bin/launch-uxplay-workspace`, `bin/launch-uxplay-builder`,
  `bin/extra-terminal`, `bin/update-codex-esp32-image`,
  `bin/update-codex-uxplay-image` — each a 2–3 line `exec` wrapper.

**Acceptance criteria.**

- Each retained legacy script invokes the corresponding generic command and
  produces equivalent behaviour, inheriting persistence (AC12).
- Wrappers contain no duplicated safety logic — they only `exec` a generic
  command (eliminates drift, project goal).
- `shellcheck bin/*` is clean across all wrappers and commands.
</content>
</invoke>
