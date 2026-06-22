# Secrets and SSH

---

## Secrets via ENV_FILE (R7)

Set `ENV_FILE` in your profile to inject secrets (API keys, tokens, registry
credentials) into the container at launch time:

```bash
# In your profile .env file:
ENV_FILE="${CODEX_JAILS_DIR}/esp32-secrets.env"
```

The secrets file is passed to Podman via `--env-file`. **Required mode: `600`**
(readable only by the owner):

```bash
chmod 600 "$CODEX_JAILS_DIR/esp32-secrets.env"
```

**Never commit the secrets file to Git.** Add it to `.gitignore`:

```
*-secrets.env
*.secrets.env
```

If `ENV_FILE` is set but the file is not found at launch time, the framework
**warns and continues** — the container starts without the secrets rather than
failing hard. This allows the same profile to be used in environments where
the secrets file is not deployed (e.g. a CI build that injects secrets another
way).

---

## SSH strategy (R8)

The host `~/.ssh` directory is **never mounted** into any container by default.
This means:

- The host SSH identity (private keys, known_hosts, agent socket) is not
  accessible inside the container.
- A compromised container or runaway agent cannot exfiltrate host SSH credentials.

### Recommended: dedicated in-sandbox SSH key

Generate a dedicated `ed25519` key **inside the container** for scoped Git access:

```bash
# Inside the container (ai-launch <profile> or ai-terminal <profile>):
ssh-keygen -t ed25519 -C "ai-agent@$(hostname)" -f ~/.ssh/id_ed25519_agent
# (leave the passphrase empty for non-interactive agent use)
```

Add the **public key** (`~/.ssh/id_ed25519_agent.pub`) to the Git hosting
service (GitHub, GitLab, etc.) as a **deploy key** scoped to the specific
repository the agent works on. A deploy key grants read-only (or read-write)
access to one repository — not the full account.

Configure the in-container SSH client to use this key:

```bash
# ~/.ssh/config inside the container (lives in CONTAINER_HOME/.ssh/):
Host github.com
    IdentityFile ~/.ssh/id_ed25519_agent
    IdentitiesOnly yes
```

Because `CONTAINER_HOME` is a host directory bind-mounted into the container,
the key persists across container recreations.

### Why not mount the host ~/.ssh?

Mounting the host `~/.ssh` would give the container access to all host
identities, known_hosts, and potentially a forwarded agent socket. A scoped
deploy key limits the blast radius of a compromised agent to a single repository.
