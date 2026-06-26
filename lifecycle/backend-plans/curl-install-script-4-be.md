---
title: Curl-Driven Install Script for ai-podbuilder — Backend Plan
type: plan-backend
status: done
lineage: curl-install-script
parent: lifecycle/requirements/curl-install-script-3.md
---

# Backend Plan — Curl-Driven Install Script

All work is one new shell script, `install.sh`, at the repo root. No Go, no
changes to `lib/*.sh` (the resolver already prefers `AI_PODMAN_JAILS_DIR` per
the completed `deprecate-codex-jails-env-vars` work). The installer fetches the
latest GitHub release tarball, stages it, swaps managed files into place
atomically, and owns a single sourced env file.

Source of truth for the managed runtime set (R3.1): `bin/`, `lib/`, `config/`,
`templates/`, `prompts/`, `profiles/*.example`, and `start-here.sh`.

---

## Milestone 1 — Skeleton, strict mode, arg & help parsing

**Description.** Stand up the script so it runs identically over stdin
(`curl … | bash`) and as a file. Strict mode on. Parse the optional positional
install-root and `--help`/`-h`. Do not touch `$0`/`BASH_SOURCE` for any logic
(R1.1 — stdin has no file).

**Files to change.**
- `install.sh` (new):
  - `#!/usr/bin/env bash` + `set -euo pipefail`.
  - `INSTALL_ROOT="${1:-$HOME/ai-podman-jails}"`; expand `~`/`$HOME` (R1.2 —
    rely on shell expansion, `eval`-free).
  - `--help`/`-h` → `usage()` printing invocation forms, positional arg, default
    root, and the env-file path; `exit 0` (R1.3).
  - Small helpers: `die()` (message to stderr, non-zero exit, names the step),
    `info()`.

**Acceptance criteria.**
- `bash install.sh --help` and `curl … | bash -s -- --help` both print usage and
  exit 0.
- `cat install.sh | bash -s -- /tmp/foo` sets root `/tmp/foo`; no arg → root
  `$HOME/ai-podman-jails`.
- No code path dereferences `$0`/`BASH_SOURCE` (`grep` confirms).
- A forced failure in any later step exits non-zero with a step-named message
  (R7.2).

## Milestone 2 — Prerequisite checks

**Description.** Before any write, verify `bash`, `curl`, and rootless `podman`
are present. Report only; never install anything (R2.1, R2.2).

**Files to change.**
- `install.sh`: `check_prereqs()` — `command -v bash curl podman`; for podman,
  confirm rootless works (`podman info` succeeds as the invoking user). Missing
  → single actionable `die` naming what is absent, before any filesystem write.

**Acceptance criteria.**
- With `podman` absent (or rootless broken), the script exits non-zero, names
  the missing prerequisite, and writes nothing (AC7).
- All three present → proceeds silently.

## Milestone 3 — Fetch latest release tarball to a temp stage

**Description.** Resolve and download the **latest GitHub release** tarball over
HTTPS into a `mktemp -d` staging dir, then extract (Q2/Q5 answers). Default ref
= latest release; allow `AI_PODMAN_REF` env override for pinning. Clean up the
temp dir on any exit (`trap … EXIT`).

**Files to change.**
- `install.sh`: `fetch_release()`:
  - `STAGE="$(mktemp -d)"`; `trap 'rm -rf "$STAGE"' EXIT`.
  - Use the GitHub API `releases/latest` to get the tarball URL (or
    `…/tarball/<ref>` when `AI_PODMAN_REF` set), `curl -fsSL` to
    `"$STAGE/src.tar.gz"`, `tar -xzf` into `"$STAGE/src"`. GitHub tarballs nest
    one top-level `<owner>-<repo>-<sha>/` dir — resolve it (`SRCROOT=$(echo
    "$STAGE"/src/*/)`).
  - `-f` makes curl fail (non-zero) on HTTP errors; a failed download `die`s
    here (R3.4 — nothing has been moved into the install root yet).

**Acceptance criteria.**
- A successful run leaves the extracted tree under `$STAGE/src/<top>/` with
  `bin/`, `lib/`, etc. present.
- A simulated fetch failure (bad URL / network) exits non-zero before the
  install root is touched; temp dir is removed (AC8).
- `AI_PODMAN_REF=<tag>` fetches that ref's tarball instead of latest.

## Milestone 4 — Select managed set & atomic swap into the install root

**Description.** Copy only the managed set (R3.1) from the stage into the
install root, atomically and without clobbering user data (R3.4, R4.1, R4.2).
Restore exec bits (R3.3). Detect fresh-install vs update for reporting (R4.3).

**Files to change.**
- `install.sh`: `install_files()`:
  - `MANAGED=(bin lib config templates prompts start-here.sh)`; profiles handled
    specially (only `*.example`).
  - Stage the final layout in `"$STAGE/out"` first: copy each managed path from
    `$SRCROOT`; copy `profiles/*.example` only (never overwrite real `*.env`).
  - `mkdir -p "$INSTALL_ROOT"`. For each managed top-level dir, replace in place
    via temp-dir-then-`mv` (`rm -rf "$INSTALL_ROOT/bin.new"; cp -a …; mv -T`),
    so a managed dir is swapped atomically and `projects/`, real `profiles/*.env`
    outside the managed set are never deleted (R4.2, R7.1).
  - `chmod +x "$INSTALL_ROOT"/bin/* "$INSTALL_ROOT/start-here.sh"` (R3.3).
  - `WAS_UPDATE=1` if the root already held managed files; else fresh.

**Acceptance criteria.**
- After install, `lifecycle/`, `tests/`, `doc/`, `docs/`, example `projects/`
  are **absent**; `prompts/` and `profiles/*.example` are **present** (AC9).
- `bin/*` and `start-here.sh` pass `test -x` (AC6).
- Re-running with a pre-existing `projects/` and a hand-authored
  `profiles/foo.env` leaves both untouched (AC3, AC4 user-data clause).
- A failure mid-copy leaves the prior install's managed files intact (swap is
  per-dir `mv`, staged in `$STAGE/out`) (AC8).

## Milestone 5 — Owned, idempotent env file

**Description.** Write `PATH` + `AI_PODMAN_JAILS_DIR` to a single sourced file
the installer fully owns; never append inline to rc files; never emit the
deprecated `CODEX_JAILS_DIR` (R5.1, R5.2, R5.3).

**Files to change.**
- `install.sh`: `write_env_file()`:
  - `ENV_FILE="$HOME/.bashrc.d/podbuilder.sh"`; `mkdir -p` its dir.
  - Overwrite (not append) the whole file each run so re-running can never
    duplicate blocks (R5.3):
    ```sh
    # Managed by ai-podbuilder install.sh — safe to delete.
    export AI_PODMAN_JAILS_DIR="<install-root>"
    export PATH="<install-root>/bin:${PATH}"
    ```
  - Report the path to the user.

**Acceptance criteria.**
- Exactly one env file at the reported path; it exports `AI_PODMAN_JAILS_DIR`
  and the `PATH` entry and **not** `CODEX_JAILS_DIR` (AC4, AC10).
- Re-running does not duplicate or corrupt the file (AC4).
- No inline writes to `~/.bashrc`/`~/.profile`/`~/.zshrc` from this milestone.

## Milestone 6 — Guarded bashrc source line (bash-only)

**Description.** `~/.bashrc.d/*` is not universally auto-sourced; a piped
install cannot assume it. Per Q3 (yes, bash-only) add a single clearly-marked,
idempotent `source` line to `~/.bashrc` when it does not already source the
directory (R5.4). This is the only permitted inline rc edit (R7.1).

**Files to change.**
- `install.sh`: `ensure_sourced()`:
  - If `~/.bashrc` already sources `~/.bashrc.d` (grep), do nothing.
  - Else append a guarded block delimited by a unique marker comment; guard the
    source with `[ -f … ] && . …`. Use the marker to make append idempotent
    (grep for marker before appending).

**Acceptance criteria.**
- When `~/.bashrc` lacks the directory source, exactly one guarded marked line
  is added; re-running adds nothing further (AC5).
- The line is the only `~/.bashrc` mutation; `~/.profile`/`~/.zshrc` untouched
  (AC5).

## Milestone 7 — Legacy-install migration (Q6 a+b+c)

**Description.** Returning users may have `export CODEX_JAILS_DIR=$HOME/codex-jails`
in `~/.bashrc` and a populated old install root (R6.1). Q6 answer = do all of
a, b, c: the new env file's `AI_PODMAN_JAILS_DIR` already takes precedence (a);
**warn** when an old inline `CODEX_JAILS_DIR` export is detected (b); and
**offer** to migrate the old root's `projects/` into the new root (c).

**Files to change.**
- `install.sh`: `migrate_legacy()`:
  - Detect `CODEX_JAILS_DIR` export in `~/.bashrc` → print a warning that it is
    deprecated and the new env file now wins; advise removing it to silence the
    deprecation warning (b).
  - If `$HOME/codex-jails/projects` (or the detected old root) exists and differs
    from the new root, offer to copy `projects/` over. On a piped/non-interactive
    stdin, default to **skip + print the exact `cp -a` command** (no blocking
    prompt). `ponytail: interactive prompt only when stdin is a TTY; piped
    install prints the manual command instead of hanging.` (c)

**Acceptance criteria.**
- A `CODEX_JAILS_DIR` inline export triggers a single deprecation warning naming
  the file and the canonical variable (b).
- New install is keyed on `AI_PODMAN_JAILS_DIR` and works without the user
  hand-editing the old setup (R6.1, AC10).
- Migration offer (c) never blocks a piped install; declining/auto-skip leaves
  the old root untouched and prints the copy command.

## Milestone 8 — Post-install report + activation instructions

**Description.** Tell the user whether it was a fresh install or update, the
install root, the env-file path, and the exact command to activate in the
current shell without a new terminal (R4.3, R5.5).

**Files to change.**
- `install.sh`: `report()` — print summary and
  `source "$HOME/.bashrc.d/podbuilder.sh"` as the activation command.

**Acceptance criteria.**
- Output names fresh-vs-update, the root, and the env file, and shows the exact
  `source …` line (R5.5).
- After sourcing, `ai-list ai-new ai-build ai-launch ai-terminal` resolve on
  `PATH` and run without "command not found" (AC1, AC2).

## Milestone 9 — Lint / self-check

**Description.** Shellcheck the script and run a dry self-check.

**Files to change.**
- `install.sh` (fixes only).

**Acceptance criteria.**
- `shellcheck install.sh` passes with no new warnings.
- `--help` and prereq-fail paths exit before any write (covered by test plan).

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
