---
title: Remove Legacy Profile-Specific Containers, Builders, and Launchers
type: requirement
status: planning
lineage: legacy-containers-builders-launchers-not-removed
parent: lifecycle/defects/legacy-containers-builders-launchers-not-removed.md
assignees:
    - role: product-owner
      who: agent
---

# Remove Legacy Profile-Specific Containers, Builders, and Launchers

## Problem

The repo predates the generic `ai-build` / `ai-launch` / `ai-terminal` / `ai-list`
commands. From that earlier era it still carries hardcoded, profile-specific
scripts for the `esp32` and `uxplay` projects. They are thin wrappers that just
forward to the generic commands (e.g. `launch-esp32-workspace` → `ai-launch esp32`),
so they add no capability — only clutter and ambiguity about which entrypoint is
authoritative. They remain in the working tree and on GitHub (`aburow/ai-podbuilder`).

Concretely, the suspected legacy artifacts are:

- `launchers/esp32-codex`, `launchers/uxplay-builder`, `launchers/uxplay-codex`
- `bin/launch-esp32-workspace`, `bin/launch-uxplay-workspace`,
  `bin/short-launch-esp32-workspace`, `bin/launch-uxplay-builder`
- `bin/update-codex-esp32-image`, `bin/update-codex-uxplay-image`
- `bin/extra-terminal` (its own comment calls it a "Legacy wrapper")

Complication: `tests/70_wrappers.sh` (labelled **AC12**, "Legacy compatibility
wrappers delegate to the right generic command") *asserts these wrappers must
exist and delegate correctly*. So a prior requirement deliberately introduced
them as a backwards-compatibility contract. Removal therefore reverses an existing
acceptance criterion — it cannot be a silent delete, and the test suite will fail
until it is updated.

## Goals / Non-goals

**Goals**

- Remove the hardcoded esp32/uxplay launcher and wrapper scripts from the working
  tree and from the `main` branch on GitHub.
- Update or remove the contradicting test (`tests/70_wrappers.sh` / AC12) and any
  docs that reference the removed scripts, so the suite passes and docs are accurate.
- Confirm, before deleting, that nothing in the active workflow depends on each
  artifact.

**Non-goals**

- Renaming or changing the generic `ai-*` commands (`ai-build`, `ai-launch`,
  `ai-terminal`, `ai-list`, `ai-new`) — these stay.
- Removing the `esp32`/`uxplay` *example profiles* (`profiles/*.env.example`) or
  profile/docs mentions of esp32/uxplay as illustrative examples — see Open Questions.
- Pruning container *images* from any host or container registry. This requirement
  covers repo/GitHub source artifacts only.
- Rewriting `templates/Containerfile.durable.tmpl` (current, in-use).

## Detailed Requirements

1. **Inventory & classify.** Produce the definitive list of legacy artifacts to
   remove, starting from the set in Problem. An artifact qualifies as legacy if it
   is (a) hardcoded to a specific profile (esp32/uxplay) AND (b) a pure pass-through
   to a generic `ai-*` command with no unique logic.
2. **Verify before delete.** For each artifact, grep the repo for references
   (`bin/`, `lib/`, `tests/`, `docs/`, `doc/`, `templates/`, desktop entries) and
   confirm no current code path or documented workflow requires it. Record the
   finding per artifact.
3. **Remove from the tree.** `git rm` the confirmed-legacy scripts.
4. **Reconcile the AC12 contract.** Because removal contradicts `tests/70_wrappers.sh`,
   update that test (delete the cases for removed wrappers, or delete the file if all
   are removed) so the suite reflects the new intent. Note in the commit that AC12 is
   intentionally retired.
5. **Update documentation.** Fix any docs that reference removed scripts
   (`docs/desktop-integration.md`, `docs/teardown.md`, README, etc.) so no live doc
   points at a deleted file. Generic esp32/uxplay *examples* may stay if still valid.
6. **Push to GitHub.** Commit and push the deletions to `main` so the artifacts are
   gone from GitHub, not just locally.
7. **Keep changes scoped.** Do not touch the generic commands, current libraries, or
   the durable Containerfile template.

## Acceptance Criteria

- [ ] The legacy scripts identified in step 1 no longer exist in the working tree or
      on `origin/main`.
- [ ] `tests/run_tests.sh` passes with no references to removed artifacts (AC12
      cases removed or `tests/70_wrappers.sh` deleted).
- [ ] `grep -rI` across `bin/ lib/ tests/ docs/ doc/ templates/ README.md` returns no
      reference to any removed script path.
- [ ] The generic commands (`ai-build`, `ai-launch`, `ai-terminal`, `ai-list`,
      `ai-new`) and `templates/Containerfile.durable.tmpl` are unchanged.
- [ ] A short note in the PR/commit records which artifacts were removed and why
      AC12 was retired.

## Answers

1. **Keep or drop the esp32/uxplay example profiles?** `profiles/esp32.env.example`, `profiles/uxplay.env.example`, and the esp32/uxplay examples in `docs/profiles.md` are illustrative, not legacy wrappers. Default: keep them. Confirm.

Answer: remove them. There is no need for this any longer as ai-new generates profiles, etc

2. **Is the AC12 backwards-compat contract truly dead?** AC12 was added on purpose. Confirm there are no external desktop entries / muscle-memory dependents before retiring it, or whether a deprecation period is wanted instead of immediate removal.

Answer: Yes, it is truly dead

3. **"Containers" scope.** No legacy *Containerfiles* are committed (only the current durable template). Does "legacy containers" mean stale *images* on the host/registry (out of scope here), or is this purely about the launcher/builder scripts? Confirm the defect is satisfied by source-artifact removal alone.

Answer: removal alone satisfies the requirement

4. **`bin/extra-terminal`** defaults to esp32 but is a generic helper. Remove it, or keep it as a profile-agnostic convenience? Default: remove (self-labelled legacy).

Answer: remove it, there is a replacement
