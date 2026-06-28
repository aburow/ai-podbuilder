---
title: 'AI-New: Agent Model, Effort, and Approval Tuning'
type: idea
status: done
lineage: ai-new-agent-tuning
created: "2026-06-28T00:00:00+10:00"
priority: normal
---

# AI-New: Agent Model, Effort, and Approval Tuning

The `ai-new` bootstrap container launches the selected agent CLI with no
model, effort, or permission-policy flags — the agent defaults apply, which
are typically the highest-capability tier and fully interactive (prompting the
user for every file write or shell command).

Inside the bootstrap container the environment is sandboxed: all writes are
confined to the project directory. Constant approval interruptions are friction
without safety benefit in this context. Similarly, using the top-tier model
at maximum effort for a scaffolding session is unnecessarily expensive; a
mid-tier model at medium effort produces equivalent scaffold quality at lower
cost and latency.

## Goals

1. Add `AGENT_MODEL`, `AGENT_EFFORT`, and `AGENT_APPROVAL` as first-class
   optional registry fields so each agent entry can declare the correct values
   without editing framework scripts.
2. Ship tuned defaults for `codex` (GPT mid-tier, medium effort, full-auto
   approval) and `claude` (Sonnet, skip-permissions).
3. Register `claude` (`@anthropic-ai/claude-code`) as a first-class agent
   alongside `codex` and `gemini`.
4. Wire the new fields into `start-here.sh` `_build_launch_argv()` so they
   are passed as CLI flags at launch time.

## Out of scope

- Dynamic model selection based on task complexity.
- Effort tuning for the durable project container (this only affects the
  bootstrap session).
- Per-user overrides (deferred to a future config layer).
