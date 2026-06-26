# AI Agent Podman Sandbox Framework

Rootless Podman tooling for running AI coding agents in isolated, persistent
containers on Bazzite / Fedora Atomic hosts.

The repository now supports two related workflows:

- `ai-new` scaffolds a brand-new project through an agent-led bootstrap session.
- `ai-build`, `ai-launch`, `ai-terminal`, and `ai-list` manage durable
  profile-based sandboxes once a project exists.

## What This Repo Contains

```text
bin/        User-facing commands
lib/        Shared Bash libraries used by the commands
config/     Agent runtime registry (`config/agents.d/*.env`)
profiles/   Hand-authored profile examples and local profiles
projects/   Generated project scaffolds and sample projects
templates/  Files emitted by `ai-new`
docs/       Operator and design documentation
tests/      Shell test suite
start-here.sh  Bootstrap entrypoint used inside ai-new containers
```

## Main Workflows

### 1. Bootstrap a new project with `ai-new`

Use `ai-new` when you do not yet have a project container layout.

```sh
ai-new my-project --agent codex
```

That command creates `projects/my-project/`, builds a minimal bootstrap image,
and drops you into a disposable container where `/start-here.sh` launches the
selected agent. The agent interviews you, generates the durable project files,
and the host runs a quality gate against the generated image.

Resume an interrupted bootstrap session with:

```sh
ai-new my-project --resume
```

Useful flags:

- `--boost <auth.json>` seeds local Codex auth for bootstrap use.
- `--shell-on-exit` leaves you in an interactive shell if the agent exits.
- `--skip-trial-build` skips the host-side trial `podman build`.

Full details: [docs/ai-new.md](docs/ai-new.md)

### 2. Run a durable sandbox from a profile

Use the profile commands when you already have a project profile, whether it
was created by `ai-new` or authored manually.

```sh
ai-build <profile>
ai-launch <profile>
ai-terminal <profile>
ai-list
```

`ai-launch` supports several modes, including `shell`, `codex`, `codex`,
`aider`, `opencode`, `ollama-shell`, and an ephemeral privileged `builder`
mode for cases that require raw device access.

## PATH Setup

Add the repo's `bin/` directory to your shell `PATH`:

```sh
export CODEX_JAILS_DIR="${CODEX_JAILS_DIR:-$HOME/codex-jails}"
export PATH="${CODEX_JAILS_DIR}/bin:${PATH}"
```

If `CODEX_JAILS_DIR` is unset, the commands derive the base directory from
their own location, so the repo remains self-hosting.

## Project Layout

`ai-new` generates projects under `projects/<name>/` with a durable layout like:

```text
projects/<name>/
├── README.md
├── profile.env
├── PODMAN_BUILDER.md
├── image/
│   └── Containerfile
├── launchers/
├── workspace/
└── bootstrap/
    ├── agent.env
    ├── session.json
    ├── session.md
    ├── build.log
    └── ...
```

The `bootstrap/` directory persists the temporary bootstrap state on the host.
The `image/`, `profile.env`, `launchers/`, and `workspace/` tree are the durable
artifacts you keep using after bootstrap is complete.

## Security Model

- Rootless Podman only.
- Persistent containers use `--userns=keep-id`.
- The default model mounts the workspace and a dedicated container home, not
  the host `$HOME`.
- Host SSH material is not mounted by default.
- The only privileged path is `ai-launch <profile> builder`, which is ephemeral.

More detail: [docs/security-model.md](docs/security-model.md)

## Key Documentation

- [docs/ai-new.md](docs/ai-new.md) — bootstrap flow and generated scaffold
- [docs/profiles.md](docs/profiles.md) — profile schema and examples
- [docs/security-model.md](docs/security-model.md) — runtime isolation model
- [docs/secrets-and-ssh.md](docs/secrets-and-ssh.md) — secrets injection and SSH strategy
- [docs/selinux.md](docs/selinux.md) — SELinux options and trade-offs
- [docs/desktop-integration.md](docs/desktop-integration.md) — launcher scripts and desktop entrypoints
- [docs/teardown.md](docs/teardown.md) — reset and recreate workflows

## Testing

The repository ships a shell-based test suite under `tests/`.

```sh
tests/run_tests.sh
```

Some tests rely on Podman and the expected host environment, so run them on a
machine that matches the framework's target assumptions.
