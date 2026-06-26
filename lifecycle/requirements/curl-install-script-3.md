---
title: Curl-Driven Install Script for ai-podbuilder
type: requirement
status: draft
lineage: curl-install-script
parent: lifecycle/ideas/curl-install-script.md
assignees:
    - role: product-owner
      who: agent
---

# Curl-Driven Install Script for ai-podbuilder

> Supersedes the abandoned `curl-install-script-2.md`. That draft was blocked on
> Q1 (which base-directory variable the installer must export). The
> `deprecate-codex-jails-env-vars` work is now **done**: `AI_PODMAN_JAILS_DIR`
> is the canonical variable (it mirrors the legacy `CODEX_JAILS_DIR`), resolved
> centrally in `lib/common.sh`. That answer is folded in below; the remaining
> open questions are carried forward.

## Problem

There is no one-step way to install the framework. Today a user must clone the
whole repository, know that `bin/` has to be on `PATH`, and know that the base
directory is controlled by an environment variable (README "PATH Setup",
README.md:74-83). Nothing fetches "just the runtime", nothing wires the
environment, and nothing updates an existing install in place.

We want a single shell script bootstrappable via `curl -fsSL <url> | bash` that:

1. Installs only the components the runtime needs (the managed set in R3.1) —
   not `lifecycle/`, `tests/`, `doc/`, `docs/`, or example `projects/`.
2. Takes an optional positional install-root argument, defaulting to a
   well-known directory under `$HOME`.
3. Is idempotent: the same command both installs from scratch and updates an
   existing install with no manual steps.
4. Writes shell-environment changes to a **sourced file** the user can review or
   delete, never mutating `~/.bashrc` / `~/.profile` inline.

The earlier naming tension is resolved. The commands read `AI_PODMAN_JAILS_DIR`
(with `CODEX_JAILS_DIR` honoured as a deprecated alias), resolved in
`lib/common.sh:33-41`. The installer exports `AI_PODMAN_JAILS_DIR` only. Note
the code still *defaults* an unset value to `$HOME/codex-jails`
(`lib/common.sh:63`); the `deprecate` requirement (Q5) wants **new** installs to
use `~/ai-podman-jails`. The installer is the agreed place to set that — it
explicitly exports `AI_PODMAN_JAILS_DIR=<install-root>` so the on-disk default
only ever applies to a self-hosting repo checkout, not a curl install.

## Goals / Non-goals

**Goals**

- A self-contained `install.sh` runnable both as `curl … | bash` and as a
  downloaded-then-executed file (`bash install.sh [DIR]`).
- Optional positional install-root arg; default `~/ai-podman-jails`.
- Fetch the required runtime files for the current `main` (or a pinned ref) and
  place them under `<install-root>/`.
- Idempotent install/update: re-running refreshes managed files in place and
  preserves user data (existing `projects/`, hand-authored `profiles/`).
- Emit environment wiring (`PATH` entry for `<install-root>/bin`, and
  `AI_PODMAN_JAILS_DIR=<install-root>`) to a single sourced file the user can
  inspect and opt out of.
- Print clear post-install instructions, including how to activate the
  environment in the current shell without restarting.
- Verify prerequisites (rootless `podman`, `bash`, `curl`) and fail with an
  actionable message when missing.

**Non-goals**

- Installing or configuring Podman itself, or any AI agent runtime (codex,
  codex, etc.).
- Packaging for system package managers (rpm/deb/brew).
- A separate uninstaller beyond documenting how to remove the install root and
  the sourced env file.
- Windows / non-Unix shells. Target is bash on Fedora Atomic / Bazzite per the
  framework's existing assumptions (README "Security Model").
- Multi-version / side-by-side installs.
- Re-exporting the deprecated `CODEX_JAILS_DIR` from the env file — the commands
  resolve it from `AI_PODMAN_JAILS_DIR` themselves; emitting the legacy name
  would only re-trigger the deprecation warning.

## Detailed Requirements

### Invocation & arguments

- **R1.1** The script MUST run correctly when piped to `bash` over stdin
  (`curl -fsSL <url> | bash`) and when executed as a file
  (`bash install.sh [DIR]` or `./install.sh [DIR]`). It MUST NOT depend on
  `$0`/`BASH_SOURCE` pointing at a real file on disk (stdin invocation has none).
- **R1.2** The first positional argument, if present, sets the install root.
  When absent, the default is `~/ai-podman-jails`. The root MUST expand
  `~`/`$HOME` correctly.
- **R1.3** Passing `--help`/`-h` MUST print usage (invocation forms, the
  positional arg, the default root, the env file path) and exit 0.
- **R1.4** The script MUST set `set -euo pipefail` (or equivalent strict-mode
  guards) so a partial failure aborts rather than leaving a half-written install.

### Prerequisite checks

- **R2.1** Before writing anything, the script MUST verify required tooling is
  present: `bash`, `curl`, and rootless `podman`. Missing prerequisites MUST
  produce a single actionable error and a non-zero exit, naming what is missing.
- **R2.2** The check MUST NOT attempt to install Podman or agents itself
  (Non-goals); it only reports.

### Fetch & file selection

- **R3.1** The installer MUST fetch the required runtime components only:
  `bin/`, `lib/`, `config/`, `templates/`, `prompts/`, the example `profiles/`
  (`*.example`), and `start-here.sh`. These are the paths the commands resolve
  under `$AI_PODMAN_JAILS_DIR` (`bin`, `lib`, `config`, `prompts`, `profiles`,
  plus `start-here.sh`). It MUST NOT install `lifecycle/`, `tests/`, `doc/`,
  `docs/`, or example `projects/`.
- **R3.2** Fetched files MUST be retrieved from a single canonical source ref
  (default `main`) over HTTPS; the source URL/ref strategy is per Q2.
- **R3.3** Executable bits MUST be preserved/restored on `bin/*` and
  `start-here.sh` (curl-fetched files lose the mode bit; the installer must
  `chmod +x` them).
- **R3.4** A failed or partial fetch MUST NOT overwrite a working existing
  install. Stage to a temp location and atomically move into place, or verify
  completeness before replacing managed files.

### Idempotent install / update

- **R4.1** Re-running the script against an existing install MUST update the
  managed files in place (R3.1 set) and MUST require no manual pre/post steps.
- **R4.2** The update MUST preserve user-owned data under the install root —
  at minimum any `projects/` and hand-authored `profiles/` (real `*.env`, as
  opposed to the shipped `*.env.example`) — and MUST NOT delete files outside
  the managed set.
- **R4.3** The script SHOULD report whether it performed a fresh install or an
  update, and SHOULD be safe to run repeatedly with no net change ("nothing to
  do" is an acceptable outcome).

### Environment wiring

- **R5.1** Environment changes MUST be written to a single sourced file
  (e.g. `~/.bashrc.d/podbuilder.sh`), NOT appended inline to `~/.bashrc`,
  `~/.profile`, or `~/.zshrc`. The file path MUST be reported to the user.
- **R5.2** The env file MUST export `AI_PODMAN_JAILS_DIR=<install-root>` and
  prepend `<install-root>/bin` to `PATH`. It MUST NOT export the deprecated
  `CODEX_JAILS_DIR` (Non-goals).
- **R5.3** Writing the env file MUST be idempotent — re-running overwrites/owns
  the managed file rather than appending duplicate blocks. If a different
  pre-existing env file exists, the installer MUST NOT silently clobber unrelated
  content (own a dedicated file, or use a clearly delimited managed block).
- **R5.4** The installer MUST NOT assume `~/.bashrc.d/*` is auto-sourced. If the
  user's `~/.bashrc` does not already source the chosen directory, the installer
  MUST either add a guarded source line (its only inline edit, clearly marked) or
  instruct the user how to source it. The chosen approach is per Q3.
- **R5.5** Post-install output MUST tell the user how to activate the new
  environment in the current shell immediately (e.g. the exact
  `source <env-file>` command) without opening a new terminal.

### Migration of existing installs

- **R6.1** When run over an existing install whose environment was wired with
  the legacy `CODEX_JAILS_DIR` (manual README setup), the installer MUST produce
  a working install keyed on `AI_PODMAN_JAILS_DIR` without requiring the user to
  hand-edit their old setup. Behaviour when both an old inline `CODEX_JAILS_DIR`
  export and the new env file are present is per Q6.

### Safety & output

- **R7.1** All writes MUST stay within the install root and the single env file
  (plus at most the one guarded `~/.bashrc` source line from R5.4). No other host
  files may be modified.
- **R7.2** On any error the script MUST exit non-zero with a message identifying
  the failed step; it MUST NOT report success after a partial install.

## Acceptance Criteria

- **AC1** On a fresh machine (Podman present, repo not cloned),
  `curl -fsSL <url> | bash` produces a working install: `ai-list`, `ai-new`,
  `ai-build`, `ai-launch`, `ai-terminal` are on `PATH` after sourcing the env
  file and run without "command not found".
- **AC2** `curl -fsSL <url> | bash ~/somewhere-else` installs under the given
  directory; with no argument it installs under `~/ai-podman-jails` and exports
  `AI_PODMAN_JAILS_DIR` to match.
- **AC3** Running the same command a second time updates managed files in place,
  exits 0, and leaves any pre-existing `projects/` and hand-authored `profiles/`
  untouched.
- **AC4** After install, exactly one sourced env file exists at the reported
  path, it exports `AI_PODMAN_JAILS_DIR` and the `PATH` entry (and not
  `CODEX_JAILS_DIR`), and re-running the installer does not duplicate or corrupt
  its contents.
- **AC5** No inline mutation of `~/.bashrc`/`~/.profile`/`~/.zshrc` occurs beyond
  the single guarded source line permitted by R5.4 (if that approach is chosen),
  and that line is idempotent across re-runs.
- **AC6** Files under `bin/` and `start-here.sh` are executable after install
  (`test -x`).
- **AC7** With `podman` absent, the script exits non-zero before writing
  anything and names the missing prerequisite.
- **AC8** A simulated mid-fetch failure leaves any prior working install intact
  (no half-written managed files); a fresh-install failure leaves no partial
  install root that looks complete.
- **AC9** `lifecycle/`, `tests/`, `doc(s)/`, and example `projects/` are NOT
  present in the install root after a normal install; `prompts/` and the example
  `profiles/*.example` ARE present.
- **AC10** Running a command after install emits no `CODEX_JAILS_DIR`
  deprecation warning (the env file sets only the canonical variable).

## Answers

- **Q2 (fetch source).** What is the canonical fetch source — `git clone`/sparse checkout, a per-file raw download from a hosting URL, or a release tarball? And what ref does the installer pin to by default (`main`, latest tag, or a version the script embeds)? This determines how updates detect "newer".

Answer: It will be the latest release as a tarball from github

- **Q3 (bashrc.d sourcing).** May the installer add a guarded `source ~/.bashrc.d/*` line to `~/.bashrc` when the shell does not already source that directory (Fedora's default `~/.bashrc` does, but a piped install cannot assume it), or should it stay strictly hands-off and only print instructions? Also: is bash-only acceptable, or must zsh be supported?

Answer: yes, bash only at this stage

- **Q5 (download URL stability).** What is the public `<url>` users will curl, and is it owned/stable enough to advertise in the README as the supported install path?

Answer: The URL will be the latest release on github for this project

- **Q6 (legacy inline export).** A returning user may still have a manual  `export CODEX_JAILS_DIR=$HOME/codex-jails` in their `~/.bashrc` from the old README. Should the installer (a) leave it alone and let the new env file's `AI_PODMAN_JAILS_DIR` take precedence — accepting the deprecation warning until the user removes the old line, (b) detect and warn about it, or (c) offer to migrate the old install root's `projects/` into the new default? Tied to the interactive yes/no setup flow flagged in the `deprecate` requirement (Q5).

Answer: (a), (b) and (c)
