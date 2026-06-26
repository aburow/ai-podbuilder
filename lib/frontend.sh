#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# 2026 - Anthony Burow - https://github.com/aburow
# Frontend rendering entry point. Sources lib/render.sh for the full
# implementation. Source this file; do not execute directly.

_FE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=render.sh
source "${_FE_DIR}/render.sh"
