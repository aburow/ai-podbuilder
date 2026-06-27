---
title: 'static_check_status is always "skipped" in all quality-gate result files'
type: defect
status: done
lineage: static-check-status-always-skipped
created: "2026-06-27T00:00:00+10:00"
priority: normal
labels:
    - defect
---

# static_check_status is always "skipped" in all quality-gate result files

## Summary

Every result file emitted during the bootstrap quality gate reports `static_check_status: "skipped"`. The quality gate advertises less certainty than users may infer from the schema, and a potentially dead validation stage is hidden behind a neutral status.

## Reproduction Steps

1. Run any bootstrap workflow and inspect all emitted `build.result.*.json` files.
2. Check the `static_check_status` field in each file.

## Expected Behaviour

Either static checks run and report their outcome, or the protocol documents why they are skipped, or the field is removed until it carries real signal.

## Actual Behaviour

All four result files from the kaos-control run (`build.result.1.json` through `build.result.4.json`) report `static_check_status: "skipped"` with no explanation.

## Logs / Output

Source: `imported_defect_data/DEFECTS.md` D-007, kaos-control bootstrap run 2026-06-27.
Evidence: `bootstrap/build.result.1.json`, `build.result.2.json`, `build.result.3.json`, `build.result.4.json` — all report `static_check_status: "skipped"`.

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
