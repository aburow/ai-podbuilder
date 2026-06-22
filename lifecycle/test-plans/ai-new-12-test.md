---
title: 'ai-new: Agent-Primed Bootstrap Container — Test Plan'
type: plan-test
status: draft
lineage: ai-new
parent: lifecycle/requirements/ai-new-9.md
created: "2026-06-22T00:00:00+10:00"
priority: normal
assignees:
    - role: test-developer
      who: agent
---

# ai-new: Agent-Primed Bootstrap Container — Test Plan

This plan defines integration tests that verify the behaviour specified by the
backend plan (`ai-new-10-be.md`) and frontend plan (`ai-new-11-fe.md`) against the
requirement's acceptance criteria (AC1–AC28) and binding defaults (D1–D4). Tests
live under `tests/`; each milestone maps to one or more AC IDs.

Testing approach and constraints:

- Tests are runnable on Bazzite/Fedora with rootless Podman (R16.3) but MUST
  isolate from the user's real environment: every test sets `CODEX_JAILS_DIR` to a
  temp dir, never touches `$HOME`, and cleans up containers/images it creates.
- **Fast vs slow tiers.** Pure-logic tests (registry parsing/hashing, slug
  sanitizer, session-state, collision/resume dispatch, coordination-protocol
  validation, lock/reconciliation) run with **no Podman** by stubbing `podman` on
  `PATH`. Container/build tests (launch posture, trial build, timeout) are tagged
  `slow` and may be skipped where Podman is unavailable, recording the skip
  explicitly (never a silent pass).
- The bootstrap **agent** is mocked: a fake agent CLI scripted to emit interview
  artifacts, write `session.*`, and drive the coordination protocol, so end-to-end
  flows are deterministic without a live LLM.
- Security assertions are first-class: a hostile registry value MUST NOT execute,
  and the bootstrap container MUST NOT receive the host Podman socket or
  nested-Podman privileges.
- Each test asserts exit codes and message content, not just side effects.

---

## Milestone T1 — Command surface, help & flag handling

**Description.** Verify the CLI entry points, help, and v1 flag surface.

**Tests / files.**

- `tests/test_help_and_flags.sh` — `ai-new -h` and `/start-here.sh -h` print
  usage and exit zero; deferred `--force` / `--refresh-agent-registry` print a
  "deferred beyond v1" message and exit non-zero.
- Podman-unavailable path: with a stubbed-missing `podman`, `ai-new` exits
  non-zero with a clear message.

**Acceptance criteria.**

- `ai-new -h` and `/start-here.sh -h` print usage (AC19).
- Podman-unavailable and unknown-flag paths exit non-zero with clear messages
  (AC19, R12.1).

---

## Milestone T2 — Registry parsing, adapter validation & security

**Description.** Verify the restricted registry parser, adapter validation, and
the no-execution security guarantee (R13, AC2, AC20).

**Tests / files.**

- `tests/test_registry_parse.sh` — known keys parse; unknown keys ignored;
  multi-value fields (`AGENT_CONFIG_DIRS`, `AGENT_ENV_VARS`) decode from
  colon-separated form into arrays.
- `tests/test_registry_adapter_validation.sh` — unknown `AGENT_INSTALL_ADAPTER`
  fails validation; the v1 fixed set (`npm-global`, `pipx`, `dnf-package`,
  `preinstalled`, `manual`, auth `argv`) validates.
- `tests/test_registry_security.sh` — a registry file whose string field contains
  command substitution / shell metacharacters is parsed as a literal and the
  content is **never executed** (assert a sentinel side-effect file is never
  created); file is never `source`d/`eval`'d.
- `tests/test_list_agents.sh` — `config/agents.d/` defaults expose `codex`,
  `codex`, `gemini`.

**Acceptance criteria.**

- A registry file is parsed key-by-key, never `source`d/`eval`'d; a hostile value
  does not execute; an unknown adapter fails validation; multi-value fields decode
  (AC20).
- `ai-new <name> --agent <unknown>` exits non-zero, names the agent, and lists
  registered agents (AC2).

---

## Milestone T3 — Registry hashing, normalization & pinning

**Description.** Verify deterministic normalization/hashing and pinning durability
(R13.6, R13.10, AC21, AC27).

**Tests / files.**

- `tests/test_registry_hash.sh` — the hash is stable across two independent runs
  for an unchanged normalized file; CRLF/CR vs LF and trailing-whitespace-only
  differences hash identically; comment/key-order changes alter the hash. Cross-
  machine stability is approximated by hashing in two independent processes/temp
  dirs.
- `tests/test_pinning.sh` — `ai-new` copies the selected entry to
  `bootstrap/agent.env` with original path, agent name, version/hash, timestamp;
  after editing/removing the global registry file, resume still reads the pinned
  copy and works unchanged.

**Acceptance criteria.**

- Hash is stable for an unchanged normalized file across runs; normalization-only
  differences hash identically (AC27).
- `ai-new` pins the entry with required metadata; resume works unchanged after the
  global registry is edited or removed (AC21).

---

## Milestone T4 — Scaffold layout, slug sanitizer & collision/resume

**Description.** Verify scaffold creation, the deterministic slug sanitizer, and
status-driven collision/resume handling (R2, R20.1, AC3, AC4, AC27, D2).

**Tests / files.**

- `tests/test_scaffold_layout.sh` — `ai-new <name> --agent codex` (Podman stubbed
  for the launch step) creates the R2.2 layout under
  `$CODEX_JAILS_DIR/projects/<name>/`.
- `tests/test_collision.sh` — bare `ai-new <name>` creates when absent, refuses-
  and-suggests-`--resume` when `session.json` status is non-terminal, and aborts
  without overwriting when terminal (`complete`/`generated-unvalidated`).
- `tests/test_resume_missing_session.sh` — `--resume` with missing/unreadable
  `session.json` fails clearly rather than restarting.
- `tests/test_slug_sanitizer.sh` — deterministic mapping; lowercasing; illegal
  chars → `-`; collapse/trim; empty fails; >63 chars truncates with `-<8-char-hash>`;
  two distinct names colliding on a slug fail closed with name/slug/existing-user
  details (D2).

**Acceptance criteria.**

- Collision handling matches `session.json` status (create / refuse-and-suggest /
  abort) (AC3).
- `--resume` re-enters an incomplete scaffold; missing `session.json` fails
  clearly (AC4).
- The sanitizer is deterministic and fails closed on slug collision (AC27, D2).

---

## Milestone T5 — Bootstrap launch posture & image minimality (slow)

**Description.** Verify the bootstrap container's safety posture and image
minimality (R1.4, R1.5, R3, R14, R15, R17, AC1, AC15, AC17, AC22). Tagged `slow`;
records an explicit skip when Podman is unavailable.

**Tests / files.**

- `tests/test_bootstrap_posture.sh` — inspect the launched bootstrap container:
  rootless, `--userns=keep-id`, network enabled, only the project tree mounted at
  `/project`, `$HOME` = `/project/bootstrap/home`; assert the host Podman socket is
  **absent** and no nested-Podman privileges are present.
- `tests/test_bootstrap_image_minimal.sh` — inspect the bootstrap image: no
  project language stack / build systems / OS packages; only the selected runtime
  present.

**Acceptance criteria.**

- `ai-new <name> --agent <agent>` launches a minimal bootstrap container containing
  no project stack and only the selected runtime (AC1).
- The container is rootless, `--userns=keep-id`, network enabled, only the project
  tree mounted, with `$HOME` = `/project/bootstrap/home` and a shared `/project`
  tree (AC15, AC17).
- The host Podman socket is not present and no nested-Podman privileges are granted
  (AC22).

---

## Milestone T6 — `start-here.sh` resolution, auth gate & agent launch

**Description.** Verify `/start-here.sh` runtime resolution, the pre-interview auth
gate, and agent launch with CWD `/project`, using a mocked agent CLI (R4, R10, D1,
D4, AC5, AC6, AC26).

**Tests / files.**

- `tests/test_start_here_resolution.sh` — selected runtime used; single available
  used when none specified; zero available fails with setup instructions; multiple
  available with none specified fails with guidance to use `--agent` (no chooser);
  on `--resume` it never re-prompts.
- `tests/test_auth_gate.sh` — with the mock auth-check failing, `start-here.sh`
  reports the failure + setup command/path, exits non-zero, and does NOT start the
  interview; with auth passing, the agent is launched with CWD `/project`.
- `tests/test_manual_runtime.sh` — `gemini` as `manual` with a missing command
  reports setup instructions rather than installing (D1).

**Acceptance criteria.**

- `/start-here.sh` resolves the runtime across all four cases, validates auth
  before any interview, and launches the agent with CWD `/project`, without a
  hardcoded questionnaire/self-generation/per-agent logic (AC5).
- Missing/invalid credentials → reported with setup command/path, non-zero exit,
  no interview (AC6).
- A `manual` runtime with a missing command reports setup instructions (AC26, D1).

---

## Milestone T7 — Interview & generated scaffold (mocked agent)

**Description.** Drive the mocked agent through the interview and generation, then
assert the produced scaffold and secret handling (R5, R6, R7, AC7, AC8, AC10,
AC11, AC16).

**Tests / files.**

- `tests/test_interview_coverage.sh` — assert the mock agent (following
  `prompts/bootstrap-prompt.md`) records the R5.2 minimum topic set in `session.md`
  and steers secrets toward runtime mounting.
- `tests/test_generated_scaffold.sh` — assert the produced files: real
  `image/Containerfile`, image dir, `profile.env`, launcher under `launchers/`,
  build/update helper, README with next steps, `.env.example`, `.gitignore`, plus
  `session.md`/`session.json`.
- `tests/test_secret_handling.sh` — `.env.example` holds placeholders only; no
  populated secret files committed/baked; `.gitignore` excludes
  `bootstrap/agent.env.local`, `bootstrap/home/`, any project `.env`, runtime
  secret/cache files.
- `tests/test_conventions_no_username.sh` — generated profile/launcher/config
  derive paths from `$HOME`/`CODEX_JAILS_DIR`; grep finds no hardcoded usernames.
- `tests/test_next_steps.sh` — completion message states bootstrap is done and
  gives the four next steps referencing actual generated paths/commands.

**Acceptance criteria.**

- The interview covers the R5.2 minimum set and steers secrets to runtime mounting
  (AC7).
- The complete minimal scaffold is written (AC8).
- Secret handling and `.gitignore` exclusions are correct (AC10).
- Artifacts follow `ai-agent-podman-sandbox` conventions with no hardcoded
  usernames (AC11).
- The four next steps reference actual paths/commands (AC16).

---

## Milestone T8 — Coordination protocol determinism

**Description.** Verify the file-based request/result protocol (R8.7–R8.13, AC27).
Pure-logic tier; no real build.

**Tests / files.**

- `tests/test_coordination_ids.sh` — `request_id` is allocated as
  `max(existing, session.json) + 1`; an id ≤ last-completed is rejected.
- `tests/test_coordination_atomicity.sh` — requests are written `.tmp` + rename;
  the host processes only final files; malformed/partial/missing-field/non-integer
  requests are rejected.
- `tests/test_coordination_dedupe.sh` — a duplicate request whose id already has a
  result does not trigger a second build.
- `tests/test_coordination_reconstruct.sh` — a `request.<id>`/`result.<id>` pair is
  reconstructable on resume.

**Acceptance criteria.**

- Numbered request/result pairs are reconstructable on resume; duplicate ids do not
  trigger duplicate builds; requests are atomic via `.tmp` + rename; ids ≤
  last-completed are rejected (AC27).

---

## Milestone T9 — Quality gate: static check, build, skip, timeout (slow where building)

**Description.** Verify the host-side gate outcomes and status mapping (R8.1–R8.6,
R17, R18, R20.2–R20.3, AC12, AC13, AC22, AC23, AC25, AC28).

**Tests / files.**

- `tests/test_gate_pass.sh` (slow) — a valid generated `Containerfile` builds on
  the host; status → `complete`; `build.log` captured; the image is tagged
  `localhost/ai-new/<slug>:trial` and optionally
  `localhost/ai-project/<slug>:latest`, left as warm cache, tag recorded in
  `session.json`.
- `tests/test_gate_fail_repair.sh` (slow) — a broken Containerfile fails; status →
  `quality-gate-failed` after the repair cap; the mock agent reads `build.log` and
  performs a repair attempt; repair cap honours `AI_NEW_MAX_REPAIR_ATTEMPTS`.
- `tests/test_gate_skip.sh` — `AI_NEW_SKIP_TRIAL_BUILD=1` / `--skip-trial-build`
  yields `generated-unvalidated` with an explicit "build not validated" warning.
- `tests/test_gate_timeout.sh` (slow) — `AI_NEW_BUILD_TIMEOUT` accepts `timeout(1)`
  syntax, defaults to `30m`, is enforced via `timeout --foreground`; on expiry
  status → `quality-gate-timeout`, partial `build.log` preserved, session
  resumable.
- `tests/test_gate_static_check.sh` — static check is advisory: no tool →
  `static_check=skipped` and proceeds; a static failure alone does not produce
  `quality-gate-failed` unless the build also fails/cannot start.
- `tests/test_gate_no_nested_build.sh` — assert the build runs in the host process
  and the bootstrap container neither runs `podman build` nor accesses a host
  socket, yet can read `build.log` (AC22, AC28).

**Acceptance criteria.**

- Gate runs static check, trial build, timeout handling, log capture; status maps
  pass→`complete`, skip→`generated-unvalidated`, timeout→`quality-gate-timeout`,
  persistent fail→`quality-gate-failed`; agent repairs on resume (AC12).
- Skip yields `generated-unvalidated` + warning (AC13).
- Timeout grammar/default/enforcement and resumable timeout state hold (AC23).
- Build runs host-side with no in-container build/socket; container reads
  `build.log` (AC22, AC28).
- Trial-image tagging/warm-cache/recording hold (AC25).

---

## Milestone T10 — Session-state schema & status vocabulary

**Description.** Verify `session.json`/`session.md` contents and the controlled
status vocabulary (R11, AC9).

**Tests / files.**

- `tests/test_session_json_fields.sh` — `session.json` carries all R11.3 fields
  (incl. build-log path and trial-image tag when present, and the pinned
  `agent.env` reference with computed hash); `status` is from the R11.4 vocabulary;
  an out-of-vocabulary status is rejected.
- `tests/test_session_md_content.sh` — `session.md` carries the R11.2 content
  including reconciliation notes.
- `tests/test_completeness.sh` — a scaffold is `complete` only when all R11.6
  conditions hold.

**Acceptance criteria.**

- `session.json` carries all R11.3 fields with a valid status; `session.md` carries
  R11.2 content including reconciliation notes (AC9).

---

## Milestone T11 — Concurrency, stale lock & reconciliation

**Description.** Verify the lock, heartbeat, stale detection, and resume
reconciliation (R8.13, R19, R20.4–R20.6, AC24, AC26, D3).

**Tests / files.**

- `tests/test_lock_active.sh` — a second `ai-new <name> --resume` while a session
  holds an active lock is refused with lock details.
- `tests/test_lock_stale_report.sh` — an uncleanly killed session (dead container
  / expired heartbeat) leaves a lock detectable as stale; `ai-new` reports it and
  offers a safe clear path; non-interactive fails closed and prints the manual
  clear command (D3).
- `tests/test_reconcile_resume.sh` — a running status (`interviewing` /
  `quality-gate-running`) with no live process is reconciled per R19.8 (mapping to
  `interrupted` / `quality-gate-timeout` / `quality-gate-failed` / `complete`) and
  the change is noted in `session.md`.
- `tests/test_resume_agent_pinned.sh` — resume honours the recorded
  `selected_agent` and never re-prompts; resume fails clearly if the pinned agent
  is absent; a pinned-but-uninstallable/unauthenticated runtime causes
  `start-here.sh` to report the runtime/auth problem with setup instructions.

**Acceptance criteria.**

- Active-lock refusal with details; stale-lock report with safe clear path;
  running-status reconciliation per R19.8 noted in `session.md` (AC24).
- Resume honours `selected_agent`, never re-prompts, fails clearly on absent pinned
  agent, and reports runtime/auth problems for an uninstallable pinned runtime
  (AC26).

---

## Milestone T12 — Persistence across disposal & resume

**Description.** Verify generated files and agent config persist across bootstrap
container disposal and resumed sessions (R7.1, R9, AC14).

**Tests / files.**

- `tests/test_persistence.sh` — after the user exits and the bootstrap container is
  removed, generated files under the project tree persist; agent config under
  `/project/bootstrap/home` persists across a simulated bootstrap image rebuild and
  a resumed session.

**Acceptance criteria.**

- Generated files persist after the container is removed; agent config under
  `/project/bootstrap/home` persists across rebuilds and resumed sessions (AC14).
