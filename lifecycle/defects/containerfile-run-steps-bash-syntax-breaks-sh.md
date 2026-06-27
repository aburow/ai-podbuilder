---
title: 'Bootstrap prompt generates bash-specific RUN syntax that fails under /bin/sh'
type: defect
status: done
lineage: containerfile-run-steps-bash-syntax-breaks-sh
created: "2026-06-27T00:00:00+10:00"
priority: high
labels:
    - defect
---

# Bootstrap prompt generates bash-specific RUN syntax that fails under /bin/sh

## Summary

The bootstrap prompt does not instruct agents to use POSIX-compatible shell syntax
in Containerfile `RUN` steps. Agents routinely generate bash-specific constructs
(primarily `[[ ]]` double-bracket conditionals) that fail immediately on the first
trial build because Ubuntu's default shell for `RUN` is `/bin/sh`, which does not
support `[[`. This is a repeat breakpoint that has hit multiple users. Every
occurrence consumes a repair-budget slot and forces an in-flight Codex repair cycle
during the consulting bootstrap process — wasting both user time and API spend.

## Reproduction Steps

1. Run `ai-new <project>` with any agent on a fresh Ubuntu-based target image.
2. Allow the agent to generate a Containerfile that includes account-management,
   conditional logic, or multi-step provisioning in a single `RUN` block.
3. Submit the initial build request.
4. Observe `/bin/sh: 1: [[: not found` in the build log; build exits non-zero.

## Expected Behaviour

The first trial build succeeds without requiring any shell-syntax repair. Containerfile
`RUN` steps use only POSIX-compatible syntax (`[ ]`, `test`, POSIX `if/then/fi`)
so they execute correctly under `/bin/sh` regardless of the base image.

## Actual Behaviour

Agents generate `[[ ]]` conditionals and other bash-isms inside `RUN` steps. The
build fails immediately with `/bin/sh: 1: [[: not found`. A repair iteration is
required to convert the syntax, consuming budget that should be reserved for real
Containerfile defects.

Example from kaos-control build.result.2.json:

```
/bin/sh: 1: [[: not found
/bin/sh: 1: [[: not found
/bin/sh: 1: [[: not found
usermod: user 'developer' does not exist
Error: building at STEP "RUN apt-get update && ... && if [[ -z "${existing_group}" ]]; ...
```

A second repair attempt removed a `SHELL ["/bin/bash", "-c"]` workaround that had
been added, because OCI runtimes ignore the `SHELL` instruction and it generated
its own build warning.

## Impact

- Repeat breakpoint confirmed across multiple user systems during the consulting bootstrap process.
- Each occurrence burns one repair-budget slot on a preventable syntax error.
- Forces an in-flight Codex repair cycle that the user has to wait through.
- If the project already has other real Containerfile defects, the budget is reduced
  before any real repair work begins.

## Proposed Fix

1. **Prompt** (`prompts/bootstrap-prompt.md`): Add an explicit, prominent constraint to
   the Containerfile generation section stating that `RUN` steps execute under `/bin/sh`
   and must use only POSIX-compatible shell syntax. Enumerate the prohibited constructs:
   `[[ ]]`, `(( ))`, `function`, bash arrays, `local` in non-function scope, `source`,
   `$'...'` quoting, `&>>`, `<<<`. Provide a POSIX-safe reference pattern for the
   common account-existence check that has triggered this repeatedly.

2. **Static check** (`lib/quality_gate.sh`): `hadolint` (D-007) catches bash-specific
   syntax in `RUN` steps (rule DL4006 / SC2039). Implementing D-007 would surface this
   class of error as a static-check warning before the trial build runs, giving the
   agent a chance to self-correct without consuming a build slot.

## Logs / Output

Source: kaos-control bootstrap run 2026-06-27; confirmed on multiple prior user systems.
Evidence: `imported_defect_data/build.result.2.json` — exit_code 1, error_summary
contains three `/bin/sh: 1: [[: not found` lines followed by the failing RUN step.
Session note: "Repair attempt 2: converted account-detection conditionals from Bash
double-bracket syntax to portable POSIX test syntax."

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
