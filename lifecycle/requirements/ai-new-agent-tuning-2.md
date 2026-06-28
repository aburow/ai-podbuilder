---
title: 'AI-New Agent Tuning: Model, Effort, and Approval Policy'
type: requirement
status: done
lineage: ai-new-agent-tuning
created: "2026-06-28T00:00:00+10:00"
priority: normal
parent: lifecycle/ideas/ai-new-agent-tuning.md
---

# AI-New Agent Tuning: Model, Effort, and Approval Policy

## Context

`ai-new` launches the bootstrap agent with no model, effort, or approval-policy
flags, falling back to agent-CLI defaults. Inside the sandboxed bootstrap
container, top-tier models at maximum effort and fully interactive approval are
both unnecessary and expensive. This requirement formalises the tuning contract.

## Requirements

### R1 — Registry schema extension

Three optional keys are added to the agent registry schema parsed by
`lib/registry.sh` and `lib/start-here.sh`:

| Key | Type | Description |
|-----|------|-------------|
| `AGENT_MODEL` | string | Model name to pass as `--model <value>` at launch. Empty = omit flag. |
| `AGENT_EFFORT` | string | Reasoning effort to pass at launch. Empty = omit flag. |
| `AGENT_APPROVAL` | string | Approval/permission policy identifier. Empty = omit flag. |

Unknown values are passed through as-is; the framework does not validate model
names against a registry (agent CLIs reject unknown models themselves).

### R2 — Per-agent flag translation

`_build_launch_argv()` in `lib/start-here.sh` translates registry fields to
CLI flags per agent:

| Agent | `AGENT_MODEL` → | `AGENT_EFFORT` → | `AGENT_APPROVAL` → |
|-------|-----------------|------------------|--------------------|
| `codex` | `--model <value>` | `--reasoning-effort <value>` | `--approval-policy <value>` |
| `claude` | `--model <value>` | (omitted) | `--dangerously-skip-permissions` when value is `skip-permissions` |
| `gemini` | `--model <value>` | (omitted) | (omitted) |
| generic | `--model <value>` | (omitted) | (omitted) |

Empty fields are omitted from the launch argv. Order: model → effort →
approval → prompt.

### R3 — Shipped defaults: codex

`config/agents.d/codex.env` ships with:

```
AGENT_MODEL="gpt-5.4"
AGENT_EFFORT="medium"
AGENT_APPROVAL="full-auto"
```

Rationale: mid-tier model (not mini, not flagship), medium effort, full
auto-approval inside the sandboxed bootstrap container.

### R4 — Shipped defaults: claude (new agent)

`config/agents.d/claude.env` is created as a first-class agent entry:

```
AGENT_NAME="claude"
AGENT_COMMAND="claude"
AGENT_INSTALL_ADAPTER="npm-global"
AGENT_INSTALL_PACKAGE="@anthropic-ai/claude-code"
AGENT_CONFIG_DIRS=".claude"
AGENT_MODEL="claude-sonnet-4-6"
AGENT_EFFORT=""
AGENT_APPROVAL="skip-permissions"
AGENT_AUTH_CHECK_ARGV="claude|--version"
```

Sonnet is the mid-tier Claude model (not haiku, not opus). Claude Code has
no effort-level flag; model selection controls the capability tier.
`skip-permissions` maps to `--dangerously-skip-permissions` and eliminates
in-container approval prompts.

### R5 — Backward compatibility

Registry files without the new keys continue to parse correctly.
`parse_registry_file()` initialises `REG_AGENT_MODEL`, `REG_AGENT_EFFORT`,
and `REG_AGENT_APPROVAL` to empty strings before parsing; missing keys leave
them empty and the flags are omitted at launch.

## Acceptance Criteria

| ID | Criterion |
|----|-----------|
| AC1 | `ai-new myproject --agent codex` launches codex with `--model gpt-5.4 --reasoning-effort medium --approval-policy full-auto`. |
| AC2 | `ai-new myproject --agent claude` launches claude with `--model claude-sonnet-4-6 --dangerously-skip-permissions`. |
| AC3 | A registry file with no `AGENT_MODEL`/`AGENT_EFFORT`/`AGENT_APPROVAL` keys launches the agent with no extra flags (existing behaviour preserved). |
| AC4 | `list_registered_agents` includes `claude`. |
| AC5 | Registry parse tests cover the three new keys. |

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
