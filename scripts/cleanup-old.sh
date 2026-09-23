#!/usr/bin/env bash
# Jenkins stage: Old Version Cleanup
# Only called after switch-traffic.sh has verified the new color is live
# and serving correctly (Phase 3: "Only after successful validation may the
# previous version be removed").
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"

OLD_COLOR="${1:?usage: cleanup-old.sh <old_color>}"
OLD_CONTAINER="orders-${OLD_COLOR}"

if ! container_exists "$OLD_CONTAINER"; then
  log "'$OLD_CONTAINER' does not exist - nothing to clean up (likely first-ever deployment)"
  exit 0
fi

log "Stopping and removing previous production container '$OLD_CONTAINER'"
docker stop "$OLD_CONTAINER" >/dev/null || true
docker rm "$OLD_CONTAINER" >/dev/null || true
ok "removed '$OLD_CONTAINER'"
