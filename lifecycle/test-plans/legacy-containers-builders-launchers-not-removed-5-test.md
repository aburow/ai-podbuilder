---
title: Remove Legacy Profile-Specific Containers, Builders, and Launchers — Test Plan
type: plan-test
status: abandoned
lineage: legacy-containers-builders-launchers-not-removed
parent: lifecycle/requirements/legacy-containers-builders-launchers-not-removed-2.md
---

# Test Plan — Retire AC12 & Keep the Suite Green After Removal

Two test-suite jobs: (1) retire the AC12 contract that *requires* the deleted
wrappers, and (2) decouple the profile fixtures from the deleted example
profiles so the rest of the suite keeps passing. `tests/run_tests.sh` discovers
cases via the globs `[0-9]*.sh` and `test_*.sh`, so deleting a test file removes
it from the run automatically — no registry to edit.

---

## Milestone T1 — Retire the AC12 wrapper test

**Description.** Every case in `tests/70_wrappers.sh` asserts a now-deleted
wrapper exists and delegates. All seven wrappers are removed, so the entire file
is obsolete — delete it rather than gutting it case-by-case.

**Files to change.**
- `git rm tests/70_wrappers.sh`

**Acceptance criteria.**
- [ ] `tests/70_wrappers.sh` no longer exists.
- [ ] `bash tests/run_tests.sh` no longer lists the "70_wrappers" suite or any
      `→ ai-launch esp32` / `→ ai-build` wrapper case.
- [ ] No other test sources or references `70_wrappers`.

## Milestone T2 — Decouple profile fixtures from shipped examples (BLOCKER)

**Description.** **Root cause to fix before backend M3 lands.**
`tests/helpers/setup.bash:94` seeds every test's profile fixtures by globbing
`profiles/*.env.example`. When backend M3 deletes
`profiles/esp32.env.example`/`uxplay.env.example`, that glob matches nothing and
~10 suites that call `load_profile esp32` / `ai-launch esp32` (`10_profile`,
`20_safety_policy`, `40_modes`, `80_stale`, `81_reset`, `90_render`,
`11_ai-build`, and any sourcing the seed) fail with "required field unset".

Fix: give the tests their own fixture source independent of shipped product
files. Add a test-owned reference profile under `tests/helpers/fixtures/` (retain
the `esp32` name and field values — `PROFILE_NAME=esp32`,
`CONTAINER_NAME=codex-esp32`, `IMAGE_NAME=codex-esp32-image`, etc. — so the value
assertions in `10_profile.sh`/`90_render.sh` need **no** edits) and repoint the
seed loop at it.

This keeps the esp32 *name* only as internal test plumbing — it is not a shipped
legacy artifact and the requirement's AC greps target removed *script paths*, not
the substring "esp32".

**Files to change.**
- Add `tests/helpers/fixtures/esp32.env.example` (seed copy of the old shipped
  profile, `${CODEX_JAILS_DIR}` placeholders preserved). Add a second generic
  fixture only if a suite needs a second profile.
- `tests/helpers/setup.bash` — change `PROFILES_SRC` (line ~8) to point at
  `tests/helpers/fixtures`, leaving the seed loop (lines ~92–99) otherwise intact.

**Acceptance criteria.**
- [ ] With `profiles/*.env.example` deleted, `setup_test_env` still writes
      `${_TMPDIR}/profiles/esp32.env`.
- [ ] `load_profile esp32` succeeds and `10_profile.sh` value assertions pass
      unchanged.
- [ ] No test sources a file under the production `profiles/` directory.

## Milestone T3 — Add a regression guard against legacy re-introduction

**Description.** Cheap guard so the removed scripts can't silently come back. The
existing `tests/00_static.sh` is the natural home (it already runs static
checks). Add one assertion that none of the removed script paths exist and that
no tracked file under `bin lib docs doc templates README.md` references them.

**Files to change.**
- `tests/00_static.sh` — add a case asserting absence of the ten removed paths
  and zero references via `grep -rI`. (New standalone `tests/8x_*.sh` is
  acceptable if 00_static is kept minimal — prefer extending 00_static to avoid
  a new file.)

**Acceptance criteria.**
- [ ] A test fails if any of the ten removed script paths reappears in the tree.
- [ ] A test fails if `grep -rI <removed-path>` over
      `bin lib tests docs doc templates README.md` finds a reference (AC12 test
      excluded — it's deleted).
- [ ] The guard passes on the post-removal tree.

## Milestone T4 — Full-suite green run

**Description.** Run the complete suite end-to-end after T1–T3 and the backend/
frontend changes to confirm no collateral breakage.

**Files to change.** None (verification).

**Acceptance criteria.**
- [ ] `bash tests/run_tests.sh` exits 0 with no skipped/failed cases attributable
      to the removal.
- [ ] The summary shows the wrapper suite gone and the profile-dependent suites
      still passing.
- [ ] Companion artifact written to `lifecycle/tests/` documenting the fixture
      decoupling and the retired AC12 contract.
