---
title: 'Agent-suggested project rename during bootstrap creates host directory mismatch'
type: defect
status: done
lineage: bootstrap-agent-rename-breaks-host-directory
created: "2026-06-28T00:00:00+10:00"
priority: high
labels:
    - defect
    - bootstrap
    - scaffold
    - ux
---

# Agent-suggested project rename during bootstrap creates host directory mismatch

## Summary

When the bootstrap agent suggests renaming the project slug mid-session (e.g.
from `kaos-control` to `kaos-control-dev`), the agent rewrites `profile.env`
and all scaffold paths to use the new name. However, `ai-new` already created
the host-side project directory using the original name
(`${AI_PODMAN_JAILS_DIR}/projects/kaos-control/`). The generated scaffold then
references a directory that doesn't exist (`projects/kaos-control-dev/`), and
the framework has no mechanism to detect or correct the mismatch. The user must
manually rename the directory on the host before `ai-build`, `ai-launch`, or
`ai-list` reflect a consistent state.

## Reproduction Steps

1. Run `ai-new kaos-control --agent codex`.
2. During the bootstrap interview, allow or follow the agent's suggestion to
   rename the project to `kaos-control-dev`.
3. Let the bootstrap complete.
4. Observe: the directory on disk remains `projects/kaos-control/` but
   `profile.env` and all generated paths reference `projects/kaos-control-dev/`.
5. `ai-build kaos-control-dev` or `ai-launch kaos-control-dev` will fail because
   `projects/kaos-control-dev/profile.env` doesn't exist.
6. `ai-launch kaos-control` also fails because the profile.env paths point to the
   wrong directory.

## Expected Behaviour

Either:
- The bootstrap prompt prohibits changing the project slug from the one used at
  `ai-new` invocation, and the agent never proposes it; OR
- The framework detects the mismatch after bootstrap and provides a clear error
  with the corrective command (`mv projects/kaos-control projects/kaos-control-dev`).

## Actual Behaviour

- The prompt has no constraint against renaming.
- `validate_launchability_contract` and `reconcile_durable_project` do not check
  whether `PROFILE_NAME` in `profile.env` matches the project directory basename.
- The user sees only generic profile-not-found errors and must diagnose the
  directory mismatch manually.

## Logs / Output

User report: "during one of the consult sessions the agent suggested changing the
name of the instance. This appears to have caused a break as well requiring the
user to rename the project folder." (2026-06-28)

Additionally, the resulting broken state is visible in `import_error_states/cli-errors.txt`:
```
ai-launch kaos-control
[ERROR] Profile not found for 'kaos-control': tried
  .../projects/kaos-control/profile.env and
  .../profiles/kaos-control.env
```

Root causes:
- `prompts/bootstrap-prompt.md` — no constraint on changing `PROJECT_NAME` / `PROFILE_NAME`.
- `lib/durable.sh:validate_launchability_contract` — does not compare `PROFILE_NAME`
  against the project directory basename.

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
