---
title: 'ai-new: Agent-Primed Bootstrap Container — Frontend (User-Surface) Plan'
type: plan-frontend
status: done
lineage: ai-new
parent: lifecycle/requirements/ai-new-9.md
created: "2026-06-22T00:00:00+10:00"
priority: normal
assignees:
    - role: frontend-developer
      who: agent
---

# ai-new: Agent-Primed Bootstrap Container — Frontend (User-Surface) Plan

This plan covers everything the **user and the bootstrap agent see and interact
with**: the in-container `/start-here.sh` agent-priming launcher, the structured
bootstrap prompt handed to the agent, the agent-authored interview/generation
contract, the generated durable scaffold's user-facing files (README, next steps,
`.env.example`, `.gitignore`, profile/launcher conventions), the in-container
waiting/progress UX during the host-side build, and all help/usage/error copy.

The host-side engine — `ai-new`, registry parsing/pinning, container launch,
coordination protocol, quality gate, lock/heartbeat, session-state writes — is
owned by the **backend plan** (`ai-new-10-be.md`). This plan consumes the contract
files that plan owns: the pinned `bootstrap/agent.env`, `session.json`/`session.md`,
and the `build.request.<id>.json` / `build.result.<id>.json` protocol.

"Frontend" here means the human/agent interface of a CLI tool, not a GUI. The
shared constraints from the backend plan apply (Bash, `set -euo pipefail`, no
hardcoded usernames, `-h`/`--help` everywhere, `shellcheck` clean, registry content
never `eval`'d).

---

## Milestone F1 — `/start-here.sh` skeleton, help & runtime resolution

**Description.** Ship `/start-here.sh` at the filesystem root of the bootstrap
container as the single primary entrypoint the user runs after entering (R4.1,
AC5). It reads runtime metadata **only** from the pinned `bootstrap/agent.env`
and contains no hardcoded questionnaire, no project generation, and no per-agent
install/auth logic beyond the generic adapter contract (R4.2, R13.8).

- Runtime resolution (R4.3, D4): use the runtime selected at `ai-new` time; if
  exactly one is registered/available and none specified, it may use it; zero
  available → fail with setup instructions; multiple available and none specified
  → fail with guidance to rerun with `--agent <agent>`. No interactive
  multi-runtime chooser in v1. On `--resume` it never re-prompts (R4.3, R20.4).
- `-h`/`--help` prints usage; failure paths exit non-zero with a clear message
  (R4.8, AC19).

**Files to change / create.**

- `start-here.sh` (placed at container root by the backend launcher) — shebang,
  `set -euo pipefail`, arg/`--help` parsing, source the pinned `agent.env`
  metadata via the backend's restricted parser (never `source`/`eval`), runtime
  resolution.

**Acceptance criteria.**

- `/start-here.sh` exists at the filesystem root of the bootstrap container
  (AC5).
- It resolves the runtime correctly across selected / single / fail-on-zero /
  fail-on-multiple, and on `--resume` never re-prompts (AC5, AC26).
- It contains no hardcoded questionnaire, does not generate the project, and
  embeds no per-agent logic beyond the adapter contract (AC5).
- `/start-here.sh -h` prints usage and exits zero (AC19).
- `shellcheck start-here.sh` is clean.

---

## Milestone F2 — Authentication validation surface (pre-interview)

**Description.** Before any interview, validate that the selected runtime is
present and can authenticate, via the registry auth-check adapter (R4.4, R10,
AC6).

- Credential source order (R10.2): (1) persisted agent config under the bootstrap
  home (`/project/bootstrap/home`); (2) profile/bootstrap env-file values when the
  runtime uses API keys (`AGENT_ENV_VARS`, sourced from
  `bootstrap/agent.env.local`); (3) an interactive login/setup flow initiated by
  the agent CLI if supported (`AGENT_PROMPT_MODE`).
- Run the `argv` auth-check (e.g. `codex|--version`) through the backend's argv
  wrapper — no shell interpolation of registry content (R13.12).
- On missing/invalid credentials: report the failure clearly, give the required
  setup command or file path, and exit non-zero **without starting the interview**
  (R4.4, R10.4, AC6).
- For a `manual` runtime whose command is missing, report setup instructions
  rather than attempting an install (R13.13, D1).
- Bootstrap-time API keys live in `bootstrap/agent.env.local` (gitignored,
  host-persisted, loaded only for the bootstrap runtime), distinct from the pinned
  `agent.env` and the durable `.env.example` (R10.5).

**Files to change / create.**

- `start-here.sh` — auth-validation step gating the interview; clear
  missing-credential reporting referencing `bootstrap/agent.env.local` and the
  runtime's setup command.

**Acceptance criteria.**

- When credentials are missing or invalid, `start-here.sh` reports the failure and
  the required setup command/path, exits non-zero, and does not start the
  interview (AC6).
- Validation occurs **before** any interview begins (AC5, AC6).
- A `manual` runtime with a missing command reports setup instructions, not an
  install attempt (AC26, D1).
- `shellcheck` clean.

---

## Milestone F3 — Agent launch & structured bootstrap prompt

**Description.** Launch the selected agent with CWD `/project` and hand it the
structured project-bootstrap prompt (R4.5, R4.6, R15.2). The prompt — not a shell
questionnaire — drives the entire interview/generation/repair flow.

- Launch the agent in the project tree (`/project`) using `AGENT_COMMAND` from the
  pinned metadata (R4.5).
- The bootstrap prompt instructs the agent to: interview the user; design the
  container; generate the final durable project files; maintain session state
  (`session.md`/`session.json`, R11); request the host-side quality gate via the
  coordination protocol (R8.7); and interpret quality-gate logs/results for repair
  (R4.6, R8).
- The launcher must not strand the user without guidance; final next-step
  instructions are delegated to the agent, but the launcher guarantees the user is
  never left without direction (R4.7).

**Files to change / create.**

- `start-here.sh` — agent launch with CWD `/project`; pass the bootstrap prompt.
- `prompts/bootstrap-prompt.md` — the structured prompt template (interview →
  design → generate → maintain state → request gate → repair), referencing real
  `bootstrap/` paths and the coordination-protocol contract.

**Acceptance criteria.**

- `start-here.sh` launches the agent with CWD `/project` (AC5).
- The prompt instructs the agent through interview, generation, session-state
  maintenance, gate request, and repair (AC7, AC8, AC28).
- The launcher never exits leaving the user without direction (R4.7).
- `shellcheck` clean.

---

## Milestone F4 — Interview contract (R5.2 coverage & secret steering)

**Description.** Encode in the bootstrap prompt the interview behaviour the agent
must follow (R5, AC7). This is prompt/spec content, not shell logic.

- The agent asks targeted questions, progressively narrowing requirements without
  overwhelming the user, then produces a concrete result (R5.1, R5.3).
- It determines at minimum the full R5.2 set: project purpose; preferred runtime;
  role/profile; language/runtime stack; OS packages; developer tools; package
  managers; build systems; source/project layout; workspace mount strategy;
  persistent-state needs; exposed ports; environment variables; secrets to mount
  vs bake; network assumptions; host-resource needs (GPU/audio/USB/display);
  rootless-friendliness; Podman/Docker/both; whether helper scripts are generated;
  whether README/onboarding docs are generated.
- It explicitly distinguishes secrets to **mount at runtime** from values safe to
  bake, steering secrets toward runtime mounting (R5.4).
- It instructs that the user MUST NOT install project software manually during the
  `ai-new` phase — requirements are captured in the generated Containerfile /
  includes / profile / helper scripts (R5.5).

**Files to change / create.**

- `prompts/bootstrap-prompt.md` — interview section enumerating the R5.2 minimum
  set, follow-up guidance, and secret-steering rules.

**Acceptance criteria.**

- The launched agent conducts an interactive interview covering at least the R5.2
  minimum set, asks follow-ups as needed, and steers secrets toward runtime
  mounting (AC7).
- The prompt forbids manual project-software installation during the `ai-new`
  phase (R5.5).

---

## Milestone F5 — Generated durable scaffold (user-facing files)

**Description.** Specify and template the complete minimal sandbox scaffold the
agent produces, immediately buildable/launchable through the
`ai-agent-podman-sandbox` framework (R6, AC8, AC11). The agent writes the final
files; this milestone provides templates/conventions and the secret-handling
pattern.

- v1 output includes at least (R6.3): the workspace; `image/` dir; the **real
  durable `image/Containerfile`** (the most important output, R6.2); `profile.env`;
  a launch wrapper/path under `launchers/`; a build/update helper; a README with
  next steps; `.env.example`; `.gitignore`.
- Profile/launcher/config artifacts follow `ai-agent-podman-sandbox` conventions
  (profile `.env` shape, `launchers/` wrappers) and derive paths from
  `$HOME`/`CODEX_JAILS_DIR`, never hardcoding usernames (R6.4, AC11).
- Keep real secrets out of VCS and the image: provide `.env.example` (placeholders
  only), not populated secret files (R6.5). `.gitignore` excludes
  `bootstrap/agent.env.local`, `bootstrap/home/`, any project `.env`, and
  runtime-specific secret/cache files (AC10).

**Files to change / create.**

- `templates/Containerfile.durable.tmpl` — durable image template/conventions.
- `templates/profile.env.tmpl`, `templates/launcher.tmpl`,
  `templates/build-update.sh.tmpl` — scaffold conventions.
- `templates/README.tmpl`, `templates/.env.example.tmpl`,
  `templates/.gitignore.tmpl` — user-facing scaffold files (gitignore covers
  AC10 entries).
- `prompts/bootstrap-prompt.md` — generation section enumerating R6.3 outputs and
  the secret/`.gitignore` rules.

**Acceptance criteria.**

- At session end the agent has written a complete minimal scaffold: real
  `image/Containerfile`, image dir, `profile.env`, launch wrapper/path,
  build/update helper, README with next steps, `.env.example`, `.gitignore`, plus
  `bootstrap/session.md` and `bootstrap/session.json` (AC8).
- Secret handling uses the `.env.example`/runtime-mount pattern; no populated
  secret files are baked into the image or committed; `.gitignore` excludes
  `bootstrap/agent.env.local`, `bootstrap/home/`, any project `.env`, and
  runtime-specific secret/cache files (AC10).
- Generated profile/launcher/config artifacts follow `ai-agent-podman-sandbox`
  conventions and derive paths from `$HOME`/`CODEX_JAILS_DIR` (AC11).

---

## Milestone F6 — Build-wait UX & repair loop (in-container)

**Description.** Specify the agent's behaviour while the **host** runs the quality
gate, and on each result (R8.14, R17.3, R28). The agent coordinates only through
files and never runs `podman build` itself.

- On writing `build.request.<id>.json`, the agent tells the user the host-side
  supervisor is running the gate **outside** the container, then enters a waiting
  state (R8.14).
- While waiting it periodically shows concise progress: current `session.json`
  status, `bootstrap/build.log` path, elapsed time, timeout setting; it may tail or
  summarize `build.log` but MUST NOT run `podman build` and MUST NOT require host
  socket access (R8.14, R17.3, AC28).
- On result: success → report the pass and write final next steps; failure → read
  `build.log`, repair files, optionally request another build with the next
  `request_id`; timeout → report and leave the session resumable (R8.14).
- The agent allocates the next `request_id` per R8.8 and writes requests
  atomically (`.tmp` + rename) per R8.9 — consuming the backend coordination
  contract.

**Files to change / create.**

- `prompts/bootstrap-prompt.md` — build-wait/repair section: request emission,
  progress reporting from shared state, result handling, repair-iteration rules.

**Acceptance criteria.**

- During a host-side build the agent reports progress from shared state (status,
  log path, elapsed time, timeout) and does not run `podman build` itself or
  require host socket access; on result it reports success/failure/timeout per
  R8.14 (AC28).
- The agent reads `bootstrap/build.log` for repair and requests subsequent builds
  with the next `request_id` (AC22, AC27).

---

## Milestone F7 — Completion reporting, next steps & session.md narrative

**Description.** Specify the agent's end-of-session reporting: completion state,
quality-gate result, the four next steps, and human-readable session notes (R7,
R8.5, R11.2, AC9, AC16).

- On generation complete the agent states the bootstrap container has finished its
  job and reports the quality-gate result (pass / skipped / timeout / fail) and the
  resulting `session.json` status (R7.2, R8.5).
- Final instructions give the four next steps, referencing **actual generated
  paths/commands** (not placeholders): (1) review the generated files; (2) exit the
  bootstrap container; (3) build the real image from the generated `Containerfile`;
  (4) relaunch into the new project container (R7.3, R7.4, AC16).
- A skipped build (`generated-unvalidated`) must be reported with an explicit
  "build not validated — build manually before trusting it" warning (R8.3, AC13).
- `session.md` records the R11.2 content: interview summary, decisions, unresolved
  questions, generated files, quality-gate result, next recommended action, and any
  reconciliation notes (R11.2, AC9).

**Files to change / create.**

- `prompts/bootstrap-prompt.md` — completion/next-steps/`session.md` section with
  the four-step template and the skipped-build warning.

**Acceptance criteria.**

- On completion the agent states the bootstrap is done and gives the four next
  steps (review, exit, build from the generated `Containerfile`, relaunch),
  referencing actual generated paths/commands (AC16).
- A skipped build yields an explicit "build not validated" warning (AC13).
- `session.md` carries the R11.2 content including any reconciliation notes (AC9).

---

## Milestone F8 — Help, usage & error-message copy across surfaces

**Description.** Provide consistent, actionable help and error copy across all
user-facing surfaces (R1.7, R4.8, R16.2, AC19). This milestone owns the wording;
the backend triggers exits.

- `ai-new -h`/`--help` and `/start-here.sh -h`/`--help` print usage (AC19).
- Clear non-zero-exit messages for: Podman unavailable; image build/pull failure;
  unknown agent runtime (naming the unknown agent and listing registered agents);
  ambiguous resume state; active/stale lock (with the D3 lock details and manual
  clear command) (R1.7, AC2, AC19, AC24, D3).
- The unknown-`--agent` message lists registered agents from `config/agents.d/`
  (AC2).

**Files to change / create.**

- `start-here.sh` — usage/help text and failure-path messages.
- `lib/messages.sh` — shared user-facing message builders consumed by `ai-new`
  and `start-here.sh` (help banners, unknown-agent listing, stale-lock report).

**Acceptance criteria.**

- `ai-new -h` and `/start-here.sh -h` print usage (AC19).
- Failure paths (no Podman, build/pull failure, unknown agent runtime, ambiguous
  resume state, active/stale lock) exit non-zero with a clear message (AC19).
- The unknown-`--agent` message names the agent and lists registered agents (AC2).
- `shellcheck` clean across the user-surface scripts.
