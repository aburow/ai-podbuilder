---
title: 'install.sh does not copy VERSION to install root, breaking ai-pod-doctor'
type: defect
status: done
lineage: install-sh-omits-version-file
created: "2026-06-28T00:00:00+10:00"
priority: high
labels:
    - defect
    - installer
    - integrity
---

# install.sh does not copy VERSION to install root, breaking ai-pod-doctor

## Summary

`install.sh` copies only `bin`, `lib`, `config`, `templates`, and `prompts` into
`${INSTALL_ROOT}`. The top-level `VERSION` file is not included in the managed
set, so after any install or update `${AI_PODMAN_JAILS_DIR}/VERSION` is absent.
`ai-pod-doctor` calls `detect_version()` in `lib/integrity.sh`, which requires
that file and exits with code 3 and the message
`"no version marker at …/VERSION; reinstall required"` when it is missing.

## Reproduction Steps

1. Run `bash install.sh` against any install root.
2. Execute `ai-pod-doctor`.
3. Observe: `ERROR: no version marker at …/VERSION; reinstall required`.

## Expected Behaviour

`ai-pod-doctor` runs successfully. `${AI_PODMAN_JAILS_DIR}/VERSION` contains
the installed release string (e.g. `0.55.0`) after every install or update.

## Actual Behaviour

`ai-pod-doctor` exits 3 immediately. The `VERSION` file is never written by the
installer, so the integrity check cannot proceed.

## Logs / Output

```
mrnobody@temp11:~$ ai-pod-doctor
ERROR: no version marker at /home/mrnobody/ai-podman-jails/VERSION; reinstall required
```

Source: `import_error_states/cli-errors.txt`, recorded 2026-06-28.
Root cause: `install.sh:95` — `managed=(bin lib config templates prompts)` excludes `VERSION`.

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
