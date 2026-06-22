#!/usr/bin/env bash
# Usage functions for all ai-* commands. Source this file; do not execute directly.

usage_ai_build() {
    cat >&2 <<'EOF'
Usage: ai-build <profile>

Build (or rebuild) the container image defined by the named profile.
The image is built from IMAGE_DIR using BUILD_ARGS. If POST_BUILD_CHECK
is defined in the profile, it is run inside the freshly built image to
print installed tool/library versions.

ai-build never touches existing containers.

Example:
  ai-build esp32

Options:
  -h, --help    Show this help and exit.
EOF
}

usage_ai_launch() {
    cat >&2 <<'EOF'
Usage: ai-launch <profile> [mode] [flags]

Launch a persistent sandbox container for the named profile. If a container
named by the profile already exists, it is reused; otherwise created.

Modes (default: shell):
  shell / bash   Interactive bash shell (default)
  codex          Run the Codex AI coding agent
  codex         Run the Codex AI coding agent
  builder        Privileged ephemeral build container — the only --privileged
                 path; the container is removed on exit (workspace preserved)
  aider          Run the Aider AI coding agent
  opencode       Run the OpenCode AI coding agent
  ollama-shell   Run an Ollama interactive shell

Flags:
  --yes / --non-interactive   Non-interactive: warn-and-continue on staleness
                              and stop without prompting on --reset.
                              NOTE: --yes means "continue with existing",
                              NOT "recreate".
  --recreate                  Remove and recreate the persistent container from
                              the current image (workspace preserved)
  --no-recreate               Explicitly continue with the existing container
  --reset                     Stop and remove the persistent container, then
                              recreate it from the current image; workspace,
                              home dir, profile, image, and secrets are preserved
  -h, --help                  Show this help and exit.

Examples:
  ai-launch esp32                    # Interactive shell in the esp32 container
  ai-launch esp32 codex              # Run Codex in the esp32 container
  ai-launch esp32 builder            # Ephemeral privileged build (removed on exit)
  ai-launch esp32 --recreate         # Recreate container from current image
  ai-launch esp32 --reset --yes      # Stop and recreate without confirmation
EOF
}

usage_ai_terminal() {
    cat >&2 <<'EOF'
Usage: ai-terminal <profile>

Attach an additional interactive shell to the running container for the
named profile via 'podman exec -it'. The container must already be running
(use 'ai-launch <profile>' to start or resume it).

Example:
  ai-terminal esp32

Options:
  -h, --help    Show this help and exit.
EOF
}

usage_ai_list() {
    cat >&2 <<'EOF'
Usage: ai-list

List all profiles in the profiles/ directory, printing name, image name,
workspace path, and persistent container state (running/stopped/absent).
Column widths adapt to the longest value in each column.

Example:
  ai-list

Options:
  -h, --help    Show this help and exit.
EOF
}
