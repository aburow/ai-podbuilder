---
title: AI Agent Podman Sandbox Framework — Frontend (User-Surface) Plan
type: plan-frontend
status: done
lineage: ai-agent-podman-sandbox
parent: lifecycle/requirements/ai-agent-podman-sandbox-5.md
created: "2026-06-22T00:00:00+10:00"
priority: normal
assignees:
    - role: frontend-developer
      who: agent
---

# AI Agent Podman Sandbox Framework — Frontend (User-Surface) Plan

This framework has no GUI. Its "frontend" is the **user-facing surface**: the
terminal UX (help text, the pre-launch policy banner, interactive prompts, and
warnings), the aligned `ai-list` rendering, the desktop / Podman-Desktop launch
integration, and the operator-facing documentation (security model, SELinux
choice, secrets, SSH strategy, teardown). These are the surfaces through which
the user perceives and trusts the safety policy, so clarity and honesty of
presentation are the acceptance bar.

This plan consumes the structured hooks the backend plan
(`ai-agent-podman-sandbox-6-be.md`) exposes — `render_launch_summary`,
`prompt_stale_choice`, the `ai-list` formatter — and owns their rendering. It
does **not** implement container lifecycle logic.

Shared constraints: pure Bash output (no color dependency beyond optional
TTY-gated ANSI), no hardcoded usernames or `/var/home/<user>` paths in any
launcher, `.desktop`, or doc example (R12.2).

---

## Milestone F1 — Usage / help text for every command

**Description.** Provide consistent `-h` / `--help` / no-arg usage output for
`ai-build`, `ai-launch`, `ai-terminal`, and `ai-list` (R3.4, R13.2). Each usage
block names the command, its modes/flags, and a one-line example. `ai-launch`
usage must enumerate modes (`shell`/`bash`, `codex`, `codex`, `builder`) and
all flags (`--yes`/`--non-interactive`, `--recreate`, `--no-recreate`,
`--reset`).

**Files to change / create.**

- `lib/usage.sh` — `usage_ai_build`, `usage_ai_launch`, `usage_ai_terminal`,
  `usage_ai_list`; sourced by each `bin/` command.

**Acceptance criteria.**

- Each command with `-h`, `--help`, or no required arg prints its usage and
  exits zero; an invalid arg prints usage and exits non-zero (R13.2).
- `ai-launch` usage lists all four modes and all five flags, and notes that
  `builder` is privileged/ephemeral and `--yes` means *continue, not recreate*.

---

## Milestone F2 — Pre-launch policy banner

**Description.** Implement `render_launch_summary`, the banner printed before
every launch/attach (R4.8), so the active safety policy is always visible.

Fields: profile, container name, image, workspace path, container `$HOME`, mode,
network mode, SELinux mode, and whether an existing container is being reused.
Builder mode must be visibly flagged as **privileged + ephemeral**. Output is
plain text, aligned label/value pairs; ANSI emphasis only when stdout is a TTY.

**Files to change / create.**

- `lib/render.sh` — `render_launch_summary` consuming the backend's field set.

**Acceptance criteria.**

- The banner shows all R4.8 fields including the reuse flag (AC2-supporting; the
  user can read off the policy before the container starts).
- Builder mode renders an explicit privileged/ephemeral warning line; normal
  modes do not.
- The banner is emitted on every `ai-launch` path (create, reuse, recreate).

---

## Milestone F3 — Stale-image and teardown prompts and warnings

**Description.** Implement the interactive rendering the backend reconciliation
(B6/B7) calls into, plus the non-interactive warning text.

- `prompt_stale_choice` (R4.9): present the three explicit choices — (1) continue
  with existing container, (2) recreate from new image preserving workspace,
  (3) cancel and inspect — read a choice, and return it to the backend. Default
  on empty input in interactive mode must be the **safe** choice (continue), and
  the prompt must spell out that recreate removes-and-rebuilds the container
  while preserving the workspace.
- Non-interactive staleness: emit a clear warn-and-continue message (no prompt)
  (R4.10).
- `--reset` confirmation prompt (R4.11): in interactive mode, confirm before
  stopping a running container; render the message making clear that
  workspace/home/profile/image/secrets are preserved.

**Files to change / create.**

- `lib/render.sh` — `prompt_stale_choice`, `warn_stale_noninteractive`,
  `confirm_reset`.

**Acceptance criteria.**

- Interactive staleness presents exactly three labelled choices; empty input
  selects continue (never recreate) (AC14, R4.10).
- Non-interactive staleness prints a warning and no prompt is shown (AC14).
- The recreate and reset prompts both state explicitly that the workspace is
  preserved (AC14, AC15).

---

## Milestone F4 — `ai-list` aligned rendering and state column

**Description.** Implement the `ai-list` formatter (R10.1) the backend feeds
rows into: name, image, workspace path in aligned columns, plus a persistent-
container state column (none / running / stopped). Column widths adapt to the
longest value; output stays readable when piped (no ANSI when not a TTY).

**Files to change / create.**

- `lib/render.sh` — `render_profile_table` (column-aligned output).

**Acceptance criteria.**

- `ai-list` prints every profile with name, image, workspace aligned into
  columns, plus the container state (AC11).
- Output is column-aligned regardless of differing field lengths and contains no
  ANSI escapes when stdout is not a TTY.

---

## Milestone F5 — Desktop / Podman Desktop launcher integration (manual v1 subset)

**Description.** Ship the manual launcher wrappers and documented `.desktop`
examples (R12; automatic generation is deferred D4).

- `launchers/<name>-<mode>` thin scripts call `ai-launch <name> <mode>` and are
  the recommended desktop / Podman-Desktop entry points (R12.1). They SHOULD pass
  `--non-interactive` so a launcher never hangs behind a hidden prompt (R4.10).
- `.desktop` example entries for `~/.local/share/applications/` launch the
  `launchers/` scripts in a terminal, with KDE (`konsole`) and GNOME (`kgx`)
  variants (R12.2). All paths derive from `$HOME` / `$CODEX_JAILS_DIR` — **no
  hardcoded `/var/home/<user>`** (R12.2).
- Document that persistent containers launched this way are visible/manageable in
  Podman Desktop (start/stop/inspect/remove) (R12.3).

**Files to change / create.**

- `launchers/esp32-codex`, `launchers/uxplay-codex`,
  `launchers/uxplay-builder` (examples).
- `docs/desktop-integration.md` — `.desktop` KDE/GNOME examples + Podman Desktop
  notes, with portable derived paths.

**Acceptance criteria.**

- A `launchers/<name>-<mode>` script invokes `ai-launch <name> <mode>` with
  `--non-interactive` and contains no hardcoded username (R12.1, AC-supporting
  DA1).
- A hand-authored `.desktop` example launches a sandbox via a `launchers/`
  wrapper on KDE with `$HOME`/`$CODEX_JAILS_DIR`-derived paths; the running
  container appears in Podman Desktop (DA1 — documented; manual launchers are v1).
- The docs explicitly state automatic `.desktop` generation is deferred (D4).

---

## Milestone F6 — Operator documentation: security model, SELinux, secrets, SSH, teardown

**Description.** Author the operator-facing docs that make the safety policy and
its escape hatches explicit and selectable.

- **Security model:** the single normal-mode policy (R5), what is *not* mounted
  (R5.2), why `--privileged` is builder-only (R5.3), and the persistence/
  containment rationale (R4.2).
- **SELinux choice (R5.5, R5.6):** document why `label=disable` is the friction-
  free default for mounted dev workspaces on Bazzite, and present `SELINUX_MODE`
  (`disable` | `enforce`) with the stricter `:Z`-only option as an explicit,
  selectable choice — not hidden.
- **Secrets (R7):** `ENV_FILE` usage, expected mode `600`, never committed to
  Git; warn-and-continue when missing.
- **SSH strategy (R8):** host `~/.ssh` never mounted by default; how to generate
  a dedicated in-sandbox `ed25519` key for scoped Git access without exposing the
  host identity.
- **Teardown (R4.11):** `--reset` / `--recreate` as the canonical path; raw
  Podman commands documented only as an escape hatch.
- **Profiles & PATH (R1.3, R2):** how to author a profile, required vs optional
  fields, and persisting `bin/` on `PATH`.

**Files to change / create.**

- `docs/security-model.md`, `docs/selinux.md`, `docs/secrets-and-ssh.md`,
  `docs/teardown.md`, `docs/profiles.md`.
- `README.md` — expand the backend stub into an index linking these docs.

**Acceptance criteria.**

- The SELinux doc presents both modes and shows that a `SELINUX_MODE=enforce`
  profile launches without `label=disable` while the default uses it (AC9 —
  documented and selectable).
- The secrets doc states mode `600`, no-commit, and warn-and-continue-on-missing
  behaviour (AC13).
- The SSH doc gives a concrete dedicated-key generation recipe and states the
  host identity is never exposed by default (R8).
- The teardown doc presents `--reset`/`--recreate` as canonical and lists exactly
  what is preserved (AC15).
- No doc example contains a hardcoded username or `/var/home/<user>` path
  (R12.2).
</content>

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
