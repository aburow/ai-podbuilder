# AI Agent Podman Sandbox Framework

A rootless-Podman sandbox framework for running AI coding agents in isolated,
persistent containers on Bazzite / Fedora Atomic hosts.

## Layout

```
bin/        Generic commands: ai-build, ai-launch, ai-terminal, ai-list
lib/        Shared sourced libraries (common.sh, profile.sh, policy.sh, render.sh, …)
profiles/   Per-project profile files (<name>.env)
launchers/  Optional desktop/per-project launcher scripts
docs/       Operator documentation
```

## PATH setup

Add the `bin/` directory to your shell `PATH`:

```sh
export CODEX_JAILS_DIR="${CODEX_JAILS_DIR:-$HOME/codex-jails}"
export PATH="${CODEX_JAILS_DIR}/bin:${PATH}"
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

Run any command with `-h` or `--help` for full usage.

## Documentation

- [Profiles](docs/profiles.md) — How to author a profile, required vs optional fields, and PATH setup.
- [Security model](docs/security-model.md) — Normal-mode policy, what is not mounted, builder-only `--privileged`, and persistence rationale.
- [SELinux](docs/selinux.md) — `SELINUX_MODE=disable` (default) vs `enforce`, trade-offs and how to choose.
- [Secrets and SSH](docs/secrets-and-ssh.md) — `ENV_FILE` usage, mode `600`, no-commit rule, and the dedicated in-sandbox SSH key recipe.
- [Teardown](docs/teardown.md) — `--reset` and `--recreate` as the canonical teardown paths; raw Podman as escape hatch.
- [Desktop integration](docs/desktop-integration.md) — Launcher scripts, `.desktop` KDE/GNOME examples, and Podman Desktop notes.
