---
title: Merge Updated podman-jail Bug Fixes — Test Artifact
type: test
status: done
lineage: merge-updated-podman-jail-fixes
parent: lifecycle/test-plans/merge-updated-podman-jail-fixes-5-test.md
created: "2026-06-26T00:00:00+10:00"
---

# Merge Updated podman-jail Bug Fixes — Test Artifact

Documents the test verification for the `merge-updated-podman-jail-fixes`
lineage. No new test files were authored here — the tests were merged from the
updated tree as part of the backend plan (done at `merge-updated-podman-jail-fixes-3-be.md`).
This artifact records what was verified, the suite result, and the coverage
mapping for the three rewritten install tests.

## M1 — Modified tests present and syntax-clean

All 6 modified test files are present with updated content:

| File | Status |
|------|--------|
| `tests/10_profile.sh` | present, syntax-clean |
| `tests/11_ai-build.sh` | present, syntax-clean |
| `tests/20_safety_policy.sh` | present, syntax-clean |
| `tests/51_extras.sh` | present, syntax-clean |
| `tests/61_list.sh` | present, syntax-clean |
| `tests/90_render.sh` | present, syntax-clean |
| `tests/test_bootstrap_image_prefixes.sh` | present, syntax-clean |
| `tests/test_gate_skip.sh` | present, syntax-clean |
| `tests/test_gemini_adapter.sh` | present, syntax-clean |
| `tests/test_generated_scaffold.sh` | present, syntax-clean |
| `tests/test_help_and_flags.sh` | present, syntax-clean |
| `tests/test_install_failure_message.sh` | present, syntax-clean (rewrite — see M4) |
| `tests/test_install_idempotent_resume.sh` | present, syntax-clean (rewrite — see M4) |
| `tests/test_interview_coverage.sh` | present, syntax-clean |
| `tests/test_manual_runtime.sh` | present, syntax-clean |
| `tests/test_next_steps.sh` | present, syntax-clean |
| `tests/test_no_dead_install_code.sh` | present, syntax-clean (rewrite — see M4) |
| `tests/test_secret_handling.sh` | present, syntax-clean |
| `tests/test_session_json_fields.sh` | present, syntax-clean |

`updated-code/` was removed in backend M6 before this verification; the
working tree is the authoritative source.

## M2 — New tests present and syntax-clean

All 11 new test files (`bash -n` clean):

| File | Tests | Result |
|------|-------|--------|
| `tests/53_gui.sh` | 3 | pass |
| `tests/test_ai_new_boost.sh` | 3 | pass |
| `tests/test_ai_new_durable_contract.sh` | 4 | pass |
| `tests/test_codex_adapter.sh` | 2 | pass |
| `tests/test_coordination_relative_paths.sh` | 2 | pass |
| `tests/test_launch_bashrc.sh` | 2 | pass |
| `tests/test_launch_entrypoint.sh` | 3 | pass |
| `tests/test_prompt_timeout_semantics.sh` | 2 | pass |
| `tests/test_resume_refreshes_entrypoint.sh` | 2 | pass |
| `tests/test_shell_on_exit.sh` | 2 | pass |
| `tests/test_supervisor_cleanup.sh` | 6 | pass |

Runner discovery: `run_tests.sh` uses globs `[0-9]*.sh` and `test_*.sh` — all
11 new files match one of those patterns. No runner update was required.

## M3 — Suite result

```
tests/run_tests.sh   → All test files passed.   Exit 0.
```

75 test files executed. 0 failures. Skips are all Tier B
(`PODMAN_LIVE=1` required — live Podman not available in this environment).

## M4 — Coverage mapping for rewritten install tests

The three tests lost the most lines in the merge. Per requirement answer 4,
these are intentional rewrites tracking the shift from runtime-install (start-here.sh installs the agent on launch) to Containerfile-install (agent installed during `podman build`).

### test_install_failure_message.sh

Old model tested: error path when start-here.sh failed to install via `npm`.  
New model tests: `ensure_bootstrap_image` / `_write_bootstrap_containerfile`
in `lib/bootstrap_image.sh`.

| Deleted assertion (old model) | Covering test (new model) |
|-------------------------------|--------------------------|
| `npm install` error surfaced to user | `test_build_failure_names_agent_and_containerfile` — build exit code propagates with agent name + Containerfile path |
| install step named the agent package | `test_generated_step_contains_registry_package` — Containerfile contains correct `npm install --global <package>` line |

### test_install_idempotent_resume.sh

Old model tested: re-running start-here.sh skipped reinstall when agent binary present.  
New model tests: `ensure_bootstrap_image` skips `podman build` when the
agent-specific image already exists.

| Deleted assertion (old model) | Covering test (new model) |
|-------------------------------|--------------------------|
| second launch skips `npm install` | `test_existing_agent_image_skips_build` — `podman image exists` short-circuits build; `BOOTSTRAP_IMAGE_TAG` set correctly |

### test_no_dead_install_code.sh

Old model tested: guard assertions that the old runtime-install machinery (a
mounted `start-here-lib`, `run_install_adapter` calls in start-here.sh) did
not re-appear after a prior cleanup.

| Deleted assertion (old model) | Covering test (new model) |
|-------------------------------|--------------------------|
| `start-here.sh` contains no `npm install` | `test_start_here_does_not_install_on_launch` — asserts `run_install_adapter` and `npm install` absent from start-here.sh |
| launch does not mount `/start-here-lib` | `test_launch_does_not_mount_host_install_library` — asserts `/start-here-lib` absent from lib/launch.sh |
| build context excluded project secrets | `test_build_context_excludes_project_secrets` — asserts build context is `${CODEX_JAILS_DIR}/config`, not the project dir |
| agent binary installed in Containerfile | `test_agent_is_installed_by_containerfile` — asserts `RUN npm install --global ...` and `command -v <agent>` in generated Containerfile |
| build happens before container launch | `test_ai_new_builds_before_launch` — asserts line number of `ensure_bootstrap_image` < line number of `launch_bootstrap` in bin/ai-new |

All deleted assertions map to a covering test. No coverage gap.

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
