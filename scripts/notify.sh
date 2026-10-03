#!/usr/bin/env bash
# notify.sh — shared notification helpers. Source this from other scripts.
# Requires: curl, jq
# Requires env vars: DISCORD_BOT_TOKEN, DISCORD_USER_ID
# Optional env var: HEALTHCHECK_URL (dead-man's-switch ping, e.g. healthchecks.io)

discord_dm() {
  local message="$1"
  local channel_id

  channel_id="$(curl -sS -X POST "https://discord.com/api/v10/users/@me/channels" \
    -H "Authorization: Bot ${DISCORD_BOT_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"recipient_id\": \"${DISCORD_USER_ID}\"}" | jq -r '.id')"

  if [[ -z "$channel_id" || "$channel_id" == "null" ]]; then
    log "ERROR: failed to open Discord DM channel"
    return 1
  fi

  curl -sS -X POST "https://discord.com/api/v10/channels/${channel_id}/messages" \
    -H "Authorization: Bot ${DISCORD_BOT_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg content "$message" '{content: $content}')" > /dev/null
}

healthcheck_ping() {
  # Usage: healthcheck_ping            -> success ping
  #        healthcheck_ping "/fail"    -> failure ping
  local suffix="${1:-}"
  if [[ -n "${HEALTHCHECK_URL:-}" ]]; then
    curl -fsS -m 10 --retry 3 "${HEALTHCHECK_URL}${suffix}" >/dev/null || true
  fi
}

log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*"
}
