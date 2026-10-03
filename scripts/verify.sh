#!/usr/bin/env bash
# verify.sh — cheap periodic sanity check that the remote archive still
# looks like the source, without touching (or paying to thaw) Deep Archive
# data. Run monthly/quarterly from a separate, lighter-weight timer.
#
# Usage: ./verify.sh config/<name>.env

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/notify.sh"

CONFIG_FILE="${1:?Usage: verify.sh <config-file>}"
source "$CONFIG_FILE"

: "${SOURCE_PATH:?SOURCE_PATH not set in config}"
: "${S3_REMOTE:?S3_REMOTE not set in config}"
: "${S3_BUCKET:?S3_BUCKET not set in config}"
: "${S3_PREFIX:?S3_PREFIX not set in config}"

REMOTE_PATH="${S3_REMOTE}:${S3_BUCKET}/${S3_PREFIX}"

log "Verifying ${SOURCE_PATH} against ${REMOTE_PATH} (size-only — Deep Archive objects aren't hash-readable without a restore)"

if rclone check "$SOURCE_PATH" "$REMOTE_PATH" --size-only --one-way; then
  log "Verify OK: remote matches local by size and file count"
  discord_dm "🔎 Verify OK: ${CONFIG_FILE##*/} matches remote archive" || true
  healthcheck_ping
  exit 0
else
  log "Verify MISMATCH — remote archive is missing files present locally"
  discord_dm "⚠️ Verify MISMATCH for ${CONFIG_FILE##*/} — remote archive is behind. Run backup.sh." || true
  healthcheck_ping "/fail"
  exit 1
fi
