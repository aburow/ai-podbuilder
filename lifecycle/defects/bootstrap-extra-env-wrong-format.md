---
title: 'Bootstrap scaffold generates bare KEY=VALUE in EXTRA_ENV/EXTRA_VOLUMES, failing profile validation'
type: defect
status: done
lineage: bootstrap-extra-env-wrong-format
created: "2026-06-28T00:00:00+10:00"
priority: high
labels:
    - defect
    - bootstrap
    - scaffold
---

# Bootstrap scaffold generates bare KEY=VALUE in EXTRA_ENV/EXTRA_VOLUMES, failing profile validation

## Summary

The bootstrap prompt shows `EXTRA_ENV=()` and `EXTRA_VOLUMES=()` as empty-array
placeholders but gives no example of the required populated format.
`lib/profile.sh` requires alternating flag + value pairs: each `EXTRA_ENV` entry
must be `-e` or `--env` followed by `KEY=VALUE`; each `EXTRA_VOLUMES` entry must
be `-v` or `--volume` followed by `HOST:CTR[:opts]`. LLM-generated scaffolds fill
these arrays with bare values, which fail validation immediately on
`ai-build` or `ai-launch`.

## Reproduction Steps

1. Run the `ai-new` bootstrap interview for a project that requires additional
   env vars (e.g. `GOTOOLCHAIN=auto`).
2. Inspect the generated `profile.env` — `EXTRA_ENV` contains bare `KEY=VALUE`
   entries such as `"GOTOOLCHAIN=auto"`.
3. Run `ai-build <profile>`.
4. Observe the validation error.

## Expected Behaviour

Generated `profile.env` uses the correct alternating format:
```bash
EXTRA_ENV=(
  "-e" "GOTOOLCHAIN=auto"
  "-e" "PNPM_HOME=/home/developer/.local/share/pnpm"
)
EXTRA_VOLUMES=(
  "-v" "${HOME}/.codex:/home/developer/.codex:rw"
  "-v" "${HOME}/.claude:/home/developer/.claude:rw"
)
```

## Actual Behaviour

```bash
EXTRA_ENV=(
  "GOTOOLCHAIN=auto"
  "PNPM_HOME=/home/developer/.local/share/pnpm"
)
```

`ai-build` then fails:
```
[ERROR] Profile 'kaos-control-dev' (…/profile.env): EXTRA_ENV entry 0 must be -e/--env, got 'GOTOOLCHAIN=auto'
```

The same issue applies to `EXTRA_VOLUMES`: bare `HOST:CTR` strings instead of
`"-v" "HOST:CTR"` pairs.

## Logs / Output

Source: `import_error_states/cli-errors.txt` and
`import_error_states/kaos-control-dev/profile.env`, recorded 2026-06-28.
Root cause: `prompts/bootstrap-prompt.md:172-173` — prompt only shows empty array
form with no populated-format example; `templates/profile.env.tmpl` has no
instructional comment either.

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
