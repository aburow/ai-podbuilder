---
title: 'Fix ai-new bootstrap container setup — Frontend Plan'
type: plan-frontend
status: done
lineage: ai-new-container-setup-failures
parent: lifecycle/requirements/ai-new-container-setup-failures-2.md
created: "2026-06-23T00:00:00+10:00"
priority: high
assignees:
    - role: frontend-developer
      who: agent
---

# Fix ai-new Bootstrap Container Setup — Frontend Plan

This plan covers the **in-container, user-facing launcher** — `start-here.sh`
and the messaging the user sees — which is the surface the requirement's
failures #2 and #3 are felt on. It depends on the backend plan
(`ai-new-container-setup-failures-3-be.md`) for three guarantees: `start-here.sh`
is delivered executable under `$HOME`; the install helper (`run_install_adapter`)
is mounted at `/start-here-lib/adapter.sh` and the bootstrap image exposes
home-based `NPM_CONFIG_PREFIX`/`PIPX_*` + PATH; and the pinned
`bootstrap/agent.env` names a real, installable adapter for every agent.

`start-here.sh` already parses `agent.env` safely (key-by-key, never
`source`/`eval`, lines 64-113), resolves the runtime (118-154), loads
credentials (163-196), validates presence/auth (`_validate_runtime`, 200-255),
and launches the agent (257-328). The missing piece is an **install step**
between resolution and validation, plus messaging that reflects the new home
path. No new per-agent logic and no questionnaire are introduced (R4 from the
ai-new lineage stays intact).

Constraints (inherited): Bash, `set -euo pipefail`; argv arrays only — registry
strings are never interpolated into a shell; `shellcheck` clean per milestone.

---

## Milestone F1 — Install the pinned runtime before validation

**Description.** Add `_install_runtime()` to `start-here.sh`, invoked **after**
`_resolve_runtime` and **before** `_validate_runtime`, so the pinned agent is
present on `$PATH` by the time validation runs (R3.1, R3.3, AC3, AC5). This is
the call site that makes `run_install_adapter` live code.

- Source the backend-mounted helper once: `. /start-here-lib/adapter.sh`
  (which itself requires `common.sh` for `_info`/`_die`; source
  `/start-here-lib/common.sh` first). Guard with a clear error if the mount is
  absent (older image / misconfigured launch) rather than a bare "file not
  found".
- `_install_runtime` logic:
  - If `command -v "$RESOLVED_COMMAND"` already resolves, skip install and log
    that the runtime is already present (idempotent on resume; R3.5).
  - Otherwise call
    `run_install_adapter "$AGENT_INSTALL_ADAPTER" "$AGENT_INSTALL_PACKAGE" "$AGENT_INSTALL_VERSION"`
    using the already-parsed pinned values (lines 71-73). The adapter builds the
    argv internally — `start-here.sh` does not construct package strings (R3.2).
  - Because the backend sets `NPM_CONFIG_PREFIX`/PATH in the image, the install
    lands under `$HOME/.npm-global/bin` which is already on `$PATH`; no PATH
    mutation is needed here. If a future adapter installs elsewhere, re-`hash -r`
    so the new binary resolves in the current shell.
- `--resume` path: install runs the same way (the runtime may have been
  installed in a prior, since-disposed container, but persists under `$HOME`;
  if present it is skipped, if missing it is reinstalled) — never re-prompts for
  the agent (existing behaviour preserved).

**Files to change.**

- `start-here.sh` — add `_install_runtime`, source the mounted helper, call
  `_install_runtime` immediately before `_validate_runtime` (around line 254).

**Acceptance criteria.**

- For `--agent codex|codex|gemini`, launching the bootstrap container and
  reaching `start-here.sh` installs the agent so `command -v <cmd>` resolves
  inside the container before `_validate_runtime` runs (AC3).
- `run_install_adapter` is actually executed on a normal run (verify via its
  `[INFO] Installing via …` log line) — no dead code (AC5).
- Re-running (resume) with the runtime already present skips reinstall and logs
  it (R3.5, idempotent).
- `shellcheck start-here.sh` is clean.

---

## Milestone F2 — Post-install validation and actionable failure messaging

**Description.** Keep `_validate_runtime` as the post-install gate so a failed
install surfaces as a clear error, and make the messaging actionable for the
adapters that cannot fully self-install (R3.4, R3.5, AC3).

- Retain `_validate_runtime` after `_install_runtime`; a still-missing command
  after a supposed install must produce a clear error naming the agent, the
  command, the adapter used, and the install command that was attempted (not the
  current generic "Install it and ensure it is on PATH").
- Rework the `manual`-adapter branch (current lines 204-211): since shipped
  agents no longer use `manual` (gemini moved to `npm-global` per the backend
  plan), this branch becomes the **explicit fallback** for any future `manual`
  agent — it must print concrete setup guidance (what to install, where PATH is)
  and exit non-zero, never silently leave a missing-command error (R3.4).
- On `npm-global`/`pipx` install failure (non-zero from `run_install_adapter`),
  catch it and emit: the adapter, the package, the failing command, and the
  likely cause (e.g. network off, registry unreachable, prefix not writable),
  then exit non-zero. Do not fall through to a confusing auth-check failure.
- Preserve the existing auth-check flow (lines 213-253) unchanged for the
  success path.

**Files to change.**

- `start-here.sh` — `_validate_runtime` messaging; `manual` fallback branch;
  install-failure handling around the `_install_runtime` call.

**Acceptance criteria.**

- A simulated failed install (e.g. stub `npm` exiting non-zero) makes
  `start-here.sh` exit non-zero with a message naming agent, adapter, package,
  and the attempted command — not a downstream auth error (R3.4, R3.5).
- A pinned `manual` agent with a missing command prints actionable setup
  instructions and exits non-zero (no silent missing-command) (R3.4).
- On success, `_validate_runtime` passes and the agent launches as before (AC3).
- `shellcheck start-here.sh` is clean.

---

## Milestone F3 — Path & invocation guidance for the home-directory location

**Description.** Update every path reference and user-facing string in
`start-here.sh` so it is consistent with the new home location, and tell the
user how to invoke the now-executable script (R1.3, R2.3, AC2).

- Update the header comment (lines 2-3) that states the script is "Placed at
  `/start-here.sh`" → `/project/bootstrap/home/start-here.sh`.
- Usage/help text (lines 12-39) and any "re-enter with" guidance: ensure they
  reference the home path and that the script is directly executable
  (`./start-here.sh` from `$HOME`, or by absolute path), without a `bash`
  prefix, since the container drops into `/bin/bash` (R2.3, AC2). Keep the
  `ai-new <name> --resume` host-side guidance.
- Confirm internal paths that are **not** changing remain correct:
  `BOOTSTRAP_DIR=/project/bootstrap`, `AGENT_ENV`, `AGENT_ENV_LOCAL`,
  `PROMPT_FILE`, and the prompt source `/start-here-prompts/bootstrap-prompt.md`
  (the prompts mount is unchanged by the backend plan) — verify none assumed the
  old root location (R1.3).
- The launch banner the user sees on entering the container should state the
  exact command to start the session (`/project/bootstrap/home/start-here.sh`).
  Coordinate with `lib/launch.sh`'s info banner (backend B1) so they agree.

**Files to change.**

- `start-here.sh` — header comment, `_usage` text, launch/next-step banners,
  path-reference audit.

**Acceptance criteria.**

- `start-here.sh --help` describes invocation from the home directory and as a
  directly-executable script (no `bash` prefix) (R2.3, AC2).
- No string in `start-here.sh` refers to `/start-here.sh` at root (R1.3).
- Invoking `"$HOME/start-here.sh"` (or `./start-here.sh` from `$HOME`) inside the
  container runs without permission-denied and without a `bash` prefix (AC2).
- `shellcheck start-here.sh` is clean.

---

## Cross-cutting acceptance (frontend contribution to requirement ACs)

- **AC2** direct, prefix-free invocation works and is documented (F3).
- **AC3** pinned agent is installed and `_validate_runtime` passes (F1, F2).
- **AC5** `run_install_adapter` is invoked on a normal run — no dead code (F1).
- **R3.4/R3.5** failed/`manual` installs produce clear, actionable, non-zero
  errors rather than silent missing-command failures (F2).
