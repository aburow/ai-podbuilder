---
title: 'Fix ai-new bootstrap container setup — Test Plan'
type: plan-test
status: done
lineage: ai-new-container-setup-failures
parent: lifecycle/requirements/ai-new-container-setup-failures-2.md
created: "2026-06-23T00:00:00+10:00"
priority: high
assignees:
    - role: test-developer
      who: agent
---

# Fix ai-new Bootstrap Container Setup — Test Plan

This plan defines tests that verify the behaviour specified by the backend plan
(`ai-new-container-setup-failures-3-be.md`) and frontend plan
(`ai-new-container-setup-failures-4-fe.md`) against the requirement's acceptance
criteria (AC1–AC6). Tests live under `tests/`.

Testing approach and constraints (consistent with `ai-new-12-test.md`):

- Every test sets `CODEX_JAILS_DIR` to a temp dir, never touches the real
  `$HOME`, and removes any containers/images it creates.
- **Fast vs slow tiers.** Scaffold/permission/registry/wiring assertions run with
  **no Podman** by stubbing `podman` (and, where needed, `npm`/`pipx`) on
  `PATH`. Tests that actually build/run the bootstrap container are tagged
  `slow` and record an explicit skip (never a silent pass) where Podman is
  unavailable.
- The agent CLI is **mocked** where a real network install would otherwise be
  required: a fake `npm` on `PATH` that "installs" a stub `codex`/`codex`/
  `gemini` into `NPM_CONFIG_PREFIX/bin` makes install + PATH-resolution
  deterministic without a live registry.
- Each test asserts exit codes and message content, not just side effects.

---

## Milestone T1 — `start-here.sh` location & executability (AC1, AC2)

**Description.** Verify failure #1 and #2 are fixed: the script lives under
`$HOME` and is executable independent of the host checkout's mode.

**Tests / files.**

- `tests/test_start_here_location.sh` (fast) — after `ai-new <name> --agent codex`
  (Podman stubbed for the launch step), assert
  `<project>/bootstrap/home/start-here.sh` exists and that no `/start-here.sh`
  root delivery/mount is configured (grep `lib/launch.sh`).
- `tests/test_start_here_executable.sh` (fast) — set the source/canonical
  `start-here.sh` to mode `0644`, create the scaffold, and assert the scaffold
  copy has the execute bit set anyway (mode `0755`/`u+x`) — proving the bit does
  not depend on host mode (R2.2).
- `tests/test_start_here_in_container.sh` (slow) — in a launched bootstrap
  container, assert `find / -name start-here.sh` returns
  `/project/bootstrap/home/start-here.sh` (not root), `test -x` succeeds, and
  invoking `"$HOME/start-here.sh" --help` runs without `bash` and without
  permission-denied.

**Acceptance criteria.**

- `find / -name start-here.sh` resolves under `$HOME`, not `/start-here.sh`
  (AC1).
- The script is executable regardless of host file mode and runs prefix-free
  (AC2).

---

## Milestone T2 — Agent install & PATH resolution per agent (AC3, AC5)

**Description.** Verify failure #3 is fixed: the pinned agent is installed via
the (now live) adapter and resolves on `$PATH`, for each supported agent, and the
install code is no longer dead.

**Tests / files.**

- `tests/test_install_adapter_invoked.sh` (fast) — with a fake `npm` on `PATH`
  that records its argv and drops a stub binary into `NPM_CONFIG_PREFIX/bin`,
  run `start-here.sh`'s install step (or `run_install_adapter` directly) for
  codex/codex/gemini; assert `npm install -g <package>` was called with the
  package from the **pinned** `agent.env` (`@openai/codex`,
  `@openai/codex`, `@google/gemini-cli`) and the command then resolves via
  `command -v` (AC3, R3.2).
- `tests/test_install_idempotent_resume.sh` (fast) — with the command already on
  `PATH`, assert the install step is skipped and logged, and `--resume` never
  re-prompts (R3.5).
- `tests/test_install_failure_message.sh` (fast) — fake `npm` exits non-zero;
  assert `start-here.sh` exits non-zero and the message names agent, adapter,
  package, and attempted command — not a downstream auth error (R3.4).
- `tests/test_no_dead_install_code.sh` (fast) — assert `run_install_adapter` has
  a reachable call site from the launch path (grep `start-here.sh` for the
  sourced helper + call), guarding AC5 against regression.
- `tests/test_install_resolves_in_container.sh` (slow) — full launch with the
  fake `npm`: after `start-here.sh` runs, `command -v <agent>` resolves and
  `_validate_runtime` passes.

**Acceptance criteria.**

- For each `--agent`, the corresponding command resolves via `command -v`/`which`
  and `_validate_runtime` passes (AC3).
- The build/launch path contains no dead install code — the install step is
  reachable and exercised on a normal run (AC5).
- Install failures surface as clear, non-zero, actionable errors (R3.4).

---

## Milestone T3 — Registry, image prefix & spec reconciliation (AC3, AC4, AC5)

**Description.** Verify the backend registry/image changes and the
documentation reconciliation.

**Tests / files.**

- `tests/test_gemini_adapter.sh` (fast) — `config/agents.d/gemini.env` declares
  `npm-global` + `@google/gemini-cli`; pinning gemini produces an `agent.env`
  with those values; `manual` is still accepted by the parser/validator as a
  known adapter (no v1-set regression) (R3.2, R3.4).
- `tests/test_bootstrap_image_prefixes.sh` (slow) — `podman image inspect` the
  bootstrap image shows `NPM_CONFIG_PREFIX`, `PIPX_HOME`/`PIPX_BIN_DIR` under
  `/project/bootstrap/home` and a `PATH` including their `bin/` dirs (AC3
  support — the non-root install can succeed and resolve).
- `tests/test_spec_reconciled.sh` (fast) — assert `lifecycle/requirements/ai-new-3.md`
  no longer presents `/start-here.sh` at root as the current spec without a
  supersession note referencing the home-directory placement (AC4).

**Acceptance criteria.**

- gemini installs via a real adapter like codex/codex; `manual` remains a valid
  (if unused) adapter (AC3).
- The image exposes home-based prefixes + PATH enabling non-root install
  resolution (AC3, AC5).
- `ai-new-3.md` R4.1 (and sibling root references) are annotated/superseded so
  they no longer contradict the home placement (AC4).

---

## Milestone T4 — End-to-end integration test (R4.1, AC6)

**Description.** The requirement's R4.1 integration test: build and run the
bootstrap container and assert all three fixes together. Tagged `slow`; records
an explicit skip when Podman is unavailable.

**Tests / files.**

- `tests/test_bootstrap_setup_e2e.sh` (slow) — with a fake `npm` (or, when a
  network is available, the real package), `ai-new <name> --agent <agent>` builds
  + launches the bootstrap container and asserts, in one run:
  - (a) `start-here.sh` exists under `$HOME` (`/project/bootstrap/home/...`) and
    not at root;
  - (b) it is executable and runs without a `bash` prefix;
  - (c) after `start-here.sh`'s install step, the pinned agent command resolves
    on `$PATH` and `_validate_runtime` passes.
  Repeat for at least codex and gemini (the previously-`manual` case) to prove
  the registry fix end-to-end.

**Acceptance criteria.**

- The integration test asserts (a) home-dir location, (b) executable +
  prefix-free invocation, and (c) pinned-agent PATH resolution, and passes in CI
  (AC6, R4.1).
- The test isolates `CODEX_JAILS_DIR`, mocks the agent install for determinism,
  and cleans up its containers/images; an unavailable-Podman run records an
  explicit skip, never a silent pass.

---

## Coverage map (requirement ACs → milestones)

- **AC1** home-dir location → T1, T4.
- **AC2** executable, prefix-free invocation → T1, T4.
- **AC3** pinned agent installs and resolves on `$PATH` → T2, T3, T4.
- **AC4** `ai-new-3.md` reconciled → T3.
- **AC5** no dead install code; install reachable on a normal run → T2, T3.
- **AC6** R4.1 integration test passes → T4.
