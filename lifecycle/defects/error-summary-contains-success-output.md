---
title: 'Failure result stores successful build tail output in error_summary field'
type: defect
status: done
lineage: error-summary-contains-success-output
created: "2026-06-27T00:00:00+10:00"
priority: normal
labels:
    - defect
---

# Failure result stores successful build tail output in error_summary field

## Summary

The `error_summary` field in a failed result record contains successful build output (COMMIT, tag, digest lines) instead of diagnostic failure information. Repair logic, human debugging, and session narratives are all misled because the recorded error payload is not an error.

## Reproduction Steps

1. Run the quality-gate workflow until the host-side supervisor writes `build.result.4.json`.
2. Inspect `build.result.4.json` field `error_summary`.

## Expected Behaviour

`error_summary` contains the failure cause or is absent on success. A result with `status: "failed"` must not have an `error_summary` that is clearly a success log tail.

## Actual Behaviour

`build.result.4.json:10` contains `STEP 29/29`, `COMMIT`, `Successfully tagged`, and the final digest in the `error_summary` field.

## Logs / Output

Source: `imported_defect_data/DEFECTS.md` D-004, kaos-control bootstrap run 2026-06-27.
Evidence: `bootstrap/build.result.4.json:10` — error_summary value is successful build tail output.

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
