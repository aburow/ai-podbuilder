# Desktop Integration

This framework provides thin launcher scripts in `launchers/` that serve as
desktop or Podman-Desktop entry points. Each script calls `ai-launch` with
`--non-interactive` so it never blocks behind a hidden prompt.

> **Note:** Automatic `.desktop` file generation is deferred (D4). The
> examples below are hand-authored and must be edited to match your paths.

---

## Launcher scripts

Launcher scripts live in `launchers/<name>-<mode>` and simply call:

```bash
ai-launch <name> <mode> --non-interactive
```

Provided examples:

| Script                     | Profile  | Mode      |
|---------------------------|----------|-----------|
| `launchers/esp32-codex`   | esp32    | codex     |
| `launchers/uxplay-codex` | uxplay   | codex    |
| `launchers/uxplay-builder`| uxplay   | builder   |

Add `$AI_PODMAN_JAILS_DIR/bin` to your `PATH` so that `ai-launch` resolves
without a hard-coded path (see the README PATH setup section).

---

## `.desktop` file examples

`.desktop` files go in `~/.local/share/applications/`. Paths in the examples
use `$HOME` and `$AI_PODMAN_JAILS_DIR` — **no hard-coded usernames or `/var/home`
paths** (R12.2). Substitute the actual expanded values when writing the file,
or use a wrapper script that performs the expansion at launch time.

### KDE (Konsole)

```ini
[Desktop Entry]
Version=1.0
Type=Application
Name=ESP32 Codex Sandbox
Comment=Launch Codex AI agent in the ESP32 development container
Exec=konsole --noclose -e bash -c '$HOME/codex-jails/launchers/esp32-codex'
Icon=utilities-terminal
Categories=Development;
```

### GNOME (GNOME Console / kgx)

```ini
[Desktop Entry]
Version=1.0
Type=Application
Name=ESP32 Codex Sandbox
Comment=Launch Codex AI agent in the ESP32 development container
Exec=kgx -- bash -c '$HOME/codex-jails/launchers/esp32-codex'
Icon=utilities-terminal
Categories=Development;
```

> Replace `$HOME/codex-jails` with `$AI_PODMAN_JAILS_DIR` if that variable is set
> in your login environment and the terminal inherits it.

---

## Podman Desktop integration

Persistent containers launched by `ai-launch` appear in Podman Desktop under
the **Containers** list. From there you can:

- **Start / Stop** the container without opening a terminal.
- **Inspect** environment variables, mounts, and resource usage.
- **Remove** the container (equivalent to `ai-launch <profile> --reset --yes`).

Builder-mode containers (`ai-launch <profile> builder`) are ephemeral (`--rm`)
and are not visible in Podman Desktop after they exit.

> **Note:** Automatic `.desktop` generation from profiles is planned but
> deferred (D4). Until then, copy and edit the examples above.

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
