---
title: 'bashrc.default PS1 hardcodes ai-podbuilder hostname instead of using \h'
type: defect
status: done
lineage: ps1-hardcoded-hostname
created: "2026-06-28T00:00:00+10:00"
priority: low
labels:
    - defect
    - ux
---

# bashrc.default PS1 hardcodes ai-podbuilder hostname instead of using \h

## Summary

`config/bashrc.default` hardcoded the literal string `ai-podbuilder` in PS1,
so every container showed the same hostname in the prompt regardless of what
the container was actually named.  The prompt therefore misled the user about
which container they were in.

## Root Cause

`PS1='\[\e[1;32m\]\u@ai-podbuilder\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\]\$ '`

`\h` was not used, so the real container hostname was ignored.

## Fix

Changed `ai-podbuilder` to `\h` in PS1.  Combined with `--hostname` now passed
at launch time (`lib/policy.sh` for durable containers, `lib/launch.sh` for the
bootstrap container), the prompt reflects the actual container name.

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
