---
title: 'Defect Fix — test_no_dead_install_code.sh: update CODEX_JAILS_DIR assertion'
type: test
status: done
lineage: deprecate-codex-jails-env-vars
parent: lifecycle/defects/deprecate-codex-jails-env-vars-8.md
created: "2026-06-26T00:00:00+10:00"
---

# Defect Fix — test_no_dead_install_code.sh: update CODEX_JAILS_DIR assertion

## What was built

Updated `tests/test_no_dead_install_code.sh` line 45 — the single assertion in
`test_build_context_excludes_project_secrets` that checked for the old
`CODEX_JAILS_DIR` literal was changed to `AI_PODMAN_JAILS_DIR`:

```bash
# before
assert_contains 'local _build_context="${CODEX_JAILS_DIR}/config"' "$src" || return 1

# after
assert_contains 'local _build_context="${AI_PODMAN_JAILS_DIR}/config"' "$src" || return 1
```

## Verification

```
PASS  image build context excludes project secrets
```

All six tests in `test_no_dead_install_code.sh` pass.
