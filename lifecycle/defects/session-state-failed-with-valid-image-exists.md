---
title: 'Terminal session state remains quality-gate-failed when a valid trial image exists'
type: defect
status: done
lineage: session-state-failed-with-valid-image-exists
created: "2026-06-27T00:00:00+10:00"
priority: normal
labels:
    - defect
---

# Terminal session state remains quality-gate-failed when a valid trial image exists

## Summary

The protocol has no distinct state for "artifact built but supervisor failed." When repair budget is exhausted due to contradictory results, `session.json` stays `quality-gate-failed` even though a valid trial image was built and tagged. Resumability, user instructions, and automation status all misrepresent the artifact reality.

## Reproduction Steps

1. Let the repair loop consume its budget under contradictory supervisor results (image committed, result says failed).
2. Inspect `bootstrap/session.json` — status is `quality-gate-failed`.
3. Inspect `bootstrap/session.json` field `trial_image_tag` — a valid tag is recorded.
4. Verify the image exists: `podman image inspect localhost/ai-new/kaos-control:trial` succeeds.

## Expected Behaviour

Protocol state reflects the durable artifact reality, or at minimum surfaces a distinct state such as `quality-gate-inconsistent` or `artifact-built-supervisor-failed` so the user and automation know the image was produced.

## Actual Behaviour

`bootstrap/session.json` reports `status: "quality-gate-failed"` while simultaneously recording `trial_image_tag: "localhost/ai-new/kaos-control:trial"`. The build log confirms the image exists (lines 1646-1649). The two truths are never reconciled.

## Logs / Output

Source: `imported_defect_data/DEFECTS.md` D-009, kaos-control bootstrap run 2026-06-27.
Evidence: `bootstrap/session.json` (status: quality-gate-failed, trial_image_tag present), `bootstrap/build.log:1646-1649` (image committed and tagged).

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
