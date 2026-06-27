---
title: 'PODMAN_BUILDER.md not emitted as self-contained authoritative durable contract'
type: defect
status: done
lineage: podman-builder-md-incomplete-durable-contract
created: "2026-06-27T00:00:00+10:00"
priority: normal
labels:
    - defect
---

# PODMAN_BUILDER.md not emitted as self-contained authoritative durable contract

## Summary

The scaffold generator emitted a `PODMAN_BUILDER.md` that deferred key sections to other files, contained incomplete array fragments, and was not suitable as a standalone technical contract. The file was manually rewritten in this run; the generator/template still needs a fix.

## Reproduction Steps

1. Run the bootstrap scaffold generator without post-generation review.
2. Inspect the initially emitted `PODMAN_BUILDER.md` before any correction.
3. Observe indirect references such as "Derived from …" and malformed sections under mounts/state.

## Expected Behaviour

The first-emitted `PODMAN_BUILDER.md` is complete, self-contained, and describes the durable runtime contract directly without references to other files.

## Actual Behaviour

Original file contained malformed array fragments and indirect references. The scaffold lacked a reliable technical handoff until `PODMAN_BUILDER.md` was rewritten out-of-band.

## Logs / Output

Source: `imported_defect_data/DEFECTS.md` D-006, kaos-control bootstrap run 2026-06-27.
Status: fixed in scaffold for this run; generator/template root cause unresolved.

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
