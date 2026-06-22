---
title: 'ai-new: Agent-Primed Bootstrap Container — Backend Plan'
type: plan-backend
status: in-development
lineage: ai-new
parent: lifecycle/requirements/ai-new-9.md
created: "2026-06-22T00:00:00+10:00"
priority: normal
assignees:
    - role: backend-developer
      who: agent
---

# ai-new: Agent-Primed Bootstrap Container — Backend Plan

This plan covers the **host-side engine**: the `ai-new` command, scaffold
generation, the safely-parsed runtime registry and pinning, the bootstrap
container launch under the sandbox safety posture, the file-based host↔container
coordination protocol, the host-side quality gate (static check + trial
`podman build` + timeout), session-state read/write, the slug sanitizer, and the
atomic lock with host-owned heartbeat / stale-lock reconciliation.

User-facing surfaces — `/start-here.sh` as an agent-priming launcher, the
structured bootstrap prompt handed to the agent, the in-container waiting UX,
README/next-step text, and help/usage copy — are owned by the **frontend plan**
(`ai-new-11-fe.md`). Where the two meet, this plan owns the contract files the
launcher reads (pinned `bootstrap/agent.env`, `session.json`, build
request/result files) and the host behaviours the launcher and agent depend on.

Implementation constraints (apply to every milestone, per R16):

- POSIX/Bash, `#!/usr/bin/env bash`, `set -euo pipefail`; no daemon beyond
  rootless Podman (R16.1).
- No hardcoded usernames or `/var/home/<user>` paths — derive every path from
  `$HOME` / `$CODEX_JAILS_DIR` (R2.1, R6.4).
- Every command supports `-h`/`--help` and exits non-zero with an actionable
  message on failure (R1.7, R16.2).
- **Registry content is never `source`d, `eval`'d, or run via `sh -c`** (R13.2,
  R13.4). All adapter execution builds argv arrays internally with no shell
  interpolation of registry strings.
- `shellcheck` clean is a precondition for every milestone marked complete.
- Targets Bazzite/Fedora with rootless Podman (R16.3).

---

## Milestone B1 — Command skeleton, layout resolution & shared library

**Description.** Establish the `ai-new` entry point, argument parsing, and the
shared library functions every later milestone builds on. Resolve the base
directory and the per-project paths; provide logging/error helpers and
interactivity detection. No container or build behaviour yet.

- `CODEX_JAILS_DIR` defaults to `${CODEX_JAILS_DIR:-$HOME/codex-jails}` (R2.1).
- Project root is `$CODEX_JAILS_DIR/projects/<name>/`; derive `workspace/`,
  `image/`, `launchers/`, `bootstrap/` (and `bootstrap/home/`) paths (R2.2).
- Global locations: `$CODEX_JAILS_DIR/bin`, `$CODEX_JAILS_DIR/config/agents.d/`
  (R2.3, R13.1).
- Parse the v1 flag surface: `<name>`, `--agent <agent>`, `--resume`,
  `--skip-trial-build`, `-h`/`--help`. `--force` and `--refresh-agent-registry`
  are recognised only to emit a "deferred beyond v1" message, not implemented
  (R1.6, R12.1, R2.6).

**Files to change / create.**

- `bin/ai-new` — shebang, `set -euo pipefail`, arg parsing, dispatch stubs.
- `lib/common.sh` — `_die`/`_warn`/`_info` (stderr; `_die` exits non-zero),
  `resolve_base_dir`, `project_paths <name>` (echoes/derives the R2.2 paths),
  `is_interactive` (`[[ -t 0 && -t 1 ]]`), `require_cmd podman`.

**Acceptance criteria.**

- `ai-new -h` prints usage listing `--agent`, `--resume`, `--skip-trial-build`
  and exits zero (AC19).
- Path helpers resolve correctly with and without `CODEX_JAILS_DIR` set; no
  username appears in source (AC11).
- Unknown deferred flags (`--force`, `--refresh-agent-registry`) print a clear
  "deferred beyond v1" message and exit non-zero (R12.1).
- `require_cmd podman` causes a clear non-zero exit when Podman is absent (R1.7,
  AC19).
- `shellcheck bin/ai-new lib/common.sh` is clean.

---

## Milestone B2 — Restricted registry parser & adapter validation

**Description.** Implement the safe, key-by-key registry parser for
`$CODEX_JAILS_DIR/config/agents.d/<agent>.env` and validate the declared
adapters. The parser MUST NOT `source`/`eval`/`sh -c` the file (R13.2, AC20).

- Parse only known keys: `AGENT_NAME`, `AGENT_COMMAND`, `AGENT_CONFIG_DIRS`,
  `AGENT_ENV_VARS`, `AGENT_PROMPT_MODE`, `AGENT_INSTALL_ADAPTER`,
  `AGENT_INSTALL_PACKAGE`, `AGENT_INSTALL_VERSION`, `AGENT_AUTH_CHECK_ARGV`,
  `AGENT_REGISTRY_VERSION` (R13.3, R13.4). Unknown keys are ignored (MAY warn).
- All values load as strings; multi-value fields are colon-separated quoted
  strings decoded into arrays (e.g. `AGENT_CONFIG_DIRS=".codex"`) (R13.3,
  AC20).
- Reject hostile values structurally: a value containing command substitution or
  shell metacharacters is treated as a literal string and never executed (AC20).
- Validate the install adapter against the fixed v1 set: `npm-global`, `pipx`,
  `dnf-package`, `preinstalled`, `manual`; auth-check adapter is `argv`. An
  unknown adapter name is a validation error (R13.11, R13.12, AC20).
- `AGENT_AUTH_CHECK_ARGV` is pipe-delimited (`"codex|--version"`) split into an
  argv array for direct execution without a shell (R13.4, R13.12).
- Ship default registry files for `codex`, `codex`, `gemini` (R13.9, R13.13,
  D1): `codex` → `npm-global` `@openai/codex`; `codex` →
  `npm-global` `@openai/codex`; `gemini` → `manual`.

**Files to change / create.**

- `lib/registry.sh` — `parse_registry_file <path>` (key-by-key, returns
  validated assoc-array fields), `split_multi <value>`, `validate_adapters`,
  `list_registered_agents` (enumerates `config/agents.d/*.env`).
- `config/agents.d/codex.env`, `config/agents.d/codex.env`,
  `config/agents.d/gemini.env` — shipped defaults.

**Acceptance criteria.**

- A registry file is parsed key-by-key and is never `source`d/`eval`'d; a file
  containing command substitution in a string field does not execute that
  content (AC20).
- An unknown `AGENT_INSTALL_ADAPTER` fails validation with a clear message
  (AC20, R13.11).
- Multi-value fields decode from colon-separated form into arrays (AC20).
- `list_registered_agents` returns `codex`, `codex`, `gemini` from the shipped
  defaults (AC2).
- `shellcheck lib/registry.sh` is clean.

---

## Milestone B3 — `--agent` validation, registry hashing & pinning

**Description.** Validate the selected `--agent` against the registry, compute
the stable normalized hash, and pin the entry into the project (R13.5, R13.6,
R13.10).

- Unknown `--agent` exits non-zero, names the unknown agent, and lists registered
  agents (R1.3, AC2).
- **Normalization (R13.10):** read UTF-8; CRLF/CR → LF; strip trailing whitespace
  per line; preserve comments, key order, interior blank lines; remove trailing
  blank lines at EOF; ensure exactly one trailing newline. Hash the normalized
  text with SHA-256. The hash is the authoritative drift detector;
  `AGENT_REGISTRY_VERSION` is display-only.
- **Pinning (R13.6):** copy the selected entry to `bootstrap/agent.env`,
  recording original registry path, selected agent name, optional
  `AGENT_REGISTRY_VERSION`, computed source hash, and copy timestamp.
- `start-here.sh` and resume read runtime metadata only from the pinned copy;
  the global registry is consulted only for diagnostics (R13.7, R13.8).

**Files to change / create.**

- `lib/registry.sh` — `normalize_registry <path>`, `registry_hash <path>`
  (SHA-256 over normalized text), `pin_registry <agent> <project>`.
- `bin/ai-new` — wire `--agent` validation + pinning into the create path.

**Acceptance criteria.**

- `ai-new <name> --agent <unknown>` exits non-zero, names the agent, and lists
  registered agents (AC2).
- The hash is stable for an unchanged normalized file across two independent runs
  and on two machines; semantically-irrelevant line-ending/trailing-whitespace
  differences hash identically while comment/order changes alter the hash (AC27).
- `ai-new` copies the selected entry to `bootstrap/agent.env` with original path,
  agent name, version/hash, and timestamp (AC21).
- `shellcheck` clean.

---

## Milestone B4 — Scaffold generation & collision handling

**Description.** Create the project scaffold and decide create/resume/abort from
`session.json` status, not file presence (R2.2, R2.4).

- Create the R2.2 layout: `workspace/`, `image/`, `profile.env`, `launchers/`,
  `bootstrap/` (with `home/`), `README.md`. Write the bootstrap Containerfile and
  `/start-here.sh` (content owned by FE; this milestone places them) and the
  pinned `bootstrap/agent.env` (B3).
- Initialise `bootstrap/session.json` (status `started`) and `bootstrap/session.md`
  (B7 schema).
- **Collision (R2.4, AC3):** no project dir → create; project exists and status
  is not terminal → refuse the bare invocation and instruct
  `ai-new <name> --resume`; status terminal (`complete`/`generated-unvalidated`)
  → abort without overwriting.
- `--resume` re-enters an existing incomplete scaffold rather than restarting
  (R2.5, R9.2); `--resume` with missing/unreadable `session.json` fails clearly
  (R12.3, AC4).
- Provide the slug sanitizer here so collision logic and trial-image naming share
  it (R20.1, D2): lowercase ASCII; replace chars outside `[a-z0-9._-]` with `-`;
  collapse repeated `-`; trim leading/trailing `.`/`_`/`-`; fail if empty; cap at
  63 chars; append `-<8-char-hash>` on truncation; fail closed if two distinct
  names collide on a slug.

**Files to change / create.**

- `lib/scaffold.sh` — `create_scaffold <name>`, `scaffold_layout`, place bootstrap
  files + pinned `agent.env`.
- `lib/slug.sh` — `sanitize_slug <name>` (deterministic, fail-closed on collision).
- `lib/session.sh` — `read_status <project>`, `init_session <project>`.
- `bin/ai-new` — create/resume/abort dispatch on status.

**Acceptance criteria.**

- Bare `ai-new <name>` creates when absent, refuses-and-suggests-`--resume` when
  incomplete, and aborts without overwriting when terminal (AC3).
- `ai-new <name> --resume` re-enters an incomplete scaffold; `--resume` with
  missing `session.json` fails clearly (AC4).
- The scaffold matches the R2.2 layout (AC1).
- The sanitizer maps the same `<name>` to the same slug deterministically and
  fails closed when two distinct names collide, printing requested name, computed
  slug, the existing user, and guidance (AC27, D2).
- `shellcheck` clean.

---

## Milestone B5 — Bootstrap container launch under safety posture

**Description.** Launch the minimal disposable bootstrap container with the
selected runtime, under the sandbox safety posture (R1, R3, R14, R15, R17).

- Build/pull the v1 bootstrap image from `fedora:latest`, carrying only the
  tooling to run `start-here.sh`, install the **selected** runtime via its
  install adapter, validate credentials, and write files — never the project's
  language stack/build systems/OS packages (R3.1–R3.4).
- Run rootless with `--userns=keep-id`; the **only** writable host mount is the
  project tree mounted at `/project` (R14.1, R14.2, R15.1); no host
  secrets/`~/.ssh`/config dirs/agent sockets/**Podman socket** mounted (R14.2,
  R17.2); `$HOME` = `/project/bootstrap/home` (R14.3, R15.3).
- **Network enabled by default**, independent of the durable project's
  `NETWORK_MODE` (R1.5, AC17).
- The host Podman socket MUST NOT be present and **no nested-Podman privileges**
  are granted (R17.1, R17.2, AC22).
- Drop the user into the container with CWD `/project` (R15.2).
- Install only the selected runtime via the adapter contract (argv-built, no
  shell interpolation): `npm-global`/`pipx`/`dnf-package` run their fixed
  command; `preinstalled`/`manual` perform no install (R13.12, R3.4).

**Files to change / create.**

- `lib/bootstrap_image.sh` — bootstrap Containerfile template (fedora base),
  `ensure_bootstrap_image`.
- `lib/launch.sh` — `launch_bootstrap <project>` assembling the `podman run` argv
  (keep-id, single mount, contained HOME, network on, no socket).
- `lib/adapter.sh` — `run_install_adapter`, `build_argv` (no shell interpolation
  of registry strings).
- `bin/ai-new` — wire image-ensure + launch into create/resume paths.

**Acceptance criteria.**

- `ai-new <name> --agent <agent>` launches a minimal bootstrap container and drops
  the user in; inspecting the image confirms no project language stack/build
  systems/OS packages and only the selected runtime (AC1).
- Container runs rootless, `--userns=keep-id`, network enabled, only the project
  tree mounted, no host Podman socket, no nested-Podman privileges (AC17, AC22).
- `$HOME` inside is `/project/bootstrap/home`; the durable scaffold and bootstrap
  state share the single `/project` mount (AC15).
- Podman-unavailable / image build-or-pull failure exits non-zero with a clear
  message (AC19).
- `shellcheck` clean.

---

## Milestone B6 — Atomic lock, host-owned heartbeat & stale-lock handling

**Description.** Prevent concurrent sessions with an atomic lock directory whose
heartbeat the **host-side supervisor** owns; detect and surface stale locks
without silently clearing them (R19, D3).

- `mkdir bootstrap/session.lock` is the atomic primitive — success owns the lock,
  `EEXIST` means locked (R19.1). Record `pid`, `hostname`, `container_name`,
  `started_at`, `last_heartbeat` (R19.2).
- The host supervisor refreshes `last_heartbeat` every `60s` by default; if
  `AI_NEW_LOCK_STALE_AFTER` overrides the `10m` default, refresh interval is
  `min(60s, threshold/5)` floored at `10s`. It refreshes while the container runs,
  while the gate runs, and while waiting on build request/result transitions
  (R19.6, R19.7).
- A launch that would enter the bootstrap refuses if the lock exists and appears
  **active** (R19.3). A lock is **stale** when the recorded container no longer
  exists/runs **and** the supervisor pid is dead or `last_heartbeat` exceeds the
  threshold (R19.4).
- On stale detection: **never silently remove** — print lock path, recorded
  `pid`/`hostname`/`container_name`/`started_at`/`last_heartbeat`, why it is
  stale, and the exact manual clear command (`rm -rf <project>/bootstrap/session.lock`).
  Interactive MAY confirm-then-remove; non-interactive MUST fail closed (D3,
  R19.4).
- `AI_NEW_LOCK_STALE_AFTER` uses GNU `timeout(1)` duration syntax (R19.7, R18.1).

**Files to change / create.**

- `lib/lock.sh` — `acquire_lock`, `release_lock`, `lock_is_active`,
  `lock_is_stale`, `report_stale_lock`, `heartbeat_loop` (backgrounded by the
  supervisor).
- `bin/ai-new` — acquire before entering a session or running the gate; start the
  heartbeat; release on clean exit.

**Acceptance criteria.**

- A second `ai-new <name> --resume` while a session is active is refused with lock
  details (AC24).
- An uncleanly killed session leaves a lock detectable as stale (dead container or
  expired heartbeat); `ai-new` reports it and offers a safe clear path rather than
  starting concurrently (AC24, D3).
- Non-interactive stale detection fails closed and prints the manual clear command
  (D3).
- `shellcheck` clean.

---

## Milestone B7 — Session-state files (`session.json` / `session.md`)

**Description.** Implement the read/write layer for the two session-state files
and the controlled status vocabulary (R11).

- `session.json` records at minimum (R11.3, AC9): project name; selected agent;
  status; last-update timestamp; generated file list; Containerfile path;
  quality-gate status; last error; resume command; build-log path; trial-image
  tag; static-check status; pinned `agent.env` reference incl. computed source
  hash.
- `status` uses the R11.4 vocabulary: `started`, `interviewing`, `generated`,
  `quality-gate-running`, `quality-gate-failed`, `quality-gate-timeout`,
  `generated-unvalidated`, `interrupted`, `complete`.
- `session.md` records (R11.2): interview summary; decisions; unresolved
  questions; generated files; quality-gate result; next recommended action;
  reconciliation notes. (Content authored by the agent; this milestone provides
  the file, append helpers, and an initial template.)
- Updates are atomic (write `.tmp` + rename) so resume never reads a partial
  file. `ai-new` uses `session.json` for collision/resume; the agent/user use
  `session.md` for continuity (R11.5).
- A scaffold is **complete** only per R11.6 (real `image/Containerfile`; R6.3
  files present; gate passed or explicitly skipped; next-steps written;
  status `complete` or `generated-unvalidated`).

**Files to change / create.**

- `lib/session.sh` — `write_session_field`, `set_status` (validates against
  R11.4 vocabulary), `append_session_md`, `is_complete` (R11.6 check),
  `resume_command_for <project>`.

**Acceptance criteria.**

- `session.json` carries all R11.3 fields and a `status` from the R11.4
  vocabulary; an out-of-vocabulary status is rejected (AC9).
- Updates are atomic; a crash mid-write never leaves an unreadable file
  (supports AC27 reconstruction).
- `is_complete` returns true only when every R11.6 condition holds (AC9).
- `shellcheck` clean.

---

## Milestone B8 — File-based coordination protocol (request/result)

**Description.** Implement the deterministic, file-based host↔container
coordination through `bootstrap/` only — never a host socket, FIFO, or nested
Podman (R8.7–R8.13, AC27).

- The agent requests a gate by atomically writing
  `bootstrap/build.request.<id>.json` (`.tmp` + rename) (R8.9). The host writes
  the matching `bootstrap/build.result.<id>.json` and `bootstrap/build.log`
  (R8.7).
- `request_id` is a monotonically increasing integer; allocated as
  `max(existing request/result ids, session.json) + 1` (R8.8). Request fields:
  `request_id`, `requested_at`, `requested_by`, `containerfile`, `context_dir`,
  `image_tag`, `reason`, `repair_iteration`. Result fields: `request_id`,
  `started_at`, `finished_at`, `exit_code`, `status`, `static_check_status`,
  `build_log_path`, `image_tag`, `error_summary` (R8.8).
- The host processes only final non-`.tmp` files; it rejects malformed, partially
  written, missing-field, non-integer, or stale ids; an id ≤ the last completed id
  is rejected (R8.9). Duplicate requests whose id already has a result are ignored
  (R8.11).
- **Polling, not inotify:** host detects new requests at a fixed interval (default
  `2s`, `AI_NEW_COORDINATION_POLL_INTERVAL` override); the agent polls for its
  result at the same default. Polling is deterministic across bind mounts,
  disposal, and resume/crash recovery (R8.10).
- Validate no build is already running for the project; set status
  `quality-gate-running` before running the gate (R8.11).

**Files to change / create.**

- `lib/coordination.sh` — `next_request_id`, `validate_request`, `poll_requests`,
  `write_result` (atomic), `request_already_completed`.
- `bin/ai-new` — supervisor loop polling for requests during a session.

**Acceptance criteria.**

- A numbered `build.request.<id>.json` / `build.result.<id>.json` pair is
  reconstructable on resume; duplicate ids do not trigger duplicate builds;
  request files are written atomically via `.tmp` + rename (AC27).
- Malformed/partial/missing-field/non-integer/stale ids and ids ≤ last-completed
  are rejected (R8.9).
- Poll interval honours `AI_NEW_COORDINATION_POLL_INTERVAL`, default `2s` (R8.10).
- `shellcheck` clean.

---

## Milestone B9 — Host-side quality gate: static check, trial build, timeout

**Description.** Run the quality gate on the host in response to a validated
request, reconciled with the no-host-socket posture (R8.1–R8.6, R17, R18, R20).

- **Static check (R8.6, advisory):** preference order Podman-native parse/check →
  Buildah parse/check → `hadolint` → none. No tool → record
  `static_check=skipped` and proceed; a failure → `static_check=failed` with
  detail in `bootstrap/static-check.log` (or `build.log`), and does **not** alone
  produce `quality-gate-failed` unless the trial build also fails or cannot start.
- **Trial build (R8.1, R8.2, R17.1):** runs in the host `ai-new` process — never
  nested — via `podman build` of the generated `image/Containerfile`, with output
  captured to `bootstrap/build.log` (R17.4). Required by default; skipped by
  `AI_NEW_SKIP_TRIAL_BUILD=1` / `--skip-trial-build` (R8.2).
- **Timeout (R18):** `AI_NEW_BUILD_TIMEOUT` accepts `timeout(1)` syntax, defaults
  to `30m`, enforced via `timeout --foreground "$AI_NEW_BUILD_TIMEOUT"`. On
  expiry → status `quality-gate-timeout`, partial `build.log` preserved, session
  resumable (R18.2–R18.4).
- **Trial-image naming (R20):** tag `localhost/ai-new/<slug>:trial` (B4
  sanitizer); on success MAY also tag `localhost/ai-project/<slug>:latest`; leave
  image in local storage as a warm cache; record the tag in `session.json`.
- **Status mapping (R8.3):** pass → eligible for `complete`; skipped →
  `generated-unvalidated` (never `complete`); timeout → `quality-gate-timeout`;
  fail after repairs → `quality-gate-failed`. Write result files + update
  `session.json` (R8.11).

**Files to change / create.**

- `lib/quality_gate.sh` — `static_check`, `trial_build` (timeout-wrapped),
  `tag_trial_image`, `map_gate_status`.
- `bin/ai-new` — invoke the gate from the supervisor loop on a validated request.

**Acceptance criteria.**

- The gate runs static check where available, trial `podman build`, timeout
  handling, and build-log capture; status is `complete` on pass,
  `generated-unvalidated` when skipped, `quality-gate-timeout` on timeout,
  `quality-gate-failed` on persistent failure (AC12).
- `AI_NEW_SKIP_TRIAL_BUILD=1` / `--skip-trial-build` skips and yields
  `generated-unvalidated` (AC13).
- `AI_NEW_BUILD_TIMEOUT` accepts `timeout(1)` syntax, defaults to `30m`, is
  enforced via `timeout --foreground`, and on expiry yields `quality-gate-timeout`
  with preserved partial `build.log` and resumable session (AC23).
- The trial build runs in the host process; the host Podman socket is not in the
  container and no nested-Podman privileges are granted; the container can still
  read `build.log` (AC22).
- The trial image is tagged `localhost/ai-new/<slug>:trial`, optionally also
  `localhost/ai-project/<slug>:latest` on success, left as warm cache, and its tag
  recorded in `session.json` (AC25).
- `shellcheck` clean.

---

## Milestone B10 — Repair cap & crash/restart reconciliation

**Description.** Bound repair cycles and make resume deterministically reconcile
interrupted state (R8.12, R8.13, R19.8, R20.4–R20.6).

- Repair attempts capped at `3` (`AI_NEW_MAX_REPAIR_ATTEMPTS` override). After the
  final failed cycle → `quality-gate-failed`; the user may later resume explicitly
  and request another cycle (R8.12).
- On `--resume`, perform status reconciliation **before** entering the container
  (R19.8): stale `interviewing` → `interrupted`; stale `quality-gate-running` with
  no complete build log → `quality-gate-timeout` if the configured timeout was
  exceeded else `interrupted`; stale `quality-gate-running` with a captured failure
  log → `quality-gate-failed`; with a captured success marker → `complete`. Append
  a note to `session.md` explaining previous status, why stale, and the
  replacement.
- File-based interrupted-request reconstruction (R8.13): a `build.request.<id>.json`
  with no matching result and no active lock/build process is treated as
  interrupted and reconciled per R19.8.
- Resume honours `selected_agent` and the pinned `bootstrap/agent.env` and NEVER
  re-prompts for agent selection (R20.4); resume fails clearly if the recorded
  agent is no longer represented by the pinned file (R20.5).

**Files to change / create.**

- `lib/reconcile.sh` — `reconcile_on_resume`, `interrupted_requests`,
  `apply_status_replacement` (writes `session.json`, appends `session.md`).
- `bin/ai-new` — enforce repair cap; run reconciliation in the resume path.

**Acceptance criteria.**

- Repair attempts are capped (default `3`, override honoured); after the final
  failed cycle status is `quality-gate-failed` and the user may resume to request
  another cycle (AC12, R8.12).
- On resume, a running status with no live process is reconciled per R19.8 and the
  change is noted in `session.md` (AC24).
- An interrupted `build.request.<id>.json` with no result and no active lock is
  reconciled, not silently rebuilt (AC27, R8.13).
- Resume honours the recorded `selected_agent`, never re-prompts, and fails
  clearly if the pinned agent is absent (AC26, R20.4, R20.5).
- `shellcheck` clean.
