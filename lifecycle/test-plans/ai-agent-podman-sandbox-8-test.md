---
title: AI Agent Podman Sandbox Framework — Test Plan
type: plan-test
status: in-development
lineage: ai-agent-podman-sandbox
parent: lifecycle/requirements/ai-agent-podman-sandbox-5.md
created: "2026-06-22T00:00:00+10:00"
priority: normal
assignees:
    - role: test-developer
      who: agent
---

# AI Agent Podman Sandbox Framework — Test Plan

This plan maps every v1 acceptance criterion (AC1–AC15) to executable
integration tests under `tests/`, plus static checks. It covers the backend
engine (`ai-agent-podman-sandbox-6-be.md`) and the user surface
(`ai-agent-podman-sandbox-7-fe.md`). Deferred acceptance (DA1–DA4) is **out of
scope** for v1 test execution; a small forward-looking section records intended
coverage only.

## Test approach and harness

- **Framework:** [`bats-core`](https://github.com/bats-core/bats-core) for shell
  integration tests, or a plain Bash test runner if bats is unavailable — choose
  one and keep it consistent. Tests live under `tests/`.
- **Two test tiers:**
  - **Tier A — dry-run / inspection (no real containers):** the bulk of policy
    coverage. `ai-launch` must support a `DRY_RUN=1` (or `--print-cmd`) mode that
    prints the fully-assembled `podman` argument vector **without executing** it,
    so the safety policy can be asserted on CI/dev machines without rootless
    Podman side effects. *This is a testability requirement on the backend
    plan's B4/B5 — if not already present, add it.*
  - **Tier B — live Podman (gated):** tests that actually create/persist/remove
    containers, gated behind a `PODMAN_LIVE=1` env guard and skipped cleanly when
    Podman is unavailable or not rootless. These validate persistence,
    ephemerality, network, and exec attach for real.
- **Fixtures:** temporary `CODEX_JAILS_DIR` per test (mktemp), seeded with the
  `profiles/*.env.example` reference profiles (esp32, uxplay) and a tiny
  buildable `*-image/Containerfile` so Tier B builds are fast.
- **Isolation:** each test sets its own `CODEX_JAILS_DIR`; Tier B uses unique
  container names and a teardown trap removing any container it created.
- **Companion artifact:** a `lifecycle/tests/` document recording what was built
  and how to run each tier.

---

## Milestone T1 — Static checks and harness bootstrap

**Description.** Stand up the runner and the always-on static gate.

**Files to change / create.**

- `tests/helpers/setup.bash` — temp `CODEX_JAILS_DIR`, seed profiles/images,
  Podman/rootless detection, `skip_unless_live`.
- `tests/00_static.bats` — `shellcheck` over `bin/*` and `lib/*`; assert no
  hardcoded username / `/var/home/` literal in `bin/`, `lib/`, `launchers/`, and
  doc examples (R12.2); assert `set -euo pipefail` present in every `bin/` script
  (R13.1).

**Acceptance criteria.**

- The static suite fails if any `bin/`/`lib/` script is shellcheck-dirty, lacks
  `set -euo pipefail`, or contains a hardcoded username/`/var/home/` path.

---

## Milestone T2 — Profile validation and `ai-build` (AC1)

**Description.** Cover profile loading errors and image build behaviour.

**Files to change / create.**

- `tests/10_profile.bats` — valid load; each missing required field → non-zero
  with field named (R2.6); nonexistent profile → non-zero naming path; unset
  optional arrays usable under `set -u`.
- `tests/11_ai-build.bats` — (Tier B) `ai-build esp32`/`uxplay` build from
  `IMAGE_DIR` and print `POST_BUILD_CHECK` versions; (Tier A) missing profile and
  missing `IMAGE_DIR` → non-zero clear message; assert `ai-build` creates no
  container and no `state/` file (R3.5).

**Acceptance criteria (AC1).**

- Valid profiles build and print tool/library versions; missing profile or image
  dir exits non-zero with a clear message.
- `ai-build` touches no container and writes no framework image-state file.

---

## Milestone T3 — Normal-mode safety policy inspection (AC2)

**Description.** Assert the single authoritative policy via Tier A dry-run and,
when live, via `podman inspect`.

**Files to change / create.**

- `tests/20_safety_policy.bats` — assert the assembled command contains
  `--userns=keep-id`, `--group-add keep-groups`,
  `--security-opt no-new-privileges`, the configured SELinux mode,
  `-e HOME=$CONTAINER_HOME`, and **exactly one** bind mount
  (`$WORKSPACE:/workspace`); assert **absence** of host `$HOME`, `~/.ssh`,
  `~/.gnupg`, `~/.config`, `/`, Docker socket, Podman socket, and `--privileged`.
- (Tier B) `podman inspect` the created container and assert the same.

**Acceptance criteria (AC2).**

- Inspected config shows exactly the required normal-mode flags and the single
  workspace mount, and none of the forbidden mounts or `--privileged`.

---

## Milestone T4 — Persistence and reuse (AC3)

**Description.** Validate that normal-mode containers persist and are reused
(Tier B).

**Files to change / create.**

- `tests/30_persistence.bats` — `ai-launch <profile>` writes a marker file in the
  in-container `$HOME` and in `/workspace`; after exit assert the container still
  exists; a second `ai-launch` reuses it and the markers are present; a
  documented user-initiated removal destroys it; routine exit does not.

**Acceptance criteria (AC3).**

- Container survives routine exit; second launch reuses it with prior state
  intact; only explicit removal destroys it.

---

## Milestone T5 — Modes, builder privilege and ephemerality (AC4, AC5, AC6)

**Description.** Cover the mode set and the privileged/ephemeral builder path.

**Files to change / create.**

- `tests/40_modes.bats` — (Tier A) mode dispatch maps `codex`/`codex`/`bash` to
  the expected in-container command; unknown mode → non-zero + usage.
- `tests/41_builder.bats` — (Tier A) `builder` is the only assembled command
  with `--privileged`, uses the `-builder` name, and includes `--rm`; normal
  modes never include `--privileged`. (Tier B) after a builder session the
  `-builder` container no longer exists while the normal persistent container is
  unaffected.

**Acceptance criteria (AC4, AC5, AC6).**

- AC4: `codex`/`codex`/`bash` start the right agent/shell.
- AC5: only `builder` yields `--privileged`, using the `-builder` name.
- AC6: builder runs with `--rm` and is gone after exit; normal container intact.

---

## Milestone T6 — Network, devices/env/hosts, SELinux choice (AC7, AC8, AC9)

**Description.** Cover network policy, per-profile extras, and SELinux selection.

**Files to change / create.**

- `tests/50_network.bats` — (Tier A) `NETWORK_MODE=none` → `--network none`;
  default → configured default. (Tier B) inside a `none` container an outbound
  connection fails; default has connectivity (AC7).
- `tests/51_extras.bats` — a profile-declared `--device=/dev/ttyUSB0`,
  `EXTRA_HOSTS`, and `EXTRA_ENV` appear in the assembled command exactly as
  declared, and only for the declaring profile (AC8).
- `tests/52_selinux.bats` — `SELINUX_MODE=enforce` profile assembles without
  `label=disable`; default profile assembles with `label=disable` (AC9).

**Acceptance criteria (AC7, AC8, AC9).**

- AC7: `none` is offline, default has network.
- AC8: device/hosts/env appear verbatim and only for the declaring profile.
- AC9: stricter SELinux profile omits `label=disable`; default includes it.

---

## Milestone T7 — `ai-terminal` and `ai-list` (AC10, AC11)

**Description.** Cover the auxiliary commands.

**Files to change / create.**

- `tests/60_terminal.bats` — (Tier B) with a running container `ai-terminal`
  attaches a second shell (assert a command runs in the same container); with no
  running container exits non-zero with a clear message (AC10).
- `tests/61_list.bats` — `ai-list` prints each profile with name/image/workspace
  aligned plus container state; absent profile dir → non-zero (AC11). Assert
  column alignment and no ANSI when piped.

**Acceptance criteria (AC10, AC11).**

- AC10: attach works when running; clear non-zero error when not.
- AC11: aligned listing with state column; missing dir exits non-zero.

---

## Milestone T8 — Compatibility wrappers and secrets (AC12, AC13)

**Description.** Cover legacy wrappers and `ENV_FILE` handling.

**Files to change / create.**

- `tests/70_wrappers.bats` — each retained legacy name
  (`launch-esp32-workspace`, `update-codex-uxplay-image`, `launch-uxplay-builder`,
  `extra-terminal`, …) invokes the corresponding generic command with the right
  fixed args (assert via `DRY_RUN`/intercept) and inherits persistence (AC12).
- `tests/71_secrets.bats` — `ENV_FILE` defined+present (mode `600`) → `--env-file`
  added and a variable is visible in-container (Tier B); defined+missing → warning
  emitted and launch proceeds (AC13); undefined → no secret mount (Tier A).

**Acceptance criteria (AC12, AC13).**

- AC12: every wrapper maps to the right generic command and inherits persistence.
- AC13: present → vars available; missing → warn-and-continue; undefined → no
  host secret mounted.

---

## Milestone T9 — Stale-image reconciliation and teardown (AC14, AC15)

**Description.** Cover reconciliation and `--reset`, the highest-risk safety
flows.

**Files to change / create.**

- `tests/80_stale.bats` — rebuild to change the image ID, then: interactive
  `ai-launch` (simulate TTY/piped choices) offers continue/recreate/cancel;
  `--yes`/`--non-interactive` warns and **continues without recreating**;
  `--recreate` recreates from the current image while workspace + container-home
  content survive (AC14). Assert no `state/` file is consulted (R4.9).
- `tests/81_reset.bats` — `--reset` removes the persistent container and leaves
  workspace, container-home, profile, image dir, and secret env file intact; a
  subsequent launch recreates the container; non-interactive `--reset` without
  `--yes` does not silently stop a running container (AC15).

**Acceptance criteria (AC14, AC15).**

- AC14: interactive offers three choices; `--yes` continues (never recreates);
  `--recreate` recreates preserving workspace.
- AC15: `--reset` preserves all protected paths and recreates on next launch;
  non-interactive `--reset` without `--yes` does not stop a running container.

---

## Milestone T10 — User-surface rendering checks

**Description.** Lightweight assertions on the frontend surfaces that back the
acceptance criteria.

**Files to change / create.**

- `tests/90_render.bats` — pre-launch banner (F2) lists all R4.8 fields incl.
  reuse flag and flags builder as privileged/ephemeral; stale prompt (F3) shows
  three labelled choices with empty-input defaulting to continue; help text (F1)
  for every command exits zero on `-h` and lists modes/flags.

**Acceptance criteria.**

- Banner, prompts, and help text render the fields/choices required by R4.8,
  R4.9, and R3.4, supporting AC2/AC14 from the user's vantage point.

---

## Deferred test coverage (out of v1 scope, recorded only)

- **DA1** desktop `.desktop` + Podman Desktop visibility (manual launchers are
  v1; auto-generation D4).
- **DA2** `ai-doctor` checks + `--cleanup` git-protection (D1).
- **DA3** agent-delegated builder (D6).
- **DA4** clone-to-second-host + self-hosting from sandbox workspace (R13.4 is
  v1-relevant for *editing* the repo from a sandbox; full packaging is D5). A v1
  smoke test MAY assert the commands run with a non-default `CODEX_JAILS_DIR`
  pointing at a sandbox-style workspace path (covered indirectly by the temp-dir
  harness in T1).
</content>
