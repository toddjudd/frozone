#!/usr/bin/env bash
# backup.sh — sync a source directory to S3 Glacier Deep Archive.
#
# Usage:
#   op run --env-file=config/<name>.env -- ./backup.sh <name>
#
# Expects config/<name>.env to define:
#   SOURCE_PATH   - directory to back up
#   S3_REMOTE     - rclone remote name (e.g. "s3remote")
#   S3_BUCKET     - bucket name
#   S3_PREFIX     - key prefix within the bucket (e.g. "immich/")
#   DB_DUMP_PATH  - optional; a file/dir to copy alongside SOURCE_PATH before upload (leave unset to skip)
#
# That file holds both config values and op:// secret references, and is read
# by `op run --env-file=` rather than sourced here — sourcing it would
# overwrite the secrets op had just resolved with the literal op:// strings.
# The argument is only a label for logs and notifications.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/notify.sh"
source "${SCRIPT_DIR}/validate.sh"

INSTANCE="${1:?Usage: backup.sh <instance-name>}"

validate_remote_config
validate_source_path
validate_notify_config

LOG_DIR="${LOG_DIR:-/var/log/frozone}"
mkdir -p "$LOG_DIR"
LOGFILE="${LOG_DIR}/backup-$(date -u +'%Y%m%dT%H%M%SZ').log"

log "Starting backup of ${SOURCE_PATH} -> ${S3_REMOTE}:${S3_BUCKET}/${S3_PREFIX}"

RCLONE_ARGS=(
  copy "$SOURCE_PATH" "${S3_REMOTE}:${S3_BUCKET}/${S3_PREFIX}"
  --s3-storage-class DEEP_ARCHIVE
  --s3-chunk-size 64M
  --log-file "$LOGFILE"
  --log-level INFO
)

if rclone "${RCLONE_ARGS[@]}"; then
  # Optional: ship a DB dump (or any extra file/dir) alongside the library
  if [[ -n "${DB_DUMP_PATH:-}" && -e "$DB_DUMP_PATH" ]]; then
    log "Uploading DB dump from ${DB_DUMP_PATH}"
    rclone copy "$DB_DUMP_PATH" "${S3_REMOTE}:${S3_BUCKET}/${S3_PREFIX}_db/" \
      --s3-storage-class DEEP_ARCHIVE --log-file "$LOGFILE" --log-level INFO
  fi

  log "Backup completed successfully"
  discord_dm "✅ frozone (${INSTANCE}) completed: $(date -u +'%Y-%m-%d %H:%M UTC')" || true
  healthcheck_ping
  exit 0
else
  log "Backup FAILED — see ${LOGFILE}"
  discord_dm "❌ frozone (${INSTANCE}) FAILED — check ${LOGFILE} on the host" || true
  healthcheck_ping "/fail"
  exit 1
fi
