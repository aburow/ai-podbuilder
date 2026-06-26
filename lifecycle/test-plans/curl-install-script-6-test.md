---
title: Curl-Driven Install Script for ai-podbuilder — Test Plan
type: plan-test
status: done
lineage: curl-install-script
parent: lifecycle/requirements/curl-install-script-3.md
---

# Test Plan — Curl-Driven Install Script

Bash integration tests in `tests/`, picked up by `run_tests.sh`'s `test_*.sh`
glob. The installer fetches from GitHub, so tests must run **offline**: stub the
network by pointing the script at a **local tarball** built from the working
tree (via an env override the backend exposes for the fetch source) and at a
throwaway `$HOME` (`mktemp -d`) so no real rc files are touched.

All cases set `HOME="$tmp"` and run the installer with the source override; each
asserts and exits non-zero on failure (matching the existing suite's style).

## Milestone 1 — Test harness & local-source fixture

**Description.** Build a fixture tarball from the repo so fetch logic runs
without network, and a helper that invokes `install.sh` with a sandboxed `$HOME`.

**Files to change.**
- `tests/test_install_script.sh` (new): `setup()` tars the working tree to a
  temp `.tar.gz` and exports the override the backend reads for its fetch source
  (e.g. `AI_PODMAN_INSTALL_TARBALL=<path>`); `run_install()` runs with
  `HOME="$(mktemp -d)"`.

**Acceptance criteria.**
- Fixture builds and a baseline fresh install succeeds offline.
- No test writes outside its temp `$HOME` / install root.

## Milestone 2 — Fresh install & managed-set selection

**Description.** Verify a fresh install lays down only the managed set and makes
commands runnable (AC1, AC2, AC6, AC9).

**Acceptance criteria.**
- Default root `$HOME/ai-podman-jails`; positional arg overrides it (AC2).
- `bin/ lib/ config/ templates/ prompts/` and `profiles/*.example` present;
  `lifecycle/ tests/ doc/ docs/` and example `projects/` **absent** (AC9).
- `test -x` true for every `bin/*` and `start-here.sh` (AC6).
- After `source <env-file>`, all five commands resolve on `PATH` (AC1).

## Milestone 3 — Env file & bashrc guard idempotency

**Description.** Verify the owned env file and the single guarded `~/.bashrc`
line (AC4, AC5, AC10).

**Acceptance criteria.**
- Exactly one `~/.bashrc.d/podbuilder.sh`; exports `AI_PODMAN_JAILS_DIR` + the
  `PATH` entry; contains no `CODEX_JAILS_DIR` (AC4, AC10).
- Second run does not duplicate/corrupt the env file (AC4).
- At most one guarded marked line added to `~/.bashrc`; second run adds nothing;
  `~/.profile`/`~/.zshrc` unmodified (AC5).

## Milestone 4 — Idempotent update & user-data preservation

**Description.** Re-run over an existing install (AC3).

**Acceptance criteria.**
- Pre-seed `projects/demo/` and a hand-authored `profiles/mine.env`; re-run
  exits 0, refreshes managed files, and leaves both untouched (AC3).
- Re-running with no upstream change is safe (no net managed-file churn that
  breaks; exit 0).

## Milestone 5 — Prerequisite & failure safety

**Description.** Prereq gate and partial-failure atomicity (AC7, AC8, R7.2).

**Acceptance criteria.**
- With `podman` shadowed off `PATH`, the script exits non-zero, names the
  missing prerequisite, and the install root is **not** created/written (AC7).
- A simulated mid-fetch failure (corrupt/short tarball) against a prior working
  install leaves its managed files intact; a fresh-install failure leaves no
  install root that looks complete (AC8).
- Every error path exits non-zero with a step-identifying message; no "success"
  printed after a partial install (R7.2).

## Milestone 6 — Invocation forms & legacy migration

**Description.** Stdin vs file invocation and Q6 migration behaviour (R1.1,
R6.1).

**Acceptance criteria.**
- `cat install.sh | bash -s -- <root>` and `bash install.sh <root>` produce
  identical installs; no path depends on `$0`/`BASH_SOURCE` (R1.1).
- `--help` over both forms exits 0 with usage (R1.3).
- With a `CODEX_JAILS_DIR` export pre-seeded in the sandbox `~/.bashrc`: install
  emits exactly one deprecation warning, still produces a working
  `AI_PODMAN_JAILS_DIR`-keyed install, and the migration offer does not block
  the piped run (Q6 a+b+c, R6.1).
- Running a command post-install emits no `CODEX_JAILS_DIR` deprecation warning
  (AC10).

## Milestone 7 — Static lint gate

**Description.** Keep the installer shellcheck-clean alongside the rest of the
suite.

**Acceptance criteria.**
- `shellcheck install.sh` reports no new warnings (extend `00_static.sh`'s lint
  coverage to include `install.sh`).

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
