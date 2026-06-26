---
title: Merge Updated podman-jail Bug Fixes — Test Plan
type: plan-test
status: draft
lineage: merge-updated-podman-jail-fixes
parent: lifecycle/requirements/merge-updated-podman-jail-fixes-2.md
---

# Merge Updated podman-jail Bug Fixes — Test Plan

The updated tree is itself the source of truth for tests (answer 5: updated
wins, higher coverage). This plan does not author new tests — it reconciles the
suite to match the updated tree and proves it green. Large deletions in
`test_install_*` / `test_no_dead_install_code.sh` are intentional rewrites
(answer 4), not lost coverage.

## M1 — Merge modified tests

**Description:** Overwrite repo-root test files with the updated versions.

**Files to change (copy from updated tree):**
- `tests/10_profile.sh`, `tests/11_ai-build.sh`, `tests/20_safety_policy.sh`,
  `tests/51_extras.sh`, `tests/61_list.sh`, `tests/90_render.sh`
- `tests/test_bootstrap_image_prefixes.sh`, `tests/test_gate_skip.sh`,
  `tests/test_gemini_adapter.sh`, `tests/test_generated_scaffold.sh`,
  `tests/test_help_and_flags.sh`, `tests/test_install_failure_message.sh`,
  `tests/test_install_idempotent_resume.sh`, `tests/test_interview_coverage.sh`,
  `tests/test_manual_runtime.sh`, `tests/test_next_steps.sh`,
  `tests/test_no_dead_install_code.sh`, `tests/test_secret_handling.sh`,
  `tests/test_session_json_fields.sh`

**Acceptance criteria:**
- [ ] Each file byte-identical to the updated tree.
- [ ] For `test_install_failure_message.sh`,
      `test_install_idempotent_resume.sh`, `test_no_dead_install_code.sh`:
      confirm the large `<` removals are rewrites — the behavior they assert
      still has a covering test somewhere in the suite (record the mapping).

## M2 — Add new tests

**Description:** Add the test files that exist only in the updated tree.

**Files to add (copy from updated tree):**
- `tests/53_gui.sh`
- `tests/test_ai_new_boost.sh`, `tests/test_ai_new_durable_contract.sh`,
  `tests/test_codex_adapter.sh`, `tests/test_coordination_relative_paths.sh`,
  `tests/test_launch_bashrc.sh`, `tests/test_launch_entrypoint.sh`,
  `tests/test_prompt_timeout_semantics.sh`,
  `tests/test_resume_refreshes_entrypoint.sh`, `tests/test_shell_on_exit.sh`,
  `tests/test_supervisor_cleanup.sh`

**Acceptance criteria:**
- [ ] All 11 new test files present.
- [ ] `tests/run_tests.sh` discovers each new file (check its discovery glob —
      if it enumerates explicitly rather than globbing, the runner must be
      updated to include them).
- [ ] `bash -n` clean on every new test.

## M3 — Run and confirm green

**Description:** Full-suite run after backend + test merge.

**Files to change:** none.

**Commands:**
```
tests/run_tests.sh
```

**Acceptance criteria:**
- [ ] Suite exits 0; every test passes, including the 11 new files and the
      rewritten install tests.
- [ ] No test references an excluded runtime artifact as committed content; any
      fixture a test needs is created by the test itself, not assumed present.
- [ ] Re-run after `updated-code/` deletion (backend M6) stays green — no test
      reads from the staging path.

## M4 — Coverage sanity check

**Description:** Confirm the merge did not silently drop coverage. Compare the
set of test files before vs. after; every removed assertion in the rewritten
install tests maps to a covering test.

**Files to change:** none; record the mapping in this plan.

**Acceptance criteria:**
- [ ] Test-file count after merge ≥ before, plus the 11 additions accounted for.
- [ ] Mapping table: each deleted install-test assertion → its covering test
      (or explicit confirmation it was redundant per answer 4).
