#!/usr/bin/env bash
# restore.sh — thaw and download a Deep Archive backup.
#
# This is a two-step, two-day process by design — Deep Archive is slow to
# retrieve on purpose. Run this script once to request the thaw, wait
# (~12h standard / ~48h bulk), then run it again with --download to pull
# the thawed copy down.
#
# Usage:
#   ./restore.sh config/<name>.env --request [--priority Standard|Bulk]
#   ./restore.sh config/<name>.env --download <local-dest-dir>
#   ./restore.sh config/<name>.env --status

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/notify.sh"

CONFIG_FILE="${1:?Usage: restore.sh <config-file> --request|--download|--status}"
ACTION="${2:?Specify --request, --download, or --status}"
source "$CONFIG_FILE"

: "${S3_REMOTE:?S3_REMOTE not set in config}"
: "${S3_BUCKET:?S3_BUCKET not set in config}"
: "${S3_PREFIX:?S3_PREFIX not set in config}"

REMOTE_PATH="${S3_REMOTE}:${S3_BUCKET}/${S3_PREFIX}"

case "$ACTION" in
  --request)
    PRIORITY="Bulk"
    if [[ "${3:-}" == "--priority" ]]; then PRIORITY="${4:?}"; fi
    echo "This will mark EVERYTHING under ${REMOTE_PATH} for restore."
    read -r -p "Type 'yes' to continue: " CONFIRM
    [[ "$CONFIRM" == "yes" ]] || { echo "Aborted."; exit 1; }
    log "Requesting restore (priority=${PRIORITY}, lifetime=7 days)"
    rclone backend restore "$REMOTE_PATH" -o priority="$PRIORITY" -o lifetime=7
    discord_dm "🧊 Restore requested for ${REMOTE_PATH} (priority=${PRIORITY}). Standard ~12h, Bulk ~48h." || true
    ;;
  --status)
    rclone backend restore-status "$REMOTE_PATH"
    ;;
  --download)
    DEST="${3:?Usage: restore.sh <config-file> --download <local-dest-dir>}"
    mkdir -p "$DEST"
    log "Downloading ${REMOTE_PATH} -> ${DEST}"
    rclone copy "$REMOTE_PATH" "$DEST" --progress
    log "Download complete. Verify against your asset count before trusting it."
    discord_dm "✅ Restore download complete: ${REMOTE_PATH} -> ${DEST}" || true
    ;;
  *)
    echo "Unknown action: $ACTION"
    exit 1
    ;;
esac
