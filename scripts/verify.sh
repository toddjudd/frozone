#!/usr/bin/env bash
# verify.sh — cheap periodic sanity check that the remote archive still
# looks like the source, without touching (or paying to thaw) Deep Archive
# data. Run monthly/quarterly from a separate, lighter-weight timer.
#
# Usage: op run --env-file=config/<name>.env -- ./verify.sh <name>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/notify.sh"
source "${SCRIPT_DIR}/validate.sh"

# Config comes from the environment via `op run`; this is only a label.
INSTANCE="${1:?Usage: verify.sh <instance-name>}"

validate_remote_config
validate_source_path
validate_notify_config

REMOTE_PATH="${S3_REMOTE}:${S3_BUCKET}/${S3_PREFIX}"

log "Verifying ${SOURCE_PATH} against ${REMOTE_PATH} (size-only — Deep Archive objects aren't hash-readable without a restore)"

if rclone check "$SOURCE_PATH" "$REMOTE_PATH" --size-only --one-way; then
  log "Verify OK: remote matches local by size and file count"
  discord_dm "🔎 Verify OK: ${INSTANCE} matches remote archive" || true
  healthcheck_ping
  exit 0
else
  log "Verify MISMATCH — remote archive is missing files present locally"
  discord_dm "⚠️ Verify MISMATCH for ${INSTANCE} — remote archive is behind. Run backup.sh." || true
  healthcheck_ping "/fail"
  exit 1
fi
