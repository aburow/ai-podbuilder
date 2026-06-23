---
title: 'ai-new container: start-here.sh misplaced and non-executable, agent not installed'
type: defect
status: clarifying
lineage: ai-new-container-setup-failures
created: "2026-06-23T14:38:05+10:00"
priority: normal
labels:
    - defect
---

# ai-new container: start-here.sh misplaced and non-executable, agent not installed

## Summary

Three setup failures prevent the ai-new container from functioning: `start-here.sh` is placed in the container root (`/`) instead of the home directory, `start-here.sh` does not have the executable bit set, and no agent (Codex, Codex, or Gemini) is installed. Agent installation is critical to core container functionality.

## Reproduction Steps

1. Build and run the ai-new container.
2. Inspect the filesystem: `find / -name start-here.sh` — file appears at `/start-here.sh` instead of `~/<user>/start-here.sh` or equivalent home path.
3. Check permissions: `ls -la /start-here.sh` — mode does not include execute bit.
4. Check for agent binaries: `which codex`, `which codex`, `which gemini` — all return not found.

## Expected Behaviour

- `start-here.sh` is placed in the container user's home directory (e.g. `/root/start-here.sh` or `/home/<user>/start-here.sh`).
- `start-here.sh` is executable (`chmod +x`).
- At least one agent (Codex, Codex, or Gemini) is installed and available on `$PATH` inside the container.

## Actual Behaviour

- `start-here.sh` exists at `/start-here.sh` (container root), not the home directory.
- `start-here.sh` is not executable.
- `codex`, `codex`, and `gemini` are all absent; no agent is installed in the container.

## Logs / Output

Not provided
