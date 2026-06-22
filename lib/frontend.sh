#!/usr/bin/env bash
# Frontend rendering entry point. Sources lib/render.sh for the full
# implementation. Source this file; do not execute directly.

_FE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=render.sh
source "${_FE_DIR}/render.sh"
