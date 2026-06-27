---
title: 'Repair budget exhausted by supervisor-side false negatives on successful builds'
type: defect
status: done
lineage: repair-budget-exhausted-by-supervisor-false-negatives
created: "2026-06-27T00:00:00+10:00"
priority: high
labels:
    - defect
---

# Repair budget exhausted by supervisor-side false negatives on successful builds

## Summary

Repair-attempt budget is consumed by contradictory supervisor-side failure classifications rather than real build failures. The workflow cannot distinguish `Containerfile` defects from control-plane defects and can strand a working image in a failed session.

## Reproduction Steps

1. Run the bootstrap prompt's repair loop in the presence of contradictory result files (image committed but result says failed).
2. Observe that each repair attempt counts against the three-attempt budget even when the image built successfully.
3. After three iterations the workflow terminates with budget exhausted and session failed.

## Expected Behaviour

Repair-attempt budget is consumed only by genuine build failures. Contradictory or supervisor-side outcomes (image committed and tagged, result says failed) do not count against the budget and trigger a supervisor-integrity branch instead.

## Actual Behaviour

- Request 3 produced an image but was treated as failed due to an OCI warning; counted against budget.
- Request 4 produced an image and was again treated as failed; consumed the final budget slot.
- Workflow terminated in `quality-gate-failed` with a working image in the registry.

## Logs / Output

Source: `imported_defect_data/DEFECTS.md` D-005, kaos-control bootstrap run 2026-06-27.
Evidence: `bootstrap/build.result.3.json` and `bootstrap/build.result.4.json` both record failure despite committed/tagged images; `bootstrap/session.md` records terminal failure after maximum repair iterations.

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
