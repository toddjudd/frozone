#!/usr/bin/env bash
# validate.sh — config sanity checks shared by backup/verify/restore.
#
# Scope is deliberately narrow: only mistakes that rclone would accept and act
# on. A bad bucket name or an unknown remote already fails loudly on the first
# call, so checking those here buys nothing. What's checked instead are the
# configs that produce a successful-looking run against the wrong target, or
# no target at all — the failures you'd only notice during a restore.
#
# Nothing here assumes AWS, so pointing a config at another rclone backend
# later doesn't require touching this file.

require_set() {
  local name="$1"
  local value="${!name:-}"
  if [[ -z "$value" ]]; then
    log "ERROR: ${name} is unset or empty — check your config file"
    return 1
  fi
  if [[ "$value" == op://* ]]; then
    log "ERROR: ${name} is still an unresolved 1Password reference (${value})."
    log "       Run via: op run --env-file=<config> -- <script> <config>"
    return 1
  fi
}

validate_remote_config() {
  require_set S3_REMOTE
  require_set S3_BUCKET
  require_set S3_PREFIX

  # Both "immich" and "immich/" are prefixes rclone accepts, but the unslashed
  # form also matches the sibling "immich_db" prefix backup.sh writes to.
  if [[ "$S3_PREFIX" != */ ]]; then
    log "ERROR: S3_PREFIX '${S3_PREFIX}' must end with a trailing slash"
    return 1
  fi
}

# Source directory: only meaningful for backup and verify.
validate_source_path() {
  require_set SOURCE_PATH

  if [[ ! -d "$SOURCE_PATH" ]]; then
    log "ERROR: SOURCE_PATH '${SOURCE_PATH}' is not a directory (unmounted disk?)"
    return 1
  fi

  # An unmounted volume looks like an empty directory, and copying it succeeds
  # while uploading nothing — a green run that silently backs up no data.
  if [[ -z "$(ls -A "$SOURCE_PATH" 2>/dev/null)" ]]; then
    log "ERROR: SOURCE_PATH '${SOURCE_PATH}' is empty — refusing to run"
    return 1
  fi
}

validate_notify_config() {
  require_set DISCORD_BOT_TOKEN
  require_set DISCORD_USER_ID
}
