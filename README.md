# AI Agent Podman Sandbox Framework

A rootless-Podman sandbox framework for running AI coding agents in isolated,
persistent containers.

## Layout

```
bin/        Generic commands: ai-build, ai-launch, ai-terminal, ai-list
lib/        Shared sourced libraries (common.sh, profile.sh, policy.sh, …)
profiles/   Per-project profile files (<name>.env)
launchers/  Optional desktop/per-project launcher scripts
```

## PATH setup

Add the `bin/` directory to your shell `PATH`:

```sh
export CODEX_JAILS_DIR="${CODEX_JAILS_DIR:-$HOME/codex-jails}"
export PATH="$CODEX_JAILS_DIR/bin:$PATH"
```

If `CODEX_JAILS_DIR` is unset, each command derives the base directory from its
own location (`BASH_SOURCE`), so the repo is self-hosting from any path.

## Quick start

```sh
# Build an image from a profile
ai-build <profile>

# Launch a persistent sandbox container (default: interactive shell)
ai-launch <profile>

# Attach a second terminal to a running container
ai-terminal <profile>

# List all profiles and their container state
ai-list
```
