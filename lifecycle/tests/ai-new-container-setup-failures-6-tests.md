---
title: Fix ai-new bootstrap container setup — Test Artifact
type: test
status: done
lineage: ai-new-container-setup-failures
parent: lifecycle/test-plans/ai-new-container-setup-failures-5-test.md
created: "2026-06-23T00:00:00+10:00"
---

# Fix ai-new Bootstrap Container Setup — Test Artifact

Documents the integration tests built for the `ai-new-container-setup-failures`
lineage, implementing all four test milestones (T1–T4) from the plan at
`lifecycle/test-plans/ai-new-container-setup-failures-5-test.md`.

## What was built

### Test files

| File | Milestone | AC / R | Tier |
|------|-----------|--------|------|
| `tests/test_start_here_location.sh`        | T1 | AC1, B1, R1.3 | A (fast) |
| `tests/test_start_here_executable.sh`      | T1 | AC2, B1, R2.2 | A (fast) |
| `tests/test_start_here_in_container.sh`    | T1 | AC1, AC2      | B (slow) |
| `tests/test_install_adapter_invoked.sh`    | T2 | AC3, R3.2, R3.4 | A (fast) |
| `tests/test_install_idempotent_resume.sh`  | T2 | R3.5, AC3     | A (fast) |
| `tests/test_install_failure_message.sh`    | T2 | R3.4          | A (fast) |
| `tests/test_no_dead_install_code.sh`       | T2 | AC5, B2       | A (fast) |
| `tests/test_install_resolves_in_container.sh` | T2 | AC3        | B (slow) |
| `tests/test_gemini_adapter.sh`             | T3 | AC3, R3.2, R3.4 | A (fast) |
| `tests/test_bootstrap_image_prefixes.sh`   | T3 | AC3, B2       | A+B      |
| `tests/test_spec_reconciled.sh`            | T3 | AC4, B4       | A (fast) |
| `tests/test_bootstrap_setup_e2e.sh`        | T4 | AC6, R4.1     | B (slow) |

Tier A = fast, Podman stubbed or not needed; Tier B = slow, requires `PODMAN_LIVE=1`.

---

## Test coverage map

| AC | Milestone | Test files |
|----|-----------|-----------|
| AC1 — home-dir location | T1, T4 | `test_start_here_location.sh`, `test_start_here_in_container.sh`, `test_bootstrap_setup_e2e.sh` |
| AC2 — executable, prefix-free invocation | T1, T4 | `test_start_here_executable.sh`, `test_start_here_in_container.sh`, `test_bootstrap_setup_e2e.sh` |
| AC3 — pinned agent installs + PATH resolution | T2, T3, T4 | `test_install_adapter_invoked.sh`, `test_gemini_adapter.sh`, `test_install_resolves_in_container.sh`, `test_bootstrap_setup_e2e.sh` |
| AC4 — spec reconciled | T3 | `test_spec_reconciled.sh` |
| AC5 — no dead install code | T2, T3 | `test_no_dead_install_code.sh`, `test_install_adapter_invoked.sh` |
| AC6 — R4.1 integration test passes | T4 | `test_bootstrap_setup_e2e.sh` |

---

## Milestone detail

### T1 — `start-here.sh` location & executability

**`tests/test_start_here_location.sh`** (5 assertions, fast):
- `create_scaffold` places `start-here.sh` at `bootstrap/home/start-here.sh`.
- `start-here.sh` is NOT at the project root.
- `lib/launch.sh` contains no `:/start-here.sh:ro` bind mount.
- `lib/launch.sh` banner references the home-dir path.
- No `--volume :/start-here.sh` remaining in `lib/` or `bin/`.

**`tests/test_start_here_executable.sh`** (4 assertions, fast):
- Scaffold copy is executable even when source mode is 0644.
- Scaffold copy is executable even when source mode is 0444.
- Scaffold copy is executable when source already has execute bit.
- Scaffold copy is a real file, not a symlink.

**`tests/test_start_here_in_container.sh`** (3 assertions, slow):
- `find /project -name start-here.sh` returns the home-dir path.
- `test -x` passes inside the container.
- Invoking the script directly produces no "permission denied".

---

### T2 — Agent install & PATH resolution

**`tests/test_install_adapter_invoked.sh`** (6 assertions, fast):
- Fake `npm` on PATH records argv; `run_install_adapter npm-global @openai/codex ""` calls `npm install -g @openai/codex`.
- Same for `@openai/codex` and `@google/gemini-cli`.
- Package names in registry match expected values (not literals in `lib/`).
- `preinstalled` adapter: npm not called, exits 0.
- `dnf-package` adapter: exits non-zero with actionable root-requirement message.

**`tests/test_install_idempotent_resume.sh`** (3 assertions, fast):
- When command is on PATH, npm is not called and "already present" is logged.
- `--resume` path: same idempotency, npm not called.
- Skip-install log is at `[INFO]` level.

**`tests/test_install_failure_message.sh`** (7 assertions, fast):
- Fake `npm` exits 1: `start-here.sh` exits non-zero.
- Error names the agent, adapter, package, and install command.
- Error is not misreported as an auth failure.
- Same assertions verified for gemini agent.

**`tests/test_no_dead_install_code.sh`** (6 assertions, fast):
- `start-here.sh` sources `/start-here-lib/adapter.sh` and `/start-here-lib/common.sh`.
- `run_install_adapter` is called (not just defined) in `start-here.sh`.
- That call is live code, not a comment.
- `lib/launch.sh` mounts `lib/` as `/start-here-lib` in the container.
- `_install_runtime` call is between `_resolve_runtime` and `_validate_runtime`.

**`tests/test_install_resolves_in_container.sh`** (2 assertions, slow):
- After install step with fake npm, `command -v <agent>` resolves in container.
- Fake npm was invoked (records calls).

---

### T3 — Registry, image prefix & spec reconciliation

**`tests/test_gemini_adapter.sh`** (7 assertions, fast):
- `gemini.env` has `AGENT_INSTALL_ADAPTER=npm-global`.
- `gemini.env` has `AGENT_INSTALL_PACKAGE=@google/gemini-cli`.
- `gemini.env` is not using `manual` adapter.
- `AGENT_COMMAND=gemini`.
- Pinned `agent.env` carries npm-global + @google/gemini-cli.
- `manual` adapter still passes `validate_adapters` (no regression).
- All three shipped agents use a real (non-manual) adapter.

**`tests/test_bootstrap_image_prefixes.sh`** (1 fast + 5 slow):
- Static: `_write_bootstrap_containerfile` includes `NPM_CONFIG_PREFIX`, `PIPX_HOME`, `PIPX_BIN_DIR`, pointing to home-based paths.
- Live (slow): `podman image inspect` verifies these ENV values and that PATH includes the bin dirs.

**`tests/test_spec_reconciled.sh`** (5 assertions, fast):
- `lifecycle/requirements/ai-new-3.md` exists.
- Every line that makes a root-location claim for `start-here.sh` has a nearby supersession note.
- R4.1 specifically has a supersession note.
- No active-looking `:/start-here.sh` bind mounts in the spec.
- The supersession note references the home-dir path.

---

### T4 — End-to-end integration (AC6)

**`tests/test_bootstrap_setup_e2e.sh`** (1 fast + 2 slow):
- Fast: When `PODMAN_LIVE=0`, `skip_unless_live` sets `_SKIP_REASON` — no silent pass.
- Slow (codex): Asserts (a) `start-here.sh` at home, (b) executable, (c) agent on PATH after install.
- Slow (gemini): Same three assertions for the formerly-`manual` gemini case.

Each slow test uses a fake npm that records its argv and drops a stub binary, making the
install step deterministic without network access. The project dir is isolated under
`CODEX_JAILS_DIR` (temp dir); all containers and images created are removed after the test.

---

## Running the tests

Fast tests (no Podman required):
```sh
bash tests/test_start_here_location.sh
bash tests/test_start_here_executable.sh
bash tests/test_install_adapter_invoked.sh
bash tests/test_install_idempotent_resume.sh
bash tests/test_install_failure_message.sh
bash tests/test_no_dead_install_code.sh
bash tests/test_gemini_adapter.sh
bash tests/test_bootstrap_image_prefixes.sh
bash tests/test_spec_reconciled.sh
bash tests/test_bootstrap_setup_e2e.sh
```

Slow tests (require rootless Podman and the bootstrap image):
```sh
PODMAN_LIVE=1 bash tests/test_start_here_in_container.sh
PODMAN_LIVE=1 bash tests/test_install_resolves_in_container.sh
PODMAN_LIVE=1 bash tests/test_bootstrap_image_prefixes.sh
PODMAN_LIVE=1 bash tests/test_bootstrap_setup_e2e.sh
```
