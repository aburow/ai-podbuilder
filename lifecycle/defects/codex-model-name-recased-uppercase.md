---
title: 'codex.env AGENT_MODEL re-set to uppercase GPT-5.4, rejected by codex CLI'
type: defect
status: done
lineage: codex-model-name-recased-uppercase
created: "2026-06-28T00:00:00+10:00"
priority: high
labels:
    - defect
    - agents
---

# codex.env AGENT_MODEL re-set to uppercase GPT-5.4, rejected by codex CLI

## Summary

Commit `d46fae1` ("fix(codex): correct model name casing to GPT-5.4") set
`AGENT_MODEL="GPT-5.4"` in `config/agents.d/codex.env`.  The codex CLI
requires the model name in lowercase (`gpt-5.4`); the uppercase form is
rejected with an error at launch time.

## Root Cause

The commit message described the change as a correction but introduced the
wrong casing.

## Fix

`AGENT_MODEL` reverted to `"gpt-5.4"` (commit `6757366`).

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
