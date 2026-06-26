---
title: 'Release installer URL returned 404 because install.sh was not uploaded as a release asset'
type: defect
status: clarifying
lineage: release-installer-asset-missing
created: "2026-06-26T17:58:00+10:00"
priority: high
labels:
    - defect
    - release
    - installer
---

# Release installer URL returned 404 because install.sh was not uploaded as a release asset

## Summary

The published `0.51` release was marked as the latest GitHub Release, but it did
not include `install.sh` as a release asset. As a result, the documented install
command failed for users with HTTP 404:

```bash
curl -fsSL https://github.com/aburow/ai-podbuilder/releases/latest/download/install.sh | bash
```

The source tree contained `install.sh`, but GitHub only serves
`/releases/latest/download/<asset>` URLs for files explicitly uploaded as release
assets. A tag or source file alone is not enough.

## Reproduction Steps

1. Publish a GitHub Release for tag `0.51` without uploading `install.sh`.
2. Run:
   ```bash
   curl -fsSL https://github.com/aburow/ai-podbuilder/releases/latest/download/install.sh | bash
   ```
3. Observe:
   ```text
   curl: (22) The requested URL returned error: 404
   ```
4. Inspect the release assets:
   ```bash
   gh release view 0.51 --json assets
   ```
5. Observe that `assets` is empty.

## Expected Behaviour

- Every published release that is intended to be installable includes
  `install.sh` as a release asset.
- The latest installer URL returns HTTP 200 before the release process is
  considered complete.
- Release verification includes a public smoke check:
  ```bash
  curl -fsSL https://github.com/aburow/ai-podbuilder/releases/latest/download/install.sh | head
  ```

## Actual Behaviour

- Release `0.51` was created and marked latest with no assets.
- The expected installer URL returned 404.
- The issue was only found after trying the public install command manually.

## Root-Cause Analysis

The release process created the Git tag and GitHub Release object, but did not
include an explicit asset upload step:

```bash
gh release upload 0.51 install.sh --clobber
```

There was also no post-release smoke check for the public
`/releases/latest/download/install.sh` URL. The process verified tests, tag
creation, and release metadata, but not end-user installability.

## Improvement Actions

1. Add `install.sh` asset upload to the release checklist.
2. Verify release assets after publish:
   ```bash
   gh release view <version> --json assets
   ```
3. Verify the public latest installer URL returns HTTP 200:
   ```bash
   curl -I -L https://github.com/aburow/ai-podbuilder/releases/latest/download/install.sh
   ```
4. Add a release smoke test that fetches the installer and prints the first few
   lines without executing it.
5. Consider a scripted release command that performs tag creation, release
   creation, asset upload, and public URL verification as one repeatable flow.

## Resolution Applied

The missing asset was uploaded to release `0.51`:

```bash
gh release upload 0.51 install.sh --clobber
```

The public latest installer URL was then verified to return HTTP 200 and serve
the expected script content.

## Logs / Output

Initial failure:

```text
curl -fsSL https://github.com/aburow/ai-podbuilder/releases/latest/download/install.sh | bash
curl: (22) The requested URL returned error: 404
```

Release asset inspection before fix:

```json
{"assets":[],"name":"Release 0.51","tagName":"0.51"}
```

Release asset inspection after fix:

```json
{"assets":[{"name":"install.sh","state":"uploaded","size":7284}],"name":"Release 0.51","tagName":"0.51"}
```
