---
title: 'ai-launch profile-not-found error provides no close-match suggestion'
type: defect
status: done
lineage: ai-launch-no-close-match-suggestion
created: "2026-06-28T00:00:00+10:00"
priority: normal
labels:
    - defect
    - ux
    - cli
---

# ai-launch profile-not-found error provides no close-match suggestion

## Summary

When `ai-launch <name>` cannot find a profile, `load_profile()` in
`lib/profile.sh` dies with the two paths it tried and nothing else. If the user
typed a partial or slightly wrong name, the error gives no hint about available
profiles and forces manual inspection.

## Reproduction Steps

1. Ensure a profile exists for `kaos-control-dev` under
   `${AI_PODMAN_JAILS_DIR}/projects/kaos-control-dev/profile.env`.
2. Run `ai-launch kaos-control`.
3. Observe: `[ERROR] Profile not found for 'kaos-control': tried … and …`
   with no indication that `kaos-control-dev` exists nearby.

## Expected Behaviour

The error message lists any profiles in `projects/` whose names begin with or
closely match the supplied argument, for example:
`Did you mean: kaos-control-dev?`

## Actual Behaviour

```
[ERROR] Profile not found for 'kaos-control': tried
  /home/mrnobody/ai-podman-jails/projects/kaos-control/profile.env and
  /home/mrnobody/ai-podman-jails/profiles/kaos-control.env
```

No suggestion is printed. The user must run `ai-list` separately.

## Logs / Output

Source: `import_error_states/cli-errors.txt`, recorded 2026-06-28.
Root cause: `lib/profile.sh:86` — `_die` call with no candidate scan.

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
