---
title: Merge Updated podman-jail Bug Fixes — Backend Plan
type: plan-backend
status: done
lineage: merge-updated-podman-jail-fixes
parent: lifecycle/requirements/merge-updated-podman-jail-fixes-2.md
---

# Merge Updated podman-jail Bug Fixes — Backend Plan

Reconcile `updated-code/podman-jails/` into the repo-root package. This is a
file-by-file merge of Bash sources (`bin/`, `lib/`, `start-here.sh`), not a
feature build. Per the requirement answers: **updated wins** on conflict (it
has higher test coverage), runtime artifacts are excluded, and `updated-code/`
is deleted after a green suite.

## M1 — Establish the authoritative diff baseline

**Description:** Re-run the diff and freeze the inventory. The requirement's
list is a starting point, not authoritative.

```
diff -rq updated-code/podman-jails . \
  -x .git -x lifecycle -x kaos -x doc -x docs -x updated-code -x .codex
```

Cross-check the package-level extras the requirement did not enumerate:
`updated-code/podman-jails/{CODEX.md,LICENSE,devops/}` — diff each against
repo root and classify (identical → ignore; differ → manual review; root-only →
keep). Record the full classification table inline in this plan before any file
is touched.

**Files to change:** none (analysis only); append the frozen inventory table to
this plan file under an `## Inventory` heading.

**Acceptance criteria:**
- [ ] `diff -rq` output captured and every entry classified as
      merge / add / exclude / keep-local.
- [ ] `CODEX.md`, `LICENSE`, `devops/` explicitly classified (not silently
      dropped).
- [ ] Inventory committed to this plan before M2 begins.

## M2 — Merge backend logic (`lib/`, `bin/`, `start-here.sh`)

**Description:** Overwrite repo-root counterparts with the updated versions
(updated wins). Add the one new library. Reconcile by hand only where a
repo-root file carries local changes absent from the updated tree (none known —
the diff shows no root-only `lib/`/`bin/` logic files beyond the keep-local
launchers).

**Files to change (modified — copy from updated tree):**
- `bin/ai-build`, `bin/ai-launch`, `bin/ai-list`, `bin/ai-new`
- `lib/bootstrap_image.sh`, `lib/common.sh`, `lib/container.sh`,
  `lib/coordination.sh`, `lib/launch.sh`, `lib/policy.sh`, `lib/profile.sh`,
  `lib/quality_gate.sh`, `lib/reconcile.sh`, `lib/scaffold.sh`,
  `lib/session.sh`, `lib/usage.sh`
- `start-here.sh`

**Files to add (new):**
- `lib/durable.sh` (durable project normalize/validate/build-spec for `ai-new`)

**Must NOT touch (keep-local):**
- `bin/extra-terminal`, `bin/launch-*`, `bin/short-launch-*`,
  `bin/update-codex-*`, `launchers/`, `.gitignore`, `.codex/`

**Verify intent (R2) before accepting, not blind-copy:**
- `lib/durable.sh` is referenced by `bin/ai-new` (grep confirms the call site).
- `lib/policy.sh` adds `gui_args` / `GUI_FORWARD` display forwarding.
- `lib/scaffold.sh` adds `.env.example`/`.gitignore` scaffold + bootstrap
  entrypoint refresh.
- `lib/bootstrap_image.sh` agent-specific bootstrap image management.

**Acceptance criteria:**
- [ ] All listed modified files are byte-identical to the updated tree
      (`diff` returns empty for each).
- [ ] `lib/durable.sh` present and sourced/called by `bin/ai-new`.
- [ ] No keep-local path modified or deleted (`git status` shows none).
- [ ] `bash -n` clean on every changed/added `.sh` file.

## M3 — Exclude runtime/user artifacts (with dependency check)

**Description:** Do not import developer runtime output. But first confirm the
package does not treat these paths as fixed dependencies (R2 / answer 3): grep
the merged sources for hard-coded references to `config/slug-index.tsv`,
`profiles/`, and `projects/`. If a script expects the file/dir to exist,
note whether it creates it at runtime (acceptable) vs. requires it committed
(a real dependency — escalate via requirement update).

**Files to change:** none added. Verify absent from the merge:
- `config/slug-index.tsv`
- `profiles/alex.env`, `profiles/dotnet2.env`, `profiles/tester.env`
- `projects/`

**Acceptance criteria:**
- [ ] None of the excluded paths exist in the working tree after merge (or are
      untracked/ignored, never staged).
- [ ] Grep result recorded: each excluded path is runtime-generated, not a
      committed dependency. Any exception escalated, not silently merged.

## M4 — Verify the suite is green

**Description:** Run the full package suite after the merge. The new tests
(owned by the test plan) are part of the suite and must pass.

**Files to change:** none.

**Commands:**
```
tests/run_tests.sh
```

**Acceptance criteria:**
- [ ] `tests/run_tests.sh` exits 0; all tests pass including newly added ones.
- [ ] Spot-check: excluded artifacts absent, keep-local files present.

## M5 — Commit in focused commits

**Description:** Stage by path only — never `git add -A` (it would catch
`updated-code/`, `lifecycle/`, `kaos/`, `doc/`). Group commits by fix area
(durable/ai-new, gui-forwarding/policy, scaffold, bootstrap-image, supporting
libs, docs/templates, tests). Reference the area in each message. Hooks and
signing intact.

**Files to change:** git staging only.

**Acceptance criteria:**
- [ ] Each commit stages an explicit path list; no `-A`.
- [ ] `git status` shows no unintended staged paths.
- [ ] Commit messages reference the fix area (no fabricated defect IDs — answer
      1: describe by area, no defect list exists).
- [ ] Pre-commit hooks and signing not skipped.

## M6 — Delete `updated-code/` staging dir

**Description:** Per answer 2, remove the staging tree after a green suite
(backup exists). Do this as the final, separate commit.

**Files to change:** delete `updated-code/`.

**Acceptance criteria:**
- [ ] `updated-code/` removed and the removal committed separately.
- [ ] Suite still green after removal (no script depended on the staging path).

## Inventory

Frozen from `diff -rq updated-code/podman-jails . -x .git -x lifecycle -x kaos -x doc -x docs -x updated-code -x .codex` on 2026-06-26.

| Path | Classification | Notes |
|---|---|---|
| `CODEX.md` | ignore (identical) | byte-for-byte match |
| `LICENSE` | ignore (identical) | byte-for-byte match |
| `devops/` | ignore (identical) | only `sample.yaml`, byte-for-byte match |
| `README.md` | merge (updated wins) | |
| `bin/ai-build` | merge (updated wins) | |
| `bin/ai-launch` | merge (updated wins) | |
| `bin/ai-list` | merge (updated wins) | |
| `bin/ai-new` | merge (updated wins) | |
| `bin/extra-terminal` | keep-local | root-only launcher |
| `bin/launch-esp32-workspace` | keep-local | root-only launcher |
| `bin/launch-uxplay-builder` | keep-local | root-only launcher |
| `bin/launch-uxplay-workspace` | keep-local | root-only launcher |
| `bin/short-launch-esp32-workspace` | keep-local | root-only launcher |
| `bin/update-codex-esp32-image` | keep-local | root-only launcher |
| `bin/update-codex-uxplay-image` | keep-local | root-only launcher |
| `launchers/` | keep-local | root-only dir |
| `.gitignore` | keep-local | root-only |
| `config/slug-index.tsv` | exclude (runtime artifact) | generated at runtime, not committed |
| `lib/bootstrap_image.sh` | merge (updated wins) | |
| `lib/common.sh` | merge (updated wins) | |
| `lib/container.sh` | merge (updated wins) | |
| `lib/coordination.sh` | merge (updated wins) | |
| `lib/durable.sh` | add (new in updated) | new lib for ai-new durable projects |
| `lib/launch.sh` | merge (updated wins) | |
| `lib/policy.sh` | merge (updated wins) | adds gui_args/GUI_FORWARD |
| `lib/profile.sh` | merge (updated wins) | |
| `lib/quality_gate.sh` | merge (updated wins) | |
| `lib/reconcile.sh` | merge (updated wins) | |
| `lib/scaffold.sh` | merge (updated wins) | adds .env.example/.gitignore scaffold |
| `lib/session.sh` | merge (updated wins) | |
| `lib/usage.sh` | merge (updated wins) | |
| `profiles/alex.env` | exclude (runtime artifact) | developer-local profile |
| `profiles/dotnet2.env` | exclude (runtime artifact) | developer-local profile |
| `profiles/tester.env` | exclude (runtime artifact) | developer-local profile |
| `projects/` | exclude (runtime artifact) | developer runtime output dir |
| `prompts/bootstrap-prompt.md` | merge (updated wins) | |
| `start-here.sh` | merge (updated wins) | |
| `templates/README.tmpl` | merge (updated wins) | |
| `templates/launcher.tmpl` | merge (updated wins) | |
| `templates/profile.env.tmpl` | merge (updated wins) | |
| `tests/10_profile.sh` | merge (updated wins) | |
| `tests/11_ai-build.sh` | merge (updated wins) | |
| `tests/20_safety_policy.sh` | merge (updated wins) | |
| `tests/51_extras.sh` | merge (updated wins) | |
| `tests/53_gui.sh` | add (new in updated) | |
| `tests/61_list.sh` | merge (updated wins) | |
| `tests/90_render.sh` | merge (updated wins) | |
| `tests/test_ai_new_boost.sh` | add (new in updated) | |
| `tests/test_ai_new_durable_contract.sh` | add (new in updated) | |
| `tests/test_bootstrap_image_prefixes.sh` | merge (updated wins) | |
| `tests/test_codex_adapter.sh` | add (new in updated) | |
| `tests/test_coordination_relative_paths.sh` | add (new in updated) | |
| `tests/test_gate_skip.sh` | merge (updated wins) | |
| `tests/test_gemini_adapter.sh` | merge (updated wins) | |
| `tests/test_generated_scaffold.sh` | merge (updated wins) | |
| `tests/test_help_and_flags.sh` | merge (updated wins) | |
| `tests/test_install_failure_message.sh` | merge (updated wins) | |
| `tests/test_install_idempotent_resume.sh` | merge (updated wins) | |
| `tests/test_interview_coverage.sh` | merge (updated wins) | |
| `tests/test_launch_bashrc.sh` | add (new in updated) | |
| `tests/test_launch_entrypoint.sh` | add (new in updated) | |
| `tests/test_manual_runtime.sh` | merge (updated wins) | |
| `tests/test_next_steps.sh` | merge (updated wins) | |
| `tests/test_no_dead_install_code.sh` | merge (updated wins) | |
| `tests/test_prompt_timeout_semantics.sh` | add (new in updated) | |
| `tests/test_resume_refreshes_entrypoint.sh` | add (new in updated) | |
| `tests/test_secret_handling.sh` | merge (updated wins) | |
| `tests/test_session_json_fields.sh` | merge (updated wins) | |
| `tests/test_shell_on_exit.sh` | add (new in updated) | |
| `tests/test_supervisor_cleanup.sh` | add (new in updated) | |

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
