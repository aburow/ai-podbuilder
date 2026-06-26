#!/usr/bin/env bash
# Slug sanitizer for ai-new project names (R20.1, D2).
# Source this file; do not execute directly. Requires common.sh.

# _slug_collision_db: path to the slug collision index file.
# Located at $AI_PODMAN_JAILS_DIR/config/slug-index.tsv (name<TAB>slug).
_slug_db() {
    echo "${AI_PODMAN_JAILS_DIR}/config/slug-index.tsv"
}

# sanitize_slug <name>
# Outputs the deterministic slug for <name>.
# Rules (R20.1, D2):
#   - lowercase ASCII
#   - chars outside [a-z0-9._-] replaced with -
#   - collapse repeated -
#   - trim leading/trailing . _ -
#   - fail if empty after trimming
#   - cap at 63 chars; append -<8-char-hash> on truncation
#   - fail closed if two distinct names collide on the same slug
sanitize_slug() {
    local _name="$1"

    # Lowercase.
    local _slug="${_name,,}"

    # Replace disallowed chars with -.
    _slug="${_slug//[^a-z0-9._-]/-}"

    # Collapse repeated -.
    while [[ "$_slug" == *--* ]]; do
        _slug="${_slug//--/-}"
    done

    # Trim leading and trailing . _ -
    while [[ "$_slug" =~ ^[._-] ]]; do
        _slug="${_slug:1}"
    done
    while [[ "$_slug" =~ [._-]$ ]]; do
        _slug="${_slug:0:${#_slug}-1}"
    done

    [[ -n "$_slug" ]] || _die "Project name '${_name}' produces an empty slug after sanitization."

    # Cap at 63 chars with hash suffix on truncation.
    if [[ "${#_slug}" -gt 63 ]]; then
        local _hash8
        _hash8="$(printf '%s' "$_name" | sha256sum | cut -c1-8)"
        _slug="${_slug:0:54}-${_hash8}"
    fi

    # Collision detection: check slug-index.tsv
    local _db
    _db="$(_slug_db)"
    if [[ -f "$_db" ]]; then
        local _existing_name _existing_slug
        while IFS=$'\t' read -r _existing_name _existing_slug || [[ -n "$_existing_name" ]]; do
            if [[ "$_existing_slug" == "$_slug" && "$_existing_name" != "$_name" ]]; then
                _die "Slug collision: name '${_name}' → slug '${_slug}' already claimed by '${_existing_name}'.
  To resolve: choose a different project name."
            fi
        done < "$_db"
    fi

    echo "$_slug"
}

# register_slug <name> <slug>
# Records the name→slug mapping in the collision index.
register_slug() {
    local _name="$1"
    local _slug="$2"
    local _db
    _db="$(_slug_db)"
    mkdir -p "$(dirname "$_db")"
    # Only write if not already present.
    if [[ -f "$_db" ]]; then
        grep -qF "	${_slug}" "$_db" 2>/dev/null && return 0
    fi
    printf '%s\t%s\n' "$_name" "$_slug" >> "$_db"
}
