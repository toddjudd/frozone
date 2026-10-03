#!/usr/bin/env bash
# deploy.sh — copy this checkout to /opt/frozone, where the systemd units
# expect it, and refresh the installed unit files.
#
# Usage:
#   sudo ./scripts/deploy.sh
#
# Copies rather than symlinks the checkout: the units run as root, and a
# working tree your login user can write to would hand root execution to any
# process running as you.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${DEST:-/opt/frozone}"

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: must run as root. Try: sudo $0" >&2
  exit 1
fi

if [[ ! -d "${REPO_DIR}/systemd" ]]; then
  echo "ERROR: ${REPO_DIR} does not look like the frozone repo" >&2
  exit 1
fi

# --delete so files removed from the repo also leave the deployed copy.
rsync -a --delete --exclude .git --exclude .github "${REPO_DIR}/" "${DEST}/"

chown -R root:root "$DEST"
# The scripts run as root; group-write would let another account edit them.
chmod -R go-w "$DEST"

shopt -s nullglob
for env_file in "$DEST"/config/*.env; do
  chmod 640 "$env_file"
done
shopt -u nullglob

# systemd reads units from /etc/systemd/system, not from $DEST.
cp "$DEST"/systemd/frozone-*.service "$DEST"/systemd/frozone-*.timer /etc/systemd/system/
systemctl daemon-reload

echo "Deployed ${REPO_DIR} -> ${DEST}, units reinstalled, systemd reloaded."
echo "Enabled timers keep working; re-enabling is not needed."
