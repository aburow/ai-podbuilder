---
title: Curl-Driven Install Script for ai-podbuilder
type: requirement
status: blocked
lineage: curl-install-script
parent: lifecycle/ideas/curl-install-script.md
assignees:
    - role: product-owner
      who: agent
---

# Curl-Driven Install Script for ai-podbuilder

## Problem

There is no one-step way to install the framework. Today a user must clone the
whole repository, know that `bin/` has to be on `PATH`, and know that
`CODEX_JAILS_DIR` controls the base directory (README "PATH Setup",
README.md:74-83). Nothing fetches "just the runtime", nothing wires the
environment, and nothing updates an existing install in place.

We want a single shell script bootstrappable via `curl -fsSL <url> | bash` that:

1. Installs only the components the runtime needs (`bin/`, `lib/`, `config/`,
   `templates/`, `start-here.sh` — not `lifecycle/`, `tests/`, `doc/`, or the
   bundled `projects/` examples).
2. Takes an optional positional install-root argument, defaulting to a
   well-known directory under `$HOME`.
3. Is idempotent: the same command both installs from scratch and updates an
   existing install with no manual steps.
4. Writes shell-environment changes to a **sourced file** the user can review or
   delete, never mutating `~/.bashrc` / `~/.profile` inline.

A naming tension must be resolved before implementation: the idea names the
default root `~/podman-jails` and the tool "ai-podbuilder", but the existing
code and README use `CODEX_JAILS_DIR` defaulting to `$HOME/codex-jails`
(README.md:78). The installer must agree with what the commands actually read,
or set the variable the commands actually honour. See Open Questions Q1.

## Goals / Non-goals

**Goals**

- A self-contained `install.sh` runnable both as `curl … | bash` and as a
  downloaded-then-executed file (`bash install.sh [DIR]`).
- Optional positional install-root arg; sensible `$HOME`-relative default.
- Fetch the required runtime files for the current `main` (or a pinned ref) and
  place them under `<install-root>/`.
- Idempotent install/update: re-running refreshes managed files in place and
  preserves user data (existing `projects/`, hand-authored `profiles/`).
- Emit environment wiring (`PATH` entry for `<install-root>/bin`, the base-dir
  variable the commands read) to a single sourced file the user can inspect and
  opt out of.
- Print clear post-install instructions, including how to activate the
  environment in the current shell without restarting.
- Verify prerequisites (rootless `podman`, `bash`, `curl`) and fail with an
  actionable message when missing.

**Non-goals**

- Installing or configuring Podman itself, or any AI agent runtime (codex,
  codex, etc.).
- Packaging for system package managers (rpm/deb/brew) — out of scope.
- A separate uninstaller beyond documenting how to remove the install root and
  the sourced env file.
- Windows / non-Unix shells. Target is bash on Fedora Atomic / Bazzite per the
  framework's existing assumptions (README "Security Model").
- Multi-version / side-by-side installs.

## Detailed Requirements

### Invocation & arguments

- **R1.1** The script MUST run correctly when piped to `bash` over stdin
  (`curl -fsSL <url> | bash`) and when executed as a file
  (`bash install.sh [DIR]` or `./install.sh [DIR]`). It MUST NOT depend on
  `$0`/`BASH_SOURCE` pointing at a real file on disk (stdin invocation has none).
- **R1.2** The first positional argument, if present, sets the install root.
  When absent, the default install root applies (Q1). The root MUST be
  `$HOME`-relative by default and expand `~`/`$HOME` correctly.
- **R1.3** Passing `--help`/`-h` MUST print usage (invocation forms, the
  positional arg, the default root, the env file path) and exit 0.
- **R1.4** The script MUST set `set -euo pipefail` (or equivalent strict-mode
  guards) so a partial failure aborts rather than leaving a half-written install.

### Prerequisite checks

- **R2.1** Before writing anything, the script MUST verify required tooling is
  present: `bash` (>= the version the libs assume), `curl`, and rootless
  `podman`. Missing prerequisites MUST produce a single actionable error and a
  non-zero exit, naming what is missing.
- **R2.2** The check MUST NOT attempt to install Podman or agents itself
  (Non-goals); it only reports.

### Fetch & file selection

- **R3.1** The installer MUST fetch the required runtime components only:
  `bin/`, `lib/`, `config/`, `templates/`, and `start-here.sh`. It MUST NOT
  install `lifecycle/`, `tests/`, `doc/`, `docs/` (Q4), or example
  `projects/`.
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
  at minimum any `projects/` and hand-authored `profiles/` — and MUST NOT delete
  files outside the managed set.
- **R4.3** The script SHOULD report whether it performed a fresh install or an
  update, and SHOULD be safe to run repeatedly with no net change ("nothing to
  do" is an acceptable outcome).

### Environment wiring

- **R5.1** Environment changes MUST be written to a single sourced file
  (e.g. `~/.bashrc.d/podbuilder.sh`), NOT appended inline to `~/.bashrc`,
  `~/.profile`, or `~/.zshrc`. The file path MUST be reported to the user.
- **R5.2** The env file MUST export the base-directory variable the commands
  actually read (`CODEX_JAILS_DIR` today — see Q1) pointing at the install root,
  and prepend `<install-root>/bin` to `PATH`.
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

### Safety & output

- **R6.1** All writes MUST stay within the install root and the single env file
  (plus at most the one guarded `~/.bashrc` source line from R5.4). No other host
  files may be modified.
- **R6.2** On any error the script MUST exit non-zero with a message identifying
  the failed step; it MUST NOT report success after a partial install.

## Acceptance Criteria

- **AC1** On a fresh machine (Podman present, repo not cloned),
  `curl -fsSL <url> | bash` produces a working install: `ai-list`, `ai-new`,
  `ai-build`, `ai-launch`, `ai-terminal` are on `PATH` after sourcing the env
  file and run without "command not found".
- **AC2** `curl -fsSL <url> | bash ~/somewhere-else` installs under the given
  directory; with no argument it installs under the default root and exports the
  base-dir variable to match.
- **AC3** Running the same command a second time updates managed files in place,
  exits 0, and leaves any pre-existing `projects/` and hand-authored `profiles/`
  untouched.
- **AC4** After install, exactly one sourced env file exists at the reported
  path, it exports the base-dir variable and the `PATH` entry, and re-running the
  installer does not duplicate or corrupt its contents.
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
  present in the install root after a normal install.

## Open Questions

- **Q1 (base-dir name & default).** The idea says default root `~/podman-jails`
  and tool name "ai-podbuilder", but the commands read `CODEX_JAILS_DIR`
  defaulting to `$HOME/codex-jails` (README.md:78). Which wins: keep
  `CODEX_JAILS_DIR` (installer sets it to the chosen root, default
  `~/codex-jails`), rename the variable across the codebase, or set a new
  `PODBUILDER_DIR` that the commands learn to honour? The installer must export
  whatever the commands actually read.

- **Q2 (fetch source).** What is the canonical fetch source — `git clone`/sparse
  checkout, a per-file raw download from a hosting URL, or a release tarball? And
  what ref does the installer pin to by default (`main`, latest tag, or a version
  the script embeds)? This determines how updates detect "newer".

- **Q3 (bashrc.d sourcing).** May the installer add a guarded
  `source ~/.bashrc.d/*` line to `~/.bashrc` when the shell does not already
  source that directory (Fedora's default `~/.bashrc` does, but a piped install
  cannot assume it), or should it stay strictly hands-off and only print
  instructions? Also: is bash-only acceptable, or must zsh be supported?

- **Q4 (docs in install).** Should operator docs (`docs/`) be included so
  installed commands can point at local help, or is keeping the install minimal
  (runtime only) preferred?

- **Q5 (download URL stability).** What is the public `<url>` users will curl,
  and is it owned/stable enough to advertise in the README as the supported
  install path?
