---
title: 'AI-New: Interactive Project Bootstrap Container'
type: idea
status: done
lineage: ai-new
created: "2026-06-22T19:22:13+10:00"
priority: normal
---

# `ai-new`: Interactive Agent-Primed Project Bootstrap Container

The `ai-new` command creates and launches a **minimal temporary bootstrap container** for starting a new AI-agent project.

This bootstrap container is **not** the final development environment. It is a disposable scaffolding environment whose only purpose is to help the user define and generate the real project container.

The bootstrap container ships with a single primary entrypoint script at the filesystem root:

```sh
/start-here.sh
```

The `start-here.sh` script does **not** contain a hardcoded questionnaire and does **not** attempt to generate the final project by itself.

Instead, `start-here.sh` acts as an **agent-priming launcher**.

Its role is to start the selected AI agent runtime inside the bootstrap container with a strong bootstrap prompt. That prompt instructs the agent to interactively interrogate the user, gather the project requirements, reason through the required container design, and generate the appropriate project files.

The agent, not the shell script, is responsible for guiding the user through the project-definition process.

## Intended Flow

```text
ai-new
  → creates/launches a tiny temporary bootstrap container
  → user enters the bootstrap container
  → user runs /start-here.sh
  → start-here.sh primes and launches the selected AI agent
  → the agent interviews the user about the intended project
  → the agent determines the required container design
  → the agent writes the real project Containerfile and helper files
  → the user exits the bootstrap container
  → the user builds and launches the actual project container
```

## Purpose of the Bootstrap Container

The bootstrap container should be as small and low-friction as possible.

It only needs enough tooling to:

```text
- run /start-here.sh
- launch or connect to the selected AI agent runtime
- provide a workspace where generated files can be written
- emit the final project Containerfile and supporting scripts
```

The bootstrap image should avoid carrying the full development stack for the eventual project. Real project dependencies belong in the generated image, not in the bootstrap image.

## Role of `start-here.sh`

The `start-here.sh` script should:

```text
- detect or ask which AI agent runtime should be used
- launch that agent in the current project workspace
- provide the agent with a structured project-bootstrap prompt
- instruct the agent to interview the user interactively
- instruct the agent to generate the final project files
- ensure the user receives clear next-step instructions
```

The script should not try to encode every possible project option itself. Its value is in reliably launching the agent with the correct mission and constraints.

In short:

```text
/start-here.sh primes the agent.
The agent interrogates the user.
The agent generates the project.
```

## Agent Responsibilities

Once launched by `start-here.sh`, the agent should ask the user targeted questions to understand the desired project environment.

The agent should determine, at minimum:

```text
- the intended project purpose
- the preferred AI agent runtime, such as Codex or another supported runtime
- the desired project role or profile
- the target language/runtime stack
- required OS packages
- required developer tools
- required package managers
- required build systems
- expected source/project layout
- workspace mount strategy
- persistent state requirements
- exposed ports
- environment variables
- secrets or credentials that must be mounted instead of baked into the image
- network assumptions
- GPU, audio, USB, display, or other host resource needs
- whether the environment should be rootless-friendly
- whether the environment should support Podman, Docker, or both
- whether update/build/launch helper scripts should be generated
- whether README or onboarding instructions should be generated
```

The agent should ask follow-up questions where needed, but it should avoid overwhelming the user. It should progressively narrow the requirements and then produce a concrete result.

## Generated Output

After gathering enough information, the agent should generate the actual project scaffold.

Expected generated files may include:

```text
Containerfile
README.md
launch script
update/build script
agent configuration
role/profile files
.env.example
.gitignore
workspace directory structure
optional helper scripts
```

The most important output is the real project `Containerfile`.

That `Containerfile` defines the durable development image for the user’s actual AI-agent project.

## User Instructions After Generation

When generation is complete, the agent should clearly tell the user that the bootstrap container has finished its job.

The final instructions should tell the user to:

```text
1. Review the generated files.
2. Exit the bootstrap container.
3. Build the real project image from the generated Containerfile.
4. Relaunch into the new project container.
```

At that point, the generated image becomes the user’s actual working environment.

## Design Principle

The key architectural principle is:

```text
The bootstrap container is disposable.
The generated project container is durable.
```

The bootstrap layer exists only to start an agent-led setup conversation. It should not become a large general-purpose development environment.

All meaningful project dependencies, tools, runtimes, and configuration should be declared in the generated `Containerfile` and installed during the real image build.

## Goal

The goal of `ai-new` is to provide the lowest possible barrier to creating a new AI-agent project container.

A user should not need to manually write a `Containerfile`, understand every runtime dependency, or know the full project layout in advance.

Instead, they should be able to run:

```sh
ai-new
```

Then enter the bootstrap environment, run:

```sh
/start-here.sh
```

And be guided by an AI agent that asks the right questions and produces a tailored, reproducible project container.

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
