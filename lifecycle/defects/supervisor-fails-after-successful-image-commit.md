---
title: 'Supervisor reports build failure after successful podman image commit and tag'
type: defect
status: done
lineage: supervisor-fails-after-successful-image-commit
created: "2026-06-27T00:00:00+10:00"
priority: high
labels:
    - defect
---

# Supervisor reports build failure after successful podman image commit and tag

## Summary

The host-side supervisor writes a result file recording `exit_code: 1` and `status: "failed"` even when the build log shows a successful image commit and tag. A valid image is treated as failed, the session is blocked from normal completion, and the user receives incorrect terminal guidance.

## Reproduction Steps

1. Run the quality-gate workflow for the kaos-control scaffold.
2. Allow the build to reach successful image commit and tag.
3. Inspect `bootstrap/build.result.4.json` — it records failure despite the build succeeding.

## Expected Behaviour

A successful `podman build` run that reaches image commit and tag produces a passed result: `exit_code: 0`, `status: "passed"`.

## Actual Behaviour

`bootstrap/build.result.4.json` records `exit_code: 1` and `status: "failed"` despite the build log showing:
- `COMMIT localhost/ai-new/kaos-control:trial` (line 1646)
- `Successfully tagged localhost/ai-new/kaos-control:trial` (line 1648)
- Final image digest (line 1649)

## Logs / Output

Source: `imported_defect_data/DEFECTS.md` D-003, kaos-control bootstrap run 2026-06-27.
Evidence: `bootstrap/build.log:1646-1649` (success), `bootstrap/build.result.4.json:5-10` (exit_code:1, status:failed).

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
