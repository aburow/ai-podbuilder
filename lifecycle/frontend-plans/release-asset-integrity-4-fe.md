---
title: Publish and verify a SHA-256 checksum for the install.sh release asset — Frontend Plan
type: plan-frontend
status: draft
lineage: release-asset-integrity
parent: lifecycle/requirements/release-asset-integrity-2.md
created: "2026-06-26T00:00:00+10:00"
priority: medium
assignees:
    - role: frontend-developer
      who: agent
---

# Publish and verify a SHA-256 checksum for the install.sh release asset — Frontend Plan

This project's only user-facing surface is the `README.md` install docs. R7 is
the sole frontend requirement: document a verify-before-run one-liner using the
new `install.sh.sha256` asset. One milestone, one file.

## Milestone 1 — Add a verified install variant to the README (R7)

**Description.** In the `## Install` section of `README.md`, keep the existing
quick one-liner (line 29) as the default path and add a **Verify before running**
variant immediately after it, using the published `.sha256` asset:

```sh
curl -fsSL https://github.com/aburow/ai-podbuilder/releases/latest/download/install.sh -o install.sh
curl -fsSL https://github.com/aburow/ai-podbuilder/releases/latest/download/install.sh.sha256 | sha256sum -c -
# if it prints "install.sh: OK", then run it:
bash install.sh
```

Notes for the writer:
- The piped `sha256sum -c -` works only because the published checksum records
  the bare filename `install.sh` and the `-o install.sh` download uses that same
  name in the cwd — keep both names as `install.sh`. Call this out in one short
  sentence so a user who renames the download understands why a rename breaks it.
- Use the exact repo URL already in the README (`aburow/ai-podbuilder`); do not
  change the install URL, repo name, or the existing one-liner (Non-goals).
- Keep prose minimal — one short paragraph framing "quick vs. verified".

**Files to change.** `README.md` — `## Install` section.

**Acceptance criteria.**
- The `## Install` section shows both the existing quick one-liner and a verified
  variant that downloads `install.sh` + `install.sh.sha256` and runs
  `sha256sum -c -` before execution (AC6, R7).
- Copy-pasting the verified block against a real release prints `install.sh: OK`
  and only then runs the script.
- The original quick one-liner and the install URL/repo name are unchanged.
