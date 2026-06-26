---
title: Merge Updated podman-jail Bug Fixes
type: requirement
status: planning
lineage: merge-updated-podman-jail-fixes
parent: lifecycle/ideas/merge-updated-podman-jail-fixes.md
assignees:
    - role: product-owner
      who: agent
---

# Merge Updated podman-jail Bug Fixes

## Problem

A bug-fixed copy of the `podman-jails` package was dropped into
`updated-code/podman-jails/`. The package's authoritative source lives at the
repository root (`bin/`, `lib/`, `start-here.sh`, `templates/`, `prompts/`,
`tests/`, `README.md`). The two trees have diverged and must be reconciled so
the fixes land in the primary package without losing repo-local work or
importing the developer's runtime junk.

The divergence is non-trivial: ~25 existing files differ, one new library
(`lib/durable.sh`) and ~11 new test files were added, and the updated tree also
contains user/runtime artifacts that are **not** fixes. A blind copy would both
delete repo-local files and pollute the package, so a reviewed, file-by-file
merge is required.

## Goals / Non-goals

**Goals**

- Diff `updated-code/podman-jails/` against the repo-root package and enumerate
  every difference.
- Classify each difference as: genuine fix to merge, new file to add, or
  runtime/user artifact to exclude.
- Merge the genuine fixes and new files into the primary package, preserving
  repo-local files that exist only at the root.
- Keep the test suite green after the merge.
- Commit the merge in focused commits referencing the defects/fix areas, with
  correct `git add`/`git commit` per the repo conventions.

**Non-goals**

- No new features beyond what the updated tree already contains.
- Do **not** import runtime/user artifacts: `projects/`, generated
  `profiles/{alex,dotnet2,tester}.env`, and `config/slug-index.tsv`.
- Do not delete repo-local-only files (e.g. `launchers/`, `bin/launch-*`,
  `bin/extra-terminal`, `.codex`, `.gitignore`).
- Do not refactor or "improve" the updated code beyond resolving merge
  conflicts.
- The `updated-code/` staging directory is not part of the shipped package; its
  removal after merge is optional and called out as an open question.

## Detailed Requirements

### R1 — Establish the diff baseline

Produce a complete inventory of `diff -rq updated-code/podman-jails .` (scoped
to package paths, excluding `.git`, `lifecycle`, `kaos`, `doc`, `docs`,
`updated-code`). The known set at time of writing:

- **Modified files (~25):** `README.md`; `bin/ai-build`, `bin/ai-launch`,
  `bin/ai-list`, `bin/ai-new`; `lib/bootstrap_image.sh`, `common.sh`,
  `container.sh`, `coordination.sh`, `launch.sh`, `policy.sh`, `profile.sh`,
  `quality_gate.sh`, `reconcile.sh`, `scaffold.sh`, `session.sh`, `usage.sh`;
  `start-here.sh`; `prompts/bootstrap-prompt.md`; `templates/README.tmpl`,
  `launcher.tmpl`, `profile.env.tmpl`; plus ~18 files under `tests/`.
- **New files to add:** `lib/durable.sh`; new tests including `tests/53_gui.sh`,
  `test_ai_new_boost.sh`, `test_ai_new_durable_contract.sh`,
  `test_codex_adapter.sh`, `test_coordination_relative_paths.sh`,
  `test_launch_bashrc.sh`, `test_launch_entrypoint.sh`,
  `test_prompt_timeout_semantics.sh`, `test_resume_refreshes_entrypoint.sh`,
  `test_shell_on_exit.sh`, `test_supervisor_cleanup.sh`.
- **Exclude (runtime/user artifacts, not fixes):** `projects/`,
  `profiles/alex.env`, `profiles/dotnet2.env`, `profiles/tester.env`,
  `config/slug-index.tsv`.
- **Repo-local only (must survive untouched):** `launchers/`, `bin/launch-*`,
  `bin/extra-terminal`, `bin/short-launch-*`, `bin/update-codex-*`, `.codex`,
  `.gitignore`.

The final inventory is authoritative; this list is the starting point, not a
substitute for re-running the diff.

### R2 — Review and classify each change

For every modified file, review the diff and confirm the change is a deliberate
fix (not an accidental edit or a revert of repo-local work). Notable areas to
verify intent against the originating fix:

- `lib/durable.sh` (new): durable project normalization/validation/build-spec
  for `ai-new`.
- `lib/policy.sh`: GUI/display forwarding (`gui_args`, `GUI_FORWARD`).
- `lib/scaffold.sh`: scaffold of `.env.example`/`.gitignore` and bootstrap
  entrypoint refresh.
- `lib/bootstrap_image.sh`: agent-specific bootstrap image management.
- Test churn where `<` removals are large (`test_install_failure_message.sh`,
  `test_install_idempotent_resume.sh`, `test_no_dead_install_code.sh`) — confirm
  these are intentional rewrites, not lost coverage.

### R3 — Merge mechanics

- Copy modified and new files from the updated tree into their repo-root
  counterparts. Where a repo-root file has local changes not present in the
  updated tree, reconcile by hand rather than overwrite.
- Do not touch repo-local-only paths from R1.
- Do not introduce the excluded artifacts from R1.

### R4 — Verify

- Run the package test suite (`tests/run_tests.sh`) after the merge; it must
  pass. Newly added tests are part of the suite and must pass too.
- Spot-check that excluded artifacts are absent and repo-local files remain.

### R5 — Commit

- Stage only intended paths (`git add` by path, never `git add -A` blindly —
  that would catch `updated-code/`, `lifecycle/`, and artifacts).
- Commit in focused commits per CODEX.md conventions; reference the defect/fix
  area in each message. Do not skip hooks or signing.
- Leave `updated-code/` unstaged/untracked unless its removal is explicitly
  decided (see Open Questions).

## Acceptance Criteria

- [ ] A complete diff inventory exists and every entry is classified
      (merge / add / exclude / keep-local).
- [ ] All genuine fixes from `updated-code/podman-jails/` are present in the
      repo-root package.
- [ ] `lib/durable.sh` and all new test files are added.
- [ ] None of `projects/`, `profiles/{alex,dotnet2,tester}.env`,
      `config/slug-index.tsv` are committed.
- [ ] Repo-local-only files (`launchers/`, `bin/launch-*`, `bin/extra-terminal`,
      etc.) are unchanged and still present.
- [ ] `tests/run_tests.sh` passes after the merge.
- [ ] Changes are committed in focused commits with messages referencing the
      addressed defects/fix areas; hooks and signing intact.
- [ ] `git status` shows no unintended staged paths.

## Answers

1. **Provenance of fixes** — there is no defect list or changelog in the
   updated tree. Which `lifecycle/defects/` entries (if any) should the commit
   messages reference, or do we describe fixes by area?

answer: You will need to work against and update requirements as the user didn't provide full information. We do know that the code is operational and validated as best we can tell.

2. **`updated-code/` disposition** — after a successful merge, should the
   staging directory be deleted in the same change, left untracked, or kept?

answer: deleted - there is a backup that can be brought back in if required

3. **Excluded artifacts confirmation** — confirm `projects/`, the three extra `profiles/*.env`, and `config/slug-index.tsv` are indeed developer runtime output and not intended package content.

answer: they are runtime output. You will need to confirm details to ensure structures aren't fixed dependencies.
   
4. **Large test deletions** — `test_install_*` and `test_no_dead_install_code.sh` lose 90–160 lines each. Confirm these are intentional rewrites and that no required coverage is dropped.

answer: they are intentional

5. **Repo-local divergence** — for any file changed in *both* the updated tree and the repo root since the fork, how should conflicts be resolved (prefer updated, prefer local, or manual merge)?

answer: updated should win as it has a higher level of testing
