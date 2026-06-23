---
title: 'Fix ai-new bootstrap container setup — Backend Plan'
type: plan-backend
status: in-development
lineage: ai-new-container-setup-failures
parent: lifecycle/requirements/ai-new-container-setup-failures-2.md
created: "2026-06-23T00:00:00+10:00"
priority: high
assignees:
    - role: backend-developer
      who: agent
---

# Fix ai-new Bootstrap Container Setup — Backend Plan

This plan covers the **host-side engine and image/launch chain** that make the
three reported failures possible: where `start-here.sh` is delivered and with
what mode, how the bootstrap image and `podman run` argv are assembled, the
agent registry content, and the install-adapter machinery in `lib/`. The
in-container launcher behaviour (`start-here.sh` itself — the `_install_runtime`
step, validation messaging, and usage/path copy) is owned by the **frontend
plan** (`ai-new-container-setup-failures-4-fe.md`). The two meet at one
contract: the backend guarantees that (a) `start-here.sh` exists, executable,
under `$HOME` on the project mount; (b) the install-adapter helper is reachable
and runnable inside the container as the non-root user; and (c) the pinned
`bootstrap/agent.env` names a real, installable adapter for every supported
agent. The frontend consumes those guarantees.

## Binding decisions (from the requirement's Resolved Questions)

- **D-Q1 (delivery).** "Copy the file into the image." Because `HOME` =
  `/project/bootstrap/home` sits **under** the `/project` bind mount, an image
  `COPY` to that path is shadowed at launch. The faithful realisation of
  "copy, don't bind-mount the host checkout" is therefore to **copy
  `start-here.sh` into the project scaffold** (`bootstrap/home/start-here.sh`)
  at create time with the execute bit set, and to **remove** the
  `:/start-here.sh:ro,z` root bind mount. This decouples the in-container mode
  from the host checkout's permissions (satisfies R2.2) while keeping the script
  inside `$HOME` on the persistent project tree.
- **D-Q2 (install timing).** "Launch time, as it will install the latest
  version." The agent is installed **inside the running container at launch**,
  not baked into the image.
- **D-Q3 (gemini).** The `manual` adapter is "nonsense" — gemini is installed
  exactly like codex/codex at launch time (npm-global).
- **D-Q4 (home path).** Container opens in `/project`; `$HOME` is
  `/project/bootstrap/home`. The script lives at
  `/project/bootstrap/home/start-here.sh`.
- **D-Q8 (which agents).** Only the single pinned agent for the current run.

Implementation constraints (apply to every milestone, inherited from
`ai-new-10-be.md` R16):

- POSIX/Bash, `#!/usr/bin/env bash`, `set -euo pipefail`.
- No hardcoded usernames or `/var/home/<user>` paths — derive every path from
  `$HOME` / `$CODEX_JAILS_DIR`.
- Registry content is never `source`d/`eval`'d/`sh -c`'d; install runs build an
  argv array with no shell interpolation of registry strings (R3.2, R13.4).
- `shellcheck` clean is a precondition for every milestone marked complete.

---

## Milestone B1 — Deliver `start-here.sh` into the container HOME, executable

**Description.** Stop bind-mounting `start-here.sh` onto the container root and
instead place an executable copy inside the project scaffold's home directory so
it appears at `/project/bootstrap/home/start-here.sh` through the existing
`/project` mount. Resolves failures #1 (location) and #2 (not executable)
together (R1.1, R1.2, R2.1, R2.2).

- In scaffold creation, copy the canonical plugin `start-here.sh` to
  `<project>/bootstrap/home/start-here.sh` and `chmod +x` the copy. The execute
  bit is set on the **scaffold copy by `ai-new`**, never inherited from the
  user's host checkout mode (R2.2). The `/project` mount is `:z` (read-write),
  so the bit and writability are preserved in-container.
- Remove the root bind mount in `lib/launch.sh:40-42`
  (`--volume "${_start_here}:/start-here.sh:ro,z"`). Drop the now-unused
  `_start_here` resolution. The container no longer has `/start-here.sh`.
- Keep the prompts mount (`/start-here-prompts`, `lib/launch.sh:44-46`) — it is
  at root, read-only, and not under `$HOME`, so it is unaffected by the
  relocation; `start-here.sh` still copies the bootstrap prompt from it into
  `bootstrap/`. Confirm no other path reference assumes `/start-here.sh` (R1.3).
- Update `lib/launch.sh` info banner to print the in-home path and how to invoke
  it (`/project/bootstrap/home/start-here.sh`), since the container still drops
  into `/bin/bash` (`lib/launch.sh:52`) — the exact invocation copy is owned by
  the FE plan; backend only stops advertising the root path.

**Files to change.**

- `lib/scaffold.sh` — copy canonical `start-here.sh` into
  `bootstrap/home/start-here.sh` with `chmod +x` during `create_scaffold`.
- `lib/launch.sh` — remove the `/start-here.sh` bind mount and `_start_here`;
  correct the info banner path.

**Acceptance criteria.**

- After `ai-new <name> --agent <agent>`, the scaffold contains
  `<project>/bootstrap/home/start-here.sh` with mode showing the execute bit
  (`-rwxr-xr-x` or equivalent) regardless of the host checkout's mode (AC1, AC2).
- In a launched container, `find / -name start-here.sh` returns
  `/project/bootstrap/home/start-here.sh` and **not** `/start-here.sh` (AC1).
- `grep -rn '/start-here.sh' lib/ bin/` finds no remaining mount/reference to the
  root path (R1.3, AC4 support).
- `shellcheck lib/scaffold.sh lib/launch.sh` is clean.

---

## Milestone B2 — Make the install adapter runnable inside the container (non-root)

**Description.** Wire the existing-but-dead `run_install_adapter()` /
`build_argv()` (`lib/adapter.sh`) into the live launch path so it is actually
invoked, and make it work for the launch-time, rootless, `--userns=keep-id`
case. This is the host/image half: expose the helper into the container and
configure writable, home-based package prefixes so a non-root global install
succeeds and persists (R3.1, R3.3, AC5).

- **Expose the helper.** Add a read-only mount in `lib/launch.sh` of the plugin
  library needed to run installs (`lib/adapter.sh`, plus `lib/common.sh` for
  `_info`/`_die`) at a fixed in-container path, e.g.
  `--volume "${CODEX_JAILS_DIR}/lib:/start-here-lib:ro,z"`. The FE `start-here.sh`
  sources `/start-here-lib/adapter.sh` and calls `run_install_adapter` — this is
  the wiring that kills the dead code (AC5). `adapter.sh` must remain
  source-safe (no top-level execution; "Source; do not execute." already holds).
- **Home-based prefixes (the rootless-write fix).** Default `npm install -g`,
  `pipx`, and `dnf` all target non-writable locations for a keep-id non-root
  user. In `lib/bootstrap_image.sh`, set persistent, home-based prefixes and
  PATH in the bootstrap image so launch-time installs land on the project mount
  and resolve on `$PATH`:
  - `ENV NPM_CONFIG_PREFIX=/project/bootstrap/home/.npm-global`
  - `ENV PIPX_HOME=/project/bootstrap/home/.local/pipx`,
    `PIPX_BIN_DIR=/project/bootstrap/home/.local/bin`
  - `ENV PATH=/project/bootstrap/home/.npm-global/bin:/project/bootstrap/home/.local/bin:$PATH`
  Because `$HOME` is on the `/project` mount, the installed binary persists
  across container disposal and resume (consistent with the ai-new persistence
  model) while a fresh `npm install -g` each launch still pulls the latest
  version (D-Q2).
- **`dnf-package` at launch is not feasible non-root.** `build_argv`'s
  `dnf-package` branch would fail without root at launch time. None of the three
  supported agents use it (B3 keeps them all `npm-global`), but
  `run_install_adapter` MUST surface a clear, actionable error for
  `dnf-package`/`pipx`-needs-root rather than a raw permission failure, so a
  future registry entry fails loudly (R3.4). Add an explicit guard/message in
  `lib/adapter.sh`.
- Confirm `ensure_bootstrap_image` rebuilds when the Containerfile changes (the
  ENV additions). Document that an existing cached `localhost/ai-new/bootstrap`
  image must be rebuilt; if `ensure_bootstrap_image` keys only on existence,
  note the manual `podman rmi` step or add a content check (do not silently use
  a stale image).

**Files to change.**

- `lib/bootstrap_image.sh` — add `NPM_CONFIG_PREFIX`, `PIPX_*`, and `PATH` ENV to
  the bootstrap Containerfile; ensure the prefix dirs are creatable by the
  non-root user (they live under the writable mount).
- `lib/launch.sh` — add the read-only `lib/` mount for the install helper.
- `lib/adapter.sh` — keep `run_install_adapter`/`build_argv` argv-only; add an
  actionable error for adapters that cannot run non-root at launch (R3.4).

**Acceptance criteria.**

- The bootstrap image carries the home-based `NPM_CONFIG_PREFIX`/`PIPX_*` and a
  PATH that includes their `bin/` dirs (inspect with `podman image inspect`).
- `run_install_adapter npm-global @openai/codex ""` run as the
  non-root container user installs without a permission error and the resulting
  `codex` binary is on `$PATH` (AC3, AC5).
- `run_install_adapter` is invoked on a normal `ai-new` run (no longer dead
  code): `grep -rn run_install_adapter` shows a live call site reachable from the
  launch path (AC5).
- A `dnf-package` (or root-requiring) adapter produces a clear, actionable
  message rather than a raw failure (R3.4).
- `shellcheck lib/bootstrap_image.sh lib/launch.sh lib/adapter.sh` is clean.

---

## Milestone B3 — Fix the registry so every supported agent has a real adapter

**Description.** Replace gemini's no-op `manual` adapter with a real install so
the pinned agent is installable like codex and codex (D-Q3, R3.2). Registry
content is the single source of truth for package names — no hard-coding (R3.2).

- `config/agents.d/gemini.env`: set `AGENT_INSTALL_ADAPTER="npm-global"` and
  `AGENT_INSTALL_PACKAGE="@google/gemini-cli"` (the published Gemini CLI npm
  package); keep `AGENT_COMMAND="gemini"` and the existing auth-check argv.
- Leave `codex.env` (`@openai/codex`) and `codex.env`
  (`@openai/codex`) unchanged — both already `npm-global`.
- `manual` remains a **valid adapter value** in the parser/validator
  (`lib/registry.sh`, `lib/adapter.sh`) for forward-compatibility, but is no
  longer used by any shipped agent. The FE plan ensures `start-here.sh` still
  degrades gracefully (actionable message) if a `manual` agent is ever pinned
  (R3.4).
- Re-pinning: a project pinned **before** this change still carries the old
  `manual` gemini entry in `bootstrap/agent.env`. Document that such a project
  must be recreated (or its pinned `agent.env` updated) to pick up the new
  adapter; the install step keys off the **pinned** copy, not the global
  registry (consistent with R13.7).

**Files to change.**

- `config/agents.d/gemini.env` — `manual` → `npm-global` + `@google/gemini-cli`.

**Acceptance criteria.**

- `ai-new <name> --agent gemini` pins an `agent.env` whose
  `AGENT_INSTALL_ADAPTER` is `npm-global` and `AGENT_INSTALL_PACKAGE` is
  `@google/gemini-cli` (AC3).
- The registry parser/validator still accepts `manual` as a known adapter (no
  regression to the v1 fixed set) (R3.4).
- For each of codex/codex/gemini, the package name used by the install comes
  from the pinned registry, not a literal in `lib/` (R3.2).

---

## Milestone B4 — Reconcile the conflicting specification (ai-new-3 R4.1)

**Description.** Resolve the documented spec conflict: `ai-new-3.md` R4.1 (and
R3.1, R4.8, R10.1 wording) asserts `/start-here.sh` at the filesystem root,
which now contradicts the home-directory placement (R1.4, AC4).

- Annotate `lifecycle/requirements/ai-new-3.md` R4.1 (and the other
  `/start-here.sh`-root references found at its lines 42, 57, 65, 106, 145, 156,
  158, 176) with an explicit supersession note pointing to this lineage
  (`ai-new-container-setup-failures-2.md` R1) and the new home-dir path. Do not
  silently rewrite history — record that the root location is superseded.
- Add a short reconciliation note to the requirement/plan trail so requirements
  and implementation no longer disagree (AC4).

**Files to change.**

- `lifecycle/requirements/ai-new-3.md` — supersession annotations on the
  root-location requirements.

**Acceptance criteria.**

- `ai-new-3.md` no longer asserts `/start-here.sh` at root without a
  supersession note referencing the home-directory placement (AC4).
- `grep -rn '/start-here.sh' lifecycle/requirements/` surfaces only annotated /
  historical references, none presented as the current spec (AC4).

---

## Cross-cutting acceptance (backend contribution to requirement ACs)

- **AC1** `find / -name start-here.sh` → `/project/bootstrap/home/...`, not root
  (B1).
- **AC2** scaffold copy is executable independent of host mode (B1); invocation
  copy owned by FE.
- **AC3/AC5** install adapter is reachable, runs non-root, resolves the agent on
  `$PATH`; no dead code remains (B2, B3).
- **AC4** spec reconciliation (B4).
