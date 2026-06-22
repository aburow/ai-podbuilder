# SELinux Configuration

The framework supports two SELinux modes, selectable per profile via
`SELINUX_MODE`. Both options are explicit; neither is hidden.

---

## Default: `SELINUX_MODE=disable` (friction-free for dev workspaces)

When `SELINUX_MODE` is unset or set to `disable`, the container is launched with:

```
--security-opt label=disable
```

This disables SELinux label enforcement for the container process. It is the
**recommended default for mounted development workspaces on Bazzite** because:

- Dev workspaces contain many files with mixed labels (source trees cloned as
  a regular user, editor state, compiled artifacts). Enforcing labels on such
  directories requires recursive relabelling (`chcon -R`) which can take minutes
  on large trees and must be re-done after every `git checkout` that touches
  many files.
- `label=disable` preserves all other security controls (`no-new-privileges`,
  user namespace, network isolation, no host-home mount).

This is a deliberate trade-off, not an accidental omission.

---

## Strict: `SELINUX_MODE=enforce` (`:Z` relabelling on mounts)

Set `SELINUX_MODE=enforce` in your profile to omit `label=disable`. The
framework then relies on the `:Z` suffix already present on all bind mounts
(e.g. `-v WORKSPACE:/workspace:Z`) to have Podman relabel the mounted
directory for the container's SELinux context.

```bash
# In your profile .env file:
SELINUX_MODE=enforce
```

With this setting the container runs under its SELinux context without any
label override. The `:Z` mount flag handles relabelling. On a large workspace
the initial relabel may take several seconds.

---

## Comparison

| Setting | `label=disable` flag | `:Z` relabelling | Best for |
|---------|---------------------|-----------------|---------|
| `disable` (default) | Yes — label not enforced | Still applied | Large dev workspaces, Bazzite |
| `enforce` | No | Still applied | Stricter SELinux policy enforcement |

Both modes retain all other safety controls. The choice affects only SELinux
label enforcement, not user namespace, networking, or privilege controls.
