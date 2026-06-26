# Releasing

## Canonical flow

1. Bump `VERSION` (single source of truth — the tag must match exactly).
2. Commit and push to `main`.
3. Push the matching tag:
   ```sh
   git tag -a <version> -m "Release <version>"
   git push origin refs/tags/<version>
   ```
4. The GitHub Actions workflow (`.github/workflows/release.yml`) runs
   `devops/release.sh`, which performs the steps below in order.

---

## Steps performed by `devops/release.sh`

### 1. Create tag (if not already present)

The script creates an annotated tag at HEAD and pushes it. If the tag already
exists at HEAD the step is skipped (idempotent).

### 2. Create GitHub release

```sh
gh release create <version> --repo aburow/ai-podbuilder \
  --title "Release <version>" --notes "Release <version>"
```

Idempotent — skipped if the release already exists.

### 3. Upload asset

```sh
gh release upload <version> install.sh --repo aburow/ai-podbuilder --clobber
```

The `--clobber` flag replaces an existing asset with the same name.

### 4. Verify asset (R2)

```sh
gh release view <version> --repo aburow/ai-podbuilder --json assets
```

A "good" result has an entry for `install.sh` with:

- `"name": "install.sh"`
- `"state": "uploaded"`
- `"size"` > 0

### 5. Verify public URL returns HTTP 200 (R3)

```sh
curl -I -L https://github.com/aburow/ai-podbuilder/releases/latest/download/install.sh
```

Expect `HTTP/2 200` (or `HTTP/1.1 200`). Any non-200 means the asset is not
publicly reachable.

### 6. Verify content (R4)

```sh
curl -fsSL https://github.com/aburow/ai-podbuilder/releases/latest/download/install.sh | head
```

Eyeball the first few lines; **never pipe into `bash` during verification**.
The script checks that the first line is `#!/usr/bin/env bash` and that the
known marker `REPO="aburow/ai-podbuilder"` is present.

---

## Fail-closed rule (R6)

> **A release is NOT done until the asset-verify (step 4) and public-URL-verify
> (step 5) checks both pass.**

If either check fails the script exits non-zero and the release workflow
fails. Do not mark a release complete based solely on the tag or GitHub
release object — the downloadable asset must exist and be reachable.

---

## Running steps by hand

If `devops/release.sh` is unavailable, run each step manually in order:

```sh
# 1. Upload
gh release upload <version> install.sh --repo aburow/ai-podbuilder --clobber

# 2. Verify asset
gh release view <version> --repo aburow/ai-podbuilder --json assets
# Look for: name=install.sh, state=uploaded, size > 0

# 3. Verify public URL
curl -I -L https://github.com/aburow/ai-podbuilder/releases/latest/download/install.sh
# Expect: HTTP 200

# 4. Eyeball content (do NOT pipe into bash)
curl -fsSL https://github.com/aburow/ai-podbuilder/releases/latest/download/install.sh | head
```

---

## Offline / skip-network mode (Q3)

Set `RELEASE_SKIP_NETWORK=1` to skip the public-URL and content checks (steps
5–6). The script will print a clear warning that the release was **not fully
verified**. Do not use this mode for production releases.
