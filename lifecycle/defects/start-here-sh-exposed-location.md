---
title: start-here.sh exposed in user-accessible host location
type: defect
status: done
lineage: start-here-sh-exposed-location
created: "2026-06-26T19:15:45+10:00"
priority: normal
labels:
    - defect
    - installer
---

# start-here.sh exposed in user-accessible host location

## Summary

`start-here.sh` is currently placed in a location on the host that is visible and accessible to end users. The script is an internal resource intended solely for the container builder instance, not for direct host-side use. Its current placement risks user tampering and causes confusion about its purpose.

## Reproduction Steps

1. Inspect the installed file layout on the host after a normal install.
2. Observe that `start-here.sh` resides in a user-facing or user-writable directory.

## Expected Behaviour

`start-here.sh` should reside in an internal, non-user-facing location (e.g. inside the container image, a protected system directory, or a path conventionally reserved for tooling internals) where it is not discoverable or modifiable by host users.

## Actual Behaviour

The script is placed in a host-accessible location, exposing it to accidental modification, deletion, or misuse by users who may not understand its role in the container builder lifecycle.

## Logs / Output

Not provided

SPDX-License-Identifier: GPL-3.0-only
2026 - Anthony Burow - https://github.com/aburow
